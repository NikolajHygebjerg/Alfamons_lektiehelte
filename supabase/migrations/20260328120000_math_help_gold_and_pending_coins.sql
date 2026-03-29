-- Matematik: fradrag ved hjælp + optjening som summerede guldmønter (ikke kun antal opgaver × fast sats).

alter table public.math_folders
  add column if not exists math_help_gold_cost integer null;

comment on column public.math_folders.math_help_gold_cost is
  'Fradrag i guld når barnet bruger matematikhjælp på opgaven; null = arv fra forældremappe (standard 1).';

alter table public.math_progress
  add column if not exists pending_gold_coins integer not null default 0;

comment on column public.math_progress.pending_gold_coins is
  'Sum af optjente guldmønter siden sidste Afslut. pending_gold_tasks bruges kun som ældre fallback.';

comment on column public.math_folders.gold_coins_per_task is
  'Guld uden matematikhjælp pr. rigtig opgave; null = arv (standard 2 i rod).';
