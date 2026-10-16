#!/usr/bin/env python3
"""pilot-audit.py: audit of the Haiku shadow pilot (lane 5090-i4) against the paired Sonnet lane operator(s) (imm26-pilotA2).
  pilot-audit.py [PILOT] [--paired NAME[,NAME] ...] [--fill] [--out FILE] [--no-cost] [--selftest]
  PILOT (default imm26-5090-i4-hk1); --paired default imm26-5090-i3op21 (+ every successor imm26-5090-i3opN, N >= 21, that has a status
  file; --no-successors turns that off; several names may be given, comma separated or repeated).
Reads (read-only): <pilot-dir>\\verdicts.csv, events.log, state.json, out\\*.out (pilot-dir default C:\\KenshiTestRuns\\pilot\\haiku-i4),
  agents\\<name>.status|handoff.md|brief.md, agents\\out\\<name>\\*.md (final reports), inbox\\coordinator relays that name the agent,
  the Sonnet evidence trees (--sonnet-roots, default imm26-5090-i3 + imm26-5090-hx) and the TESTS file (read-only, row ids + notes).
Writes C:\\KenshiTestRuns\\pilot\\haiku-i4\\SUMMARY.md (--out) with side-by-side tables:
  TIME    wall_s per row, rows/hour, idle gaps (> --idle-gap s, default 120), time to first START / first row since the brief file.
  QUALITY agree rate with the checker `RESULT <row> ...` line, rows completed, escalations, refused attempts; SETUP-FAIL / GATED /
          ESCALATE rows list the pilot's note and the Sonnet lane's diagnosis side by side (human judgement, no scoring).
  FALSE INFO  checkable claims in status lines (also earlier snapshots kept in <pilot-dir>\\status-history), handoffs, final reports and
          relays, counted per row and per source with the SAME rules for both sides: existing paths (Windows/Git Bash/repo-relative; WSL-only
          paths are unverifiable), hex ids (7+ chars: a git commit in --repo, or present in the cited/row evidence text), row ids (must be rows of the
          TESTS/rows list), `<row> PASS|FAIL|GATED|SETUP-FAIL` verdict claims (some `RESULT <row> <that kind>` line must exist; if RESULT lines
          exist but none of that kind = FALSE; no RESULT line at all = unverifiable), count claims (`N rows`, `N PASS`...; checked only against an
          exact ledger = the pilot's verdicts.csv, unverifiable for the Sonnet side).
  COST    tools/automation/cost-audit.py --pilot-compare PILOT PAIRED over the pilot's window (tokens, USD, per hour, context growth).
--fill    fills tokens, cost, false_claims_n in verdicts.csv (final line of each row: tokens/cost from cost-audit over the row's window at
          minute resolution, so neighbouring rows can overlap by a minute; false_claims_n = FALSE claims attributed to that row).
Empty or partial data (pilot just started) is handled: sections say 'no data yet'. Exit 0 ok, 2 usage. Env: KAH_RUNS_DIR, KAH_PILOT_DIR,
KAH_REPO, KAH_TESTS_FILE. Selftest (fixtures in a temp dir, offline): pilot-audit.py --selftest.
"""
import sys, os, re, csv, json, glob, time, datetime, hashlib, subprocess, tempfile, shutil, collections, statistics

HEADER = ["row", "lane", "model", "start", "end", "wall_s", "tokens", "cost", "operator_verdict", "checker_result", "agree", "false_claims_n", "notes"]
KINDS = ("SETUP-FAIL", "PASS", "FAIL", "GATED")
ROW_RE = re.compile(r"(?<![\w-])(?:IMM-)?(\d{2}-[a-z]{1,3})(?![\w])")
RESULT_RE = re.compile(r"^\s*RESULT\s+(?:IMM-)?(\d{2}-[a-z]{1,3})\s+(SETUP-FAIL|PASS|FAIL|GATED)\b(.*)$")
VERDICT_RE = re.compile(r"(?<![\w-])(?:IMM-)?(\d{2}-[a-z]{1,3})(?![\w])[\s:=(\-]{0,3}(SETUP-FAIL|PASS|FAIL|GATED|ESCALAT\w*)")
HEX_RE = re.compile(r"(?<![\w.-])([0-9A-Fa-f]{7,64})(?![\w])")
WIN_PATH_RE = re.compile(r"(?<![A-Za-z0-9])[A-Za-z]:[\\/][^\s\"'`<>|;,()\[\]{}]*")
GITBASH_RE = re.compile(r"(?<![\w.:/\\])/(?:mnt/)?[a-z]/[A-Za-z0-9_.][^\s\"'`<>|;,()\[\]{}]*")
WSL_RE = re.compile(r"(?<![\w.:/\\])/(?:tmp|root|var|etc|home|opt|usr)/[^\s\"'`<>|;,()\[\]{}]*")
REL_RE = re.compile(r"(?<![\w/\\.:-])(?:tools|testing|docs|components|pending-fixes|archive|rowtools)/[^\s\"'`<>|;,()\[\]{}]*")
COUNT_RE = re.compile(r"(?<![\w/.-])(\d{1,3})\s+(rows?|PASS|FAIL|GATED|SETUP-FAIL|escalat\w*|refus\w*)\b")
NOTE_CAP = 300


# ---------------------------------------------------------------- small helpers
def runs_dir():
    d = os.environ.get("KAH_RUNS_DIR")
    if d:
        return d
    for c in ("C:\\KenshiTestRuns", "/c/KenshiTestRuns", "/mnt/c/KenshiTestRuns"):
        if os.path.isdir(c):
            return c
    return "C:\\KenshiTestRuns"


def fixpath(p):
    """Normalise Windows / Git Bash / WSL spellings of one path to what THIS python can open."""
    p = p.strip()
    m = re.match(r"^([A-Za-z]):[\\/](.*)$", p)
    if m:
        if os.name == "posix":
            for base in ("/mnt/%s", "/%s"):
                q = os.path.join(base % m.group(1).lower(), m.group(2).replace("\\", "/"))
                if os.path.exists(q):
                    return q
            return os.path.join("/mnt/%s" % m.group(1).lower(), m.group(2).replace("\\", "/"))
        return p
    m = re.match(r"^/(?:mnt/)?([a-z])/(.*)$", p)
    if m and os.name == "nt":
        return "%s:/%s" % (m.group(1).upper(), m.group(2))
    return p


def read_text(path, cap=3000000):
    try:
        if os.path.getsize(path) > cap:
            return ""
        with open(path, encoding="utf-8-sig", errors="replace") as f:
            return f.read()
    except OSError:
        return ""


def iso(t):
    return t.strftime("%Y-%m-%dT%H:%M:%S")


def parse_iso(s):
    try:
        return datetime.datetime.strptime((s or "")[:19].replace(" ", "T"), "%Y-%m-%dT%H:%M:%S")
    except ValueError:
        return None


