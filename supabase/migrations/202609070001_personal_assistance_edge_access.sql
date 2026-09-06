begin;

-- RLS intentionally remains disabled for the assignment. Instead, prevent
-- Flutter's publishable/anon client from accessing personal tables directly.
revoke all on table public.profiles from anon, authenticated;
revoke all on table public.saved_routes from anon, authenticated;
revoke all on table public.saved_places from anon, authenticated;
revoke all on table public.daily_commutes from anon, authenticated;
revoke all on table public.navigation_history from anon, authenticated;

grant select, insert, update, delete on table public.profiles to service_role;
grant select, insert, update, delete on table public.saved_routes to service_role;
grant select, insert, update, delete on table public.saved_places to service_role;
grant select, insert, update, delete on table public.daily_commutes to service_role;
grant select, insert, update, delete on table public.navigation_history to service_role;

-- Avatar access now goes through profile-avatar/delete-account Edge Functions.
-- Storage keeps its own platform RLS enabled, but client policies are no longer
-- needed because only the server-side service role accesses this bucket.
drop policy if exists "Read own avatar" on storage.objects;
drop policy if exists "Upload own avatar" on storage.objects;
drop policy if exists "Replace own avatar" on storage.objects;
drop policy if exists "Delete own avatar" on storage.objects;

commit;
