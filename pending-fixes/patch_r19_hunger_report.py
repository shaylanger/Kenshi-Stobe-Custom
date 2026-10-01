#!/usr/bin/env python3
"""Round 19 meals: KenshiFP writes '<id>\t<actor>\thunger' to
stobe_goal_report.request when she is hungry and there's no food in her pack
or base storage. Queue a goal_report directive so she says so once.
Usage: patch_r19_hunger_report.py <StobeServer tree root>"""
import sys, pathlib
p = pathlib.Path(sys.argv[1]) / "lib/task_goal_functions.php"; s = p.read_text()
a = """        [$id,$actor,$type]=[trim($p[0]),normalizeParticipantNameToken(trim($p[1])),trim($p[2])];
"""
b = """        [$id,$actor,$type]=[trim($p[0]),normalizeParticipantNameToken(trim($p[1])),trim($p[2])];
        if($type==='hunger'){
            if($actor==='')continue;
            $instruction="You're getting hungry and there's no food in your pack or in the base's storage. Tell {$player} briefly, in your own voice, that you're hungry and there's no food. You keep working for now. Don't claim you ate.";
            stobeNegQueueDirective($actor,'goal_report',$id,['instruction'=>$instruction,'actions'=>[]],false);
            stobeLogInfo('Hunger report queued',['actor'=>$actor,'id'=>$id]);
            $queued++;
            continue;
        }
"""
if b not in s:
    assert s.count(a) == 1, "anchor not found"
    s = s.replace(a, b)
p.write_text(s); print("patched", p)
