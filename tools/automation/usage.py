#!/usr/bin/env python3
"""usage.py <script> | --list: print the usage-table.tsv line for a script wrapped to 150 columns, at most 12 lines (imm26-ctxfix). Wrapped by usage.sh.
Env KAH_USAGE_TABLE overrides the table (selftest). Exit 0 found, 1 unknown script."""
import sys, os, io, re, textwrap
HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.environ.get("KAH_REPO") or os.path.dirname(os.path.dirname(HERE))
MAXL = 12


def table():
    t = {}
    p = os.environ.get("KAH_USAGE_TABLE") or os.path.join(HERE, "usage-table.tsv")
    for ln in io.open(p, encoding="utf-8"):
        if not ln.strip() or ln.startswith("#") or " | " not in ln:
            continue
        k, v = ln.rstrip("\n").split(" | ", 1)
        t[k.strip()] = v.strip()
    return t


def find(name):
    for base in (os.path.join(REPO, "testing", "live-stobe-queue", "imm26-assert", "rowtools"), os.path.join(REPO, "testing", "live-stobe-queue", "imm26-assert"), HERE):
        p = os.path.join(base, name)
        if os.path.isfile(p):
            return p.replace("\\", "/")
    return None


def main(a):
    if not a:
        print(__doc__); return 2
    t = table()
    if a[0] == "--list":
        print(" ".join(sorted(t))); return 0
    n = os.path.basename(a[0].replace("\\", "/"))
    cands = [n, n + ".sh", n + ".py", n + ".ps1"]
    key = next((c for c in cands if c in t), None)
    if not key:
        print("usage.sh: no table entry for '%s'. Known: %s" % (n, " ".join(sorted(t))))
        return 1
    lines = textwrap.wrap(t[key], 150)
    p = find(key)
    foot = "(more: sed -n 1,25p %s)" % p if p else ""
    if len(lines) > MAXL - (1 if foot else 0):
        lines = lines[: MAXL - 1 - (1 if foot else 0)] + ["... (usage line cut; read the script header)"]
    print("\n".join(lines + ([foot] if foot else [])))
    return 0


if __name__ == "__main__":
    try:
        sys.stdout.reconfigure(newline=chr(10), encoding="utf-8")
    except Exception:
        pass
    sys.exit(main(sys.argv[1:]))
