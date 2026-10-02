#!/usr/bin/env python3
"""Her words didn't know about drops: a taken-off item dropped at her feet (full pack)
and she still said it "goes in the pack" (run 2).

Her line is written before KenshiFP takes the item off, so:
- the take-off turn gets a note: don't say where it goes; with a full pack it lands
  at your feet;
- later turns are told what was dropped: KenshiFP logs "UNEQUIP_ITEM no carried
  section has room; dropped at feet ... result=dropped" before the result line; the
  clothing block now lists those items as "on the ground at your feet".

Usage: patch_r23_unequip_drop_words.py <StobeServer tree root>  (idempotent)
"""
import sys
from pathlib import Path

root = Path(sys.argv[1])
eng = root / 'lib' / 'negotiation_engine.php'
e = eng.read_text(encoding='utf-8')
if 'dropped at your feet (full pack)' not in e:
    edits = [
        ("""        $removed = [];
        $pendingSlot = '';
        foreach (stobeNegBridgeRecords(time() - 6 * 3600) as $r) {
            $body = $r['body'];
            if (preg_match('/^UNEQUIP_ITEM section move result .* source=(\\S+) .*equippedAfter=0/', $body, $m)) { $pendingSlot = $m[1]; continue; }
            if (preg_match('/^UNEQUIP_ITEM serial=(\\d+) .*matched=(.+?) result=ok/', $body, $m)) {
                if (intval($m[1]) === $serial) $removed[strtolower(trim($m[2]))] = [trim($m[2]), $pendingSlot];
                $pendingSlot = '';
                continue;
            }""",
         """        $removed = [];
        $dropped = [];
        $pendingSlot = '';
        $pendingDrop = false;
        foreach (stobeNegBridgeRecords(time() - 6 * 3600) as $r) {
            $body = $r['body'];
            if (preg_match('/^UNEQUIP_ITEM section move result .* source=(\\S+) .*equippedAfter=0/', $body, $m)) { $pendingSlot = $m[1]; continue; }
            if (str_starts_with($body, 'UNEQUIP_ITEM no carried section has room; dropped at feet') && str_contains($body, 'result=dropped')) { $pendingDrop = true; continue; }
            if (preg_match('/^UNEQUIP_ITEM serial=(\\d+) .*matched=(.+?) result=ok/', $body, $m)) {
                if (intval($m[1]) === $serial) {
                    if ($pendingDrop) $dropped[strtolower(trim($m[2]))] = trim($m[2]);
                    else $removed[strtolower(trim($m[2]))] = [trim($m[2]), $pendingSlot];
                }
                $pendingSlot = '';
                $pendingDrop = false;
                continue;
            }"""),
        ("""        if (count($removed) === 0) return '';
        $carried = stobeNegInventoryCounts(strval($npcData['inventory'] ?? ''));""",
         """        if (count($removed) === 0 && count($dropped) === 0) return '';
        $carried = stobeNegInventoryCounts(strval($npcData['inventory'] ?? ''));"""),
        ("""        if (count($lines) === 0) return '';
        return "<clothing_you_took_off>\\nYou took these off earlier and are carrying them, not wearing them: " . implode('; ', $lines)""",
         """        $droppedLines = [];
        foreach ($dropped as $name) {
            if (!stobeNegItemCount($carried, $name) && !stobeNegItemCount($worn, $name)) $droppedLines[] = $name;
        }
        $droppedText = count($droppedLines) > 0
            ? "\\nYour pack was full, so these were dropped at your feet (full pack) when you took them off; they are on the ground, not in your pack: " . implode('; ', $droppedLines) . '.'
            : '';
        if (count($lines) === 0) return $droppedText === '' ? '' : "<clothing_you_took_off>" . $droppedText . "\\n</clothing_you_took_off>";
        return "<clothing_you_took_off>" . $droppedText . "\\nYou took these off earlier and are carrying them, not wearing them: " . implode('; ', $lines)"""),
    ]
    for o, n in edits:
        assert e.count(o) == 1, 'anchor: ' + o[:70]
        e = e.replace(o, n)
    eng.write_text(e, encoding='utf-8', newline='')
    print('patched', eng)

chat = root / 'processor' / 'chat.php'
c = chat.read_text(encoding='utf-8')
if 'full pack drops it at your feet' not in c:
    anchor = "// Mid-fight replies skip the model's hidden reasoning step (setting COMBAT_FAST_REPLIES)."
    add = """// A take-off request: her line comes before the game moves the item; a full pack drops it at your feet.
if (!$narratorMode && strcasecmp($speaker, $playerName) === 0 && function_exists('stobeDealPlayerAsksTakeOffOnly')
    && stobeDealPlayerAsksTakeOffOnly($message)) {
    $messages[] = ['role' => 'user', 'content' => '[If you take something off, do not say where it goes: if your pack is full, a full pack drops it at your feet.]'];
}
"""
    assert c.count(anchor) == 1
    c = c.replace(anchor, add + anchor)
    chat.write_text(c, encoding='utf-8', newline='')
    print('patched', chat)

test = root / 'tests' / 'negotiation_engine_regression.php'
t = test.read_text(encoding='utf-8')
if 'dropped at your feet (full pack)' not in t:
    anchor = "// ---------------------------------------------------------------- 13. toggles"
    add = """// ---------------------------------------------------------------- 12g. a take-off dropped at her feet (full pack) is known later
fixtureNpc('NegTestDrop', ['money'=>10, 'storage_id'=>'hand_555'], 'Bread x1 value 10', '', '100/100');
kfpLine('UNEQUIP_ITEM no carried section has room; dropped at feet item=0000 qty=1 source=head result=dropped', time());
kfpLine('UNEQUIP_ITEM serial=555 query=Iron Hat matched=Iron Hat result=ok', time());
$dropBlock = stobeRemovedClothingPromptBlock('NegTestDrop', getNpcData('NegTestDrop') ?: []);
check('dropped at your feet (full pack): the next turn knows', str_contains($dropBlock, 'Iron Hat') && str_contains($dropBlock, 'at your feet'), $dropBlock);
$db->exec("DELETE FROM core_npc_master WHERE name='NegTestDrop'");

"""
    assert t.count(anchor) == 1
    t = t.replace(anchor, add + anchor)
    test.write_text(t, encoding='utf-8', newline='')
    print('patched', test)
