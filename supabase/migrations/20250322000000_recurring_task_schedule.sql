-- Planlægning af tilbagevendende opgaver per barn
-- Kør i Supabase SQL Editor hvis migration ikke kører automatisk.
--
-- AFHÆNGIGHED: 20250301030000_tasks_recurring_bootstrap.sql (opretter recurring_tasks).

alter table public.recurring_tasks
  add column if not exists schedule_mode text not null default 'every_day';

alter table public.recurring_tasks
  drop constraint if exists recurring_tasks_schedule_mode_check;

alter table public.recurring_tasks
  add constraint recurring_tasks_schedule_mode_check
  check (schedule_mode in ('every_day', 'weekdays', 'specific_dates'));

alter table public.recurring_tasks
  add column if not exists weekdays smallint[] default null;

comment on column public.recurring_tasks.weekdays is 'ISO ugedag 1=mandag … 7=søndag. Bruges når schedule_mode = weekdays.';

alter table public.recurring_tasks
  add column if not exists specific_dates date[] default null;

comment on column public.recurring_tasks.specific_dates is 'Konkrete datoer når schedule_mode = specific_dates.';
