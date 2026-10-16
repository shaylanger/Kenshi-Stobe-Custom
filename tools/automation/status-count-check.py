#!/usr/bin/env python3
"""status-count-check.py: mechanical check of the numeric claims in an agent's status file against its ledger (read-only).
Why (Shay 2026-10-16, pilot 1): the Haiku operator's status said "13 rows: 2 PASS 4 FAIL 6 SETUP-FAIL 1 escalated" while its own ledger had
1 PASS and 13 escalation lines. A status line is the only thing the coordinator reads, so a wrong count must be flagged automatically.

  status-count-check.py <agent> [--runs DIR] [--pilot-dir DIR | --csv FILE [--events FILE]] [--repo DIR] [--no-asof] [--quiet]
  status-count-check.py --scan [--hours 3] [--runs DIR] [--repo DIR] [--quiet]     all recent status files that have a ledger
  status-count-check.py --selftest
Exit 0 = every checkable count claim matches (or there is nothing to check), 1 = at least one MISMATCH line, 2 = usage.
Works with Windows python and WSL python3 (paths are normalised; times are compared as naive local strings, never converted).

Claims parsed from the `task:`, `latest:` and `outputs:` lines of <runs>\\agents\\<agent>.status:
  "N PASS|FAIL|SETUP-FAIL|GATED|rows|escalated|refused|marked|accepted"   (N = 1..3 digits, not part of a path/id/fraction)
Ledger (auto-detected, first hit wins):
  1. PILOT ledger: <runs>\\pilot\\**\\verdicts.csv whose events.log has `agent=<agent>` lines (pilot-mark.py format). Entries: accepted PASS/FAIL (checker agreed),
     escalations (note starts with ESCALATE, this includes SETUP-FAIL / GATED the operator may not close), refusals (note starts with REFUSED).
     Counted over the SHARED ledger (successors continue it) and over the lines this agent wrote (events.log attribution); a claim matches if it equals either.
  2. REAL lanes: marks of the agent in the TESTS file = commits `imm26 <agent>: <row> <STATUS> ...` (status-mark.sh) in git log of testing/NPC_IMMERSION_26_TESTS.md.
Count definitions (a claim matches if it is in the candidate set; the candidates are printed on a mismatch):
  PASS/FAIL     distinct rows whose latest accepted/marked verdict is that word; real lanes also: number of such mark commits
  SETUP-FAIL    distinct rows the operator reported SETUP-FAIL (pilot) / latest mark SETUP-FAIL (real); GATED likewise
  escalated     pilot: number of ESCALATE lines (all, incl. 00-* questions) or distinct non-00 rows escalated    (real lanes: unverifiable)
  refused       pilot: number of REFUSED lines
  rows          distinct non-00 rows with at least one ledger line (real: distinct rows marked)
  marked/accepted  pilot: distinct accepted rows, or all non-00 ledger lines; real: distinct rows marked, or number of mark commits
As-of: while the agent is RUNNING its status is a snapshot; ledger entries written after (status minute + 59 s + 120 s) are ignored (--no-asof turns that off).
"""
import sys, os, re, csv, glob, json, subprocess, tempfile, shutil, datetime

CLAIM_RE = re.compile(r"(?<![\w/.\-])(\d{1,3})\s+(SETUP-FAIL|PASS|FAIL|GATED|rows?|escalat\w*|marked|accepted|refus\w*)(?![\w\-])", re.I)
KINDS = ("PASS", "FAIL", "SETUP-FAIL", "GATED", "ROWS", "ESCALATED", "REFUSED", "MARKED", "ACCEPTED")
TESTS_REL = "testing/NPC_IMMERSION_26_TESTS.md"
SLACK_S = 120


def runs_dir(a=None):
    if a:
        return a
    d = os.environ.get("KAH_RUNS_DIR")
    if d:
        return d
    for c in ("/mnt/c/KenshiTestRuns", "/c/KenshiTestRuns", "C:\\KenshiTestRuns"):
        if os.path.isdir(c):
            return c
    return "C:\\KenshiTestRuns"


def repo_dir(a=None):
    if a:
        return a
    d = os.environ.get("KAH_REPO")
    if d:
        return d
    for c in ("/mnt/c/KenshiModding", "/c/KenshiModding", "C:\\KenshiModding"):
        if os.path.isdir(c):
            return c
    return "C:\\KenshiModding"


