-- Gemmer spil mod computeren så de vises i aktive spil
CREATE TABLE IF NOT EXISTS kid_computer_matches (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  kid_id uuid NOT NULL REFERENCES kids(id) ON DELETE CASCADE,
  status text NOT NULL DEFAULT 'in_progress' CHECK (status IN ('in_progress', 'completed')),
  game_state jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_kid_computer_matches_kid_status
  ON kid_computer_matches(kid_id, status);

-- RLS
ALTER TABLE kid_computer_matches ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Kids see own computer matches" ON kid_computer_matches;
CREATE POLICY "Kids see own computer matches" ON kid_computer_matches
  FOR ALL USING (
    auth.uid() IN (
      SELECT p.auth_user_id FROM profiles p
      JOIN kids k ON k.parent_id = p.id
      WHERE k.id = kid_id
    )
  );

DO $$
BEGIN
  ALTER PUBLICATION supabase_realtime ADD TABLE kid_computer_matches;
EXCEPTION
  WHEN OTHERS THEN
    IF SQLERRM LIKE '%already member%' OR SQLERRM LIKE '%already exists%' THEN
      NULL;
    ELSE
      RAISE;
    END IF;
END $$;
