"""rowgate.py: ROW REWORK GATE (imm26 credit-review cut #1, Shay 2026-10-16). Docs: docs/ROW_REWORK_GATE.md.

Why: on 24 rows with 2+ agents the later agents cost $105.75 (25% of the day). The cost is re-reading and re-diagnosis, so a 2nd+
agent for a row must be handed the previous agent's report, say what is different, and replay the REAL lane evidence offline.

Ledger  <runs>/rowgate/<row>.json  (row without IMM- prefix, e.g. 23-a, 13-c-neg)
  {row, state open|closed, round, attempts:[{n, name, role, case, desc, key, state, started, ended, report, evidence, different,
   outcome, cost, agentId, skipped, round}], rounds:[closed history], ticketEvidence, costNote}
Roles: fixer | recipe (case patch/generate), investigator (investigate/debug/escalate)  = GATED (count as attempts)
       operator (description says "operator" or name op<N>), reader (read/check/parse), bench/grade = never gated (operators are recorded only).

Subcommands (python -I rowgate.py ...): guard (PreToolUse Agent, stdin JSON, exit 2 = deny), post (PostToolUse Agent, stdin JSON),
status [row], list, add, done, close, cost, seed, rows <text>.   Env (tests): ROWGATE_RUNS, ROWGATE_DIR, ROWGATE_AGENTS, ROWGATE_NOW, ROWGATE_MAX.
"""
import hashlib
import json
import os
import re
import sys
import time
from datetime import datetime, timedelta

RUNS = os.environ.get("ROWGATE_RUNS") or r"C:\KenshiTestRuns"
GATE = os.environ.get("ROWGATE_DIR") or os.path.join(RUNS, "rowgate")
AGENTS = os.environ.get("ROWGATE_AGENTS") or os.path.join(RUNS, "agents")
SETUPFAIL = os.path.join(RUNS, "setupfail")
MAX_ATTEMPTS = int(os.environ.get("ROWGATE_MAX") or 3)   # 4th gated agent for a row needs ESCALATE:
OPEN_TTL_MIN = 45          # a RUNNING status older than this (or an agent with no status for this long) is not "open" (same 45 min as the Stop hook)
DEDUPE_MIN = 15            # same case+description again within this window = a retry of the same call (e.g. the router denied it), not a new attempt
GATED_CASES = {"patch": "fixer", "generate": "fixer", "investigate": "investigator", "debug": "investigator", "escalate": "investigator"}
EXEMPT_CASES = {"read", "check", "parse", "grade", "bench"}
# Row ids: two digits, one letter, optional x (a..g, ax, bx, cx, dx ...), optional -neg.  "24-bit", "30-min", "2026-10-16", "4080-i3" do not match.
ROW_RE = re.compile(r"(?<![\w.])(\d{2}-[a-z]x?(?:-neg)?)(?![\w])", re.I)
MAX_ROWS = 4               # more rows than this in one call = a sweep, not a rework: not gated (logged)
SKIP_RE = re.compile(r"\[rowgate:skip\s+([^\]]*?)\]", re.I)
UTF8 = "utf-8"


def now():
    v = os.environ.get("ROWGATE_NOW")
    return datetime.strptime(v, "%Y-%m-%d %H:%M:%S") if v else datetime.now().replace(microsecond=0)


def ts(d=None):
    return (d or now()).strftime("%Y-%m-%d %H:%M:%S")


def pts(s):
    try:
        return datetime.strptime(s, "%Y-%m-%d %H:%M:%S")
    except Exception:
        return None


def norm_row(r):
    return re.sub(r"^imm-", "", r.strip().lower())


def find_rows(text):
    seen = []
    for m in ROW_RE.finditer(text or ""):
        r = norm_row(m.group(1))
        if r not in seen:
            seen.append(r)
    return seen


def lpath(row):
    return os.path.join(GATE, row + ".json")


def load(row):
    p = lpath(row)
    if os.path.exists(p):
        try:
            with open(p, "r", encoding=UTF8) as f:
                return json.load(f)
        except Exception:
            pass
    return {"row": row, "state": "open", "round": 1, "attempts": [], "rounds": []}


