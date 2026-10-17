#!/usr/bin/env python3
"""ab2-plan.py [--seed N] [--force-new] [--print]: write the FROZEN pilot-2 plan (C:/KenshiTestRuns/pilot/ab2/plan.json) once.
Reads queue.txt, shuffles the rows with the seed, assigns the first arm per row in the pattern A B B A A B B A ... (second run of each row = the other arm),
and records the lane baseline (Stobe.dll sha8 of both copies, deployed server bundle id, fingerprints of the base saves) and the script manifest (sha256[:12]
of every script each row command reaches). Never regenerated once written (--force-new refuses unless state.json does not exist yet; after a lane change use ab2-rebaseline.py, which archives the old plan and checks the lane).
Runs are a flat sequence: seq 1 = row1 first arm, seq 2 = row1 second arm, seq 3 = row2 first arm, ...
"""
import sys, os, json
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import ab2_lib as L


def main(a):
    seed, force, only_print = 20261016, False, False
    i = 0
    while i < len(a):
        if a[i] == "--seed" and i + 1 < len(a):
            seed = int(a[i + 1]); i += 2
        elif a[i] == "--force-new":
            force = True; i += 1
        elif a[i] == "--print":
            only_print = True; i += 1
        else:
            print(__doc__); return 2
    d = L.ab2_dir()
    os.makedirs(d, exist_ok=True)
    pp = d + "/plan.json"
    if os.path.exists(pp) and not only_print:
        if not force or os.path.exists(d + "/state.json"):
            print("ab2-plan: plan.json already exists (frozen; seed %s). Not regenerated." % L.read_json(pp).get("seed")); return 3
    plan = L.build_plan(seed)
    missing = [r for r, m in plan["manifest"].items() if not m]
    if missing:
        print("ab2-plan: WARNING no script found for rows %s" % missing)
    if only_print:
        print(json.dumps({k: plan[k] for k in ("seed", "rows", "first_arm_of_row_1", "baseline")}, indent=1))
        for r in plan["runs"]:
            print("seq %2d  %-6s %-5s %s" % (r["seq"], r["arm"], r["order"], r["row"]))
        return 0
    L.write_json(pp, plan)
    print("ab2-plan: wrote %s (%d rows, %d runs, seed %s)" % (pp, len(plan["rows"]), len(plan["runs"]), seed))
    for r in plan["runs"]:
        print("seq %2d  %-6s %-6s %s" % (r["seq"], r["arm"], r["order"], r["row"]))
    print("baseline:", json.dumps(plan["baseline"]))
    print("manifest files per row:", {r: len(m) for r, m in plan["manifest"].items()})
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
