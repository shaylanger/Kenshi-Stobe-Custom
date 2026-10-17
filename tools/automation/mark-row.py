#!/usr/bin/env python3
"""mark-row.py: the one way to mark an imm26 test row in testing/NPC_IMMERSION_26_TESTS.md (replaces the per-lane mark.py copies, which now call this).
  mark-row.py ROW STATUS "evidence" [--lane LANE] [--prev append|drop|keep] [keepold]
    ROW without IMM- prefix (04-c). STATUS = PASS|FAIL|SETUP-FAIL|GATED|UNRUN.  --prev: append (default) = old evidence appended as "(prev: ...)"
    (400 chars); drop = old evidence discarded; keep / legacy `keepold` = appended as "; PRIOR RUN: ..." (600 chars).
  SETUP-FAIL (Shay 2026-10-15): the text MUST contain `needs: recipe|server-fix|native|design|fixture` and say what exactly; a bare SETUP-FAIL is
  REFUSED (exit 2, nothing written). PREFLIGHT-FAIL text (llm/lane down: the row never ran) is exempt. A SETUP-FAIL mark creates/updates the unblock
  ticket (<runs>/setupfail/<row>.json, inbox note for the coordinator); PASS / FAIL closes it (GATED is a note only, the ticket stays open). See setupfail.py / setupfail.ps1.
  PI-52: a SETUP-FAIL 'bundle dirs missing under <bd>: ..' is REFUSED when run.log (in the evidence dir named in the text) is empty and the dirs exist.
Env: KAH_TESTS_MD (file), KAH_RUNS_DIR (ticket + inbox dir), KAH_LANE (default lane).
"""
import sys, os, io, re, datetime
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import setupfail as sf


def _winpath(p):
    """/c/x and /mnt/c/x -> C:/x (the form Windows python opens); other paths unchanged."""
    m = re.match(r"^/(?:mnt/)?([a-zA-Z])/(.*)$", p)
    return "%s:/%s" % (m.group(1).upper(), m.group(2)) if m and os.name == "nt" else p


def false_bundle_setupfail(status, note):
    """PI-52: refuse SETUP-FAIL 'bundle dirs missing under <bd>: g:d,..' when the run's run.log is empty AND every listed dir exists
    (the hxdefs.sh /c/.. path bug made the verdict python miss existing dirs). Narrow: anything else (no evidence dir, non-empty or missing
    run.log, dirs really missing, other reasons) returns "" and the mark passes unchanged."""
    if str(status).strip().upper() != "SETUP-FAIL":
        return ""
    m = re.search(r"bundle dirs missing under (\S+?):\s+(.+?)(?:\s+\(the row script|\s*\[evidence=|$)", str(note))
    e = re.search(r"evidence[= ]+([^\]\s;,)]+)", str(note))
    if not m or not e:
        return ""
    ev, bd = _winpath(e.group(1)), _winpath(m.group(1))
    dirs = [x.strip().split(":")[-1].strip() for x in m.group(2).split(",") if x.strip()]
    log = os.path.join(ev, "run.log")
    try:
        if not dirs or not os.path.isfile(log) or os.path.getsize(log) != 0:
            return ""
    except OSError:
        return ""
    if not all(os.path.isdir(os.path.join(bd, d)) for d in dirs):
        return ""
    return ("REFUSED: false SETUP-FAIL 'bundle dirs missing': %s exist under %s and run.log is empty, so the row script never failed; "
            "the verdict python could not open the /c/.. path in bundle_dir.txt (hxdefs.sh winpath bug, testing/KNOWN_BLOCKERS.md). "
            "Workaround: rerun the row with a current hxdefs.sh, or set HX_OUT=C:/KenshiTestRuns/imm26-4080-hx; do not file a ticket." % (",".join(dirs), bd))


def main(a):
    pos, lane, prev = [], os.environ.get("KAH_LANE", "-"), "append"
    i = 0
    while i < len(a):
        if a[i] == "--lane" and i + 1 < len(a):
            lane = a[i + 1]; i += 2
        elif a[i] == "--prev" and i + 1 < len(a):
            prev = a[i + 1]; i += 2
        else:
            pos.append(a[i]); i += 1
    if len(pos) < 3:
        print(__doc__); return 2
    row, status, note = sf.norm_row(pos[0]), pos[1].strip(), pos[2]
    if len(pos) > 3 and pos[3] == "keepold":
        prev = "keep"
    msg = false_bundle_setupfail(status, note)   # PI-52: checked first so the real cause is named
    ok = not msg
    if ok:
        ok, msg = sf.check_mark(status, note)
    if not ok:
        print("%s (row %s not marked)" % (msg, row)); return 2
    p = sf.tests_md()
    L = io.open(p, encoding="utf-8", newline="").read().split("\n")
    for i, l in enumerate(L):
        if l.startswith("| IMM-%s |" % row):
            f = l.split("|")
            if len(f) < 10:
                print("ABORT: row %s has %d fields (need >= 10)" % (row, len(f))); return 1
            old = f[8].strip()
            note = note.replace("|", "/")
            if old and prev == "append":
                note += " (prev: %s)" % (old if len(old) < 400 else old[:400] + "...")
            elif old and prev == "keep":
                note += "; PRIOR RUN: " + old[:600]
            f[7], f[8], f[9] = " %s " % status, " %s " % note, " %s " % datetime.date.today().isoformat()
            L[i] = "|".join(f)
            break
    else:
        print("ROW NOT FOUND", row); return 1
    data = "\n".join(L)
    try:
        tmp = p + ".tmp"
        io.open(tmp, "w", encoding="utf-8", newline="").write(data)
        os.replace(tmp, p)
    except OSError:
        io.open(p, "w", encoding="utf-8", newline="").write(data)
    print("marked", row, status)
    try:
        t = sf.on_verdict(row, lane, status, pos[2])
        if status.upper() == "SETUP-FAIL" and t:
            print("ticket %s: %s" % (row, sf.line(t)))
        elif t:
            print("ticket %s closed (%s)" % (row, status))
    except Exception as e:
        print("(ticket update failed: %s)" % e)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
