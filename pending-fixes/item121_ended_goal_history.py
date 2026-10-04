#!/usr/bin/env python3
"""Item 121: ended goals (COMPLETE/CANCELLED/BLOCKED) are rendered in the prompt as past history,
not as current blockers. Old "Grain Silo has no power" reasons of cancelled Bread goals made the
NPC refuse a fresh, feasible "make 2 bread" order.
- work_goals / task_goals: ended goals get ended_minutes_ago, no current_step, no reason
  (except a BLOCKED goal that ended <= 15 min ago: one <history> line, phrased as past);
- an ended goal superseded by a newer goal for the same output is dropped;
- new rules: ended goals are history; never turn down a new order because of one.
Usage: python3 item121_ended_goal_history.py <tree-root>
"""
import sys, pathlib

root = pathlib.Path(sys.argv[1])


def patch(rel, pairs):
    p = root / rel
    s = p.read_text()
    for old, new in pairs:
        if new in s and old not in s:
            print(f"{rel}: already patched hunk")
            continue
        assert s.count(old) == 1, f"{rel}: anchor not found once: {old[:80]!r}"
        s = s.replace(old, new)
    p.write_text(s)
    print(f"{rel}: ok")


WG_SELECT_OLD = """            "SELECT goal_id, item_name, quantity, destination_name,
                    status, completed, current_step, reason
             FROM stobe_work_goal
             WHERE LOWER(actor_name)=LOWER($1)"""
WG_SELECT_NEW = """            "SELECT goal_id, item_name, quantity, destination_name,
                    status, completed, current_step, reason,
                    GREATEST(0, FLOOR(EXTRACT(EPOCH FROM (NOW() - updated_at)) / 60))::int AS age_min
             FROM stobe_work_goal
             WHERE LOWER(actor_name)=LOWER($1)"""

WG_RULE_OLD = """    $lines[] = '  <rule>Do not claim a blocked or incomplete goal succeeded. If a goal is blocked, explain its recorded reason naturally when relevant.</rule>';
    foreach ($rows as $row) {
        if (!is_array($row)) {
            continue;
        }
        $status = strtoupper(trim(strval($row['status'] ?? 'ACTIVE')));
        $item = trim(strval($row['item_name'] ?? ''));"""
WG_RULE_NEW = """    $lines[] = '  <rule>Do not claim a blocked or incomplete goal succeeded. If a current goal is blocked, explain its recorded reason naturally when relevant.</rule>';
    foreach (stobeEndedGoalRules() as $rule) {
        $lines[] = '  <rule>' . $rule . '</rule>';
    }
    $seenOutputs = [];
    foreach ($rows as $row) {
        if (!is_array($row)) {
            continue;
        }
        $status = strtoupper(trim(strval($row['status'] ?? 'ACTIVE')));
        $item = trim(strval($row['item_name'] ?? ''));
        // Item 121: an ended goal is history; a newer goal for the same output supersedes it.
        $ended = stobeGoalStatusEnded($status);
        $outputKey = strtolower($item);
        if ($ended && isset($seenOutputs[$outputKey])) {
            continue;
        }
        $seenOutputs[$outputKey] = true;"""

