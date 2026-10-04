#!/usr/bin/env python3
"""m24 fixer 13 (16-fullbase step 63): the goal status-file sync resurrected goals and made them look fresh.
Batch G: loading kah-fullbase rolled back (item 109) and deleted the earlier run's BLOCKED Junkbow goal (wg-5490d01b,
"no ... crafting bench ... can provide Junkbow"), but Stobe's stobe_work_goal.status still listed it; the next prompt's
sync re-INSERTed it with updated_at=NOW() (and created_game_ts 0, so no later rollback removes it), and every sync
UPDATE also set updated_at=NOW() even when nothing changed. So the prompt said "BLOCKED Junkbow, ended 0 min ago,
no crafting bench" and Avarek refused ("I tried that already. There's no crossbow bench here"), no WORK_GOAL.
Fix (work + task goals): an ended goal missing from the DB is not inserted (it was rolled back or pruned);
an unchanged row keeps its updated_at. Status file paths overridable by env for the regression test.
Usage: m24-f13-goal-sync.py <tree root>   (edits in place: run on a copy, then mv)
"""
import sys
root = sys.argv[1].rstrip('/')

def patch(rel, pairs):
    p = root + '/' + rel
    s = open(p, encoding='utf-8').read()
    for old, new in pairs:
        n = s.count(old)
        if n != 1:
            sys.exit(f'{rel}: anchor count {n} != 1: {old[:90]!r}')
        s = s.replace(old, new)
    open(p, 'w', encoding='utf-8').write(s)
    print('patched', rel)

patch('lib/work_goal_functions.php', [
    ("    $path = '/mnt/d/Steam/steamapps/common/Kenshi/RE_Kenshi/mods/Stobe/stobe_work_goal.status';\n",
     "    $path = strval(getenv('STOBE_WORK_GOAL_STATUS_FILE') ?: '/mnt/d/Steam/steamapps/common/Kenshi/RE_Kenshi/mods/Stobe/stobe_work_goal.status');\n"),
    ("""                 SET status=$2, completed=$3, current_step=$4, reason=$5, updated_at=NOW()
                 WHERE goal_id=$1",""",
     """                 SET status=$2, completed=$3, current_step=$4, reason=$5,
                     -- M24_F13: an unchanged line keeps its age (every prompt syncs; NOW() made ended goals read 0 min old)
                     updated_at=CASE WHEN status IS DISTINCT FROM $2 OR completed IS DISTINCT FROM $3
                                       OR current_step IS DISTINCT FROM $4 OR reason IS DISTINCT FROM $5
                                     THEN NOW() ELSE updated_at END
                 WHERE goal_id=$1","""),
    ("""        } else {
            $safeActor = normalizeParticipantNameToken($actor);
            $safeItem = substr(trim(strval($item)), 0, 160);
            $safeDestination = substr(trim(strval($destination)), 0, 160);
            $safeQuantity = max(1, min(1000, intval($quantity)));
            if ($safeActor !== '' && $safeItem !== '') {""",
     """        } else {
            // M24_F13: an ended goal missing from the DB was rolled back (item 109) or pruned: don't resurrect it
            // as a fresh "ended 0 min ago" blocker (16-fullbase m22 G: stale BLOCKED Junkbow -> Avarek refused).
            if (stobeGoalStatusEnded($status)) {
                continue;
            }
            $safeActor = normalizeParticipantNameToken($actor);
            $safeItem = substr(trim(strval($item)), 0, 160);
            $safeDestination = substr(trim(strval($destination)), 0, 160);
            $safeQuantity = max(1, min(1000, intval($quantity)));
            if ($safeActor !== '' && $safeItem !== '') {"""),
])

