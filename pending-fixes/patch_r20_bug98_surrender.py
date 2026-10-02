#!/usr/bin/env python3
"""Bug 98: no bandit offered to surrender in run 8 although Vorr, Maelis and
Pax were badly hurt.
- Maelis/Pax/Skovr had no health data (blood "0/0", no limbs) and
  stobeNegHealthRatio() then returns 1.0, so they never counted as losing.
  Fix: without health data, estimate from "took a major hit" events against
  the NPC in the last 90 s (each hit -35 %: two hits = badly hurt).
- Skovrek's "help me" (assist) offer started the one shared 120 s cooldown that
  also blocks surrender offers. Fix: separate global cooldowns per kind.
Usage: patch_r20_bug98_surrender.py <StobeServer tree root>"""
import sys, pathlib
root = pathlib.Path(sys.argv[1])

def patch(rel, pairs):
    p = root / rel; s = p.read_text()
    for a, b in pairs:
        if b in s: continue
        assert s.count(a) == 1, f"{rel}: anchor not found: {a[:70]!r}"
        s = s.replace(a, b)
    p.write_text(s); print("patched", p)

patch("lib/negotiation_engine.php", [
    ("function stobeNegConsiderInitiatives(string $eventType, string $eventData, string $peopleRaw, int $gamets): void {",
     """/** Bug 98: "X: took a major hit" events against $name since $sinceUnix. */
function stobeNegMajorHitsOn(string $name, int $sinceUnix): int {
    try {
        $row = $GLOBALS['db']->fetchOne(
            "SELECT COUNT(*) AS n FROM eventlog WHERE type='major_damage' AND localts >= $1 AND data LIKE $2",
            [$sinceUnix, $name . ': took a major hit%']
        );
        return intval($row['n'] ?? 0);
    } catch (Throwable $e) {
        return 0;
    }
}

/** Bug 98: does the stored row carry real health numbers? */
function stobeNegHasHealthData(array $row): bool {
    if (preg_match('/^\\s*-?\\d+(?:\\.\\d+)?\\s*\\/\\s*[1-9]/', strval($row['blood'] ?? ''))) return true;
    $limbs = stobeNegDecode($row['limbs'] ?? []);
    return is_array($limbs) && count($limbs) > 0;
}

function stobeNegConsiderInitiatives(string $eventType, string $eventData, string $peopleRaw, int $gamets): void {"""),
    ("""        $recentGlobal = $GLOBALS['db']->fetchOne(
            "SELECT MAX(created_unix) AS t FROM stobe_negotiation_directive WHERE kind IN ('surrender','assist')"
        );
        if (($now - intval($recentGlobal['t'] ?? 0)) < STOBE_NEG_INITIATIVE_GLOBAL_COOLDOWN) return;
""",
     """        // Bug 98: one cooldown per kind, so a "help me" offer doesn't block surrenders.
        $recentSurrender = $GLOBALS['db']->fetchOne(
            "SELECT MAX(created_unix) AS t FROM stobe_negotiation_directive WHERE kind='surrender'"
        );
        $recentAssist = $GLOBALS['db']->fetchOne(
            "SELECT MAX(created_unix) AS t FROM stobe_negotiation_directive WHERE kind='assist'"
        );
        $surrenderReady = ($now - intval($recentSurrender['t'] ?? 0)) >= STOBE_NEG_INITIATIVE_GLOBAL_COOLDOWN;
        $assistReady = ($now - intval($recentAssist['t'] ?? 0)) >= STOBE_NEG_INITIATIVE_GLOBAL_COOLDOWN;
        if (!$surrenderReady && !$assistReady) return;
"""),
    ("""            $ratio = stobeNegHealthRatio($row);
            $events = stobeNegCombatEvents($now - 90, $name);""",
     """            $ratio = stobeNegHealthRatio($row);
            if (!stobeNegHasHealthData($row)) { // bug 98: no numbers -> judge by major hits
                $ratio = max(0.1, 1.0 - 0.35 * stobeNegMajorHitsOn($name, $now - 90));
            }
            $events = stobeNegCombatEvents($now - 90, $name);"""),
    ("""            if ($hostileToPlayer && stobeNegPhaseEnabled(4) && $ratio < stobeNegCourageThreshold($personality, 0.35)) {""",
     """            if ($surrenderReady && $hostileToPlayer && stobeNegPhaseEnabled(4) && $ratio < stobeNegCourageThreshold($personality, 0.35)) {"""),
    ("""            if (!$hostileToPlayer && $fightingOthers && $playerNearby && stobeNegPhaseEnabled(5)""",
     """            if ($assistReady && !$hostileToPlayer && $fightingOthers && $playerNearby && stobeNegPhaseEnabled(5)"""),
])
