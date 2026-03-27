-- Lydbibliotek: ord med optaget lyd til brug i Læs-let bøger
-- Ord gemmes lowercase for case-insensitive matching i bogtekster

CREATE TABLE IF NOT EXISTS audio_library (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  word text NOT NULL,
  audio_url text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_audio_library_word_lower ON audio_library (lower(word));

ALTER TABLE audio_library ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Authenticated read audio_library" ON audio_library;
CREATE POLICY "Authenticated read audio_library" ON audio_library
  FOR SELECT USING (auth.role() = 'authenticated');

DROP POLICY IF EXISTS "Authenticated all audio_library" ON audio_library;
CREATE POLICY "Authenticated all audio_library" ON audio_library
  FOR ALL USING (auth.role() = 'authenticated');

-- Storage bucket til ord-lydfiler
INSERT INTO storage.buckets (id, name, public)
SELECT 'book-audio', 'book-audio', true
WHERE NOT EXISTS (SELECT 1 FROM storage.buckets WHERE id = 'book-audio');

DROP POLICY IF EXISTS "Authenticated upload book-audio" ON storage.objects;
CREATE POLICY "Authenticated upload book-audio" ON storage.objects
  FOR INSERT WITH CHECK (
    bucket_id = 'book-audio' AND auth.role() = 'authenticated'
  );

DROP POLICY IF EXISTS "Public read book-audio" ON storage.objects;
CREATE POLICY "Public read book-audio" ON storage.objects
  FOR SELECT USING (bucket_id = 'book-audio');
