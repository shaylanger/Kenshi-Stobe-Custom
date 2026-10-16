#!/usr/bin/env python3
"""rowcard.py: fixed-size row cards, next-claimable-row and lane inbox digest for the imm26 lane operators (imm26-ctxfix, 2026-10-16).
Replaces grep/awk/python over the 200 KB testing/NPC_IMMERSION_26_TESTS.md (operators paid ~17k tokens per window for those lookups).
Wrapped by tools/automation/row-card.sh and next-row.sh. READ-ONLY by default; the only writes are `next ... --claim` (mkdir claims/<row>, the
claim rule of the lane plan) and nothing else. It never edits a row script, the TESTS file or any list a running operator uses.

  rowcard.py card ROW [--lane LANE]        one card, <= 600 chars: status, claim, RUN command, SETUP, EXPECT, RESULT/evidence path, last attempt
  rowcard.py next LANE [--n N] [--ids] [--claim] [--cards]
                                           next claimable rows for the lane. Default: the best row as a card + the other candidates on one line.
                                           --ids: one id per line (N of them); --claim: mkdir claims/<row> for the first one that is free (prints CLAIMED);
                                           --cards: a card for each of the N rows.
  rowcard.py inbox LANE [--ids a,b] [--max-bytes N]
                                           lane-tagged digest of C:\\KenshiTestRuns\\inbox\\operators (one line + path per note, default <= 2500 bytes)
  rowcard.py state LANE                    one-line facts: PASS count, claimed rows, handoff file
Order of "next": (1) inbox\\operators\\<lane>-ready-<row>.txt notes, (2) TODO ids of the newest lane handoff, (3) the lane's queue in the newest
lane-plan-*.txt, (4) every other open row that has a runner script (UNRUN, SETUP-FAIL, FAIL, then GATED). Rows already claimed (claims\\<row>) are
skipped; rows whose last attempt on this lane FAILED (PI-06 guard, row-attempts\\<lane>.json) and GATED rows come after the fresh ones, marked.
Runner table: tools/automation/row-runners.tsv ("row | script (under rowtools/) | extra args | note"); a row with rd_<id> in rowdefs.sh/tripdefs.sh
falls back to go-row.sh; anything else is "manual".
Env: KAH_RUNS_DIR, KAH_REPO, KAH_TESTS_MD, KAH_ROW_RUNNERS (selftests).
"""
import sys, os, re, io, json, time, glob

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.environ.get("KAH_REPO") or os.path.dirname(os.path.dirname(HERE))
RT_REL = "testing/live-stobe-queue/imm26-assert/rowtools"
CARD_MAX = 600

LANES = {  # ops/globs/dirs = same defaults as lane-brief.ps1 (lane-owners.json overrides ops+dirs there); ready = the lane's ready save; ev = evidence dir
    "5090-i3": dict(ops=["imm26-5090-i3op3"], globs=["imm26-5090-i3op*"], ev="imm26-5090-i3", ready="kah-imm26-5090-ready", env=""),
    "5090-i4": dict(ops=["imm26-5090-i4op3"], globs=["imm26-5090-i4op*"], ev="imm26-5090-i4", ready="kah-imm26-i4-trip2", env=""),
    "5090-i5": dict(ops=["imm26-5090-ctxop322"], globs=["imm26-5090-i5op*", "imm26-5090-i5-op*", "imm26-5090-ctxop*"], ev="imm26-5090-i5", ready="kah-imm26-i5", env=""),
    "4080-i3": dict(ops=["imm26-4080-op2g"], globs=["imm26-4080-op*", "imm26-4080-i3op*"], ev="imm26-4080", ready="kah-imm26-4080", env=""),
    "4080-i4": dict(ops=["imm26-4080-i4op5"], globs=["imm26-4080-i4op*"], ev="imm26-4080-i4", ready="kah-imm26-4080-i4h", env="KAH_PF_ISOLATION=0 "),
}
STATUSES = ("PASS", "FAIL", "SETUP-FAIL", "GATED", "UNRUN")


def runs_dir():
    for c in (os.environ.get("KAH_RUNS_DIR"), "C:/KenshiTestRuns", "/c/KenshiTestRuns", "/mnt/c/KenshiTestRuns"):
        if c and os.path.isdir(c):
            return c.replace("\\", "/")
    return "C:/KenshiTestRuns"


