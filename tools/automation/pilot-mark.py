#!/usr/bin/env python3
"""pilot-mark.py: SHADOW verdict ledger for the Haiku-vs-Sonnet operator pilot (lane 5090-i4). Called through pilot-mark.sh.
  pilot-mark.py <agent> <ROW> START|PASS|FAIL|SETUP-FAIL|GATED|ESCALATE ["<evidence text>"] [--evidence-file P] [--lane L] [--model M]
Shadow mode: never touches claims\\, never writes NPC_IMMERSION_26_TESTS.md, never opens/closes setupfail tickets, never commits.
Writes <pilot>/verdicts.csv (row,lane,model,start,end,wall_s,tokens,cost,operator_verdict,checker_result,agree,false_claims_n,notes),
<pilot>/events.log (every call incl. refused ones), <pilot>/state.json (per-row bookkeeping) and, on ESCALATE, an inbox message.
  START     before each row: records the start time (wall_s later), creates <pilot>/ACTIVE (switches off real setupfail tickets for lane 5090-i4).
  PASS      accepted only if the evidence file (or dir/result.txt) holds a checker line `RESULT <row> PASS ...` (the LAST RESULT line for the row)
            that is not older than the row's START. Otherwise refused, exit 3, logged as a wrong-verdict attempt (a 2nd refusal on the row = ESCALATE).
  FAIL      accepted only if the last RESULT line is FAIL; a 2nd FAIL of the same row = ESCALATE. Otherwise refused, exit 3.
  SETUP-FAIL / GATED / ESCALATE / anything else   = ESCALATE: recorded, inbox\\coordinator\\<ts>-pilot-escalate-<row>.msg ("PILOT-ESCALATE <row> ..."),
            the row is closed for the operator (exit 4): do NOT retry or diagnose it, take the next row.
Exit: 0 accepted/started, 2 usage, 3 refused (wrong verdict), 4 escalated / row closed. Env: KAH_RUNS_DIR, KAH_PILOT_DIR, PILOT_MODEL (default haiku).
"""
import sys, os, re, csv, json, datetime, time

HEADER = ["row", "lane", "model", "start", "end", "wall_s", "tokens", "cost", "operator_verdict", "checker_result", "agree", "false_claims_n", "notes"]
RESULT_RE = r"^\s*RESULT\s+(?:IMM-)?%s\s+(\S+)(.*)$"


def runs_dir():
    d = os.environ.get("KAH_RUNS_DIR")
    if d:
        return d
    for c in ("/c/KenshiTestRuns", "/mnt/c/KenshiTestRuns", "C:\\KenshiTestRuns"):
        if os.path.isdir(c):
            return c
    return "C:\\KenshiTestRuns"


def fixpath(p):
    m = re.match(r"^([A-Za-z]):[\\/](.*)$", p)
    if m and os.name == "posix":
        for base in ("/mnt/%s", "/%s"):
            q = os.path.join(base % m.group(1).lower(), m.group(2).replace("\\", "/"))
            if os.path.exists(q):
                return q
        return os.path.join("/mnt/%s" % m.group(1).lower(), m.group(2).replace("\\", "/"))
    return p


def now():
    return datetime.datetime.now()


def iso(t):
    return t.strftime("%Y-%m-%dT%H:%M:%S")


def load_state(p):
    try:
        return json.load(open(p, encoding="utf-8"))
    except Exception:
        return {"rows": {}}


def save_state(p, st):
    tmp = p + ".tmp"
    json.dump(st, open(tmp, "w", encoding="utf-8"), indent=1)
    os.replace(tmp, p)


def checker_line(path, row):
    """(kind, full line) of the LAST `RESULT <row> <kind>` line in the file/dir, or (None, reason)."""
    if not path:
        return None, "no evidence file given"
    path = fixpath(path)
    if os.path.isdir(path):
        path = os.path.join(path, "result.txt")
    if not os.path.isfile(path):
        return None, "evidence file not found: %s" % path
    last = None
    rx = re.compile(RESULT_RE % re.escape(row))
    with open(path, encoding="utf-8", errors="replace") as f:
        for ln in f:
            ln = ln.rstrip("\r\n")
            m = rx.match(ln)
            if m:
                last = (m.group(1).upper(), ln.strip())
    if not last:
        return None, "no `RESULT %s ...` line in %s" % (row, path)
    return last[0], last[1] + "  [file=%s mtime=%s]" % (path, iso(datetime.datetime.fromtimestamp(os.path.getmtime(path))))


