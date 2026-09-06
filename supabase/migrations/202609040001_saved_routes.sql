begin;

create table public.saved_routes (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  name text not null check (char_length(btrim(name)) between 1 and 80),
  route_key text not null check (octet_length(route_key) <= 2000),
  origin jsonb not null check (
    jsonb_typeof(origin) = 'object'
    and jsonb_typeof(origin -> 'ids') = 'array'
    and jsonb_array_length(origin -> 'ids') > 0
  ),
  destination jsonb not null check (
    jsonb_typeof(destination) = 'object'
    and jsonb_typeof(destination -> 'ids') = 'array'
    and jsonb_array_length(destination -> 'ids') > 0
  ),
  route_signature text not null,
  line_name text not null,
  created_at timestamptz not null default now(),
  unique (user_id, route_key)
);

create index saved_routes_user_created_idx
  on public.saved_routes (user_id, created_at desc);

revoke all on public.saved_routes from anon;
grant select, insert, update, delete on public.saved_routes to authenticated;

commit;