def save(led):
    os.makedirs(GATE, exist_ok=True)
    p = lpath(led["row"])
    tmp = p + ".tmp"
    with open(tmp, "w", encoding=UTF8, newline="\n") as f:
        json.dump(led, f, indent=1, ensure_ascii=False)
    os.replace(tmp, p)


def log(kind, text):
    try:
        os.makedirs(GATE, exist_ok=True)
        with open(os.path.join(GATE, "gate.log"), "a", encoding=UTF8, newline="\n") as f:
            f.write("%s\t%s\t%s\n" % (ts(), kind, re.sub(r"[\t\r\n]+", " ", text)[:400]))
    except Exception:
        pass


def key_of(case, desc):
    return hashlib.sha1((case + "|" + re.sub(r"\s+", " ", desc.strip().lower())).encode(UTF8)).hexdigest()[:12]


def fpath(p):
    """normalise a path the brief wrote (quotes, /mnt/c, /c/, trailing punctuation)"""
    p = (p or "").strip().strip("`'\"<>").rstrip(".,;)")
    p = re.sub(r"^/mnt/([a-z])/", lambda m: m.group(1).upper() + ":/", p)
    p = re.sub(r"^/([a-z])/", lambda m: m.group(1).upper() + ":/", p)
    return p


def parse_status(name):
    f = os.path.join(AGENTS, name + ".status")
    if not os.path.exists(f):
        return None
    try:
        with open(f, "r", encoding=UTF8, errors="replace") as fh:
            head = fh.readline().strip()
        parts = [x.strip() for x in head.split("|")]
        return {"state": (parts[1] if len(parts) > 1 else "").upper(), "mtime": datetime.fromtimestamp(os.path.getmtime(f)).replace(microsecond=0), "file": f}
    except Exception:
        return None


def refresh(led):
    """update running attempts from status files / ttl; returns True if changed"""
    changed = False
    t = now()
    for a in led["attempts"]:
        if a.get("state") != "running":
            continue
        st = parse_status(a["name"]) if a.get("name") else None
        started = pts(a.get("started", "")) or t
        if st and st["mtime"] >= started - timedelta(minutes=3):
            if st["state"] in ("DONE", "FAILED", "STOPPED-CONTEXT", "STOPPED"):
                a["state"] = {"DONE": "done", "FAILED": "failed"}.get(st["state"], "stopped")
                a["ended"] = ts(st["mtime"])
                a["report"] = a.get("report") or find_report(a["name"])
                changed = True
            elif st["mtime"] + timedelta(minutes=OPEN_TTL_MIN) < t:
                a["state"] = "stale"
                a["ended"] = ts(st["mtime"])
                changed = True
        elif started + timedelta(minutes=OPEN_TTL_MIN) < t:
            a["state"] = "expired"
            a["ended"] = ts(started + timedelta(minutes=OPEN_TTL_MIN))
            changed = True
    return changed


def find_report(name):
    for c in (os.path.join(AGENTS, "out", name, "latest.md"), os.path.join(AGENTS, name + ".handoff.md")):
        if os.path.exists(c):
            return c.replace("\\", "/")
    return ""


def current(led):
    return [a for a in led["attempts"] if a.get("round", 1) == led.get("round", 1)]


def gated(a):
    return a.get("role") in ("fixer", "recipe", "investigator")


def derive_name(desc, prompt):
    m = re.search(r"agents[\\/]+([A-Za-z0-9._-]+?)\.(?:status|handoff|brief)", prompt or "")
    if m:
        return m.group(1)
    m = re.search(r"\bYou are (?:operator |agent )?'?([A-Za-z0-9][A-Za-z0-9._-]*-[A-Za-z0-9._-]+)'?", prompt or "")
    if m:
        return m.group(1).rstrip(".-_")
    m = re.search(r"\]\s*(imm26-[A-Za-z0-9._-]+)", desc or "")
    return m.group(1).rstrip(".-_") if m else ""