def norm_kind(w):
    w = w.upper()
    if w.startswith("ROW"):
        return "ROWS"
    if w.startswith("ESCALAT"):
        return "ESCALATED"
    if w.startswith("REFUS"):
        return "REFUSED"
    return w


def read_status(path):
    """(state, naive 'YYYY-MM-DD HH:MM' or '', {source: text}) from a status file."""
    txt = open(path, encoding="utf-8-sig", errors="replace").read().replace("\r", "")
    lines = txt.split("\n")
    head = lines[0] if lines else ""
    parts = [p.strip() for p in head.split("|")]
    state = parts[1] if len(parts) > 1 else ""
    stamp = parts[2] if len(parts) > 2 else ""
    src = {}
    for ln in lines[1:]:
        m = re.match(r"^(task|latest|outputs):\s*(.*)$", ln)
        if m:
            src[m.group(1)] = m.group(2)
    return state, stamp, src


def claims_of(src):
    out = []
    for key in ("task", "latest", "outputs"):
        for m in CLAIM_RE.finditer(src.get(key, "")):
            out.append((key, int(m.group(1)), norm_kind(m.group(2)), m.group(0)))
    return out


def cutoff_of(stamp):
    """Naive local ISO cutoff string for entries: status minute + 59 s + slack, or '' (no limit)."""
    try:
        t = datetime.datetime.strptime(stamp[:16], "%Y-%m-%d %H:%M")
    except ValueError:
        return ""
    return (t + datetime.timedelta(seconds=59 + SLACK_S)).strftime("%Y-%m-%dT%H:%M:%S")


# ---------------------------------------------------------------- ledgers
def is00(row):
    return row.startswith("00-")


def pilot_entries(csvp, evp, agent):
    """[{row, t, op, agree, note, mine}] from verdicts.csv; mine = events.log attributes the line to `agent`."""
    ev = {}
    if evp and os.path.isfile(evp):
        for ln in open(evp, encoding="utf-8", errors="replace"):
            m = re.match(r"^(\S+) agent=(\S+) lane=\S+ row=(\S+) verdict=\S+ (ACCEPTED|ESCALATE|REFUSED):", ln)
            if m:
                ev[(m.group(3), m.group(1))] = m.group(2)
    out = []
    for r in csv.DictReader(open(csvp, encoding="utf-8-sig", errors="replace", newline="")):
        e = {"row": r["row"], "t": r["end"], "op": (r["operator_verdict"] or "").upper(), "agree": r["agree"], "note": r["notes"] or ""}
        e["mine"] = ev.get((e["row"], e["t"])) == agent
        out.append(e)
    return out


def pilot_counts(ent):
    pr = [e for e in ent if not is00(e["row"])]
    acc = {}
    for e in pr:
        if e["agree"] == "1" and e["op"] in ("PASS", "FAIL") and not e["note"].startswith("ESCALATE"):
            acc[e["row"]] = e["op"]
    esc_lines = [e for e in ent if e["note"].startswith("ESCALATE")]
    last_op = {}
    for e in pr:
        if e["note"].startswith("ESCALATE") and e["op"] in ("SETUP-FAIL", "GATED"):
            last_op.setdefault(e["op"], set()).add(e["row"])
    return {
        "PASS": {sum(1 for v in acc.values() if v == "PASS")},
        "FAIL": {sum(1 for v in acc.values() if v == "FAIL")},
        "SETUP-FAIL": {len(last_op.get("SETUP-FAIL", ()))},
        "GATED": {len(last_op.get("GATED", ()))},
        "ESCALATED": {len(esc_lines), len({e["row"] for e in esc_lines if not is00(e["row"])})},
        "REFUSED": {sum(1 for e in ent if e["note"].startswith("REFUSED"))},
        "ROWS": {len({e["row"] for e in pr})},
        "MARKED": {len(acc), len(pr)},
        "ACCEPTED": {len(acc)},
    }


def merge_counts(cs):
    out = {}
    for c in cs:
        for k, v in c.items():
            out.setdefault(k, set()).update(v)
    return out


