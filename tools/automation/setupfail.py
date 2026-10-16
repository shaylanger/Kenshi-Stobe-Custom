#!/usr/bin/env python3
"""setupfail.py: SETUP-FAIL unblock tickets (Shay 2026-10-15: a row marked SETUP-FAIL = "row could not run"; someone must find out what is
needed to run it and get it done). Core for setupfail.ps1 (CLI), mark-row.py (md marks) and attempts.py (go-row verdicts).

Ticket  <runs>/setupfail/<row>.json   (row without the IMM- prefix, e.g. 08-d)
  {row, lane, marked_at, reason, needs, owner, state, plan_path, last_update, notes[], reopened, closed_at, closed_by}
  needs : recipe | server-fix | native | design | fixture | unknown
  state : open | planned | building | ready | closed
Rules
  * a SETUP-FAIL mark creates the ticket (or updates reason/lane; owner+state kept; a `ready` ticket that SETUP-FAILs again goes back to open;
    a closed ticket is reopened with owner '-'). New or reopened ticket -> inbox note <runs>/inbox/coordinator/<ts>-setupfail-<row>.msg
    ("SETUP-FAIL <row> needs unblock plan: <needs>") which the coordinator's waker reports.
  * the text of a SETUP-FAIL md mark must contain `needs: recipe|server-fix|native|design|fixture` and a few words saying what exactly
    (check_mark). PREFLIGHT-FAIL (llm/lane down: the row never ran) is exempt and never makes a ticket.
  * a ticket closes when its row is next marked PASS, FAIL or GATED (it ran / is not a setup problem).
Env: KAH_RUNS_DIR (default C:\\KenshiTestRuns, /mnt/c/KenshiTestRuns on posix), KAH_TESTS_MD (the imm26 tests file).
CLI: setupfail.py list [--all] [--lane L] | brief [N] | assign ROW AGENT [PLAN] | state ROW STATE [NOTE] | close ROW [NOTE]
     | open ROW LANE REASON | sync [--notify] | backfill [--force] | check STATUS NOTE
"""
import sys, os, io, re, json, time, datetime

NEEDS = ("recipe", "server-fix", "native", "design", "fixture")
ALLNEEDS = NEEDS + ("unknown",)
STATES = ("open", "planned", "building", "ready", "closed")
REPO = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
NEEDS_RE = re.compile(r"\bneeds?\s*[:=]\s*(recipe|server-fix|native|design|fixture)\b", re.I)


def runs_dir():
    d = os.environ.get("KAH_RUNS_DIR")
    if d:
        return d
    return r"C:\KenshiTestRuns" if os.name == "nt" else "/mnt/c/KenshiTestRuns"


def tests_md():
    return os.environ.get("KAH_TESTS_MD") or os.path.join(REPO, "testing", "NPC_IMMERSION_26_TESTS.md")


def now():
    return time.strftime("%Y-%m-%dT%H:%M:%S")


def norm_row(r):
    r = str(r).strip()
    return r[4:] if r.upper().startswith("IMM-") else r


def one(s, n=600):
    return " ".join(str(s).split())[:n]


def tdir(runs=None):
    return os.path.join(runs or runs_dir(), "setupfail")


def tpath(row, runs=None):
    return os.path.join(tdir(runs), norm_row(row) + ".json")


def load(row, runs=None):
    try:
        with io.open(tpath(row, runs), encoding="utf-8-sig") as f:
            return json.load(f)
    except Exception:
        return None


def save(t, runs=None):
    os.makedirs(tdir(runs), exist_ok=True)
    p = tpath(t["row"], runs)
    tmp = p + ".tmp"
    with io.open(tmp, "w", encoding="utf-8") as f:
        json.dump(t, f, indent=1)
    os.replace(tmp, p)


def all_tickets(runs=None):
    out = []
    d = tdir(runs)
    if os.path.isdir(d):
        for n in sorted(os.listdir(d)):
            if n.endswith(".json"):
                try:
                    with io.open(os.path.join(d, n), encoding="utf-8-sig") as f:
                        out.append(json.load(f))
                except Exception:
                    pass
    return out


# ---------------------------------------------------------------------------------------------------- text rules
def is_preflight(text):
    return bool(re.match(r"\s*(SETUP-FAIL\s+)?PREFLIGHT-FAIL", str(text), re.I))


def needs_of(text):
    m = NEEDS_RE.search(str(text))
    return m.group(1).lower() if m else None


