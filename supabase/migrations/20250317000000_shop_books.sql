-- Bogbutik: Bøger og sider til Læs-let
-- Format: 1024x1024 px per side
-- Forside + opslag (2-3, 4-5, osv.) – venstre side = tekst, højre side = billede

CREATE TABLE IF NOT EXISTS shop_books (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  title text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS shop_book_pages (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  book_id uuid NOT NULL REFERENCES shop_books(id) ON DELETE CASCADE,
  spread_index int NOT NULL,
  left_text text NOT NULL DEFAULT '',
  right_image_url text,
  UNIQUE(book_id, spread_index)
);

-- RLS: Kun autentificerede brugere kan læse (forældre køber, børn læser)
-- Skriv adgang styres af app-logik (kun nikolaj@begejstring.dk via admin)
ALTER TABLE shop_books ENABLE ROW LEVEL SECURITY;
ALTER TABLE shop_book_pages ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Authenticated read shop_books" ON shop_books;
CREATE POLICY "Authenticated read shop_books" ON shop_books
  FOR SELECT USING (auth.role() = 'authenticated');

DROP POLICY IF EXISTS "Authenticated read shop_book_pages" ON shop_book_pages;
CREATE POLICY "Authenticated read shop_book_pages" ON shop_book_pages
  FOR SELECT USING (auth.role() = 'authenticated');

-- Service role / admin skriver via app – tillad insert/update/delete for authenticated
-- (Admin book builder bruger samme auth – vi begrænser i appen til nikolaj@begejstring.dk)
DROP POLICY IF EXISTS "Authenticated all shop_books" ON shop_books;
CREATE POLICY "Authenticated all shop_books" ON shop_books
  FOR ALL USING (auth.role() = 'authenticated');

DROP POLICY IF EXISTS "Authenticated all shop_book_pages" ON shop_book_pages;
CREATE POLICY "Authenticated all shop_book_pages" ON shop_book_pages
  FOR ALL USING (auth.role() = 'authenticated');

-- Storage bucket til bogbilleder (1024x1024)
-- Opret i Supabase Dashboard hvis migration fejler: Storage → New bucket → id: book-images, public: true
INSERT INTO storage.buckets (id, name, public)
SELECT 'book-images', 'book-images', true
WHERE NOT EXISTS (SELECT 1 FROM storage.buckets WHERE id = 'book-images');

-- RLS for storage: authenticated kan uploade og læse
DROP POLICY IF EXISTS "Authenticated upload book-images" ON storage.objects;
CREATE POLICY "Authenticated upload book-images" ON storage.objects
  FOR INSERT WITH CHECK (
    bucket_id = 'book-images' AND auth.role() = 'authenticated'
  );

DROP POLICY IF EXISTS "Public read book-images" ON storage.objects;
CREATE POLICY "Public read book-images" ON storage.objects
  FOR SELECT USING (bucket_id = 'book-images');