WG_BODY_OLD = """        $lines[] = '  <goal' . $attrs . '>';
        if ($step !== '') {
            $lines[] = '    <current_step>' . stobePromptXmlEscape($step) . '</current_step>';
        }
        if ($reason !== '') {
            $lines[] = '    <blocker>' . stobePromptXmlEscape($reason) . '</blocker>';
        }
        $lines[] = '  </goal>';
    }
    $lines[] = '</work_goals>';
    return implode("\\n", $lines);
}"""
WG_BODY_NEW = """        if ($ended) {
            $ageMin = max(0, intval($row['age_min'] ?? 0));
            $lines[] = '  <goal' . $attrs . ' ended_minutes_ago="' . $ageMin . '">';
            $history = stobeEndedGoalHistoryNote($status, $ageMin, $reason);
            if ($history !== '') {
                $lines[] = '    <history>' . stobePromptXmlEscape($history) . '</history>';
            }
            $lines[] = '  </goal>';
            continue;
        }
        $lines[] = '  <goal' . $attrs . '>';
        if ($step !== '') {
            $lines[] = '    <current_step>' . stobePromptXmlEscape($step) . '</current_step>';
        }
        if ($reason !== '') {
            $lines[] = '    <blocker>' . stobePromptXmlEscape($reason) . '</blocker>';
        }
        $lines[] = '  </goal>';
    }
    $lines[] = '</work_goals>';
    return implode("\\n", $lines);
}

/** Item 121: COMPLETE / CANCELLED / BLOCKED goals have ended (BLOCKED = she stopped and walked back). */
function stobeGoalStatusEnded(string $status): bool
{
    return !in_array(strtoupper(trim($status)), ['ACTIVE', 'PAUSED', 'WAITING_APPROVAL'], true);
}

/** Item 121: prompt rules for ended goals (shared by work_goals and task_goals). */
function stobeEndedGoalRules(): array
{
    return [
        'Goals with ended_minutes_ago have ended (COMPLETE, CANCELLED or BLOCKED). They are past history, not the current state: power, materials, stations and stock may have changed since.',
        'Never turn down a new order because of an ended goal. When the player orders new work, take it on and start a new goal; the planner checks power, materials and stations right now and reports any real blocker itself.',
    ];
}

/**
 * Item 121: what an ended goal may still say. Only a BLOCKED goal that ended at most 15 minutes ago
 * keeps its reason, phrased as past (the player may ask why she stopped). Cancelled and completed
 * goals and older blocks keep nothing: their old blockers read like current facts to the model.
 */
function stobeEndedGoalHistoryNote(string $status, int $ageMin, string $reason): string
{
    $reason = trim($reason);
    if (strtoupper(trim($status)) !== 'BLOCKED' || $reason === '' || $ageMin > 15) {
        return '';
    }
    return 'Past, may no longer be true: ' . $ageMin . ' min ago she stopped because ' . $reason;
}"""

TG_SELECT_OLD = """                    current_step,reason,max_spend,spent
             FROM stobe_task_goal_runtime WHERE LOWER(actor_name)=LOWER($1)"""
TG_SELECT_NEW = """                    current_step,reason,max_spend,spent,
                    GREATEST(0,FLOOR(EXTRACT(EPOCH FROM (NOW()-updated_at))/60))::int AS age_min
             FROM stobe_task_goal_runtime WHERE LOWER(actor_name)=LOWER($1)"""

TG_LOOP_OLD = """    foreach($rows as $r){
        $attrs=' kind="'.stobePromptXmlEscape(strval($r['kind']??'')).'" status="'.stobePromptXmlEscape(strval($r['status']??'')).'"';"""
TG_LOOP_NEW = """    if(function_exists('stobeEndedGoalRules'))foreach(stobeEndedGoalRules() as $rule)$o[]='  <rule>'.$rule.'</rule>';
    $seen=[];
    foreach($rows as $r){
        // Item 121: ended goals are history; a newer goal of the same kind+item supersedes them.
        $st=strtoupper(trim(strval($r['status']??'')));
        $ended=function_exists('stobeGoalStatusEnded')&&stobeGoalStatusEnded($st);
        $key=strtolower(strval($r['kind']??'').'|'.trim(strval($r['item_name']??'')));
        if($ended&&isset($seen[$key]))continue;
        $seen[$key]=true;
        $attrs=' kind="'.stobePromptXmlEscape(strval($r['kind']??'')).'" status="'.stobePromptXmlEscape(strval($r['status']??'')).'"';"""

TG_BODY_OLD = """        $o[]='  <goal'.$attrs.'>';
        if(trim(strval($r['current_step']??''))!=='')$o[]='    <current_step>'.stobePromptXmlEscape(strval($r['current_step'])).'</current_step>';"""
TG_BODY_NEW = """        if($ended){
            $age=max(0,intval($r['age_min']??0));
            $o[]='  <goal'.$attrs.' ended_minutes_ago="'.$age.'">';
            $h=stobeEndedGoalHistoryNote($st,$age,strval($r['reason']??''));
            if($h!=='')$o[]='    <history>'.stobePromptXmlEscape($h).'</history>';
            $o[]='  </goal>';
            continue;
        }
        $o[]='  <goal'.$attrs.'>';
        if(trim(strval($r['current_step']??''))!=='')$o[]='    <current_step>'.stobePromptXmlEscape(strval($r['current_step'])).'</current_step>';"""

patch("lib/work_goal_functions.php", [(WG_SELECT_OLD, WG_SELECT_NEW), (WG_RULE_OLD, WG_RULE_NEW), (WG_BODY_OLD, WG_BODY_NEW)])
patch("lib/task_goal_functions.php", [(TG_SELECT_OLD, TG_SELECT_NEW), (TG_LOOP_OLD, TG_LOOP_NEW), (TG_BODY_OLD, TG_BODY_NEW)])
