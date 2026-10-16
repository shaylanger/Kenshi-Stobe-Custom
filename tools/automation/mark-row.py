#!/usr/bin/env python3
"""mark-row.py: the one way to mark an imm26 test row in testing/NPC_IMMERSION_26_TESTS.md (replaces the per-lane mark.py copies, which now call this).
  mark-row.py ROW STATUS "evidence" [--lane LANE] [--prev append|drop|keep] [keepold]
    ROW without IMM- prefix (04-c). STATUS = PASS|FAIL|SETUP-FAIL|GATED|UNRUN.  --prev: append (default) = old evidence appended as "(prev: ...)"
    (400 chars); drop = old evidence discarded; keep / legacy `keepold` = appended as "; PRIOR RUN: ..." (600 chars).
  SETUP-FAIL (Shay 2026-10-15): the text MUST contain `needs: recipe|server-fix|native|design|fixture` and say what exactly; a bare SETUP-FAIL is
  REFUSED (exit 2, nothing written). PREFLIGHT-FAIL text (llm/lane down: the row never ran) is exempt. A SETUP-FAIL mark creates/updates the unblock
  ticket (<runs>/setupfail/<row>.json, inbox note for the coordinator); PASS / FAIL / GATED closes it. See setupfail.py / setupfail.ps1.
Env: KAH_TESTS_MD (file), KAH_RUNS_DIR (ticket + inbox dir), KAH_LANE (default lane).
"""
import sys, os, io, datetime
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import setupfail as sf


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
