-- Kort log over guldmønt-transaktioner (kiste). Start-constraint matcher forhistorik før 20250322130000;
-- derefter udvider 20250322130000 (book), 20250322140000 (gold_earn) og 20260325120000 (math).

create table if not exists public.points_ledger (
  id uuid primary key default gen_random_uuid (),
  kid_id uuid not null references public.kids (id) on delete cascade,
  source text not null,
  task_completion_id uuid null,
  delta_points integer not null,
  balance_after integer not null,
  created_at timestamptz not null default now (),
  constraint points_ledger_source_check check (
    source = any (
      array['task'::text, 'daily_bonus'::text]
    )
  )
);

create index if not exists points_ledger_kid_id_idx on public.points_ledger (kid_id);
create index if not exists points_ledger_kid_created_idx on public.points_ledger (kid_id, created_at desc);

alter table public.points_ledger enable row level security;

drop policy if exists "points_ledger_select_own_kids" on public.points_ledger;
create policy "points_ledger_select_own_kids" on public.points_ledger for select using (
  kid_id in (
    select k.id
      from public.kids k
      join public.profiles p on p.id = k.parent_id
     where p.auth_user_id = auth.uid ()
  )
);

drop policy if exists "points_ledger_insert_own_kids" on public.points_ledger;
create policy "points_ledger_insert_own_kids" on public.points_ledger for insert with check (
  kid_id in (
    select k.id
      from public.kids k
      join public.profiles p on p.id = k.parent_id
     where p.auth_user_id = auth.uid ()
  )
);

comment on table public.points_ledger is 'Guldmønt-ledger (delta + saldo i kiste efter transaktion).';
