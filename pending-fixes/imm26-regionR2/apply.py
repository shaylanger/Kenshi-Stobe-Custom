#!/usr/bin/env python3
"""apply.py <server-tree-root>   (imm26 WP-R2, row 24-b region route; SERVER ONLY; apply to /root/imm26/compose or a copy, never the live tree)

Shay decided 2026-10-16: row 24-b = "grounded destination: native id if in range, else the nearest known town in the region". The NPC OFFERS A FIRST LEG
(PROPOSE only, server-written reply, no movement action); the next explicit "Yes" is the ordinary ACCEPT -> TRAVEL_LOCATION. Region routing may use
undiscovered (rumoured) towns.

ROOT CAUSE (plan C:/KenshiTestRuns/agents/out/imm26-regionA1/out-20261016-144825.md, blockers B1-B4)
  B1 "Let's consider Vain..." without an earlier NPC SUGGEST got the fixed reply "I don't have a current offer for that area to act on yet." and never reached
     the resolver; B2 only the exact "I agree to go to Vain" counted as consent; B3 the resolver only knew native candidates within 180 m; B4 no region -> place data.

CHANGES (all anchored, idempotent: second run prints ALREADY-APPLIED per item and exits 0; a missing anchor exits 3 without writing anything)
  NEW  lib/region_route.php             data-source seam stobeRegionRouteTownRegions() (reads data/kenshi_town_regions.json), nearest-town pick, stobeRegionRouteResolve()
  NEW  data/kenshi_town_regions.json    town -> catalog region, every entry with its source (native table + Universal Wasteland Expansion map-item town lists)
  NEW  tests/imm26_regionroute_regression.php
  lib/area_goal.php                     require region_route.php; stobeAreaGoalResolve(..., array $townRoute = []) falls back to the region town when no native candidate qualifies
  lib/area_goal_integration.php         unpaired/conversational CONSIDER no longer dead-ends: PROPOSE-only first-leg offer (stobeAreaGoalOfferRoute); the exact same-turn consent
                                        keeps its path; town points compare by label
  lib/region_plan.php                   stage route_ready state builder + one prompt sentence (stage lists for referential agreement are NOT widened on purpose)
  lib/travel_companionship.php          ALLOWLIST values only in stobeTravelTakeRegionalConsent (endpoint_source/endpoint_region_evidence 'world_town_region') + a
                                        request-local pin in stobeTravelResolvePlan so ONE server-chosen region town (possibly undiscovered) resolves like a visited location.
                                        stobeTravelRegionWaypointGoal and the old-state carry stay untouched.
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))

NEW_FILES = ['lib/region_route.php', 'data/kenshi_town_regions.json', 'tests/imm26_regionroute_regression.php']

EDITS = []


def edit(path, old, new, marker):
    EDITS.append((path, old, new, marker))


# ---- area_goal.php -------------------------------------------------------------------------------------------------------------------------------
edit('lib/area_goal.php',
     " * The ordinary travel consent/lifecycle remains responsible for execution.\n */\n",
     " * The ordinary travel consent/lifecycle remains responsible for execution.\n */\nrequire_once __DIR__.'/region_route.php'; // imm26 24-b: nearest known town of the region\n",
     "require_once __DIR__.'/region_route.php';")
edit('lib/area_goal.php',
     "    array $trustedScope, array $currentTravelRead, array $knownRegions = [], string $currentTown = ''): array {\n    $region = trim(strval($regionPlan['proposed_region'] ?? ''));\n",
     "    array $trustedScope, array $currentTravelRead, array $knownRegions = [], string $currentTown = '', array $townRoute = []): array {\n    $region = trim(strval($regionPlan['proposed_region'] ?? ''));\n",
     "string $currentTown = '', array $townRoute = []): array {")
edit('lib/area_goal.php',
     "    return ['status'=>'cannot_route_yet','goal_type'=>'regional_outing','region'=>$region,\n",
     "    // imm26 24-b (Shay 2026-10-16): no native point in range -> the nearest known town of the region (stobeRegionRouteResolve, computed by the caller;\n"
     "    // rumoured towns allowed). The point is the town's own coordinates; nothing here dispatches or grants consent.\n"
     "    $town = is_array($townRoute['town'] ?? null) ? $townRoute['town'] : null;\n"
     "    if (($townRoute['status'] ?? '') === 'route_ready' && $town && strcasecmp(trim(strval($townRoute['region'] ?? '')),$region) === 0\n"
     "        && trim(strval($town['name'] ?? '')) !== ''\n"
     "        && ($currentTown === '' || strcasecmp(trim($currentTown),trim(strval($town['name']))) !== 0)\n"
     "        && is_numeric($town['x'] ?? null) && is_numeric($town['y'] ?? null) && is_numeric($town['z'] ?? null)) {\n"
     "        $label = trim(strval($town['name']));\n"
     "        return ['status'=>'route_ready','goal_type'=>'regional_outing','region'=>$region,\n"
     "            'travel_destination'=>$label,'endpoint_label'=>$label,\n"
     "            'endpoint_source'=>'world_town_region','endpoint_actor_serial'=>$actorSerial,\n"
     "            'endpoint_region_evidence'=>'world_town_region',\n"
     "            'endpoint_point'=>['x'=>floatval($town['x']),'y'=>floatval($town['y']),'z'=>floatval($town['z'])],\n"
     "            'endpoint_discovered'=>$town['discovered'] ?? null,'endpoint_region_source'=>strval($town['region_source'] ?? ''),\n"
     "            'trip_read_succeeded'=>true,'trip_read_scope'=>$readScope,'trip_read_scope_hash'=>hash('sha256',json_encode($readScope)),\n"
     "            'trip_read_actor_serial'=>intval($currentTravelRead['actor_serial']),\n"
     "            'trip_read_speaker_serial'=>intval($currentTravelRead['speaker_serial']),\n"
     "            'trip_read_gamets'=>intval($currentTravelRead['gamets']),\n"
     "            'prior_trip_status'=>is_array($trip)?strval($trip['status']??'unknown'):'none',\n"
     "            'movement_consent'=>false,'dispatch'=>false,'preserve_existing_travel'=>true,\n"
     "            'reply'=>'I can lead us toward '.$region.' as a rough area. '.$label.' is only a first stop there; it does not guarantee what we will find or that the whole route is safe.'];\n"
     "    }\n"
     "    return ['status'=>'cannot_route_yet','goal_type'=>'regional_outing','region'=>$region,\n",
     "'endpoint_source'=>'world_town_region'")

# ---- area_goal_integration.php --------------------------------------------------------------------------------------------------------------------
edit('lib/area_goal_integration.php',
     "    if (!in_array($previous['stage']??'', ['concept','awaiting_route'],true)\n"
     "        || ($previous['scope']??'')!==stobeRegionPlanScope($turn['scope'])\n"
     "        || ($previous['offer_source']??'')!=='npc_suggestion'\n"
     "        || strcasecmp(strval($previous['proposed_region']??''),strval($result['state']['proposed_region']??''))!==0) {\n"
     "        $text=\"I don't have a current offer for that area to act on yet.\"; $actions=[]; return true;\n"
     "    }\n"
     "    if (!stobeAreaGoalDirectTripConsent($quote,strval($result['state']['proposed_region']))) {\n"
     "        $text=\"I understand the area you mean, but I need a clear answer before setting out.\"; $actions=[]; return true;\n"
     "    }\n",
     "    // imm26 24-b (Shay 2026-10-16): a broad \"consider <region>\" agreement is never a dead end. The NPC offers a first leg (PROPOSE only, no movement) and the\n"
     "    // next explicit \"Yes\" is the ordinary ACCEPT. Only the exact \"I agree to go to <region>\" that answers the NPC's own earlier suggestion still starts the\n"
     "    // trip in the same turn (the pre-existing consent path below).\n"
     "    $exactConsent=in_array($previous['stage']??'', ['concept','awaiting_route'],true)\n"
     "        && ($previous['scope']??'')===stobeRegionPlanScope($turn['scope'])\n"
     "        && ($previous['offer_source']??'')==='npc_suggestion'\n"
     "        && strcasecmp(strval($previous['proposed_region']??''),strval($result['state']['proposed_region']??''))===0\n"
     "        && stobeAreaGoalDirectTripConsent($quote,strval($result['state']['proposed_region']));\n",
     "$exactConsent=in_array(")
edit('lib/area_goal_integration.php',
     "    $resolved=stobeAreaGoalResolve($result['state'],\n"
     "        function_exists('stobeTravelLocalCandidates')?array_values(stobeTravelLocalCandidates($actor,$npc)):[],\n"
     "        intval($turn['scope']['actor_id']),$now,$turn['scope'],$trip,$knownRegions,$currentTown);\n",
     "    $townRoute=function_exists('stobeRegionRouteResolve')\n"
     "        ?stobeRegionRouteResolve(strval($result['state']['proposed_region']),$npc,$speaker,$currentTown):[];\n"
     "    $resolved=stobeAreaGoalResolve($result['state'],\n"
     "        function_exists('stobeTravelLocalCandidates')?array_values(stobeTravelLocalCandidates($actor,$npc)):[],\n"
     "        intval($turn['scope']['actor_id']),$now,$turn['scope'],$trip,$knownRegions,$currentTown,$townRoute);\n",
     "$townRoute=function_exists('stobeRegionRouteResolve')")
edit('lib/area_goal_integration.php',
     "    $resolved['trip_read_gamets']=$trip['gamets'];\n\n",
     "    $resolved['trip_read_gamets']=$trip['gamets'];\n"
     "    if (!$exactConsent) return stobeAreaGoalOfferRoute($resolved,$result['state'],$turn,$actor,$npc,$speaker,$quote,$now,$text,$actions);\n\n",
     "if (!$exactConsent) return stobeAreaGoalOfferRoute(")
edit('lib/area_goal_integration.php',
     "    $offerText=''; $offerActions=[];\n"
     "    stobeTravelCapture(json_encode(['travel_decision'=>'PROPOSE','travel_kind'=>'same_route','travel_leader'=>'npc',\n"
     "        'travel_destination'=>$resolved['travel_destination'],'travel_reason'=>'Regional outing toward '.$resolved['region'],\n"
     "        'travel_player_quote'=>''],JSON_UNESCAPED_UNICODE),$actor,$npc,$speaker,$quote,$now,$offerText,$offerActions);\n"
     "    $offered=stobeTravelRead($actor,$speaker,$now);\n"
     "    if (!is_array($offered) || ($offered['status']??'')!=='PROPOSED'\n"
     "        || strval($offered['destination_point']['id']??'')!==$resolved['travel_destination']) {\n",
     "    $offerText=''; $offerActions=[];\n"
     "    stobeAreaGoalPinRoute($resolved);\n"
     "    try {\n"
     "        stobeTravelCapture(json_encode(['travel_decision'=>'PROPOSE','travel_kind'=>'same_route','travel_leader'=>'npc',\n"
     "            'travel_destination'=>$resolved['travel_destination'],'travel_reason'=>'Regional outing toward '.$resolved['region'],\n"
     "            'travel_player_quote'=>''],JSON_UNESCAPED_UNICODE),$actor,$npc,$speaker,$quote,$now,$offerText,$offerActions);\n"
     "    } finally { unset($GLOBALS['STOBE_TRAVEL_REGION_ROUTE_PIN']); }\n"
     "    $offered=stobeTravelRead($actor,$speaker,$now);\n"
     "    if (!is_array($offered) || ($offered['status']??'')!=='PROPOSED'\n"
     "        || stobeAreaGoalPointKey($offered)!==$resolved['travel_destination']) {\n",
     "!=='PROPOSED'\n        || stobeAreaGoalPointKey($offered)")
edit('lib/area_goal_integration.php',
     "        && strval($state['destination_point']['id']??'')===$resolved['travel_destination'];\n",
     "        && stobeAreaGoalPointKey($state)===$resolved['travel_destination'];\n",
     "&& stobeAreaGoalPointKey($state)===$resolved['travel_destination'];")
edit('lib/area_goal_integration.php',
     "/** Production-caller seam, preserving the same response and turn gates used\n",
     "/** The identity of a stored offer's point: a native candidate id, else the label of a visited/world town (imm26 24-b). */\n"
     "function stobeAreaGoalPointKey(mixed $state): string {\n"
     "    $point=is_array($state)&&is_array($state['destination_point']??null)?$state['destination_point']:[];\n"
     "    return strval($point['id']??$point['label']??'');\n"
     "}\n\n"
     "/** Request-local pin so stobeTravelResolvePlan can resolve the ONE server-chosen region town (even a rumoured one). Cleared by the caller. */\n"
     "function stobeAreaGoalPinRoute(array $resolved): void {\n"
     "    unset($GLOBALS['STOBE_TRAVEL_REGION_ROUTE_PIN']);\n"
     "    $point=$resolved['endpoint_point']??null;\n"
     "    if (($resolved['endpoint_source']??'')!=='world_town_region' || !is_array($point)) return;\n"
     "    $GLOBALS['STOBE_TRAVEL_REGION_ROUTE_PIN']=['label'=>strval($resolved['endpoint_label']??''),\n"
     "        'x'=>floatval($point['x']??0),'y'=>floatval($point['y']??0),'z'=>floatval($point['z']??0)];\n"
     "}\n\n"
     "/**\n"
     " * imm26 24-b first-leg offer for a conversational region agreement: PROPOSE only (server-written reply, NO movement action, no consent). The stored\n"
     " * PROPOSED agreement carries regional_goal{region, endpoint_*, evidence}; the region plan gets a route_ready row. The next explicit \"Yes\" is the\n"
     " * ordinary ACCEPT, which carries the goal over (stobeTravelRegionWaypointGoal / old-state carry, unchanged). A refused PROPOSE (policy, busy NPC)\n"
     " * shows the ordinary refusal and leaves the plan at awaiting_route.\n"
     " */\n"
     "function stobeAreaGoalOfferRoute(array $resolved,array $regionState,array $turn,string $actor,array|false $npc,\n"
     "    string $speaker,string $quote,int $now,string &$text,array &$actions): bool {\n"
     "    $actions=[];\n"
     "    $offerText=''; $offerActions=[];\n"
     "    stobeAreaGoalPinRoute($resolved);\n"
     "    try {\n"
     "        stobeTravelCapture(json_encode(['travel_decision'=>'PROPOSE','travel_kind'=>'same_route','travel_leader'=>'npc',\n"
     "            'travel_destination'=>$resolved['travel_destination'],'travel_reason'=>'Regional outing toward '.$resolved['region'],\n"
     "            'travel_player_quote'=>''],JSON_UNESCAPED_UNICODE),$actor,$npc,$speaker,$quote,$now,$offerText,$offerActions);\n"
     "    } finally { unset($GLOBALS['STOBE_TRAVEL_REGION_ROUTE_PIN']); }\n"
     "    $offered=stobeTravelRead($actor,$speaker,$now);\n"
     "    if (!is_array($offered) || ($offered['status']??'')!=='PROPOSED' || stobeAreaGoalPointKey($offered)!==$resolved['travel_destination']) {\n"
     "        $text=trim($offerText)!==''?$offerText:\"I understand the area, but I can't make a safe travel proposal yet.\"; return true;\n"
     "    }\n"
     "    $offered['regional_goal']=['region'=>$resolved['region'],'goal_source'=>'player_considers_region',\n"
     "        'endpoint_id'=>strval($offered['destination_point']['id']??''),'endpoint_label'=>strval($resolved['endpoint_label']),\n"
     "        'endpoint_source'=>$resolved['endpoint_source'],'endpoint_actor_serial'=>intval($resolved['endpoint_actor_serial']),\n"
     "        'endpoint_region_evidence'=>$resolved['endpoint_region_evidence'],'checked_gamets'=>$now];\n"
     "    if (is_array($resolved['endpoint_point']??null)) $offered['regional_goal']['endpoint_point']=$resolved['endpoint_point'];\n"
     "    if (!stobeTravelWrite($actor,$speaker,$now,$offered)) { $text=\"Let's discuss that again in a moment.\"; return true; }\n"
     "    if (function_exists('stobeRegionPlanRouteReady')) {\n"
     "        $ready=stobeRegionPlanRouteReady($regionState,$resolved,strval($offered['agreement_id']??''));\n"
     "        if (!stobeRegionPlanStore($turn['scope'],intval($turn['gamets']??0),['changed'=>true,'state'=>$ready]) && function_exists('stobeLogWarn'))\n"
     "            stobeLogWarn('Region route_ready row was not persisted',[]);\n"
     "    }\n"
     "    $text=\"Sure, let's head toward \".$resolved['region'].\". I'd lead us to \".$resolved['endpoint_label'].\" first - I can't promise the road is safe. Shall we set out?\";\n"
     "    return true;\n"
     "}\n\n"
     "/** Production-caller seam, preserving the same response and turn gates used\n",
     "function stobeAreaGoalOfferRoute(")

# ---- region_plan.php ------------------------------------------------------------------------------------------------------------------------------
edit('lib/region_plan.php',
     "/** Extend an existing strict JSON response schema without altering travel/action fields. */\n",
     "/**\n"
     " * imm26 24-b: the awaiting_route state after the NPC offered a first leg (stage route_ready). It records the grounded destination and the PROPOSED\n"
     " * agreement id for evidence; it grants no movement consent. The stage is deliberately NOT part of the referential-agreement stage lists: a plain \"yes\"\n"
     " * after the offer belongs to the ordinary travel ACCEPT.\n"
     " */\n"
     "function stobeRegionPlanRouteReady(array $awaiting,array $route,string $agreementId): array {\n"
     "    $state=['stage'=>'route_ready','scope'=>strval($awaiting['scope']??''),'proposed_region'=>strval($awaiting['proposed_region']??''),\n"
     "        'provenance'=>$awaiting['provenance']??[],'conceptual_agreement'=>true,'offer_source'=>strval($awaiting['offer_source']??'unpaired_concept'),\n"
     "        'quote'=>strval($awaiting['quote']??''),'movement_consent'=>false,\n"
     "        'endpoint_label'=>strval($route['endpoint_label']??''),'endpoint_source'=>strval($route['endpoint_source']??''),\n"
     "        'endpoint_region_evidence'=>strval($route['endpoint_region_evidence']??''),'agreement_id'=>$agreementId];\n"
     "    if (is_array($route['endpoint_point']??null)) $state['endpoint_point']=$route['endpoint_point'];\n"
     "    if (($route['travel_destination']??'')!=='' && ($route['endpoint_source']??'')==='current_actor_scoped_native_candidate') $state['endpoint_id']=strval($route['travel_destination']);\n"
     "    return $state;\n"
     "}\n"
     "/** Extend an existing strict JSON response schema without altering travel/action fields. */\n",
     "function stobeRegionPlanRouteReady(")
edit('lib/region_plan.php',
     " Preserve every existing travel leg, accepted destination and native task.",
     " Stage route_ready means the server already offered a first leg and is waiting for the player's own yes; never restate it as an accepted trip. Preserve every existing travel leg, accepted destination and native task.",
     "Stage route_ready means the server already offered")

# ---- travel_companionship.php ---------------------------------------------------------------------------------------------------------------------
edit('lib/travel_companionship.php',
     "        || ($marker['endpoint_source']??'')!=='current_actor_scoped_native_candidate'\n"
     "        || !in_array($marker['endpoint_region_evidence']??'', ['native_spatial_region','npc_known_town_region'],true)\n",
     "        || !in_array($marker['endpoint_source']??'', ['current_actor_scoped_native_candidate','world_town_region'],true)\n"
     "        || !in_array($marker['endpoint_region_evidence']??'', ['native_spatial_region','npc_known_town_region','world_town_region'],true)\n",
     "['current_actor_scoped_native_candidate','world_town_region']")
edit('lib/travel_companionship.php',
     "function stobeTravelResolvePlan(string $actor, array|false $npc, string $requested, ?array $old): array|false {\n",
     "function stobeTravelResolvePlan(string $actor, array|false $npc, string $requested, ?array $old): array|false {\n"
     "    // imm26 24-b: ONE server-chosen region town (stobeAreaGoalPinRoute, request-local, cleared by its caller) resolves like a visited location even when the\n"
     "    // player has not discovered it. Never the town the NPC stands in.\n"
     "    $pin = $GLOBALS['STOBE_TRAVEL_REGION_ROUTE_PIN'] ?? null;\n"
     "    if (is_array($pin) && trim($requested) !== '' && trim(strval($pin['label'] ?? '')) !== ''\n"
     "        && strcasecmp(trim($requested),trim(strval($pin['label']))) === 0\n"
     "        && strcasecmp(trim(strval($GLOBALS['CACHE_CITY'] ?? '')),trim(strval($pin['label']))) !== 0) {\n"
     "        return ['label'=>trim(strval($pin['label'])),'x'=>floatval($pin['x'] ?? 0),'y'=>floatval($pin['y'] ?? 0),'z'=>floatval($pin['z'] ?? 0),'source'=>'visited_location'];\n"
     "    }\n",
     "STOBE_TRAVEL_REGION_ROUTE_PIN")


def main():
    if len(sys.argv) != 2 or not os.path.isdir(sys.argv[1]):
        print('usage: apply.py <server-tree-root>', file=sys.stderr)
        return 2
    root = sys.argv[1]
    plan = []
    for rel in NEW_FILES:
        src = os.path.join(HERE, 'files', rel)
        if not os.path.isfile(src):
            print('MISSING source file', src, file=sys.stderr)
            return 3
        plan.append(('new', rel, open(src, 'rb').read()))
    texts = {}
    for path, old, new, marker in EDITS:
        full = os.path.join(root, path)
        if not os.path.isfile(full):
            print('MISSING target', full, file=sys.stderr)
            return 3
        text = texts.get(path)
        if text is None:
            text = open(full, 'rb').read().decode('utf-8')
        if marker in text:
            print('ALREADY-APPLIED', path, '::', marker[:50].replace('\n', ' '))
        else:
            n = text.count(old)
            if n != 1:
                print('ANCHOR %s (%d matches) in %s: %r' % ('MISSING' if n == 0 else 'AMBIGUOUS', n, path, old[:90]), file=sys.stderr)
                return 3
            text = text.replace(old, new)
            print('APPLIED', path, '::', marker[:50].replace('\n', ' '))
        texts[path] = text
    # everything asserted: write
    for path, text in texts.items():
        full = os.path.join(root, path)
        data = text.encode('utf-8')
        if open(full, 'rb').read() != data:
            open(full, 'wb').write(data)
    for kind, rel, data in plan:
        full = os.path.join(root, rel)
        os.makedirs(os.path.dirname(full), exist_ok=True)
        if os.path.isfile(full) and open(full, 'rb').read() == data:
            print('ALREADY-APPLIED', rel)
        else:
            open(full, 'wb').write(data)
            print('WROTE', rel)
    return 0


if __name__ == '__main__':
    sys.exit(main())
