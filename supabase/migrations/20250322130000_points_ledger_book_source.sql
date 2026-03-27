-- Appen bruger source = 'book' ved TaskCompletionService.awardBookPoints (læst bog).
-- Inkluder også gold_earn og math så eksisterende rækker (fra senere app-features)
-- ikke bryder check ved push på databaser hvor data allerede findes.
alter table public.points_ledger
  drop constraint if exists points_ledger_source_check;

-- Legacy / manuelle rækker med andre kilder end appen bruger i dag
update public.points_ledger
set source = 'task'
where source is not null
  and source not in (
    'task',
    'daily_bonus',
    'book',
    'gold_earn',
    'math'
  );

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

comment on constraint points_ledger_source_check on public.points_ledger is
  'task, daily_bonus, book, gold_earn, math — se nyere migrations for fuld liste';
