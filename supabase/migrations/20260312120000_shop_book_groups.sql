-- Navngivne grupper af købte bøger pr. forælderprofil (barnets bibliotek når > 6 bøger)
--
-- AFHÆNGIGHED: Kør FØRST 20250317000000_shop_books.sql (opretter shop_books + shop_book_pages).
-- Uden shop_books får du: ERROR 42P01 relation "shop_books" does not exist.
--
CREATE TABLE IF NOT EXISTS shop_book_groups (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  profile_id uuid NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  name text NOT NULL,
  sort_order int NOT NULL DEFAULT 0,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS shop_book_group_items (
  group_id uuid NOT NULL REFERENCES shop_book_groups(id) ON DELETE CASCADE,
  book_id uuid NOT NULL REFERENCES shop_books(id) ON DELETE CASCADE,
  sort_order int NOT NULL DEFAULT 0,
  PRIMARY KEY (group_id, book_id)
);

CREATE INDEX IF NOT EXISTS idx_shop_book_groups_profile ON shop_book_groups(profile_id);
CREATE INDEX IF NOT EXISTS idx_shop_book_group_items_group ON shop_book_group_items(group_id);

ALTER TABLE shop_book_groups ENABLE ROW LEVEL SECURITY;
ALTER TABLE shop_book_group_items ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Authenticated read shop_book_groups" ON shop_book_groups;
CREATE POLICY "Authenticated read shop_book_groups" ON shop_book_groups
  FOR SELECT USING (auth.role() = 'authenticated');

DROP POLICY IF EXISTS "Authenticated manage own shop_book_groups" ON shop_book_groups;
CREATE POLICY "Authenticated manage own shop_book_groups" ON shop_book_groups
  FOR ALL USING (
    profile_id IN (SELECT id FROM profiles WHERE auth_user_id = auth.uid())
  )
  WITH CHECK (
    profile_id IN (SELECT id FROM profiles WHERE auth_user_id = auth.uid())
  );

DROP POLICY IF EXISTS "Authenticated read shop_book_group_items" ON shop_book_group_items;
CREATE POLICY "Authenticated read shop_book_group_items" ON shop_book_group_items
  FOR SELECT USING (auth.role() = 'authenticated');

DROP POLICY IF EXISTS "Authenticated manage shop_book_group_items" ON shop_book_group_items;
CREATE POLICY "Authenticated manage shop_book_group_items" ON shop_book_group_items
  FOR ALL USING (
    group_id IN (
      SELECT g.id FROM shop_book_groups g
      WHERE g.profile_id IN (SELECT id FROM profiles WHERE auth_user_id = auth.uid())
    )
  )
  WITH CHECK (
    group_id IN (
      SELECT g.id FROM shop_book_groups g
      WHERE g.profile_id IN (SELECT id FROM profiles WHERE auth_user_id = auth.uid())
    )
  );
