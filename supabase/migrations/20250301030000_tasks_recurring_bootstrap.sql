-- Opgavekerne: skabeloner, gentagelser, daglige instanser og fuldførelser.
-- Kræver profiles + kids (bootstrap eller eksisterende skema).
-- Skal køre før 20250322000000_recurring_task_schedule.sql (ALTER recurring_tasks).

create table if not exists public.tasks (
  id uuid primary key default gen_random_uuid (),
  parent_id uuid not null references public.profiles (id) on delete cascade,
  title text not null,
  description text null,
  mode text not null,
  points_fixed int null,
  points_per_unit int null,
  require_approval boolean not null default false,
  emoji text null,
  created_at timestamptz not null default now (),
  constraint tasks_mode_check check (mode = any (array['fixed'::text, 'counter'::text]))
);

create index if not exists tasks_parent_id_idx on public.tasks (parent_id);

create table if not exists public.recurring_tasks (
  kid_id uuid not null references public.kids (id) on delete cascade,
  task_id uuid not null references public.tasks (id) on delete cascade,
  due_time text null,
  allow_upfront boolean not null default true,
  per_day_count int not null default 1,
  schedule_mode text not null default 'every_day',
  weekdays smallint[] null,
  specific_dates date[] null,
  primary key (kid_id, task_id),
  constraint recurring_tasks_schedule_mode_check check (
    schedule_mode = any (
      array[
        'every_day'::text,
        'weekdays'::text,
        'specific_dates'::text
      ]
    )
  )
);

create index if not exists recurring_tasks_kid_idx on public.recurring_tasks (kid_id);

create table if not exists public.task_instances (
  id uuid primary key default gen_random_uuid (),
  task_id uuid not null references public.tasks (id) on delete cascade,
  kid_id uuid not null references public.kids (id) on delete cascade,
  date date not null,
  due_time text null,
  allow_upfront boolean not null default false,
  status text not null default 'pending',
  required_completions int not null default 1,
  completions_done int not null default 0,
  unique (task_id, kid_id, date),
  constraint task_instances_status_check check (
    status = any (
      array[
        'pending'::text,
        'completed'::text,
        'needs_approval'::text,
        'approved'::text
      ]
    )
  )
);

create index if not exists task_instances_kid_date_idx on public.task_instances (kid_id, date);

create table if not exists public.task_completions (
  id uuid primary key default gen_random_uuid (),
  task_instance_id uuid not null references public.task_instances (id) on delete cascade,
  kid_id uuid not null references public.kids (id) on delete cascade,
  count_entered int null,
  points_awarded int not null,
  created_at timestamptz not null default now ()
);

create index if not exists task_completions_kid_idx on public.task_completions (kid_id);

create table if not exists public.settings (
  key text primary key,
  value text null
);

-- RLS
alter table public.tasks enable row level security;
alter table public.recurring_tasks enable row level security;
alter table public.task_instances enable row level security;
alter table public.task_completions enable row level security;
alter table public.settings enable row level security;

drop policy if exists "tasks_own_profile" on public.tasks;
create policy "tasks_own_profile" on public.tasks for all using (
  parent_id in (
    select id from public.profiles where auth_user_id = auth.uid ()
  )
)
with check (
  parent_id in (
    select id from public.profiles where auth_user_id = auth.uid ()
  )
);

drop policy if exists "recurring_tasks_own_kids" on public.recurring_tasks;
create policy "recurring_tasks_own_kids" on public.recurring_tasks for all using (
  kid_id in (
    select k.id
      from public.kids k
      join public.profiles p on p.id = k.parent_id
     where p.auth_user_id = auth.uid ()
  )
)
with check (
  kid_id in (
    select k.id
      from public.kids k
      join public.profiles p on p.id = k.parent_id
     where p.auth_user_id = auth.uid ()
  )
);

drop policy if exists "task_instances_own_kids" on public.task_instances;
create policy "task_instances_own_kids" on public.task_instances for all using (
  kid_id in (
    select k.id
      from public.kids k
      join public.profiles p on p.id = k.parent_id
     where p.auth_user_id = auth.uid ()
  )
)
with check (
  kid_id in (
    select k.id
      from public.kids k
      join public.profiles p on p.id = k.parent_id
     where p.auth_user_id = auth.uid ()
  )
);

drop policy if exists "task_completions_own_kids" on public.task_completions;
create policy "task_completions_own_kids" on public.task_completions for all using (
  kid_id in (
    select k.id
      from public.kids k
      join public.profiles p on p.id = k.parent_id
     where p.auth_user_id = auth.uid ()
  )
)
with check (
  kid_id in (
    select k.id
      from public.kids k
      join public.profiles p on p.id = k.parent_id
     where p.auth_user_id = auth.uid ()
  )
);

drop policy if exists "settings_authenticated_all" on public.settings;
create policy "settings_authenticated_all" on public.settings for all using (auth.role () = 'authenticated')
with check (auth.role () = 'authenticated');

comment on table public.tasks is 'Opgave-skabelon pr. forælderprofil.';
comment on table public.recurring_tasks is 'Plan for hvilke opgaver et barn har; materialiseres til task_instances.';
