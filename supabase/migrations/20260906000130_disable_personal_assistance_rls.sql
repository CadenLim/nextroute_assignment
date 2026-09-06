begin;

-- This assignment intentionally keeps RLS disabled for its application tables.
-- Avatar access remains protected separately by policies on storage.objects.
do $$
declare
  target_table text;
  existing_policy record;
begin
  foreach target_table in array array[
    'profiles',
    'saved_routes',
    'daily_commutes',
    'navigation_history'
  ]
  loop
    if to_regclass(format('public.%I', target_table)) is null then
      continue;
    end if;

    execute format(
      'alter table public.%I disable row level security',
      target_table
    );
    execute format('revoke all on table public.%I from anon', target_table);
    execute format(
      'grant select, insert, update, delete on table public.%I to authenticated',
      target_table
    );

    for existing_policy in
      select policyname
      from pg_policies
      where schemaname = 'public'
        and tablename = target_table
    loop
      execute format(
        'drop policy %I on public.%I',
        existing_policy.policyname,
        target_table
      );
    end loop;
  end loop;
end
$$;

commit;
