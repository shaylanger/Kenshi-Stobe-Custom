#!/usr/bin/env python3
"""Bug 104 (server part): a loot goal that took 0 items was reported with
"You just finished the job (loot area all; 0/0 done)... tell Shay it's done",
so Malzin claimed the bodies were stripped. KenshiFP now ends such goals
BLOCKED; as a backstop the server never says "done" for a COMPLETE goal that
did nothing, and "0/0" (no fixed amount) reads as "N taken".
Usage: patch_r20_bug104_report.py <StobeServer tree root>"""
import sys, pathlib
root = pathlib.Path(sys.argv[1])

def patch(rel, pairs):
    p = root / rel; s = p.read_text()
    for a, b in pairs:
        if b in s: continue
        assert s.count(a) == 1, f"{rel}: anchor not found: {a[:70]!r}"
        s = s.replace(a, b)
    p.write_text(s); print("patched", p)

patch("lib/task_goal_functions.php", [
    ("""        $done=intval($row['completed']??0).'/'.intval($row['quantity']??0);
        $reason=trim(strval($row['reason']??''));
        $instruction=match($status){""",
     """        $doneN=intval($row['completed']??0);$qty=intval($row['quantity']??0);
        $done=$qty>0?$doneN.'/'.$qty:$doneN.' taken';
        $reason=trim(strval($row['reason']??''));
        if($status==='COMPLETE'&&$doneN===0&&$kindWord!=='work'){ // bug 104: nothing done is not "done"
            $instruction="You tried the job {$player} gave you ({$what}) but found nothing to do: nothing matching was there. Tell {$player} plainly, in your own voice, that you found nothing. Don't claim you took, moved or finished anything.";
            stobeNegQueueDirective($actor,'goal_report',$id,['instruction'=>$instruction,'actions'=>[]],false);
            stobeLogInfo('Goal report queued',['actor'=>$actor,'goal_id'=>$id,'status'=>'COMPLETE_EMPTY']);
            $queued++;
            continue;
        }
        $instruction=match($status){"""),
])
