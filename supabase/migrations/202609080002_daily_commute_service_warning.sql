begin;

alter table public.daily_commutes
  add column if not exists has_service_warning boolean not null default false;

comment on column public.daily_commutes.has_service_warning is
  'True when the user saved a departure despite no complete matching Favourite Route service being scheduled around that time.';

commit;
