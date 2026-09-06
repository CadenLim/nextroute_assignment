import { createClient } from "npm:@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};
class HttpError extends Error { constructor(public status: number, message: string) { super(message); } }
function json(body: Record<string, unknown>, status = 200): Response { return Response.json(body, { status, headers: corsHeaders }); }
async function authenticatedContext(request: Request) {
  const token = request.headers.get("Authorization")?.replace(/^Bearer\s+/i, "").trim();
  if (!token) throw new HttpError(401, "Please sign in again.");
  const url = Deno.env.get("SUPABASE_URL");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !anonKey || !serviceKey) throw new HttpError(500, "Server data access is not configured.");
  const authClient = createClient(url, anonKey, { global: { headers: { Authorization: `Bearer ${token}` } }, auth: { persistSession: false } });
  const { data, error } = await authClient.auth.getUser(token);
  if (error || !data.user) throw new HttpError(401, "Your session has expired. Please sign in again.");
  return { user: data.user, admin: createClient(url, serviceKey, { auth: { persistSession: false } }) };
}
async function requestBody(request: Request): Promise<Record<string, unknown>> {
  try { return await request.json(); } catch (_) { throw new HttpError(400, "Invalid request."); }
}
function errorResponse(error: unknown): Response {
  if (error instanceof HttpError) return json({ error: error.message }, error.status);
  console.error(error); return json({ error: "Unable to complete the request." }, 500);
}
function requirePost(request: Request): Response | null {
  if (request.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  return request.method === "POST" ? null : json({ error: "Method not allowed." }, 405);
}
function requiredString(value: unknown, field: string): string {
  if (typeof value !== "string" || value.trim().length === 0) throw new HttpError(400, `${field} is required.`);
  return value.trim();
}

Deno.serve(async (request) => {
  const early = requirePost(request);
  if (early) return early;
  try {
    const body = await requestBody(request);
    const action = requiredString(body.action, "action");
    const { user, admin } = await authenticatedContext(request);

    if (action === "list") {
      const requestedLimit = typeof body.limit === "number" ? body.limit : 100;
      const limit = Math.max(1, Math.min(200, Math.trunc(requestedLimit)));
      let query = admin
        .from("navigation_history")
        .select("*")
        .eq("user_id", user.id)
        .order("created_at", { ascending: false })
        .limit(limit);
      if (body.completed_only === true) query = query.eq("status", "completed");
      const { data, error } = await query;
      if (error) throw error;
      return json({ data: data ?? [] });
    }

    if (action === "insert") {
      const input = body.journey;
      if (!input || typeof input !== "object") throw new HttpError(400, "Journey is required.");
      const journey = input as Record<string, unknown>;
      const row = {
        user_id: user.id,
        origin: requiredString(journey.origin, "origin"),
        destination: requiredString(journey.destination, "destination"),
        fare: journey.fare,
        currency: journey.currency ?? "MYR",
        duration_minutes: journey.duration_minutes,
        departure_time: journey.departure_time,
        estimated_arrival_time: journey.estimated_arrival_time,
        transit_steps: journey.transit_steps ?? [],
        status: journey.status ?? "completed",
      };
      const { data, error } = await admin
        .from("navigation_history")
        .insert(row)
        .select("*")
        .single();
      if (error) throw error;
      return json({ data });
    }

    if (action === "clear") {
      const { error } = await admin
        .from("navigation_history")
        .delete()
        .eq("user_id", user.id);
      if (error) throw error;
      return json({ deleted: true });
    }

    throw new HttpError(400, "Unknown action.");
  } catch (error) {
    return errorResponse(error);
  }
});
