#!/usr/bin/env python3
"""apply_region_waypoint.py <server-tree-root>   (imm26-sfL, PROPOSAL, apply to /root/imm26/compose only; not deployed)

Rows 24-b / 24-c root cause and fix (Shay decision 2026-10-16: "Let's go toward Vain" -> the NPC remembers Vain as the GOAL, kept after save/load):

ROOT CAUSE
  The only code that writes a trip `regional_goal` is the single-consent route (stobeAreaGoalFinishCurrentTurn -> stobeTravelTakeRegionalConsent). It needs
  (1) the exact phrase "I agree to go to/toward Vain" (stobeAreaGoalDirectTripConsent), (2) a stored region plan with offer_source npc_suggestion, and
  (3) a native candidate carrying spatial.region_name == Vain (never forwarded; native never emits it) or a known-town memory. "Let's go toward Vain." is an ordinary
  travel request (stobeRegionPlanExistingStart), so the hook returns false, stobeTravelCapture PROPOSEs whatever known place the model picks (Stumble Inn) and nothing
  records that Vain was the goal; "Yes" accepts that plain trip without a regional_goal block. The region plan stays awaiting_route for ever (nothing consumes it).

FIX (server only, three anchored edits)
  lib/area_goal_integration.php  stobeAreaGoalNoteRegionHint(): on the ordinary-travel early return, when the authenticated current human quote asks to go
                                 toward exactly one catalog region, leave a one-shot request-local hint (actor, speaker, gamets, quote, region).
  lib/travel_companionship.php   stobeTravelTakeRegionHint() consumes it in stobeTravelCapture; stobeTravelRegionWaypointGoal() writes
                                 regional_goal{region, goal_source player_toward_region, endpoint_* = the model's concrete offer, endpoint_region_evidence
                                 none_waypoint (honest: the waypoint is NOT claimed to be inside the region)} on PROPOSE/ACCEPT, and copies the goal of the stored
                                 PROPOSED/pending offer onto its ACCEPT (the accept state is built fresh). The goal rides the trip state, so save/load keeps it
                                 (same path as wpR1). The rule that rejects an endpoint equal to the player's current town (area_goal.php) is NOT touched.
Idempotent: a second run reports ALREADY-APPLIED, exit 0; a missing anchor exits 3 without writing.
"""
import os
import sys

