begin;

create table if not exists public.daily_commutes (
  user_id uuid primary key references auth.users(id) on delete cascade,
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

alter table public.daily_commutes enable row level security;

revoke all on public.daily_commutes from anon;

drop policy if exists "Users can view their daily commute" on public.daily_commutes;
create policy "Users can view their daily commute"
on public.daily_commutes for select
to authenticated
using ((select auth.uid()) = user_id);

drop policy if exists "Users can create their daily commute" on public.daily_commutes;
create policy "Users can create their daily commute"
on public.daily_commutes for insert
to authenticated
with check (
  (select auth.uid()) = user_id
  and (
    saved_route_id is null
    or exists (
      select 1
      from public.saved_routes
      where saved_routes.id = daily_commutes.saved_route_id
        and saved_routes.user_id = (select auth.uid())
    )
  )
);

drop policy if exists "Users can update their daily commute" on public.daily_commutes;
create policy "Users can update their daily commute"
on public.daily_commutes for update
to authenticated
using ((select auth.uid()) = user_id)
with check (
  (select auth.uid()) = user_id
  and (
    saved_route_id is null
    or exists (
      select 1
      from public.saved_routes
      where saved_routes.id = daily_commutes.saved_route_id
        and saved_routes.user_id = (select auth.uid())
    )
  )
);

drop policy if exists "Users can delete their daily commute" on public.daily_commutes;
create policy "Users can delete their daily commute"
on public.daily_commutes for delete
to authenticated
using ((select auth.uid()) = user_id);

grant select, insert, update, delete on public.daily_commutes to authenticated;

commit;
