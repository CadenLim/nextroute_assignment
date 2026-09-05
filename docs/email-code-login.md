# Guest access and email codes

Public tabs open without a session. Profile asks the visitor to sign in.
Saving a favourite prompts for sign-in and resumes the same selected route
after authentication. Cancelling preserves the route results. A guest can
start a journey; only a signed-in user's journey is written to navigation history.
Existing authenticated sessions remain signed in until sign-out or expiry.

Login requires email and password before sending an email OTP. Passwords are
checked with a separate HTTP request, outside the shared auth client's session
and browser broadcast channel. The temporary password session is revoked and
the HTTP client closed before the main auth client requests the OTP
with `shouldCreateUser: false`. A wrong password prevents the email request.
Only a successful `verifyOTP(type: email)` establishes the app's active session.
Registration retains name, email and password and verifies a `signup` code.
Codes contain 6 digits, matching the project email OTP length.

This is an app-enforced two-step flow, not Supabase server-enforced MFA. Supabase
still exposes its password and email OTP endpoints independently; this change
does not add an AAL2 requirement to database policies. Do not describe it as
server-enforced two-factor authentication. Password-session credentials are
never copied to the app's shared client or persisted to device storage.

## Supabase settings

1. Keep the Email provider enabled and **Confirm email** enabled for sign-up.
2. Set Authentication > Sign In / Providers > Email > **Email OTP length**
   to `6`.
3. In Authentication > Email Templates > **Magic Link**, use the template
   below. Supabase uses this template for login OTP emails, separately from
   the Confirm signup template already used for registration.
4. Keep `{{ .Token }}` in **Confirm signup** as well. The templates should
   display the code rather than a login link for this in-app verification flow.

Suggested Magic Link subject: `Your NextRoute sign-in code`

```html
<h2>Sign in to NextRoute</h2>
<p>Enter this verification code in the app:</p>
<p style="font-size:28px;font-weight:bold;letter-spacing:4px">{{ .Token }}</p>
<p>If you did not request this code, you can ignore this email.</p>
```

No database table changes are needed for email-code login. An unregistered
email must use Create Account; requesting a login code cannot register it.
Delivery still depends on the project's email templates, provider limits,
and SMTP configuration. Verify delivery with a real registered email.

## Manual verification

- Sign out, reopen the app and search two stations without signing in.
- Tap Save route, cancel sign-in and confirm the result is preserved.
- Tap Save route again, request a code, enter it and save the same route.
- Enter an incorrect password and verify that no code is requested.
- Test a wrong code and resend; neither should sign in prematurely.
- Check Profile while signed out, then sign in and check your saved routes.
- Check Stations, AI Crowd and public analytics as a guest. Cloud data needs
  anonymous SELECT permissions for the public datasets; do not grant guest
  access to profiles, saved_routes or navigation_history.

Reference: https://supabase.com/docs/guides/auth/auth-email-passwordless
