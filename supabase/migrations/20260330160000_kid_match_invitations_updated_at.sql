-- kid_match_invitations manglede updated_at; app/realtime forventer kolonnen (KidInvitationService m.fl.).
ALTER TABLE kid_match_invitations
  ADD COLUMN IF NOT EXISTS updated_at timestamptz NOT NULL DEFAULT now();

-- Eksisterende rækker: alignér med created_at (ny kolonne fik ellers samme DEFAULT ved migration).
UPDATE kid_match_invitations
SET updated_at = created_at;

CREATE OR REPLACE FUNCTION kid_match_invitations_set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS kid_match_invitations_touch_updated_at ON kid_match_invitations;
CREATE TRIGGER kid_match_invitations_touch_updated_at
  BEFORE UPDATE ON kid_match_invitations
  FOR EACH ROW
  EXECUTE FUNCTION kid_match_invitations_set_updated_at();