RUNS = runs_dir()
TESTS = os.environ.get("KAH_TESTS_MD") or os.path.join(REPO, "testing", "NPC_IMMERSION_26_TESTS.md")


def norm_row(r):
    r = r.strip()
    r = re.sub(r"^IMM-", "", r, flags=re.I)
    m = re.match(r"^(\d{2})([a-z].*)$", r)  # 05cx -> 05-cx
    return (m.group(1) + "-" + m.group(2)) if m else r


def clip(s, n):
    s = re.sub(r"\s+", " ", s or "").strip()
    return s if len(s) <= n else s[: max(0, n - 3)] + "..."


def read_rows():
    rows = {}
    order = []
    try:
        txt = io.open(TESTS, encoding="utf-8").read().split("\n")
    except OSError:
        return rows, order
    for ln in txt:
        m = re.match(r"^\|\s*IMM-([0-9A-Za-z-]+)\s*\|", ln)
        if not m:
            continue
        c = re.split(r"(?<!\\)\|", ln.strip().strip("|"))
        st = None
        for i in range(5, len(c)):
            t = c[i].strip()
            if t in STATUSES:
                st = t
                break
        g = lambda k: c[k].strip() if len(c) > k else ""
        rid = m.group(1)
        rows[rid] = dict(id=rid, setup=g(1), utter=g(2), expect=g(3), neg=g(4), build=g(5), status=st or "?",
                         evidence=g(7), date=g(8))
        order.append(rid)
    return rows, order


def read_runners():
    tbl = {}
    p = os.environ.get("KAH_ROW_RUNNERS") or os.path.join(HERE, "row-runners.tsv")
    try:
        for ln in io.open(p, encoding="utf-8"):
            if not ln.strip() or ln.lstrip().startswith("#"):
                continue
            f = [x.strip() for x in ln.rstrip("\n").split("|")]
            if len(f) >= 2 and f[0] and f[1]:
                tbl[f[0]] = dict(script=f[1], args=f[2] if len(f) > 2 else "", note=f[3] if len(f) > 3 else "")
    except OSError:
        pass
    return tbl


def rd_fallback(rid):
    key = "rd_" + rid.replace("-", "")
    for fn in ("rowdefs.sh", "tripdefs.sh"):
        try:
            for ln in io.open(os.path.join(REPO, RT_REL, fn), encoding="utf-8"):
                if ln.startswith(key + "()"):
                    return True
        except OSError:
            pass
    return False


def runner_cmd(rid, lane, with_retry=False):
    """-> (command string or None, note)"""
    tbl = read_runners()
    ent = tbl.get(rid)
    if ent:
        sp = ent["script"]
        rel = sp if sp.startswith("testing/") or sp.startswith("tools/") else RT_REL + "/" + sp
        rel = os.path.normpath(rel).replace("\\", "/")
        args = ent["args"].replace("<ready>", LANES.get(lane, {}).get("ready", "<ready save>"))
        env = LANES.get(lane, {}).get("env", "")
        cmd = "%sbash %s %s %s%s" % (env, rel, rid, lane, (" " + args) if args else "")
        if with_retry:
            cmd += ' --allow-retry "<why>"'
        return cmd, ent["note"]
    if rd_fallback(rid):
        env = LANES.get(lane, {}).get("env", "")
        return "%sbash testing/live-stobe-queue/imm26-assert/go-row.sh %s%s %s" % (env, '--allow-retry "<why>" ' if with_retry else "", rid, lane), ""
    return None, "manual: no runner script (handoff Helpers + lane-setup.sh; write your steps into the handoff, PI-24)"


def lane_cfg(lane):
    cfg = dict(LANES.get(lane) or {})
    try:
        j = json.load(io.open(os.path.join(RUNS, "lane-owners.json"), encoding="utf-8-sig"))
        if lane in j:
            cfg["ops"] = list(j[lane].get("ops") or cfg.get("ops", []))
    except Exception:
        pass
    return cfg


def lane_handoff(lane):
    cfg = lane_cfg(lane)
    ag = os.path.join(RUNS, "agents")
    cands = []
    for o in cfg.get("ops", []):
        p = os.path.join(ag, o + ".handoff.md")
        if os.path.isfile(p):
            cands.append(p)
    for g in cfg.get("globs", []):
        cands += glob.glob(os.path.join(ag, g + ".handoff.md"))
    cands = [c for c in set(cands) if os.path.isfile(c)]
    return max(cands, key=os.path.getmtime) if cands else None


