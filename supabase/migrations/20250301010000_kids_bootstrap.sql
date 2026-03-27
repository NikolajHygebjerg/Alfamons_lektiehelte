-- Grundskema: børn tilknyttet forælder-profil ([profiles.id] som parent_id).
-- Kør efter 20250301000000_profiles_bootstrap.sql. Guld kommer også ud fra 20250322140000 (add column if not exists).

create table if not exists public.kids (
  id uuid primary key default gen_random_uuid (),
  parent_id uuid not null references public.profiles (id) on delete cascade,
  name text not null,
  avatar_url text null,
  pin_code text null,
  gold_coins integer not null default 0,
  created_at timestamptz not null default now()
);

create index if not exists kids_parent_id_idx on public.kids (parent_id);

alter table public.kids enable row level security;

drop policy if exists "kids_select_own" on public.kids;
create policy "kids_select_own" on public.kids for select using (
  parent_id in (
    select id from public.profiles where auth_user_id = auth.uid ()
  )
);

drop policy if exists "kids_insert_own" on public.kids;
create policy "kids_insert_own" on public.kids for insert with check (
  parent_id in (
    select id from public.profiles where auth_user_id = auth.uid ()
  )
);

drop policy if exists "kids_update_own" on public.kids;
create policy "kids_update_own" on public.kids for update using (
  parent_id in (
    select id from public.profiles where auth_user_id = auth.uid ()
  )
)
with check (
  parent_id in (
    select id from public.profiles where auth_user_id = auth.uid ()
  )
);

drop policy if exists "kids_delete_own" on public.kids;
create policy "kids_delete_own" on public.kids for delete using (
  parent_id in (
    select id from public.profiles where auth_user_id = auth.uid ()
  )
);

comment on table public.kids is 'Barn under en forælder-profil; bruges i appen til session, opgaver, matematik m.m.';
