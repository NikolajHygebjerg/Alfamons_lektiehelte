-- Udfordringer mellem børn under samme forælder
-- Børn kan kun udfordre andre børn med samme parent_id
--
-- AFHÆNGIGHED: 20250301025000_avatars_bootstrap.sql (kid_match_rounds FK → avatars.id).
-- Kræver også kids + profiles (bootstrap eller eksisterende skema).

-- Invitationer: A udfordrer B
CREATE TABLE IF NOT EXISTS kid_match_invitations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  challenger_kid_id uuid NOT NULL REFERENCES kids(id) ON DELETE CASCADE,
  challenged_kid_id uuid NOT NULL REFERENCES kids(id) ON DELETE CASCADE,
  status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'accepted', 'declined')),
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(challenger_kid_id, challenged_kid_id)
);

-- Aktive kampe (oprettes når invitation accepteres)
CREATE TABLE IF NOT EXISTS kid_matches (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  invitation_id uuid NOT NULL REFERENCES kid_match_invitations(id) ON DELETE CASCADE UNIQUE,
  kid1_id uuid NOT NULL REFERENCES kids(id) ON DELETE CASCADE,
  kid2_id uuid NOT NULL REFERENCES kids(id) ON DELETE CASCADE,
  status text NOT NULL DEFAULT 'in_progress' CHECK (status IN ('in_progress', 'completed')),
  round_number int NOT NULL DEFAULT 1,
  kid1_score int NOT NULL DEFAULT 0,
  kid2_score int NOT NULL DEFAULT 0,
  created_at timestamptz NOT NULL DEFAULT now()
);

-- Runde-valg: for hver runde vælger begge kort først, derefter evne
-- Phase: 'pick_card' | 'pick_strength' | 'resolved'
CREATE TABLE IF NOT EXISTS kid_match_rounds (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  match_id uuid NOT NULL REFERENCES kid_matches(id) ON DELETE CASCADE,
  round_number int NOT NULL,
  phase text NOT NULL DEFAULT 'pick_card' CHECK (phase IN ('pick_card', 'pick_strength', 'resolved')),
  kid1_avatar_id uuid REFERENCES avatars(id),
  kid1_stage_index int,
  kid2_avatar_id uuid REFERENCES avatars(id),
  kid2_stage_index int,
  kid1_strength_index int,
  kid2_strength_index int,
  winner text CHECK (winner IN ('kid1', 'kid2', 'tie')),
  UNIQUE(match_id, round_number)
);

-- RLS: børn kan kun se invitationer/kampe hvor de er involveret
DROP POLICY IF EXISTS "Kids see own invitations" ON kid_match_invitations;
CREATE POLICY "Kids see own invitations" ON kid_match_invitations
  FOR ALL USING (
    auth.uid() IN (
      SELECT p.auth_user_id FROM profiles p
      JOIN kids k ON k.parent_id = p.id
      WHERE k.id IN (challenger_kid_id, challenged_kid_id)
    )
  );

DROP POLICY IF EXISTS "Kids see own matches" ON kid_matches;
CREATE POLICY "Kids see own matches" ON kid_matches
  FOR ALL USING (
    auth.uid() IN (
      SELECT p.auth_user_id FROM profiles p
      JOIN kids k ON k.parent_id = p.id
      WHERE k.id IN (kid1_id, kid2_id)
    )
  );

DROP POLICY IF EXISTS "Kids see own match rounds" ON kid_match_rounds;
CREATE POLICY "Kids see own match rounds" ON kid_match_rounds
  FOR ALL USING (
    auth.uid() IN (
      SELECT p.auth_user_id FROM profiles p
      JOIN kids k ON k.parent_id = p.id
      JOIN kid_matches m ON m.id = match_id
      WHERE k.id IN (m.kid1_id, m.kid2_id)
    )
  );

-- Enable RLS
ALTER TABLE kid_match_invitations ENABLE ROW LEVEL SECURITY;
ALTER TABLE kid_matches ENABLE ROW LEVEL SECURITY;
ALTER TABLE kid_match_rounds ENABLE ROW LEVEL SECURITY;

-- Trigger: Opret kamp når invitation accepteres
CREATE OR REPLACE FUNCTION create_match_on_accept()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.status = 'accepted' THEN
    INSERT INTO kid_matches (invitation_id, kid1_id, kid2_id)
    VALUES (NEW.id, NEW.challenger_kid_id, NEW.challenged_kid_id);
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS on_invitation_accepted ON kid_match_invitations;
CREATE TRIGGER on_invitation_accepted
  AFTER UPDATE ON kid_match_invitations
  FOR EACH ROW
  WHEN (OLD.status IS DISTINCT FROM NEW.status AND NEW.status = 'accepted')
  EXECUTE FUNCTION create_match_on_accept();

-- Realtime: Tilføj tabeller til supabase_realtime publication (idempotent)
DO $$
BEGIN
  ALTER PUBLICATION supabase_realtime ADD TABLE kid_match_invitations;
EXCEPTION
  WHEN OTHERS THEN
    IF SQLERRM LIKE '%already member%' OR SQLERRM LIKE '%already exists%' THEN
      NULL;
    ELSE
      RAISE;
    END IF;
END $$;
DO $$
BEGIN
  ALTER PUBLICATION supabase_realtime ADD TABLE kid_matches;
EXCEPTION
  WHEN OTHERS THEN
    IF SQLERRM LIKE '%already member%' OR SQLERRM LIKE '%already exists%' THEN
      NULL;
    ELSE
      RAISE;
    END IF;
END $$;
DO $$
BEGIN
  ALTER PUBLICATION supabase_realtime ADD TABLE kid_match_rounds;
EXCEPTION
  WHEN OTHERS THEN
    IF SQLERRM LIKE '%already member%' OR SQLERRM LIKE '%already exists%' THEN
      NULL;
    ELSE
      RAISE;
    END IF;
END $$;