def git_entries(repo, agent):
    cmd = ["git", "-c", "safe.directory=*", "-C", repo, "log", "--format=%ci%x09%s", "-E", "--grep=^imm26 %s: " % re.escape(agent), "--", TESTS_REL]
    try:
        p = subprocess.run(cmd, capture_output=True, text=True, errors="replace", timeout=60)
    except Exception:
        return []
    out = []
    for ln in p.stdout.splitlines():
        t, _, subj = ln.partition("\t")
        m = re.match(r"^imm26 %s: (\d{2}-[a-z]{1,3}) (PASS|FAIL|SETUP-FAIL|GATED|UNRUN)\b" % re.escape(agent), subj)
        if m:
            out.append({"row": m.group(1), "t": t[:10] + "T" + t[11:19], "op": m.group(2)})
    out.sort(key=lambda e: e["t"])
    return out


def git_counts(ent):
    latest = {}
    for e in ent:
        latest[e["row"]] = e["op"]
    c = {}
    for k in ("PASS", "FAIL", "SETUP-FAIL", "GATED"):
        c[k] = {sum(1 for v in latest.values() if v == k), sum(1 for e in ent if e["op"] == k)}
    c["ROWS"] = {len(latest)}
    c["MARKED"] = {len(latest), len(ent)}
    c["ACCEPTED"] = {sum(1 for v in latest.values() if v in ("PASS", "FAIL"))}
    return c    # escalated / refused: no ledger -> unverifiable


def find_pilot(runs, agent, csv_arg=None, ev_arg=None):
    if csv_arg:
        return csv_arg, ev_arg or os.path.join(os.path.dirname(csv_arg), "events.log")
    for p in sorted(glob.glob(os.path.join(runs, "pilot", "*", "verdicts.csv")) + glob.glob(os.path.join(runs, "pilot", "*", "*", "verdicts.csv"))):
        evp = os.path.join(os.path.dirname(p), "events.log")
        if os.path.isfile(evp) and re.search(r"(?m)\bagent=%s\b" % re.escape(agent), open(evp, encoding="utf-8", errors="replace").read()):
            return p, evp
    return None, None


# ---------------------------------------------------------------- check
def check(agent, runs, repo, csv_arg=None, ev_arg=None, asof=True, status_path=None):
    """(lines, n_ok, n_bad, n_unv). Lines are printed by the caller."""
    sp = status_path or os.path.join(runs, "agents", agent + ".status")
    if not os.path.isfile(sp):
        return ["NO-STATUS %s: %s not found" % (agent, sp)], 0, 0, 0
    state, stamp, src = read_status(sp)
    claims = claims_of(src)
    if not claims:
        return ["OK %s: no count claims in task/latest/outputs (state %s)" % (agent, state)], 0, 0, 0
    cut = cutoff_of(stamp) if (asof and state == "RUNNING") else ""
    csvp, evp = find_pilot(runs, agent, csv_arg, ev_arg)
    if csvp and os.path.isfile(csvp):
        ent = pilot_entries(csvp, evp, agent)
        if cut:
            ent = [e for e in ent if not e["t"] or e["t"] <= cut]
        cand = merge_counts([pilot_counts(ent), pilot_counts([e for e in ent if e["mine"]])] if any(e["mine"] for e in ent) else [pilot_counts(ent)])
        what = "pilot ledger %s (%d lines%s)" % (csvp, len(ent), ", as of " + cut if cut else "")
    else:
        ent = git_entries(repo, agent)
        if cut:
            ent = [e for e in ent if e["t"] <= cut]
        if not ent:
            return ["UNVERIFIABLE %s: no pilot ledger and no TESTS marks `imm26 %s: <row> <STATUS>` found; claims %s" % (agent, agent, ", ".join('"%s"' % c[3] for c in claims))], 0, 0, len(claims)
        cand = git_counts(ent)
        what = "TESTS marks in git (%d commits%s)" % (len(ent), ", as of " + cut if cut else "")
    lines, ok, bad, unv = [], 0, 0, 0
    for key, n, kind, text in claims:
        c = cand.get(kind)
        if c is None:
            unv += 1
            lines.append("UNVERIFIABLE %s %s: \"%s\" has no ledger count in %s" % (agent, key, text, what))
        elif n in c:
            ok += 1
            lines.append("OK %s %s: \"%s\" matches (%s)" % (agent, key, text, what))
        else:
            bad += 1
            lines.append("MISMATCH %s %s: claims \"%s\" but ledger has %s %s [%s]" % (agent, key, text, "/".join(str(x) for x in sorted(c)), kind, what))
    return lines, ok, bad, unv