def field(prompt, label):
    m = re.search(r"(?im)^[ \t>*_-]*" + label + r"[ \t]*:[ \t]*(.+?)[ \t]*$", prompt or "")
    return m.group(1).strip() if m else ""


def classify(desc, prompt):
    """returns (case, role, rows, skip_reason) ; role '' = not handled by the gate"""
    m = re.search(r"\[case:([a-z]+)\]", desc or "")
    case = m.group(1) if m else ""
    if not case:
        m = re.search(r"Routing: case=([a-z]*)", prompt or "")
        case = m.group(1) if m else ""
    sk = SKIP_RE.search(desc or "") or SKIP_RE.search((prompt or "")[:600])
    skip = (sk.group(1).strip() or "(no reason)") if sk else ""
    if case in ("bench", "grade"):
        return case, "", [], skip
    rows = find_rows(desc)
    if not rows:
        rows = find_rows((prompt or "")[:300])
    low = (desc or "").lower()
    name = derive_name(desc, prompt)
    if re.search(r"\b\d{4}-i\d\s+operator\b", low) or re.search(r"-\d{4}-i\d+op\d+[a-z]?$", name):   # lane operators: "5090-i3 operator ..." / imm26-5090-i3op23
        role = "operator"
    elif case in GATED_CASES:
        role = "recipe" if "recipe" in low else GATED_CASES[case]
    elif case in EXEMPT_CASES:
        role = "reader"
    else:
        role = ""
    return case, role, rows, skip


def suggest_evidence(row):
    out = []
    try:
        for d in sorted(os.listdir(RUNS)):
            p = os.path.join(RUNS, d, "rows", row)
            if d.startswith("imm26-") and os.path.isdir(p):
                out.append((os.path.getmtime(p), p.replace("\\", "/")))
    except Exception:
        pass
    out.sort(reverse=True)
    return [p for _, p in out[:3]]


def ticket_evidence(row):
    try:
        with open(os.path.join(SETUPFAIL, row + ".json"), "r", encoding=UTF8) as f:
            m = re.search(r"evidence[: ]+([A-Za-z]:[\\/][^\s,;)]+)", json.load(f).get("reason", ""))
        return m.group(1) if m else ""
    except Exception:
        return ""


