-- Atiach trin 0: tidligere migration kunne sætte image_url til assets/stage-0-egg-1765290185001.jpg
-- (når Bezzles æg var assets/… — filen findes ikke i Flutter). Ret til rigtig Storage-URL.
--
-- Kræver mindst én anden avatar_stages-række med http(s) image_url (typisk Bezzles æg i Storage).

DO $$
DECLARE
  v_atiach uuid;
  v_template text;
  v_new text;
BEGIN
  SELECT id INTO v_atiach FROM public.avatars WHERE lower(trim(name)) = 'atiach' LIMIT 1;
  IF v_atiach IS NULL THEN
    RETURN;
  END IF;

  SELECT nullif(trim(s.image_url), '') INTO v_template
  FROM public.avatar_stages s
  JOIN public.avatars a ON a.id = s.avatar_id AND lower(trim(a.name)) = 'bezzle'
  ORDER BY s.stage_index ASC
  LIMIT 1;

  IF v_template IS NULL OR v_template !~ '^https?://' THEN
    SELECT nullif(trim(s.image_url), '') INTO v_template
    FROM public.avatar_stages s
    WHERE s.image_url ~ '^https?://'
    ORDER BY s.stage_index ASC
    LIMIT 1;
  END IF;

  IF v_template IS NULL OR v_template !~ '^https?://' THEN
    RAISE NOTICE 'fix_atiach_egg: ingen http(s) skabelon — kør manuelt UPDATE på avatar_stages for Atiach trin 0.';
    RETURN;
  END IF;

  v_new := regexp_replace(
    v_template,
    '(^.*/)[^/?#]+',
    '\1stage-0-egg-1765290185001.jpg'
  );

  UPDATE public.avatar_stages s
  SET image_url = v_new
  WHERE s.avatar_id = v_atiach
    AND s.stage_index = 0
    AND s.image_url LIKE 'assets/stage-0-egg%';
END $$;
