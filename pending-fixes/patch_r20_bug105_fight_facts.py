#!/usr/bin/env python3
"""Bug 105: in the run 8 fight NPCs invented facts: knockouts before they
happened ("Vorr's down" 3 min early), the wrong person credited ("your Ranger
did the work on Pax" - Skovrek's own club did), Skovr and Skovrek mixed up,
and enemy gangs treated as friends (the game's faction relation said
[Friendly] while they fought each other).
Causes: the six <recent_situation> slots were filled by "Initiated attack"
lines (score 70; 1,862 of them that session), pushing out knockouts/deaths;
no rule against stating unseen outcomes; nothing about look-alike names.
Fix (lifelike continuity block):
- at most one "Initiated attack" line in <recent_situation>;
- rule: state knockouts/deaths/hits only when an event or the people list
  shows them; never guess who hit whom;
- rule: who is fighting whom now overrides faction labels;
- rule naming look-alike names present in the scene (e.g. Skovr / Skovrek).
Usage: patch_r20_bug105_fight_facts.py <StobeServer tree root>"""
import sys, pathlib
root = pathlib.Path(sys.argv[1])

def patch(rel, pairs):
    p = root / rel; s = p.read_text()
    for a, b in pairs:
        if b in s: continue
        assert s.count(a) == 1, f"{rel}: anchor not found: {a[:70]!r}"
        s = s.replace(a, b)
    p.write_text(s); print("patched", p)

patch("lib/lifelike_npc.php", [
    ("""    $location = stobeLifelikeCurrentLocation($safeNpc);

    foreach ($rows as $idx => $row) {
        if (!is_array($row)) {
            continue;
        }
        $line = stobeLifelikeCleanLine($row);
        if ($line === '') {
            continue;
        }""",
     """    $location = stobeLifelikeCurrentLocation($safeNpc);
    $attackLines = 0; // bug 105: "Initiated attack" spam must not crowd out knockouts/deaths

    foreach ($rows as $idx => $row) {
        if (!is_array($row)) {
            continue;
        }
        $line = stobeLifelikeCleanLine($row);
        if ($line === '') {
            continue;
        }
        $isAttackSpam = strtolower(trim(strval($row['type'] ?? ''))) === 'combat'
            && stripos($line, 'Initiated attack') !== false;"""),
    ("""        if ($score >= 30 && count($recentMeaningful) < 6) {
            $recentMeaningful[] = $line;
        }""",
     """        if ($score >= 30 && count($recentMeaningful) < 6 && (!$isAttackSpam || $attackLines++ < 1)) {
            $recentMeaningful[] = $line;
        }"""),
    ("""    $lines[] = '  <rule>In danger, combat, severe injury, or urgent flight, prioritize survival and short urgent speech over casual conversation.</rule>';""",
     """    $lines[] = '  <rule>In danger, combat, severe injury, or urgent flight, prioritize survival and short urgent speech over casual conversation.</rule>';
    // Bug 105: no invented fight outcomes, no mixed-up names, sides from the fight itself.
    $lines[] = '  <rule>Only say that someone is knocked out, down, dead or badly hit when a recent event or the people list shows it. Never guess who hit or downed whom; if you did not see it, do not claim it.</rule>';
    $lines[] = '  <rule>Who is fighting whom right now matters more than faction labels: anyone attacking you or your group is an enemy in this fight, whatever their faction is called.</rule>';
    $lookAlikes = [];
    $sceneNames = array_values(array_unique(array_filter(array_map(
        static fn($n) => trim(preg_replace('/\\s*\\[[^\\]]*\\]\\s*$/', '', strval($n)) ?? strval($n)),
        function_exists('stobeLifelikeLatestNearbyRosterNames') ? stobeLifelikeLatestNearbyRosterNames($safeNpc) : []
    ))));
    for ($i = 0; $i < count($sceneNames); $i++) {
        for ($j = $i + 1; $j < count($sceneNames); $j++) {
            $a = $sceneNames[$i]; $b = $sceneNames[$j];
            if (strlen($a) >= 3 && strlen($b) >= 3 && strcasecmp($a, $b) !== 0
                && (stripos($a, $b) === 0 || stripos($b, $a) === 0 || similar_text(strtolower($a), strtolower($b)) >= max(strlen($a), strlen($b)) - 2)) {
                $lookAlikes[] = $a . ' and ' . $b;
            }
        }
    }
    if (count($lookAlikes) > 0) {
        $lines[] = '  <rule>' . stobePromptXmlEscape(implode('; ', array_slice($lookAlikes, 0, 4))) . ' are different people with similar names. Use the exact name from the events when you say who did what.</rule>';
    }"""),
])
