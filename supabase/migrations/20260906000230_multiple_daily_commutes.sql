begin;

alter table public.daily_commutes
  add column if not exists id uuid default gen_random_uuid();

update public.daily_commutes
set id = gen_random_uuid()
where id is null;

alter table public.daily_commutes
  alter column id set default gen_random_uuid(),
  alter column id set not null;

alter table public.daily_commutes
  drop constraint if exists daily_commutes_pkey;

alter table public.daily_commutes
  add constraint daily_commutes_pkey primary key (id);

create index if not exists daily_commutes_user_updated_idx
  on public.daily_commutes (user_id, updated_at desc);

revoke all on public.daily_commutes from anon;
grant select, insert, update, delete on public.daily_commutes to authenticated;
alter table public.daily_commutes disable row level security;

commit;