def ids_in(text, rows):
    out = []
    for m in re.finditer(r"(?<![\w-])(\d{2})-([a-z])((?:/[a-z])*)(?![A-Za-z0-9])", text):
        ids = [m.group(1) + "-" + m.group(2)] + [m.group(1) + "-" + x for x in m.group(3).split("/") if x]
        out += ids
    # longer ids (23-ax, 13-c-neg, 10-e-inproc): match known row ids literally
    for rid in rows:
        if len(rid) > 4 and re.search(r"(?<![\w-])" + re.escape(rid) + r"(?![A-Za-z0-9-])", text):
            out.append(rid)
    seen, res = set(), []
    for i in out:
        if i in rows and i not in seen:
            seen.add(i)
            res.append(i)
    return res


def handoff_todo(lane, rows):
    p = lane_handoff(lane)
    if not p:
        return [], None
    ids = []
    try:
        for ln in io.open(p, encoding="utf-8", errors="replace"):
            if re.search(r"\bTODO\b", ln, re.I):
                for i in ids_in(ln, rows):
                    if i not in ids:
                        ids.append(i)
    except OSError:
        pass
    return ids, p


def plan_queue(lane, rows):
    plans = sorted(glob.glob(os.path.join(RUNS, "inbox", "operators", "lane-plan-*.txt")), key=os.path.getmtime)
    if not plans:
        return []
    try:
        for ln in io.open(plans[-1], encoding="utf-8", errors="replace"):
            if ln.startswith(lane + " ") or ln.startswith(lane + "("):
                return ids_in(ln, rows)
    except OSError:
        pass
    return []


def ready_notes(lane, rows):
    out = []
    for p in sorted(glob.glob(os.path.join(RUNS, "inbox", "operators", lane + "-ready-*.txt")), key=os.path.getmtime, reverse=True):
        m = re.search(r"-ready-(.+)\.txt$", p.replace("\\", "/"))
        if m:
            r = norm_row(m.group(1))
            if r in rows and r not in out:
                out.append(r)
    return out


def claims():
    d = os.path.join(RUNS, "claims")
    try:
        return {n: os.path.getmtime(os.path.join(d, n)) for n in os.listdir(d) if os.path.isdir(os.path.join(d, n))}
    except OSError:
        return {}


def attempts(lane):
    try:
        return json.load(io.open(os.path.join(RUNS, "row-attempts", lane + ".json"), encoding="utf-8")).get("rows", {})
    except Exception:
        return {}


def candidates(lane):
    """-> list of dict(id, src, flag) in priority order (claimed rows excluded, returned separately)"""
    rows, order = read_rows()
    cl = claims()
    att = attempts(lane)
    tiers = []
    for src, ids in (("ready-note", ready_notes(lane, rows)), ("handoff-TODO", handoff_todo(lane, rows)[0]), ("lane-plan", plan_queue(lane, rows))):
        for i in ids:
            tiers.append((i, src))
    pri = {"UNRUN": 0, "SETUP-FAIL": 1, "FAIL": 2, "GATED": 3, "?": 4}
    rest = sorted([r for r in order if rows[r]["status"] != "PASS"], key=lambda r: (pri.get(rows[r]["status"], 4), order.index(r)))
    for i in rest:
        if runner_cmd(i, lane)[0]:
            tiers.append((i, "open+runner"))
    seen, fresh, retry, held = set(), [], [], []
    for i, src in tiers:
        if i in seen or i not in rows or rows[i]["status"] == "PASS":
            continue
        seen.add(i)
        e = dict(id=i, src=src, status=rows[i]["status"])
        if i in cl:
            held.append(e)
            continue
        a = att.get(i)
        if a and a.get("last") in ("FAIL", "SETUP-FAIL"):
            e["flag"] = "retry-needs-why(last %s x%s)" % (a.get("last"), a.get("attempts"))
            (fresh if src == "ready-note" else retry).append(e)  # a coordinator "ready" note means the fix landed: stays in front
        elif rows[i]["status"] == "GATED":
            e["flag"] = "gated"
            retry.append(e)
        else:
            fresh.append(e)
    return fresh + retry, held, rows


