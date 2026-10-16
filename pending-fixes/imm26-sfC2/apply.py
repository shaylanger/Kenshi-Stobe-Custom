#!/usr/bin/env python3
"""imm26 sfC2 (row 10-e): restart-proof load order for the restitution scope gate. usage: apply.py <tree-root>  (idempotent, asserts anchors)
Server-held monotone load sequence SOCIAL_LOAD_SEQ (stobe_meta.settings): advances once per new (campaign, session, epoch) triple, so a decreased native
epoch after a REAL game restart no longer reads as an older load. Agreements frozen with load_seq use it; legacy ones keep the epoch rule.
Edits lib/social_repair_agreements.php only (tests/probe ship as files)."""
import sys
root = sys.argv[1]
p = root.rstrip('/') + '/lib/social_repair_agreements.php'
s = open(p, encoding='utf-8', newline='').read()
if 'function stobeSocialLoadSeq' in s:
    print('already applied'); sys.exit(0)

def sub(old, new):
    global s
    assert s.count(old) == 1, 'anchor not unique/missing: ' + old[:60]
    s = s.replace(old, new)

sub("        $scope=stobeSocialScope($GLOBALS['db']);\n        foreach (['recipient_storage_id'=>$npcRow",
    "        $scope=stobeSocialScope($GLOBALS['db']);\n        $loadSeq=stobeSocialLoadSeq($scope);if ($loadSeq!==null) $scope['load_seq']=$loadSeq; // imm26 sfC (10-e): restart-proof load order\n        foreach (['recipient_storage_id'=>$npcRow")
helper = r'''/**
 * imm26 sfC (10-e): server-side monotone load sequence. Returns the sequence number of the load identified by the scope's
 * (campaign, native session, epoch) triple; it advances by one the first time a NEW triple is seen (one atomic upsert, safe under
 * concurrent requests) and never goes down, so it orders loads across game restarts where the native epoch counter restarts at 1.
 * null = unknown (fail closed to the old epoch rule).
 */
function stobeSocialLoadSeq(array $scope): ?string {
    try {
        $triple=strval($scope['campaign_id'] ?? '').'|'.strval($scope['native_session_id'] ?? '').'|'.strval($scope['timeline_epoch'] ?? '');
        if ($triple==='||') return null;
        $row=$GLOBALS['db']->fetchOne("INSERT INTO stobe_meta.settings (key,value) VALUES ('SOCIAL_LOAD_SEQ',$1) ON CONFLICT (key) DO UPDATE SET value=CASE WHEN settings.value::jsonb->>'triple'=$2::text THEN settings.value ELSE jsonb_build_object('triple',$2::text,'seq',COALESCE((settings.value::jsonb->>'seq')::bigint,0)+1)::text END RETURNING (value::jsonb->>'seq') AS seq",
            [json_encode(['triple'=>$triple,'seq'=>1]),$triple]);
        $seq=is_array($row) ? strval($row['seq'] ?? '') : '';
        return preg_match('/^[0-9]{1,18}$/D',$seq) ? $seq : null;
    } catch (Throwable $e) { return null; }
}

'''
sub("/**\n * imm26 wpR2: is $current", helper + "/**\n * imm26 wpR2: is $current")
sub("    $e0=$scope['timeline_epoch'] ?? null;$e1=$current['timeline_epoch'] ?? null;\n    if (!is_string($e0) || !is_string($e1) || !preg_match('/^[0-9]{1,18}$/D',$e0) || !preg_match('/^[0-9]{1,18}$/D',$e1) || intval($e1)<=intval($e0)) return false;\n",
    "    $q0=$scope['load_seq'] ?? null;\n    if (is_string($q0) && preg_match('/^[0-9]{1,18}$/D',$q0)) {\n        // imm26 sfC (10-e): the native epoch restarts at 1 with every game start; loads are ordered by the server's own sequence.\n        $q1=$current['load_seq'] ?? stobeSocialLoadSeq($current);\n        if (!is_string($q1) || !preg_match('/^[0-9]{1,18}$/D',$q1) || intval($q1)<=intval($q0)) return false;\n    } else {\n    $e0=$scope['timeline_epoch'] ?? null;$e1=$current['timeline_epoch'] ?? null;\n    if (!is_string($e0) || !is_string($e1) || !preg_match('/^[0-9]{1,18}$/D',$e0) || !preg_match('/^[0-9]{1,18}$/D',$e1) || intval($e1)<=intval($e0)) return false;\n    }\n")
open(p, 'w', encoding='utf-8', newline='').write(s)
print('applied', p)
