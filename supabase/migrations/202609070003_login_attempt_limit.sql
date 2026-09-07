begin;

create table if not exists public.auth_login_attempts (
  user_id uuid primary key references auth.users(id) on delete cascade,
  failed_attempts integer not null default 0
    check (failed_attempts between 0 and 5),
  locked_until timestamptz,
  updated_at timestamptz not null default now()
);

alter table public.auth_login_attempts disable row level security;
revoke all on table public.auth_login_attempts from public;
revoke all on table public.auth_login_attempts from anon;
revoke all on table public.auth_login_attempts from authenticated;
grant select, insert, update, delete on table public.auth_login_attempts
  to service_role;

create or replace function public.auth_login_attempt_status(email_to_check text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  account_id uuid;
  attempt_record public.auth_login_attempts%rowtype;
  retry_minutes integer;
begin
  select id into account_id
  from auth.users
  where lower(email) = lower(btrim(email_to_check));

  if account_id is null then
    return jsonb_build_object('exists', false, 'locked', false);
  end if;

  update public.auth_login_attempts
  set failed_attempts = 0,
      locked_until = null,
      updated_at = now()
  where user_id = account_id
    and locked_until is not null
    and locked_until <= now();

  select * into attempt_record
  from public.auth_login_attempts
  where user_id = account_id;

  if attempt_record.locked_until is not null
      and attempt_record.locked_until > now() then
    retry_minutes := greatest(
      1,
      ceil(extract(epoch from (attempt_record.locked_until - now())) / 60)::int
    );
    return jsonb_build_object(
      'exists', true,
      'locked', true,
      'retry_after_minutes', retry_minutes
    );
  end if;

  return jsonb_build_object(
    'exists', true,
    'locked', false,
    'attempts_remaining', 5 - coalesce(attempt_record.failed_attempts, 0)
  );
end;
$$;

create or replace function public.auth_record_login_failure(email_to_check text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  account_id uuid;
  attempt_record public.auth_login_attempts%rowtype;
  retry_minutes integer;
begin
  select id into account_id
  from auth.users
  where lower(email) = lower(btrim(email_to_check));

  if account_id is null then
    return jsonb_build_object('exists', false, 'locked', false);
  end if;

  insert into public.auth_login_attempts as attempts (
    user_id,
    failed_attempts,
    locked_until,
    updated_at
  )
  values (account_id, 1, null, now())
  on conflict (user_id) do update
  set failed_attempts = case
        when attempts.locked_until is not null
          and attempts.locked_until > now()
          then attempts.failed_attempts
        when attempts.locked_until is not null
          and attempts.locked_until <= now()
          then 1
        else least(5, attempts.failed_attempts + 1)
      end,
      locked_until = case
        when attempts.locked_until is not null
          and attempts.locked_until > now()
          then attempts.locked_until
        when (
          case
            when attempts.locked_until is not null
              and attempts.locked_until <= now()
              then 1
            else attempts.failed_attempts + 1
          end
        ) >= 5 then now() + interval '15 minutes'
        else null
      end,
      updated_at = now()
  returning * into attempt_record;

  if attempt_record.locked_until is not null
      and attempt_record.locked_until > now() then
    retry_minutes := greatest(
      1,
      ceil(extract(epoch from (attempt_record.locked_until - now())) / 60)::int
    );
  end if;

  return jsonb_build_object(
    'exists', true,
    'locked', attempt_record.locked_until is not null
      and attempt_record.locked_until > now(),
    'attempts_remaining', greatest(0, 5 - attempt_record.failed_attempts),
    'retry_after_minutes', retry_minutes
  );
end;
$$;

create or replace function public.auth_reset_login_attempts(target_user_id uuid)
returns void
language sql
security definer
set search_path = ''
as $$
  delete from public.auth_login_attempts where user_id = target_user_id;
$$;

revoke all on function public.auth_login_attempt_status(text) from public;
revoke all on function public.auth_login_attempt_status(text) from anon;
revoke all on function public.auth_login_attempt_status(text) from authenticated;
grant execute on function public.auth_login_attempt_status(text) to service_role;

revoke all on function public.auth_record_login_failure(text) from public;
revoke all on function public.auth_record_login_failure(text) from anon;
revoke all on function public.auth_record_login_failure(text) from authenticated;
grant execute on function public.auth_record_login_failure(text) to service_role;

revoke all on function public.auth_reset_login_attempts(uuid) from public;
revoke all on function public.auth_reset_login_attempts(uuid) from anon;
revoke all on function public.auth_reset_login_attempts(uuid) from authenticated;
grant execute on function public.auth_reset_login_attempts(uuid) to service_role;

commit;
