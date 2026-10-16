"""imm26-fix26f4: availability bypass for the activity PROPOSE test seam (26-f: Cind is in melee with the bandits, npc_availability.php returns in_combat,
ActivityChat.php rejects both the PROPOSE and the later ACCEPT with 'Activity availability rejected').
usage (WSL or Git Bash): python3 patch.py <repo root C:/KenshiModding or /mnt/c/KenshiModding>
Edits (anchor-asserted, idempotent): pending-fixes/imm26-sfO/ActivityTestInject.php, pending-fixes/imm26-sfO/imm26_sfO_inject_propose.php.
The production path (npc_availability.php, ActivityChat.php, apply.py's one guarded call) is NOT touched: the bypass lives only in the seam file, behind the
lane gate (/tmp/stobe-*/site + private DB socket) AND an explicit marker flag bypass_availability=true written by inject-propose.sh --bypass-availability."""
import sys, os
root = sys.argv[1].rstrip('/')
d = root + '/pending-fixes/imm26-sfO/'


def edit(path, pairs, flag):
    s = open(path, 'rb').read().decode('utf-8')
    crlf = '\r\n' in s
    s = s.replace('\r\n', '\n')
    if flag in s:
        print('already patched', os.path.basename(path))
        return
    for old, new in pairs:
        assert s.count(old) == 1, ('anchor', old[:70], s.count(old))
        s = s.replace(old, new)
    if crlf:
        s = s.replace('\n', '\r\n')
    open(path, 'wb').write(s.encode('utf-8'))
    print('patched', os.path.basename(path))


# ---------------------------------------------------------------- ActivityTestInject.php
A1_OLD = "function stobeActivityTestInjectApply(array $turn, &$reply): string {"
A1_NEW = "function stobeActivityTestInjectApply(array &$turn, &$reply): string {   // $turn by reference: the availability bypass (fix26f4) edits $turn['availability']"
A2_OLD = "        if ($actor !== 0 && $actor !== ($turn['request']['context']['actor'] ?? null)) return 'other_actor';\n"
A2_NEW = A2_OLD + (
    "        // fix26f4: the second phase of a bypass marker (written when the PROPOSE fired) covers the player's Yes.\n"
    "        if (($spec['phase'] ?? '') === 'accept') return stobeActivityTestInjectAcceptPhase($turn, $reply, $spec, $lane, $marker);\n")
A3_OLD = "        @file_put_contents($fired, json_encode($spec + ['fired_at'=>time(), 'intent'=>$intent], JSON_UNESCAPED_SLASHES));\n"
A3_NEW = A3_OLD + (
    "        // fix26f4: availability bypass, ONLY when the marker asks for it (inject-propose.sh --bypass-availability). The PROPOSE turn and the player's Yes turn are rejected by\n"
    "        // ActivityChat.php when the NPC is in combat (npc_availability.php in_combat); 26-f's Cind fights the very group she is asked to clear. Phase 2 of the marker keeps the bypass for\n"
    "        // the Yes (see stobeActivityTestInjectAcceptPhase). Nothing else about the product path changes: grounding, willingness, consent evidence, native scope check.\n"
    "        if (($spec['bypass_availability'] ?? false) === true) {\n"
    "            stobeActivityTestInjectBypass($turn, 'propose');\n"
    "            $win = max(60, min(1800, intval($spec['bypass_window'] ?? 600)));\n"
    "            $next = array_merge($spec, ['phase'=>'accept', 'actor'=>intval($turn['request']['context']['actor'] ?? 0), 'npc'=>'', 'expires_at'=>time() + $win, 'proposed_at'=>time()]);\n"
    "            $tmp = $marker . '.tmp' . getmypid();\n"
    "            if (@file_put_contents($tmp, json_encode($next, JSON_UNESCAPED_SLASHES)) !== false) { @chmod($tmp, 0644); @rename($tmp, $marker); }\n"
    "        }\n")
