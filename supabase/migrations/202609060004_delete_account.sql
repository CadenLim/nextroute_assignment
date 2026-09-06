begin;

create or replace function public.delete_personal_account(target_user_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  delete from public.daily_commutes where user_id = target_user_id;
  delete from public.saved_places where user_id = target_user_id;
  delete from public.saved_routes where user_id = target_user_id;
  delete from public.navigation_history where user_id = target_user_id;
  delete from public.profiles where id = target_user_id;

  delete from auth.users where id = target_user_id;
  if not found then
    raise exception 'Account not found.';
  end if;
end;
$$;

revoke all on function public.delete_personal_account(uuid) from public;
revoke all on function public.delete_personal_account(uuid) from anon;
revoke all on function public.delete_personal_account(uuid) from authenticated;
grant execute on function public.delete_personal_account(uuid) to service_role;

commit;