def check_row(led, case, role, prompt, same_key_attempt):
    """returns list of problems (empty = allowed)"""
    row = led["row"]
    cur = current(led)
    prior = [a for a in cur if gated(a) and a is not same_key_attempt]
    probs = []
    opened = [a for a in prior if a.get("state") == "running"]
    if opened:
        o = opened[-1]
        probs.append("another agent for row %s is still RUNNING: %s (%s, since %s). One open agent per row: wait for it, or "
                     "`rowgate.ps1 done %s %s <outcome>` if it is really finished" % (row, o.get("name") or "(unnamed)", o.get("role"), o.get("started"), row, o.get("name") or "<name>"))
    n = len(prior) + 1
    if n > MAX_ATTEMPTS:
        esc_ok = case == "escalate" and field(prompt, "ESCALATE") and field(prompt, "METHOD-QUESTION")
        if not esc_ok:
            probs.append("row %s already has %d gated attempts (cap %d): attempt %d needs [case:escalate], a line `ESCALATE: <why the 3 attempts failed>` and a line "
                         "`METHOD-QUESTION: <the different approach you put to Shay>` (send that question to Shay's relay first)" % (row, len(prior), MAX_ATTEMPTS, n))
    if n >= 2:
        last = prior[-1]
        rep = fpath(field(prompt, "PREV-REPORT"))
        if not rep:
            probs.append("missing line `PREV-REPORT: <path>` (previous agent %s, report/handoff: %s)" % (last.get("name") or "?", last.get("report") or "see C:/KenshiTestRuns/agents/out/<name>/latest.md"))
        elif rep.lower().startswith("none"):
            if not all(a.get("state") in ("failed", "stopped", "expired", "stale") and not a.get("report") for a in prior):
                probs.append("PREV-REPORT: none is only accepted when every earlier agent failed/stopped without a report")
        elif not os.path.exists(rep):
            probs.append("PREV-REPORT does not exist: %s" % rep)
        else:
            st = pts(last.get("started", ""))
            try:
                mt = datetime.fromtimestamp(os.path.getmtime(rep))
                if st and not last.get("seeded") and mt < st - timedelta(minutes=2) and last.get("state") not in ("failed", "stopped", "expired", "stale"):
                    probs.append("PREV-REPORT %s (modified %s) is older than the previous agent's start %s: point at that agent's own handoff/report" % (rep, ts(mt), last.get("started")))
            except Exception:
                pass
        dif = field(prompt, "WHAT IS DIFFERENT THIS TIME")
        if len(dif) < 20 or re.fullmatch(r"(?i)(n/?a|none|same|retry|tbd|todo|\W*)", dif):
            probs.append("missing/empty line `WHAT IS DIFFERENT THIS TIME: <one line, >= 20 chars, what changed vs the previous attempt>`")
        ev = fpath(field(prompt, "REPLAY-EVIDENCE"))
        sug = suggest_evidence(row)
        te = led.get("ticketEvidence") or ticket_evidence(row)
        hint = " (candidates: %s)" % ", ".join(([te.replace("\\", "/")] if te else []) + sug) if (te or sug) else ""
        if not ev:
            probs.append("missing line `REPLAY-EVIDENCE: <dir>` = the REAL lane evidence of the previous live run that the fix is replayed against OFFLINE before any live rerun%s" % hint)
        elif not os.path.isdir(ev) or not any(True for _ in os.scandir(ev)):
            probs.append("REPLAY-EVIDENCE is not an existing non-empty directory: %s%s" % (ev, hint))
        elif re.search(r"(?i)selftest|fake|scratch|[\\/]tmp[\\/]|fixture", ev):
            probs.append("REPLAY-EVIDENCE %s looks like a fake/selftest scene, not real lane evidence%s" % (ev, hint))
    return probs, n


def do_guard(raw):
    inp = json.loads(raw)
    if inp.get("tool_name") != "Agent":
        return 0
    if not re.match(r"^[A-Za-z]:[\\/]KenshiModding([\\/]|$)", str(inp.get("cwd", ""))):
        return 0
    ti = inp.get("tool_input") or {}
    desc = str(ti.get("description", ""))
    prompt = str(ti.get("prompt", ""))
    case, role, rows, skip = classify(desc, prompt)
    if not role or not rows:
        if role and not rows:
            log("norow", "%s %s" % (case, desc))
        return 0
    if len(rows) > MAX_ROWS:
        log("sweep", "%d rows, not gated: %s" % (len(rows), desc))
        return 0
    name = derive_name(desc, prompt)
    key = key_of(case, desc)
    allproblems = []
    pending = []
    for row in rows:
        led = load(row)
        refresh(led)
        same = None
        for a in current(led):
            if a.get("key") == key and a.get("state") == "running":
                st = pts(a.get("started", ""))
                if st and st + timedelta(minutes=DEDUPE_MIN) >= now():
                    same = a
        if role in ("operator", "reader"):
            probs, n = [], 0
        else:
            probs, n = check_row(led, case, role, prompt, same)
        if skip:
            if probs:
                log("skip", "row=%s why=%s problems=%s desc=%s" % (row, skip, " || ".join(probs), desc))
                with open(os.path.join(GATE, "skips.log"), "a", encoding=UTF8, newline="\n") as f:
                    f.write("%s\t%s\t%s\t%s\n" % (ts(), row, skip, desc[:120]))
            probs = []
        allproblems += probs
        pending.append((led, same, n))
    if allproblems:
        log("deny", "rows=%s %s :: %s" % (",".join(rows), desc, " || ".join(allproblems)))
        sys.stderr.write("rowgate DENY (docs/ROW_REWORK_GATE.md; rows %s):\n" % ", ".join(rows))
        for p in allproblems:
            sys.stderr.write("  - " + p + "\n")
        sys.stderr.write("Fix the brief and call again; real exception: add `[rowgate:skip <why>]` to the description (logged in rowgate/skips.log).\n")
        return 2
    for led, same, n in pending:
        if same is None:
            led["state"] = "open"
            led["attempts"].append({
                "n": n, "name": name, "role": role, "case": case, "desc": desc[:160], "key": key, "state": "running", "started": ts(), "ended": "",
                "report": "", "prev_report": fpath(field(prompt, "PREV-REPORT")),
                "evidence": fpath(field(prompt, "REPLAY-EVIDENCE")), "different": field(prompt, "WHAT IS DIFFERENT THIS TIME"),
                "outcome": "", "cost": None, "agentId": "", "skipped": skip, "round": led.get("round", 1)})
        save(led)
    log("allow", "rows=%s role=%s case=%s name=%s %s" % (",".join(rows), role, case, name, desc))
    return 0


