#!/usr/bin/env python3
"""Server round 17b (bug 46): faction members know the player's base.

The DLL sends every NPC's own player_base snapshot as inside=false (never filled in),
so <player_base> never reached the chat prompt: Malzin said there was "no mill, no
stove, no mine" while standing in Home. Fallback: when the NPC is in the player's
faction and player_base_presence says the player is inside a base (<= 90 s old),
build the block from that server-side snapshot.

Usage: patch_round17b.py <StobeServer root>
"""
import sys, pathlib

root = pathlib.Path(sys.argv[1])
f = root / "lib" / "chat_helper_functions.php"
s = f.read_text()

def rep(old, new):
    global s
    n = s.count(old)
    assert n == 1, f"anchor count {n}: {old[:70]!r}"
    s = s.replace(old, new)

rep("""        ? stobeNormalizePlayerBaseSnapshot($extended['player_base'] ?? [], false)
        : [];
    if (!boolval($base['inside'] ?? false)) {
        return '';
    }
    $serverObservedAt = intval($base['server_observed_at'] ?? 0);
    if ($serverObservedAt > 0 && (time() - $serverObservedAt) > 90) {
        return '';
    }
""", """        ? stobeNormalizePlayerBaseSnapshot($extended['player_base'] ?? [], false)
        : [];
    $baseFromPresence = false;
    $ownFresh = boolval($base['inside'] ?? false)
        && !(intval($base['server_observed_at'] ?? 0) > 0 && (time() - intval($base['server_observed_at'])) > 90);
    if (!$ownFresh) {
        // The DLL does not fill in per-NPC base presence; a faction member knows the
        // player's base when the player is inside it (server-side presence snapshot).
        $row = (function_exists('stobeGetCurrentPlayerBaseState') && npcIsInPlayerFaction($npcData))
            ? stobeGetCurrentPlayerBaseState(90)
            : [];
        if (!is_array($row) || trim(strval($row['base_id'] ?? '')) === '') {
            return '';
        }
        $pgBool = static fn($v): bool => $v === true || in_array(strtolower(strval($v)), ['t', 'true', '1'], true);
        $details = json_decode(strval($row['details'] ?? ''), true);
        $base = [
            'inside' => true,
            'name' => strval($row['name'] ?? 'Player Base'),
            'power_generated' => $row['power_generated'] ?? 0,
            'power_required' => $row['power_required'] ?? 0,
            'has_spare_power' => $pgBool($row['has_spare_power'] ?? false),
            'battery_charge' => $row['battery_charge'] ?? 0,
            'battery_capacity' => $row['battery_capacity'] ?? 0,
            'battery_drain' => $row['battery_drain'] ?? 0,
            'battery_charging' => $row['battery_charging'] ?? 0,
            'battery_mode' => $pgBool($row['battery_mode'] ?? false),
            'members_inside' => intval($row['members_inside'] ?? 0),
            'has_gates' => $pgBool($row['has_gates'] ?? false),
            'gates_closed' => $pgBool($row['gates_closed'] ?? false),
            'details' => is_array($details) ? $details : [],
        ];
        $baseFromPresence = true;
    }
""")

rep("""    $lines[] = '  <context>This character is currently inside this player-owned base perimeter.</context>';
    $lines[] = '</player_base>';""",
    """    $lines[] = $baseFromPresence
        ? '  <context>This is your faction\\'s own base; the player is inside it now. Its production buildings, farms and storage listed here are yours to work (WORK_GOAL / TASK_GOAL).</context>'
        : '  <context>This character is currently inside this player-owned base perimeter.</context>';
    $lines[] = '</player_base>';""")

f.write_text(s)
print("patched", f)
