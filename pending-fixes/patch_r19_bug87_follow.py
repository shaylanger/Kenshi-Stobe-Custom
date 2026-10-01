#!/usr/bin/env python3
"""Bug 87: "Malzin, follow me." -> "Following you, then." with no action.
A plain follow/guard request to a faction member that the model answered
without a movement action -> add BODYGUARD@<player> as a late action
(KenshiFP turns squad->squad BODYGUARD into the follow order, bug 86).
Usage: patch_r19_bug87_follow.py <StobeServer tree root>"""
import sys, pathlib
root = pathlib.Path(sys.argv[1])

def patch(rel, pairs):
    p = root / rel; s = p.read_text()
    for a, b in pairs:
        if b in s: continue
        assert s.count(a) == 1, f"{rel}: anchor not found: {a[:70]!r}"
        s = s.replace(a, b)
    p.write_text(s); print("patched", p)

FUNC = r'''/**
 * Bug 87: "follow me" / "guard me" to a squad member answered without a
 * movement action -> BODYGUARD@<player>.
 */
function stobeInferFollowFromOrder(string $playerLine, array|false $npcData, array $actions, string $playerName): string {
    if ($playerName === '' || !is_array($npcData) || !function_exists('npcIsInPlayerFaction') || !npcIsInPlayerFaction($npcData)) return '';
    foreach ($actions as $a) {
        if (preg_match('/^(FOLLOW|BODYGUARD|GUARD_TARGET|MOVE_TO|MOVE_TO_TARGET|HOLD_POSITION|PATROL|ATTACK|STOP_ATTACK|TRAVEL_LOCATION|WORK_GOAL|TASK_GOAL)@/i', strval($a))) return '';
    }
    $line = trim($playerLine);
    if ($line === '' || preg_match("/\b(don'?t|do\s+not|stop|quit|no\s+longer|never)\b/i", $line)) return '';
    if (!preg_match('/\b(follow\s+me|guard\s+me|protect\s+me|cover\s+me|watch\s+my\s+back|come\s+with\s+me|stay\s+(?:close|with\s+me|near\s+me)|stick\s+(?:close|with\s+me)|keep\s+up\s+with\s+me)\b/i', $line)) return '';
    return 'BODYGUARD@' . $playerName;
}

'''

patch("lib/chat_helper_functions.php", [
    ("/** Work orders a non-faction NPC never takes from the player (feature 1). */",
     FUNC + "/** Work orders a non-faction NPC never takes from the player (feature 1). */"),
])
patch("processor/chat.php", [
    ("""        $responseActions[] = $inferredGoal;
        stobeLogInfo('Work goal inferred from a direct order (bug 76)', ['npc'=>$targetNpc, 'action'=>$inferredGoal]);
    }
}""",
     """        $responseActions[] = $inferredGoal;
        stobeLogInfo('Work goal inferred from a direct order (bug 76)', ['npc'=>$targetNpc, 'action'=>$inferredGoal]);
    }
}
if (!$narratorMode && function_exists('stobeInferFollowFromOrder')
    && !in_array($dealTurnDecision, ['ACCEPT','COUNTER','PROPOSE'], true)) {
    $inferredFollow = stobeInferFollowFromOrder(strval($GLOBALS['STOBE_CURRENT_PLAYER_MESSAGE'] ?? ''), $npcData, $responseActions,
        trim(strval(getSetting('PLAYER_NAME', ''))));
    if ($inferredFollow !== '') {
        $responseActions[] = $inferredFollow;
        stobeLogInfo('Follow inferred from a direct request (bug 87)', ['npc'=>$targetNpc, 'action'=>$inferredFollow]);
    }
}"""),
])
