#!/bin/bash
# Item 100 (b) one-off data move (live DB `stobe`, run once after item100b_reputation_follows_speaker.py).
# Under option (a) (StobeServer 97e0b9f .. item 100 b) a deal made by another squad character than the
# PLAYER_NAME persona was counted on the persona's reputation row. Those deals are still in
# stobe_social_contract (player_name = the character, consequences_applied = true), so their counts are
# moved from the persona row to the character's own row. Deals made by the persona stay where they are.
# Backup: table stobe_negotiation_reputation_bak_item100b (created once). Idempotent: a character that
# already has a row is skipped (it was counted under (b) already, or moved by an earlier run).
set -e
cd /tmp
sudo -u postgres psql -d stobe -v ON_ERROR_STOP=1 <<'SQL'
BEGIN;
CREATE TABLE IF NOT EXISTS stobe_negotiation_reputation_bak_item100b AS TABLE stobe_negotiation_reputation;
WITH persona AS (SELECT LOWER(value) AS p FROM general_settings WHERE id='PLAYER_NAME'),
moved AS (
  SELECT LOWER(c.player_name) AS who,
         COUNT(*) FILTER (WHERE c.status='COMPLETE') AS kept,
         COUNT(*) FILTER (WHERE c.status='BREACHED_PLAYER') AS broken,
         COUNT(*) FILTER (WHERE c.status='BREACHED_NPC') AS npc_broken
    FROM stobe_social_contract c, persona
   WHERE c.consequences_applied AND c.status IN ('COMPLETE','BREACHED_PLAYER','BREACHED_NPC')
     AND LOWER(c.player_name) <> persona.p AND COALESCE(c.player_name,'') <> ''
     AND NOT EXISTS (SELECT 1 FROM stobe_negotiation_reputation r WHERE r.player_name = LOWER(c.player_name))
   GROUP BY 1
),
ins AS (
  INSERT INTO stobe_negotiation_reputation (player_name, player_kept, player_broken, npc_broken)
  SELECT who, kept, broken, npc_broken FROM moved RETURNING player_name
)
UPDATE stobe_negotiation_reputation r
   SET player_kept = GREATEST(0, r.player_kept - (SELECT COALESCE(SUM(kept),0) FROM moved)),
       player_broken = GREATEST(0, r.player_broken - (SELECT COALESCE(SUM(broken),0) FROM moved)),
       npc_broken = GREATEST(0, r.npc_broken - (SELECT COALESCE(SUM(npc_broken),0) FROM moved)),
       updated_at = NOW()
  FROM persona WHERE r.player_name = persona.p AND EXISTS (SELECT 1 FROM moved);
COMMIT;
SELECT * FROM stobe_negotiation_reputation ORDER BY player_name;
SQL
