-- Module 5 only: retain short-lived vehicle movement observations and publish
-- explicitly labelled GPS/timetable estimates when the source omits alerts.
begin;

create table if not exists public.module5_vehicle_observations (
  id bigint generated always as identity primary key,
  vehicle_id text not null,
  route_id text not null,
  trip_id text not null,
  latitude double precision not null check (latitude between -90 and 90),
  longitude double precision not null check (longitude between -180 and 180),
  vehicle_timestamp timestamp with time zone not null,
  observed_at timestamp with time zone not null default now(),
  speed_kmh double precision check (speed_kmh is null or speed_kmh between 0 and 180),
  movement_interval_seconds integer check (
    movement_interval_seconds is null or movement_interval_seconds between 1 and 3600
  ),
  source text not null default 'rapidkl_gtfs_realtime',
  unique (vehicle_id, vehicle_timestamp)
);

create index if not exists module5_vehicle_observations_recent_idx
  on public.module5_vehicle_observations (vehicle_id, vehicle_timestamp desc);
create index if not exists module5_vehicle_observations_cleanup_idx
  on public.module5_vehicle_observations (vehicle_timestamp);

-- This coursework does not use RLS. Access is restricted with explicit SQL
-- privileges instead: the mobile app roles have no table privileges and only
-- the Edge Function service role can read or write movement observations.
alter table public.module5_vehicle_observations disable row level security;
revoke all on table public.module5_vehicle_observations from public, anon, authenticated;
grant select, insert, update, delete on table public.module5_vehicle_observations to service_role;
grant usage, select on sequence public.module5_vehicle_observations_id_seq to service_role;

alter table public.notifications
  add column if not exists observed_speed_kmh double precision,
  add column if not exists observation_duration_minutes integer;

comment on column public.notifications.observed_speed_kmh is
  'Average GPS movement speed used by a clearly labelled NextRoute congestion estimate.';
comment on column public.notifications.observation_duration_minutes is
  'Approximate duration covered by consecutive GPS movement intervals.';

-- Replace the same-signature delay recorder so newly generated messages describe
-- a near-stop GPS observation rather than claiming the feed reported STOPPED_AT.
create or replace function public.module5_record_estimated_delay(
  route text,
  trip text,
  service_date text,
  start_time text,
  delay_minutes integer,
  vehicle_label text,
  from_stop text,
  to_stop text,
  direction text,
  observed_stop_id text,
  scheduled_arrival timestamp with time zone,
  estimated_arrival timestamp with time zone,
  observed_at timestamp with time zone
) returns void
language plpgsql
security invoker
set search_path = ''
as $$
declare
  notice_key text;
  notice_severity text;
  updated_count integer;
