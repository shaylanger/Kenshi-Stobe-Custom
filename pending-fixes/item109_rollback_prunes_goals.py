#!/usr/bin/env python3
"""Item 109: loading an older save also drops goals from the abandoned timeline.

m18 Full-Base: Avarek's prompt still listed a COMPLETE "FETCH dried meat" goal from the m17 run of the same
save (created at game time 145360, after the save's 143636), so she said "Already fetched that one - it's in
your pack" and sent no goal. The playthrough rollback pruned eventlog/memory/history newer than the cutoff
but not the goal tables. Now stobe_task_goal_runtime and stobe_work_goal rows stamped after the cutoff
(created_game_ts > cutoff; unstamped 0 rows stay) are deleted too.

Usage: item109_rollback_prunes_goals.py <tree root>
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

patch("lib/playthrough_rollback.php",
"""        'player_base_presence_cleared' => 0,
    ];

    if (stobePlaythroughTableExists('eventlog')) {""",
"""        'player_base_presence_cleared' => 0,
        'task_goals' => 0,
        'work_goals' => 0,
    ];

    // Item 109: goals made in the abandoned timeline (stamped after the cutoff) go too; unstamped rows stay.
    foreach (['stobe_task_goal_runtime' => 'task_goals', 'stobe_work_goal' => 'work_goals'] as $goalTable => $goalKey) {
        if (stobePlaythroughTableExists($goalTable) && stobePlaythroughColumnExists($goalTable, 'created_game_ts')) {
            $counts[$goalKey] = stobePlaythroughDeleteCount(
                'WITH deleted AS (
                    DELETE FROM ' . $goalTable . '
                    WHERE created_game_ts > $1
                    RETURNING 1
                 ) SELECT COUNT(*)::int AS c FROM deleted',
                [$cutoff]
            );
        }
    }

    if (stobePlaythroughTableExists('eventlog')) {""")

patch("tests/playthrough_rollback_regression.php",
"""exit(0);""",
"""// Item 109: goals stamped after the cutoff belong to the abandoned timeline and are pruned; older and
// unstamped goals stay.
require_once __DIR__ . '/../lib/task_goal_functions.php';
stobeTaskGoalEnsureSchema();
$db->exec("DELETE FROM stobe_task_goal_runtime WHERE goal_id LIKE 'pt109-%'");
foreach (['pt109-future' => 5000, 'pt109-past' => 100, 'pt109-unstamped' => 0] as $gid => $gts) {
    $db->exec(
        "INSERT INTO stobe_task_goal_runtime (goal_id, actor_name, actor_serial, kind, item_name, quantity, status, created_game_ts)
         VALUES ($1, 'PT109 Avarek', 1, 'FETCH', 'dried meat', 1, 'COMPLETE', $2)",
        [$gid, $gts]
    );
}
$goalPrune = stobePlaythroughPruneFutureTimeline(1000);
$left = array_column($db->fetchAll("SELECT goal_id FROM stobe_task_goal_runtime WHERE goal_id LIKE 'pt109-%' ORDER BY goal_id") ?: [], 'goal_id');
ptAssert($left === ['pt109-past', 'pt109-unstamped'], 'item 109: future-timeline goal pruned, past/unstamped kept: ' . json_encode($left));
ptAssert(intval($goalPrune['task_goals'] ?? 0) >= 1, 'item 109: task_goals count reported');
$db->exec("DELETE FROM stobe_task_goal_runtime WHERE goal_id LIKE 'pt109-%'");
echo "PASS item 109 rollback prunes future-timeline goals" . PHP_EOL;

exit(0);""")
