#!/usr/bin/env python3
"""imm26-sfQ: deferred plan-change confirm reliability (rows 20-a, 20-d).
usage: apply.py <tree root>   (idempotent; asserts every anchor)
(1) lib/imm26_plans.php: stobeImm26PromptTail tells the model explicitly to ACCEPT the pending destination on a confirming line;
    stobeImm26PendingChangeOffer also takes a model destination equal to the OLD trip when the player's line is pure confirmation.
(2) lib/travel_companionship.php: pass $npc, and rewrite the model's echoed old terms to the pending offer's terms before the ACCEPT checks.
"""
import sys, os
root = sys.argv[1]

def patch(rel, pairs):
    p = os.path.join(root, rel)
    s = open(p, encoding='utf-8').read()
    for marker, old, new in pairs:
        if marker in s:
            continue
        assert s.count(old) == 1, (rel, old[:60], s.count(old))
        s = s.replace(old, new)
    open(p, 'w', encoding='utf-8', newline='').write(s)

# ---------------------------------------------------------------- imm26_plans.php
OLD_FN_START = "/** The pending offer when this ACCEPT turn confirms it (same destination, same accepted trip, fresh); else null. */\nfunction stobeImm26PendingChangeOffer(string $actor, string $speaker, int $gamets, array $accepted, string $destination, string $playerLine): ?array {"
NEW_FN_START = """/** True when the player's line is (or contains) a refusal/negation, so it must never be read as confirming a pending change. */
function stobeImm26LineNegates(string $line): bool {
    $l = mb_strtolower(preg_replace('/\\b(no problem|no worries|not a problem|no trouble)\\b/iu', ' ', $line) ?? $line);
    return preg_match("/\\b(no|nope|nah|not|never|don'?t|do not|didn'?t|won'?t|cancel|forget it|nevermind|never mind|stop|instead)\\b/u", $l) === 1;
}
/** True when the player's line names a known place other than the offered/old destinations (so a bare confirmation is not bare). */
function stobeImm26LineNamesOtherPlace(string $actor, array|false $npc, string $line, array $skip): bool {
    if (!is_array($npc) || trim($line) === '') return false;
    $lineN = ' ' . stobeImm26Norm($line) . ' ';
    $skipN = [];
    foreach ($skip as $s) if (trim(strval($s)) !== '') $skipN[stobeImm26Norm(strval($s))] = true;
    try {
        $names = [];
        foreach (stobeTravelLocalCandidates($actor, $npc) as $p) $names[] = strval($p['label'] ?? '');
        foreach (stobeTravelKnownPlaceNames($actor, $npc) as $n) $names[] = strval($n);
        foreach (stobeTravelZoneRows() as $z) $names[] = strval($z['name'] ?? '');
    } catch (Throwable $e) { return false; }
    foreach ($names as $n) {
        $nn = stobeImm26Norm($n);
        if ($nn === '' || mb_strlen($nn) < 4 || isset($skipN[$nn])) continue;
        $covered = false;
        foreach ($skipN as $sn => $_) if ($sn !== '' && (str_contains($sn, $nn) || str_contains($nn, $sn))) { $covered = true; break; }
        if ($covered) continue;
        if (str_contains($lineN, ' ' . $nn . ' ')) return true;
    }
    return false;
}
/** The pending offer when this ACCEPT turn confirms it (same destination, same accepted trip, fresh); else null.
 * imm26 sfQ (20-a/20-d): a model that echoes the OLD trip's destination on a pure confirmation ("Yes.") still confirms the pending
 * change, provided the player's line does not name the old destination or another place and is not a negation. */
function stobeImm26PendingChangeOffer(string $actor, string $speaker, int $gamets, array $accepted, string $destination, string $playerLine, array|false $npc = false): ?array {"""

OLD_BODY = """    if ($destination !== '') {
        $offeredId = strval($offer['destination_point']['id'] ?? '');
        if (strcasecmp($destination, $offered) !== 0 && ($offeredId === '' || strcasecmp($destination, $offeredId) !== 0)) return null;
    } else {
        // A bare yes confirms the change unless the line names the old destination.
        $oldDest = strval($accepted['destination'] ?? '');
        if ($oldDest !== '' && mb_stripos($playerLine, $oldDest) !== false) return null;
    }
    return $offer;"""
