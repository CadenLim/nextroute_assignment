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
      const { data, error } = await admin
        .from("daily_commutes")
        .select("*")
        .eq("user_id", user.id)
        .order("updated_at", { ascending: false });
      if (error) throw error;
      return json({ data: data ?? [] });
    }

    if (action === "upsert") {
      const input = body.commute;
      if (!input || typeof input !== "object") throw new HttpError(400, "Commute is required.");
      const commute = input as Record<string, unknown>;
      const savedRouteId = commute.saved_route_id;
      if (savedRouteId != null) {
        const { data: route, error: routeError } = await admin
          .from("saved_routes")
          .select("id")
          .eq("id", savedRouteId)
          .eq("user_id", user.id)
          .maybeSingle();
        if (routeError) throw routeError;
        if (!route) throw new HttpError(400, "Favourite route not found.");
      }
      const values = {
        user_id: user.id,
        saved_route_id: savedRouteId ?? null,
        origin: requiredString(commute.origin, "origin"),
        destination: requiredString(commute.destination, "destination"),
        arrive_by: requiredString(commute.arrive_by, "arrive_by"),
        active_days: commute.active_days,
        reminder_enabled: commute.reminder_enabled,
        reminder_minutes_before: commute.reminder_minutes_before,
        estimated_duration_minutes: commute.estimated_duration_minutes,
        updated_at: new Date().toISOString(),
      };

      const id = commute.id;
      const normalizeDays = (value: unknown): number[] =>
        Array.isArray(value)
          ? value.map(Number).filter(Number.isInteger).sort((a, b) => a - b)
          : [];
      const requestedDays = normalizeDays(values.active_days);
      const { data: existing, error: existingError } = await admin
        .from("daily_commutes")
        .select("id,saved_route_id,origin,destination,arrive_by,active_days,reminder_enabled,reminder_minutes_before")
        .eq("user_id", user.id);
      if (existingError) throw existingError;
      const duplicate = (existing ?? []).some((item) => {
        if (typeof id === "string" && item.id === id) return false;
        const itemDays = normalizeDays(item.active_days);
        return item.saved_route_id === values.saved_route_id &&
          item.origin.trim().toLowerCase() === values.origin.toLowerCase() &&
          item.destination.trim().toLowerCase() === values.destination.toLowerCase() &&
          item.arrive_by.slice(0, 5) === values.arrive_by.slice(0, 5) &&
          JSON.stringify(itemDays) === JSON.stringify(requestedDays) &&
          item.reminder_enabled === values.reminder_enabled &&
          item.reminder_minutes_before === values.reminder_minutes_before;
      });
      if (duplicate) {
        throw new HttpError(409, "An identical Daily Commute already exists.");
      }

      if (typeof id === "string" && id.length > 0) {
        const { data, error } = await admin
          .from("daily_commutes")
          .update(values)
          .eq("id", id)
          .eq("user_id", user.id)
          .select("*")
          .maybeSingle();
        if (error) throw error;
        if (!data) throw new HttpError(404, "Daily commute not found.");
        return json({ data });
      }

      const { data, error } = await admin
        .from("daily_commutes")
        .insert(values)
        .select("*")
        .single();
      if (error) throw error;
      return json({ data });
    }

    if (action === "delete") {
      const id = requiredString(body.id, "id");
      const { data, error } = await admin
        .from("daily_commutes")
        .delete()
        .eq("id", id)
        .eq("user_id", user.id)
        .select("id")
        .maybeSingle();
      if (error) throw error;
      if (!data) throw new HttpError(404, "Daily commute not found.");
      return json({ deleted: true });
    }

    throw new HttpError(400, "Unknown action.");
  } catch (error) {
    return errorResponse(error);
  }
});