def do_post(raw):
    inp = json.loads(raw)
    if inp.get("tool_name") != "Agent":
        return 0
    ti = inp.get("tool_input") or {}
    desc = str(ti.get("description", ""))
    case, role, rows, _ = classify(desc, str(ti.get("prompt", "")))
    if not role or not rows or len(rows) > MAX_ROWS:
        return 0
    resp = inp.get("tool_response")
    text = resp if isinstance(resp, str) else json.dumps(resp)
    m = re.search(r'agentId"?\s*:\s*"?([A-Za-z0-9_-]+)', text)
    aid = m.group(1) if m else ""
    background = "Async agent launched" in text or "output_file" in text
    key = key_of(case, desc)
    for row in rows:
        led = load(row)
        hit = [a for a in current(led) if a.get("key") == key]
        if not hit:
            continue
        a = hit[-1]
        if aid:
            a["agentId"] = aid
        if not background and a.get("state") == "running":
            a["state"] = "done"
            a["ended"] = ts()
        save(led)
    return 0


def cli_status(row=None):
    global VERDICTS
    VERDICTS = tests_verdicts()
    rows = [norm_row(row)] if row else sorted(os.path.splitext(f)[0] for f in os.listdir(GATE) if f.endswith(".json")) if os.path.isdir(GATE) else []
    for r in rows:
        led = load(r)
        if refresh(led):
            save(led)
        cur = current(led)
        g = [a for a in cur if gated(a)]
        op = [a for a in cur if a.get("role") == "operator"]
        openn = [a for a in g if a.get("state") == "running"]
        if not row and not g:
            continue
        flag = "OPEN-AGENT" if openn else ("CAP" if len(g) >= MAX_ATTEMPTS else "")
        print("%-9s %-6s round %d  gated %d (cap %d)  operators %d  tests:%s %s%s" % (r, led.get("state"), led.get("round", 1), len(g), MAX_ATTEMPTS, len(op), VERDICTS.get(r, "?"), flag,
                                                                       ("  | " + led["costNote"]) if led.get("costNote") else ""))
        if row:
            for a in cur:
                print("   #%-2s %-9s %-11s %-8s %s  %s%s" % (a.get("n"), a.get("role"), a.get("state"), (a.get("started") or "")[5:16], a.get("name") or "(unnamed)",
                      (a.get("outcome") or ""), ("  $%s" % a["cost"]) if a.get("cost") is not None else ""))
                if a.get("report"):
                    print("        report: %s" % a["report"])
            te = led.get("ticketEvidence") or ticket_evidence(r)
            sug = suggest_evidence(r)
            print("   replay-evidence candidates: %s" % (", ".join(([te] if te else []) + sug) or "(none found; the operator must file it in the ticket)"))
            nxt = len(g) + 1
            print("   next gated agent = attempt %d: %s" % (nxt, "BLOCKED (agent running)" if openn else ("needs ESCALATE" if nxt > MAX_ATTEMPTS else ("needs PREV-REPORT + WHAT IS DIFFERENT THIS TIME + REPLAY-EVIDENCE" if nxt >= 2 else "free"))))
    return 0


