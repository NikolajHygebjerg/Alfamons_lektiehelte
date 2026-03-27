-- Superadmin: fuld app-adgang (app_role = admin). Inkl. begge stavevarianter af email.
update public.profiles p
set app_role = 'admin'
where p.auth_user_id in (
  select id
  from auth.users
  where lower(trim(email)) in (
    'nikolaj@idevaaerket.dk',
    'nikolaj@idevaerket.dk'
  )
);
