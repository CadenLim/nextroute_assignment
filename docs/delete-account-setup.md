# Delete Account setup

Account deletion uses an authenticated Edge Function. The Flutter app never
contains or receives the Supabase service-role key.

## Deploy

1. Run `supabase/migrations/202609060004_delete_account.sql` in the Supabase SQL
   Editor.
2. Deploy the function with:

   ```sh
   supabase functions deploy delete-account --no-verify-jwt
   ```

`SUPABASE_URL`, `SUPABASE_ANON_KEY`, and `SUPABASE_SERVICE_ROLE_KEY` are provided
to hosted Edge Functions by Supabase. Do not copy the service-role key into the
Flutter app or commit it to the repository.

The Edge Function validates the caller's bearer token with Supabase Auth and
always deletes only that authenticated user. The database function is revoked
from `anon` and `authenticated` and can only be invoked using `service_role`.

The user's avatar is removed through the Storage API. The following database
records are then removed in one transaction: `daily_commutes`, `saved_places`,
`saved_routes`, `navigation_history`, `profiles`, and finally `auth.users`.
No RLS policies are added or enabled.
