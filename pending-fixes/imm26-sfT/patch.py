#!/usr/bin/env python3
"""imm26-sfT (row 08-d): retire satisfied follow-up topics BEFORE the speech gates in
stobeSocialFollowupsClaim, reason log on every null return, roster-row reason log.
Usage: python3 patch.py <compose-root>   (idempotent: skips a file already patched)"""
import sys, os, shutil
root = sys.argv[1] if len(sys.argv) > 1 else '/root/imm26/compose'

def patch(path, fn):
    p = os.path.join(root, path)
    s = open(p, encoding='utf-8').read()
    if 'imm26 sfT' in s:
        print('already applied:', path); return
    shutil.copy(p, p + '.bak_before_sfT')
    s = fn(s)
    open(p, 'w', encoding='utf-8').write(s)
    print('patched', path)

NEW_CLAIM = r'''/** imm26 sfT: one debug line per null return of stobeSocialFollowupsClaim, so the gate that fired is provable. */
function stobeFollowupClaimNull(string $reason,array $ctx=[]): ?array {
    if (function_exists('stobeLogDebug')) { try { stobeLogDebug('social_followup_claim null: '.$reason,$ctx); } catch (Throwable $e) {} }
    return null;
}
/** Only the existing ordinary eligible bored-turn branch can consume this; never a new scheduler.
 *  imm26 sfT: resolving/retiring a satisfied topic is state hygiene, so it runs BEFORE the speech gates
 *  (optional-speech / attention / communication / manual-input / cooldown); the gates still decide whether anything is ASKED. */
function stobeSocialFollowupsClaim(string $actor,array $npc,string $listener,array $meta=[]): ?array {
    if (($meta['eligible_bored_turn']??false)!==true) return stobeFollowupClaimNull('not_eligible_bored_turn',['actor'=>$actor]);
    if (empty($meta['social_scope'])) return stobeFollowupClaimNull('no_social_scope',['actor'=>$actor]);
    if (!isset($GLOBALS['db'])) return stobeFollowupClaimNull('no_db',['actor'=>$actor]);
    $denied='';
    if (($meta['social_optional_speech_allowed']??false)!==true) $denied='optional_speech_not_allowed';
    elseif (!function_exists('stobeSocialAttentionOptionalSpeechAllowed') || !stobeSocialAttentionOptionalSpeechAllowed($actor,$npc,$meta)) $denied='attention_gate';
    elseif (function_exists('stobeSocialCommunicationAllowsOptional') && !stobeSocialCommunicationAllowsOptional($actor,$npc,$listener,'followup',stobeFollowupTime($meta),$meta)) $denied='communication_gate';
    $scope=stobeFollowupScope($actor,$npc,$listener,$meta);$now=stobeFollowupTime($meta);
    if (!$scope || $now<=0) return stobeFollowupClaimNull('no_scope_or_time',['actor'=>$actor,'now'=>$now]);
    $serial=0;
    if ($denied==='') {
        if (!function_exists('stobeResolveLiveParticipantSerial')) $denied='no_serial_resolver';
        else { $serial=stobeResolveLiveParticipantSerial($actor,true);if ($serial<=0) $denied='no_live_serial'; }
    }
    $db=$GLOBALS['db'];$locked=false;$topicLocked=false;$tx=null;$lockKey=stobeFollowupPrefix($scope);$imm26Retired=0;
    try {
        $lock=$db->fetchOne('SELECT pg_try_advisory_lock(1937006964,1) AS acquired');
        $locked=is_array($lock)&&in_array($lock['acquired']??false,[true,1,'1','t'],true);if (!$locked) return stobeFollowupClaimNull('global_lock_busy',['actor'=>$actor]);
        $lock=$db->fetchOne('SELECT pg_try_advisory_lock(hashtext($1),1937006965) AS acquired',[$lockKey]);
        $topicLocked=is_array($lock)&&in_array($lock['acquired']??false,[true,1,'1','t'],true);if (!$topicLocked) return stobeFollowupClaimNull('topic_lock_busy',['actor'=>$actor]);
        $tx=stobeFollowupTransaction($scope);
        if (stobeFollowupScope($actor,$npc,$listener,$meta)!==$scope) return stobeFollowupClaimNull('scope_changed',['actor'=>$actor]);
        stobeFollowupRejectFuture($scope,$now);
        // State hygiene first: a topic whose condition is already satisfied (e.g. a COMPLETED trip) is retired even when speech is not allowed.
        $imm26Records=stobeFollowupRead($scope,$now,true);
        if (function_exists('imm26C2ResolvedFollowupIds')) {
            $imm26Resolved=imm26C2ResolvedFollowupIds($actor,$listener,$imm26Records,$now);
            if ($imm26Resolved) $imm26Retired=imm26C2RetireResolved($scope,$now,$imm26Records,$imm26Resolved);
            $meta['resolved_followup_ids']=array_merge($meta['resolved_followup_ids']??[],$imm26Resolved);
        }
        if ($denied==='') {
            $manual=$db->fetchOne("SELECT rowid FROM eventlog WHERE type IN ('inputtext','inputtext_s') AND localts >= $1 AND gamets <= $2 LIMIT 1",[time()-30,$now]);
            if (is_array($manual)&&isset($manual['rowid'])) $denied='manual_input_30s';
        }
        if ($denied==='') {
            $recent=$db->fetchAll("SELECT data,localts FROM eventlog WHERE type='situated_remark_claim' AND gamets <= $1 ORDER BY gamets DESC,rowid DESC LIMIT 96",[$now]);
            foreach (is_array($recent)?$recent:[] as $row) {
                $claim=json_decode(strval($row['data']??''),true);$elapsed=time()-intval($row['localts']??0);
                if ($elapsed<60 || (intval($claim['actor_serial']??0)===$serial&&$elapsed<180)) { $denied='claim_cooldown'; break; }
            }
        }
        if ($denied!=='') {
            if ($imm26Retired>0) { stobeFollowupFinish($tx,true);$tx=null; }
            return stobeFollowupClaimNull('gate:'.$denied,['actor'=>$actor,'retired'=>$imm26Retired]);
        }
        foreach (array_reverse($imm26Records) as $record) {
            if (!in_array($record['status']??'',['open','snoozed'],true) || intval($record['expires_gamets']??0)<=$now || intval($record['not_before_gamets']??PHP_INT_MAX)>$now || intval($record['ask_count']??0)>=2) continue;
            // Integrator supplies veto IDs from known outcomes; absent evidence is not completion.
            if (in_array($record['topic_id'],$meta['resolved_followup_ids']??[],true)) continue;
            $record['ask_count']=intval($record['ask_count']??0)+1;$record['not_before_gamets']=$now+86400;$record['status']='open';
            if (!stobeFollowupWrite($scope,$now,$record)) return stobeFollowupClaimNull('write_failed',['actor'=>$actor]);
            if (!is_array(storeEvent('situated_remark_claim',time(),$now,json_encode(['actor_serial'=>$serial,'event_id'=>'followup:'.$record['topic_id'].':'.$record['ask_count']]),'pending','','',false))) return stobeFollowupClaimNull('claim_event_failed',['actor'=>$actor]);
            stobeFollowupFinish($tx,true);$tx=null;return $record;
        }
        if ($imm26Retired>0) { stobeFollowupFinish($tx,true);$tx=null; }
        return stobeFollowupClaimNull('no_askable_topic',['actor'=>$actor,'retired'=>$imm26Retired]);
    } catch (Throwable $e) { return stobeFollowupClaimNull('exception',['actor'=>$actor,'error'=>$e->getMessage()]); }
    finally {
        if ($tx!==null) {try {stobeFollowupFinish($tx,false);} catch(Throwable $e) {}}
        if ($topicLocked) {try {$db->fetchOne('SELECT pg_advisory_unlock(hashtext($1),1937006965)',[$lockKey]);} catch(Throwable $e) {}}
        if ($locked) {try {$db->fetchOne('SELECT pg_advisory_unlock(1937006964,1)');} catch(Throwable $e) {}}
    }
    return null;
}
'''