def main(a):
    if "--selftest" in a:
        return selftest()
    if len(a) >= 3 and a[0] == "--make-fixture":   # --make-fixture <runs-dir> GOOD|BAD : pilot-1 shaped ledger + status (used by event-wait-statuscount-selftest.sh)
        make_fixture(a[1])
        write_status(a[1], "13 rows: 1 PASS 4 FAIL 6 SETUP-FAIL 13 escalated" if a[2].upper() == "GOOD" else "13 rows: 2 PASS 4 FAIL 6 SETUP-FAIL 1 escalated")
        return 0
    pos, opts, i = [], {}, 0
    while i < len(a):
        if a[i] in ("--runs", "--repo", "--pilot-dir", "--csv", "--events", "--hours") and i + 1 < len(a):
            opts[a[i]] = a[i + 1]; i += 2
        elif a[i] in ("--scan", "--no-asof", "--quiet"):
            opts[a[i]] = True; i += 1
        else:
            pos.append(a[i]); i += 1
    runs, repo = runs_dir(opts.get("--runs")), repo_dir(opts.get("--repo"))
    csv_arg = opts.get("--csv")
    if opts.get("--pilot-dir"):
        csv_arg = os.path.join(opts["--pilot-dir"], "verdicts.csv")
    quiet = opts.get("--quiet")
    if opts.get("--scan"):
        import time
        hrs = float(opts.get("--hours", 3))
        bad_total = 0
        for sp in sorted(glob.glob(os.path.join(runs, "agents", "*.status"))):
            if time.time() - os.path.getmtime(sp) > hrs * 3600:
                continue
            ag = os.path.basename(sp)[:-7]
            lines, ok, bad, unv = check(ag, runs, repo, None, None, not opts.get("--no-asof"))
            if bad:
                bad_total += bad
                for l in lines:
                    if l.startswith("MISMATCH"):
                        print(l)
            elif not quiet and (ok or unv):
                print("STATUS-COUNT %s OK (%d ok, %d unverifiable)" % (ag, ok, unv))
        if not bad_total and not quiet:
            print("STATUS-COUNT scan: no mismatch")
        return 1 if bad_total else 0
    if not pos:
        print(__doc__); return 2
    lines, ok, bad, unv = check(pos[0], runs, repo, csv_arg, opts.get("--events"), not opts.get("--no-asof"))
    for l in lines:
        if not quiet or l.startswith("MISMATCH"):
            print(l)
    print("STATUS-COUNT %s %s (%d ok, %d mismatch, %d unverifiable)" % (pos[0], "MISMATCH" if bad else "OK", ok, bad, unv))
    return 1 if bad else 0


