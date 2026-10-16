#!/usr/bin/env python3
"""apply_region_name_forward.py <server-tree-root>   (imm26-sfE2, PROPOSAL, not deployed)

Server half of the 24-b/24-c area-goal fix. stobeTravelLocalCandidates() (lib/travel_companionship.php) copies only the optional spatial text fields
direction, anchor_name, anchor_type, relation, terrain, path_evidence, town_name from the native candidate; `region_name` is dropped, so
stobeAreaGoalEndpointValid() (lib/area_goal.php:30) can never match `spatial.region_name == region` (its first proof). This script adds 'region_name' to that
whitelist (anchor asserted, idempotent: a second run reports ALREADY-APPLIED, exit 0). Use on /root/imm26/compose first (php -l + tests/imm26_wpE_region_regression.php),
never on the live tree without Shay. It is useless alone: the native producer must also emit it (see NATIVE below).

NATIVE half (not built; needs a coordinator-assigned native work package, ~1 file, small):
  components/STOBE/src/LocalTravel.cpp  Json() (~line 170-196) writes the candidate "spatial":{...}; add `,\"region_name\":\"<EscapeJSON(c.region)>\"` after town_name, and fill
  Candidate::region where candidates are built (LocalTravel.cpp ~276 landmark, ~471 building/landmark, ~422 known_place in the N1 source) with the region of the CANDIDATE POINT,
  resolved like Context.cpp:3936-3948 does for an actor (town region -> zone -> ResolveMappedRegionFromTownName(town)); leave it empty when unknown. Unknown/empty must stay
  empty: the server compares case-insensitively to the consented region and never infers.
Also decide (Shay): area_goal.php:36-37 rejects any candidate whose anchor equals the NPC's CURRENT town; keep (default) or relax for region == current region.
"""
import os
import re
import sys

OLD = "foreach (['direction','anchor_name','anchor_type','relation','terrain','path_evidence','town_name'] as $field) {"
NEW = "foreach (['direction','anchor_name','anchor_type','relation','terrain','path_evidence','town_name','region_name'] as $field) {"


def main(root):
    p = os.path.join(root, 'lib', 'travel_companionship.php')
    s = open(p, encoding='utf-8').read()
    if NEW in s:
        print('ALREADY-APPLIED ' + p)
        return 0
    if s.count(OLD) != 1:
        print('ANCHOR-MISSING (%d matches) in %s' % (s.count(OLD), p))
        return 3
    open(p, 'w', encoding='utf-8', newline='').write(s.replace(OLD, NEW))
    print('APPLIED ' + p)
    return 0


if __name__ == '__main__':
    if len(sys.argv) != 2:
        print(__doc__)
        sys.exit(2)
    sys.exit(main(sys.argv[1]))
