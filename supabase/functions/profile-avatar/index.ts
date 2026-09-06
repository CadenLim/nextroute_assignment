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

const allowedTypes = new Set(["image/jpeg", "image/png", "image/webp"]);
const maximumBytes = 5 * 1024 * 1024;

Deno.serve(async (request) => {
  const early = requirePost(request);
  if (early) return early;
  try {
    const body = await requestBody(request);
    const action = requiredString(body.action, "action");
    const { user, admin } = await authenticatedContext(request);
    const path = `${user.id}/avatar`;

    if (action === "upload") {
      const contentType = requiredString(body.content_type, "content_type");
      if (!allowedTypes.has(contentType)) throw new HttpError(400, "Use a JPEG, PNG, or WebP photo.");
      const encoded = requiredString(body.data_base64, "data_base64");
      let bytes: Uint8Array;
      try {
        bytes = Uint8Array.from(atob(encoded), (char) => char.charCodeAt(0));
      } catch (_) {
        throw new HttpError(400, "Invalid photo data.");
      }
      if (bytes.byteLength > maximumBytes) throw new HttpError(400, "Photo must be 5 MB or smaller.");

      const { error: uploadError } = await admin.storage
        .from("avatars")
        .upload(path, bytes, { upsert: true, contentType });
      if (uploadError) throw uploadError;
      const { error: profileError } = await admin
        .from("profiles")
        .update({ avatar_path: path, updated_at: new Date().toISOString() })
        .eq("id", user.id);
      if (profileError) throw profileError;
      const { data: signed, error: signedError } = await admin.storage
        .from("avatars")
        .createSignedUrl(path, 3600);
      if (signedError) throw signedError;
      return json({ avatar_url: `${signed.signedUrl}&v=${Date.now()}` });
    }

    if (action === "delete") {
      const { error: storageError } = await admin.storage.from("avatars").remove([path]);
      if (storageError) throw storageError;
      const { error: profileError } = await admin
        .from("profiles")
        .update({ avatar_path: null, updated_at: new Date().toISOString() })
        .eq("id", user.id);
      if (profileError) throw profileError;
      return json({ deleted: true });
    }

    throw new HttpError(400, "Unknown action.");
  } catch (error) {
    return errorResponse(error);
  }
});
