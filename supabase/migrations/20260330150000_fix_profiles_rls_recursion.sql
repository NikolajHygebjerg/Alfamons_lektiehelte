-- RLS på profiles brugte EXISTS (SELECT … FROM profiles …), hvilket evaluerer SELECT-politikken
-- igen → "infinite recursion detected in policy for relation profiles".
-- Løsning: SECURITY DEFINER-funktion (kører som ejer og bypass’er RLS ved det interne opslag).

create or replace function public.current_user_is_app_admin ()
  returns boolean
  language sql
  stable
  security definer
  set search_path = public
  as $$
  select exists (
    select 1
    from public.profiles p
    where p.auth_user_id = auth.uid ()
      and p.app_role = 'admin'
  );
$$;

comment on function public.current_user_is_app_admin () is 'Sand hvis auth.uid har profiles.app_role=admin; brug i RLS (undgår rekursion).';

revoke all on function public.current_user_is_app_admin () from public;
grant execute on function public.current_user_is_app_admin () to authenticated;

drop policy if exists "profiles_select_own" on public.profiles;
create policy "profiles_select_own"
  on public.profiles for select
  using (
    auth.uid () = auth_user_id
    or public.current_user_is_app_admin ()
  );

-- Trigger: samme logik via funktion (konsistent, undgår evt. edge cases).
create or replace function public.profiles_enforce_role_change ()
  returns trigger
  language plpgsql
  security definer
  set search_path = public
  as $$
begin
  if new.app_role is distinct from old.app_role then
    if auth.uid () is not null then
      if not public.current_user_is_app_admin () then
        raise exception 'Kun administratorer kan ændre app_role';
      end if;
    end if;
  end if;
  return new;
end;
$$;

-- RPC til klient (PostgREST) – opret/erstat så schema-cache kan finde den.
create or replace function public.get_my_app_role ()
  returns text
  language sql
  stable
  security definer
  set search_path = public
  as $$
  select coalesce(
    (
      select p.app_role::text
      from public.profiles p
      where p.auth_user_id = auth.uid ()
      limit 1
    ),
    'user'
  );
$$;

comment on function public.get_my_app_role () is 'Returnerer profiles.app_role for auth.uid(); default user hvis ingen profil.';

revoke all on function public.get_my_app_role () from public;
grant execute on function public.get_my_app_role () to authenticated;

notify pgrst, 'reload schema';
