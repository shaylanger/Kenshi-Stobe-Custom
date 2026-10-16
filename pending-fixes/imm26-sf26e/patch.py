#!/usr/bin/env python3
"""imm26-sf26e (row 26-e + inv26 hardening): after a save/load the native displayed-offer map is empty, the server rebinds a
PROPOSED activity but nothing re-displays it, so the player's Yes carries no consent and accept() dies with
'Explicit scoped consent was not verified'. Fix: an ACCEPT on a proposed record without consent re-displays the SAME
offer (decision PROPOSE, offerDisplayed) so the native side binds it and the next Yes carries consent.
Also: resumed-note wording for proposed records, warn carries the error, far-target identity uses the stored serial.
Usage: python3 patch.py <compose-root>   (idempotent: skips a file already patched; backup *.bak_before_sf26e)"""
import sys, os, shutil
root = sys.argv[1] if len(sys.argv) > 1 else '/root/imm26/compose'

def rep(s, old, new, label):
    assert s.count(old) == 1, 'anchor %s found %d times' % (label, s.count(old))
    return s.replace(old, new)

def patch(path, fn):
    p = os.path.join(root, path)
    s = open(p, encoding='utf-8').read()
    if 'imm26 sf26e' in s:
        print('already applied:', path); return
    shutil.copy(p, p + '.bak_before_sf26e')
    s = fn(s)
    open(p, 'w', encoding='utf-8').write(s)
    print('patched', path)

def chat(s):
    # (b) far/voice-sent target: stored-serial fallback for the addressed NPC
    s = rep(s, "stobeResolveLiveParticipantSerial($npc) !== $c['actor']\n        || stobeResolveLiveParticipantSerial($player) !== $c['requester']) {\n        throw new RuntimeException('Activity chat identity mismatch');",
            "stobeResolveLiveParticipantSerial($npc,true) !== $c['actor'] /* imm26 sf26e: far/voice-sent target is absent from people */\n        || stobeResolveLiveParticipantSerial($player) !== $c['requester']) {\n        throw new RuntimeException('Activity chat identity mismatch');", 'begin-identity')
    # 26-e: decide before the transaction
    s = rep(s, "    $proposalValidated = false;\n    try {\n        if ($decision!=='NONE' && (($reply['deal_decision']",
            "    $proposalValidated = false;\n"
            "    // imm26 sf26e: a save/load clears the native displayed-offer map, so the Yes after a resume carries no consent. The proposal is still pending and\n"
            "    // valid: show the SAME offer again (decision PROPOSE, offerDisplayed) so the native side binds it; the next Yes then carries consent.\n"
            "    $redisplay = $decision === 'ACCEPT' && is_array($turn['record']) && ($turn['record']['status'] ?? '') === 'proposed'\n"
            "        && empty($request['consent']) && $context['now'] < intval($turn['record']['proposalExpiresAt'] ?? 0);\n"
            "    try {\n        if ($decision!=='NONE' && (($reply['deal_decision']", 'redisplay-flag')
    s = rep(s, "&$text,&$proposalValidated): void {\n            $record = $turn['record'];\n",
            "&$text,&$proposalValidated,$redisplay): void {\n            $record = $turn['record']; $redisplayNow = false;\n", 'closure-use')
    s = rep(s, "                $record = $store->load($record['agreement']['id']);\n                $evidence = $request['consent'] ?? [];\n                $evidence['playerText'] = $request['playerText']; $evidence['quotedText'] = $request['playerText'];\n                $transition = $decision === 'ACCEPT' ? $adapter->accept($context,$record,$evidence) : $adapter->cancel($context,$record,$evidence);\n                $record = $store->commit($transition,bin2hex(random_bytes(16)));\n",
            "                $record = $store->load($record['agreement']['id']);\n"
            "                if ($redisplay && ($record['status'] ?? '') === 'proposed') $redisplayNow = true; // imm26 sf26e: nothing is accepted without displayed consent\n"
            "                else {\n"
            "                $evidence = $request['consent'] ?? [];\n                $evidence['playerText'] = $request['playerText']; $evidence['quotedText'] = $request['playerText'];\n                $transition = $decision === 'ACCEPT' ? $adapter->accept($context,$record,$evidence) : $adapter->cancel($context,$record,$evidence);\n                $record = $store->commit($transition,bin2hex(random_bytes(16)));\n                }\n", 'accept-branch')
    s = rep(s, "            if ($decision==='PROPOSE') {\n                $a=$record['agreement'];",
            "            if ($redisplayNow) $result['decision']='PROPOSE';\n            if ($decision==='PROPOSE' || $redisplayNow) {\n                $a=$record['agreement'];", 'result-block')
    return s

def resume(s):
    return rep(s, "        'note' => 'A save/load interrupted this agreed job and it was picked up again; the same agreement stands, do not ask for consent again.'];",
        "        'note' => $accepted ? 'A save/load interrupted this agreed job and it was picked up again; the same agreement stands, do not ask for consent again.'\n"
        "            : 'A save/load interrupted this pending offer (imm26 sf26e) and it was carried over unchanged; the player has NOT accepted it yet. If the player agrees, answer ACCEPT: the offer is shown once more and their next Yes confirms it.'];", 'resume-note')

def procchat(s):
    return rep(s, "catch (Throwable $activityError) { stobeLogWarn('Activity chat context rejected', ['npc'=>$targetNpc]); }",
        "catch (Throwable $activityError) { stobeLogWarn('Activity chat context rejected', ['npc'=>$targetNpc,'error'=>$activityError->getMessage()]); /* imm26 sf26e */ }", 'chat-warn')

patch('lib/activity/ActivityChat.php', chat)
patch('lib/activity/ActivityResume.php', resume)
patch('processor/chat.php', procchat)