begin
  if nullif(btrim(route), '') is null or nullif(btrim(trip), '') is null or
     service_date is null or service_date !~ '^\d{8}$' or
     delay_minutes is null or delay_minutes not between 0 and 180 or
     (start_time is not null and start_time !~ '^([0-3][0-9]|4[0-7]):[0-5][0-9]:[0-5][0-9]$') or
     nullif(btrim(from_stop), '') is null or nullif(btrim(to_stop), '') is null or
     nullif(btrim(direction), '') is null or
     scheduled_arrival is null or estimated_arrival is null or observed_at is null or
     observed_at < now() - interval '5 minutes' or
     observed_at > now() + interval '1 minute' or
     estimated_arrival <> scheduled_arrival + make_interval(mins => delay_minutes) then
    raise exception 'invalid estimated delay input' using errcode = '22023';
  end if;
  notice_key := 'estimated-delay:' || btrim(trip) || ':' || service_date || ':' ||
    coalesce(nullif(btrim(start_time), ''), 'scheduled');
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(notice_key, 0));

  if delay_minutes < 5 then
    update public.notifications
    set expires_at = least(coalesce(expires_at, observed_at), observed_at)
    where dedupe_key = notice_key and is_active = true;
    return;
  end if;

  notice_severity := case
    when delay_minutes >= 30 then 'high'
    when delay_minutes >= 15 then 'moderate'
    else 'info'
  end;

  update public.notifications set
    title = 'Estimated delay on bus route ' || btrim(module5_record_estimated_delay.route),
    message = 'A fresh bus position near a scheduled stop was compared with the published GTFS timetable. '
      || 'The trip is estimated ' || module5_record_estimated_delay.delay_minutes
      || ' minutes late towards ' || btrim(module5_record_estimated_delay.direction)
      || '. This is a NextRoute estimate, not an operator Trip Update.',
    route_id = btrim(module5_record_estimated_delay.route),
    severity = notice_severity,
    expires_at = module5_record_estimated_delay.observed_at + interval '45 minutes',
    is_active = true,
    delay_minutes = module5_record_estimated_delay.delay_minutes,
    vehicle_label = nullif(btrim(module5_record_estimated_delay.vehicle_label), ''),
    from_stop = btrim(module5_record_estimated_delay.from_stop),
    to_stop = btrim(module5_record_estimated_delay.to_stop),
    direction = btrim(module5_record_estimated_delay.direction),
    trip_id = btrim(module5_record_estimated_delay.trip),
    observed_stop_id = nullif(btrim(module5_record_estimated_delay.observed_stop_id), ''),
    scheduled_arrival = module5_record_estimated_delay.scheduled_arrival,
    estimated_arrival = module5_record_estimated_delay.estimated_arrival,
    estimate_method = 'schedule_near_stop_position'
  where dedupe_key = notice_key;
  get diagnostics updated_count = row_count;

  if updated_count = 0 then
    insert into public.notifications (
      notification_type, title, message, route_id, created_at, origin, severity,
      dedupe_key, expires_at, is_active, delay_minutes, vehicle_label,
      from_stop, to_stop, direction, trip_id, observed_stop_id,
      scheduled_arrival, estimated_arrival, estimate_method
    ) values (
      'delay',
      'Estimated delay on bus route ' || btrim(route),
      'A fresh bus position near a scheduled stop was compared with the published GTFS timetable. '
        || 'The trip is estimated ' || delay_minutes || ' minutes late towards '
        || btrim(direction) || '. This is a NextRoute estimate, not an operator Trip Update.',
      btrim(route), observed_at, 'appGenerated', notice_severity, notice_key,
      observed_at + interval '45 minutes', true, delay_minutes,
      nullif(btrim(vehicle_label), ''), btrim(from_stop), btrim(to_stop),
      btrim(direction), btrim(trip), nullif(btrim(observed_stop_id), ''),
      scheduled_arrival, estimated_arrival, 'schedule_near_stop_position'
    );
  end if;
end;
$$;

create or replace function public.module5_record_estimated_congestion(
  route text,
  trip text,
  vehicle_label text,
  speed_kmh double precision,
  duration_minutes integer,
  observed_at timestamp with time zone
) returns void
language plpgsql
security invoker
set search_path = ''
as $$
declare
  notice_key text;
  notice_severity text;
  updated_count integer;
