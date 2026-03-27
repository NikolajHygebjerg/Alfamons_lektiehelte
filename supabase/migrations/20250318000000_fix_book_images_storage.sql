-- Sikr at authenticated brugere kan uploade og erstatte billeder i book-images
-- Kør i Supabase SQL Editor

-- Fjern evt. eksisterende policies
DROP POLICY IF EXISTS "Authenticated upload book-images" ON storage.objects;
DROP POLICY IF EXISTS "Authenticated update book-images" ON storage.objects;
DROP POLICY IF EXISTS "Authenticated delete book-images" ON storage.objects;
DROP POLICY IF EXISTS "Authenticated all book-images" ON storage.objects;
DROP POLICY IF EXISTS "Public read book-images" ON storage.objects;

-- Én samlet policy: authenticated kan gøre alt i book-images
CREATE POLICY "Authenticated all book-images" ON storage.objects
  FOR ALL TO authenticated
  USING (bucket_id = 'book-images')
  WITH CHECK (bucket_id = 'book-images');

-- Public kan læse (til visning af billeder)
CREATE POLICY "Public read book-images" ON storage.objects
  FOR SELECT USING (bucket_id = 'book-images');
