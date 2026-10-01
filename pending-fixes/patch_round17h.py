#!/usr/bin/env python3
"""Server round 17h (bug 57): faction members keep the base block when the selected
character stands among the base's outer buildings.

Run 4: player_base_presence is sampled from the *selected* character. With Malzin
selected at the stone mine / well (outside Home's town radius), presence said
inside=false and the round 17b <player_base> block disappeared. Fallback: when
presence isn't inside, use the latest player_bases snapshot (<= 3 h old) of a known
base location within 1500 units of the request's position (loc_x/loc_z).

Requires round 17b. Usage: patch_round17h.py <StobeServer root>
"""
import sys, pathlib

f = pathlib.Path(sys.argv[1]) / "lib" / "chat_helper_functions.php"
s = f.read_text()
old = """        $row = (function_exists('stobeGetCurrentPlayerBaseState') && npcIsInPlayerFaction($npcData))
            ? stobeGetCurrentPlayerBaseState(90)
            : [];
"""
new = """        $inFaction = npcIsInPlayerFaction($npcData);
        $row = ($inFaction && function_exists('stobeGetCurrentPlayerBaseState'))
            ? stobeGetCurrentPlayerBaseState(90)
            : [];
        if ($inFaction && (!is_array($row) || trim(strval($row['base_id'] ?? '')) === '')) {
            // Presence follows the selected character, who may be out at the base's own
            // mine or well (outside the town radius). Use the nearest known base instead.
            $qx = is_numeric($_GET['loc_x'] ?? null) ? floatval($_GET['loc_x']) : null;
            $qz = is_numeric($_GET['loc_z'] ?? null) ? floatval($_GET['loc_z']) : null;
            if ($qx !== null && $qz !== null) {
                try {
                    $near = $GLOBALS['db']->fetchOne(
                        "SELECT b.* FROM player_base_locations l
                           JOIN player_bases b ON b.base_id = l.base_id
                          WHERE (l.x - $1) * (l.x - $1) + (l.z - $2) * (l.z - $2) <= 1500.0 * 1500.0
                            AND b.last_seen_at >= NOW() - INTERVAL '3 hours'
                          ORDER BY (l.x - $1) * (l.x - $1) + (l.z - $2) * (l.z - $2), b.last_seen_at DESC
                          LIMIT 1",
                        [$qx, $qz]
                    );
                    if (is_array($near)) {
                        $row = $near;
                    }
                } catch (Throwable $e) {
                    $row = [];
                }
            }
        }
"""
assert s.count(old) == 1, "anchor (needs round 17b)"
f.write_text(s.replace(old, new))
print("patched", f)
