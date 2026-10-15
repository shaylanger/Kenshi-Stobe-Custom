#!/usr/bin/env python3
"""claude-md-verify.py: prove no rule of the original CLAUDE.md is lost by the trim (claude-md-trim, 2026-10-15).

Checks (exit 0 only if all pass):
  1. every non-empty line of docs/claude-md-archive/CLAUDE.md.original appears verbatim (whole line, stripped) as a line of
     CLAUDE.md.proposed or of an archive page;
  2. every non-empty original line is listed in RULE_CHECKLIST.md (| <n> | ...);
  3. every archive page is named in the proposed core's index; the core has the Large-programs slot markers, the waker guard
     bullet and the imm26 pointer;
  4. archive pages / proposal / checklist have LF endings only, no BOM;
  5. tool paths named in the checklist's `TOOL`/`HOOK` flags that look like files exist in the repo (reported, missing = warning
     unless --strict-tools);
  6. prints the proposal size and a token estimate (chars/4).
Usage: python -I tools/automation/claude-md-verify.py [--original <path>] [--strict-tools]
"""
import os, re, sys, glob

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
ARC = os.path.join(ROOT, "docs", "claude-md-archive")


def read(p):
    with open(p, "rb") as f:
        b = f.read()
    return b


def main():
    orig_path = os.path.join(ARC, "CLAUDE.md.original")
    strict = "--strict-tools" in sys.argv
    if "--original" in sys.argv:
        orig_path = sys.argv[sys.argv.index("--original") + 1]
    fails = []
    ob = read(orig_path)
    orig = ob.decode("utf-8").split("\n")
    prop_b = read(os.path.join(ARC, "CLAUDE.md.proposed"))
    pages = sorted(p for p in glob.glob(os.path.join(ARC, "*.md")) if os.path.basename(p) not in ("RULE_CHECKLIST.md",))
    all_b = {p: read(p) for p in pages}
    check_b = read(os.path.join(ARC, "RULE_CHECKLIST.md"))

    # 4 endings
    for name, b in [("CLAUDE.md.proposed", prop_b), ("RULE_CHECKLIST.md", check_b)] + [(os.path.basename(p), b) for p, b in all_b.items()]:
        if b"\r" in b:
            fails.append("CR found in " + name)
        if b.startswith(b"\xef\xbb\xbf"):
            fails.append("BOM in " + name)

    # 1 verbatim lines
    pool = {}
    pool["CLAUDE.md.proposed"] = set(l.strip() for l in prop_b.decode("utf-8").split("\n"))
    for p, b in all_b.items():
        pool[os.path.basename(p)] = set(l.strip() for l in b.decode("utf-8").split("\n"))
    in_core = in_arch = 0
    nonempty = 0
    for n, ln in enumerate(orig, 1):
        s = ln.strip()
        if not s:
            continue
        nonempty += 1
        where = [k for k, v in pool.items() if s in v and k != "CLAUDE.md.original"]
        if not where:
            fails.append("original line %d not found verbatim anywhere: %s..." % (n, s[:60]))
        elif "CLAUDE.md.proposed" in where:
            in_core += 1
        else:
            in_arch += 1
    # also check that archive-resident lines are not duplicated needlessly: informational only

    # 2 checklist coverage
    chk = check_b.decode("utf-8")
    listed = set(int(m.group(1)) for m in re.finditer(r"^\| (\d+) \|", chk, re.M))
    for n, ln in enumerate(orig, 1):
        if ln.strip() and n not in listed:
            fails.append("original line %d missing from RULE_CHECKLIST.md" % n)

    # 3 index + slots
    prop = prop_b.decode("utf-8")
    for p in pages:
        base = os.path.basename(p)
        if base in ("CLAUDE.md.original",):
            continue
        if base not in prop:
            fails.append("proposal index does not name " + base)
    if "RULE_CHECKLIST.md" not in prop:
        fails.append("proposal index does not name RULE_CHECKLIST.md")
    for marker in ("LARGE-PROGRAMS-SLOT-BEGIN", "LARGE-PROGRAMS-SLOT-END", "Waker guard (restored",
                   "NPC_IMMERSION_26_HANDOFF.md", "## Large programs", "Commit identity"):
        if marker not in prop:
            fails.append("proposal lacks marker: " + marker)

    # 5 tools named in checklist exist
    missing = set()
    for m in re.finditer(r"((?:tools/automation|tests/ingame/stobe|tools)/[A-Za-z0-9_./-]+\.(?:ps1|sh|py|json))", chk):
        rel = m.group(1)
        if not os.path.exists(os.path.join(ROOT, rel)) and not glob.glob(os.path.join(ROOT, "**", rel), recursive=True):
            missing.add(rel)
    # tools/automation names without the dir (e.g. "session-start.ps1")
    for m in re.finditer(r"\b([a-z0-9-]+\.(?:ps1|sh|py))\b", chk):
        nm = m.group(1)
        if not glob.glob(os.path.join(ROOT, "**", nm), recursive=True):
            missing.add(nm)
    for t in sorted(missing):
        print(("MISSING-TOOL " if strict else "warn: tool not found in repo: ") + t)
        if strict:
            fails.append("missing tool " + t)

    chars = len(prop)
    print("original: %d bytes, %d non-empty lines (%d verbatim in core, %d verbatim in archive pages only)" % (len(ob), nonempty, in_core, in_arch))
    print("proposal: %d bytes, ~%d tokens (chars/4)" % (len(prop_b), chars // 4))
    print("archive pages: %s" % ", ".join(os.path.basename(p) for p in pages if not p.endswith(".original")))
    if fails:
        for f in fails:
            print("FAIL", f)
        print("VERIFY FAIL (%d)" % len(fails))
        return 1
    print("VERIFY OK: every original line is verbatim in the proposal or an archive page; checklist complete")
    return 0


if __name__ == "__main__":
    sys.exit(main())
