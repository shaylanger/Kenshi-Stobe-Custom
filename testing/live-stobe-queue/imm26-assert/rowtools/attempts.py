#!/usr/bin/env python3
"""attempts.py: per-lane, per-row attempt counter for go-row.sh / go-batch.sh (PI-06: one debug attempt per row, enforced).
State:  <DIR>/<lane>.json   {"rows": {"<ROW>": {"attempts": n, "last": "FAIL", "cause": "...", "evidence": "...", "t": "..."}}}
Audit:  <DIR>/attempts.log  one line per event: time lane=.. row=.. event=START|VERDICT|BLOCK|ALLOW|RESET|CLEAR attempt=.. ...
Usage:
  attempts.py check  DIR LANE ROW [ALLOW_REASON]   exit 0 = run it (START logged); exit 4 = prints `ROW-NEEDS-FIXER <ROW> <LANE> cause=...`
  attempts.py record DIR LANE ROW VERDICT CAUSE [EVIDENCE]   PASS/GATED clear the failure block; FAIL/SETUP-FAIL count an attempt;
                                                              PREFLIGHT-FAIL (row never ran) is logged only, not counted
  attempts.py reset  DIR LANE ROW REASON            forget the row's failed state (reason is mandatory, logged)
  attempts.py show   DIR [LANE]                     current state + last 15 audit lines
"""
import sys, os, json, time

def now(): return time.strftime("%Y-%m-%dT%H:%M:%S")
def one(s, n=400): return " ".join(str(s).split())[:n]

def load(d, lane):
    p = os.path.join(d, lane + ".json")
    try:
        with open(p, encoding="utf-8") as f: return json.load(f)
    except Exception: return {"rows": {}}

def save(d, lane, st):
    os.makedirs(d, exist_ok=True)
    p = os.path.join(d, lane + ".json"); tmp = p + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f: json.dump(st, f, indent=1)
    os.replace(tmp, p)

def log(d, lane, row, event, **kv):
    os.makedirs(d, exist_ok=True)
    line = "%s lane=%s row=%s event=%s %s" % (now(), lane, row, event, " ".join("%s=%s" % (k, one(v)) for k, v in kv.items()))
    with open(os.path.join(d, "attempts.log"), "a", encoding="utf-8") as f: f.write(line.rstrip() + "\n")

def ticket_hook(d, lane, row, verdict, cause):
    """SETUP-FAIL unblock tickets (tools/automation/setupfail.py): SETUP-FAIL opens/updates <runs>/setupfail/<row>.json, PASS/FAIL/GATED closes it,
    PREFLIGHT-FAIL is exempt. <runs> = the parent of DIR (DIR = <runs>/row-attempts). Never breaks a record: any error is swallowed."""
    try:
        sp = os.environ.get("KAH_SETUPFAIL_PY") or os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "..", "..", "tools", "automation", "setupfail.py")
        if not os.path.isfile(sp): return
        import importlib.util
        spec = importlib.util.spec_from_file_location("setupfail", sp); m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
        m.on_verdict(row, lane, verdict, cause, runs=os.path.dirname(os.path.abspath(d)))
    except Exception: pass

def main(a):
    if len(a) < 2: print(__doc__); return 2
    cmd, d = a[0], a[1]
    if cmd == "show":
        lanes = [a[2]] if len(a) > 2 else sorted(x[:-5] for x in os.listdir(d) if x.endswith(".json")) if os.path.isdir(d) else []
        for lane in lanes:
            for row, r in sorted(load(d, lane)["rows"].items()):
                print("%s %s attempts=%s last=%s cause=%s" % (lane, row, r.get("attempts"), r.get("last"), one(r.get("cause", ""), 160)))
        lp = os.path.join(d, "attempts.log")
        if os.path.isfile(lp):
            print("-- last audit lines"); print("".join(open(lp, encoding="utf-8").readlines()[-15:]), end="")
        return 0
    if len(a) < 4: print(__doc__); return 2
    lane, row = a[2], a[3]
    st = load(d, lane); r = st["rows"].get(row)
    if cmd == "check":
        reason = a[4] if len(a) > 4 else ""
        n = (r or {}).get("attempts", 0)
        if r and r.get("last") in ("FAIL", "SETUP-FAIL") and n >= 1:
            if not reason:
                log(d, lane, row, "BLOCK", attempt=n + 1, last=r.get("last"), cause=r.get("cause", ""))
                print("ROW-NEEDS-FIXER %s %s cause=%s evidence=%s (override: --allow-retry \"<reason>\" or row-attempts.ps1 reset %s %s \"<reason>\")"
                      % (row, lane, one(r.get("cause", "?"), 300), r.get("evidence", "?"), lane, row))
                return 4
            log(d, lane, row, "ALLOW", attempt=n + 1, reason=reason, last=r.get("last"))
        log(d, lane, row, "START", attempt=n + 1)
        return 0
    if cmd == "record":
        verdict = a[4] if len(a) > 4 else "?"; cause = a[5] if len(a) > 5 else ""; ev = a[6] if len(a) > 6 else ""
        n = (r or {}).get("attempts", 0)
        if verdict == "PASS":
            st["rows"].pop(row, None); log(d, lane, row, "VERDICT", verdict=verdict, attempt=n + 1, cleared="yes")
        elif verdict in ("FAIL", "SETUP-FAIL"):
            st["rows"][row] = {"attempts": n + 1, "last": verdict, "cause": one(cause, 600), "evidence": ev, "t": now()}
            log(d, lane, row, "VERDICT", verdict=verdict, attempt=n + 1, cause=cause)
        elif verdict == "GATED":
            st["rows"][row] = {"attempts": n, "last": "GATED", "cause": one(cause, 600), "evidence": ev, "t": now()}
            log(d, lane, row, "VERDICT", verdict=verdict, attempt=n + 1, cause=cause)
        else:  # PREFLIGHT-FAIL and anything else: the row did not run; not counted, block state unchanged
            log(d, lane, row, "VERDICT", verdict=verdict, attempt=n + 1, counted="no", cause=cause)
        save(d, lane, st); ticket_hook(d, lane, row, verdict, cause); return 0
    if cmd == "reset":
        reason = a[4] if len(a) > 4 else ""
        if not reason: print("reset needs a reason"); return 2
        was = (r or {}).get("attempts", 0)
        st["rows"].pop(row, None); save(d, lane, st); log(d, lane, row, "RESET", was_attempts=was, reason=reason)
        print("RESET %s %s (was %s attempts) reason=%s" % (lane, row, was, one(reason))); return 0
    print(__doc__); return 2

if __name__ == "__main__": sys.exit(main(sys.argv[1:]))