patch('lib/task_goal_functions.php', [
    ("    $path='/mnt/d/Steam/steamapps/common/Kenshi/RE_Kenshi/mods/Stobe/stobe_task_goal.status';\n",
     "    $path=strval(getenv('STOBE_TASK_GOAL_STATUS_FILE') ?: '/mnt/d/Steam/steamapps/common/Kenshi/RE_Kenshi/mods/Stobe/stobe_task_goal.status');\n"),
    ("max_spend=GREATEST(max_spend,$7),spent=$8,approved_purchase=$9,updated_at=NOW()\n",
     "max_spend=GREATEST(max_spend,$7),spent=$8,approved_purchase=$9,\n"
     "                        updated_at=CASE WHEN status IS DISTINCT FROM $2 OR completed IS DISTINCT FROM $3 OR current_step IS DISTINCT FROM $4\n"
     "                                          OR reason IS DISTINCT FROM $5 OR spent IS DISTINCT FROM $8 OR approved_purchase IS DISTINCT FROM $9\n"
     "                                        THEN NOW() ELSE updated_at END\n"),
    ("""        } else {
            // Includes automatic last-resort purchase approvals spawned by KenshiFP.
""",
     """        } else {
            // M24_F13: an ended goal missing from the DB was rolled back or pruned: don't resurrect it as fresh.
            if(stobeGoalStatusEnded($status))continue;
            // Includes automatic last-resort purchase approvals spawned by KenshiFP.
"""),
])

patch('tests/ended_goal_history_regression.php', [
    ("""echo "SUMMARY pass=$pass fail=$fail\\n";
""",
     """// M24_F13 (16-fullbase m22 G): the status-file sync must not resurrect a goal the rollback deleted, nor make an
// unchanged ended goal read "0 min ago".
$sf = tempnam(sys_get_temp_dir(), 'wgs'); putenv('STOBE_WORK_GOAL_STATUS_FILE=' . $sf);
file_put_contents($sf, "r121-g\\tR121Sync\\tBLOCKED\\tJunkbow\\t2\\t0\\tYour Outpost\\tTraveling\\tno usable mine, farm, production machine, crafting bench, or approved nearby purchase route can provide Junkbow\\n");
$s = stobeBuildWorkGoalStateBlock('R121Sync');
check('sync: a rolled-back ended goal is not resurrected', !str_contains($s, 'Junkbow'), $s);
$wg('r121-h', 'R121Sync2', 'Junkbow', 'BLOCKED', 'Traveling', 'no crafting bench can provide Junkbow', 60);
file_put_contents($sf, "r121-h\\tR121Sync2\\tBLOCKED\\tJunkbow\\t2\\t0\\tHome\\tTraveling\\tno crafting bench can provide Junkbow\\n");
$s2 = stobeBuildWorkGoalStateBlock('R121Sync2');
check('sync: an unchanged ended goal keeps its age', str_contains($s2, 'ended_minutes_ago="60"') && !str_contains($s2, 'crafting bench'), $s2);
$tf = tempnam(sys_get_temp_dir(), 'tgs'); putenv('STOBE_TASK_GOAL_STATUS_FILE=' . $tf);
file_put_contents($tf, "r121-t1\\tR121Task\\tCANCELLED\\tFETCH\\tWheatstraw\\t20\\t0\\tStorage Chest\\t\\tWalking to Storage Chest\\tStorage Chest has no Wheatstraw\\t0\\t0\\t0\\n"
    . "r121-t2\\tR121Task2\\tBLOCKED\\tFETCH\\tNails\\t2\\t0\\tStorage Chest\\t\\tWalking\\tStorage Chest has no Nails\\t0\\t0\\t0\\n");
$t2 = stobeBuildTaskGoalStateBlock('R121Task');
check('task sync: an unchanged ended goal keeps its age', str_contains($t2, 'ended_minutes_ago="4"'), $t2);
$t3 = stobeBuildTaskGoalStateBlock('R121Task2');
check('task sync: a rolled-back ended goal is not resurrected', !str_contains($t3, 'Nails'), $t3);
putenv('STOBE_WORK_GOAL_STATUS_FILE'); putenv('STOBE_TASK_GOAL_STATUS_FILE'); @unlink($sf); @unlink($tf);

echo "SUMMARY pass=$pass fail=$fail\\n";
"""),
])