begin
  if nullif(btrim(route), '') is null or nullif(btrim(trip), '') is null or
     nullif(btrim(vehicle_label), '') is null or speed_kmh is null or
     speed_kmh < 0.5 or speed_kmh > 8 or duration_minutes not between 4 and 20 or
     observed_at is null or observed_at < now() - interval '5 minutes' or
     observed_at > now() + interval '1 minute' then
    raise exception 'invalid estimated congestion input' using errcode = '22023';
  end if;
  notice_key := 'estimated-congestion:' || btrim(vehicle_label) || ':' || btrim(trip);
  notice_severity := case when speed_kmh <= 3 then 'moderate' else 'info' end;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(notice_key, 0));

  update public.notifications set
    title = 'Possible congestion on bus route ' || btrim(module5_record_estimated_congestion.route),
    message = 'Bus ' || btrim(module5_record_estimated_congestion.vehicle_label)
      || ' moved at an average ' || round(module5_record_estimated_congestion.speed_kmh::numeric, 1)
      || ' km/h across two consecutive GPS intervals ('
      || module5_record_estimated_congestion.duration_minutes || ' minutes). '
      || 'This may indicate road congestion or prolonged slow movement; it is not operator-confirmed.',
    route_id = btrim(module5_record_estimated_congestion.route),
    created_at = module5_record_estimated_congestion.observed_at,
    severity = notice_severity,
    expires_at = module5_record_estimated_congestion.observed_at + interval '20 minutes',
    is_active = true,
    vehicle_label = btrim(module5_record_estimated_congestion.vehicle_label),
    trip_id = btrim(module5_record_estimated_congestion.trip),
    estimate_method = 'gps_low_speed_two_intervals',
    observed_speed_kmh = module5_record_estimated_congestion.speed_kmh,
    observation_duration_minutes = module5_record_estimated_congestion.duration_minutes
  where dedupe_key = notice_key;
  get diagnostics updated_count = row_count;

  if updated_count = 0 then
    insert into public.notifications (
      notification_type, title, message, route_id, created_at, origin, severity,
      dedupe_key, expires_at, is_active, vehicle_label, trip_id, estimate_method,
      observed_speed_kmh, observation_duration_minutes
    ) values (
      'crowd',
      'Possible congestion on bus route ' || btrim(route),
      'Bus ' || btrim(vehicle_label) || ' moved at an average '
        || round(speed_kmh::numeric, 1) || ' km/h across two consecutive GPS intervals ('
        || duration_minutes || ' minutes). This may indicate road congestion or prolonged slow movement; '
        || 'it is not operator-confirmed.',
      btrim(route), observed_at, 'appGenerated', notice_severity, notice_key,
      observed_at + interval '20 minutes', true, btrim(vehicle_label), btrim(trip),
      'gps_low_speed_two_intervals', speed_kmh, duration_minutes
    );
  end if;
end;
$$;

revoke all on function public.module5_record_estimated_congestion(
  text,text,text,double precision,integer,timestamp with time zone
) from public, anon, authenticated;
grant execute on function public.module5_record_estimated_congestion(
  text,text,text,double precision,integer,timestamp with time zone
) to service_role;

-- Keep the report/archive projection aligned with the additive estimate fields.
create or replace function public.module5_alert_history(
  start_at timestamptz, end_at timestamptz, page_offset integer default 0
)
returns jsonb language plpgsql stable security invoker set search_path = ''
as $$
declare result jsonb;
begin
  if start_at is null or end_at is null or end_at <= start_at
      or end_at - start_at > interval '63 days'
      or page_offset is null or page_offset < 0 or page_offset > 50000 then
    raise exception 'Invalid archive period or page';
  end if;
  select coalesce(jsonb_agg(to_jsonb(a) order by a.created_at, a.id), '[]'::jsonb)
  into result from (
    select n.id, n.notification_type, n.title, n.message, n.route_id,
      n.created_at, n.origin, n.severity, n.dedupe_key,
      n.delay_minutes, n.vehicle_label, n.from_stop, n.to_stop, n.direction,
      n.trip_id, n.observed_stop_id, n.scheduled_arrival,
      n.estimated_arrival, n.estimate_method,
      n.observed_speed_kmh, n.observation_duration_minutes
    from public.notifications n
    where n.is_active = true and n.created_at >= start_at and n.created_at < end_at
      and n.created_at <= now()
    order by n.created_at, n.id
    limit 500 offset page_offset
  ) a;
  return result;
end;
$$;

revoke all on function public.module5_alert_history(timestamptz, timestamptz, integer)
  from public;
grant execute on function public.module5_alert_history(timestamptz, timestamptz, integer)
  to anon, authenticated, service_role;

commit;
