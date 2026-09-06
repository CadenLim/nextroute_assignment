-- Module 5 only: store auditable schedule-vs-position delay estimates.
-- Additive, safe to rerun, and does not change teammate tables or grants.
begin;

alter table public.notifications
  add column if not exists trip_id text,
  add column if not exists observed_stop_id text,
  add column if not exists scheduled_arrival timestamp with time zone,
  add column if not exists estimated_arrival timestamp with time zone,
  add column if not exists estimate_method text;

comment on column public.notifications.scheduled_arrival is
  'Published GTFS scheduled arrival at the downstream terminal used by the estimate.';
comment on column public.notifications.estimated_arrival is
  'NextRoute estimate, not an operator Trip Update.';
comment on column public.notifications.estimate_method is
  'Null for publisher notices; schedule_stop_observation for Module 5 estimates.';

-- Keep the weekly archive projection aligned with the additive delay fields.
-- This remains public service data only; user read state/preferences are excluded.
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
      n.estimated_arrival, n.estimate_method
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

  -- Below five minutes means no material delay. Expiring the existing episode
  -- preserves it in History while removing it from Current notifications.
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

  -- Advisory locking plus update-then-insert works whether or not the team's
  -- existing notifications table has a UNIQUE constraint on dedupe_key.
  update public.notifications set
    title = 'Estimated delay on bus route ' || btrim(module5_record_estimated_delay.route),
    message = 'A fresh vehicle stop observation was compared with the published GTFS timetable. '
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
    estimate_method = 'schedule_stop_observation'
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
      'A fresh vehicle stop observation was compared with the published GTFS timetable. '
        || 'The trip is estimated ' || delay_minutes || ' minutes late towards '
        || btrim(direction) || '. This is a NextRoute estimate, not an operator Trip Update.',
      btrim(route), observed_at, 'appGenerated', notice_severity, notice_key,
      observed_at + interval '45 minutes', true, delay_minutes,
      nullif(btrim(vehicle_label), ''), btrim(from_stop), btrim(to_stop),
      btrim(direction), btrim(trip), nullif(btrim(observed_stop_id), ''),
      scheduled_arrival, estimated_arrival, 'schedule_stop_observation'
    );
  end if;
end;
$$;

revoke all on function public.module5_record_estimated_delay(
  text,text,text,text,integer,text,text,text,text,text,
  timestamp with time zone,timestamp with time zone,timestamp with time zone
) from public, anon, authenticated;
grant execute on function public.module5_record_estimated_delay(
  text,text,text,text,integer,text,text,text,text,text,
  timestamp with time zone,timestamp with time zone,timestamp with time zone
) to service_role;

commit;
