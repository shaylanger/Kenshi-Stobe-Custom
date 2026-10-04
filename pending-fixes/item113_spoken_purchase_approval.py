#!/usr/bin/env python3
"""Item 113: a spoken yes/no to a purchase waiting for approval approves/declines it.

m18 Squin STOBE 15: Kint's `buy-wg-...-Fabrics` goal was WAITING_APPROVAL; Beak said "Yes, go ahead and buy the
fabrics." and the model answered MOVE_TO_TARGET@Apothecary Marquart, no TASK_CONTROL@APPROVE, so the goal never
moved. The approval is the player's decision: when the squad member has a WAITING_APPROVAL goal and the player's
line is a clear yes (or no), TASK_CONTROL@APPROVE|DECLINE@<goal id> is added (unless the reply already has a
TASK_CONTROL).

Usage: item113_spoken_purchase_approval.py <tree root>
"""
import sys, pathlib

root = pathlib.Path(sys.argv[1])

def patch(rel, old, new):
    p = root / rel
    s = p.read_text()
    if new in s:
        print(f"{rel}: already patched"); return
    assert s.count(old) == 1, f"{rel}: anchor found {s.count(old)}x"
    p.write_text(s.replace(old, new))
    print(f"{rel}: patched")

patch("lib/chat_helper_functions.php",
"""/**
 * Item 43: the items a player's line asks her to hand over, in order:""",
"""/**
 * Item 113: the player's clear yes/no to a squad member's purchase that waits for approval ->
 * TASK_CONTROL@APPROVE|DECLINE@<goal id>. $waiting(actor) returns the waiting goal id or ''.
 */
function stobeInferApprovalFromReply(string $playerLine, array|false $npcData, array $actions, ?callable $waiting = null, ?bool $squadMember = null): string {
    if (!is_array($npcData)) return '';
    if ($squadMember === null) $squadMember = function_exists('npcIsInPlayerFaction') && npcIsInPlayerFaction($npcData);
    if (!$squadMember) return '';
    foreach ($actions as $a) {
        if (preg_match('/^TASK_CONTROL@(APPROVE|DECLINE|CANCEL)@/i', trim(strval($a)))) return '';
    }
    $line = strtolower(trim($playerLine));
    if ($line === '' || str_contains($line, '?')) return '';
    $no = preg_match("/\\b(no|nope|don'?t|do\\s+not|cancel|decline|forget\\s+(?:it|that)|never\\s*mind|not\\s+worth)\\b/", $line) === 1;
    $yes = preg_match("/^(?:[a-z]+,\\s*)?(?:yes|yeah|yep|aye|sure|ok(?:ay)?|fine|approved?)\\b|\\b(?:go\\s+ahead|do\\s+it|you\\s+can\\s+buy|buy\\s+(?:it|them|those|that|the\\s+[a-z' -]{2,40})|i\\s+approve|approved)\\b/", $line) === 1;
    if ($yes === $no) return ''; // neither, or mixed
    $actor = normalizeParticipantNameToken(strval($npcData['name'] ?? ''));
    if ($actor === '' && $waiting === null) return '';
    if ($waiting === null) {
        $waiting = static function (string $who): string {
            try {
                $row = $GLOBALS['db']->fetchOne(
                    "SELECT goal_id FROM stobe_task_goal_runtime WHERE LOWER(actor_name)=LOWER($1) AND status='WAITING_APPROVAL' ORDER BY updated_at DESC LIMIT 1",
                    [$who]
                );
                return is_array($row) ? strval($row['goal_id'] ?? '') : '';
            } catch (Throwable $e) {
                return '';
            }
        };
    }
    $goal = strval($waiting($actor));
    if ($goal === '') return '';
    return 'TASK_CONTROL@' . ($yes ? 'APPROVE' : 'DECLINE') . '@' . $goal . '@0@';
}

/**
 * Item 43: the items a player's line asks her to hand over, in order:""")

patch("processor/chat.php",
"""if (!$narratorMode && function_exists('stobeInferFollowFromOrder')""",
"""if (!$narratorMode && function_exists('stobeInferApprovalFromReply')
    && !in_array($dealTurnDecision, ['ACCEPT','COUNTER','PROPOSE'], true)) {
    $inferredApproval = stobeInferApprovalFromReply(strval($GLOBALS['STOBE_CURRENT_PLAYER_MESSAGE'] ?? ''), $npcData, $responseActions);
    if ($inferredApproval !== '') {
        $responseActions = array_values(array_filter($responseActions, static fn($a) => !preg_match('/^(MOVE_TO|MOVE_TO_TARGET)@/i', strval($a))));
        $responseActions[] = $inferredApproval;
        stobeLogInfo('Spoken purchase approval: TASK_CONTROL added (item 113)', ['npc'=>$targetNpc, 'action'=>$inferredApproval]);
    }
}
if (!$narratorMode && function_exists('stobeInferFollowFromOrder')""")

patch("tests/goal_destination_regression.php",
"""// 111: "from the shop here\"""",
"""// 113: a spoken yes/no to a purchase waiting for approval (m18 Squin)
$wait113 = static fn(string $who): string => 'buy-wg-test-Fabrics';
check('item 113: "Yes, go ahead and buy the fabrics." -> APPROVE',
    stobeInferApprovalFromReply('Yes, go ahead and buy the fabrics.', $npc73, ['MOVE_TO_TARGET@Apothecary Marquart'], $wait113, true) === 'TASK_CONTROL@APPROVE@buy-wg-test-Fabrics@0@',
    stobeInferApprovalFromReply('Yes, go ahead and buy the fabrics.', $npc73, ['MOVE_TO_TARGET@Apothecary Marquart'], $wait113, true));
check('item 113: "No, don\\'t buy anything." -> DECLINE', stobeInferApprovalFromReply("No, don't buy anything.", $npc73, [], $wait113, true) === 'TASK_CONTROL@DECLINE@buy-wg-test-Fabrics@0@');
check('item 113: nothing waiting -> nothing', stobeInferApprovalFromReply('Yes, go ahead.', $npc73, [], static fn($w) => '', true) === '');
check('item 113: a question -> nothing', stobeInferApprovalFromReply('Should I buy the fabrics?', $npc73, [], $wait113, true) === '');
check('item 113: not a squad member -> nothing', stobeInferApprovalFromReply('Yes, go ahead.', false, [], $wait113) === '');
// 111: "from the shop here\"""")
