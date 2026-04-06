-- Atiach trin 0 (æg): peg på stage-0-egg-1765290185001.jpg i samme Storage bucket/sti som Bezzles æg (kun filnavnet skiftes).

DO $$
DECLARE
  v_atiach uuid;
  v_bezzle_egg text;
  v_new text;
  v_min_stage int;
BEGIN
  SELECT id INTO v_atiach FROM public.avatars WHERE lower(trim(name)) = 'atiach' LIMIT 1;
  IF v_atiach IS NULL THEN
    RETURN;
  END IF;

  SELECT min(s.stage_index) INTO v_min_stage
  FROM public.avatar_stages s
  WHERE s.avatar_id = v_atiach;

  IF v_min_stage IS NULL THEN
    RETURN;
  END IF;

  SELECT nullif(trim(s.image_url), '') INTO v_bezzle_egg
  FROM public.avatar_stages s
  JOIN public.avatars a ON a.id = s.avatar_id AND lower(trim(a.name)) = 'bezzle'
  ORDER BY s.stage_index ASC
  LIMIT 1;

  IF v_bezzle_egg IS NULL OR v_bezzle_egg !~ '^https?://' THEN
    SELECT nullif(trim(s.image_url), '') INTO v_bezzle_egg
    FROM public.avatar_stages s
    WHERE s.image_url ~ '^https?://'
    ORDER BY s.stage_index ASC
    LIMIT 1;
  END IF;

  IF v_bezzle_egg IS NULL OR v_bezzle_egg !~ '^https?://' THEN
    RAISE NOTICE 'atiach_egg_derive: ingen http(s) skabelon-URL — springer over.';
    RETURN;
  END IF;

  v_new := regexp_replace(
    v_bezzle_egg,
    '(^.*/)[^/?#]+',
    '\1stage-0-egg-1765290185001.jpg'
  );

  UPDATE public.avatar_stages s
  SET image_url = v_new
  WHERE s.avatar_id = v_atiach
    AND s.stage_index = v_min_stage;
END $$;