def card(rid, lane=None):
    rows, _ = read_rows()
    rid = norm_row(rid)
    r = rows.get(rid)
    if not r:
        return "ROW %s not found in %s" % (rid, os.path.basename(TESTS))
    lane = lane or "<lane>"
    cl = claims()
    att = attempts(lane).get(rid) if lane in LANES else None
    blocked = bool(att and att.get("last") in ("FAIL", "SETUP-FAIL"))
    cmd, note = runner_cmd(rid, lane, with_retry=blocked)
    claim = "HELD" if rid in cl else "free"
    hdr = "IMM-%s [%s] %s | claim:%s" % (rid, r["status"], lane, claim)
    if blocked:
        hdr += " | last attempt %s x%s: needs --allow-retry" % (att.get("last"), att.get("attempts"))
    evdir = "%s/%s/rows/%s/" % (RUNS, LANES[lane]["ev"], rid) if lane in LANES else "%s/<lane dir>/rows/%s/" % (RUNS, rid)
    last = ""
    if r["evidence"]:
        last = "LAST: %s %s" % (r["date"], r["evidence"])
    parts = [
        ("hdr", hdr, 130),
        ("run", ("RUN: cd /c/KenshiModding && " + cmd) if cmd else ("RUN: " + note), 235),
        ("setup", "SETUP: " + r["setup"], 90),
        ("expect", "EXPECT: " + r["expect"], 120),
        ("res", "OUT: RESULT %s PASS|FAIL|SETUP-FAIL|GATED <evidence>; evidence %s" % (rid, evdir), 150),
        ("last", last, 60),
    ]
    # fit: clip each part to its cap, then trim the longest soft parts until <= CARD_MAX
    lines = [clip(t, n) for _, t, n in parts if t]
    while len("\n".join(lines)) > CARD_MAX:
        k = max(range(len(lines)), key=lambda i: len(lines[i]) if not lines[i].startswith(("RUN", "OUT")) else 0)
        lines[k] = clip(lines[k], max(24, len(lines[k]) - 12))
        if all(len(x) <= 24 for x in lines if not x.startswith(("RUN", "OUT"))):
            break
    return "\n".join(lines)[: CARD_MAX + 40]


def cmd_next(lane, n=1, ids=False, claim=False, cards=False):
    if lane not in LANES:
        print("usage: next-row.sh <%s> [--n N] [--ids] [--claim] [--cards]" % "|".join(LANES))
        return 2
    cands, held, rows = candidates(lane)
    if not cands:
        print("NEXT %s: no claimable open row with a runner (claimed by others: %s). Ask the coordinator or run row-card.sh <row> for a manual row." % (lane, " ".join(h["id"] for h in held) or "none"))
        return 1
    pick = []
    if claim:
        d = os.path.join(RUNS, "claims")
        os.makedirs(d, exist_ok=True)
        for e in cands:
            try:
                os.mkdir(os.path.join(d, e["id"]))
                pick = [e]
                print("CLAIMED %s (claims\\%s; release only if you give the row up unrun: rmdir)" % (e["id"], e["id"]))
                break
            except OSError:
                held.append(e)
        if not pick:
            print("NEXT %s: every candidate was just claimed by someone else" % lane)
            return 1
    else:
        pick = cands[:n]
    if ids:
        for e in pick:
            print(e["id"])
        return 0
    for k, e in enumerate(pick):
        if k and not cards:
            break
        print("NEXT %s: %s [%s] via %s%s" % (lane, e["id"], e["status"], e["src"], (" " + e["flag"]) if e.get("flag") else ""))
        print(card(e["id"], lane))
    more = [e for e in cands if e["id"] not in [p["id"] for p in pick]][:6]
    if more or held:
        hl = [h["id"] for h in held]
        print("also: %s%s" % (" ".join("%s[%s%s]" % (e["id"], e["status"], "," + e["flag"] if e.get("flag") else "") for e in more) or "-",
                              ("  | claimed: " + " ".join(hl[:8]) + (" +%d" % (len(hl) - 8) if len(hl) > 8 else "")) if held else ""))
    return 0


def lane_tag_re(lane):
    rig, i = lane.split("-")
    return re.compile(r"(?<![\w])(%s[- ]%s)(?![\w])" % (rig, i), re.I)


