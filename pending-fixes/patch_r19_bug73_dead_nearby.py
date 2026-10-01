#!/usr/bin/env python3
"""Bug 73: Malzin talked about dead Sorth as alive ("still breathing").
The prompt's nearby "Person" line used Sorth's stored metadata, frozen at
"moving" (Stobe.dll never re-scanned the corpse). Stobe.dll r19 now marks the
infonpc roster: "nearby NPC roster (2): Malzin, Sorth [Dust Bandit] (dead)".
Server: strip the marker from names (lookups keep working) and say DEAD /
unconscious in the prompt.
Usage: patch_r19_bug73_dead_nearby.py <StobeServer tree root>"""
import sys, pathlib
root = pathlib.Path(sys.argv[1])

def patch(rel, pairs):
    p = root / rel; s = p.read_text()
    for a, b in pairs:
        if b in s: continue
        assert s.count(a) == 1, f"{rel}: anchor not found: {a[:70]!r}"
        s = s.replace(a, b)
    p.write_text(s); print("patched", p)

HELPER = r'''/**
 * "Sorth [Dust Bandit] (dead)" -> ["Sorth [Dust Bandit]", "dead"] (bug 73).
 * Records the state in $GLOBALS['STOBE_ROSTER_STATES'][lowercase name].
 */
function stobeRosterSplitState(string $raw): array
{
    $raw = trim($raw);
    $state = '';
    if (preg_match('/^(.*?)\s*\((dead|unconscious)\)\s*$/iu', $raw, $m) === 1) {
        $raw = trim($m[1]);
        $state = strtolower($m[2]);
    }
    if ($raw !== '') {
        $GLOBALS['STOBE_ROSTER_STATES'][strtolower($raw)] = $state;
    }
    return [$raw, $state];
}

function stobeRosterState(string $name): string
{
    return strval($GLOBALS['STOBE_ROSTER_STATES'][strtolower(trim($name))] ?? '');
}

function stobeLifelikeNearbySquadLines(array $npcData, string $npcName): array
{'''

patch("lib/lifelike_npc.php", [
    ("function stobeLifelikeNearbySquadLines(array $npcData, string $npcName): array\n{", HELPER),
    ("""        foreach (explode(',', strval($m[1] ?? '')) as $piece) {
            $appendName($piece);
        }""",
     """        foreach (explode(',', strval($m[1] ?? '')) as $piece) {
            $appendName(stobeRosterSplitState(strval($piece))[0]);
        }"""),
    ("""        $action = trim(strval($meta['current_action'] ?? ''));
        if ($action !== '' && strtolower($action) !== 'idle' && strtolower($action) !== 'none') {
            $bits[] = 'doing:' . $action;
        }
        if (!empty($meta['is_in_combat']) || !empty($meta['is_attacking'])) {""",
     """        $rosterState = stobeRosterState($name);
        if ($rosterState === 'dead') {
            $out[] = $name . ' | DEAD: a corpse, not alive; cannot hear, speak or move';
            continue;
        }
        $action = trim(strval($meta['current_action'] ?? ''));
        if ($rosterState === 'unconscious') {
            $action = 'unconscious (knocked out, cannot talk)';
        }
        if ($action !== '' && strtolower($action) !== 'idle' && strtolower($action) !== 'none') {
            $bits[] = 'doing:' . $action;
        }
        if (!empty($meta['is_in_combat']) || !empty($meta['is_attacking'])) {"""),
])

patch("processor/chat.php", [
    ("""        foreach ($parts as $part) {
            $name = normalizeParticipantNameToken(strval($part));
            $name = trim(str_replace('...', '', $name));""",
     """        foreach ($parts as $part) {
            if (function_exists('stobeRosterSplitState')) {
                $part = stobeRosterSplitState(strval($part))[0];
            }
            $name = normalizeParticipantNameToken(strval($part));
            $name = trim(str_replace('...', '', $name));"""),
    ("""        $actors = [];
        foreach ($names as $name) {
            $actors[] = ['name' => $name];
        }
        return $actors;""",
     """        $actors = [];
        foreach ($names as $name) {
            $rosterState = function_exists('stobeRosterState') ? stobeRosterState($name) : '';
            $actors[] = $rosterState !== ''
                ? ['name' => $name, 'current_action' => $rosterState, 'is_' . $rosterState => true]
                : ['name' => $name];
        }
        return $actors;"""),
])
