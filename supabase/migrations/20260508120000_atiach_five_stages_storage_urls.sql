-- Atiach: alle 5 udviklingstrin som offentlige Storage-URL'er (samme mappe som jeres uploads).
-- Afvikles på [avatars]-rækken med lower(name) = 'atiach'. Opdater eksisterende [avatar_stages] via ON CONFLICT.

DO $$
DECLARE
  v_id uuid;
  n_dup int;
  base text := 'https://bdsnfnwcnfnszgdqbapo.supabase.co/storage/v1/object/public/avatars/4f515a78-71c2-48ed-a476-965f5171e208/';
BEGIN
  SELECT count(*)::int INTO n_dup FROM public.avatars WHERE lower(trim(name)) = 'atiach';
  IF n_dup > 1 THEN
    RAISE NOTICE 'atiach_five_stages: der findes % Atiach-rækker i avatars — rens dubletter og kør evt. manuelt UPDATE.', n_dup;
  END IF;

  SELECT id INTO v_id FROM public.avatars WHERE lower(trim(name)) = 'atiach' ORDER BY created_at ASC LIMIT 1;
  IF v_id IS NULL THEN
    RAISE NOTICE 'atiach_five_stages: ingen avatars-række med name Atiach — springer over.';
    RETURN;
  END IF;

  INSERT INTO public.avatar_stages (avatar_id, stage_index, image_url)
  VALUES
    (v_id, 0, base || 'stage-0-egg-1765290185001.jpg'),
    (v_id, 1, base || 'stage-1-1765290185885.jpg'),
    (v_id, 2, base || 'stage-2-1765290186270.jpg'),
    (v_id, 3, base || 'stage-3-1765290186876.jpg'),
    (v_id, 4, base || 'stage-4-1765290187573.jpg')
  ON CONFLICT (avatar_id, stage_index) DO UPDATE SET image_url = EXCLUDED.image_url;
END $$;