A4_OLD = "/**\n * Called by stobeActivityChatFinish() only when the marker file exists."
A4_NEW = (
    "/**\n * fix26f4: mark this turn's availability as open and keep a trace of what the product gate said (the row evidence shows e.g. reasons=[in_combat]).\n"
    " * Only reachable from stobeActivityTestInjectApply() after the lane gate and a marker with bypass_availability=true; an unarmed request never gets here.\n */\n"
    "function stobeActivityTestInjectBypass(array &$turn, string $where): void {\n"
    "    $was = is_array($turn['availability'] ?? null) ? $turn['availability'] : [];\n"
    "    $turn['availability'] = ['available'=>true, 'reasons'=>[], 'detail'=>[], 'test_inject_bypass'=>['was_available'=>($was['available'] ?? true), 'was_reasons'=>($was['reasons'] ?? [])]];\n"
    "    if (function_exists('stobeLogWarn')) stobeLogWarn('STOBE_TEST_ACTIVITY_INJECT availability bypassed (test seam, isolated lane only)',\n"
    "        ['where'=>$where, 'actor'=>$turn['request']['context']['actor'] ?? null, 'was_available'=>($was['available'] ?? true), 'was_reasons'=>($was['reasons'] ?? [])]);\n"
    "}\n\n"
    "/**\n * fix26f4 phase 2 of a bypass marker (the PROPOSE already fired for this actor). While the record the seam proposed is still `proposed`:\n"
    " *  - availability is opened for the Yes turn (ActivityChat.php checks it again at ACCEPT);\n"
    " *  - when the model answered NONE (it is told to decline while the NPC is in combat) and the native side delivered REAL consent evidence for the displayed offer (the player's Yes),\n"
    " *    the model's choice is replaced by ACCEPT. Consent is never created here: adapter->accept() still validates the evidence (proposal id, digest, displayed) exactly as in production.\n"
    " * Once the record is no longer `proposed` (accepted / ended) the marker is consumed. It also expires after bypass_window (default 600 s) and inject-propose.sh --disarm-all removes it.\n */\n"
    "function stobeActivityTestInjectAcceptPhase(array &$turn, &$reply, array $spec, string $lane, string $marker): string {\n"
    "    $rec = $turn['record'] ?? null;\n"
    "    $status = is_array($rec) ? strval($rec['status'] ?? '') : '';\n"
    "    if ($status === '') return 'accept_phase_wait';\n"
    "    if ($status !== 'proposed') {\n"
    "        @rename($marker, $lane . '/test-inject-activity.done-' . date('YmdHis') . '-' . bin2hex(random_bytes(3)) . '.json');\n"
    "        return 'accept_phase_done';\n"
    "    }\n"
    "    if (strval($rec['agreement']['kind'] ?? '') !== strval($spec['kind'] ?? '')) return 'accept_phase_other_kind';\n"
    "    stobeActivityTestInjectBypass($turn, 'accept');\n"
    "    $decision = is_array($reply) ? strval($reply['activity_decision'] ?? 'NONE') : 'NONE';\n"
    "    if ($decision === 'NONE' && !empty($turn['request']['consent'])) {\n"
    "        $reply = array_merge(is_array($reply) ? $reply : [], ['action'=>'Talk', 'activity_decision'=>'ACCEPT', 'activity_intent'=>'', 'travel_decision'=>'NONE', 'deal_decision'=>'NONE', 'deal_terms'=>'']);\n"
    "        if (function_exists('stobeLogWarn')) stobeLogWarn('STOBE_TEST_ACTIVITY_INJECT accept injected (real consent evidence present)', ['actor'=>$turn['request']['context']['actor'] ?? null]);\n"
    "        return 'accept_injected';\n"
    "    }\n"
    "    return 'accept_phase_bypass';\n"
    "}\n\n"
    + A4_OLD)
edit(d + 'ActivityTestInject.php', [(A1_OLD, A1_NEW), (A2_OLD, A2_NEW), (A3_OLD, A3_NEW), (A4_OLD, A4_NEW)], 'stobeActivityTestInjectAcceptPhase')

