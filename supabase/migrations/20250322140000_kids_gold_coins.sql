-- Guldmønter: samles i kisten (kids.gold_coins), tildeles Alfamons manuelt fra Alfamons-skærmen.
alter table public.kids
  add column if not exists gold_coins integer not null default 0;

comment on column public.kids.gold_coins is 'Ufordelte guldmønter (belønninger). Overføres til alfamon via kid_avatar_library.points_current.';

-- Ledger: gold_earn = opgave/bog m.m. (balance_after = guldmønter i kiste efter transaktion).
alter table public.points_ledger
  drop constraint if exists points_ledger_source_check;

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
