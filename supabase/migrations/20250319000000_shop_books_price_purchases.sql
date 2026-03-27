-- Pris på bøger og købshistorik
ALTER TABLE shop_books ADD COLUMN IF NOT EXISTS price_kr decimal(10,2) NOT NULL DEFAULT 0;

-- Køb: profil (forælder) har købt bog – børn under profilen kan læse den
CREATE TABLE IF NOT EXISTS shop_book_purchases (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  profile_id uuid NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  book_id uuid NOT NULL REFERENCES shop_books(id) ON DELETE CASCADE,
  purchased_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(profile_id, book_id)
);

ALTER TABLE shop_book_purchases ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Authenticated read purchases" ON shop_book_purchases;
CREATE POLICY "Authenticated read purchases" ON shop_book_purchases
  FOR SELECT USING (auth.role() = 'authenticated');

DROP POLICY IF EXISTS "Authenticated insert own purchase" ON shop_book_purchases;
CREATE POLICY "Authenticated insert own purchase" ON shop_book_purchases
  FOR INSERT TO authenticated
  WITH CHECK (
    profile_id IN (SELECT id FROM profiles WHERE auth_user_id = auth.uid())
  );
