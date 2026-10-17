#!/usr/bin/env python3
"""ab2-rebaseline.py [--tag nc20] [--expect-dll 3FE805BF] [--seed N] [--check]
Re-freeze plan.json on the CURRENT lane state after a deliberate lane change (new Stobe.dll install + relaunch) and BEFORE the first ab2 run.
Order of work (stops at the first refusal, exit 5, nothing written):
  1. pilot not started: state.json has no runs / voids, no RUNNING lock, captures.jsonl empty.
  2. lane 5090-i4 is up as the README requires: a kenshi_x64 whose path is under D:\\KenshiInst\\4 (game pid), C:\\KenshiTestRuns\\game-4.lock owned by
     rig5090-imm26-i4, inflight\\5090-imm26-i4 present, `5090-i4` held in lanes.held (not expired), backend healthy (lane-backend.sh status i4: php+bridge listening, pg up, health http=200).
  3. new baseline readable: Stobe.dll of both copies present and equal (and starts with --expect-dll if given), bundle id, both base-save fingerprints.
  4. every queue.txt row re-verified with its own command + `--dry` (offline fake lane; rows base redirected to a temp dir so no lane evidence is touched):
     each must print one `RESULT <row> DRY-RUN ...` line.
Then: plan.json -> plan.json.<tag>-<timestamp> (archive, never deleted), a new plan.json is written (same seed as the old plan unless --seed, same rows, same
A/B/B/A order when queue.txt is unchanged; game pid + lane facts recorded under plan["rebaseline"]), line appended to rebaseline.log.
--check does steps 1-4 and prints the result without writing. Test hooks: AB2_FAKE_LANE (json lane facts), AB2_FAKE_BASELINE (see ab2_lib).
"""
import sys, os, re, json, time, shutil, tempfile, subprocess, datetime
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import ab2_lib as L

OWNER = "rig5090-imm26-i4"
WSL_BACKEND = "/mnt/c/KenshiModding/tools/automation/lane-backend.sh"


def refuse(msg):
    print("ab2-rebaseline: REFUSED: " + msg)
    return 5


def pilot_started(d):
    st = L.read_json(d + "/state.json")
    why = []
    if st and (st.get("runs") or st.get("voided") or int(st.get("cur", 1)) > 1):
        why.append("state.json has runs (%d) / voids (%d) / cur=%s: the pilot already started, the plan stays frozen" % (len(st.get("runs") or {}), len(st.get("voided") or {}), st.get("cur")))
    if os.path.isdir(d + "/RUNNING"):
        why.append("RUNNING lock exists")
    cj = d + "/captures.jsonl"
    if os.path.exists(cj) and os.path.getsize(cj) > 0:
        why.append("captures.jsonl is not empty")
    return why


def _hold_active(runs, lane):
    try:
        lines = open(runs + "/lanes.held", encoding="utf-8-sig", errors="replace").read().splitlines()
    except OSError:
        return False
    for ln in lines:
        s = ln.strip()
        if not s or s.startswith("#"):
            continue
        if s.split()[0] == lane:
            m = re.search(r"until=(\S+ ?\S*)", s)
            if m:
                for fmt in ("%Y-%m-%d %H:%M", "%Y-%m-%dT%H:%M:%S", "%Y-%m-%d %H:%M:%S"):
                    try:
                        if datetime.datetime.strptime(m.group(1).strip(), fmt) < datetime.datetime.now():
                            return False
                        break
                    except ValueError:
                        continue
            return True
    return False


