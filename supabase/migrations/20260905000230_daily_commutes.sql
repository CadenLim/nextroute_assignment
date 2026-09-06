begin;

create table if not exists public.daily_commutes (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  saved_route_id uuid references public.saved_routes(id) on delete set null,
  origin text not null check (length(btrim(origin)) > 0),
  destination text not null check (length(btrim(destination)) > 0),
  arrive_by time without time zone not null,
  active_days smallint[] not null,
  reminder_enabled boolean not null default true,
  reminder_minutes_before smallint not null default 10
    check (reminder_minutes_before in (5, 10, 15, 30)),
  estimated_duration_minutes integer not null
    check (estimated_duration_minutes > 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint daily_commutes_active_days_not_empty
    check (cardinality(active_days) > 0),
  constraint daily_commutes_active_days_valid
    check (active_days <@ array[1, 2, 3, 4, 5, 6, 7]::smallint[])
);

create index if not exists daily_commutes_user_updated_idx
  on public.daily_commutes (user_id, updated_at desc);

revoke all on public.daily_commutes from anon;
grant select, insert, update, delete on public.daily_commutes to authenticated;

commit;
