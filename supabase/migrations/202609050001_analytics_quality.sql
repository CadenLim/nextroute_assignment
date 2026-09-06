-- Module 5 only. Run once in Supabase SQL Editor BEFORE deploying the collector.
-- Additive: no existing rows, views, policies or teammate tables are deleted.
begin;

alter table public.analytics_snapshots
  add column if not exists congestion_reported_vehicle_count integer,
  add column if not exists fresh_vehicle_count integer,
  add column if not exists stale_vehicle_count integer,
  add column if not exists unknown_timestamp_vehicle_count integer,
  add column if not exists fresh_congestion_reported_vehicle_count integer,
  add column if not exists fresh_congested_vehicle_count integer,
  add column if not exists latest_vehicle_at timestamptz;

-- NULL means legacy/not measured. Never backfill these fields with zero.
comment on column public.analytics_snapshots.congestion_reported_vehicle_count
  is 'Vehicles explicitly reporting GTFS congestion levels 1–4; NULL for legacy/unmeasured records.';
comment on column public.analytics_snapshots.fresh_vehicle_count
  is 'Position timestamps between captured_at minus 5 minutes and captured_at plus 60 seconds. App quality threshold, not an operator guarantee.';

create or replace function public.module5_daily_summaries(start_day date, end_day date)
returns jsonb language plpgsql stable security invoker set search_path = ''
as $$
declare result jsonb;
begin
  if start_day is null or end_day is null or end_day <= start_day or end_day - start_day > 63 then
    raise exception 'Choose a period of 1 to 63 days';
  end if;
  select coalesce(jsonb_agg(to_jsonb(d) order by d.service_date), '[]'::jsonb)
  into result from (
    select (s.bucket_start at time zone 'Asia/Kuala_Lumpur')::date as service_date,
      count(*) as sample_count,
      count(*) filter (where s.fetch_succeeded) as successful_sample_count,
      count(*) filter (where not s.fetch_succeeded) as failed_sample_count,
      avg(s.vehicle_count) filter (where s.fetch_succeeded) as average_vehicle_count,
      avg(s.route_count) filter (where s.fetch_succeeded) as average_route_count,
      avg(s.congested_vehicle_count) filter (where s.fetch_succeeded) as average_congested_vehicle_count,
      avg(s.severe_congestion_count) filter (where s.fetch_succeeded) as average_severe_congestion_count,
      -- Weight by known fresh vehicle observations, never by days or all buses.
      100.0 * sum(s.fresh_congested_vehicle_count) filter (where s.fetch_succeeded)
        / nullif(sum(s.fresh_congestion_reported_vehicle_count) filter (where s.fetch_succeeded), 0)
        as average_congestion_rate,
      100.0 * count(*) filter (where s.fetch_succeeded) / nullif(count(*), 0) as feed_success_rate,
      max(s.vehicle_count) filter (where s.fetch_succeeded) as peak_vehicle_count,
      max(s.congested_vehicle_count) filter (where s.fetch_succeeded) as peak_congested_vehicle_count,
      max(s.severe_congestion_count) filter (where s.fetch_succeeded) as peak_severe_congestion_count,
      count(*) filter (where s.fresh_vehicle_count is not null) as quality_sample_count,
      count(*) filter (where s.fetch_succeeded and s.vehicle_count = 0
        and s.fresh_vehicle_count is not null) as empty_sample_count,
      count(*) filter (where s.stale_vehicle_count > 0) as stale_sample_count,
      count(*) filter (where s.unknown_timestamp_vehicle_count > 0) as unknown_freshness_sample_count,
      sum(s.fresh_congestion_reported_vehicle_count) filter (where s.fetch_succeeded)
        as congestion_reported_observation_count
    from public.analytics_snapshots s
    where s.source = 'rapidkl_gtfs_realtime'
      and s.bucket_start >= (start_day::timestamp at time zone 'Asia/Kuala_Lumpur')
      and s.bucket_start < (end_day::timestamp at time zone 'Asia/Kuala_Lumpur')
    group by 1
  ) d;
  return result;
end;
$$;

-- Explicit projection: no private profiles, read state, preferences or push tokens.
-- Invoker security preserves the team's existing table privileges.
-- The notifications table is the shared PUBLIC service-alert archive.
-- Expiration hides an alert from the live inbox, not from historical reports.
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
      n.created_at, n.origin, n.severity, n.dedupe_key
    from public.notifications n
    where n.is_active = true and n.created_at >= start_at and n.created_at < end_at
      and n.created_at <= now()
    order by n.created_at, n.id
    limit 500 offset page_offset
  ) a;
  return result;
end;
$$;

-- Service-role-only writer. Repeated observations extend ONE alert instead
-- of adding a fresh notification every half hour/hour. Missing observations
-- are NOT treated as proof that a disruption has resolved.
create or replace function public.module5_record_congestion(
  route text, congested integer, severe integer, observed_at timestamptz
)
returns void language plpgsql security invoker set search_path = ''
as $$
declare current_id public.notifications.id%type;
declare route_key text := coalesce(nullif(trim(route), ''), 'Unknown route');
begin
  if congested is null or severe is null or congested <= 0 or severe < 0
      or severe > congested or observed_at is null
      or abs(extract(epoch from (now() - observed_at))) > 300 then
    raise exception 'Invalid congestion observation';
  end if;
  perform pg_advisory_xact_lock(hashtextextended('module5-congestion:' || route_key, 0));
  select n.id into current_id from public.notifications n
    where n.origin = 'appGenerated' and n.notification_type = 'crowd'
      and n.dedupe_key like 'congestion:%'
      and coalesce(n.route_id, 'Unknown route') = route_key
      and n.is_active and n.expires_at > observed_at
    order by n.created_at desc limit 1 for update;
  if current_id is not null then
    update public.notifications set expires_at = greatest(expires_at, observed_at + interval '2 hours')
      where id = current_id;
  else
    insert into public.notifications(
      notification_type, title, message, route_id, severity, origin,
      dedupe_key, created_at, expires_at, is_active
    ) values (
      'crowd',
      case when severe > 0 then 'Severe congestion reported' else 'Congestion reported' end,
      'The Rapid Bus KL feed reported ' || congested || ' congested vehicle(s) on ' ||
        route_key || '. Based on positions no more than 5 minutes old; not passenger crowding.',
      nullif(route_key, 'Unknown route'),
      case when severe > 0 then 'critical' else 'high' end,
      'appGenerated',
      'congestion:' || route_key || ':' || extract(epoch from observed_at)::text,
      observed_at, observed_at + interval '2 hours', true
    );
  end if;
end;
$$;

revoke all on function public.module5_daily_summaries(date, date) from public;
revoke all on function public.module5_alert_history(timestamptz, timestamptz, integer) from public;
revoke all on function public.module5_record_congestion(text, integer, integer, timestamptz)
  from public, anon, authenticated;
grant execute on function public.module5_daily_summaries(date, date) to anon, authenticated, service_role;
grant execute on function public.module5_alert_history(timestamptz, timestamptz, integer) to anon, authenticated, service_role;
grant execute on function public.module5_record_congestion(text, integer, integer, timestamptz) to service_role;

commit;