def f_followups(s):
    a = s.index('/** Only the existing ordinary eligible bored-turn branch')
    b = s.index('function stobeSocialFollowupsInstruction')
    assert s.count('function stobeSocialFollowupsClaim') == 1
    return s[:a] + NEW_CLAIM + s[b:]

def f_roster(s):
    anchor = r'''        if (!is_array($row)) {
            return [];
        }
        $data = trim(strval($row['data'] ?? ''));
        if (preg_match('/nearby\s+NPC\s+roster\s*\([0-9]+\)\s*:\s*(.+)$/iu', $data, $m) !== 1) {
            return [];
        }
'''
    assert s.count(anchor) == 1, 'roster anchor'
    new = r'''        if (!is_array($row)) {
            stobeLifelikeRosterReason('no_infonpc_row', $safe);
            return [];
        }
        $data = trim(strval($row['data'] ?? ''));
        // imm26 sfT: say which infonpc row was chosen and why (data prefix vs people column), so a short roster is provable.
        $byData = stripos($data, $safe . ': nearby NPC roster') === 0;
        stobeLifelikeRosterReason('row_chosen', $safe, ['by' => $byData ? 'data_prefix' : 'people_column', 'data' => mb_substr($data, 0, 200), 'people' => mb_substr(strval($row['people'] ?? ''), 0, 200)]);
        if (preg_match('/nearby\s+NPC\s+roster\s*\([0-9]+\)\s*:\s*(.+)$/iu', $data, $m) !== 1) {
            stobeLifelikeRosterReason('row_not_a_roster', $safe);
            return [];
        }
'''
    s = s.replace(anchor, new)
    fn = 'function stobeLifelikeLatestNearbyRosterNames(string $npcName): array\n'
    assert s.count(fn) == 1
    helper = '''/** imm26 sfT: one debug line explaining the roster-row choice. */
function stobeLifelikeRosterReason(string $reason, string $npc, array $ctx = []): void
{
    if (function_exists('stobeLogDebug')) {
        try { stobeLogDebug('lifelike roster: ' . $reason, ['npc' => $npc] + $ctx); } catch (Throwable $e) {}
    }
}

'''
    return s.replace(fn, helper + fn)

patch('lib/social_followups.php', f_followups)
patch('lib/lifelike_npc.php', f_roster)
