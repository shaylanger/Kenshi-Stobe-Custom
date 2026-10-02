#!/usr/bin/env python3
"""Bug 110: a squad member refused a loot order from stale chat memory.

Run 9 (test 71): "loot everything from the Hungry Bandit's body" on fresh bodies;
Malzin: "Already picked that one clean" (her history about earlier bodies misled
her). Loot orders run as goals and the goal checks the bodies, so:

- Prompt: a player's loot order to a squad member gets a note: the goal checks the
  bodies; don't refuse from memory; use LootTarget / LootArea.
- Fallback: if she still emits no loot action, a LOOT_TARGET@<nothing> is added,
  which the action bridge turns into a LOOT_AREA goal (category from the line).
  The goal reports what it found.

Usage: patch_r22_bug110_loot_order_goal.py <StobeServer tree root>  (idempotent)
"""
import sys
from pathlib import Path

root = Path(sys.argv[1])

lib = root / 'lib' / 'chat_helper_functions.php'
text = lib.read_text(encoding='utf-8')
if 'bug 110' not in text:
    anchor = "function stobeSpeechClaimsEquipDone(string $message): bool {"
    helpers = r"""/** Bug 110: the player orders a loot ("loot the bodies", "strip the bandit"), not a question about one. */
function stobeLootOrderLine(string $playerMessage): bool {
    $m = strtolower($playerMessage);
    if (!preg_match("/\b(loot|strip|rummage|scavenge)\b|\bsearch\s+(?:the\s+)?(?:bod(?:y|ies)|corpses?|dead)\b/", $m)) return false;
    return !preg_match("/\b(did|have|has|had)\s+(?:you|she|he|they|anyone)\b|\bdon'?t\b|\bdo not\b|\bstop\b|\bnever\b|\bwho\b/", $m);
}

/** Bug 110: the reply already loots (LootTarget, a loot goal). */
function stobeLootActionPresent(array $actions): bool {
    foreach ($actions as $action) {
        if (preg_match('/^(LOOT_TARGET|LOOT_AREA|LOOT_STORE|BATTLE_CLEANUP)\b|^(TASK_GOAL|WORK_GOAL)@(LOOT|BATTLE)/i', trim(strval($action)))) return true;
    }
    return false;
}

"""
    assert text.count(anchor) == 1, 'helper anchor'
    text = text.replace(anchor, helpers + anchor)
    lib.write_text(text, encoding='utf-8', newline='')
    print('patched', lib)

chat = root / 'processor' / 'chat.php'
c = chat.read_text(encoding='utf-8')
if 'bug 110' not in c:
    note_anchor = "// Mid-fight replies skip the model's hidden reasoning step (setting COMBAT_FAST_REPLIES)."
    note = """// Bug 110: a loot order to a squad member: the goal checks the bodies, not her memory.
$lootOrder = !$narratorMode && strcasecmp($speaker, $playerName) === 0 && is_array($npcData)
    && npcIsInPlayerFaction($npcData) && function_exists('stobeLootOrderLine') && stobeLootOrderLine($message);
if ($lootOrder) {
    $messages[] = ['role' => 'user', 'content' => '[Looting runs as a goal that checks the bodies itself. You cannot know from memory '
        . 'whether these bodies were already looted (earlier bodies were others), so do not refuse for that reason: '
        . 'use LootTarget on the body (or LootArea) and let the goal report what it finds.]'];
}
"""
    assert c.count(note_anchor) == 1, 'note anchor'
    c = c.replace(note_anchor, note + note_anchor)
    act_anchor = "// Bug 32: an NPC doesn't give up the weapon she's using unless she's surrendering or trusts the player."
    act = """// Bug 110: she still emitted no loot action: the order runs as a loot goal anyway.
if (!empty($lootOrder) && function_exists('stobeLootActionPresent') && !stobeLootActionPresent($responseActions)) {
    $responseActions[] = 'LOOT_TARGET@';
    stobeLogInfo('Loot order without a loot action: loot goal added (bug 110)', ['npc'=>$targetNpc, 'message'=>$message, 'text'=>$responseText]);
}
"""
    assert c.count(act_anchor) == 1, 'action anchor'
    c = c.replace(act_anchor, act + act_anchor)
    chat.write_text(c, encoding='utf-8', newline='')
    print('patched', chat)

test = root / 'tests' / 'negotiation_engine_regression.php'
t = test.read_text(encoding='utf-8')
if 'bug 110' not in t:
    anchor = "// ---------------------------------------------------------------- 13. toggles"
    add = """// ---------------------------------------------------------------- 12c. bug 110: loot orders run as goals
check('bug 110: loot order recognised', stobeLootOrderLine("Malzin, loot everything from the Hungry Bandit's body.") && stobeLootOrderLine('Search the bodies.'));
check('bug 110: questions and stops are not orders', !stobeLootOrderLine('Did you loot him already?') && !stobeLootOrderLine("Don't loot that one."));
check('bug 110: loot action detected', stobeLootActionPresent(['LOOT_TARGET@Hungry Bandit']) && stobeLootActionPresent(['TASK_GOAL@LOOT_AREA@all']) && !stobeLootActionPresent(['FOLLOW@Shay']));

"""
    assert t.count(anchor) == 1, 'test anchor'
    t = t.replace(anchor, add + anchor)
    test.write_text(t, encoding='utf-8', newline='')
    print('patched', test)
