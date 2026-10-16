#!/usr/bin/env python3
"""Source-contract check (IMM-26-a): Activity travel calls must use the lifecycle's own world id.

Run: python3 activity_travel_world_source_tests.py <src-dir> [<src-dir> ...]
Default src-dir: /mnt/c/KenshiTestRuns/imm26-nc16/src (the Activity sources live in the NC tree, not the components/STOBE snapshot).
NativeTravelLifecycle::Prepare only accepts the id minted by NativeTravelLifecycle Reset() ("travel-<32hex>"), so the Activity epoch
a.worldId (plain 32-hex) passed as expectedWorld is always rejected (travel_identity_or_ownership_rejected).
Exit 0 = pass. Prints one RESULT line per tree.
"""
import re
import sys
from pathlib import Path

FILES = ("ActivityRuntimeBindings.cpp", "ActivityHandBack.cpp")
CALL = re.compile(r"NativeTravelLifecycle::(Start|InspectRequest|ReleaseOwned)\(")
MIN_CALLS = 10


def call_args(text, start):
    """Return the argument text of the call whose '(' is at start-1 (balanced parens)."""
    depth, i = 1, start
    while i < len(text) and depth:
        c = text[i]
        depth += (c == "(") - (c == ")")
        i += 1
    return text[start:i - 1]


def check(src):
    total, failures = 0, []
    for name in FILES:
        text = (Path(src) / name).read_text(encoding="utf-8")
        for m in CALL.finditer(text):
            args = call_args(text, m.end())
            total += 1
            line = text.count("\n", 0, m.start()) + 1
            if "NativeTravelLifecycle::WorldId()" not in args:
                failures.append("%s:%d %s lacks NativeTravelLifecycle::WorldId()" % (name, line, m.group(1)))
            if "a.worldId" in args:
                failures.append("%s:%d %s still passes a.worldId" % (name, line, m.group(1)))
    if total < MIN_CALLS:
        failures.append("call-count guard: found %d NativeTravelLifecycle calls, need >= %d" % (total, MIN_CALLS))
    return total, failures


def main():
    trees = sys.argv[1:] or ["/mnt/c/KenshiTestRuns/imm26-nc16/src"]
    bad = 0
    for src in trees:
        total, failures = check(src)
        for f in failures:
            print("  FAIL " + f)
        print("RESULT ACTIVITY_TRAVEL_WORLD_SOURCE %s calls=%d failures=%d src=%s" % ("PASS" if not failures else "FAIL", total, len(failures), src))
        bad += len(failures)
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
