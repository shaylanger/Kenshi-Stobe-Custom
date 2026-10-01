#!/usr/bin/env python3
"""Server round 17e (bug 53): "resume / continue / try again" resumes the existing goal.

Run 4 (three times): "Resume the building materials", "Okay, resume the building
materials", "try the bread again" -> the model emitted a new WORK_GOAL instead of
TASK_CONTROL@RESUME, leaving the PAUSED/BLOCKED goal behind as a duplicate.
When the player's line asks to resume/continue/carry on/try again and the actor
already has a PAUSED or BLOCKED work goal for that item, the WORK_GOAL becomes
RESUME of that goal (KenshiFP round 17 restarts BLOCKED goals on RESUME).

Usage: patch_round17e.py <StobeServer root>
"""
import sys, pathlib

f = pathlib.Path(sys.argv[1]) / "lib" / "chat_helper_functions.php"
s = f.read_text()
old = """            $goalResult = stobeQueueWorkGoalRequest(
                $actor,
                $goalItem,
                $goalQuantity,
                $goalDestination,
                $effectiveDeliveryGamets
            );"""
new = """            $goalResult = null;
            $resumeLine = strtolower(strval($GLOBALS['STOBE_CURRENT_PLAYER_MESSAGE'] ?? ''));
            if ($goalItem !== '' && $resumeLine !== '' && function_exists('stobeAnyGoalControl')
                && preg_match('/\\b(resume|continue|carry\\s+on|keep\\s+going|pick\\s+(?:it\\s+)?(?:back\\s+)?up|try\\s+(?:\\w+\\s+){0,3}again|start\\s+(?:\\w+\\s+){0,3}again|unpause)\\b/', $resumeLine) === 1) {
                try {
                    if (function_exists('stobeWorkGoalSyncStatusFile')) stobeWorkGoalSyncStatusFile();
                    $paused = $GLOBALS['db']->fetchOne(
                        "SELECT goal_id FROM stobe_work_goal WHERE LOWER(actor_name)=LOWER($1)
                           AND status IN ('PAUSED','BLOCKED') AND LOWER(item_name)=LOWER($2)
                         ORDER BY updated_at DESC LIMIT 1",
                        [normalizeParticipantNameToken($actor), $goalItem]
                    );
                    if (is_array($paused)) {
                        $resumeResult = stobeAnyGoalControl($actor, 'RESUME', $goalItem);
                        if (boolval($resumeResult['ok'] ?? false)) {
                            stobeLogInfo('WORK_GOAL turned into RESUME of the existing goal', ['actor' => $actor, 'item' => $goalItem, 'goal_id' => strval($resumeResult['goal_id'] ?? '')]);
                            $goalResult = ['ok' => true, 'goal_id' => strval($resumeResult['goal_id'] ?? ''), 'resumed' => true];
                        }
                    }
                } catch (Throwable $e) {
                    stobeLogWarn('Resume lookup failed', ['error' => $e->getMessage()]);
                }
            }
            if ($goalResult === null) {
                $goalResult = stobeQueueWorkGoalRequest(
                    $actor,
                    $goalItem,
                    $goalQuantity,
                    $goalDestination,
                    $effectiveDeliveryGamets
                );
            }"""
assert s.count(old) == 1, "anchor"
f.write_text(s.replace(old, new))
print("patched", f)
