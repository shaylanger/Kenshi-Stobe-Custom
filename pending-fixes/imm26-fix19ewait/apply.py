#!/usr/bin/env python3
"""imm26 fix19ewait (row 19-e): log WHY stobeCommitmentResumeCheck waits.
Row 19-e (imm26-5090-i5-op20) s4 produced no resume and the 'wait' verdict was silent. This patch only adds logging:
  - lib/commitment_native_bridge.php: stobeCommitmentSnapshotDiag() (which freshness gate the native snapshot failed),
    stobeCommitmentResumeCheck() wait verdicts carry a 'detail' array, stobeCommitmentResumeAction() writes ONE
    'Trip resume wait' INFO line per wait (reason code + inputs); the branch where the reconcile has not (yet) entered
    interrupted_by_load after a load writes a DEBUG 'Trip resume wait' line (why=not_interrupted_yet + snapshot diag).
  No verdict, no state write and no action changes (the wait is by design, see README.md).
usage: python3 apply.py <tree-root> [--check]   (idempotent; asserts anchors; writes *.bak-fix19ewait)
"""
import sys, shutil, os
root = sys.argv[1]; check = '--check' in sys.argv
PF = os.path.join(root, 'lib/commitment_native_bridge.php')

A1 = ("    $wait = static fn(string $why): array => ['verdict'=>'wait','reason'=>'','why'=>$why];\n"
      "    if (stobeResolveLiveParticipantSerial($actor) <= 0) return $wait('not_in_people'); // beyond the 80u participant radius\n"
      "    $snapshot = stobeCommitmentNativeSnapshot($actor,$npc,$gamets);\n"
      "    if (!$snapshot) return $wait('no_snapshot');\n"
      "    if (!stobeCommitmentAbsenceVerified($snapshot,$gamets)) return $wait('absence_unverified');\n"
      "    if (function_exists('stobeNpcAvailability')) {\n"
      "        $availability = stobeNpcAvailability($actor,$npc,$gamets);\n"
      "        if (array_intersect(['incapacitated','in_combat'],$availability['reasons'] ?? [])) return $wait('unavailable');\n"
      "    }\n")
N1 = ("    // imm26 fix19ewait: every wait carries the inputs that produced it (logged once per response by stobeCommitmentResumeAction).\n"
      "    $wait = static fn(string $why, array $detail = []): array => ['verdict'=>'wait','reason'=>'','why'=>$why,'detail'=>$detail];\n"
      "    if (stobeResolveLiveParticipantSerial($actor) <= 0) { // beyond the 80u participant radius\n"
      "        $people = json_decode(strval($GLOBALS['CACHE_PEOPLE'] ?? ''),true);\n"
      "        return $wait('not_in_people',['people_n'=>is_array($people) ? count($people) : -1,'stored_serial'=>stobeResolveLiveParticipantSerial($actor,true)]);\n"
      "    }\n"
      "    $snapshot = stobeCommitmentNativeSnapshot($actor,$npc,$gamets);\n"
      "    if (!$snapshot) return $wait('no_snapshot',stobeCommitmentSnapshotDiag($actor,$npc,$gamets));\n"
      "    if (!stobeCommitmentAbsenceVerified($snapshot,$gamets)) {\n"
      "        return $wait('absence_unverified',[\n"
      "            'absent_flag'=>($snapshot['scoped_travel_absent_verified'] ?? false) === true,\n"
      "            'absence_age_gamets'=>$gamets - intval($snapshot['absence_observed_gamets'] ?? 0),\n"
      "            'absence_age_unix'=>time() - intval($snapshot['absence_observed_unix'] ?? 0),\n"
      "            'absence_id_world_ok'=>str_starts_with(strval($snapshot['absence_evidence_id'] ?? ''),strval($snapshot['world_id'] ?? '').':')]);\n"
      "    }\n"
      "    if (function_exists('stobeNpcAvailability')) {\n"
      "        $availability = stobeNpcAvailability($actor,$npc,$gamets);\n"
      "        if (array_intersect(['incapacitated','in_combat'],$availability['reasons'] ?? [])) return $wait('unavailable',['reasons'=>array_values($availability['reasons'] ?? [])]);\n"
      "    }\n")

