-- Kopiér avatar_strengths til Atiach fra en donor-Alfamon (standard: Bezzle), så spilkort / vs computer virker.
-- Stadier mappes 1:1 efter sorteret rækkefølge (fx Atiach 0–3 ↔ donor 1–4).
-- Kræver: public.avatar_strengths, Atiach + avatar_stages (fx efter 20260502120000).
-- Idempotent: indsætter kun rækker der ikke allerede findes for Atiach.

DO $$
DECLARE
  v_atiach uuid;
  v_donor uuid;
  v_atiach_stages int;
  v_donor_stages int;
BEGIN
  IF to_regclass('public.avatar_strengths') IS NULL THEN
    RAISE NOTICE 'copy_atiach_strengths: tabellen avatar_strengths findes ikke — springer over.';
    RETURN;
  END IF;

  SELECT id INTO v_atiach FROM public.avatars WHERE lower(trim(name)) = 'atiach' LIMIT 1;

  IF v_atiach IS NULL THEN
    RAISE NOTICE 'copy_atiach_strengths: ingen avatar med navnet Atiach — springer over.';
    RETURN;
  END IF;

  SELECT count(*)::int INTO v_atiach_stages FROM public.avatar_stages WHERE avatar_id = v_atiach;

  IF v_atiach_stages = 0 THEN
    RAISE NOTICE 'copy_atiach_strengths: Atiach har ingen avatar_stages — springer over.';
    RETURN;
  END IF;

  SELECT a.id INTO v_donor
  FROM public.avatars a
  WHERE lower(trim(a.name)) = 'bezzle'
    AND EXISTS (SELECT 1 FROM public.avatar_strengths s WHERE s.avatar_id = a.id)
  LIMIT 1;

  IF v_donor IS NULL THEN
    SELECT a.id INTO v_donor
    FROM public.avatars a
    WHERE a.id <> v_atiach
      AND EXISTS (SELECT 1 FROM public.avatar_strengths s WHERE s.avatar_id = a.id)
    ORDER BY a.created_at
    LIMIT 1;
  END IF;

  IF v_donor IS NULL THEN
    RAISE NOTICE 'copy_atiach_strengths: ingen anden Alfamon med strengths at kopiere fra — springer over.';
    RETURN;
  END IF;

  SELECT count(DISTINCT stage_index)::int
  INTO v_donor_stages
  FROM public.avatar_strengths
  WHERE avatar_id = v_donor;

  IF v_donor_stages = 0 THEN
    RAISE NOTICE 'copy_atiach_strengths: donor mangler stage_index i strengths — springer over.';
    RETURN;
  END IF;

  INSERT INTO public.avatar_strengths (avatar_id, stage_index, strength_index, name, value)
  SELECT
    v_atiach,
    amap.atiach_stage,
    d.strength_index,
    d.name,
    d.value
  FROM public.avatar_strengths d
  INNER JOIN (
    SELECT
      a_st.stage_index AS atiach_stage,
      d_st.stage_index AS donor_stage
    FROM (
      SELECT stage_index, row_number() OVER (ORDER BY stage_index) AS rn
      FROM public.avatar_stages
      WHERE avatar_id = v_atiach
    ) a_st
    INNER JOIN (
      SELECT stage_index, row_number() OVER (ORDER BY stage_index) AS rn
      FROM (
        SELECT DISTINCT stage_index
        FROM public.avatar_strengths
        WHERE avatar_id = v_donor
      ) ds
    ) d_st ON a_st.rn = d_st.rn
  ) amap ON d.avatar_id = v_donor AND d.stage_index = amap.donor_stage
  WHERE NOT EXISTS (
    SELECT 1
    FROM public.avatar_strengths e
    WHERE e.avatar_id = v_atiach
      AND e.stage_index = amap.atiach_stage
      AND e.strength_index = d.strength_index
  );
END $$;
