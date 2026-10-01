#!/usr/bin/env python3
"""Bug 76: a plain "make N X" order to a faction member came back as a question
with no WORK_GOAL -> infer the WORK_GOAL as a late action.
Bug 77: "put them back in the chest" after fetching two items queued one STORE
-> "them/those/both/everything" expands to every item of the actor's last FETCH batch.
Usage: patch_r19_bug76_77_orders.py <StobeServer tree root>"""
import sys, pathlib
root = pathlib.Path(sys.argv[1])

def patch(rel, pairs):
    p = root / rel; s = p.read_text()
    for a, b in pairs:
        if b in s: continue
        assert s.count(a) == 1, f"{rel}: anchor not found: {a[:70]!r}"
        s = s.replace(a, b)
    p.write_text(s); print("patched", p)

FUNCS = r'''
/**
 * Bug 77: "put them back" after a fetch -> every item of the actor's latest
 * FETCH batch (goals queued within 10 s of each other, last 60 min).
 */
function stobeTaskStorePronounItems(string $actor, string $item): array {
    $line = strtolower(trim(strval($GLOBALS['STOBE_CURRENT_PLAYER_MESSAGE'] ?? '')));
    if ($actor === '' || $line === ''
        || !preg_match('/\b(them|those|these|both|everything|all\s+of\s+(?:it|them))\b/', $line)) return [];
    try {
        $rows = $GLOBALS['db']->fetchAll(
            "SELECT item_name, EXTRACT(EPOCH FROM created_at) AS ts FROM stobe_task_goal_runtime
             WHERE LOWER(actor_name)=LOWER($1) AND kind='FETCH' AND created_at > NOW() - INTERVAL '60 minutes'
             ORDER BY created_at DESC LIMIT 6", [$actor]);
    } catch (Throwable $e) {
        return [];
    }
    if (!is_array($rows) || count($rows) < 2) return [];
    $newest = floatval($rows[0]['ts'] ?? 0);
    $items = [];
    foreach ($rows as $row) {
        if ($newest - floatval($row['ts'] ?? 0) > 10.0) break;
        $name = trim(strval($row['item_name'] ?? ''));
        if ($name !== '' && !in_array(strtolower($name), array_map('strtolower', $items), true)) $items[] = $name;
    }
    if (count($items) < 2) return [];
    $one = strtolower(trim($item));
    if ($one !== '' && $one !== 'all') {
        $hit = false;
        foreach ($items as $i) {
            $li = strtolower($i);
            if (str_contains($li, $one) || str_contains($one, $li)) { $hit = true; break; }
        }
        if (!$hit) return [];
    }
    return array_reverse($items);
}

/**
 * Bug 76: a plain production order to a squad member ("Make 3 steel bars.")
 * that the model answered without a goal action -> WORK_GOAL@Item@N.
 * The planner reports BLOCKED itself when nothing can make it.
 */
function stobeInferWorkGoalFromOrder(string $playerLine, array|false $npcData, array $actions): string {
    if (!is_array($npcData) || !function_exists('npcIsInPlayerFaction') || !npcIsInPlayerFaction($npcData)) return '';
    foreach ($actions as $a) {
        if (preg_match('/^(WORK_GOAL|TASK_GOAL|TASK_CONTROL)@/i', strval($a))) return '';
    }
    $line = trim($playerLine);
    if ($line === '' || str_contains($line, '?')) return '';
    if (preg_match("/\b(don'?t|do\s+not|stop|never|no\s+need|cancel)\b/i", $line)) return '';
    $words = ['a'=>1,'an'=>1,'one'=>1,'two'=>2,'three'=>3,'four'=>4,'five'=>5,'six'=>6,'seven'=>7,
        'eight'=>8,'nine'=>9,'ten'=>10,'twelve'=>12,'twenty'=>20];
    if (!preg_match("/(?:^|[.!,;]\s*|\b(?:just|please|now|then|and)\s+)(?:make|craft|produce|smelt|cook|bake|brew)\s+(?:me\s+|us\s+)?(\d{1,4}|a|an|one|two|three|four|five|six|seven|eight|nine|ten|twelve|twenty)\s+([a-z][a-z' -]{1,40}?)(?=\s*(?:\band\b|\bfor\b|\bat\b|\bfrom\b|\bthen\b|[,.!;]|$))/i", $line, $m)) return '';
    $qty = ctype_digit($m[1]) ? intval($m[1]) : ($words[strtolower($m[1])] ?? 0);
    if ($qty < 1 || $qty > 1000) return '';
    $item = trim(preg_replace('/\s+/', ' ', $m[2]) ?? '');
    $parts = explode(' ', $item);
    $last = array_pop($parts);
    if (strlen($last) > 3 && preg_match('/[^s]s$/i', $last)) $last = substr($last, 0, -1);
    $parts[] = $last;
    $item = ucwords(strtolower(implode(' ', $parts)));
    if ($item === '' || preg_match('/^(it|them|that|this|some|more|sure)$/i', $item)) return '';
    return 'WORK_GOAL@' . $item . '@' . $qty;
}
'''

patch("lib/chat_helper_functions.php", [
    ("/** Work orders a non-faction NPC never takes from the player (feature 1). */",
     FUNCS.lstrip("\n") + "\n/** Work orders a non-faction NPC never takes from the player (feature 1). */"),
    ("""            $taskResults = [];
            if ($taskKind === 'BATTLE_CLEANUP') {""",
     """            $taskResults = [];
            if ($taskKind === 'STORE' && count(stobeTaskItemListFromTurn($taskItem)) <= 1
                && count($pronounItems = stobeTaskStorePronounItems($actor, $taskItem)) > 1) {
                stobeLogInfo('STORE expanded to the last fetched items (bug 77)', ['actor'=>$actor,'item'=>$taskItem,'items'=>$pronounItems]);
                $taskItem = implode(', ', $pronounItems);
            }
            if ($taskKind === 'BATTLE_CLEANUP') {"""),
])

patch("processor/chat.php", [
    ("""        stobeLogInfo('Clothing action inferred from speech', ['npc'=>$targetNpc, 'action'=>$inferredAction, 'text'=>$responseText]);
    }
}
if (!$narratorMode && function_exists('stobeNegAttachPendingForChat')) {""",
     """        stobeLogInfo('Clothing action inferred from speech', ['npc'=>$targetNpc, 'action'=>$inferredAction, 'text'=>$responseText]);
    }
}
if (!$narratorMode && function_exists('stobeInferWorkGoalFromOrder')
    && !in_array($dealTurnDecision, ['ACCEPT','COUNTER','PROPOSE'], true)) {
    $inferredGoal = stobeInferWorkGoalFromOrder(strval($GLOBALS['STOBE_CURRENT_PLAYER_MESSAGE'] ?? ''), $npcData, $responseActions);
    if ($inferredGoal !== '') {
        $responseActions[] = $inferredGoal;
        stobeLogInfo('Work goal inferred from a direct order (bug 76)', ['npc'=>$targetNpc, 'action'=>$inferredGoal]);
    }
}
if (!$narratorMode && function_exists('stobeNegAttachPendingForChat')) {"""),
])