def cmd_inbox(lane, ids=None, max_bytes=2500):
    d = os.path.join(RUNS, "inbox", "operators")
    rows, _ = read_rows()
    tag = lane_tag_re(lane)
    if ids is None:
        cands, _, _ = candidates(lane)
        ids = [e["id"] for e in cands[:4]]
    idre = re.compile(r"(?<![\w-])(%s)(?![A-Za-z0-9])" % "|".join(re.escape(i) for i in ids)) if ids else None
    now = time.time()
    out = []
    files = [p for p in glob.glob(os.path.join(d, "*")) if os.path.isfile(p) and p.lower().endswith((".txt", ".md"))]
    for p in sorted(files, key=os.path.getmtime, reverse=True):
        name = os.path.basename(p)
        age = (now - os.path.getmtime(p)) / 3600.0
        if age > 72:
            continue
        try:
            txt = io.open(p, encoding="utf-8", errors="replace").read(60000)
        except OSError:
            continue
        mine = name.startswith(lane) or bool(tag.search(txt)) or bool(idre and idre.search(txt))
        isplan = name.startswith("lane-plan")
        if not (mine or isplan):
            continue
        if isplan:
            line = next((l for l in txt.split("\n") if l.startswith(lane + " ") or l.startswith(lane + "(")), None)
            if not line:
                continue
            line = "queue: " + line
        else:
            line = next((l.strip() for l in txt.split("\n") if l.strip() and not l.strip().startswith(("#", "```"))), "")
        out.append("- %s (%dh): %s -> %s" % (name, int(age), clip(line, 150), p.replace("\\", "/")))
        if len(out) >= 8:
            break
    res = []
    total = 0
    for l in out:
        if total + len(l) + 1 > max_bytes:
            res.append("- ... %d more note(s): ls %s/inbox/operators" % (len(out) - len(res), RUNS))
            break
        res.append(l)
        total += len(l) + 1
    print("\n".join(res) if res else "- none tagged for %s in the last 72 h" % lane)
    return 0


def cmd_state(lane):
    rows, order = read_rows()
    cands, held, _ = candidates(lane)
    npass = sum(1 for r in order if rows[r]["status"] == "PASS")
    ho = lane_handoff(lane)
    print("%s: %d rows PASS of %d; claimed: %s; next: %s; handoff: %s" % (lane, npass, len(order), " ".join(sorted(claims())) or "none",
          " ".join(e["id"] for e in cands[:5]) or "none", (ho or "none").replace("\\", "/")))
    return 0


def main(a):
    if not a:
        print(__doc__)
        return 2
    cmd, rest = a[0], a[1:]
    opt = {"n": 1, "ids": False, "claim": False, "cards": False, "lane": None, "max": 2500, "idlist": None}
    pos = []
    i = 0
    while i < len(rest):
        x = rest[i]
        if x == "--n" and i + 1 < len(rest):
            opt["n"] = int(rest[i + 1]); i += 2
        elif x == "--lane" and i + 1 < len(rest):
            opt["lane"] = rest[i + 1]; i += 2
        elif x == "--max-bytes" and i + 1 < len(rest):
            opt["max"] = int(rest[i + 1]); i += 2
        elif x == "--ids" and cmd == "inbox" and i + 1 < len(rest):
            opt["idlist"] = [norm_row(t) for t in rest[i + 1].split(",") if t]; i += 2
        elif x == "--ids":
            opt["ids"] = True; i += 1
        elif x == "--claim":
            opt["claim"] = True; i += 1
        elif x == "--cards":
            opt["cards"] = True; i += 1
        else:
            pos.append(x); i += 1
    if cmd == "card" and pos:
        print(card(pos[0], opt["lane"]))
        return 0
    if cmd == "next" and pos:
        return cmd_next(pos[0], opt["n"], opt["ids"], opt["claim"], opt["cards"])
    if cmd == "inbox" and pos:
        return cmd_inbox(pos[0], opt["idlist"], opt["max"])
    if cmd == "state" and pos:
        return cmd_state(pos[0])
    print(__doc__)
    return 2


if __name__ == "__main__":
    try:
        sys.stdout.reconfigure(newline=chr(10), encoding="utf-8")
    except Exception:
        pass
    sys.exit(main(sys.argv[1:]))
