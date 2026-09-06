# Personal Assistance Edge Function setup

Personal Assistance database and avatar operations now run through authenticated
Edge Functions. The Flutter app continues to use the publishable key for
Supabase Auth and sends the signed-in user's access token to each function.

Each function is self-contained so its `index.ts` can also be pasted directly
into the Supabase Dashboard Edge Function editor.

## Deploy

From the project directory, log in and link the Supabase CLI if needed, then run:

```powershell
supabase functions deploy personal-data
supabase functions deploy daily-commutes
supabase functions deploy journey-history
supabase functions deploy profile-avatar
supabase functions deploy delete-account
supabase db push
```

Alternatively, paste and run
`supabase/migrations/202609070001_personal_assistance_edge_access.sql` in the
Supabase SQL Editor after the four new functions have been deployed.

`SUPABASE_URL`, `SUPABASE_ANON_KEY`, and `SUPABASE_SERVICE_ROLE_KEY` are provided
to hosted Edge Functions by Supabase. Do not copy the service-role key into the
Flutter application or commit it to this repository.

## Access model

- Each function validates the bearer access token with `auth.getUser`.
- The verified user's ID is used for every filter and insert. Request-provided
  `user_id` values are ignored.
- RLS remains disabled on the Personal Assistance public tables.
- The migration revokes direct `anon`/`authenticated` table privileges, so the
  publishable-key Flutter client cannot bypass the Edge Functions.
- Avatar reads, uploads, and deletes use the server-side service role. The old
  authenticated-client Storage policies are removed by the migration.
