import { createClient } from "npm:@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

function json(body: Record<string, unknown>, status: number): Response {
  return Response.json(body, { status, headers: corsHeaders });
}

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (request.method !== "POST") {
    return json({ error: "Method not allowed." }, 405);
  }

  const authorization = request.headers.get("Authorization");
  const token = authorization?.replace(/^Bearer\s+/i, "").trim();
  if (!token) return json({ error: "Please sign in again." }, 401);

  let body: { confirmation?: string };
  try {
    body = await request.json();
  } catch (_) {
    return json({ error: "Invalid request." }, 400);
  }
  if (body.confirmation !== "DELETE") {
    return json({ error: "Type DELETE to confirm account deletion." }, 400);
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseUrl || !anonKey || !serviceRoleKey) {
    return json({ error: "Account deletion is not configured." }, 500);
  }

  const userClient = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: `Bearer ${token}` } },
    auth: { persistSession: false },
  });
  const { data: userData, error: userError } = await userClient.auth.getUser(
    token,
  );
  if (userError || !userData.user) {
    return json({ error: "Your session has expired. Please sign in again." }, 401);
  }

  const admin = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false },
  });
  const userId = userData.user.id;
  const avatarPath = `${userId}/avatar`;
  let avatarBackup: Blob | null = null;

  try {
    // Keep a temporary copy so the avatar can be restored if the database
    // transaction fails after Storage has accepted the deletion.
    const { data: downloadedAvatar } = await admin.storage
      .from("avatars")
      .download(avatarPath);
    avatarBackup = downloadedAvatar;

    const { error: avatarError } = await admin.storage
      .from("avatars")
      .remove([avatarPath]);
    if (avatarError) throw avatarError;

    // This service-role-only RPC deletes all database rows and auth.users in
    // one PostgreSQL transaction, so a database failure rolls everything back.
    const { error: deletionError } = await admin.rpc(
      "delete_personal_account",
      { target_user_id: userId },
    );
    if (deletionError) throw deletionError;

    return json({ deleted: true }, 200);
  } catch (error) {
    console.error("Account deletion failed", error);
    if (avatarBackup) {
      const { error: restoreError } = await admin.storage
        .from("avatars")
        .upload(avatarPath, avatarBackup, {
          upsert: true,
          contentType: avatarBackup.type || "image/jpeg",
        });
      if (restoreError) console.error("Avatar restore failed", restoreError);
    }
    return json(
      { error: "Account deletion failed. Your account is still available." },
      500,
    );
  }
});
