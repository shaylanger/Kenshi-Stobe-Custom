#!/usr/bin/env python3
"""apply.py <server-tree-root>   (imm26 fixR2serial; SERVER ONLY; apply on top of WP-R2 (pending-fixes/imm26-regionR2) to a lane/compose copy, never the live tree)

DEFECT (found live by 5090-i3op25, report C:/KenshiTestRuns/agents/out/imm26-5090-i3op25/out-20261016-161342.md): WP-R2's region route is never reached in
production. stobeSocialPreferenceScope() puts SOCIAL DB IDS in the manual scope (actor_id e.g. '5969', speaker_id '2'), but the area-goal code compared those
ids with the LIVE native serials (2529907200 / 971557632):
  lib/area_goal_integration.php stobeAreaGoalReadCurrentTrip  intval(scope actor_id/speaker_id) !== stobeResolveLiveParticipantSerial(...)  -> read fails
      -> the fixed reply "I understand the area, but I can't verify our current trip or route yet."
  lib/area_goal.php stobeAreaGoalResolve                       scope actor_id !== $actorSerial ; read speaker_serial !== scope speaker_id
  lib/area_goal_integration.php call site                      passes intval(scope actor_id) as the "actor serial"
  lib/travel_companionship.php stobeTravelTakeRegionalConsent  readScope actor_id/speaker_id !== live serials (would refuse the same-turn exact consent)
Fixture tests passed only because they set id == serial.

FIX: the scope ids stay the region_plan key only (stobeRegionPlanScope). The trip key, the trip read, the resolve and the consent marker bind the LIVE serials:
  - stobeAreaGoalLiveActorSerial() (same lookup as stobeTravelKey: stobeTravelActorSerial); the read proof carries live actor/speaker serials, requires both > 0
    and the three scope fields (shape only)
  - the call site passes the live actor serial and the live speaker serial; stobeAreaGoalResolve(..., int $speakerSerial = 0) requires the read's actor serial ===
    the argument (> 0) and the read's speaker serial > 0 and === $speakerSerial when given
  - stobeTravelTakeRegionalConsent: the two scope-id-vs-serial comparisons are removed; identity is still bound by endpoint_actor_serial, trip_read_actor_serial,
    trip_read_speaker_serial (live serials) and the scope hash.
All edits anchored, idempotent (ALREADY-APPLIED), a missing anchor exits 3 without writing anything.
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
NEW_FILES = ['tests/imm26_regionroute_serial_regression.php']
EDITS = []


def edit(path, old, new, marker):
    EDITS.append((path, old, new, marker))


edit('lib/area_goal_integration.php',
     "/** Explicit query receipt: unlike stobeTravelRead()'s nullable result, this\n",
     "/** imm26 fixR2serial: the LIVE native serial of the addressed NPC (same lookup as stobeTravelKey). The social scope ids are DB ids, never serials. */\n"
     "function stobeAreaGoalLiveActorSerial(string $actor): int {\n"
     "    return function_exists('stobeTravelActorSerial') ? stobeTravelActorSerial($actor) : stobeResolveLiveParticipantSerial($actor, true);\n"
     "}\n\n"
     "/** Explicit query receipt: unlike stobeTravelRead()'s nullable result, this\n",
     "function stobeAreaGoalLiveActorSerial(")
edit('lib/area_goal_integration.php',
     "    $readProof=['scope'=>$readScope,'actor_serial'=>stobeResolveLiveParticipantSerial($actor),\n"
     "        'speaker_serial'=>stobeResolveLiveParticipantSerial($speaker),'gamets'=>$gamets];\n"
     "    $empty=$readProof+['read_succeeded'=>false,'state'=>null];\n"
     "    if ($gamets<=0 || !isset($GLOBALS['db']) || !function_exists('stobeTravelKey')\n"
     "        || intval($scope['actor_id']??0)!==stobeResolveLiveParticipantSerial($actor)\n"
     "        || intval($scope['speaker_id']??0)!==stobeResolveLiveParticipantSerial($speaker)) return $empty;\n",
     "    // imm26 fixR2serial: scope ids are SOCIAL DB ids (region_plan key only); the trip key and this proof use the LIVE serials of the two names.\n"
     "    $actorSerial=stobeAreaGoalLiveActorSerial($actor);$speakerSerial=stobeResolveLiveParticipantSerial($speaker);\n"
     "    $readProof=['scope'=>$readScope,'actor_serial'=>$actorSerial,'speaker_serial'=>$speakerSerial,'gamets'=>$gamets];\n"
     "    $empty=$readProof+['read_succeeded'=>false,'state'=>null];\n"
     "    if ($gamets<=0 || !isset($GLOBALS['db']) || !function_exists('stobeTravelKey')\n"
     "        || $actorSerial<=0 || $speakerSerial<=0 || count($readScope)!==3) return $empty;\n",
     "$actorSerial=stobeAreaGoalLiveActorSerial($actor);")
edit('lib/area_goal_integration.php',
     "        intval($turn['scope']['actor_id']),$now,$turn['scope'],$trip,$knownRegions,$currentTown,$townRoute);\n",
     "        stobeAreaGoalLiveActorSerial($actor),$now,$turn['scope'],$trip,$knownRegions,$currentTown,$townRoute,stobeResolveLiveParticipantSerial($speaker));\n",
     "$townRoute,stobeResolveLiveParticipantSerial($speaker));")
edit('lib/area_goal.php',
     "string $currentTown = '', array $townRoute = []): array {\n",
     "string $currentTown = '', array $townRoute = [], int $speakerSerial = 0): array {\n",
     "int $speakerSerial = 0): array {")
edit('lib/area_goal.php',
     "    if ($expectedScope === '' || ($regionPlan['scope'] ?? '') !== $expectedScope\n"
     "        || intval($trustedScope['actor_id'] ?? 0) !== $actorSerial) {\n",
     "    // imm26 fixR2serial: $actorSerial is the LIVE serial; the scope ids are social DB ids (region_plan key only) and are never compared with it.\n"
     "    if ($expectedScope === '' || ($regionPlan['scope'] ?? '') !== $expectedScope\n"
     "        || $actorSerial <= 0) {\n",
     "|| $actorSerial <= 0) {")
edit('lib/area_goal.php',
     "        || intval($currentTravelRead['speaker_serial'] ?? 0) !== intval($trustedScope['speaker_id'] ?? 0)\n",
     "        || intval($currentTravelRead['speaker_serial'] ?? 0) <= 0\n"
     "        || ($speakerSerial > 0 && intval($currentTravelRead['speaker_serial'] ?? 0) !== $speakerSerial)\n",
     "($speakerSerial > 0 && intval(")
edit('lib/travel_companionship.php',
     "        || intval($marker['trip_read_gamets']??0)!==$gamets\n"
     "        || strval($readScope['actor_id']??'')!==strval(stobeTravelActorSerial($actor))\n"
     "        || strval($readScope['speaker_id']??'')!==strval(stobeResolveLiveParticipantSerial($speaker))\n",
     "        || intval($marker['trip_read_gamets']??0)!==$gamets\n"
     "        // imm26 fixR2serial: readScope ids are social DB ids (hash-bound above), not serials; identity is bound by the live serials checked above.\n",
     "imm26 fixR2serial: readScope ids")


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