NEW_BODY = """    $offeredId = strval($offer['destination_point']['id'] ?? '');
    $oldDest = strval($accepted['destination'] ?? '');
    $oldId = strval($accepted['destination_point']['id'] ?? '');
    $namesOld = $oldDest !== '' && mb_stripos($playerLine, $oldDest) !== false;
    if ($destination !== '') {
        $isOffered = strcasecmp($destination, $offered) === 0 || ($offeredId !== '' && strcasecmp($destination, $offeredId) === 0);
        $isOld = ($oldDest !== '' && strcasecmp($destination, $oldDest) === 0) || ($oldId !== '' && strcasecmp($destination, $oldId) === 0);
        if (!$isOffered) {
            // The model echoed the recorded (old) agreement on a pure confirmation: accept only when the line is confirmation words only.
            if (!$isOld || $namesOld || stobeImm26LineNegates($playerLine)
                || stobeImm26LineNamesOtherPlace($actor, $npc, $playerLine, [$offered, $offeredId, $oldDest, $oldId])) return null;
        }
    } else {
        // A bare yes confirms the change unless the line names the old destination.
        if ($namesOld) return null;
    }
    return $offer;"""

OLD_TAIL = """        if (!empty($alt['pending_change']['offer']['destination']) && $gamets - intval($alt['pending_change']['gamets'] ?? 0) <= 21600) $out .= 'A change to ' . $alt['pending_change']['offer']['destination'] . " is waiting for the speaker's confirmation; the current trip stays in force until they confirm.\\n";"""
NEW_TAIL = """        if (!empty($alt['pending_change']['offer']['destination']) && $gamets - intval($alt['pending_change']['gamets'] ?? 0) <= 21600) {
            $po = $alt['pending_change']['offer'];
            $out .= 'A change to ' . $po['destination'] . " is waiting for the speaker's confirmation; the current trip stays in force until they confirm. The Recorded agreement above still shows the OLD trip. "
                . 'If the speaker\\'s CURRENT message confirms the change (a plain yes, take me there, or it names ' . $po['destination'] . "), answer travel_decision=ACCEPT with travel_destination=" . $po['destination']
                . (!empty($po['kind']) ? ', travel_kind=' . $po['kind'] : '') . (!empty($po['leader']) ? ', travel_leader=' . $po['leader'] : '')
                . " and travel_player_quote = their exact words from that message; do NOT answer NONE and do NOT repeat the old destination. If they decline or ask for something else, use NONE (or REPLACE for a different new place).\\n";
        }"""

patch('lib/imm26_plans.php', [
    ('stobeImm26LineNegates', OLD_FN_START, NEW_FN_START),
    ('$namesOld = $oldDest', OLD_BODY, NEW_BODY),
    ('The Recorded agreement above still shows the OLD trip', OLD_TAIL, NEW_TAIL),
])

# ---------------------------------------------------------------- travel_companionship.php
OLD_CALL = """        $pendingOffer = stobeImm26PendingChangeOffer($actor,$speaker,$gamets,$old,trim(strval($data['travel_destination'] ?? '')),$playerLine);
        if (is_array($pendingOffer)) { $swapOld = $old; $old = $pendingOffer; }"""
NEW_CALL = """        $pendingOffer = stobeImm26PendingChangeOffer($actor,$speaker,$gamets,$old,trim(strval($data['travel_destination'] ?? '')),$playerLine,$npc);
        if (is_array($pendingOffer)) {
            // imm26 sfQ: the model echoed the old recorded terms on a pure confirmation; the confirmed terms are the pending offer's.
            $echoed = trim(strval($data['travel_destination'] ?? ''));
            if ($echoed !== '' && strcasecmp($echoed,strval($pendingOffer['destination'] ?? '')) !== 0
                && strcasecmp($echoed,strval($pendingOffer['destination_point']['id'] ?? '')) !== 0) {
                $data['travel_destination'] = strval($pendingOffer['destination'] ?? '');
                if (!empty($pendingOffer['kind'])) $data['travel_kind'] = strval($pendingOffer['kind']);
                if (!empty($pendingOffer['leader'])) $data['travel_leader'] = strval($pendingOffer['leader']);
            }
            $swapOld = $old; $old = $pendingOffer;
        }"""
patch('lib/travel_companionship.php', [('imm26 sfQ: the model echoed', OLD_CALL, NEW_CALL)])
print('sfQ applied to', root)
