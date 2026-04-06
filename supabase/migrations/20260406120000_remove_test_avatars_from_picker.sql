-- Fjern manuelt indtastede test-Alfamons (fx eksterne Pokémon-URL'er i avatar_stages), som ikke hører til produktion.
-- Navneliste matcher typisk fejl/QA i alfamon-vælgeren (ekskakt match på lower(trim(name)) — fx Tegorm påvirkes ikke).
-- Rækkefølge: nullér FK i kid_match_rounds, fjern barn-/unlock-rækker, slet avatars (avatar_stages cascader).

BEGIN;

CREATE TEMP TABLE _junk_avatar_ids (id uuid PRIMARY KEY) ON COMMIT DROP;

INSERT INTO _junk_avatar_ids (id)
SELECT a.id
FROM public.avatars a
WHERE lower(trim(a.name)) IN (
  'testererer',
  'tes',
  'te',
  'tast',
  'ta',
  'simulat',
  'ok',
  'atiachtest',
  'kla'
);

UPDATE public.kids k
SET avatar_url = NULL
WHERE k.avatar_url IS NOT NULL
  AND EXISTS (
    SELECT 1
    FROM public.avatar_stages ast
    WHERE ast.avatar_id IN (SELECT j.id FROM _junk_avatar_ids j)
      AND ast.image_url IS NOT NULL
      AND ast.image_url <> ''
      AND k.avatar_url = ast.image_url
  );

UPDATE public.kid_match_rounds r
SET kid1_avatar_id = NULL
WHERE r.kid1_avatar_id IN (SELECT id FROM _junk_avatar_ids);

UPDATE public.kid_match_rounds r
SET kid2_avatar_id = NULL
WHERE r.kid2_avatar_id IN (SELECT id FROM _junk_avatar_ids);

DO $$
BEGIN
  IF to_regclass('public.kid_active_avatar') IS NOT NULL THEN
    DELETE FROM public.kid_active_avatar
    WHERE avatar_id IN (SELECT id FROM _junk_avatar_ids);
  END IF;
END $$;

DO $$
BEGIN
  IF to_regclass('public.kid_avatar_history') IS NOT NULL THEN
    DELETE FROM public.kid_avatar_history
    WHERE avatar_id IN (SELECT id FROM _junk_avatar_ids);
  END IF;
END $$;

DO $$
BEGIN
  IF to_regclass('public.kid_unlocked_alphamons') IS NOT NULL THEN
    DELETE FROM public.kid_unlocked_alphamons
    WHERE avatar_id IN (SELECT id FROM _junk_avatar_ids);
  END IF;
END $$;

DO $$
BEGIN
  IF to_regclass('public.kid_avatar_library') IS NOT NULL THEN
    DELETE FROM public.kid_avatar_library
    WHERE avatar_id IN (SELECT id FROM _junk_avatar_ids);
  END IF;
END $$;

DELETE FROM public.avatars
WHERE id IN (SELECT id FROM _junk_avatar_ids);

COMMIT;