def infer_needs(text):
    t = str(text)
    n = needs_of(t)
    if n:
        return n
    low = t.lower()
    if "not ported" in low:
        return "recipe"
    if re.search(r"\bNC\d+\b|\bdll\b|native|c\+\+|verdict\(\)|campzone", t, re.I):
        return "native"
    if re.search(r"server|\.php|lib/|prompt|social_followup", low):
        return "server-fix"
    if re.search(r"fixture|\bsave\b|contract|no .* victim", low):
        return "fixture"
    if re.search(r"design|decision|policy", low):
        return "design"
    if re.search(r"recipe|harness|row script|needs an? ", low):
        return "recipe"
    return "unknown"


def check_mark(status, note):
    """Gate for md marks. Returns (ok, message). Only SETUP-FAIL is gated; PREFLIGHT-FAIL text is exempt."""
    if str(status).strip().upper() != "SETUP-FAIL" or is_preflight(note):
        return True, ""
    n = needs_of(note)
    if not n:
        return False, ("REFUSED: a SETUP-FAIL mark must say what is needed to run the row: put 'needs: recipe|server-fix|native|design|fixture' "
                       "and WHAT exactly (the missing step/fixture/code) in the text; never just retry. (PREFLIGHT-FAIL llm/lane-down text is exempt.)")
    rest = NEEDS_RE.sub("", str(note))
    if len(one(rest)) < 15:
        return False, "REFUSED: 'needs: %s' is not enough; say what exactly is missing (a few words: step, fixture, file/function)." % n
    return True, ""


# ---------------------------------------------------------------------------------------------------- ticket ops
def notify(t, runs=None, why="needs unblock plan"):
    d = os.path.join(runs or runs_dir(), "inbox", "coordinator")
    os.makedirs(d, exist_ok=True)
    name = "%s-setupfail-%s.msg" % (time.strftime("%Y%m%d-%H%M%S"), t["row"])
    txt = "SETUP-FAIL %s %s: %s\nlane=%s reason: %s\nlist: powershell -File tools/automation/setupfail.ps1 list | assign: setupfail.ps1 assign %s <agent> [plan_path]\n" % (
        t["row"], why, t["needs"], t.get("lane", "-"), one(t.get("reason", ""), 300), t["row"])
    with io.open(os.path.join(d, name), "w", encoding="utf-8", newline="\n") as f:
        f.write(txt)
    return name


def open_ticket(row, lane, reason, runs=None, send=True):
    """SETUP-FAIL mark. Returns the ticket, or None when exempt (PREFLIGHT-FAIL)."""
    row = norm_row(row)
    if is_preflight(reason):
        return None
    t = load(row, runs)
    explicit = needs_of(reason)
    new = t is None or t.get("state") == "closed"
    if t is None:
        t = {"row": row, "lane": lane or "-", "marked_at": now(), "reason": one(reason), "needs": explicit or infer_needs(reason), "owner": "-",
             "state": "open", "plan_path": "", "last_update": now(), "notes": [], "reopened": 0}
    else:
        if t.get("state") == "closed":
            t.update({"marked_at": now(), "owner": "-", "state": "open", "plan_path": "", "reopened": int(t.get("reopened", 0)) + 1})
            t.pop("closed_at", None)
            t.pop("closed_by", None)
            t["needs"] = explicit or infer_needs(reason)
        elif explicit:
            t["needs"] = explicit
        elif t.get("needs") == "unknown":
            t["needs"] = infer_needs(reason)
        if t.get("state") == "ready":
            t["state"] = "open"
            t.setdefault("notes", []).append("%s ready ticket SETUP-FAILed again" % now())
        if lane and lane != "-":
            t["lane"] = lane
        t["reason"] = one(reason)
        t["last_update"] = now()
    save(t, runs)
    if new and send:
        try:
            notify(t, runs)
        except Exception:
            pass
    return t


def close_ticket(row, runs=None, by="ran", note=""):
    t = load(row, runs)
    if not t or t.get("state") == "closed":
        return None
    t["state"] = "closed"
    t["closed_at"] = now()
    t["closed_by"] = by
    t["last_update"] = now()
    if note:
        t.setdefault("notes", []).append("%s closed: %s" % (now(), one(note, 200)))
    save(t, runs)
    return t


def on_verdict(row, lane, verdict, cause, runs=None, send=True):
    """Hook for a recorded/marked verdict (mark-row.py, attempts.py)."""
    v = str(verdict).strip().upper()
    if v == "SETUP-FAIL":
        return open_ticket(row, lane, cause, runs, send)
    if v in ("PASS", "FAIL", "GATED"):
        return close_ticket(row, runs, by=v)
    return None