A2 = "/** Decide what to do with an interrupted_by_load trip on this response.\n"
N2 = ("/** imm26 fix19ewait: which freshness gate of stobeCommitmentNativeSnapshot() a snapshot fails (diagnostics only, never changes a verdict).\n"
      " *  Returns the inputs ('snapshot' = first failing gate, or 'ok'). */\n"
      "function stobeCommitmentSnapshotDiag(string $actor, array|false $npc, int $gamets): array {\n"
      "    if (!is_array($npc)) return ['snapshot'=>'no_npc'];\n"
      "    $meta = normalizeCoreNpcMetadata($npc['metadata'] ?? []);\n"
      "    $receipt = trim(strval($_SERVER['HTTP_X_STOBE_PLAYTHROUGH'] ?? ''));\n"
      "    $d = ['receipt_header'=>$receipt === '' ? 'none' : (in_array($receipt,['legacy','blocked'],true) ? $receipt : 'set')];\n"
      "    if ($d['receipt_header'] !== 'set') return $d + ['snapshot'=>'receipt_header'];\n"
      "    if (!hash_equals($receipt,strval($meta['travel_lifecycle_context_receipt'] ?? ''))) return $d + ['snapshot'=>'receipt_mismatch'];\n"
      "    $s = $meta['travel_lifecycle'] ?? null;\n"
      "    if (!is_array($s)) return $d + ['snapshot'=>'no_lifecycle'];\n"
      "    $stamp = intval($s['observed_gamets'] ?? 0);\n"
      "    $unix = intval($s['observed_unix'] ?? 0);\n"
      "    $d += ['snapshot_serial'=>intval($s['actor_serial'] ?? 0),'live_serial'=>stobeResolveLiveParticipantSerial($actor,true),\n"
      "        'world_id'=>strval($s['world_id'] ?? ''),'generation'=>intval($s['session_generation'] ?? 0),\n"
      "        'age_gamets'=>$gamets - $stamp,'age_unix'=>time() - $unix];\n"
      "    if ($d['snapshot_serial'] !== $d['live_serial']) $d['snapshot'] = 'serial_mismatch';\n"
      "    elseif (!preg_match('/^[A-Za-z0-9-]{16,80}$/D',$d['world_id'])) $d['snapshot'] = 'bad_world';\n"
      "    elseif ($d['generation'] < 1) $d['snapshot'] = 'bad_generation';\n"
      "    elseif ($stamp <= 0 || $stamp > $gamets + 1 || $gamets - $stamp > 120 || $unix < time()-120 || $unix > time()+15) $d['snapshot'] = 'stale';\n"
      "    else $d['snapshot'] = 'ok';\n"
      "    return $d;\n"
      "}\n\n")

A3 = "        if ($check['verdict'] !== 'resume') return '';\n"
N3 = ("        if ($check['verdict'] === 'wait') { // imm26 fix19ewait: one structured line per wait (reason code + the inputs that produced it)\n"
      "            stobeLogInfo('Trip resume wait',['npc'=>$actor,'why'=>$check['why'],'gamets'=>$gamets,\n"
      "                'interrupted_gamets'=>intval($state['execution']['interrupted_gamets'] ?? 0),\n"
      "                'resume_count'=>intval($state['execution']['resume_count'] ?? 0),\n"
      "                'agreement_id'=>strval($state['agreement_id'] ?? '')] + (is_array($check['detail'] ?? null) ? $check['detail'] : []));\n"
      "        }\n")

A4 = "            if (!is_array($state) || ($state['execution']['phase'] ?? '') !== 'interrupted_by_load') return '';\n"
N4 = ("            if (is_array($state) && ($state['status'] ?? '') === 'ACCEPTED' && !empty($state['execution']['dispatch_world_id'])\n"
      "                && ($state['execution']['phase'] ?? '') !== 'interrupted_by_load') {\n"
      "                // imm26 fix19ewait: the reconcile did not (yet) pause this trip. Log only when that is load-related (unusable snapshot,\n"
      "                // another world than the pinned one, or load_changed); a normal running trip stays quiet.\n"
      "                $diag = stobeCommitmentSnapshotDiag($actor,$npc,$gamets);\n"
      "                $exe = is_array($state['execution'] ?? null) ? $state['execution'] : [];\n"
      "                $pinned = strval($exe['dispatch_world_id'] ?? $exe['world_id'] ?? '');\n"
      "                if (($diag['snapshot'] ?? '') !== 'ok' || ($pinned !== '' && $pinned !== ($diag['world_id'] ?? '')) || ($exe['load_changed'] ?? false) === true) {\n"
      "                    stobeLogDebug('Trip resume wait',['npc'=>$actor,'why'=>'not_interrupted_yet','gamets'=>$gamets,\n"
      "                        'phase'=>strval($exe['phase'] ?? ''),'load_changed'=>($exe['load_changed'] ?? false) === true,\n"
      "                        'pinned_world'=>$pinned,'agreement_id'=>strval($state['agreement_id'] ?? '')] + $diag);\n"
      "                }\n"
      "            }\n") + A4

s = open(PF, encoding='utf-8', newline='').read()
if 'stobeCommitmentSnapshotDiag' in s:
    print('already patched:', PF); sys.exit(0)
for a in (A1, A2, A3, A4):
    assert s.count(a) == 1, 'anchor count %d: %r' % (s.count(a), a[:70])
if check:
    print('anchors ok:', PF); sys.exit(0)
shutil.copy2(PF, PF + '.bak-fix19ewait')
s = s.replace(A1, N1).replace(A2, N2 + A2).replace(A3, N3 + A3).replace(A4, N4)
open(PF, 'w', encoding='utf-8', newline='').write(s)
print('patched:', PF)
