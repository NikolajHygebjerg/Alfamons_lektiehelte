-- Stram SELECT: kun egne grupper / egne gruppe-rækker (undgå at alle autentificerede læser alle).
DROP POLICY IF EXISTS "Authenticated read shop_book_groups" ON shop_book_groups;
DROP POLICY IF EXISTS "Read own shop_book_groups" ON shop_book_groups;
CREATE POLICY "Read own shop_book_groups" ON shop_book_groups
  FOR SELECT USING (
    profile_id IN (SELECT id FROM profiles WHERE auth_user_id = auth.uid())
  );

DROP POLICY IF EXISTS "Authenticated read shop_book_group_items" ON shop_book_group_items;
DROP POLICY IF EXISTS "Read shop_book_group_items for own groups" ON shop_book_group_items;
CREATE POLICY "Read shop_book_group_items for own groups" ON shop_book_group_items
  FOR SELECT USING (
    group_id IN (
      SELECT g.id FROM shop_book_groups g
      WHERE g.profile_id IN (SELECT id FROM profiles WHERE auth_user_id = auth.uid())
    )
  );
