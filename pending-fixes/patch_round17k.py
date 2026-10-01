#!/usr/bin/env python3
"""Server round 17k: bugs 66 and 60 (rest).

66: goal_report directives forced director mode; the director found "No eligible
    Director cast", the turn was dropped and the report lost. goal_report now skips
    director mode but still bypasses the bored chance gate (the directive's
    instruction is used, listener = player).
60: "fetch the vodka and the mead" -> the model sent item=Vodka only. When a
    FETCH/STORE/DELIVER item is a single name and the player's own line lists several
    objects ("X and Y", "X, Y") that include it, the others are queued too.

Requires round 17j. Usage: patch_round17k.py <StobeServer root>
"""
import sys, pathlib

root = pathlib.Path(sys.argv[1])

def patch(rel, pairs):
    f = root / rel
    s = f.read_text()
    for old, new in pairs:
        n = s.count(old)
        assert n == 1, f"{rel}: anchor count {n}: {old[:70]!r}"
        s = s.replace(old, new)
    f.write_text(s)
    print("patched", f)

patch("processor/bored.php", [
    ("$forceDirectorMode = ($requestMode === 'director');",
     "$forceDirectorMode = ($requestMode === 'director');\n$forceDirectiveTurn = false; // goal reports: skip the chance gate, no director (bug 66)"),
    ("        $forceDirectorMode = true;\n        stobeLogInfo('Bored event taken by negotiation directive'",
     "        if (strval($negDirective['kind'] ?? '') === 'goal_report') {\n"
     "            $forceDirectiveTurn = true;\n"
     "        } else {\n"
     "            $forceDirectorMode = true;\n"
     "        }\n"
     "        stobeLogInfo('Bored event taken by negotiation directive'"),
    ("if (!$forceDirectorMode && $roll >= $boredChance) {",
     "if (!$forceDirectorMode && !$forceDirectiveTurn && $roll >= $boredChance) {"),
])

patch("lib/chat_helper_functions.php", [
    ("""            } elseif (in_array($taskKind, ['FETCH','STORE','DELIVER'], true)
                && count($taskItemList = array_values(array_filter(array_map('trim',
                    preg_split('/\\s*(?:,|&|\\band\\b)\\s*/i', strval($taskItem)) ?: []), static fn($v) => $v !== ''))) > 1) {""",
     """            } elseif (in_array($taskKind, ['FETCH','STORE','DELIVER'], true)
                && count($taskItemList = stobeTaskItemListFromTurn($taskItem)) > 1) {"""),
    ("function stobeResolveLiveParticipantSerial(string $name, bool $allowStoredFallback = false): int {",
     r'''/**
 * Items for FETCH/STORE/DELIVER: the model's item field split on "," "&" "and";
 * if that gives one item, the player's own line may list more (bug 60:
 * "fetch the vodka and the mead" came back as item=Vodka).
 */
function stobeTaskItemListFromTurn(string $item): array {
    $split = static fn(string $v): array => array_values(array_filter(array_map('trim',
        preg_split('/\s*(?:,|&|\band\b)\s*/i', $v) ?: []), static fn($x) => $x !== ''));
    $list = $split($item);
    if (count($list) !== 1) return $list;
    $line = trim(strval($GLOBALS['STOBE_CURRENT_PLAYER_MESSAGE'] ?? ''));
    if ($line === '' || !preg_match('/\b(?:fetch|get|grab|bring|take|put|store|stash|stow|give|hand)\b\s+(?:me\s+|us\s+)?(.+?)(?:\s+\b(?:from|in|into|to|back|at|for|out)\b|[.?!;]|$)/i', $line, $m)) {
        return $list;
    }
    $words = [];
    foreach ($split($m[1]) as $part) {
        $part = trim(preg_replace('/^(?:the|a|an|some|my|our|your|those|these|that|this|all|\d+)\s+/i', '', $part) ?? '');
        $part = trim(preg_replace('/^(?:the|a|an|some)\s+/i', '', $part) ?? '');
        if ($part !== '' && strlen($part) <= 40) $words[] = $part;
    }
    if (count($words) < 2) return $list;
    $one = strtolower($list[0]);
    $hit = false;
    foreach ($words as $w) {
        $lw = strtolower($w);
        if (str_contains($one, $lw) || str_contains($lw, $one)) { $hit = true; break; }
    }
    if (!$hit) return $list;
    $out = [$list[0]];
    foreach ($words as $w) {
        $lw = strtolower($w);
        if (str_contains($one, $lw) || str_contains($lw, $one)) continue;
        $out[] = $w;
    }
    return array_slice($out, 0, 6);
}

function stobeResolveLiveParticipantSerial(string $name, bool $allowStoredFallback = false): int {'''),
])
