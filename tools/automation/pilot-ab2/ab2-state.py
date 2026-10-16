#!/usr/bin/env python3
"""ab2-state.py: plan/state machine of the pilot-2 kit (called by ab2-run.sh and the coordinator).
  begin  <arm> <row>                       turn check + RUNNING lock + baseline/script-drift check; prints `CMD <expanded command>` (exit 5 = refused)
  end    <arm> <row> <exit> <start_epoch> <result line...>   write captures.jsonl, release the lock, advance to the next seq
  abort  <arm> <row> <why>                 release the lock WITHOUT advancing (reset failed etc.)
  void   <seq> <why>                       skip a run on purpose (agent never ran / lane broke); advances when it is the current seq
  unlock <why>                             remove a stale RUNNING lock (crashed run); does not advance
  status                                   one line per run: done / current / pending / voided
Refuses (exit 5) when: not the current seq of plan.json for (arm,row); a RUNNING lock exists; the lane baseline (Stobe.dll sha8 of both copies,
server bundle id, base-save fingerprints) differs from plan.json; for the SECOND arm of a row any script reached by the row command differs from what the
FIRST arm ran. AB2_ALLOW_DRIFT=1 lets a run through and records `drift` in captures.jsonl.
"""
import sys, os, json, time
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import ab2_lib as L


def lockdir():
    return L.ab2_dir() + "/RUNNING"


def refuse(msg):
    print("ab2: REFUSED: " + msg)
    return 5


def cmd_begin(arm, row):
    plan, st = L.load_plan(), L.load_state()
    cur = L.cur_run(plan, st)
    if not cur:
        return refuse("the plan is complete (cur=%s); nothing to run" % st["cur"])
    if (cur["arm"], cur["row"]) != (arm, row):
        return refuse("not your turn: the current run is seq %d = arm %s row %s (you asked %s %s)" % (cur["seq"], cur["arm"], cur["row"], arm, row))
    try:
        os.mkdir(lockdir())
    except FileExistsError:
        info = L.read_json(lockdir() + "/info.json", {})
        return refuse("a run is already in progress (RUNNING lock: %s)" % json.dumps(info))
    drift, allow = [], os.environ.get("AB2_ALLOW_DRIFT") == "1"
    base = L.baseline()
    bd = L.baseline_diff(plan.get("baseline") or {}, base)
    ref = None
    if cur["order"] == "second":
        for r in plan["runs"]:
            if r["row"] == row and r["order"] == "first":
                ref = st["runs"].get(str(r["seq"]), {}).get("manifest")
    mf = L.manifest(plan["queue"][row])
    ref = ref or plan["manifest"].get(row) or {}
    md = ["%s %s->%s" % (k, ref.get(k, "-"), mf.get(k, "-")) for k in sorted(set(ref) | set(mf)) if ref.get(k) != mf.get(k)]
    if cur["order"] == "first":
        md = []   # the first arm defines the reference; plan-time hashes are informational
    drift = (["baseline: " + x for x in bd] + ["script: " + x for x in md])
    if drift and not allow:
        os.rmdir(lockdir())
        return refuse("control broken (%s). Void/redo the pair or set AB2_ALLOW_DRIFT=1 and accept the note. Details: %s" % ("same DLL/bundle/save and scripts required", "; ".join(drift)[:900]))
    info = {"seq": cur["seq"], "arm": arm, "row": row, "begin": L.now_iso(), "pid": os.getpid()}
    L.write_json(lockdir() + "/info.json", info)
    st["runs"][str(cur["seq"])] = {"arm": arm, "row": row, "begin": info["begin"], "manifest": mf, "baseline": base, "drift": drift}
    L.save_state(st)
    print("CMD " + L.expand(plan["queue"][row], arm))
    if drift:
        print("ab2: WARNING drift allowed: " + "; ".join(drift)[:600])
    return 0