def lane_facts(runs):
    """dict: pid, lock_owner, inflight, held, backend ('ok' or the problem). AB2_FAKE_LANE replaces it (selftest)."""
    fake = os.environ.get("AB2_FAKE_LANE")
    if fake:
        return json.loads(fake)
    f = {"pid": None, "lock_owner": None, "inflight": os.path.exists(runs + "/inflight/5090-imm26-i4"), "held": _hold_active(runs, "5090-i4"), "backend": "unknown"}
    try:
        r = subprocess.run(["powershell.exe", "-NoProfile", "-Command",
                            "Get-Process kenshi_x64 -ErrorAction SilentlyContinue | Where-Object { $_.Path -like 'D:\\KenshiInst\\4\\*' } | Select-Object -First 1 -ExpandProperty Id"],
                           capture_output=True, text=True, timeout=60)
        m = re.search(r"\d+", r.stdout or "")
        f["pid"] = int(m.group(0)) if m else None
    except Exception:
        pass
    try:
        f["lock_owner"] = open(runs + "/game-4.lock", encoding="utf-8-sig", errors="replace").readline().strip()
    except OSError:
        pass
    try:
        r = subprocess.run(["wsl.exe", "-d", "DwemerAI4Skyrim3", "-u", "root", "--cd", "/", "--", "bash", WSL_BACKEND, "status", "i4"],
                           capture_output=True, text=True, timeout=60, env=dict(os.environ, MSYS_NO_PATHCONV="1"))
        o = (r.stdout or "").replace("\x00", "")
        bad = []
        if len(re.findall(r"listening=yes", o)) < 2:
            bad.append("php/bridge port not listening")
        if "pg=up" not in o:
            bad.append("pg down")
        if "http=200" not in o:
            bad.append("health.php not 200")
        f["backend"] = "ok" if not bad else ", ".join(bad)
    except Exception as e:
        f["backend"] = "status failed: %s" % e
    return f


def lane_problems(f):
    p = []
    if not f.get("pid"):
        p.append("no kenshi_x64 running from D:\\KenshiInst\\4 (lane not up)")
    if OWNER not in str(f.get("lock_owner") or ""):
        p.append("game-4.lock not held by %s (owner=%r)" % (OWNER, f.get("lock_owner")))
    if not f.get("inflight"):
        p.append("inflight\\5090-imm26-i4 marker missing (touch it; a missing marker failed preflight in pilot 1)")
    if not f.get("held"):
        p.append("5090-i4 is not (validly) listed in lanes.held: another operator could be dispatched onto the lane")
    if f.get("backend") != "ok":
        p.append("backend not healthy: %s" % f.get("backend"))
    return p


def git_bash():
    """Git Bash, never the WSL bash.exe in System32 (paths differ)."""
    b = os.environ.get("AB2_BASH")
    if b:
        return b
    for c in ("C:/Program Files/Git/usr/bin/bash.exe", "C:/Program Files/Git/bin/bash.exe"):
        if os.path.isfile(c):
            return c
    return shutil.which("bash") or "bash"


def verify_rows_dry(q):
    """Run every queue row with its own command + --dry against the OFFLINE fake lane. KAH_ROWS_BASE/KAH_RUNS_DIR/{OUT} point to a temp dir so the real lane's
    rows/ evidence is never touched. Returns [(row, ok, line)]."""
    ad = L.assert_dir()
    tmp = tempfile.mkdtemp(prefix="ab2-dry-")
    tw = L.norm(tmp)
    res = []
    try:
        for row, tpl in q:
            cmd = tpl.replace("{ARM}", "rebaseline").replace("{OUT}", tw + "/b") + " --dry"
            env = dict(os.environ, KAH_ROWS_BASE=tw, KAH_RUNS_DIR=tw)   # no MSYS_NO_PATHCONV: the row scripts hand /tmp paths to Windows python
            try:
                r = subprocess.run([git_bash(), "-c", cmd], cwd=ad, capture_output=True, text=True, timeout=300, env=env)
                out = (r.stdout or "") + (r.stderr or "")
            except Exception as e:
                res.append((row, False, "dry run failed: %s" % e)); continue
            lines = [x.strip() for x in out.splitlines() if re.match(r"^\s*RESULT\s+(IMM-)?%s\s" % re.escape(row), x)]
            ok = len(lines) == 1 and re.match(r"RESULT\s+(IMM-)?%s\s+DRY-RUN\b" % re.escape(row), lines[0]) is not None
            res.append((row, ok, (lines[-1] if lines else "no RESULT line (tail: %s)" % out.strip()[-160:].replace("\n", " | "))[:200]))
    finally:
        shutil.rmtree(tmp, ignore_errors=True)
    return res