def tests_verdicts():
    """row -> verdict from the imm26 tests table (| IMM-<row> | ... | PASS|FAIL|SETUP-FAIL|UNRUN|GATED | ...); {} when the file is missing"""
    p = os.environ.get("ROWGATE_TESTS") or os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "testing", "NPC_IMMERSION_26_TESTS.md")
    out = {}
    try:
        with open(p, "r", encoding=UTF8, errors="replace") as f:
            for ln in f:
                m = re.match(r"^\|\s*IMM-([0-9a-z-]+)\s*\|", ln, re.I)
                if m:
                    v = re.search(r"\|\s*(PASS|FAIL|SETUP-FAIL|UNRUN|GATED|PARTIAL)\s*\|", ln)
                    if v:
                        out[norm_row(m.group(1))] = v.group(1)
    except Exception:
        pass
    return out


def seed():
    """one entry per (row, agent) from status files dated today + setupfail ticket owners; idempotent"""
    added = 0
    today = now().strftime("%Y-%m-%d")
    cost_notes = {"26-a": "credit review 2026-10-16: 21 agents, first $0.57, later $18.15", "15-bx": "15 agents, first $1.43, later $8.95",
                  "23-a": "8 agents, first $1.43, later $7.54", "02-bx": "4 agents, first $0.86, later $1.15", "16-bx": "5 agents, first $0.35, later $0.90",
                  "17-bx": "2 agents, first $0.83, later $0.55", "26-f": "later agents $13.34", "14-d": "later agents $10.32", "11-b": "later agents $10.01",
                  "20-a": "later agents $6.65", "22-b": "later agents $5.91", "03-b": "later agents $5.83"}
    ents = []
    if os.path.isdir(AGENTS):
        for f in os.listdir(AGENTS):
            if not f.endswith(".status"):
                continue
            name = f[:-7]
            if name.startswith("ab2-") or "bench" in name:
                continue
            p = os.path.join(AGENTS, f)
            try:
                with open(p, "r", encoding=UTF8, errors="replace") as fh:
                    lines = [x.rstrip("\n") for x in fh.readlines()[:5]]
            except Exception:
                continue
            head = [x.strip() for x in (lines[0] if lines else "").split("|")]
            when = pts((head[2] + ":00") if len(head) > 2 and re.match(r"^\d{4}-\d\d-\d\d \d\d:\d\d$", head[2]) else "")
            if not when or when.strftime("%Y-%m-%d") != today:
                continue
            task = next((x[5:].strip() for x in lines if x.startswith("task:")), "")
            latest = next((x[7:].strip() for x in lines if x.startswith("latest:")), "")
            rows = find_rows(task)
            if not rows or len(rows) > MAX_ROWS:
                continue
            low = (task + " " + name).lower()
            if "operator" in low or re.search(r"op\d+[a-z]?$", name):
                role = "operator"
            elif re.search(r"(^|-)(inv|investigat)", name.split("imm26-")[-1]) or "investigat" in low or "root cause" in low:
                role = "investigator"
            elif "recipe" in low:
                role = "recipe"
            else:
                role = "fixer"
            rep = ""
            for c in (os.path.join(AGENTS, "out", name, "latest.md"), os.path.join(AGENTS, name + ".handoff.md"), p):
                if os.path.exists(c):
                    rep = c.replace("\\", "/")
                    break
            state = {"DONE": "done", "FAILED": "failed", "RUNNING": "running"}.get(head[1].upper() if len(head) > 1 else "", "stopped")
            ents.append((when, name, rows, role, state, rep, task, latest))
    ents.sort()
    for when, name, rows, role, state, rep, task, latest in ents:
        for row in rows:
            led = load(row)
            if any(a.get("name") == name for a in led["attempts"]):
                continue
            led["attempts"].append({"n": len([a for a in led["attempts"] if gated(a)]) + 1 if role != "operator" else 0, "name": name, "role": role, "case": "", "desc": task[:160],
                                    "key": "", "state": state, "started": ts(when), "ended": ts(when) if state != "running" else "", "report": rep, "prev_report": "", "evidence": "",
                                    "different": "", "outcome": latest[:140], "cost": None, "agentId": "", "skipped": "", "round": led.get("round", 1), "seeded": True})
            if row in cost_notes:
                led["costNote"] = cost_notes[row]
            te = ticket_evidence(row)
            if te:
                led["ticketEvidence"] = te
            save(led)
            added += 1
    closed = 0
    for row, verdict in sorted(tests_verdicts().items()):
        led = load(row)
        if verdict == "PASS" and led["attempts"] and led.get("state") != "closed" and not led["rounds"]:
            led["rounds"].append({"round": led.get("round", 1), "closed": ts(), "outcome": "PASS (tests md at seed time)", "attempts": len(current(led))})
            led["state"] = "closed"
            led["round"] = led.get("round", 1) + 1
            save(led)
            closed += 1
    print("seeded %d attempt entries, closed %d PASS rows" % (added, closed))
    return 0


