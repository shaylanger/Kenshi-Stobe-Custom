#!/usr/bin/env python3
"""ab2_lib.py: shared code of the controlled pilot-2 kit (Haiku High vs Sonnet High on the SAME rows, SAME lane 5090-i4).
Data dir (AB2_DIR, default C:/KenshiTestRuns/pilot/ab2): queue.txt, plan.json (frozen), state.json, captures.jsonl, RUNNING (lock dir), ACTIVE,
<arm>/ (verdicts.csv, events.log, state.json, out/<ROW>.out, evidence/<ROW>, bundles/) for arm in haiku, sonnet.
Shadow only: nothing here touches claims, the TESTS file, tickets or git.
"""
import os, re, sys, json, glob, time, hashlib, subprocess, datetime

HERE = os.path.dirname(os.path.abspath(__file__))
ARMS = ("haiku", "sonnet")
MODEL_OF = {"haiku": "haiku", "sonnet": "sonnet"}
LANE = "5090-i4"


def norm(p):
    return p.replace("\\", "/")


def runs_dir():
    d = os.environ.get("KAH_RUNS_DIR")
    if d:
        return norm(d)
    for c in ("C:/KenshiTestRuns", "/c/KenshiTestRuns", "/mnt/c/KenshiTestRuns"):
        if os.path.isdir(c):
            return c
    return "C:/KenshiTestRuns"


def ab2_dir():
    return norm(os.environ.get("AB2_DIR") or runs_dir() + "/pilot/ab2")


def repo_dir():
    d = os.environ.get("AB2_REPO")
    if d:
        return norm(d)
    return norm(os.path.abspath(os.path.join(HERE, "..", "..", ".."))) if os.path.isdir(os.path.join(HERE, "..", "..", "..", "testing")) else "C:/KenshiModding"


def assert_dir():
    return norm(os.environ.get("AB2_ASSERT") or repo_dir() + "/testing/live-stobe-queue/imm26-assert")


def now_iso():
    return datetime.datetime.now().strftime("%Y-%m-%dT%H:%M:%S")


def read_json(p, default=None):
    try:
        with open(p, encoding="utf-8") as f:
            return json.load(f)
    except Exception:
        return default


def write_json(p, obj):
    tmp = p + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(obj, f, indent=1)
    os.replace(tmp, p)


def append_jsonl(p, obj):
    with open(p, "a", encoding="utf-8") as f:
        f.write(json.dumps(obj, separators=(",", ":")) + "\n")


# ---------------------------------------------------------------- queue / plan
def parse_queue(path=None):
    """[(row, template)] from queue.txt lines `ROW :: command` (placeholders {ARM} {OUT})."""
    path = path or ab2_dir() + "/queue.txt"
    out = []
    with open(path, encoding="utf-8") as f:
        for ln in f:
            ln = ln.rstrip("\r\n")
            if not ln.strip() or ln.lstrip().startswith("#"):
                continue
            m = re.match(r"^(\d{2}-[a-z]{1,3})\s*::\s*(.+)$", ln)
            if not m:
                raise SystemExit("queue.txt: bad line %r" % ln[:80])
            out.append((m.group(1), m.group(2).strip()))
    return out


def expand(template, arm):
    return template.replace("{ARM}", arm).replace("{OUT}", ab2_dir() + "/" + arm)


def make_plan(rows, seed):
    """Row order shuffled by seed; first-arm pattern A B B A A B B A ... (A = random by seed) so order effects cancel; runs flat:
    row1-first, row1-second, row2-first, ..."""
    import random
    rng = random.Random(seed)
    rows = list(rows)
    rng.shuffle(rows)
    a0 = rng.choice(ARMS)
    other = {ARMS[0]: ARMS[1], ARMS[1]: ARMS[0]}
    runs = []
    seq = 1
    for i, row in enumerate(rows):
        first = a0 if i % 4 in (0, 3) else other[a0]
        for order, arm in (("first", first), ("second", other[first])):
            runs.append({"seq": seq, "row": row, "arm": arm, "model": MODEL_OF[arm], "order": order, "agent": "ab2-%s-%s" % (arm, row)})
            seq += 1
    return {"seed": seed, "created": now_iso(), "rows": rows, "first_arm_of_row_1": a0, "runs": runs}


def load_plan():
    p = read_json(ab2_dir() + "/plan.json")
    if not p:
        raise SystemExit("no plan.json in %s (run ab2-plan.py once)" % ab2_dir())
    return p


def load_state():
    return read_json(ab2_dir() + "/state.json", {"cur": 1, "runs": {}, "voided": {}})


def save_state(st):
    write_json(ab2_dir() + "/state.json", st)


def cur_run(plan, st):
    for r in plan["runs"]:
        if r["seq"] == st["cur"]:
            return r
    return None


