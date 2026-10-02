#!/usr/bin/env python3
"""Plan item 46: a SPARE/STOP_ATTACK term with "to" instead of "target" voids the deal.

Run 12: beaten raider Quarl accepted "you give me 50 cats, I let you go" with terms
[npc GIVE_CATS 50 -> player, {"kind":"SPARE","by":"player","to":"npc"}] ->
"Negotiation rejected by deterministic validation: invalid_target"; nothing recorded.
Now, for STOP_ATTACK/FIRST_AID/SAFE_PASSAGE/SPARE/PROTECT, a missing target comes from
"to"; still missing: SPARE/PROTECT -> npc, an NPC's STOP_ATTACK -> player.
Log: `Negotiation term fixed: target taken from "to" (item 46)`.

Usage: patch_r24_term_target_field.py <StobeServer tree>  (idempotent)
"""
import sys
from pathlib import Path

root = Path(sys.argv[1])

def patch(rel, anchor, new, marker, before=True):
    f = root / rel
    s = f.read_text(encoding='utf-8')
    if marker in s:
        print('already patched', rel); return
    n = s.count(anchor)
    assert n == 1, f'{rel}: anchor found {n}x: {anchor[:60]!r}'
    s = s.replace(anchor, new + anchor if before else anchor + new)
    f.write_text(s, encoding='utf-8')
    print('patched', rel)

FUNC = r'''// ---- Item 46: "to" instead of "target" ----------------------------------------------------

/** STOP_ATTACK/FIRST_AID/SAFE_PASSAGE/SPARE/PROTECT terms get their target from "to" or the obvious default. */
function stobeDealFixTargetField(array $terms): array {
    foreach ($terms as $i => $t) {
        if (!is_array($t)) continue;
        $kind = strtoupper(strval($t['kind'] ?? ''));
        if (!in_array($kind, ['STOP_ATTACK','FIRST_AID','SAFE_PASSAGE','SPARE','PROTECT'], true)) continue;
        if (in_array(strval($t['target'] ?? ''), ['npc','player'], true)) continue;
        $target = in_array(strval($t['to'] ?? ''), ['npc','player'], true) ? strval($t['to']) : '';
        if ($target === '' && in_array($kind, ['SPARE','PROTECT'], true)) $target = 'npc';
        if ($target === '' && $kind === 'STOP_ATTACK' && ($t['by'] ?? '') === 'npc') $target = 'player';
        if ($target === '') continue;
        $terms[$i]['target'] = $target;
        unset($terms[$i]['to']);
        stobeDealLog('info', 'Negotiation term fixed: target taken from "to" (item 46)', ['kind'=>$kind, 'target'=>$target]);
    }
    return $terms;
}

'''
patch('lib/negotiation_phase1.php',
      "// ---- Bug 30: agreed in words, nothing recorded -------------------------------------------",
      FUNC, 'function stobeDealFixTargetField(')

patch('lib/negotiation_phase1.php',
      "    $terms = stobeDealFixTakeOffTerms($terms, $npcData, $playerMessage);\n",
      "    $terms = stobeDealFixTargetField($terms); // item 46\n",
      'stobeDealFixTargetField($terms); // item 46', before=False)

TEST = r'''// ---------------------------------------------------------------- 12k. item 46: SPARE with "to" instead of "target"
$t46 = stobeDealFixTargetField([
    ['kind'=>'GIVE_CATS','by'=>'npc','to'=>'player','amount'=>50],
    ['kind'=>'SPARE','by'=>'player','to'=>'npc'],
]);
check('item 46: SPARE target taken from "to"', ($t46[1]['target'] ?? '') === 'npc' && !isset($t46[1]['to']), $t46);
check('item 46: the deal then validates', stobeDealValidate(['parties'=>['npc'=>'a','player'=>'b'],'terms'=>$t46])['ok'] === true);
check('item 46: GIVE_CATS keeps its "to"', ($t46[0]['to'] ?? '') === 'player');
$t46b = stobeDealFixTargetField([['kind'=>'STOP_ATTACK','by'=>'npc']]);
check('item 46: an NPC STOP_ATTACK without target targets the player', ($t46b[0]['target'] ?? '') === 'player');

'''
patch('tests/negotiation_engine_regression.php',
      "// ---------------------------------------------------------------- 13. toggles",
      TEST, 'item 46: SPARE target')