def cli(argv):
    cmd = argv[0] if argv else "status"
    a = argv[1:]
    if cmd == "status":
        return cli_status(a[0] if a else None)
    if cmd == "list":
        return cli_status(None)
    if cmd == "rows":
        print(" ".join(find_rows(" ".join(a))))
        return 0
    if cmd == "seed":
        return seed()
    if cmd in ("add", "done", "close", "cost"):
        if not a:
            sys.stderr.write("usage: rowgate.ps1 add <row> <name> <role> [report] [outcome] | done <row> <name> [outcome] | close <row> [outcome] | cost <row> <name> <usd>\n")
            return 2
        led = load(norm_row(a[0]))
        if cmd == "add":
            if len(a) < 4:
                sys.stderr.write("add <row> <name> <role fixer|recipe|investigator|operator> [report] [outcome]\n")
                return 2
            led["state"] = "open"
            led["attempts"].append({"n": len([x for x in current(led) if gated(x)]) + 1, "name": a[1], "role": a[2], "case": "", "desc": "added by hand", "key": "", "state": "running",
                                    "started": ts(), "ended": "", "report": fpath(a[4]) if len(a) > 4 else "", "prev_report": "", "evidence": "", "different": "",
                                    "outcome": a[5] if len(a) > 5 else "", "cost": None, "agentId": "", "skipped": "", "round": led.get("round", 1)})
        elif cmd == "done":
            hit = [x for x in current(led) if x.get("name") == (a[1] if len(a) > 1 else "")]
            if not hit:
                sys.stderr.write("no attempt named %s on row %s\n" % (a[1] if len(a) > 1 else "?", a[0]))
                return 1
            hit[-1]["state"] = "done"
            hit[-1]["ended"] = ts()
            if len(a) > 2:
                hit[-1]["outcome"] = a[2]
        elif cmd == "cost":
            hit = [x for x in led["attempts"] if x.get("name") == a[1]]
            if not hit:
                return 1
            hit[-1]["cost"] = float(a[2])
        else:
            led["rounds"].append({"round": led.get("round", 1), "closed": ts(), "outcome": a[1] if len(a) > 1 else "", "attempts": len(current(led))})
            led["state"] = "closed"
            led["round"] = led.get("round", 1) + 1
        save(led)
        print("ok %s %s" % (cmd, led["row"]))
        return 0
    sys.stderr.write("unknown command %s (status|list|add|done|close|cost|seed|rows|guard|post)\n" % cmd)
    return 2


if __name__ == "__main__":
    try:
        sys.stdout.reconfigure(encoding="utf-8")
        sys.stdin.reconfigure(encoding="utf-8")
    except Exception:
        pass
    c = sys.argv[1] if len(sys.argv) > 1 else "status"
    if c in ("guard", "post"):
        try:
            code = (do_guard if c == "guard" else do_post)(sys.stdin.buffer.read().decode("utf-8-sig", errors="replace"))
        except Exception as e:  # internal error: fail open like the router
            log("error", "%s: %r" % (c, e))
            sys.stderr.write("rowgate: internal error, call allowed: %r\n" % (e,))
            code = 0
        sys.exit(code)
    sys.exit(cli(sys.argv[1:]))