def main(a):
    pos, ev_file, lane, model = [], None, os.environ.get("KAH_LANE", "5090-i4"), os.environ.get("PILOT_MODEL", "haiku")
    i = 0
    while i < len(a):
        if a[i] in ("--evidence-file", "--lane", "--model") and i + 1 < len(a):
            if a[i] == "--evidence-file":
                ev_file = a[i + 1]
            elif a[i] == "--lane":
                lane = a[i + 1]
            else:
                model = a[i + 1]
            i += 2
        elif a[i] in ("--next", "--task") and i + 1 < len(a):
            i += 2  # status-line options, handled by pilot-mark.sh
        elif a[i] in ("--no-status",):
            i += 1
        else:
            pos.append(a[i]); i += 1
    if len(pos) < 3:
        print(__doc__); return 2
    agent, row, verdict = pos[0], re.sub(r"^IMM-", "", pos[1].strip()), pos[2].strip().upper()
    note = pos[3] if len(pos) > 3 else ""
    if not re.match(r"^\d{2}-[a-z]{1,3}$", row):
        print("pilot-mark: bad row id '%s' (use e.g. 05-cx)" % row); return 2
    runs = runs_dir()
    pd = os.environ.get("KAH_PILOT_DIR") or os.path.join(runs, "pilot", "haiku-i4")
    os.makedirs(pd, exist_ok=True)
    stp, evlog, csvp = os.path.join(pd, "state.json"), os.path.join(pd, "events.log"), os.path.join(pd, "verdicts.csv")
    st = load_state(stp)
    rs = st["rows"].setdefault(row, {"wrong": 0, "fails": 0, "final": None, "escalated": False})
    t = now()

    def log(kind, text):
        with open(evlog, "a", encoding="utf-8") as f:
            f.write("%s agent=%s lane=%s row=%s verdict=%s %s: %s\n" % (iso(t), agent, lane, row, verdict, kind, text.replace("\n", " ")[:600]))

    def write_csv(op_verdict, checker, agree, notes):
        new = not os.path.isfile(csvp) or os.path.getsize(csvp) == 0
        start = rs.get("start", "")
        wall = ""
        if rs.get("start_epoch"):
            wall = str(int(time.time() - rs["start_epoch"]))
        with open(csvp, "a", encoding="utf-8", newline="") as f:
            w = csv.writer(f, lineterminator=chr(10))
            if new:
                w.writerow(HEADER)
            w.writerow([row, lane, model, start, iso(t), wall, "", "", op_verdict, checker, agree, "", notes[:500]])

    if verdict == "START":
        if rs["escalated"] or rs["final"] in ("PASS",):
            msg = "row %s is closed for you (%s): take the next row of rows-i4.txt" % (row, "escalated" if rs["escalated"] else rs["final"])
            log("START-REFUSED", msg); print("pilot-mark: " + msg); return 4
        rs["start"], rs["start_epoch"] = iso(t), time.time()
        save_state(stp, st)
        open(os.path.join(pd, "ACTIVE"), "a").close()
        log("START", note)
        print("pilot-mark: STARTED %s at %s" % (row, rs["start"])); return 0

    if rs["escalated"]:
        msg = "row %s was ESCALATED: do not retry or re-mark it; take the next row" % row
        log("CLOSED", msg); print("pilot-mark: " + msg); return 4

    kind, cline = checker_line(ev_file, row)
    # staleness: the checker line must come from this attempt
    stale = False
    if kind and rs.get("start_epoch"):
        m = re.search(r"file=(.*?) mtime=", cline)
        fp = m.group(1) if m else None
        try:
            if fp and os.path.getmtime(fp) < rs["start_epoch"] - 5:
                stale = True
        except OSError:
            pass

    def escalate(reason):
        rs["escalated"] = not row.startswith("00-")   # 00-* = a question for the coordinator, never closes anything
        save_state(stp, st)
        agree = "1" if kind and kind == verdict else ("n/a" if verdict == "ESCALATE" else "0")
        write_csv(verdict, cline if kind else "-", agree, "ESCALATE: %s | %s" % (reason, note))
        log("ESCALATE", "%s | checker=%s | note=%s" % (reason, cline, note))
        inbox = os.path.join(runs, "inbox", "coordinator")
        os.makedirs(inbox, exist_ok=True)
        fn = os.path.join(inbox, "%s-pilot-escalate-%s.msg" % (t.strftime("%Y%m%d-%H%M%S"), row))
        while os.path.exists(fn):
            fn = fn[:-4] + "x.msg"
        with open(fn, "w", encoding="utf-8") as f:
            f.write("PILOT-ESCALATE %s lane=%s agent=%s operator_verdict=%s reason=%s\nchecker: %s\nevidence_file: %s\noperator note: %s\n"
                    "The Haiku operator has stopped on this row (no retry, no diagnosis) and continues with the next row.\n" % (row, lane, agent, verdict, reason, cline, ev_file or "-", note))
        print("pilot-mark: ESCALATED %s (%s). Coordinator informed (%s). Do NOT retry or diagnose this row: take the next row." % (row, reason, os.path.basename(fn)))
        return 4

    def refuse(why):
        rs["wrong"] += 1
        save_state(stp, st)
        write_csv(verdict, cline if kind else "-", "0", "REFUSED wrong-verdict #%d: %s | %s" % (rs["wrong"], why, note))
        log("REFUSED", "%s | checker=%s" % (why, cline))
        if rs["wrong"] >= 2:
            return escalate("second wrong verdict attempt (%s)" % why)
        print("pilot-mark: REFUSED %s %s: %s. Checker line: %s. Mark exactly what the checker printed (or ESCALATE), do not rerun the row." % (row, verdict, why, cline))
        return 3

    if verdict in ("PASS", "FAIL"):
        if kind is None:
            return refuse(cline)
        if stale:
            return refuse("stale evidence: the file is older than this row's START (not from this run)")
        if kind != verdict:
            return refuse("checker says %s, you said %s" % (kind, verdict))
        if verdict == "FAIL" and rs["fails"] >= 1:
            return escalate("second FAIL of the same row")
        if verdict == "FAIL":
            rs["fails"] += 1
        rs["final"] = verdict
        save_state(stp, st)
        write_csv(verdict, cline, "1", note)
        log("ACCEPTED", cline)
        print("pilot-mark: ACCEPTED %s %s (checker agrees). Take the next row." % (row, verdict)); return 0

    return escalate("operator verdict %s needs the coordinator (SETUP-FAIL/GATED/other)" % verdict if verdict != "ESCALATE" else "operator escalated")


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
