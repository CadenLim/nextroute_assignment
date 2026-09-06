-- Module 5 only: improve auditable slow-movement estimates and archive fields.
begin;

alter table public.module5_vehicle_observations
  add column if not exists slow_interval_streak integer not null default 0,
  add column if not exists slow_duration_seconds integer not null default 0;

alter table public.module5_vehicle_observations
  drop constraint if exists module5_vehicle_observations_slow_interval_streak_check,
  add constraint module5_vehicle_observations_slow_interval_streak_check
    check (slow_interval_streak between 0 and 20),
  drop constraint if exists module5_vehicle_observations_slow_duration_seconds_check,
  add constraint module5_vehicle_observations_slow_duration_seconds_check
    check (slow_duration_seconds between 0 and 7200);

alter table public.notifications
  add column if not exists confidence text;

alter table public.notifications
  drop constraint if exists notifications_confidence_check,
  add constraint notifications_confidence_check
    check (confidence is null or confidence in ('Low', 'Medium', 'High'));

comment on column public.notifications.confidence is
  'Confidence label for a clearly identified NextRoute estimate; null for publisher notices.';

-- This overload is used by the strengthened collector. The earlier six-argument
-- version remains temporarily compatible with an already-running deployment.
create or replace function public.module5_record_estimated_congestion(
  route text,
  trip text,
  vehicle_label text,
  speed_kmh double precision,
  duration_minutes integer,
  observed_at timestamp with time zone,
  confidence text
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
     speed_kmh < 1 or speed_kmh > 10 or duration_minutes not between 6 and 30 or
     confidence not in ('Low', 'Medium', 'High') or
     observed_at is null or observed_at < now() - interval '5 minutes' or
     observed_at > now() + interval '1 minute' then
    raise exception 'invalid estimated congestion input' using errcode = '22023';
  end if;
  notice_key := 'estimated-congestion:' || btrim(vehicle_label) || ':' || btrim(trip);
  notice_severity := case
    when confidence = 'High' then 'high'
    when confidence = 'Medium' or speed_kmh <= 3 then 'moderate'
    else 'info'
  end;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(notice_key, 0));

  update public.notifications set
    title = 'Possible slow movement on bus route ' || btrim(module5_record_estimated_congestion.route),
    message = 'Bus ' || btrim(module5_record_estimated_congestion.vehicle_label)
      || ' moved at an average ' || round(module5_record_estimated_congestion.speed_kmh::numeric, 1)
      || ' km/h across repeated fresh GPS intervals ('
      || module5_record_estimated_congestion.duration_minutes || ' minutes). '
      || 'Reported stop dwell was excluded. This is a NextRoute estimate, not operator-confirmed congestion.',
    route_id = btrim(module5_record_estimated_congestion.route),
    created_at = module5_record_estimated_congestion.observed_at,
    severity = notice_severity,
    expires_at = module5_record_estimated_congestion.observed_at + interval '20 minutes',
    is_active = true,
    vehicle_label = btrim(module5_record_estimated_congestion.vehicle_label),
    trip_id = btrim(module5_record_estimated_congestion.trip),
    estimate_method = 'gps_sustained_low_speed',
    observed_speed_kmh = module5_record_estimated_congestion.speed_kmh,
    observation_duration_minutes = module5_record_estimated_congestion.duration_minutes,
    confidence = module5_record_estimated_congestion.confidence
  where dedupe_key = notice_key;
  get diagnostics updated_count = row_count;

  if updated_count = 0 then
    insert into public.notifications (
      notification_type, title, message, route_id, created_at, origin, severity,
      dedupe_key, expires_at, is_active, vehicle_label, trip_id, estimate_method,
      observed_speed_kmh, observation_duration_minutes, confidence
    ) values (
      'crowd',
      'Possible slow movement on bus route ' || btrim(route),
      'Bus ' || btrim(vehicle_label) || ' moved at an average '
        || round(speed_kmh::numeric, 1) || ' km/h across repeated fresh GPS intervals ('
        || duration_minutes || ' minutes). Reported stop dwell was excluded. '
        || 'This is a NextRoute estimate, not operator-confirmed congestion.',
      btrim(route), observed_at, 'appGenerated', notice_severity, notice_key,
      observed_at + interval '20 minutes', true, btrim(vehicle_label), btrim(trip),
      'gps_sustained_low_speed', speed_kmh, duration_minutes, confidence
    );
  end if;
end;
$$;

revoke all on function public.module5_record_estimated_congestion(
  text,text,text,double precision,integer,timestamp with time zone,text
) from public, anon, authenticated;
grant execute on function public.module5_record_estimated_congestion(
  text,text,text,double precision,integer,timestamp with time zone,text
) to service_role;

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
      n.created_at, n.expires_at, n.is_active, n.origin, n.severity, n.dedupe_key,
      n.delay_minutes, n.vehicle_label, n.from_stop, n.to_stop, n.direction,
      n.trip_id, n.observed_stop_id, n.scheduled_arrival,
      n.estimated_arrival, n.estimate_method, n.observed_speed_kmh,
      n.observation_duration_minutes, n.confidence
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
