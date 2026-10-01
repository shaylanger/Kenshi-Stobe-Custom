#!/usr/bin/env python3
"""Server round 17f (bug 55): "keep N stocked" becomes a STOCK goal, not a one-off WORK_GOAL.

Run 4: "keep at least 12 building materials stocked here at Home" -> the model
emitted WORK_GOAL@Home@Building Material@12 (make 12 more, once). When the
player's line asks to keep/maintain a stock (stocked, in stock, on hand,
always have, never run out, maintain), the WORK_GOAL is queued as
TASK_GOAL STOCK with minimum = the amount.

Requires round 17e (anchor is the 17e resume block).
Usage: patch_round17f.py <StobeServer root>
"""
import sys, pathlib

f = pathlib.Path(sys.argv[1]) / "lib" / "chat_helper_functions.php"
s = f.read_text()
old = """            $goalResult = null;
            $resumeLine = strtolower(strval($GLOBALS['STOBE_CURRENT_PLAYER_MESSAGE'] ?? ''));"""
new = """            $goalResult = null;
            $stockLine = strtolower(strval($GLOBALS['STOBE_CURRENT_PLAYER_MESSAGE'] ?? ''));
            if ($goalItem !== '' && $goalQuantity > 0 && function_exists('stobeTaskGoalQueue')
                && preg_match('/\\b(stocked|in\\s+stock|on\\s+hand|always\\s+have|never\\s+run\\s+(?:out|low)|maintain|keep\\s+(?:\\w+\\s+){0,4}(?:topped|stocked|in\\s+stock|on\\s+hand|around|supplied))\\b/', $stockLine) === 1) {
                $stockResult = stobeTaskGoalQueue(
                    $actor, 'STOCK', $goalItem, '', $goalDestination, $goalQuantity,
                    false, $goalQuantity, 0, false, $effectiveDeliveryGamets
                );
                stobeLogInfo('WORK_GOAL turned into STOCK goal (player asked to keep a stock)', ['actor' => $actor, 'item' => $goalItem, 'minimum' => $goalQuantity, 'ok' => boolval($stockResult['ok'] ?? false)]);
                $goalResult = $stockResult;
            }
            $resumeLine = $goalResult === null ? strtolower(strval($GLOBALS['STOBE_CURRENT_PLAYER_MESSAGE'] ?? '')) : '';"""
assert s.count(old) == 1, "anchor (needs round 17e)"
f.write_text(s.replace(old, new))
print("patched", f)
