begin;

-- Preserve each existing reminder's calculated leave time while changing the
-- meaning of the legacy column from arrival time to user-selected departure.
update public.daily_commutes
set
  arrive_by = arrive_by - make_interval(mins => estimated_duration_minutes),
  active_days = case
    when extract(epoch from arrive_by) < estimated_duration_minutes * 60 then
      array(
        select (case when day = 1 then 7 else day - 1 end)::smallint
        from unnest(active_days) as active_day(day)
        order by case when day = 1 then 7 else day - 1 end
      )
    else active_days
  end,
  updated_at = now();

comment on column public.daily_commutes.arrive_by is
  'Legacy column name retained for compatibility; stores the user-selected departure time.';

commit;