def assign(row, agent, plan="", runs=None):
    t = load(row, runs)
    if not t:
        raise SystemExit("no ticket for %s" % norm_row(row))
    t["owner"] = agent
    if plan:
        t["plan_path"] = plan
    if t["state"] == "open":
        t["state"] = "planned"
    t["last_update"] = now()
    save(t, runs)
    return t


def set_state(row, state, note="", runs=None):
    if state not in STATES:
        raise SystemExit("state must be one of %s" % "|".join(STATES))
    t = load(row, runs)
    if not t:
        raise SystemExit("no ticket for %s" % norm_row(row))
    t["state"] = state
    if state == "closed":
        t["closed_at"] = now()
        t["closed_by"] = "manual"
    if note:
        t.setdefault("notes", []).append("%s %s: %s" % (now(), state, one(note, 200)))
    t["last_update"] = now()
    save(t, runs)
    return t


# ---------------------------------------------------------------------------------------------------- listing
def age_str(iso):
    try:
        s = (datetime.datetime.now() - datetime.datetime.strptime(iso, "%Y-%m-%dT%H:%M:%S")).total_seconds()
    except Exception:
        return "?"
    m = int(max(s, 0) // 60)
    return "%dh%02dm" % (m // 60, m % 60) if m >= 60 else "%dm" % m


def age_min(iso):
    try:
        return (datetime.datetime.now() - datetime.datetime.strptime(iso, "%Y-%m-%dT%H:%M:%S")).total_seconds() / 60.0
    except Exception:
        return 1e9


def ordered(tickets):
    """open tickets: unowned first, then oldest first."""
    op = [t for t in tickets if t.get("state") != "closed"]
    return sorted(op, key=lambda t: (t.get("owner", "-") not in ("", "-"), t.get("marked_at", "")))


def line(t):
    own = t.get("owner", "-") or "-"
    s = "%s age=%s needs=%s owner=%s state=%s" % (t["row"], age_str(t.get("marked_at", "")), t.get("needs", "?"), own, t.get("state", "?"))
    if own == "-":
        s += " - unowned"
    return s


def lane_match(t, lane):
    a, b = str(t.get("lane", "")).lower(), lane.lower()
    return bool(a) and a != "-" and (b in a or a in b)


def cmd_list(args, runs=None):
    allf = "--all" in args
    lane = None
    if "--lane" in args:
        lane = args[args.index("--lane") + 1]
    ts = all_tickets(runs)
    if lane:
        ts = [t for t in ts if lane_match(t, lane)]
    show = sorted(ts, key=lambda t: (t.get("state") == "closed", t.get("owner", "-") not in ("", "-"), t.get("marked_at", ""))) if allf else ordered(ts)
    if not show:
        print("none")
    for t in show:
        print(line(t) + ("  [closed by %s]" % t.get("closed_by") if t.get("state") == "closed" else ""))


def cmd_brief(n=12, runs=None):
    try:
        sync(runs, send=False)
    except Exception:
        pass
    ts = ordered(all_tickets(runs))
    if not ts:
        return
    print("=== SETUP-FAIL TICKETS (%d open; %d unowned; setupfail.ps1 list/assign/state/close) ===" % (len(ts), sum(1 for t in ts if t.get("owner", "-") in ("", "-"))))
    for t in ts[:n]:
        print("  " + line(t))
    if len(ts) > n:
        print("  (+%d more: setupfail.ps1 list)" % (len(ts) - n))


# ---------------------------------------------------------------------------------------------------- md reconcile
def md_rows():
    """{row: (status, evidence)} from the imm26 tests file (cols: | id | setup | say | pass | fail | exp | status | evidence | date |)."""
    res = {}
    p = tests_md()
    if not os.path.isfile(p):
        return res
    for l in io.open(p, encoding="utf-8"):
        f = l.split("|")
        if len(f) >= 10 and f[1].strip().startswith("IMM-"):
            res[norm_row(f[1])] = (f[7].strip(), f[8].strip())
    return res


def lane_of(text):
    m = re.search(r"\b(5090|4080)\s+(i\d)\b", text)
    return "%s-%s" % (m.group(1), m.group(2)) if m else "-"


def sync(runs=None, send=False):
    """tickets <-> md: SETUP-FAIL row without an open ticket -> create; open ticket whose md row is PASS/FAIL/GATED -> close."""
    made, closed = [], []
    rows = md_rows()
    for row, (st, ev) in rows.items():
        t = load(row, runs)
        if st == "SETUP-FAIL" and (t is None or t.get("state") == "closed"):
            if open_ticket(row, lane_of(ev), ev, runs, send):
                made.append(row)
        elif st in ("PASS", "FAIL", "GATED") and t and t.get("state") != "closed" and age_min(t.get("last_update", "")) >= 30:
            # (a ticket a machine verdict touched < 30 min ago is not closed by a stale md status; mark-row.py/attempts.py close on the real mark)
            close_ticket(row, runs, by="md:" + st)
            closed.append(row)
    return made, closed


# 2026-10-15 snapshot of who is on what (Shay's order); applied only when a ticket is created (or --force).
SEED = {
    "22-a": ("native", "imm26-5090-i5-op7", "building", "", "NC10 installing (drop homeBuilding from animals-only roaming Verdict())"),
    "26-a": ("native", "imm26-5090-i5-op7", "building", "", "NC10 installing (same cause as 22-a)"),
    "26-b": ("native", "imm26-5090-i5-op7", "building", "", "needs an accepted Hunt (26-a), NC10 installing"),
    "26-c": ("native", "imm26-5090-i5-op7", "building", "", "needs an accepted Hunt (26-a), NC10 installing"),
    "10-b": ("recipe", "imm26-5090-i3-hard2b", "planned", "", "depends on the 10-a rerun by imm26-5090-i3-hard2b"),
    "18-a": ("fixture", "imm26-5090-i4-hard2b", "planned", "", "harness contract-bodyguard on 5090-i4"),
    "11-b": ("recipe", "imm26-5090-i3-hard2b", "planned", "", "weak plan"),
    "08-d": ("design", "imm26-inv-setupfail", "planned", "agents/out/imm26-inv-setupfail/latest.md", "investigating"),
    "13-c": ("recipe", "imm26-inv-setupfail", "planned", "agents/out/imm26-inv-setupfail/latest.md", "investigating"),
    "14-c": ("native", "imm26-inv-setupfail", "planned", "agents/out/imm26-inv-setupfail/latest.md", "investigating"),
    "20-a": ("recipe", "imm26-inv-setupfail", "planned", "agents/out/imm26-inv-setupfail/latest.md", "investigating"),
}


def backfill(runs=None, force=False):
    made = []
    for row, (st, ev) in sorted(md_rows().items()):
        if st != "SETUP-FAIL":
            continue
        t = load(row, runs)
        if t and t.get("state") != "closed" and not force:
            continue
        t = open_ticket(row, lane_of(ev), ev, runs, send=False)
        if t is None:
            continue
        seed = SEED.get(row)
        if seed:
            t["needs"], t["owner"], t["state"], t["plan_path"] = seed[0], seed[1], seed[2], seed[3]
            t.setdefault("notes", []).append("%s backfill: %s" % (now(), seed[4]))
            t["last_update"] = now()
            save(t, runs)
        made.append(line(t))
    return made


def main(a):
    if not a:
        print(__doc__)
        return 2
    c, rest = a[0], a[1:]
    if c == "list":
        cmd_list(rest)
    elif c == "brief":
        cmd_brief(int(rest[0]) if rest else 12)
    elif c == "assign" and len(rest) >= 2:
        print(line(assign(rest[0], rest[1], rest[2] if len(rest) > 2 else "")))
    elif c == "state" and len(rest) >= 2:
        print(line(set_state(rest[0], rest[1], " ".join(rest[2:]))))
    elif c == "close" and rest:
        t = close_ticket(rest[0], by="manual", note=" ".join(rest[1:]))
        print("closed %s" % norm_row(rest[0]) if t else "no open ticket for %s" % norm_row(rest[0]))
    elif c == "open" and len(rest) >= 3:
        t = open_ticket(rest[0], rest[1], " ".join(rest[2:]))
        print(line(t) if t else "exempt (PREFLIGHT-FAIL): no ticket")
    elif c == "sync":
        made, closed = sync(send="--notify" in rest)
        print("sync: created %s closed %s" % (",".join(made) or "-", ",".join(closed) or "-"))
    elif c == "backfill":
        for l in backfill(force="--force" in rest):
            print("backfilled " + l)
        print("backfill done")
    elif c == "check" and len(rest) >= 2:
        ok, msg = check_mark(rest[0], " ".join(rest[1:]))
        print("OK" if ok else msg)
        return 0 if ok else 2
    else:
        print(__doc__)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