def cmd_end(arm, row, exit_code, start_epoch, result):
    plan, st = L.load_plan(), L.load_state()
    cur = L.cur_run(plan, st)
    if not cur or (cur["arm"], cur["row"]) != (arm, row):
        return refuse("end for %s %s but the current run is %s" % (arm, row, cur))
    rec = st["runs"].get(str(cur["seq"]), {})
    t1 = time.time()
    kind = ""
    parts = result.split()
    if len(parts) >= 3 and parts[0] == "RESULT":
        kind = parts[2]
    cap = {"seq": cur["seq"], "order": cur["order"], "arm": arm, "model": cur["model"], "row": row, "agent": cur["agent"],
           "begin": rec.get("begin"), "end": L.now_iso(), "start_epoch": float(start_epoch) if start_epoch else None, "end_epoch": t1,
           "wall_s": int(t1 - float(start_epoch)) if start_epoch else None, "exit": int(exit_code), "checker": kind,
           "result_line": result[:700], "baseline": rec.get("baseline"), "manifest_files": len(rec.get("manifest") or {}),
           "manifest_sha": __import__("hashlib").sha256(json.dumps(rec.get("manifest"), sort_keys=True).encode()).hexdigest()[:12], "drift": rec.get("drift") or []}
    L.append_jsonl(L.ab2_dir() + "/captures.jsonl", cap)
    rec.update({"end": cap["end"], "exit": cap["exit"], "checker": kind, "done": True})
    st["runs"][str(cur["seq"])] = rec
    st["cur"] = cur["seq"] + 1
    L.save_state(st)
    try:
        os.remove(lockdir() + "/info.json"); os.rmdir(lockdir())
    except OSError:
        pass
    print("ab2: run seq %d (%s %s) captured: checker=%s exit=%s wall=%ss; next seq %d" % (cur["seq"], arm, row, kind or "?", exit_code, cap["wall_s"], st["cur"]))
    return 0


def cmd_abort(arm, row, why):
    plan, st = L.load_plan(), L.load_state()
    cur = L.cur_run(plan, st)
    if cur and str(cur["seq"]) in st["runs"]:
        st["runs"][str(cur["seq"])]["aborted"] = why[:300]
        L.save_state(st)
    try:
        os.remove(lockdir() + "/info.json"); os.rmdir(lockdir())
    except OSError:
        pass
    L.append_jsonl(L.ab2_dir() + "/captures.jsonl", {"event": "abort", "arm": arm, "row": row, "at": L.now_iso(), "why": why[:300]})
    print("ab2: aborted %s %s (%s); not advanced" % (arm, row, why[:120]))
    return 0


def cmd_void(seq, why):
    plan, st = L.load_plan(), L.load_state()
    st.setdefault("voided", {})[str(seq)] = {"why": why[:300], "at": L.now_iso()}
    if st["cur"] == int(seq):
        st["cur"] += 1
    L.save_state(st)
    L.append_jsonl(L.ab2_dir() + "/captures.jsonl", {"event": "void", "seq": int(seq), "at": L.now_iso(), "why": why[:300]})
    print("ab2: seq %s voided (%s); cur=%d" % (seq, why[:120], st["cur"]))
    return 0


def cmd_unlock(why):
    try:
        os.remove(lockdir() + "/info.json")
    except OSError:
        pass
    try:
        os.rmdir(lockdir()); print("ab2: lock removed (%s)" % why[:120])
    except OSError:
        print("ab2: no lock")
    L.append_jsonl(L.ab2_dir() + "/captures.jsonl", {"event": "unlock", "at": L.now_iso(), "why": why[:300]})
    return 0


def cmd_status():
    plan, st = L.load_plan(), L.load_state()
    for r in plan["runs"]:
        s = st["runs"].get(str(r["seq"]), {})
        tag = "VOID" if str(r["seq"]) in st.get("voided", {}) else ("done" if s.get("done") else ("CURRENT" if r["seq"] == st["cur"] else "pending"))
        print("seq %2d %-6s %-6s %-6s %-8s %s" % (r["seq"], r["arm"], r["order"], r["row"], tag, (s.get("checker") or "") + (" drift" if s.get("drift") else "")))
    print("lock:", "HELD " + json.dumps(L.read_json(lockdir() + "/info.json", {})) if os.path.isdir(lockdir()) else "free")
    return 0


def main(a):
    if not a:
        print(__doc__); return 2
    c = a[0]
    if c == "begin" and len(a) == 3:
        return cmd_begin(a[1], a[2])
    if c == "end" and len(a) >= 5:
        return cmd_end(a[1], a[2], a[3], a[4], " ".join(a[5:]))
    if c == "abort" and len(a) >= 3:
        return cmd_abort(a[1], a[2], " ".join(a[3:]))
    if c == "void" and len(a) >= 3:
        return cmd_void(a[1], " ".join(a[2:]))
    if c == "unlock":
        return cmd_unlock(" ".join(a[1:]))
    if c == "status":
        return cmd_status()
    print(__doc__); return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
