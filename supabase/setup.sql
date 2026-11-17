-- Seaside seating planner: shared online save.
-- Run once in the Supabase SQL editor. Replace the two emails at the bottom
-- (lowercase) before running. Guest data never goes in this file: the plan
-- row starts empty and is filled from the app.

create table public.plans (
  id text primary key,
  json jsonb not null,
  rev bigint not null default 1,
  updated_at timestamptz not null default now(),
  updated_by text
);
create table public.plan_members (
  plan_id text not null references public.plans(id) on delete cascade,
  email text not null,
  primary key (plan_id, email)
);
alter table public.plans enable row level security;
alter table public.plan_members enable row level security;

create policy "member reads own membership" on public.plan_members
  for select to authenticated using (email = lower(auth.jwt() ->> 'email'));
create policy "members read plan" on public.plans
  for select to authenticated using (exists (select 1 from public.plan_members m where m.plan_id = plans.id and m.email = lower(auth.jwt() ->> 'email')));
create policy "members update plan" on public.plans
  for update to authenticated
  using (exists (select 1 from public.plan_members m where m.plan_id = plans.id and m.email = lower(auth.jwt() ->> 'email')))
  with check (exists (select 1 from public.plan_members m where m.plan_id = plans.id and m.email = lower(auth.jwt() ->> 'email')));
-- No insert or delete policies: the app can only read and update the one row.

-- Live updates for the other partner's screen
alter publication supabase_realtime add table public.plans;

-- One empty plan and its two members
insert into public.plans (id, json) values ('our-wedding', '{}'::jsonb);
insert into public.plan_members values
  ('our-wedding', 'partner1@example.com'),
  ('our-wedding', 'partner2@example.com');
