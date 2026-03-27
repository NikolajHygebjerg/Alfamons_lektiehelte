-- Giver platform-admin (app_role = admin) ud fra email i auth.users.
-- Bruger upsert: virker også hvis profil-rækken mangler (fx gammel konto uden trigger).
insert into public.profiles (auth_user_id, app_role)
select u.id, 'admin'::text
from auth.users u
where lower(trim(u.email)) in (
  'nikolaj@idevaerket.dk',
  'nikolaj@idevaaerket.dk',
  'nikolaj@begejstring.dk'
)
on conflict (auth_user_id) do update
set app_role = excluded.app_role;
