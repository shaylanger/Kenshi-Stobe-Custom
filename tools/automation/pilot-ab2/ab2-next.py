#!/usr/bin/env python3
"""ab2-next.py [--json] [--check-only]: print the next pilot-2 run (seq, arm, model, row, agent name, the exact Agent description, and the filled spawn prompt)
from C:/KenshiTestRuns/pilot/ab2/plan.json + state.json. The coordinator spawns exactly ONE agent per call, waits for its DONE/FAILED status, then calls this again.
Refuses (exit 3) while: the previous seq's agent status is not DONE/FAILED/STOPPED-CONTEXT (arms never share the game); a RUNNING lock exists; the current agent already has a
status file that is not terminal (double spawn); a previous finished agent never produced a captured run (use `ab2-state.py void <seq> "<why>"`).
Exit 0 = go (touches ab2/ACTIVE so the stobe-auto ban applies from the spawn), 4 = plan complete.
"""
import sys, os, json
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import ab2_lib as L

TERMINAL = ("DONE", "FAILED", "STOPPED-CONTEXT", "STOPPED")


def main(a):
    as_json, check_only = "--json" in a, "--check-only" in a
    plan, st = L.load_plan(), L.load_state()
    runs, d = L.runs_dir(), L.ab2_dir()
    cur = L.cur_run(plan, st)
    if not cur:
        print("ab2-next: PLAN COMPLETE (%d runs). Run pilot-ab2-compare.py, then the README cleanup." % len(plan["runs"])); return 4
    if os.path.isdir(d + "/RUNNING"):
        print("ab2-next: REFUSED: a run is in progress (RUNNING lock %s). Wait for the agent." % json.dumps(L.read_json(d + "/RUNNING/info.json", {}))); return 3
    prev = [r for r in plan["runs"] if r["seq"] < cur["seq"]]
    if prev:
        p = prev[-1]
        s, f = L.agent_status(runs, p["agent"])
        voided = str(p["seq"]) in st.get("voided", {})
        if s is not None and s not in TERMINAL:
            print("ab2-next: REFUSED: previous agent %s is %s (%s). Wait for DONE/FAILED; arms never run at the same time." % (p["agent"], s, f)); return 3
        if s is None and not voided:
            print("ab2-next: REFUSED: previous agent %s has no status file (never started?). If it will not run: python ab2-state.py void %d \"<why>\"" % (p["agent"], p["seq"])); return 3
        if not voided and not st["runs"].get(str(p["seq"]), {}).get("done"):
            print("ab2-next: REFUSED: seq %d (%s) finished without a captured run. Void it: python ab2-state.py void %d \"<why>\"" % (p["seq"], p["agent"], p["seq"])); return 3
    s, f = L.agent_status(runs, cur["agent"])
    if s is not None and s not in TERMINAL:
        print("ab2-next: REFUSED: %s already has a status file in state %s (%s): double spawn?" % (cur["agent"], s, f)); return 3
    if s in TERMINAL:
        print("ab2-next: REFUSED: %s already has a terminal status (%s): this seq was already spawned. Void or fix: ab2-state.py void %d \"<why>\"" % (cur["agent"], s, cur["seq"])); return 3
    brief = open(d + "/brief.md", encoding="utf-8").read()
    prompt = brief.replace("{AGENT}", cur["agent"]).replace("{ARM}", cur["arm"]).replace("{ROW}", cur["row"]).replace("{SEQ}", str(cur["seq"]))
    desc = "[case:bench] [model:%s] [effort:high] %s" % (cur["model"], cur["agent"])
    if check_only:
        print("ab2-next: OK to spawn seq %d" % cur["seq"]); return 0
    open(d + "/ACTIVE", "a").close()
    if as_json:
        print(json.dumps({"seq": cur["seq"], "arm": cur["arm"], "row": cur["row"], "order": cur["order"], "agent": cur["agent"], "description": desc,
                          "subagent_type": "general-purpose", "prompt": prompt}))
        return 0
    print("ab2-next: seq %d/%d  arm=%s (%s)  row=%s  order=%s  agent=%s" % (cur["seq"], len(plan["runs"]), cur["arm"], cur["model"], cur["row"], cur["order"], cur["agent"]))
    print("Agent tool call: subagent_type=general-purpose, run_in_background=true")
    print("  description: " + desc)
    print("  prompt (%d chars, identical for both arms except name/arm/row):" % len(prompt))
    print("-----8<-----")
    print(prompt)
    print("-----8<-----")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
