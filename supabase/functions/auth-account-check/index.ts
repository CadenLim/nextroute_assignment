import { createClient } from "npm:@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

function json(body: Record<string, unknown>, status = 200): Response {
  return Response.json(body, { status, headers: corsHeaders });
}

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (request.method !== "POST") {
    return json({ error: "Method not allowed." }, 405);
  }

  let body: { email?: unknown; password?: unknown };
  try {
    body = await request.json();
  } catch (_) {
    return json({ error: "Invalid request." }, 400);
  }

  const email = typeof body.email === "string"
    ? body.email.trim().toLowerCase()
    : "";
  const password = typeof body.password === "string" ? body.password : "";
  if (
    email.length > 320 ||
    !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)
  ) {
    return json({ allowed: false, message: "Invalid email address." });
  }
  if (password.length < 6 || password.length > 4096) {
    return json({ allowed: false, message: "Invalid password." });
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseUrl || !anonKey || !serviceRoleKey) {
    return json({ error: "Login protection is not configured." }, 500);
  }

  const admin = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false },
  });
  const { data: status, error: statusError } = await admin.rpc(
    "auth_login_attempt_status",
    {
      email_to_check: email,
    },
  );
  if (statusError) {
    console.error("Login status check failed", statusError);
    return json({ error: "Unable to check login status." }, 500);
  }
  if (status?.exists !== true) {
    return json({
      allowed: false,
      message: "No user found with this email.",
    });
  }
  if (status?.locked === true) {
    const minutes = Math.max(1, Number(status.retry_after_minutes) || 15);
    return json({
      allowed: false,
      message:
        `Too many failed login attempts. Please try again in ${minutes} minute${minutes === 1 ? "" : "s"}.`,
    });
  }

  const authClient = createClient(supabaseUrl, anonKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data: loginData, error: loginError } = await authClient.auth
    .signInWithPassword({ email, password });

  if (loginError || !loginData.user) {
    const invalidCredentials = loginError?.code === "invalid_credentials" ||
      loginError?.message.toLowerCase().includes("invalid login credentials");
    if (!invalidCredentials) {
      console.error("Password verification failed", loginError);
      return json({
        allowed: false,
        message: "Unable to verify your login. Please try again.",
      });
    }

    const { data: failure, error: failureError } = await admin.rpc(
      "auth_record_login_failure",
      { email_to_check: email },
    );
    if (failureError) {
      console.error("Failed login could not be recorded", failureError);
      return json({ error: "Unable to record the login attempt." }, 500);
    }
    if (failure?.locked === true) {
      const minutes = Math.max(
        1,
        Number(failure.retry_after_minutes) || 15,
      );
      return json({
        allowed: false,
        message:
          `Too many failed login attempts. Please try again in ${minutes} minute${minutes === 1 ? "" : "s"}.`,
      });
    }
    const remaining = Math.max(0, Number(failure?.attempts_remaining) || 0);
    return json({
      allowed: false,
      message:
        `Incorrect password. ${remaining} attempt${remaining === 1 ? "" : "s"} remaining.`,
    });
  }

  const { error: resetError } = await admin.rpc("auth_reset_login_attempts", {
    target_user_id: loginData.user.id,
  });
  if (resetError) {
    console.error("Login attempts could not be reset", resetError);
    return json({ error: "Unable to reset login protection." }, 500);
  }

  // The temporary password session is used only as proof of a correct
  // password. The app continues with its existing email-code login flow.
  const { error: signOutError } = await authClient.auth.signOut({
    scope: "local",
  });
  if (signOutError) {
    console.error("Temporary password session sign-out failed", signOutError);
  }

  return json({ allowed: true });
});