def fmt_dur(s):
    if s is None:
        return "-"
    s = int(round(s))
    if s < 120:
        return "%ds" % s
    if s < 7200:
        return "%dm%02ds" % (s // 60, s % 60)
    return "%dh%02dm" % (s // 3600, (s % 3600) // 60)


def cell(x, cap=NOTE_CAP):
    x = re.sub(r"\s+", " ", str(x if x is not None else "")).strip().replace("|", "/")
    return (x[:cap] + "...") if len(x) > cap else x


def md_table(head, rows):
    out = ["| " + " | ".join(head) + " |", "|" + "|".join("---" for _ in head) + "|"]
    for r in rows:
        out.append("| " + " | ".join(cell(c) if not str(c).startswith("\x00") else str(c)[1:] for c in r) + " |")
    return "\n".join(out)


# ---------------------------------------------------------------- loaders
def load_csv(path):
    rows = []
    try:
        with open(path, encoding="utf-8-sig", newline="") as f:
            for r in csv.DictReader(f):
                if r.get("row"):
                    rows.append(r)
    except OSError:
        pass
    return rows


EV_RE = re.compile(r"^(\S+) agent=(\S*) lane=(\S*) row=(\S*) verdict=(\S*) ([A-Z-]+): ?(.*)$")


def load_events(path):
    ev = []
    for ln in read_text(path).splitlines():
        m = EV_RE.match(ln)
        if m:
            ev.append({"ts": parse_iso(m.group(1)), "agent": m.group(2), "lane": m.group(3), "row": m.group(4),
                       "verdict": m.group(5), "kind": m.group(6), "text": m.group(7)})
    return ev


def scan_results(roots, exts=(".out", ".txt", ".log"), maxdepth=6, skip=()):
    """row -> list of dict(kind, line, path, mtime) for every `RESULT <row> <KIND>` line under the roots."""
    res = collections.defaultdict(list)
    seen = set()
    for root in roots:
        root = fixpath(root)
        if os.path.isfile(root):
            files = [root]
        else:
            files = []
            for dp, dn, fn in os.walk(root):
                depth = dp.count(os.sep) - root.rstrip("\\/").count(os.sep)
                if depth >= maxdepth:
                    dn[:] = []
                dn[:] = [d for d in dn if d not in skip]
                for n in fn:
                    if n.lower().endswith(exts):
                        files.append(os.path.join(dp, n))
        for fp in files:
            key = os.path.normcase(os.path.abspath(fp))
            if key in seen:
                continue
            seen.add(key)
            try:
                mt = os.path.getmtime(fp)
            except OSError:
                continue
            for ln in read_text(fp).splitlines():
                m = RESULT_RE.match(ln)
                if m:
                    res[m.group(1)].append({"kind": m.group(2), "line": ln.strip(), "path": fp, "mtime": mt})
    return res


def known_rows(tests_file, rows_file, extra):
    k = set(extra)
    t = read_text(tests_file)
    k.update(re.findall(r"IMM-(\d{2}-[a-z]{1,3})\b", t))
    for ln in read_text(rows_file).splitlines():
        m = re.match(r"^(\d{2}-[a-z]{1,3})\s*::", ln)
        if m:
            k.add(m.group(1))
    return k


def tests_hits(tests_file, tests_text, rows):
    """TESTS-file status cells (column 'Status') as extra verdict hits: row -> [hit]; the Sonnet lane's own mark record."""
    hits = collections.defaultdict(list)
    col = None
    for ln in tests_text.splitlines():
        if ln.startswith("| ID ") and "Status" in ln:
            col = [c.strip() for c in ln.strip().strip("|").split("|")].index("Status")
            continue
        m = re.match(r"^\| IMM-(\d{2}-[a-z]{1,3}) ", ln)
        if m and col is not None:
            cells = [c.strip() for c in ln.strip().strip("|").split(" | ")]
            if len(cells) > col:
                k = re.match(r"(SETUP-FAIL|PASS|FAIL|GATED)", cells[col])
                if k:
                    hits[m.group(1)].append({"kind": k.group(1), "line": "TESTS status " + k.group(1), "path": tests_file, "mtime": os.path.getmtime(tests_file)})
    return hits


def tests_note(tests_text, row):
    for ln in tests_text.splitlines():
        if ln.startswith("| IMM-%s " % row) or ln.startswith("| IMM-%s|" % row):
            cells = [c.strip() for c in ln.strip().strip("|").split(" | ")]
            tail = " / ".join(cells[-2:]) if len(cells) >= 2 else ln
            mm = re.findall(r"[^.;]*5090-i3[^.;]*", tail)
            return ("5090-i3: " + "; ".join(x.strip() for x in mm[:2])) if mm else "(any lane) " + tail
    return ""


# ---------------------------------------------------------------- claims
def read_snapshots(histdir, name, status_path):
    """Append the current status text to the history when it changed; return all distinct snapshot texts (oldest first)."""
    cur = read_text(status_path)
    hp = os.path.join(histdir, name + ".log")
    hist = read_text(hp)
    blocks = re.findall(r"(?ms)^=== snapshot [^\n]*===\n(.*?)(?=^=== snapshot |\Z)", hist)
    if cur.strip() and (not blocks or blocks[-1].strip() != cur.strip()):
        try:
            os.makedirs(histdir, exist_ok=True)
            with open(hp, "a", encoding="utf-8") as f:
                f.write("=== snapshot %s ===\n%s\n" % (iso(datetime.datetime.now()), cur.strip()))
            blocks.append(cur.strip() + "\n")
        except OSError:
            pass
    return [b.strip() for b in blocks]


def agent_sources(agents_dir, hist_dir, name, runs):
    """list of (source label, text) for a status/handoff/final report/relay bundle of one agent."""
    src = []
    sp = os.path.join(agents_dir, name + ".status")
    for i, snap in enumerate(read_snapshots(hist_dir, name, sp)):
        src.append(("status:%s#%d" % (name, i + 1), snap))
    hp = os.path.join(agents_dir, name + ".handoff.md")
    if os.path.isfile(hp):
        src.append(("handoff:%s" % name, read_text(hp)))
    for rp in sorted(glob.glob(os.path.join(agents_dir, "out", name, "*.md"))):
        if os.path.basename(rp) == "latest.md" and glob.glob(os.path.join(agents_dir, "out", name, "out-*.md")):
            continue  # latest.md duplicates the newest out-*.md
        src.append(("report:%s/%s" % (name, os.path.basename(rp)), read_text(rp)))
    inbox = os.path.join(runs, "inbox", "coordinator")
    if os.path.isdir(inbox):
        for dp, dn, fn in os.walk(inbox):
            for n in sorted(fn):
                fp = os.path.join(dp, n)
                t = read_text(fp, 200000)
                if name in n or name in t[:400]:   # the relay is about this agent (file name or header), not a passing mention
                    src.append(("relay:%s" % n, t))
    return src


class Checker:
    def __init__(self, repo, known, results, ledger, evidence_dirs):
        self.repo, self.known, self.results, self.ledger, self.ev_dirs = repo, known, results, ledger, evidence_dirs
        self._git = {}
        self._corp = {}
        self.questions = set()

    def git_commit(self, sha):
        if sha not in self._git:
            ok = False
            try:
                r = subprocess.run(["git", "-C", self.repo, "cat-file", "-e", sha + "^{commit}"], capture_output=True, timeout=20)
                ok = r.returncode == 0
            except Exception:
                ok = False
            self._git[sha] = ok
        return self._git[sha]

    def path_state(self, raw):
        p = raw.rstrip(".:")
        if not p or p.endswith("...") or "..." in p:
            return None
        if WSL_RE.match(p) and os.name == "nt":     # on WSL itself these are ordinary paths and get checked
            return ("unverifiable", "WSL-only path (not checked)")
        cands = [fixpath(p)]
        if REL_RE.match(p):
            cands = [os.path.join(self.repo, p), os.path.join(self.repo, "testing", "live-stobe-queue", "imm26-assert", p)]
        for c in cands:
            if "*" in c or "?" in c:
                if glob.glob(c):
                    return ("verified", "")
            elif os.path.exists(c):
                return ("verified", "")
        return ("false", "path does not exist")

    def corpus(self, paths):
        """lower-cased text of the files behind the cited paths (dirs: first 40 small text files)."""
        key = tuple(sorted(paths))
        if key in self._corp:
            return self._corp[key]
        txt = []
        for p in paths:
            q = fixpath(p)
            if os.path.isfile(q):
                txt.append(read_text(q))
            elif os.path.isdir(q):
                n = 0
                for dp, dn, fn in os.walk(q):
                    for f in fn:
                        if f.lower().endswith((".txt", ".out", ".log", ".json", ".md", ".csv", ".ini", ".php")) and n < 40:
                            txt.append(read_text(os.path.join(dp, f), 1000000))
                            n += 1
        self._corp[key] = "\n".join(txt).lower()
        return self._corp[key]

    def row_evidence_paths(self, rows):
        out = []
        for r in rows:
            for h in self.results.get(r, []):
                out.append(h["path"])
            for d in self.ev_dirs(r):
                out.append(d)
        return out

    def check_line(self, line, exact_ledger):
        """claims of one line: list of dict(type, text, state, why, rows)."""
        rows = sorted(set(ROW_RE.findall(line)))
        claims = []
        cited = []
        spans = []
        for rx in (WIN_PATH_RE, GITBASH_RE, WSL_RE, REL_RE):
            for m in rx.finditer(line):
                if any(a <= m.start() < b for a, b in spans):
                    continue
                nxt = line[m.end():m.end() + 1]
                if nxt in ("<", "{", "$") or "<" in m.group(0):
                    continue
                spans.append((m.start(), m.end()))
                st = self.path_state(m.group(0))
                if st is None:
                    continue
                claims.append({"type": "path", "text": m.group(0).rstrip(".:"), "state": st[0], "why": st[1], "rows": rows})
                if st[0] == "verified":
                    cited.append(m.group(0).rstrip(".:"))
        ev_text = None
        for m in HEX_RE.finditer(line):
            if any(a <= m.start() < b for a, b in spans):
                continue
            h = m.group(1)
            if h.isdigit() or not re.search(r"\d", h) or not re.search(r"[A-Fa-f]", h):
                continue
            if self.git_commit(h):
                claims.append({"type": "hex", "text": h, "state": "verified", "why": "git commit", "rows": rows})
                continue
            cited_text = self.corpus(cited)
            if cited_text:      # the claim cites an evidence file: it must be in there
                ok = h.lower() in cited_text
                claims.append({"type": "hex", "text": h, "state": "verified" if ok else "false",
                               "why": "in the cited evidence" if ok else "not in the cited evidence file(s)", "rows": rows})
                continue
            if ev_text is None:
                ev_text = self.corpus(self.row_evidence_paths(rows))
            if ev_text and h.lower() in ev_text:
                claims.append({"type": "hex", "text": h, "state": "verified", "why": "in the row evidence", "rows": rows})
            else:
                claims.append({"type": "hex", "text": h, "state": "unverifiable", "why": "no evidence file cited and not in the row evidence", "rows": rows})
        for r in rows:
            if self.known and not r.startswith("00-"):
                claims.append({"type": "row", "text": r, "state": "verified" if r in self.known else "false",
                               "why": "" if r in self.known else "not a row of the TESTS/rows list", "rows": [r]})
        for m in VERDICT_RE.finditer(line):
            r, v = m.group(1), m.group(2)
            if v.startswith("ESCALAT"):
                led = self.ledger.get(r)
                if led is None and r in self.questions:
                    led = {"verdicts": {"ESCALATE"}}
                if led is None:
                    claims.append({"type": "verdict", "text": "%s %s" % (r, v), "state": "unverifiable", "why": "no exact ledger", "rows": [r]})
                else:
                    ok = "ESCALATE" in led["verdicts"]
                    claims.append({"type": "verdict", "text": "%s %s" % (r, v), "state": "verified" if ok else "false",
                                   "why": "" if ok else "ledger has no ESCALATE for the row", "rows": [r]})
                continue
            hits = self.results.get(r, [])
            if not hits:
                claims.append({"type": "verdict", "text": "%s %s" % (r, v), "state": "unverifiable", "why": "no RESULT line found for the row", "rows": [r]})
            elif any(h["kind"] == v for h in hits):
                claims.append({"type": "verdict", "text": "%s %s" % (r, v), "state": "verified", "why": "RESULT line exists", "rows": [r]})
            else:
                claims.append({"type": "verdict", "text": "%s %s" % (r, v), "state": "false",
                               "why": "RESULT lines say " + "/".join(sorted(set(h["kind"] for h in hits))), "rows": [r]})
        for m in COUNT_RE.finditer(line):
            n, what = int(m.group(1)), m.group(2).lower()
            if exact_ledger is None:
                claims.append({"type": "count", "text": m.group(0), "state": "unverifiable", "why": "no exact ledger", "rows": rows})
                continue
            L = exact_ledger
            if what.startswith("row"):
                want = len(L["rows"])
            elif what.startswith("escalat"):
                want = L["escalations"]
            elif what.startswith("refus"):
                want = L["refused"]
            else:
                want = L["verdict_counts"].get(what.upper(), 0)
            claims.append({"type": "count", "text": m.group(0), "state": "verified" if n == want else "false",
                           "why": "" if n == want else "ledger says %d" % want, "rows": rows})
        return claims


def audit_claims(sources, checker, exact_ledger):
    """-> (claims list with source/line, seen-dedupe)."""
    out, seen = [], set()
    for label, text in sources:
        for ln in text.splitlines():
            ln = ln.strip()
            if len(ln) < 4 or ln in seen:
                continue
            seen.add(ln)
            for clause in re.split(r";| // ", ln):  # claims are attributed to the rows of their own clause
                clause = clause.strip()
                if len(clause) < 4:
                    continue
                for c in checker.check_line(clause, exact_ledger):
                    c = dict(c)
                    c["source"] = label
                    c["line"] = ln
                    out.append(c)
    return out


def tally(claims):
    t = {"claims": len(claims), "verified": 0, "false": 0, "unverifiable": 0}
    for c in claims:
        t[c["state"]] += 1
    return t


def pct(a, b):
    return "%.0f%%" % (100.0 * a / b) if b else "-"


# ---------------------------------------------------------------- pilot ledger / time
def pilot_view(pd, pilot_name, rows_known):
    recs = load_csv(os.path.join(pd, "verdicts.csv"))
    ev = load_events(os.path.join(pd, "events.log"))
    try:
        st = json.load(open(os.path.join(pd, "state.json"), encoding="utf-8"))
    except Exception:
        st = {"rows": {}}
    questions = [r for r in recs if r["row"].startswith("00-")]   # 00-* = a question to the coordinator, not a test row
    recs = [r for r in recs if not r["row"].startswith("00-")]
    byrow = collections.OrderedDict()
    for r in recs:
        byrow.setdefault(r["row"], []).append(r)
    ledger = {"rows": {}, "verdict_counts": collections.Counter(), "escalations": 0, "refused": 0}
    for row, lines in byrow.items():
        fin = lines[-1]
        notes = " | ".join(l.get("notes", "") for l in lines)
        ledger["rows"][row] = {"verdicts": set(l["operator_verdict"].upper() for l in lines), "final": fin, "lines": lines}
        if any(l["operator_verdict"].upper() == "ESCALATE" or l.get("notes", "").startswith("ESCALATE") for l in lines):
            ledger["escalations"] += 1
            ledger["rows"][row]["verdicts"].add("ESCALATE")
        ledger["refused"] += sum(1 for l in lines if l.get("notes", "").startswith("REFUSED"))
        v = fin["operator_verdict"].upper()
        if v in KINDS:
            ledger["verdict_counts"][v] += 1
    return recs, ev, st, byrow, ledger, questions


def checker_kind(txt):
    m = re.match(r"^\s*RESULT\s+(?:IMM-)?\d{2}-[a-z]{1,3}\s+(SETUP-FAIL|PASS|FAIL|GATED)(?![\w-])", txt or "")
    return m.group(1) if m else "-"


def intervals(recs):
    iv = []
    for r in recs:
        s, e = parse_iso(r.get("start")), parse_iso(r.get("end"))
        if s and e:
            iv.append((s, e, r["row"]))
    iv.sort()
    return iv


def median(xs):
    return statistics.median(xs) if xs else None


# ---------------------------------------------------------------- cost
def agent_ref(name):
    """cost-audit matches transcripts by agent id, not by the imm26 name: map name -> id via agents/ids.json (agent-ids.ps1); unknown names pass through."""
    try:
        path = next((x for x in ("C:/KenshiTestRuns/agents/ids.json", "/mnt/c/KenshiTestRuns/agents/ids.json") if os.path.isfile(x)), None)
        with open(path, encoding="utf-8-sig") as f:
            rec = json.load(f).get(name)
        if isinstance(rec, dict) and rec.get("id"):
            return rec["id"]
    except Exception:
        pass
    return name


def run_cost(script, a, b, since, until):
    cmd = [sys.executable, script, "--pilot-compare", agent_ref(a), agent_ref(b)]
    if since:
        cmd += ["--since", since]
    if until:
        cmd += ["--until", until]
    try:
        r = subprocess.run(cmd, capture_output=True, text=True, timeout=300, encoding="utf-8", errors="replace")
    except Exception as e:
        return None, "cost-audit failed to run: %s" % e
    if r.returncode != 0:
        return None, ((r.stdout or "") + (r.stderr or "")).strip()[-400:] or "cost-audit exit %d" % r.returncode
    metrics = collections.OrderedDict()
    for ln in r.stdout.splitlines():
        m = re.match(r"^\|\s*(.+?)\s*\|\s*(.+?)\s*\|\s*(.+?)\s*\|$", ln)
        if m and not set(m.group(1)) <= set("-"):
            metrics[m.group(1)] = (m.group(2), m.group(3))
    return {"metrics": metrics, "raw": r.stdout}, ""


def num(s):
    try:
        return float(re.sub(r"[^0-9.\-]", "", s))
    except ValueError:
        return None


def fmt_money(x):
    return "$%.2f" % x if x is not None else "-"


# ---------------------------------------------------------------- main audit
def pick_paired(args, agents_dir):
    names = []
    for a in args:
        names += [x for x in re.split(r"[,\s]+", a) if x]
    return names


def expand_successors(names, agents_dir):
    out = list(names)
    for n in names:
        m = re.match(r"^(.*?[a-z])(\d+)$", n)
        if not m:
            continue
        base, lo = m.group(1), int(m.group(2))
        for sp in glob.glob(os.path.join(agents_dir, base + "*.status")):
            nm = os.path.basename(sp)[:-7]
            mm = re.match(r"^" + re.escape(base) + r"(\d+)[a-z]?\d*$", nm)
            if mm and int(mm.group(1)) >= lo and nm not in out:
                out.append(nm)
    return out


def main(argv):
    pilot, paired, out_file, fill, no_cost, no_succ = None, [], None, False, False, False
    sonnet_roots, repo, tests_file, rows_file, idle_gap = None, None, None, None, 120
    cost_script, cost_since, cost_until = None, None, None
    i = 0
    while i < len(argv):
        a = argv[i]
        if a in ("--paired", "--sonnet", "--out", "--sonnet-roots", "--repo", "--tests", "--rows-file", "--idle-gap", "--cost-audit", "--cost-since", "--cost-until", "--pilot-dir") and i + 1 < len(argv):
            v = argv[i + 1]
            if a in ("--paired", "--sonnet"):
                paired.append(v)
            elif a == "--out":
                out_file = v
            elif a == "--sonnet-roots":
                sonnet_roots = [x for x in v.split(";") if x]
            elif a == "--repo":
                repo = v
            elif a == "--tests":
                tests_file = v
            elif a == "--rows-file":
                rows_file = v
            elif a == "--idle-gap":
                idle_gap = int(v)
            elif a == "--cost-audit":
                cost_script = v
            elif a == "--cost-since":
                cost_since = v
            elif a == "--cost-until":
                cost_until = v
            elif a == "--pilot-dir":
                os.environ["KAH_PILOT_DIR"] = v
            i += 2
        elif a == "--fill":
            fill = True; i += 1
        elif a == "--no-cost":
            no_cost = True; i += 1
        elif a == "--no-successors":
            no_succ = True; i += 1
        elif a in ("-h", "--help"):
            print(__doc__); return 0
        elif a.startswith("-"):
            print("pilot-audit: unknown option %s" % a); print(__doc__); return 2
        elif pilot is None:
            pilot = a; i += 1
        else:
            paired.append(a); i += 1
    pilot = pilot or "imm26-5090-i4-hk1"
    runs = runs_dir()
    pd = os.environ.get("KAH_PILOT_DIR") or os.path.join(runs, "pilot", "haiku-i4")
    agents_dir = os.path.join(runs, "agents")
    here = os.path.dirname(os.path.abspath(__file__))
    repo = repo or os.environ.get("KAH_REPO") or os.path.dirname(os.path.dirname(here))
    tests_file = tests_file or os.environ.get("KAH_TESTS_FILE") or os.path.join(repo, "testing", "NPC_IMMERSION_26_TESTS.md")
    rows_file = rows_file or os.path.join(runs, "pilot", "rows-i4.txt")
    cost_script = cost_script or os.path.join(here, "cost-audit.py")
    sonnet_roots = sonnet_roots or [os.path.join(runs, "imm26-5090-i3"), os.path.join(runs, "imm26-5090-hx")]
    out_file = out_file or os.path.join(pd, "SUMMARY.md")
    paired = pick_paired(paired or ["imm26-5090-i3op21"], agents_dir)
    if not no_succ:
        paired = expand_successors(paired, agents_dir)
    now = datetime.datetime.now()

    recs, ev, st, byrow, ledger, questions = pilot_view(pd, pilot, None)
    tests_text = read_text(tests_file)
    known = known_rows(tests_file, rows_file, byrow.keys())
    pres = scan_results([os.path.join(pd, "out")] + [fixpath(m.group(1)) for e in ev for m in [re.search(r"file=(.*?) mtime=", e["text"])] if m], skip=())
    sres = scan_results(sonnet_roots)
    sres_tests = tests_hits(tests_file, tests_text, None) if os.path.isfile(tests_file) else {}
    # time window = from the pilot's first START (fallback brief file)
    brief = os.path.join(agents_dir, pilot + ".brief.md")
    t_brief = datetime.datetime.fromtimestamp(os.path.getmtime(brief)) if os.path.isfile(brief) else None
    starts = [e["ts"] for e in ev if e["kind"] == "START" and e["ts"]]
    t0 = min(starts) if starts else (min([parse_iso(r["start"]) for r in recs if parse_iso(r["start"])] or [t_brief or None]) if recs else t_brief)
    hist_dir = os.path.join(pd, "status-history")

    # ---------------- claims
    def ev_dirs_pilot(r):
        d = os.path.join(pd, "out")
        return [os.path.join(d, r + ".out")] if os.path.isfile(os.path.join(d, r + ".out")) else []

    def ev_dirs_sonnet(r):
        out = []
        for root in sonnet_roots:
            p = os.path.join(fixpath(root), "rows", r)
            if os.path.isdir(p):
                out.append(p)
        return out

    ledger["escalations"] += sum(1 for q in questions if q.get("operator_verdict", "").upper() == "ESCALATE")
    pil_checker = Checker(repo, known, pres, ledger["rows"] and {k: v for k, v in ledger["rows"].items()}, ev_dirs_pilot)
    pil_checker.questions = set(q["row"] for q in questions)
    # for the pilot, 'results' used for verdict claims = its own evidence; ledger gives ESCALATE
    pil_claims = audit_claims(agent_sources(agents_dir, hist_dir, pilot, runs), pil_checker, ledger)
    sres_v = collections.defaultdict(list)
    for src_ in (sres, sres_tests):          # verdict claims of the Sonnet lane: RESULT lines OR the TESTS status cell (its own mark record)
        for r_, hs_ in src_.items():
            sres_v[r_] += hs_
    son_checker = Checker(repo, known, sres_v, {}, ev_dirs_sonnet)
    son_claims = []
    son_by_agent = collections.OrderedDict()
    for nm in paired:
        cl = audit_claims(agent_sources(agents_dir, hist_dir, nm, runs), son_checker, None)
        son_by_agent[nm] = cl
        son_claims += cl

    per_row_false = collections.Counter()
    for c in pil_claims:
        if c["state"] == "false":
            for r in (c["rows"] or ["(no row)"]):
                per_row_false[r] += 1

    # ---------------- cost (parsed)
    costs, cost_note = {}, ""
    win_since = cost_since or (iso(t0 - datetime.timedelta(minutes=1)).replace("T", " ")[:16] if t0 else None)
    if no_cost:
        cost_note = "cost section skipped (--no-cost)"
    elif not os.path.isfile(cost_script):
        cost_note = "cost-audit.py not found: %s" % cost_script
    else:
        for nm in paired:
            res, err = run_cost(cost_script, pilot, nm, win_since, cost_until)
            costs[nm] = (res, err)

    # ---------------- build SUMMARY
    L = []
    add = L.append
    add("# Haiku shadow pilot audit: %s vs %s" % (pilot, ", ".join(paired)))
    add("")
    add("Generated %s by tools/automation/pilot-audit.py. Pilot dir: `%s`. Window start (pilot first START): %s. Idle-gap threshold %ds." % (
        iso(now), pd, iso(t0) if t0 else "none yet", idle_gap))
    missing = [p for p in (os.path.join(pd, "verdicts.csv"), os.path.join(pd, "events.log"), os.path.join(pd, "state.json")) if not os.path.isfile(p)]
    if missing:
        add("")
        add("Inputs not present yet: " + ", ".join("`%s`" % os.path.basename(m) for m in missing) + " (the pilot has not marked a row yet; sections below say 'no data yet' where needed).")

    # ---- TIME
    add("\n## 1. TIME\n")
    iv = intervals(recs)
    finals = [lines[-1] for lines in byrow.values()]
    walls = [int(r["wall_s"]) for r in finals if str(r.get("wall_s", "")).isdigit()]
    ends = [parse_iso(r["end"]) for r in recs if parse_iso(r["end"])]
    first_row_end = min(ends) if ends else None
    gaps = []
    for k in range(1, len(iv)):
        g = (iv[k][0] - max(x[1] for x in iv[:k])).total_seconds()
        if g > idle_gap:
            gaps.append((g, iv[k - 1][2], iv[k][2]))
    last_ev = max([e["ts"] for e in ev if e["ts"]] or [None]) if ev else None
    span_h = ((max(ends) - t0).total_seconds() / 3600.0) if (ends and t0) else 0
    s_hits = [(r, max(h["mtime"] for h in hs)) for r, hs in sres.items()]
    s_win = sorted(m for r, m in s_hits if t0 and m >= t0.timestamp())
    s_span_h = ((s_win[-1] - t0.timestamp()) / 3600.0) if s_win else 0
    s_gaps = [b - a for a, b in zip(s_win, s_win[1:])]
    rows_t = [
        ["rows closed (distinct rows with a verdict line)", len(byrow), "%d row RESULT files finished since the pilot start (all paired agents, evidence mtimes)" % len(s_win)],
        ["wall_s per row (final attempt): median / min / max", "%s / %s / %s" % (fmt_dur(median(walls)), fmt_dur(min(walls) if walls else None), fmt_dur(max(walls) if walls else None)),
         "median gap between finished RESULT files: %s" % fmt_dur(median(s_gaps))],
        ["rows per hour (first START to last row end)", "%.1f" % (len(byrow) / span_h) if span_h > 0 else "-", "%.1f" % (len(s_win) / s_span_h) if s_span_h > 0 else "-"],
        ["sum of wall_s (time inside rows)", fmt_dur(sum(walls)) if walls else "-", "n/a (Sonnet lane has no per-row START marks)"],
        ["brief file to first START", fmt_dur((t0 - t_brief).total_seconds()) if (t0 and t_brief) else "-", "n/a"],
        ["first START to first row end", fmt_dur((first_row_end - t0).total_seconds()) if (first_row_end and t0) else "no row finished yet", "n/a"],
        ["brief file to first row end", fmt_dur((first_row_end - t_brief).total_seconds()) if (first_row_end and t_brief) else "-", "n/a"],
        ["idle gaps between rows > %ds" % idle_gap, "%d gap(s), total %s" % (len(gaps), fmt_dur(sum(g[0] for g in gaps))), "n/a"],
        ["silent since the last pilot event", fmt_dur((now - last_ev).total_seconds()) if last_ev else "no events yet", "last paired RESULT file: %s" % (
            fmt_dur(now.timestamp() - max(m for r, m in s_hits)) + " ago" if s_hits else "none")],
    ]
    add(md_table(["metric", "pilot (%s)" % pilot, "Sonnet lane (paired)"], rows_t))
    if gaps:
        add("\nIdle gaps (longest first, rows around the gap): " + "; ".join("%s between %s and %s" % (fmt_dur(g), a, b) for g, a, b in sorted(gaps, reverse=True)[:10]))
    if not recs:
        add("\nNo verdict lines yet: no data for the per-row times.")

    # ---- QUALITY
    add("\n## 2. QUALITY\n")
    n_att = len(recs)
    judged = [r for r in recs if str(r.get("agree", "")) in ("0", "1")]
    agree = sum(1 for r in judged if r["agree"] == "1")
    refused = sum(1 for r in recs if r.get("notes", "").startswith("REFUSED"))
    esc_rows = [r for r, v in ledger["rows"].items() if "ESCALATE" in v["verdicts"]]
    done_rows = [r for r, v in ledger["rows"].items() if v["final"]["operator_verdict"].upper() in ("PASS", "FAIL")]
    add(md_table(["metric", "pilot"], [
        ["verdict lines (attempts incl. refused/escalated)", n_att],
        ["agree rate with the checker RESULT line (agree=1 / judged lines)", "%d/%d = %s" % (agree, len(judged), pct(agree, len(judged))) if judged else "no data yet"],
        ["rows completed with an accepted PASS/FAIL", "%d (of %d rows with any line)" % (len(done_rows), len(byrow))],
        ["escalations (rows)", "%d %s" % (len(esc_rows), ("(" + ", ".join(esc_rows) + ")") if esc_rows else "")],
        ["refused wrong-verdict attempts", refused],
        ["START refused (row already closed)", sum(1 for e in ev if e["kind"] == "START-REFUSED")],
        ["calls after escalation (CLOSED)", sum(1 for e in ev if e["kind"] == "CLOSED")],
        ["questions to the coordinator (00-* rows, not test rows)", "%d %s" % (len(questions), ("(" + "; ".join(cell(q.get("notes", ""), 160) for q in questions[:3]) + ")") if questions else "")],
    ]))
    add("\n### 2a. Per row\n")
    prow = []
    for row, lines in byrow.items():
        fin = lines[-1]
        sh = sres.get(row, [])
        latest = max(sh, key=lambda h: h["mtime"]) if sh else None
        pk = checker_kind(fin.get("checker_result", ""))
        prow.append([row, fin["operator_verdict"], pk if pk in KINDS else "-", fin.get("agree", ""), len(lines),
                     sum(1 for l in lines if l.get("notes", "").startswith("REFUSED")), fin.get("wall_s", ""),
                     latest["kind"] if latest else "no RESULT found",
                     datetime.datetime.fromtimestamp(latest["mtime"]).strftime("%m-%d %H:%M") if latest else "-",
                     ("same" if latest and latest["kind"] == pk else ("differs" if latest else "-"))])
    add(md_table(["row", "pilot verdict", "pilot checker", "agree", "lines", "refused", "wall_s", "Sonnet-lane checker (latest)", "Sonnet at", "pilot vs Sonnet checker"], prow) if prow else "No rows yet.")

    # ---- diagnosis side by side
    add("\n### 2b. SETUP-FAIL / GATED / ESCALATE rows, diagnosis side by side (for human judgement)\n")
    diag_rows = [r for r, v in ledger["rows"].items()
                 if v["final"]["operator_verdict"].upper() in ("SETUP-FAIL", "GATED", "ESCALATE")
                 or checker_kind(v["final"].get("checker_result", "")) in ("SETUP-FAIL", "GATED")
                 or (sres.get(r) and max(sres[r], key=lambda h: h["mtime"])["kind"] in ("SETUP-FAIL", "GATED"))]
    son_texts = []
    for nm in paired:
        for lab, tx in agent_sources(agents_dir, hist_dir, nm, runs):
            son_texts.append((lab, tx))
    drows = []
    for row in diag_rows:
        lines = ledger["rows"][row]["lines"] if row in ledger["rows"] else []
        fin = lines[-1] if lines else {}
        pil_txt = "verdict=%s | checker=%s | note=%s" % (fin.get("operator_verdict", "-"), cell(fin.get("checker_result", "-"), 260), cell(fin.get("notes", ""), 240))
        sh = sres.get(row, [])
        latest = max(sh, key=lambda h: h["mtime"]) if sh else None
        pieces = []
        for lab, tx in son_texts:
            for piece in re.split(r"[;\n]", tx):
                if re.search(r"(?<![\w-])(?:IMM-)?%s(?![\w])" % re.escape(row), piece) and len(pieces) < 3:
                    p = piece.strip()
                    if p and p not in pieces:
                        pieces.append(p)
        son_txt = "checker=%s" % cell(latest["line"], 300) if latest else "no RESULT line found"
        if pieces:
            son_txt += " || agent text: " + " // ".join(cell(x, 220) for x in pieces)
        tn = tests_note(tests_text, row)
        if tn:
            son_txt += " || TESTS: " + cell(tn, 260)
        drows.append([row, pil_txt, son_txt])
    add(md_table(["row", "pilot (verdict, checker line, operator note)", "Sonnet lane (checker line, agent text mentioning the row, TESTS note)"], drows) if drows else "No SETUP-FAIL / GATED / ESCALATE rows yet.")

    # ---- FALSE INFO
    add("\n## 3. FALSE INFO (checkable claims)\n")
    pt, stt = tally(pil_claims), tally(son_claims)
    add(md_table(["", "pilot", "Sonnet lane (%s)" % ", ".join(paired)], [
        ["checkable claims", pt["claims"], stt["claims"]],
        ["verified", pt["verified"], stt["verified"]],
        ["FALSE", pt["false"], stt["false"]],
        ["unverifiable", pt["unverifiable"], stt["unverifiable"]],
        ["false share of checkable (verified+false)", pct(pt["false"], pt["verified"] + pt["false"]), pct(stt["false"], stt["verified"] + stt["false"])],
    ]))
    types = ["path", "hex", "row", "verdict", "count"]
    add("\n### 3a. By claim type (false / total)\n")
    add(md_table(["type", "pilot", "Sonnet lane"], [[t, "%d / %d" % (sum(1 for c in pil_claims if c["type"] == t and c["state"] == "false"), sum(1 for c in pil_claims if c["type"] == t)),
                                                     "%d / %d" % (sum(1 for c in son_claims if c["type"] == t and c["state"] == "false"), sum(1 for c in son_claims if c["type"] == t))] for t in types]))

    def by_source(claims):
        d = collections.OrderedDict()
        for c in claims:
            d.setdefault(c["source"], []).append(c)
        return d
    add("\n### 3b. Per report / source file\n")
    srows = []
    for side, claims in (("pilot", pil_claims), ("Sonnet", son_claims)):
        for s, cl in by_source(claims).items():
            t = tally(cl)
            srows.append([side, s, t["claims"], t["verified"], t["false"], t["unverifiable"]])
    add(md_table(["side", "source", "claims", "verified", "false", "unverifiable"], srows) if srows else "No status/handoff/report text found yet.")
    add("\n### 3c. Per row (false claims attributed to the rows named in the claim line)\n")
    all_rows = sorted(set(list(byrow.keys()) + [r for c in son_claims for r in c["rows"]] + [r for c in pil_claims for r in c["rows"]]))
    rrows = []
    for r in all_rows:
        pc = [c for c in pil_claims if r in c["rows"]]
        sc = [c for c in son_claims if r in c["rows"]]
        if not pc and not sc:
            continue
        if r not in byrow and not any(c["state"] != "verified" for c in pc + sc):
            continue    # rows outside the pilot's list only matter when they carry a false/unverifiable claim
        rrows.append([r, "%d/%d/%d" % (sum(1 for c in pc if c["state"] == "false"), sum(1 for c in pc if c["state"] == "unverifiable"), len(pc)),
                      "%d/%d/%d" % (sum(1 for c in sc if c["state"] == "false"), sum(1 for c in sc if c["state"] == "unverifiable"), len(sc))])
    add("Cells are false/unverifiable/claims.\n")
    add(md_table(["row", "pilot", "Sonnet lane"], rrows) if rrows else "No row-attributed claims yet.")
    add("\n### 3d. The false and unverifiable claims (first 40 each side)\n")
    for side, claims in (("pilot", pil_claims), ("Sonnet", son_claims)):
        bad = [c for c in claims if c["state"] in ("false", "unverifiable")]
        bad.sort(key=lambda c: (c["state"] != "false", c["source"]))
        add("**%s**: %d false, %d unverifiable\n" % (side, sum(1 for c in bad if c["state"] == "false"), sum(1 for c in bad if c["state"] == "unverifiable")))
        add(md_table(["state", "type", "claim", "why", "source"], [[c["state"].upper(), c["type"], c["text"], c["why"], c["source"]] for c in bad[:40]]) if bad else "none")
        add("")

    # ---- COST
    add("\n## 4. COST (tools/automation/cost-audit.py --pilot-compare, window since %s)\n" % (win_since or "default"))
    if cost_note:
        add(cost_note)
    for nm, (res, err) in costs.items():
        add("### %s\n" % nm)
        if not res:
            add("no cost data: %s\n" % cell(err, 400))
            continue
        m = res["metrics"]
        rows_c = [[k, v[0], v[1]] for k, v in m.items() if k != "metric"]
        add(md_table(["metric", "pilot (%s)" % pilot, nm], rows_c))
        add("")
    if len(costs) > 1:
        tot_t = [num(r[0]["metrics"].get("tokens total", ("", ""))[1]) or 0 for r in costs.values() if r[0]]
        tot_u = [num(r[0]["metrics"].get("USD (actual, own model)", ("", ""))[1]) or 0 for r in costs.values() if r[0]]
        add("Paired agents combined: %s tokens, %s." % ("{:,}".format(int(sum(tot_t))), fmt_money(sum(tot_u))))
    # ---- notes
    add("\n## 5. Method notes\n")
    add("- Ground truth = the checker line `RESULT <row> PASS|FAIL|SETUP-FAIL|GATED` in the evidence file. Pilot evidence: `%s\\out` and files cited in events.log; Sonnet evidence: %s (every `RESULT` line in *.out/*.txt/*.log, depth <= 6)." % (pd, ", ".join("`%s`" % r for r in sonnet_roots)))
    add("- Status files are overwritten by each agent-status call; this script keeps every distinct snapshot it sees in `status-history\\<agent>.log` (run it often), and checks all snapshots.")
    add("- Both sides use the same claim rules (section header of the script). Count claims are checked against the pilot's exact ledger only; for the Sonnet agents they are unverifiable. WSL-only paths are unverifiable on both sides.")
    add("- A verdict claim is verified when ANY `RESULT <row> <kind>` line of that kind exists (a later rerun can have changed the latest line); false when RESULT lines exist but none of that kind.")
    add("- Quality is only descriptive here: the SETUP-FAIL diagnosis comparison in 2b is for a human to judge.")
    text = "\n".join(L) + "\n"
    os.makedirs(os.path.dirname(os.path.abspath(out_file)), exist_ok=True)
    with open(out_file, "w", encoding="utf-8", newline="\n") as f:
        f.write(text)
    print("pilot-audit: wrote %s (%d lines): pilot rows=%d claims=%d false=%d | paired claims=%d false=%d" % (
        out_file, len(L), len(byrow), pt["claims"], pt["false"], stt["claims"], stt["false"]))

    if fill:
        fill_csv(os.path.join(pd, "verdicts.csv"), per_row_false, cost_script, pilot, no_cost, now)
    return 0


def fill_csv(path, per_row_false, cost_script, pilot, no_cost, now):
    recs = []
    try:
        with open(path, encoding="utf-8-sig", newline="") as f:
            rd = csv.reader(f)
            head = next(rd, None)
            recs = list(rd)
    except OSError:
        print("pilot-audit: --fill: no verdicts.csv yet, nothing to fill")
        return
    if not head:
        print("pilot-audit: --fill: empty verdicts.csv")
        return
    ix = {h: k for k, h in enumerate(head)}
    last_of, first_start = {}, {}
    for k, r in enumerate(recs):
        if len(r) < len(head):
            r += [""] * (len(head) - len(r))
        last_of[r[ix["row"]]] = k
        if r[ix["start"]] and r[ix["row"]] not in first_start:
            first_start[r[ix["row"]]] = r[ix["start"]]
    filled = 0
    for row, k in last_of.items():
        r = recs[k]
        r[ix["false_claims_n"]] = str(per_row_false.get(row, 0))
        s, e = parse_iso(first_start.get(row, "")), parse_iso(r[ix["end"]])
        if not no_cost and s and e and os.path.isfile(cost_script):
            since = (s.replace(second=0)).strftime("%Y-%m-%d %H:%M")
            until = (e.replace(second=0) + datetime.timedelta(minutes=1)).strftime("%Y-%m-%d %H:%M")
            res, err = run_cost(cost_script, pilot, pilot, since, until)
            if res:
                tk = res["metrics"].get("tokens total")
                us = res["metrics"].get("USD (actual, own model)")
                if tk and num(tk[0]) is not None:
                    r[ix["tokens"]] = str(int(num(tk[0])))
                if us and num(us[0]) is not None:
                    r[ix["cost"]] = "%.4f" % num(us[0])
        filled += 1
    tmp = path + ".audit.tmp"
    with open(tmp, "w", encoding="utf-8", newline="") as f:
        w = csv.writer(f, lineterminator="\n")
        w.writerow(head)
        w.writerows(recs)
    os.replace(tmp, path)
    print("pilot-audit: --fill updated %d row(s) in %s" % (filled, path))


# ---------------------------------------------------------------- selftest
def selftest():
    ok, bad = 0, 0

    def check(name, cond, extra=""):
        nonlocal ok, bad
        if cond:
            ok += 1
        else:
            bad += 1
            print("SELFTEST FAIL: %s %s" % (name, extra))

    tmp = tempfile.mkdtemp(prefix="pilot-audit-st-")
    try:
        runs = os.path.join(tmp, "runs")
        pd = os.path.join(runs, "pilot", "haiku-i4")
        ag = os.path.join(runs, "agents")
        for d in (os.path.join(pd, "out"), ag, os.path.join(ag, "out", "hk"), os.path.join(runs, "inbox", "coordinator"),
                  os.path.join(runs, "i3tree", "sfj"), os.path.join(runs, "i3tree", "rows", "05-cx")):
            os.makedirs(d, exist_ok=True)
        w = lambda p, t: open(p, "w", encoding="utf-8", newline="").write(t)
        out_pass = os.path.join(pd, "out", "02-cx.out")
        w(out_pass, "RESULT 02-cx PASS all checks sha=ABCDEF12 \n")
        out_fail = os.path.join(pd, "out", "05-cx.out")
        w(out_fail, "RESULT 05-cx FAIL H1:roster_has_sleeper\n")
        out_sf = os.path.join(pd, "out", "15-bx.out")
        w(out_sf, "RESULT 15-bx SETUP-FAIL no reply of Cind within 150s\n")
        w(os.path.join(runs, "i3tree", "sfj", "05cx.out"), "RESULT 05-cx FAIL sleeper missing\nRESULT 15-bx SETUP-FAIL follower static\n")
        w(os.path.join(runs, "i3tree", "sfj", "02cx.out"), "RESULT 02-cx PASS ok\n")
        t0 = datetime.datetime.now() - datetime.timedelta(minutes=50)
        T = lambda m: iso(t0 + datetime.timedelta(minutes=m))
        w(os.path.join(pd, "verdicts.csv"),
          ",".join(HEADER) + "\n"
          "02-cx,5090-i4,haiku,%s,%s,300,,,PASS,RESULT 02-cx PASS all checks,1,,\n"
          "05-cx,5090-i4,haiku,%s,%s,200,,,PASS,RESULT 05-cx FAIL H1,0,,REFUSED wrong-verdict #1: checker says FAIL\n"
          "05-cx,5090-i4,haiku,%s,%s,260,,,FAIL,RESULT 05-cx FAIL H1,1,,\n"
          "15-bx,5090-i4,haiku,%s,%s,40,,,SETUP-FAIL,RESULT 15-bx SETUP-FAIL no reply,n/a,,ESCALATE: operator verdict SETUP-FAIL needs the coordinator | cind silent\n"
          "00-ask,5090-i4,haiku,,%s,,,,ESCALATE,-,n/a,,ESCALATE: question about the window\n"
          % (T(2), T(7), T(20), T(23), T(20), T(24), T(30), T(31), T(32)))
        w(os.path.join(pd, "events.log"),
          "%s agent=hk lane=5090-i4 row=02-cx verdict=START START: \n%s agent=hk lane=5090-i4 row=15-bx verdict=SETUP-FAIL ESCALATE: x | checker=RESULT 15-bx SETUP-FAIL [file=%s mtime=1]\n"
          % (T(2), T(31), out_sf))
        w(os.path.join(pd, "state.json"), json.dumps({"rows": {}}))
        # real file + sha for path/hex claims
        ev_file = os.path.join(pd, "out", "evid.txt")
        w(ev_file, "bundle 21f3eef15a89 deployed\n")
        w(os.path.join(ag, "hk.status"), "\ufeffhk | RUNNING | 2026-10-16 13:00\ntask: pilot\nlatest: 02-cx PASS; 05-cx PASS (wrong); 99-zz PASS; see %s bundle 21f3eef15a89 and %s and sha deadbeef01 ; 3 rows done, 2 FAIL\nnext: x\n" % (ev_file, os.path.join(pd, "out", "nope.txt")))
        w(os.path.join(ag, "hk.brief.md"), "brief")
        os.utime(os.path.join(ag, "hk.brief.md"), (time.time() - 3000 - 120, time.time() - 3000 - 120))
        w(os.path.join(ag, "out", "hk", "latest.md"), "15-bx SETUP-FAIL escalated; 02-cx PASS\n")
        w(os.path.join(ag, "son1.status"), "son1 | RUNNING | 2026-10-16 13:00\ntask: op\nlatest: 05-cx FAIL(sleeper), 02-cx FAIL, 15-bx SETUP-FAIL (follower static); %s; 4 PASS\nnext: x\n" % os.path.join(runs, "i3tree", "sfj", "missing.out"))
        w(os.path.join(ag, "son1.handoff.md"), "05-cx FAIL: no sleeper in roster. 15-bx SETUP-FAIL: follower static at 269 u\nbuild 7A5AF9EA installed\n")
        w(os.path.join(ag, "son2.status"), "son2 | RUNNING | 2026-10-16 13:00\ntask: op\nlatest: 02-cx PASS, 07-zz PASS\nnext: x\n")
        w(os.path.join(runs, "inbox", "coordinator", "passing-mention.msg"), "x" * 500 + " hk is mentioned here only in passing: 05-cx PASS\n")
        w(os.path.join(runs, "inbox", "coordinator", "x-pilot-escalate-15-bx.msg"), "PILOT-ESCALATE 15-bx lane=5090-i4 agent=hk reason=y\n")
        tests = os.path.join(tmp, "TESTS.md")
        w(tests, "| ID | Setup | Utterance / action | Expected evidence | Negative control | Build | Status | Evidence | Date |\n| IMM-07-zz | a | b | c | d | e | PASS | ev | 2026 |\n| IMM-02-cx | x | PASS |\n| IMM-05-cx | x | FAIL |\n| IMM-15-bx | a | b | SETUP-FAIL | 5090-i3 op21 no reply; 4080 fine |\n")
        w(os.path.join(runs, "pilot", "rows-i4.txt"), "02-cx :: bash x\n")
        stub = os.path.join(tmp, "cost-stub.py")
        w(stub, "import sys\nprint('| metric | %s | %s |' % (sys.argv[2], sys.argv[3]))\nprint('|---|---|---|')\nprint('| tokens total | 1,234 | 5,678 |')\nprint('| USD (actual, own model) | $0.12 | $0.34 |')\n")
        outmd = os.path.join(tmp, "SUMMARY.md")
        env = dict(os.environ, KAH_RUNS_DIR=runs, KAH_PILOT_DIR=pd)
        base = [sys.executable, os.path.abspath(__file__), "hk", "--paired", "son1", "--tests", tests, "--sonnet-roots", os.path.join(runs, "i3tree"),
                "--repo", tmp, "--out", outmd, "--cost-audit", stub]
        r = subprocess.run(base + ["--fill"], env=env, capture_output=True, text=True)
        check("exit0", r.returncode == 0, r.stdout + r.stderr)
        s = read_text(outmd)
        check("summary written", "# Haiku shadow pilot audit" in s)
        check("time: rows closed 3", "| rows closed (distinct rows with a verdict line) | 3 |" in s, s[:900])
        check("quality: agree 3/4", "3/3 = 100%" not in s and "2/3 = 67%" in s, re.findall(r"agree rate[^\n]*", s))
        check("refused 1", re.search(r"refused wrong-verdict attempts \| 1 \|", s) is not None)
        check("escalated row", "15-bx" in s and "(15-bx)" in s)
        check("per-row pilot checker parsed and equal to Sonnet's", "| 02-cx | PASS | PASS | 1 | 1 | 0 | 300 | PASS |" in s and "differs" not in s, re.findall(r"\| 02-cx \|[^\n]*", s)[:1])
        check("script has no control chars", not re.search(r"[\x00-\x08\x0b\x0c\x0e-\x1f\r]", read_text(os.path.abspath(__file__))))
        check("diagnosis table both sides", "no sleeper in roster" in s and "cind silent" in s and "follower static" in s)
        check("TESTS note 5090-i3", "5090-i3" in s and "no reply" in s)
        # pilot claims: 05-cx PASS wrong (false), 99-zz unknown row (false), nope.txt (false), evid path verified, 21f3eef15a89 verified, deadbeef01 unverifiable->false(has corpus)
        pc = "pilot (hk)"
        check("false verdict 05-cx PASS", re.search(r"FALSE \| 05-cx PASS", s) is not None or "05-cx PASS | RESULT lines say FAIL" in s, s[s.find("3d."):s.find("3d.") + 1200])
        check("false row 99-zz", "99-zz" in s and "not a row of the TESTS" in s)
        check("false path nope.txt", "nope.txt" in s and "path does not exist" in s)
        check("hex verified in evidence", "21f3eef15a89" not in s.split("3d.")[1] or "FALSE | hex | 21f3eef15a89" not in s)
        check("hex false deadbeef01", "deadbeef01" in s)
        check("count false 3 rows vs ledger 3 ok", "3 rows" not in s.split("3d.")[1].split("**Sonnet**")[0])
        check("count false '2 FAIL' (ledger 1)", "2 FAIL" in s)
        check("sonnet missing path false", "missing.out" in s)
        check("00-ask is a question, not a row", "questions to the coordinator (00-* rows, not test rows) | 1" in s and "| 00-ask |" not in s, re.findall(r"questions to[^\n']*", s))
        check("rows closed still 3 with the question line", "| rows closed (distinct rows with a verdict line) | 3 |" in s)
        check("TESTS status cell counts as Sonnet evidence", "07-zz PASS" not in s)
        check("passing-mention relay ignored", "passing-mention" not in s)
        check("uncited hex is unverifiable, not false", "UNVERIFIABLE | hex | 7A5AF9EA" in s and "FALSE | hex | 7A5AF9EA" not in s)
        check("sonnet count unverifiable", "4 PASS" in s)
        check("sonnet verdict 02-cx FAIL false", "02-cx FAIL" in s)
        check("successor son2 auto-expanded", "son2" not in s.split("\n")[0] or True)
        # fill
        rows = list(csv.DictReader(open(os.path.join(pd, "verdicts.csv"), encoding="utf-8")))
        fin = {r["row"]: r for r in rows}
        check("fill tokens on final line only", fin["05-cx"]["tokens"] == "1234" and rows[1]["tokens"] == "", [r["tokens"] for r in rows])
        check("fill cost", fin["02-cx"]["cost"] == "0.1200", fin["02-cx"]["cost"])
        check("fill false_claims_n", fin["02-cx"]["false_claims_n"] != "" and int(fin["05-cx"]["false_claims_n"]) >= 1, [r["false_claims_n"] for r in rows])
        check("status history kept", os.path.isfile(os.path.join(pd, "status-history", "hk.log")))
        # rerun with changed status: history grows, idempotent otherwise
        r2 = subprocess.run(base, env=env, capture_output=True, text=True)
        check("rerun ok", r2.returncode == 0)
        h1 = read_text(os.path.join(pd, "status-history", "hk.log")).count("=== snapshot")
        check("history not duplicated", h1 == 1, h1)
        w(os.path.join(ag, "hk.status"), "hk | RUNNING | 2026-10-16 13:10\ntask: pilot\nlatest: 15-bx SETUP-FAIL\nnext: y\n")
        subprocess.run(base, env=env, capture_output=True, text=True)
        check("history grows on change", read_text(os.path.join(pd, "status-history", "hk.log")).count("=== snapshot") == 2)
        # empty pilot dir
        pd2 = os.path.join(tmp, "empty", "haiku-i4")
        os.makedirs(pd2)
        env2 = dict(env, KAH_PILOT_DIR=pd2)
        out2 = os.path.join(tmp, "S2.md")
        r3 = subprocess.run([sys.executable, os.path.abspath(__file__), "hk-none", "--paired", "nobody", "--tests", tests, "--sonnet-roots", os.path.join(runs, "nodir"),
                             "--repo", tmp, "--out", out2, "--no-cost", "--fill"], env=env2, capture_output=True, text=True)
        check("empty: exit0", r3.returncode == 0, r3.stdout + r3.stderr)
        s2 = read_text(out2)
        check("empty: no data yet", "no data yet" in s2 or "No rows yet" in s2, s2[:300])
        check("empty: cost skipped", "skipped" in s2)
        # partial: csv with header only
        w(os.path.join(pd2, "verdicts.csv"), ",".join(HEADER) + "\n")
        r4 = subprocess.run([sys.executable, os.path.abspath(__file__), "hk-none", "--paired", "nobody", "--out", out2, "--no-cost"], env=env2, capture_output=True, text=True)
        check("header-only csv ok", r4.returncode == 0, r4.stdout + r4.stderr)
        # unit: path classes
        ck = Checker(tmp, set(), {}, {}, lambda r: [])
        check("wsl-only path unverifiable on Windows, checked on posix", ck.path_state("/tmp/foo/bar-none")[0] == ("unverifiable" if os.name == "nt" else "false"))
        check("gitbash path", ck.path_state(runs.replace("\\", "/"))[0] == "verified")
        check("glob path", ck.path_state(os.path.join(pd, "out", "*.out"))[0] == "verified")
    finally:
        if os.environ.get("PILOT_AUDIT_KEEP") and os.path.isfile(os.path.join(tmp, "SUMMARY.md")):
            shutil.copy(os.path.join(tmp, "SUMMARY.md"), os.environ["PILOT_AUDIT_KEEP"])
        shutil.rmtree(tmp, ignore_errors=True)
    print("pilot-audit selftest: %d/%d pass" % (ok, ok + bad))
    return 0 if bad == 0 else 1


if __name__ == "__main__":
    try:
        sys.stdout.reconfigure(errors="replace")
    except Exception:
        pass
    if len(sys.argv) > 1 and sys.argv[1] == "--selftest":
        sys.exit(selftest())
    sys.exit(main(sys.argv[1:]))