# ---------------------------------------------------------------- selftest
def make_fixture(runs):
    """Pilot-1-shaped fixture: <runs>/pilot/haiku-i4/{verdicts.csv,events.log} (19 lines: 13 rows, 1 PASS, 4 FAIL, 6 SETUP-FAIL, 13 ESCALATE lines, 1 REFUSED) + put_status()."""
    pd = os.path.join(runs, "pilot", "haiku-i4")
    os.makedirs(pd, exist_ok=True); os.makedirs(os.path.join(runs, "agents"), exist_ok=True)
    hdr = ["row", "lane", "model", "start", "end", "wall_s", "tokens", "cost", "operator_verdict", "checker_result", "agree", "false_claims_n", "notes"]
    # first-pilot ledger shape: 5 questions (00-ask), 02-cx esc, 02-ax refused+esc, 16-bx FAIL, 08-d FAIL, 23-b PASS, 22-b FAIL, 20-d FAIL, 6 SETUP-FAIL escalations
    rows = [("00-ask", "ESCALATE", "-", "n/a", "ESCALATE: q"), ("00-ask", "ESCALATE", "-", "n/a", "ESCALATE: q"), ("00-ask", "ESCALATE", "-", "n/a", "ESCALATE: q"),
            ("02-cx", "ESCALATE", "x", "n/a", "ESCALATE: operator escalated"), ("00-ask", "ESCALATE", "-", "n/a", "ESCALATE: q"), ("00-ask", "ESCALATE", "-", "n/a", "ESCALATE: q"),
            ("02-ax", "PASS", "RESULT 02-ax PASS", "0", "REFUSED wrong-verdict #1: stale"), ("16-bx", "FAIL", "RESULT 16-bx FAIL", "1", "RESULT 16-bx FAIL: O2"),
            ("02-ax", "ESCALATE", "RESULT 02-ax PASS", "n/a", "ESCALATE: operator escalated"), ("15-bx", "SETUP-FAIL", "RESULT 15-bx SETUP-FAIL", "1", "ESCALATE: operator verdict SETUP-FAIL"),
            ("08-d", "FAIL", "RESULT 08-d FAIL", "1", "RESULT 08-d FAIL"), ("23-b", "PASS", "RESULT 23-b PASS", "1", "RESULT 23-b PASS"),
            ("22-b", "FAIL", "RESULT 22-b FAIL", "1", "RESULT 22-b FAIL"), ("20-a", "SETUP-FAIL", "R", "1", "ESCALATE: operator verdict SETUP-FAIL"),
            ("20-d", "FAIL", "RESULT 20-d FAIL", "1", "RESULT 20-d FAIL"), ("23-e", "SETUP-FAIL", "R", "1", "ESCALATE: operator verdict SETUP-FAIL"),
            ("24-c", "SETUP-FAIL", "R", "1", "ESCALATE: operator verdict SETUP-FAIL"), ("05-cx", "SETUP-FAIL", "R", "1", "ESCALATE: operator verdict SETUP-FAIL"),
            ("12-d", "SETUP-FAIL", "R", "1", "ESCALATE: operator verdict SETUP-FAIL")]
    with open(os.path.join(pd, "verdicts.csv"), "w", newline="", encoding="utf-8") as f, open(os.path.join(pd, "events.log"), "w") as ev:
        w = csv.writer(f, lineterminator="\n"); w.writerow(hdr)
        for k, (row, op, chk_, agree, note) in enumerate(rows):
            ts = "2026-10-16T13:%02d:%02d" % (k, 10)
            w.writerow([row, "5090-i4", "haiku", "", ts, "", "", "", op, chk_, agree, "", note])
            kind = "REFUSED" if note.startswith("REFUSED") else ("ESCALATE" if note.startswith("ESCALATE") else "ACCEPTED")
            ev.write("%s agent=imm26-hk2 lane=5090-i4 row=%s verdict=%s %s: x\n" % (ts, row, op, kind))


def write_status(runs, latest, state="DONE", stamp="2026-10-16 14:08"):
    txt = "imm26-hk2 | %s | %s" % (state, stamp) + chr(10) + "task: 5090-i4 pilot operator" + chr(10) + "latest: %s" % latest + chr(10) + "outputs: C:/KenshiTestRuns/pilot/haiku-i4/out" + chr(10) + "next: none" + chr(10)
    open(os.path.join(runs, "agents", "imm26-hk2.status"), "w", encoding="utf-8").write(txt)


