import { createClient } from "npm:@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

class HttpError extends Error {
  constructor(public status: number, message: string) { super(message); }
}

function json(body: Record<string, unknown>, status = 200): Response {
  return Response.json(body, { status, headers: corsHeaders });
}

async function authenticatedContext(request: Request) {
  const token = request.headers.get("Authorization")?.replace(/^Bearer\s+/i, "").trim();
  if (!token) throw new HttpError(401, "Please sign in again.");
  const url = Deno.env.get("SUPABASE_URL");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !anonKey || !serviceKey) throw new HttpError(500, "Server data access is not configured.");
  const authClient = createClient(url, anonKey, {
    global: { headers: { Authorization: `Bearer ${token}` } },
    auth: { persistSession: false },
  });
  const { data, error } = await authClient.auth.getUser(token);
  if (error || !data.user) throw new HttpError(401, "Your session has expired. Please sign in again.");
  return {
    user: data.user,
    admin: createClient(url, serviceKey, { auth: { persistSession: false } }),
  };
}

async function requestBody(request: Request): Promise<Record<string, unknown>> {
  try { return await request.json(); } catch (_) { throw new HttpError(400, "Invalid request."); }
}

function errorResponse(error: unknown): Response {
  if (error instanceof HttpError) return json({ error: error.message }, error.status);
  console.error(error);
  return json({ error: "Unable to complete the request." }, 500);
}

function requirePost(request: Request): Response | null {
  if (request.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  return request.method === "POST" ? null : json({ error: "Method not allowed." }, 405);
}

function requiredString(value: unknown, field: string): string {
  if (typeof value !== "string" || value.trim().length === 0) throw new HttpError(400, `${field} is required.`);
  return value.trim();
}

const placeTypes = new Set(["home", "university", "work"]);

Deno.serve(async (request) => {
  const early = requirePost(request);
  if (early) return early;

  try {
    const body = await requestBody(request);
    const action = requiredString(body.action, "action");
    const { user, admin } = await authenticatedContext(request);

    if (action === "get-profile") {
      let { data, error } = await admin
        .from("profiles")
        .select("display_name, phone_number, avatar_path")
        .eq("id", user.id)
        .maybeSingle();
      if (error?.code === "42703") {
        const fallback = await admin
          .from("profiles")
          .select("display_name, phone_number")
          .eq("id", user.id)
          .maybeSingle();
        data = fallback.data as typeof data;
        error = fallback.error;
      }
      if (error) throw error;
      const profile: Record<string, unknown> = data ?? {};
      const avatarPath = data?.avatar_path;
      if (typeof avatarPath === "string" && avatarPath.length > 0) {
        const { data: signed, error: signedError } = await admin.storage
          .from("avatars")
          .createSignedUrl(avatarPath, 3600);
        if (signedError) throw signedError;
        profile.avatar_url = `${signed.signedUrl}&v=${Date.now()}`;
      }
      return json({ data: profile });
    }

    if (action === "update-profile") {
      const changes: Record<string, unknown> = { updated_at: new Date().toISOString() };
      if (body.display_name !== undefined) {
        const name = requiredString(body.display_name, "display_name");
        if (name.length > 100) throw new HttpError(400, "Display name is too long.");
        changes.display_name = name;
      }
      if (body.phone_number !== undefined) {
        if (typeof body.phone_number !== "string") {
          throw new HttpError(400, "Invalid phone number.");
        }
        changes.phone_number = body.phone_number.trim();
      }
      if (Object.keys(changes).length === 1) return json({ data: {} });
      const { data, error } = await admin
        .from("profiles")
        .update(changes)
        .eq("id", user.id)
        .select("display_name, phone_number")
        .single();
      if (error) throw error;
      return json({ data });
    }

    if (action === "list-saved-routes") {
      const { data, error } = await admin
        .from("saved_routes")
        .select("*")
        .eq("user_id", user.id)
        .order("created_at", { ascending: false });
      if (error) throw error;
      return json({ data: data ?? [] });
    }

    if (action === "count-saved-routes") {
      const { count, error } = await admin
        .from("saved_routes")
        .select("*", { count: "exact", head: true })
        .eq("user_id", user.id);
      if (error) throw error;
      return json({ count: count ?? 0 });
    }

    if (action === "upsert-saved-route") {
      const input = body.route;
      if (!input || typeof input !== "object") throw new HttpError(400, "Route is required.");
      const route = input as Record<string, unknown>;
      const row = {
        user_id: user.id,
        name: requiredString(route.name, "name"),
        route_key: requiredString(route.route_key, "route_key"),
        origin: route.origin,
        destination: route.destination,
        route_signature: requiredString(route.route_signature, "route_signature"),
        line_name: requiredString(route.line_name, "line_name"),
      };
      const { error } = await admin.from("saved_routes").upsert(row, {
        onConflict: "user_id,route_key",
        ignoreDuplicates: true,
      });
      if (error) throw error;
      return json({ saved: true });
    }

    if (action === "rename-saved-route") {
      const id = requiredString(body.id, "id");
      const name = requiredString(body.name, "name");
      if (name.length > 80) throw new HttpError(400, "Route name is too long.");
      const { data, error } = await admin
        .from("saved_routes")
        .update({ name })
        .eq("id", id)
        .eq("user_id", user.id)
        .select("id")
        .maybeSingle();
      if (error) throw error;
      if (!data) throw new HttpError(404, "Saved route not found.");
      return json({ updated: true });
    }

    if (action === "delete-saved-route") {
      const id = requiredString(body.id, "id");
      const { data, error } = await admin
        .from("saved_routes")
        .delete()
        .eq("id", id)
        .eq("user_id", user.id)
        .select("id")
        .maybeSingle();
      if (error) throw error;
      if (!data) throw new HttpError(404, "Saved route not found.");
      return json({ deleted: true });
    }

    if (action === "list-saved-places") {
      const { data, error } = await admin
        .from("saved_places")
        .select("*")
        .eq("user_id", user.id)
        .order("place_type");
      if (error) throw error;
      return json({ data: data ?? [] });
    }

    if (action === "upsert-saved-place") {
      const input = body.place;
      if (!input || typeof input !== "object") throw new HttpError(400, "Place is required.");
      const place = input as Record<string, unknown>;
      const placeType = requiredString(place.place_type, "place_type");
      if (!placeTypes.has(placeType)) throw new HttpError(400, "Invalid place type.");
      const row = {
        user_id: user.id,
        place_type: placeType,
        station_id: requiredString(place.station_id, "station_id"),
        station_ids: place.station_ids,
        station_name: requiredString(place.station_name, "station_name"),
        lines: place.lines ?? [],
        category: place.category ?? "Transit",
        latitude: place.latitude,
        longitude: place.longitude,
        updated_at: new Date().toISOString(),
      };
      const { data, error } = await admin
        .from("saved_places")
        .upsert(row, { onConflict: "user_id,place_type" })
        .select("*")
        .single();
      if (error) throw error;
      return json({ data });
    }

    if (action === "delete-saved-place") {
      const placeType = requiredString(body.place_type, "place_type");
      if (!placeTypes.has(placeType)) throw new HttpError(400, "Invalid place type.");
      const { error } = await admin
        .from("saved_places")
        .delete()
        .eq("user_id", user.id)
        .eq("place_type", placeType);
      if (error) throw error;
      return json({ deleted: true });
    }

    throw new HttpError(400, "Unknown action.");
  } catch (error) {
    return errorResponse(error);
  }
});
