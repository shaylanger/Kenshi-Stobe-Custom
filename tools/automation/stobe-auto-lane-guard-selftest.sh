#!/usr/bin/env bash
# stobe-auto-lane-guard-selftest.sh: PI-48 lane guard inside tools/stobe-auto (WSL copy /usr/local/bin/stobe-auto).
# Offline, no game: runs a temp copy of the script whose kah.py is a stub, with KAH_RUNS_DIR = temp dir.
# Usage: bash stobe-auto-lane-guard-selftest.sh [path-to-stobe-auto]   (default: ../stobe-auto next to this folder)
here="$(cd "$(dirname "$0")" && pwd)"
src="${1:-$here/../stobe-auto}"
t="$(mktemp -d)"; trap 'rm -rf "$t"' EXIT
printf 'import sys\nprint("STUB-OK", sys.argv[1:])\n' > "$t/kah_stub.py"
sed "s|^KAH = .*|KAH = '$t/kah_stub.py'|" "$src" > "$t/stobe-auto"
grep -q "kah_stub.py" "$t/stobe-auto" || { echo "SELFTEST FAIL: could not stub KAH line"; exit 1; }
mkdir -p "$t/runs"; fail=0
run() { env -u KAH_INSTANCE -u KAH_DIR -u STOBE_AUTO_LIVE KAH_RUNS_DIR="$t/runs" "$@" python3 "$t/stobe-auto" status 2>"$t/err"; }
chk() { local n="$1" want="$2"; shift 2; run "$@" >"$t/out"; local rc=$?
  if [ "$rc" = "$want" ]; then echo "ok   $n"; else echo "FAIL $n (rc=$rc want $want)"; fail=$((fail+1)); fi; }
chk 'no lock, bare: allowed' 0 env
touch "$t/runs/game-3.lock"
chk 'lock held, bare, KAH_INSTANCE unset: REFUSED' 2 env
grep -q 'STOBE_AUTO_LIVE=1' "$t/err" && grep -q 'KAH_INSTANCE' "$t/err" && echo "ok   refusal names fix + opt-out" || { echo "FAIL refusal message"; fail=$((fail+1)); }
chk 'lock held, KAH_INSTANCE=3: allowed' 0 env KAH_INSTANCE=3
chk 'lock held, STOBE_AUTO_LIVE=1: allowed' 0 env STOBE_AUTO_LIVE=1
chk 'lock held, KAH_DIR set: allowed' 0 env KAH_DIR=/x/mods/AutomationHarness
env -u KAH_INSTANCE -u KAH_DIR KAH_RUNS_DIR="$t/runs" python3 "$t/stobe-auto" --dir /x status >/dev/null 2>&1 && echo "ok   lock held, --dir: allowed" || { echo "FAIL --dir"; fail=$((fail+1)); }
env -u KAH_INSTANCE -u KAH_DIR KAH_RUNS_DIR="$t/runs" python3 "$t/stobe-auto" help >/dev/null 2>&1 && echo "ok   lock held, help: allowed" || { echo "FAIL help"; fail=$((fail+1)); }
rm -f "$t/runs/game-3.lock"
chk 'lock released, bare: allowed' 0 env
if [ "$fail" -gt 0 ]; then echo "SELFTEST FAIL ($fail)"; exit 1; else echo "SELFTEST OK"; fi