def selftest():
    t = tempfile.mkdtemp(prefix="scc-")
    fails = []

    def chk(name, cond):
        print(("ok   " if cond else "FAIL ") + name)
        if not cond:
            fails.append(name)
    try:
        runs = os.path.join(t, "runs")
        make_fixture(runs)
        put_status = lambda latest, state="DONE", stamp="2026-10-16 14:08": write_status(runs, latest, state, stamp)
        # FALSE case = the real first-pilot claim
        put_status("lane complete: rows-i4.txt list exhausted (13 rows: 2 PASS 4 FAIL 6 SETUP-FAIL 1 escalated); game left running")
        lines, ok, bad, unv = check("imm26-hk2", runs, t)
        chk("false case: '2 PASS' flagged (ledger 1)", any(l.startswith("MISMATCH") and '"2 PASS"' in l and "ledger has 1 PASS" in l for l in lines))
        chk("false case: '1 escalated' flagged (ledger 13)", any(l.startswith("MISMATCH") and '"1 escalated"' in l and "13" in l for l in lines))
        chk("false case: 13 rows, 4 FAIL, 6 SETUP-FAIL pass", ok == 3 and bad == 2)
        rc = main(["imm26-hk2", "--runs", runs, "--repo", t, "--quiet"])
        chk("false case: exit code 1", rc == 1)
        # TRUE case: corrected counts
        put_status("lane complete: 13 rows: 1 PASS 4 FAIL 6 SETUP-FAIL 13 escalated 1 refused")
        lines, ok, bad, unv = check("imm26-hk2", runs, t)
        chk("true case: all 6 claims match, no mismatch", ok == 6 and bad == 0 and unv == 0)
        chk("true case: exit code 0", main(["imm26-hk2", "--runs", runs, "--repo", t, "--quiet"]) == 0)
        # as-of: RUNNING snapshot at 13:05 claims 1 FAIL (16-bx only, FAIL lines later are ignored); the same text as DONE is a mismatch
        put_status("rows so far: 1 FAIL", state="RUNNING", stamp="2026-10-16 13:07")
        lines, ok, bad, unv = check("imm26-hk2", runs, t)
        chk("as-of: RUNNING snapshot before later ledger lines is not a mismatch", bad == 0 and ok == 1)
        put_status("rows so far: 1 FAIL", state="DONE", stamp="2026-10-16 14:08")
        chk("as-of: same claim in a DONE status IS a mismatch (final ledger has 4 FAIL)", check("imm26-hk2", runs, t)[2] == 1)
        # no claims / no ledger
        put_status("started, reading brief")
        chk("no count claims = OK", check("imm26-hk2", runs, t)[2:] == (0, 0))
        open(os.path.join(runs, "agents", "other-agent.status"), "w").write("other-agent | DONE | 2026-10-16 14:08\ntask: t\nlatest: 3 PASS\noutputs: o\nnext: n\n")
        l2 = check("other-agent", runs, t)
        chk("no ledger = UNVERIFIABLE, not a mismatch", l2[2] == 0 and l2[3] == 1 and l2[0][0].startswith("UNVERIFIABLE"))
        # claim parser: paths/ids/fractions are not claims
        chk("parser ignores ids, paths and fractions", claims_of({"latest": "sha 7A5AF9EA, 10/13 rows, C:/x/12 rows, rc=0"}) == [])
        chk("parser reads a plain count", claims_of({"latest": "12 rows done"}) == [("latest", 12, "ROWS", "12 rows")])
        chk("parser: SETUP-FAIL is one claim (not FAIL)", [c[2] for c in claims_of({"latest": "6 SETUP-FAIL 4 FAIL"})] == ["SETUP-FAIL", "FAIL"])
        # real-lane git ledger
        if shutil.which("git"):
            repo = os.path.join(t, "repo"); os.makedirs(os.path.join(repo, "testing"))
            def g(*x):
                return subprocess.run(["git", "-C", repo, "-c", "user.email=a@b", "-c", "user.name=t"] + list(x), capture_output=True, text=True)
            g("init", "-q")
            for k, (row, st) in enumerate([("01-a", "PASS"), ("01-b", "FAIL"), ("01-b", "PASS"), ("01-c", "SETUP-FAIL")]):
                open(os.path.join(repo, TESTS_REL), "a").write("%s %s\n" % (row, st))
                g("add", "."); g("commit", "-q", "-m", "imm26 opx: %s %s evidence" % (row, st))
            open(os.path.join(runs, "agents", "opx.status"), "w").write("opx | DONE | 2026-10-16 14:08\ntask: t\nlatest: 3 rows marked: 2 PASS 1 SETUP-FAIL\noutputs: o\nnext: n\n")
            lines, ok, bad, unv = check("opx", runs, repo)
            chk("git ledger true case (3 rows, 2 PASS, 1 SETUP-FAIL)", bad == 0 and ok >= 3)
            open(os.path.join(runs, "agents", "opx.status"), "w").write("opx | DONE | 2026-10-16 14:08\ntask: t\nlatest: 5 rows marked: 4 PASS\noutputs: o\nnext: n\n")
            lines, ok, bad, unv = check("opx", runs, repo)
            chk("git ledger false case (5 rows, 4 PASS)", bad >= 2)
        else:
            print("skip git ledger tests (no git)")
    finally:
        shutil.rmtree(t, ignore_errors=True)
    print("SELFTEST FAIL (%d)" % len(fails) if fails else "SELFTEST OK")
    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
