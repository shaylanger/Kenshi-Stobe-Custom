#!/usr/bin/env python3
"""imm26 fix22b20d: two server defects from 4080-i3op25.
Usage: python3 apply.py <tree-root> [--part 22b|20d|all]   (idempotent; asserts every anchor exactly once; writes via temp+rename so hard-linked trees are safe)

22-b  lib/imm26_plans.php stobeImm26PlanReportQueuePending: a COMPLETED trip whose arrival remark was already claimed
      (eventlog situated_remark_claim event_id 'trip:<agreement>:completed') is marked reported and NOT queued as a plan_report
      directive, so the second bored tick stays silent (it used to speak a second arrival remark).
20-d  lib/imm26_plans.php + lib/travel_companionship.php: a pending_replacement (written when the old trip was being stopped) or
      a pending_change whose old trip is already dead (FAILED/ENDED, e.g. failed by a save+load) is applied on a bare
      confirmation: the destination/kind/leader of the model's PROPOSE/ACCEPT are replaced by the waiting change (the old
      destination is not re-offered), the waiting record is cleared after the PROPOSE is written; the prompt tells the model
      what to answer; pending_replacement now expires after 6 game hours like pending_change."""
import sys, os
root = sys.argv[1]
part = 'all'
if '--part' in sys.argv: part = sys.argv[sys.argv.index('--part') + 1]

def rw(rel, edits):
    p = os.path.join(root, rel)
    s = open(p, encoding='utf-8', newline='').read()
    for a, b in edits:
        if b in s: continue
        assert s.count(a) == 1, (rel, a[:80])
        s = s.replace(a, b)
    tmp = p + '.tmp-fix22b20d'
    open(tmp, 'w', encoding='utf-8', newline='').write(s)
    os.replace(tmp, p)          # new inode: never writes through a hard link
    print('ok', rel)

PLANS = 'lib/imm26_plans.php'
TRAVEL = 'lib/travel_companionship.php'

if part in ('22b', 'all'):
    rw(PLANS, [
("        $dest = mb_substr(strval($state['destination'] ?? 'our destination'), 0, 80);\n        if ($state['status'] === 'COMPLETED') {\n",
 "        if ($state['status'] === 'COMPLETED' && stobeImm26ArrivalClaimConsumed(strval($state['agreement_id']))) {\n"
 "            // imm26 22-b: the arrival remark was already spoken through the situated-event claim; a plan_report would repeat it.\n"
 "            $live['execution']['reported'] = true;\n"
 "            stobeTravelWrite($actor, $speaker, $gamets, $live);\n"
 "            continue;\n"
 "        }\n"
 "        $dest = mb_substr(strval($state['destination'] ?? 'our destination'), 0, 80);\n        if ($state['status'] === 'COMPLETED') {\n"),
("/** Queue one natural spoken report per ended trip (completed, failed, cancelled by native). */\n",
 "/** imm26 22-b: true when the arrival remark of this trip was already claimed (spoken) through the situated-event channel. */\n"
 "function stobeImm26ArrivalClaimConsumed(string $agreementId): bool {\n"
 "    if ($agreementId === '' || !isset($GLOBALS['db'])) return false;\n"
 "    $needle = '\"event_id\":\"trip:' . mb_substr($agreementId, 0, 100) . ':completed\"';\n"
 "    try {\n"
 "        $rows = $GLOBALS['db']->fetchAll(\"SELECT data FROM eventlog WHERE type='situated_remark_claim' ORDER BY rowid DESC LIMIT 200\");\n"
 "    } catch (Throwable $e) { return false; }\n"
 "    foreach (is_array($rows) ? $rows : [] as $r) if (str_contains(strval($r['data'] ?? ''), $needle)) return true;\n"
 "    return false;\n}\n\n"
 "/** Queue one natural spoken report per ended trip (completed, failed, cancelled by native). */\n"),
    ])

