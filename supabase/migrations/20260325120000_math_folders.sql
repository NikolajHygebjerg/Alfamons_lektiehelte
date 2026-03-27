-- Matematik: mappe-træ, opgaver pr. mappe, barnets fremskridt og tildelte børn pr. mappe.
-- Idempotent: kan køres igen hvis tabeller allerede findes (fx delvist kørt migration).

create table if not exists public.math_folders (
  id uuid primary key default gen_random_uuid (),
  profile_id uuid not null references public.profiles (id) on delete cascade,
  parent_id uuid references public.math_folders (id) on delete cascade,
  title text not null,
  gold_coins_per_task integer null,
  sort_order integer not null default 0,
  created_at timestamptz not null default now ()
);

create index if not exists math_folders_profile_parent_idx on public.math_folders (profile_id, parent_id);

create or replace function public.math_folders_parent_profile_match ()
  returns trigger
  language plpgsql
  as $$
begin
  if new.parent_id is not null then
    if not exists (
      select 1
        from public.math_folders p
       where p.id = new.parent_id
         and p.profile_id = new.profile_id
    ) then
      raise exception 'math_folders: forældremappe skal høre til samme profil';
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists math_folders_parent_profile_match_trg on public.math_folders;
create trigger math_folders_parent_profile_match_trg
  before insert or update of parent_id, profile_id on public.math_folders
  for each row
  execute function public.math_folders_parent_profile_match ();

create table if not exists public.math_folder_kids (
  folder_id uuid not null references public.math_folders (id) on delete cascade,
  kid_id uuid not null references public.kids (id) on delete cascade,
  primary key (folder_id, kid_id)
);

create index if not exists math_folder_kids_kid_idx on public.math_folder_kids (kid_id);

create table if not exists public.math_tasks (
  id uuid primary key default gen_random_uuid (),
  folder_id uuid not null references public.math_folders (id) on delete cascade,
  prompt text not null,
  answer text not null,
  sort_order integer not null default 0,
  created_at timestamptz not null default now ()
);

create index if not exists math_tasks_folder_idx on public.math_tasks (folder_id);

create table if not exists public.math_progress (
  kid_id uuid not null references public.kids (id) on delete cascade,
  folder_id uuid not null references public.math_folders (id) on delete cascade,
  next_task_index integer not null default 0,
  pending_gold_tasks integer not null default 0,
  updated_at timestamptz not null default now (),
  primary key (kid_id, folder_id)
);

create index if not exists math_progress_folder_idx on public.math_progress (folder_id);

alter table public.points_ledger
  drop constraint if exists points_ledger_source_check;

alter table public.points_ledger
  add constraint points_ledger_source_check
  check (
    source = any (
      array[
        'task'::text,
        'daily_bonus'::text,
        'book'::text,
        'gold_earn'::text,
        'math'::text
      ]
    )
  );

comment on table public.math_folders is 'Matematikmapper; gold_coins_per_task null = brug værdi fra forældremappe (eller 1 på rodniveau).';
comment on column public.math_progress.pending_gold_tasks is 'Korrekt løst siden sidste Afslut; udbetales ved Afslut som pending * effektiv_sats.';

-- RLS
alter table public.math_folders enable row level security;
alter table public.math_folder_kids enable row level security;
alter table public.math_tasks enable row level security;
alter table public.math_progress enable row level security;

drop policy if exists math_folders_select on public.math_folders;
create policy math_folders_select on public.math_folders
  for select using (
    profile_id in (
      select id from public.profiles where auth_user_id = auth.uid ()
    )
  );

drop policy if exists math_folders_write on public.math_folders;
create policy math_folders_write on public.math_folders
  for insert with check (
    profile_id in (
      select id from public.profiles where auth_user_id = auth.uid ()
    )
  );

drop policy if exists math_folders_update on public.math_folders;
create policy math_folders_update on public.math_folders
  for update using (
    profile_id in (
      select id from public.profiles where auth_user_id = auth.uid ()
    )
  )
  with check (
    profile_id in (
      select id from public.profiles where auth_user_id = auth.uid ()
    )
  );

drop policy if exists math_folders_delete on public.math_folders;
create policy math_folders_delete on public.math_folders
  for delete using (
    profile_id in (
      select id from public.profiles where auth_user_id = auth.uid ()
    )
  );

drop policy if exists math_folder_kids_all on public.math_folder_kids;
create policy math_folder_kids_all on public.math_folder_kids
  for all using (
    exists (
      select 1
        from public.math_folders f
        join public.profiles pr on pr.id = f.profile_id
       where f.id = math_folder_kids.folder_id
         and pr.auth_user_id = auth.uid ()
    )
    and exists (
      select 1
        from public.kids k
        join public.profiles pr on pr.id = k.parent_id
       where k.id = math_folder_kids.kid_id
         and pr.auth_user_id = auth.uid ()
    )
  )
  with check (
    exists (
      select 1
        from public.math_folders f
        join public.profiles pr on pr.id = f.profile_id
       where f.id = math_folder_kids.folder_id
         and pr.auth_user_id = auth.uid ()
    )
    and exists (
      select 1
        from public.kids k
        join public.profiles pr on pr.id = k.parent_id
       where k.id = math_folder_kids.kid_id
         and pr.auth_user_id = auth.uid ()
    )
  );

drop policy if exists math_tasks_all on public.math_tasks;
create policy math_tasks_all on public.math_tasks
  for all using (
    exists (
      select 1
        from public.math_folders f
        join public.profiles pr on pr.id = f.profile_id
       where f.id = math_tasks.folder_id
         and pr.auth_user_id = auth.uid ()
    )
  )
  with check (
    exists (
      select 1
        from public.math_folders f
        join public.profiles pr on pr.id = f.profile_id
       where f.id = math_tasks.folder_id
         and pr.auth_user_id = auth.uid ()
    )
  );

drop policy if exists math_progress_all on public.math_progress;
create policy math_progress_all on public.math_progress
  for all using (
    exists (
      select 1
        from public.kids k
        join public.profiles pr on pr.id = k.parent_id
       where k.id = math_progress.kid_id
         and pr.auth_user_id = auth.uid ()
    )
  )
  with check (
    exists (
      select 1
        from public.kids k
        join public.profiles pr on pr.id = k.parent_id
       where k.id = math_progress.kid_id
         and pr.auth_user_id = auth.uid ()
    )
  );