# ---------------------------------------------------------------- dependency manifest (script drift guard)
TOKEN_RE = re.compile(r"[A-Za-z0-9_][A-Za-z0-9_.\-]*\.(?:sh|py)\b")


def _strip_comments(text):
    out = []
    for ln in text.splitlines():
        s = ln.lstrip()
        if s.startswith("#"):
            continue
        i = ln.find(" #")
        out.append(ln if i < 0 else ln[:i])
    return "\n".join(out)


def _resolve(name, base_dirs):
    for d in base_dirs:
        p = os.path.join(d, name)
        if os.path.isfile(p):
            return norm(os.path.abspath(p))
    return None


def row_deps(template):
    """Files the row's one-call script depends on: the script plus every .sh/.py named (outside comments) in it, recursively, resolved
    in rowtools/, the assert dir and v2/. selftest/README files and candidates are ignored."""
    ad = assert_dir()
    dirs = [ad + "/rowtools", ad, ad + "/v2"]
    m = re.search(r"rowtools/([A-Za-z0-9_.\-]+\.sh)", template)
    if not m:
        return []
    first = _resolve(m.group(1), dirs)
    if not first:
        return []
    seen, todo = [], [first]
    while todo:
        f = todo.pop()
        if f in seen:
            continue
        seen.append(f)
        try:
            text = _strip_comments(open(f, encoding="utf-8", errors="replace").read())
        except OSError:
            continue
        for tok in set(TOKEN_RE.findall(text)):
            if "selftest" in tok or tok.startswith("ab2"):
                continue
            p = _resolve(tok, [os.path.dirname(f)] + dirs)
            if p and p not in seen:
                todo.append(p)
    return sorted(seen)


def file_sha(p):
    h = hashlib.sha256()
    with open(p, "rb") as f:
        h.update(f.read())
    return h.hexdigest()[:12]


def manifest(template):
    ad = assert_dir()
    out = {}
    for p in row_deps(template):
        out[os.path.relpath(p, ad).replace("\\", "/")] = file_sha(p)
    return out


# ---------------------------------------------------------------- lane baseline (same DLL / bundle / base save)
def _sha8(p):
    try:
        return file_sha(p)[:8].upper()
    except OSError:
        return None


def baseline():
    fake = os.environ.get("AB2_FAKE_BASELINE")
    if fake:
        return json.loads(fake)
    inst = "D:/KenshiInst/4"
    b = {"dll_mods": _sha8(inst + "/mods/Stobe/Stobe.dll"), "dll_re": _sha8(inst + "/RE_Kenshi/mods/Stobe/Stobe.dll"), "bundle": None, "saves": {}}
    try:
        r = subprocess.run(["wsl.exe", "-d", "DwemerAI4Skyrim3", "-u", "root", "--cd", "/", "--", "cat", "/tmp/stobe-imm26-5090-i4/BUNDLE_DEPLOYED"],
                           capture_output=True, text=True, timeout=30, env=dict(os.environ, MSYS_NO_PATHCONV="1"))
        m = re.search(r"bundle=([0-9a-f]{8,})", r.stdout or "")
        b["bundle"] = m.group(1) if m else None
    except Exception:
        pass
    for sv in ("kah-imm26-i4", "kah-imm26-i4-hx0"):
        d = inst + "/save/" + sv
        h = hashlib.sha256()
        n = 0
        for p in sorted(glob.glob(d + "/**", recursive=True)):
            if os.path.isfile(p):
                st = os.stat(p)
                h.update(("%s|%d\n" % (os.path.relpath(p, d), st.st_size)).encode())
                n += 1
        b["saves"][sv] = ("%d:%s" % (n, h.hexdigest()[:10])) if n else None
    return b


def baseline_diff(a, b):
    """Names of baseline fields that differ (None on either side = unknown, ignored)."""
    d = []
    for k in ("dll_mods", "dll_re", "bundle"):
        if a.get(k) and b.get(k) and a[k] != b[k]:
            d.append("%s %s->%s" % (k, a[k], b[k]))
    for sv in set((a.get("saves") or {}).keys()) | set((b.get("saves") or {}).keys()):
        x, y = (a.get("saves") or {}).get(sv), (b.get("saves") or {}).get(sv)
        if x and y and x != y:
            d.append("save %s %s->%s" % (sv, x, y))
    return d


def agent_status(runs, name):
    """(state word, file) of agents/<name>.status or (None, path)."""
    p = runs + "/agents/" + name + ".status"
    try:
        with open(p, encoding="utf-8-sig", errors="replace") as f:
            first = f.readline()
        m = re.search(r"\|\s*([A-Z\-]+)\s*\|", first)
        return (m.group(1) if m else "?"), p
    except OSError:
        return None, p
