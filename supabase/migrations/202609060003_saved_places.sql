begin;

create table if not exists public.saved_places (
  user_id uuid not null references auth.users(id) on delete cascade,
  place_type text not null check (place_type in ('home', 'university', 'work')),
  station_id text not null,
  station_ids text[] not null check (cardinality(station_ids) > 0),
  station_name text not null check (length(btrim(station_name)) > 0),
  lines text[] not null default '{}',
  category text not null default 'Transit',
  latitude double precision not null,
  longitude double precision not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (user_id, place_type)
);

revoke all on public.saved_places from anon;
grant select, insert, update, delete on public.saved_places to authenticated;
alter table public.saved_places disable row level security;

commit;
