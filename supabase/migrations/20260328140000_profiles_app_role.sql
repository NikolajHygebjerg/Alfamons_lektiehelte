-- Rolle pr. forælderprofil: admin = fuld adgang (bogbuilder, brugerstyring), user = almindelig.

alter table public.profiles
  add column if not exists app_role text not null default 'user'
  constraint profiles_app_role_check check (app_role in ('admin', 'user'));

comment on column public.profiles.app_role is 'admin: bogbuilder + brugerstyring; user: øvrig admin uden disse.';

-- Kendte platform-administratorer (bogbuilder-behov for begejstring bevares).
update public.profiles p
set app_role = 'admin'
where p.auth_user_id in (
  select id
  from auth.users
  where lower(trim(email)) in (
    'nikolaj@idevaerket.dk',
    'nikolaj@begejstring.dk'
  )
);

drop policy if exists "profiles_select_own" on public.profiles;
create policy "profiles_select_own"
  on public.profiles for select
  using (
    auth.uid () = auth_user_id
    or exists (
      select 1
      from public.profiles p
      where p.auth_user_id = auth.uid ()
        and p.app_role = 'admin'
    )
  );

create or replace function public.profiles_enforce_role_change ()
  returns trigger
  language plpgsql
  security definer
  set search_path = public
  as $$
begin
  if new.app_role is distinct from old.app_role then
    if auth.uid () is not null then
      if not exists (
        select 1
        from public.profiles p
        where p.auth_user_id = auth.uid ()
          and p.app_role = 'admin'
      ) then
        raise exception 'Kun administratorer kan ændre app_role';
      end if;
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists profiles_enforce_role_change_trg on public.profiles;
create trigger profiles_enforce_role_change_trg
  before update on public.profiles for each row
  execute function public.profiles_enforce_role_change ();
