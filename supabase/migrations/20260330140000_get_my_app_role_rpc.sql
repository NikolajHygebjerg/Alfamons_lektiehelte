-- Læser app_role for den indloggede bruger uden at afhænge af direkte SELECT + RLS fra klienten.
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
