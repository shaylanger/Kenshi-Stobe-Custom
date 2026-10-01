#!/usr/bin/env python3
"""Server round 17i (bug 59): an NPC reports her finished/blocked goal to the player.

KenshiFP (round 17f) appends "<goal id>\\t<actor>\\t<work|task>" to
stobe_goal_report.request and Stobe.dll (round 17d) arms an initiative turn. On that
bored/initiative turn the server reads the file, looks the goal up (after syncing
the status files) and queues a 'goal_report' negotiation-style directive with an
instruction, so that NPC takes the turn and tells the player the result (or the
block reason) and asks what's next. Uses the existing directive pipeline
(claim, listener = player, restore on LLM failure).

Usage: patch_round17i.py <StobeServer root>
"""
import sys, pathlib

root = pathlib.Path(sys.argv[1])

def patch(rel, pairs):
    f = root / rel
    s = f.read_text()
    for old, new in pairs:
        n = s.count(old)
        assert n == 1, f"{rel}: anchor count {n}: {old[:70]!r}"
        s = s.replace(old, new)
    f.write_text(s)
    print("patched", f)

patch("lib/task_goal_functions.php", [
    ("function stobeAnyGoalControl(string $actor,string $command,string $selector='',int $quantity=0,string $destination=''): array\n{",
     r'''/**
 * Bug 59: KenshiFP lists goals that just ended near the player in stobe_goal_report.request.
 * Turn each into a 'goal_report' directive so that NPC reports the result on the next
 * initiative turn. Returns the number of directives queued.
 */
function stobeGoalReportQueuePending(): int
{
    $path='/mnt/d/Steam/steamapps/common/Kenshi/RE_Kenshi/mods/Stobe/stobe_goal_report.request';
    if(!is_file($path)||filesize($path)<=0||!function_exists('stobeNegQueueDirective'))return 0;
    $fh=@fopen($path,'c+');
    if(!$fh)return 0;
    $lines=[];
    if(flock($fh,LOCK_EX)){
        $raw=stream_get_contents($fh);
        ftruncate($fh,0);fflush($fh);flock($fh,LOCK_UN);
        $lines=preg_split('/\r?\n/',strval($raw))?:[];
    }
    fclose($fh);
    if(!$lines)return 0;
    try{stobeWorkGoalSyncStatusFile();}catch(Throwable){}
    try{stobeTaskGoalSyncStatusFile();}catch(Throwable){}
    $player=function_exists('getSetting')?trim(strval(getSetting('PLAYER_NAME',''))):'';
    $player=$player!==''?ucfirst($player):'the player';
    $queued=0;
    foreach(array_slice($lines,0,8) as $line){
        $p=explode("\t",trim(strval($line)));
        if(count($p)<3||trim($p[0])==='')continue;
        [$id,$actor,$type]=[trim($p[0]),normalizeParticipantNameToken(trim($p[1])),trim($p[2])];
        $row=$type==='task'
            ?$GLOBALS['db']->fetchOne("SELECT kind,item_name,quantity,completed,status,reason FROM stobe_task_goal_runtime WHERE goal_id=$1",[$id])
            :$GLOBALS['db']->fetchOne("SELECT 'WORK' AS kind,item_name,quantity,completed,status,reason FROM stobe_work_goal WHERE goal_id=$1",[$id]);
        if(!is_array($row)||$actor==='')continue;
        $status=strtoupper(strval($row['status']??''));
        $kindWord=strtolower(str_replace('_',' ',strval($row['kind']??'')));
        $itemName=strval($row['item_name']??'');
        $what=$kindWord==='work'
            ?'make '.intval($row['quantity']??0).' '.$itemName
            :trim($kindWord.' '.$itemName);
        $done=intval($row['completed']??0).'/'.intval($row['quantity']??0);
        $reason=trim(strval($row['reason']??''));
        $instruction=match($status){
            'COMPLETE'=>"You just finished the job {$player} gave you ({$what}; {$done} done) and walked back to {$player}. Tell {$player} briefly, in your own voice, that it's done and ask what's next. Don't invent extra results.",
            'BLOCKED'=>"You had to stop the job {$player} gave you ({$what}; {$done} done) and walked back to {$player}. Tell {$player} briefly why: {$reason}. Ask what to do about it. Don't claim it succeeded.",
            'WAITING_APPROVAL'=>"Your job ({$what}) needs {$player}'s approval to spend Cats: {$reason}. Ask {$player} plainly whether to buy it.",
            'CANCELLED'=>"{$player} cancelled your job ({$what}); you're back with {$player}. Say briefly that you're ready for the next order.",
            default=>'',
        };
        if($instruction==='')continue;
        stobeNegQueueDirective($actor,'goal_report',$id,['instruction'=>$instruction,'actions'=>[]],false);
        stobeLogInfo('Goal report queued',['actor'=>$actor,'goal_id'=>$id,'status'=>$status]);
        $queued++;
    }
    return $queued;
}

function stobeAnyGoalControl(string $actor,string $command,string $selector='',int $quantity=0,string $destination=''): array
{'''),
])
patch("processor/bored.php", [
    ("$negDirective = function_exists('stobeNegClaimDirective') ? stobeNegClaimDirective($candidateNames) : null;",
     "if (function_exists('stobeGoalReportQueuePending')) {\n"
     "    try { stobeGoalReportQueuePending(); } catch (Throwable $e) { stobeLogWarn('Goal report queue failed', ['error' => $e->getMessage()]); }\n"
     "}\n"
     "$negDirective = function_exists('stobeNegClaimDirective') ? stobeNegClaimDirective($candidateNames) : null;"),
])
