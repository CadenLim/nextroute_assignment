-- Module 5 only. Additive and safe to rerun. No data insertion or grant changes.
-- Existing notifications remain readable before and after this migration.
begin;
alter table public.notifications
  add column if not exists delay_minutes integer,
  add column if not exists vehicle_label text,
  add column if not exists from_stop text,
  add column if not exists to_stop text,
  add column if not exists direction text;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.notifications'::regclass
      and conname = 'module5_delay_minutes_range'
  ) then
    alter table public.notifications
      add constraint module5_delay_minutes_range
      check (delay_minutes is null or delay_minutes between 0 and 1440);
  end if;
end $$;

comment on column public.notifications.delay_minutes is
  'Publisher-supplied delay or a labelled NextRoute estimate in minutes (0-1440); NULL means unknown, not zero.';
comment on column public.notifications.vehicle_label is
  'Optional operator-supplied public bus identifier; NULL means route-level notice, not a known individual bus.';
comment on column public.notifications.from_stop is
  'Publisher-supplied affected section, or the stop used by a labelled NextRoute estimate; not inferred from route_long_name.';
comment on column public.notifications.to_stop is
  'Publisher-supplied end of the affected section, or estimate destination.';
comment on column public.notifications.direction is
  'Publisher-supplied direction or estimate destination from the matched trip; NULL means unspecified.';
commit;
