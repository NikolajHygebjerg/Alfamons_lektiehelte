-- Alfamon / Alfamons: kort og udviklingsstadier. Kræves af bl.a. kid_match_rounds (FK til avatars).
-- Fuld seed af kort/billeder kommer ofte fra produktion eller manuelt i dashboard.

create table if not exists public.avatars (
  id uuid primary key default gen_random_uuid (),
  name text not null,
  letter text null,
  created_at timestamptz not null default now ()
);

create table if not exists public.avatar_stages (
  id uuid primary key default gen_random_uuid (),
  avatar_id uuid not null references public.avatars (id) on delete cascade,
  stage_index int not null,
  image_url text null,
  unique (avatar_id, stage_index)
);

create index if not exists avatar_stages_avatar_id_idx on public.avatar_stages (avatar_id);

alter table public.avatars enable row level security;
alter table public.avatar_stages enable row level security;

drop policy if exists "authenticated_all_avatars" on public.avatars;
create policy "authenticated_all_avatars" on public.avatars for all using (auth.role () = 'authenticated')
with check (auth.role () = 'authenticated');

drop policy if exists "authenticated_all_avatar_stages" on public.avatar_stages;
create policy "authenticated_all_avatar_stages" on public.avatar_stages for all using (auth.role () = 'authenticated')
with check (auth.role () = 'authenticated');

comment on table public.avatars is 'Alfamon-kort (bokstav, navn); refereres fra spil og kampe.';
comment on table public.avatar_stages is 'Udviklingsstadier med billede-URL pr. avatar.';
