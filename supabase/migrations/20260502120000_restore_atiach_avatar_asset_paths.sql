-- Genskab Atiach i databasen.
-- Æg (trin 0): base-URL som Bezzles æg (samme bucket/sti); filnavn sættes til stage-0-egg-1765290185001.jpg
-- i Storage (ikke Bezzles bitmap som fil).
-- (Ingen *kort0* i Flutter assets; kun kort1–4 som bundt-stier på trin 1–4 her.)
--
-- Virker både med og uden kolonnerne parent_id / points_per_stage på public.avatars.

DO $$
DECLARE
  v_id uuid;
  has_parent boolean;
  has_points boolean;
  v_bezzle_egg_url text;
  v_atiach_egg_url text;
BEGIN
  SELECT id INTO v_id FROM public.avatars WHERE lower(trim(name)) = 'atiach' LIMIT 1;

  IF v_id IS NULL THEN
    SELECT EXISTS (
      SELECT 1 FROM information_schema.columns
      WHERE table_schema = 'public' AND table_name = 'avatars' AND column_name = 'parent_id'
    ) INTO has_parent;

    SELECT EXISTS (
      SELECT 1 FROM information_schema.columns
      WHERE table_schema = 'public' AND table_name = 'avatars' AND column_name = 'points_per_stage'
    ) INTO has_points;

    IF has_parent AND has_points THEN
      INSERT INTO public.avatars (name, letter, parent_id, points_per_stage)
      SELECT 'Atiach', 'a', a.parent_id, COALESCE(a.points_per_stage, '{"0":10,"1":10,"2":10,"3":10}'::jsonb)
      FROM public.avatars a
      WHERE a.parent_id IS NOT NULL
      LIMIT 1
      RETURNING id INTO v_id;

      IF v_id IS NULL THEN
        INSERT INTO public.avatars (name, letter, parent_id, points_per_stage)
        SELECT 'Atiach', 'a', a.parent_id, COALESCE(a.points_per_stage, '{"0":10,"1":10,"2":10,"3":10}'::jsonb)
        FROM public.avatars a
        LIMIT 1
        RETURNING id INTO v_id;
      END IF;
    ELSIF has_parent THEN
      INSERT INTO public.avatars (name, letter, parent_id)
      SELECT 'Atiach', 'a', a.parent_id
      FROM public.avatars a
      WHERE a.parent_id IS NOT NULL
      LIMIT 1
      RETURNING id INTO v_id;

      IF v_id IS NULL THEN
        INSERT INTO public.avatars (name, letter, parent_id)
        SELECT 'Atiach', 'a', a.parent_id
        FROM public.avatars a
        LIMIT 1
        RETURNING id INTO v_id;
      END IF;
    END IF;

    IF v_id IS NULL THEN
      INSERT INTO public.avatars (name, letter)
      VALUES ('Atiach', 'a')
      RETURNING id INTO v_id;
    END IF;
  END IF;

  IF v_id IS NULL THEN
    RAISE EXCEPTION 'restore_atiach: kunne ikke oprette eller finde avatars-række for Atiach';
  END IF;

  -- Atiach æg (trin 0): fil i Storage skal hedde stage-0-egg-1765290185001.jpg — samme bucket/base som Bezzles æg-URL.
  SELECT nullif(trim(s.image_url), '') INTO v_bezzle_egg_url
  FROM public.avatar_stages s
  JOIN public.avatars a ON a.id = s.avatar_id AND lower(trim(a.name)) = 'bezzle'
  ORDER BY s.stage_index ASC
  LIMIT 1;

  -- Kun http(s) Storage-URL må bruges som skabelon — ellers ender vi i assets/stage-0-egg-...jpg som ikke findes i appen.
  IF v_bezzle_egg_url IS NOT NULL AND v_bezzle_egg_url ~ '^https?://' THEN
    v_atiach_egg_url := regexp_replace(
      v_bezzle_egg_url,
      '(^.*/)[^/?#]+',
      '\1stage-0-egg-1765290185001.jpg'
    );
  ELSE
    SELECT nullif(trim(s.image_url), '') INTO v_bezzle_egg_url
    FROM public.avatar_stages s
    WHERE s.image_url ~ '^https?://'
    ORDER BY s.stage_index ASC
    LIMIT 1;

    IF v_bezzle_egg_url IS NOT NULL AND v_bezzle_egg_url ~ '^https?://' THEN
      RAISE NOTICE 'restore_atiach: Bezzle har ikke http(s) æg — bruger vilkårlig Storage-URL som sti-skabelon til Atiach-æg.';
      v_atiach_egg_url := regexp_replace(
        v_bezzle_egg_url,
        '(^.*/)[^/?#]+',
        '\1stage-0-egg-1765290185001.jpg'
      );
    ELSE
      RAISE NOTICE 'restore_atiach: Ingen http(s) image_url i avatar_stages — bruger assets/Atiachkort1.webp til trin 0; upload stage-0-egg-1765290185001.jpg og opdater trin 0.';
      v_atiach_egg_url := 'assets/Atiachkort1.webp';
    END IF;
  END IF;

  INSERT INTO public.avatar_stages (avatar_id, stage_index, image_url)
  VALUES
    (v_id, 0, v_atiach_egg_url),
    (v_id, 1, 'assets/Atiachkort1.webp'),
    (v_id, 2, 'assets/Atiachkort2.webp'),
    (v_id, 3, 'assets/Atiachkort3.webp'),
    (v_id, 4, 'assets/Atiachkort4.webp')
  ON CONFLICT (avatar_id, stage_index) DO UPDATE SET image_url = EXCLUDED.image_url;
END $$;
