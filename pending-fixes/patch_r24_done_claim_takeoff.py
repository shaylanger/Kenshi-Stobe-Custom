#!/usr/bin/env python3
"""Bug 39 (plan item 39): "Already done." to a take-off order with no action sent.

Run 11: "stow your katana in your pack" -> SHEATHE_WEAPON (katana stayed equipped);
"Take the katana off and keep it in your pack" -> no action at all, reply "Already done.
It's in the pack". The prompt listed the katana under Equipment.

Guard (chat.php, after the negotiation block): the player orders a take-off/stow of an
item that is still in her Equipment, her reply agrees or claims it is done (not a
refusal), and no UNEQUIP/DROP action came back -> add UNEQUIP_ITEM@<item>
(a SHEATHE_WEAPON for that order with "pack/bag/inventory" is replaced).
Log: `Take-off order: reply had no take-off action; UNEQUIP_ITEM added (bug 39)`.

Usage: patch_r24_done_claim_takeoff.py <StobeServer tree>  (idempotent)
"""
import sys
from pathlib import Path

root = Path(sys.argv[1])

def patch(rel, anchor, new, before=True, marker='stobeTakeOffOrderGuard'):
    f = root / rel
    s = f.read_text(encoding='utf-8')
    if marker in s:
        print('already patched', rel); return
    n = s.count(anchor)
    assert n == 1, f'{rel}: anchor found {n}x: {anchor[:60]!r}'
    s = s.replace(anchor, new + anchor if before else anchor + new)
    f.write_text(s, encoding='utf-8')
    print('patched', rel)

FUNC = r'''// ---- Bug 39: "Already done." to a take-off order with no action ----------------------

/**
 * The player told her to take off / stow a worn item, she agreed or claimed it's done,
 * but no take-off action came back: returns the fixed action list, or null.
 */
function stobeTakeOffOrderGuard(array $actions, string $playerMessage, string $reply, array|false $npcData): ?array {
    if (!is_array($npcData) || trim($playerMessage) === '') return null;
    $m = strtolower($playerMessage);
    $toPack = preg_match('/\b(pack|bag|backpack|inventory)\b/', $m) === 1;
    $order = preg_match("/\b(take (it|them|that|those|the [a-z' -]{1,40}|your [a-z' -]{1,40}) off|take off|remove|unequip|strip)\b/", $m) === 1
        || ($toPack && preg_match('/\b(stow|put|keep|pack)\b/', $m) === 1);
    if (!$order) return null;
    if (preg_match("/\b(hand|give|pass|toss|throw)\b[^.?!]{0,40}\b(me|over)\b|\bto me\b/", $m)) return null;
    foreach ($actions as $a) {
        if (preg_match('/^(UNEQUIP_ITEM|DROP_WEAPON|DROP_ITEM|SURRENDER|DISARM|GIVE_ITEM)@/i', strval($a))) return null;
    }
    $r = strtolower($reply);
    $claimsDone = preg_match("/\b(already done|done|it'?s (off|away|in (the|my) (pack|bag))|in the pack|in my pack|taken (it )?off)\b/", $r) === 1;
    $agrees = preg_match("/\b(fine|sure|alright|all right|okay|ok|i'?ll|will do|as you say|if you say so)\b/", $r) === 1;
    $refuses = preg_match("/\b(no|not|won'?t|never|stays|rather not|refuse|can'?t)\b/", $r) === 1;
    if (!$claimsDone && !($agrees && !$refuses)) return null;
    if (!function_exists('stobeNegInventoryDisplayNames')) return null;
    $worn = stobeNegInventoryDisplayNames(strval($npcData['equipment'] ?? ''));
    $pick = '';
    foreach ($worn as $lower => $display) {
        foreach (preg_split('/\s+/', $lower) ?: [] as $word) {
            if (strlen($word) >= 4 && preg_match('/\b' . preg_quote($word, '/') . 's?\b/', $m)) { $pick = $display; break 2; }
        }
    }
    if ($pick === '') return null;
    $fixed = [];
    foreach ($actions as $a) {
        if ($toPack && preg_match('/^SHEATHE_WEAPON@/i', strval($a))) continue;
        $fixed[] = $a;
    }
    $fixed[] = 'UNEQUIP_ITEM@' . $pick;
    return $fixed;
}

'''
patch('lib/negotiation_phase1.php',
      "// ---- Bug 30: agreed in words, nothing recorded -------------------------------------------",
      FUNC)

HOOK = r'''        if (function_exists('stobeTakeOffOrderGuard')
            && ($takeOffFixed = stobeTakeOffOrderGuard($responseActions, $message, $responseText, $npcData)) !== null) {
            // Bug 39: she said it's done / agreed, but no take-off action came back.
            stobeLogWarn('Take-off order: reply had no take-off action; UNEQUIP_ITEM added (bug 39)', [
                'npc'=>$targetNpc, 'text'=>$responseText, 'before'=>$responseActions, 'after'=>$takeOffFixed,
            ]);
            $responseActions = $takeOffFixed;
        }
'''
patch('processor/chat.php',
      "        stobeLogInfo('LLM stream response generated', [\n",
      HOOK)

TEST = r'''// ---------------------------------------------------------------- 12h. bug 39: "Already done." to a take-off order
$npc39 = ['equipment'=>'Black Cloth Shirt [Shoddy] x1 value 202 (A shirt), Chisa Katana [Ancient] x1 value 2789 (A katana)'];
check('bug 39: done-claim without action gets UNEQUIP_ITEM',
    stobeTakeOffOrderGuard([], 'Yes. Take the katana off and keep it in your pack.', "Already done. It's in the pack, edge wrapped.", $npc39) === ['UNEQUIP_ITEM@Chisa Katana']);
check('bug 39: stow in pack -> SHEATHE replaced by UNEQUIP_ITEM',
    stobeTakeOffOrderGuard(['SHEATHE_WEAPON@'], 'Malzin, stow your katana in your pack for now.', "Fine. I'll put it away.", $npc39) === ['UNEQUIP_ITEM@Chisa Katana']);
check('bug 39: a refusal adds nothing',
    stobeTakeOffOrderGuard([], 'Take your katana off.', 'No. The katana stays on my hip.', $npc39) === null);
check('bug 39: an UNEQUIP already there is left alone',
    stobeTakeOffOrderGuard(['UNEQUIP_ITEM@Chisa Katana'], 'Take your katana off.', "Fine, I'll take it off.", $npc39) === null);
check('bug 39: an item she is not wearing adds nothing',
    stobeTakeOffOrderGuard([], 'Take your hat off.', 'Already done.', $npc39) === null);

'''
patch('tests/negotiation_engine_regression.php',
      "// ---------------------------------------------------------------- 13. toggles",
      TEST, marker='bug 39: done-claim')
