alter table public.navigation_history
  add column if not exists origin_station jsonb,
  add column if not exists destination_station jsonb,
  add column if not exists route_signature text,
  add column if not exists line_name text;