EDITS = [
    ('lib/area_goal_integration.php',
     "    if (stobeRegionPlanExistingStart($quote) && !$acceptedOfferedRegion) return false;\n",
     "    if (stobeRegionPlanExistingStart($quote) && !$acceptedOfferedRegion) {\n"
     "        stobeAreaGoalNoteRegionHint($turn,$quote,$actor,$speaker,$now); // imm26 24-b/24-c: remember the REGION as the goal of the ordinary trip\n"
     "        return false;\n"
     "    }\n",
     "stobeAreaGoalNoteRegionHint($turn"),
    ('lib/area_goal_integration.php',
     "/** Explicit query receipt: unlike stobeTravelRead()'s nullable result,",
     "/**\n"
     " * imm26 24-b/24-c (Shay 2026-10-16): \"Let's go toward Vain\" is an ordinary travel request, but the region must not be forgotten when the NPC offers a\n"
     " * concrete waypoint. Leaves a one-shot, request-local hint that stobeTravelCapture turns into a trip `regional_goal`. It grants no consent and\n"
     " * dispatches nothing. Only the authenticated current human quote counts, and it must name exactly ONE catalog region as a direction.\n"
     " */\n"
     "function stobeAreaGoalNoteRegionHint(array $turn,string $quote,string $actor,string $speaker,int $now): void {\n"
     "    unset($GLOBALS['STOBE_TRAVEL_REGION_HINT']);\n"
     "    if ($now<=0 || !is_array($turn['scope']??null) || !is_array($turn['input']??null)\n"
     "        || !stobeRegionPlanManual($turn['input'],$turn['scope'])) return;\n"
     "    if (preg_match('/\\b(?:not|never|don\\'?t|dont|avoid|away\\s+from|instead|unless|if)\\b|[\"\\x{201C}\\x{201D}]/iu',$quote)) return;\n"
     "    $named=[];\n"
     "    foreach (($turn['regions']??[]) as $candidate) if (stobeRegionPlanNamed($quote,strval($candidate['name']??''))) $named[]=strval($candidate['name']);\n"
     "    if (count($named)!==1 || $named[0]==='') return;\n"
     "    if (preg_match('/\\b(?:toward|towards|to|for|into)\\s+(?:the\\s+)?'.preg_quote($named[0],'/').'(?![\\pL\\pN])/iu',$quote)!==1) return;\n"
     "    $GLOBALS['STOBE_TRAVEL_REGION_HINT']=['actor'=>$actor,'speaker'=>$speaker,'gamets'=>$now,'quote'=>$quote,'region'=>$named[0]];\n"
     "}\n\n"
     "/** Explicit query receipt: unlike stobeTravelRead()'s nullable result,",
     "function stobeAreaGoalNoteRegionHint("),
    ('lib/travel_companionship.php',
     "function stobeTravelCapture(string $raw, string $actor, array|false $npc, string $speaker, string $playerLine, int $gamets, string &$text, array &$actions): void {\n"
     "    $GLOBALS['STOBE_TRAVEL_PLAYER_LINE'] = $playerLine; // read by stobeTravelValidateOrders (imm26 24-a)\n"
     "    $data = json_decode(trim($raw), true);\n"
     "    if (!is_array($data)) return;\n",
     "/** imm26 24-b/24-c: consume the one-shot hint left by stobeAreaGoalNoteRegionHint(); null unless it is for this very actor/speaker/turn/quote. */\n"
     "function stobeTravelTakeRegionHint(string $actor,string $speaker,int $gamets,string $line): ?string {\n"
     "    $hint = $GLOBALS['STOBE_TRAVEL_REGION_HINT'] ?? null;\n"
     "    unset($GLOBALS['STOBE_TRAVEL_REGION_HINT']);\n"
     "    if (!is_array($hint) || ($hint['actor'] ?? null) !== $actor || strcasecmp(strval($hint['speaker'] ?? ''),$speaker) !== 0\n"
     "        || intval($hint['gamets'] ?? 0) !== $gamets || ($hint['quote'] ?? null) !== $line\n"
     "        || !is_string($hint['region'] ?? null) || trim($hint['region']) === '') return null;\n"
     "    return trim($hint['region']);\n"
     "}\n\n"
     "/**\n"
     " * imm26 24-b/24-c: the `regional_goal` of an ORDINARY trip whose concrete offer was made for a broad region. The region is the remembered goal; the offered\n"
     " * place is only the grounded waypoint, and it is never claimed to lie inside the region (endpoint_region_evidence none_waypoint). An ACCEPT builds a fresh\n"
     " * state, so it carries over the goal of the stored offer it accepts.\n"
     " */\n"
     "function stobeTravelRegionWaypointGoal(array $state,mixed $old,string $decision,?string $hint,string $actor,int $gamets): ?array {\n"
     "    if (!is_array($state['destination_point'] ?? null)) return null;\n"
     "    if ($hint !== null && $hint !== '' && strcasecmp($hint,strval($state['destination'] ?? '')) !== 0) {\n"
     "        return ['region'=>$hint,'goal_source'=>'player_toward_region','endpoint_id'=>strval($state['destination_point']['id'] ?? ''),\n"
     "            'endpoint_label'=>strval($state['destination'] ?? ''),'endpoint_source'=>'ordinary_travel_waypoint',\n"
     "            'endpoint_actor_serial'=>stobeTravelActorSerial($actor),'endpoint_region_evidence'=>'none_waypoint','checked_gamets'=>$gamets];\n"
     "    }\n"
     "    if ($decision === 'ACCEPT' && is_array($old) && in_array($old['status'] ?? '',['PROPOSED','ACCEPTED'],true)\n"
     "        && is_array($old['regional_goal'] ?? null) && !empty($old['regional_goal'])) return $old['regional_goal'];\n"
     "    return null;\n"
     "}\n\n"
     "function stobeTravelCapture(string $raw, string $actor, array|false $npc, string $speaker, string $playerLine, int $gamets, string &$text, array &$actions): void {\n"
     "    $GLOBALS['STOBE_TRAVEL_PLAYER_LINE'] = $playerLine; // read by stobeTravelValidateOrders (imm26 24-a)\n"
     "    $regionHint = stobeTravelTakeRegionHint($actor,$speaker,$gamets,$playerLine);\n"
     "    $data = json_decode(trim($raw), true);\n"
     "    if (!is_array($data)) return;\n",
     "function stobeTravelTakeRegionHint("),
    ('lib/travel_companionship.php',
     "            'prior_trip_status'=>$regionalConsent['prior_trip_status'],'checked_gamets'=>$gamets];\n    }\n",
     "            'prior_trip_status'=>$regionalConsent['prior_trip_status'],'checked_gamets'=>$gamets];\n    }\n"
     "    if (!isset($state['regional_goal'])) {\n"
     "        $waypointGoal = stobeTravelRegionWaypointGoal($state,$old,$decision,$regionHint,$actor,$gamets);\n"
     "        if ($waypointGoal !== null) $state['regional_goal'] = $waypointGoal;\n"
     "    }\n",
     "stobeTravelRegionWaypointGoal($state,$old"),
]


def main(root):
    # group by file, check everything before writing anything
    files = {}
    status = []
    for rel, old, new, marker in EDITS:
        p = os.path.join(root, rel)
        s = files.get(p)
        if s is None:
            s = open(p, encoding='utf-8', newline='').read()
        if marker in s:
            status.append('ALREADY-APPLIED %s [%s]' % (rel, marker[:40]))
            files[p] = s
            continue
        if s.count(old) != 1:
            print('ANCHOR-MISSING (%d matches) in %s: %r' % (s.count(old), rel, old[:70]))
            return 3
        files[p] = s.replace(old, new)
        status.append('APPLIED %s [%s]' % (rel, marker[:40]))
    for p, s in files.items():
        open(p, 'w', encoding='utf-8', newline='').write(s)
    print('\n'.join(status))
    return 0


if __name__ == '__main__':
    if len(sys.argv) != 2:
        print(__doc__)
        sys.exit(2)
    sys.exit(main(sys.argv[1]))
