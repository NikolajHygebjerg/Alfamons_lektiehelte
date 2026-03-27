-- Tillad opdatering af lydfiler (bruges af noise reduction service)
DROP POLICY IF EXISTS "Authenticated update book-audio" ON storage.objects;
CREATE POLICY "Authenticated update book-audio" ON storage.objects
  FOR UPDATE USING (
    bucket_id = 'book-audio' AND auth.role() = 'authenticated'
  );
