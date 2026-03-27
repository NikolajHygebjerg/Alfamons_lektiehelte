-- Grundskema: profiles knytter auth.users til appens profil-id (bruges af kids, shop, math m.m.).
-- Kør denne FØR øvrige migrations hvis tabellen mangler (fx kun Flutter-repo migrations på tom database).
-- Fuld Alfamon-skema kan også komme fra Dopaminos-projektets supabase-migrationer.

create table if not exists public.profiles (
  id uuid primary key default gen_random_uuid (),
  auth_user_id uuid not null unique references auth.users (id) on delete cascade,
  created_at timestamptz not null default now()
);

create index if not exists profiles_auth_user_id_idx on public.profiles (auth_user_id);

alter table public.profiles enable row level security;

drop policy if exists "profiles_select_own" on public.profiles;
create policy "profiles_select_own" on public.profiles for select using (auth.uid () = auth_user_id);

drop policy if exists "profiles_insert_own" on public.profiles;
create policy "profiles_insert_own" on public.profiles for insert with check (auth.uid () = auth_user_id);

drop policy if exists "profiles_update_own" on public.profiles;
create policy "profiles_update_own" on public.profiles for update using (auth.uid () = auth_user_id)
with check (auth.uid () = auth_user_id);

-- Opret profil automatisk ved ny bruger (email/signup).
create or replace function public.handle_new_user_profile ()
  returns trigger
  language plpgsql
  security definer
  set search_path = public
  as $$
begin
  insert into public.profiles (auth_user_id)
    values (new.id)
  on conflict (auth_user_id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created_profile on auth.users;
create trigger on_auth_user_created_profile
  after insert on auth.users for each row
  execute function public.handle_new_user_profile ();

-- Eksisterende auth.users uden profil (én gang efter deploy).
insert into public.profiles (auth_user_id)
  select id
    from auth.users u
   where not exists (
      select 1 from public.profiles p where p.auth_user_id = u.id
    );

comment on table public.profiles is 'Forælder/konto-profil; id bruges som foreign key (fx kids.parent_id).';