def main(a):
    tag, expect, seed, check = "old", None, None, False
    i = 0
    while i < len(a):
        if a[i] == "--tag" and i + 1 < len(a):
            tag = re.sub(r"[^A-Za-z0-9_.-]", "", a[i + 1]); i += 2
        elif a[i] == "--expect-dll" and i + 1 < len(a):
            expect = a[i + 1].upper(); i += 2
        elif a[i] == "--seed" and i + 1 < len(a):
            seed = int(a[i + 1]); i += 2
        elif a[i] == "--check":
            check = True; i += 1
        else:
            print(__doc__); return 2
    d, runs = L.ab2_dir(), L.runs_dir()
    pp = d + "/plan.json"
    old = L.read_json(pp)
    if not old:
        return refuse("no plan.json to rebaseline (use ab2-plan.py)")
    # 1. pilot not started
    why = pilot_started(d)
    if why:
        return refuse("; ".join(why))
    # 2. lane up and held as the README requires
    facts = lane_facts(runs)
    lp = lane_problems(facts)
    if lp:
        return refuse("lane 5090-i4: " + "; ".join(lp))
    # 3. new baseline
    base = L.baseline()
    miss = [k for k in ("dll_mods", "dll_re", "bundle") if not base.get(k)] + ["save " + k for k, v in (base.get("saves") or {}).items() if not v]
    if len(base.get("saves") or {}) < 2:
        miss.append("base saves (kah-imm26-i4, kah-imm26-i4-hx0)")
    if miss:
        return refuse("baseline unreadable: " + ", ".join(miss))
    if base["dll_mods"] != base["dll_re"]:
        return refuse("the two Stobe.dll copies differ (mods %s vs RE_Kenshi %s): finish the install first" % (base["dll_mods"], base["dll_re"]))
    if expect and not base["dll_mods"].startswith(expect):
        return refuse("Stobe.dll is %s, expected prefix %s (install not done?)" % (base["dll_mods"], expect))
    # 4. rows re-verified with --dry
    q = L.parse_queue()
    bad = [(r, ln) for r, ok, ln in verify_rows_dry(q) if not ok]
    if bad:
        return refuse("--dry failed for %d row(s): %s" % (len(bad), " || ".join("%s: %s" % x for x in bad)[:900]))
    diff = L.baseline_diff(old.get("baseline") or {}, base)
    print("ab2-rebaseline: checks OK (pilot not started; lane up pid=%s; DLL %s; bundle %s; %d rows dry OK)." % (facts.get("pid"), base["dll_mods"], base["bundle"], len(q)))
    print("ab2-rebaseline: baseline change vs plan.json: %s" % ("; ".join(diff) if diff else "none (game pid / lane facts only)"))
    if check:
        print("ab2-rebaseline: --check only, nothing written."); return 0
    newplan = L.build_plan(seed if seed is not None else old.get("seed", 20261016))
    newplan["baseline"] = base
    stamp = time.strftime("%Y%m%d-%H%M%S")
    arch = "plan.json.%s-%s" % (tag, stamp)
    shutil.copy2(pp, d + "/" + arch)
    newplan["rebaseline"] = {"at": L.now_iso(), "archived_as": arch, "tag": tag, "game_pid": facts.get("pid"), "lane_facts": facts, "baseline_changes": diff}
    L.write_json(pp, newplan)
    same = [(r["seq"], r["arm"], r["row"]) for r in old["runs"]] == [(r["seq"], r["arm"], r["row"]) for r in newplan["runs"]]
    with open(d + "/rebaseline.log", "a", encoding="utf-8") as f:
        f.write("%s archived=%s seed=%s pid=%s dll=%s bundle=%s order_identical=%s changes=%s\n" % (L.now_iso(), arch, newplan["seed"], facts.get("pid"), base["dll_mods"], base["bundle"], same, diff))
    print("ab2-rebaseline: archived old plan as %s; wrote new plan.json (seed %s, %d rows, %d runs)." % (arch, newplan["seed"], len(newplan["rows"]), len(newplan["runs"])))
    print("ab2-rebaseline: run order %s the archived plan%s." % ("IDENTICAL to" if same else "DIFFERS from", "" if same else " (queue rows changed since: expected only if rows were replaced)"))
    print("baseline:", json.dumps(base))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