if part in ('20d', 'all'):
    rw(PLANS, [
("/** True when the player's line is (or contains) a refusal/negation,",
 "/** imm26 20-d: the change waiting for a plan that is already over: a pending_replacement (agreed in words while the old trip was being\n"
 " * stopped) or a pending_change whose old trip is dead (FAILED/ENDED/CANCELLED, e.g. failed by a save+load). Fresh = 6 game hours. */\n"
 "function stobeImm26PendingReplacement(string $actor, string $speaker, int $gamets, ?array $old): ?array {\n"
 "    $alt = stobeImm26AltRead($actor, $speaker, $gamets);\n"
 "    if (!is_array($alt)) return null;\n"
 "    $pr = $alt['pending_replacement'] ?? null;\n"
 "    if (is_array($pr) && trim(strval($pr['destination'] ?? '')) !== '') {\n"
 "        $age = $gamets - intval($pr['gamets'] ?? 0);\n"
 "        if ($age >= 0 && $age <= 21600) return ['source'=>'pending_replacement', 'destination'=>trim(strval($pr['destination'])),\n"
 "            'kind'=>strval($pr['kind'] ?? ''), 'leader'=>strval($pr['leader'] ?? '')];\n"
 "    }\n"
 "    $pc = $alt['pending_change'] ?? null;\n"
 "    if (is_array($pc) && is_array($pc['offer'] ?? null) && trim(strval($pc['offer']['destination'] ?? '')) !== ''\n"
 "        && is_array($old) && !in_array($old['status'] ?? '', ['PROPOSED', 'ACCEPTED'], true)\n"
 "        && strval($pc['old_agreement_id'] ?? '') !== '' && strval($pc['old_agreement_id']) === strval($old['agreement_id'] ?? '')) {\n"
 "        $age = $gamets - intval($pc['gamets'] ?? 0);\n"
 "        if ($age >= 0 && $age <= 21600) return ['source'=>'pending_change', 'destination'=>trim(strval($pc['offer']['destination'])),\n"
 "            'kind'=>strval($pc['offer']['kind'] ?? ''), 'leader'=>strval($pc['offer']['leader'] ?? '')];\n"
 "    }\n"
 "    return null;\n}\n"
 "/** The waiting change when this PROPOSE/ACCEPT turn is a bare confirmation of it (no negation, no other place named); else null. */\n"
 "function stobeImm26PendingReplacementOffer(string $actor, string $speaker, int $gamets, ?array $old, string $playerLine, array|false $npc = false): ?array {\n"
 "    $pr = stobeImm26PendingReplacement($actor, $speaker, $gamets, $old);\n"
 "    if ($pr === null || trim($playerLine) === '' || stobeImm26LineNegates($playerLine)\n"
 "        || stobeImm26LineNamesOtherPlace($actor, $npc, $playerLine, [$pr['destination']])) return null;\n"
 "    return $pr;\n}\n"
 "function stobeImm26PendingReplacementClear(string $actor, string $speaker, int $gamets, string $source): void {\n"
 "    $alt = stobeImm26AltRead($actor, $speaker, $gamets);\n"
 "    if (!is_array($alt) || !isset($alt[$source])) return;\n"
 "    unset($alt[$source]);\n"
 "    stobeImm26AltWrite($actor, $speaker, $gamets, $alt);\n}\n"
 "/** True when the player's line is (or contains) a refusal/negation,"),
("        if (!empty($alt['pending_replacement']['destination'])) $out .= 'A change of plan to ' . $alt['pending_replacement']['destination'] . \" was agreed in words while the old trip was being stopped; propose it again now.\\n\";\n",
 "        $prw = stobeImm26PendingReplacement($actor, $speaker, $gamets, is_array($state) ? $state : null);\n"
 "        if (is_array($prw)) $out .= 'A change of plan to ' . $prw['destination'] . \" was agreed in words while the old trip was being stopped or after it ended. The old trip is over: do NOT offer its destination again. \"\n"
 "            . \"If the speaker's CURRENT message simply confirms (a plain yes, take me there), answer travel_decision=PROPOSE with travel_destination=\" . $prw['destination']\n"
 "            . ($prw['kind'] !== '' ? ', travel_kind=' . $prw['kind'] : '') . ($prw['leader'] !== '' ? ', travel_leader=' . $prw['leader'] : '') . \".\\n\";\n"),
("        if (!empty($alt['pending_change']['offer']['destination']) && $gamets - intval($alt['pending_change']['gamets'] ?? 0) <= 21600) {\n",
 "        if (!empty($alt['pending_change']['offer']['destination']) && $gamets - intval($alt['pending_change']['gamets'] ?? 0) <= 21600\n"
 "            && ($state['status'] ?? '') === 'ACCEPTED') { // a dead old trip is handled by the pending-replacement line below (imm26 20-d)\n"),
    ])
    rw(TRAVEL, [
("    // WP-D 20: REPLACE = the player asked to change an accepted plan and the NPC agrees to the change.\n",
 "    // imm26 20-d: the old trip is already over (FAILED by a load, or stopped) while a change waits (pending_replacement, or a pending_change\n"
 "    // naming that dead trip): a bare confirmation applies the WAITING change, never a re-offer of the old destination.\n"
 "    $replacementOffer = null;\n"
 "    if (in_array($decision, ['PROPOSE', 'ACCEPT'], true) && !in_array($old['status'] ?? '', ['PROPOSED', 'ACCEPTED'], true)) {\n"
 "        $replacementOffer = stobeImm26PendingReplacementOffer($actor, $speaker, $gamets, is_array($old) ? $old : null, $playerLine, $npc);\n"
 "        if (is_array($replacementOffer)) {\n"
 "            $modelDest = trim(strval($data['travel_destination'] ?? ''));\n"
 "            $data['travel_destination'] = $replacementOffer['destination'];\n"
 "            if ($replacementOffer['kind'] !== '') $data['travel_kind'] = $replacementOffer['kind'];\n"
 "            if ($replacementOffer['leader'] !== '') $data['travel_leader'] = $replacementOffer['leader'];\n"
 "            unset($data['travel_alternative_id']);\n"
 "            $decision = 'PROPOSE';\n"
 "            if ($modelDest === '' || strcasecmp($modelDest, $replacementOffer['destination']) !== 0) $text = \"All right, \" . $replacementOffer['destination'] . \" it is. Shall we head there?\";\n"
 "            stobeLogInfo('Travel waiting change applied on a bare confirmation', ['npc'=>$actor,'speaker'=>$speaker,'destination'=>$replacementOffer['destination'],'source'=>$replacementOffer['source']]);\n"
 "        }\n"
 "    }\n"
 "    // WP-D 20: REPLACE = the player asked to change an accepted plan and the NPC agrees to the change.\n"),
("        if (($old['status'] ?? '') !== 'ACCEPTED' && !stobeTravelWrite($actor,$speaker,$gamets,$state)) $text = \"Let's discuss that again in a moment.\";\n",
 "        if (($old['status'] ?? '') !== 'ACCEPTED') {\n"
 "            if (!stobeTravelWrite($actor,$speaker,$gamets,$state)) $text = \"Let's discuss that again in a moment.\";\n"
 "            elseif (is_array($replacementOffer)) stobeImm26PendingReplacementClear($actor,$speaker,$gamets,$replacementOffer['source']);\n"
 "        }\n"),
    ])