# ---------------------------------------------------------------- php selftest
T_OLD = "// G. gate: a DB socket outside the lane root closes the seam even in a /tmp/stobe-*/site tree\n"
T_NEW = r'''// J. fix26f4 availability bypass (26-f: the NPC is in combat; ActivityChat.php rejects PROPOSE and ACCEPT with 'Activity availability rejected')
$busy = ['available'=>false, 'reasons'=>['in_combat'], 'detail'=>[]];
$mkBusy = static function(array $request, ?array $record) use ($mkTurn, $busy): array { $t = $mkTurn($request, $record); $t['availability'] = $busy; return $t; };
$doneFiles = static fn() => glob(dirname($site) . '/test-inject-activity.done-*.json') ?: [];
$proposeReply = json_encode(['action'=>'Talk','activity_decision'=>'PROPOSE','activity_intent'=>json_encode(['kind'=>'ClearGroup']),'travel_decision'=>'NONE','deal_decision'=>'NONE','deal_terms'=>'']);
@unlink($marker); foreach ($firedFiles() as $f) @unlink($f); foreach ($doneFiles() as $f) @unlink($f);
// J1: control, unarmed: an in-combat NPC is still rejected by the product gate
$text = 'Hmm.'; $actions = [];
$ok = stobeActivityChatFinish($mkBusy(reqFor(7220, 'clear them out', [huntCand(), clearCand()]), null), $noneReply, $text, $actions);
check('J1: unarmed + in_combat: no proposal (production gate unchanged)', $ok === false && !$rows(7220));
// J2: armed WITHOUT the bypass flag (the old behaviour): the PROPOSE is built but the availability gate still rejects it; refusal text names the fight
$arm(['kind'=>'ClearGroup','actor'=>7221,'row'=>'26-f']);
$text = 'Hmm.'; $actions = [];
$ok = stobeActivityChatFinish($mkBusy(reqFor(7221, 'clear them out', [huntCand(), clearCand()]), null), $noneReply, $text, $actions);
check('J2: armed without bypass_availability + in_combat: still rejected (no record), refusal in character', $ok === true && !$rows(7221) && str_contains($text, 'fight'), [$ok, $text]);
@unlink($marker); foreach ($firedFiles() as $f) @unlink($f);
// J3: armed WITH the flag: the in_combat NPC's PROPOSE becomes a real proposed record; a phase-2 marker for the Yes is written
$arm(['kind'=>'ClearGroup','actor'=>7222,'row'=>'26-f','bypass_availability'=>true]);
$text = 'Hmm.'; $actions = [];
$ok = stobeActivityChatFinish($mkBusy(reqFor(7222, 'clear them out', [huntCand(), clearCand()]), null), $noneReply, $text, $actions);
$r = $rows(7222); $recJ = $r ? json_decode($r[0]['record'], true) : null;
$m2 = is_file($marker) ? json_decode(strval(file_get_contents($marker)), true) : null;
check('J3: armed + bypass flag + in_combat: proposed ClearGroup record', $ok === true && ($recJ['status'] ?? '') === 'proposed' && ($recJ['agreement']['kind'] ?? '') === 'ClearGroup', [$ok, $recJ['status'] ?? null]);
check('J4: phase-2 marker written (phase accept, same actor, still bypass, fresh expiry)', is_array($m2) && ($m2['phase'] ?? '') === 'accept' && ($m2['actor'] ?? 0) === 7222 && ($m2['bypass_availability'] ?? false) === true && ($m2['expires_at'] ?? 0) > time() + 30, $m2);
// J5: a chat turn of the same NPC in between (model NONE, no consent): nothing injected, record untouched, marker kept
$text = 'Hmm.'; $actions = [];
$ok = stobeActivityChatFinish($mkBusy(reqFor(7222, 'so?', [huntCand(), clearCand()], 1003), $recJ), $noneReply, $text, $actions);
$r5 = $rows(7222);
check('J5: in-between NONE turn without consent: no ACCEPT injected, record stays proposed, marker kept', $ok === false && is_file($marker) && count($r5) === 1 && (json_decode($r5[0]['record'], true)['status'] ?? '') === 'proposed', [$ok]);
// J6: another NPC's turn does not use the marker
$ok = stobeActivityChatFinish($mkBusy(reqFor(7223, 'Yes', [huntCand()], 1004), null), $noneReply, $text, $actions);
check('J6: marker of 7222 does not touch NPC 7223', $ok === false && !$rows(7223) && is_file($marker));
// J7: the player's Yes (real consent evidence) while the NPC is still in combat and the model says NONE: ACCEPT injected, record accepted, grant envelope in the outbox
$req = reqFor(7222, 'Yes', [huntCand(), clearCand()], 1005);
$req['consent'] = ['origin'=>'native_player_chat','worldId'=>$W,'actor'=>7222,'requester'=>$PLAYER,'proposalId'=>$recJ['agreement']['id'],'revision'=>$recJ['revision'],
    'scopeDigest'=>$recJ['scopeDigest'],'proposalWasDisplayed'=>true];
$text = 'Busy.'; $actions = [];
$okY = stobeActivityChatFinish($mkBusy($req, $recJ), $noneReply, $text, $actions);
$r = $rows(7222); $lastJ = $r ? json_decode(end($r)['record'], true) : null;
$outJ = $db->fetchAll('SELECT envelope FROM stobe_activity_outbox WHERE world_id=$1 AND actor=$2', [$W, 7222]);
check('J7: Yes with real consent, in_combat, model NONE: ACCEPT injected -> accepted + outbox grant', $okY === true && ($lastJ['status'] ?? '') === 'accepted' && count($outJ) === 1, [$okY, $lastJ['status'] ?? null, count($outJ), $text]);
// J8: the next turn sees an accepted record: the marker is consumed (phase done), nothing else changes
$text = 'Hmm.'; $actions = [];
$ok = stobeActivityChatFinish($mkBusy(reqFor(7222, 'status?', [huntCand()], 1006), $lastJ), $noneReply, $text, $actions);
check('J8: after accept the phase-2 marker is consumed', $ok === false && !is_file($marker) && count($doneFiles()) === 1);
foreach ($doneFiles() as $f) @unlink($f);
foreach ($firedFiles() as $f) @unlink($f);
// J9: Yes WITHOUT consent evidence and model NONE: no ACCEPT is invented (consent is never created by the seam)
$arm(['kind'=>'ClearGroup','actor'=>7224,'row'=>'26-f','bypass_availability'=>true]);
$text = 'Hmm.'; $actions = [];
stobeActivityChatFinish($mkBusy(reqFor(7224, 'clear them out', [clearCand()]), null), $noneReply, $text, $actions);
$r = $rows(7224); $recK = $r ? json_decode($r[0]['record'], true) : null;
$okN = stobeActivityChatFinish($mkBusy(reqFor(7224, 'Yes', [clearCand()], 1005), $recK), $noneReply, $text, $actions);
$r = $rows(7224);
check('J9: Yes without consent evidence: nothing accepted (no consent faked)', $okN === false && count($r) === 1 && (json_decode($r[0]['record'], true)['status'] ?? '') === 'proposed' && !$db->fetchAll('SELECT 1 FROM stobe_activity_outbox WHERE world_id=$1 AND actor=$2', [$W, 7224]));
// J10: expired phase-2 marker: availability is NOT opened any more (a model ACCEPT with consent is rejected by the gate again)
$m = json_decode(strval(file_get_contents($marker)), true); $m['expires_at'] = time() - 5; file_put_contents($marker, json_encode($m));
$req = reqFor(7224, 'Yes', [clearCand()], 1007);
$req['consent'] = ['origin'=>'native_player_chat','worldId'=>$W,'actor'=>7224,'requester'=>$PLAYER,'proposalId'=>$recK['agreement']['id'],'revision'=>$recK['revision'],'scopeDigest'=>$recK['scopeDigest'],'proposalWasDisplayed'=>true];
$acceptReply = json_encode(['action'=>'Talk','activity_decision'=>'ACCEPT','activity_intent'=>'','travel_decision'=>'NONE','deal_decision'=>'NONE','deal_terms'=>'']);
$text = 'ok'; $actions = [];
stobeActivityChatFinish($mkBusy($req, $recK), $acceptReply, $text, $actions);
$r = $rows(7224);
check('J10: expired phase-2 marker: ACCEPT rejected again by the availability gate (still proposed, refusal text)', (json_decode(end($r)['record'], true)['status'] ?? '') === 'proposed' && str_contains($text, 'fight'), $text);
@unlink($marker); foreach ($firedFiles() as $f) @unlink($f);
// J11: lane gate closed (DB socket outside the lane root) + the flag in the marker: the bypass does not apply either
$arm(['kind'=>'ClearGroup','actor'=>7225,'row'=>'26-f','bypass_availability'=>true]);
$saved = getenv('STOBE_DB_HOST'); putenv('STOBE_DB_HOST=/var/run/postgresql');
$text = 'Hmm.'; $actions = [];
$ok = stobeActivityChatFinish($mkBusy(reqFor(7225, 'clear them out', [clearCand()]), null), $proposeReply, $text, $actions);
putenv('STOBE_DB_HOST=' . $saved);
check('J11: lane gate closed + bypass flag: the product gate still rejects (no record)', !$rows(7225), $text);
@unlink($marker); foreach ($firedFiles() as $f) @unlink($f);

''' + T_OLD
edit(d + 'imm26_sfO_inject_propose.php', [(T_OLD, T_NEW)], "J1: unarmed + in_combat")
