#!/usr/bin/env bash
# hx-selftest_v2.sh (imm26-sfU2): OFFLINE self-test of hxdefs_v2.sh (rd_16bx with the combat-row purge) and hxrun_v2.sh.  No game, ssh or DB: the lane is simulated by hxfake.py,
# the assert_*.py scripts by logging stubs.  The v1 files are only READ.
# Prints `SELFTEST hxv2-<name> PASS|FAIL` and `SELFTEST HXV2 ALL PASS|FAIL n/m`.  Usage: bash rowtools/hx-selftest_v2.sh
ST_HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; A="$ST_HERE/.."
PYB=$(command -v python3 || command -v python); export PYB
T=$(mktemp -d); command -v cygpath >/dev/null && T=$(cygpath -m "$T"); export KAH_ROWS_BASE="$T/runs" KAH_ROW_FAKE=1 KAH_ROW_FAKE_LOG="$T/fake.log" KAH_PF_ISOLATION=0 KAH_PF_LLM=0 FAKE_STATE="$T/state.json"
export ROW_SETTLE=0 ROW_WAIT=1 STUB_LOG="$T/assert.log"
unset KAH_AGENT_NAME KAH_ROW_DRY HX_OUT HX_SAVE HX_SAVE2 HX13_RUNS HX_KEEP HX_PRELOADED HX_NATIVE HX_ASSERT_DIR
mkdir -p "$KAH_ROWS_BASE" "$T/stubs"
printf '%s\n' 'import os, sys' "open(os.environ['STUB_LOG'], 'a').write(' '.join(sys.argv[1:]) + chr(10))" "print('RESULT %s %s stub-evidence' % (sys.argv[1], os.environ.get('STUB_KIND', 'PASS')))" > "$T/stubs/assert_claims.py"
for s in stance witness principle; do cp "$T/stubs/assert_claims.py" "$T/stubs/assert_$s.py"; done
n=0; ok=0
chk() { n=$((n+1)); if [ "$2" = ok ]; then ok=$((ok+1)); echo "SELFTEST hxv2-$1 PASS ${3:-}"; else echo "SELFTEST hxv2-$1 FAIL ${3:-}"; fi; }
D2="$ST_HERE/hxdefs_v2.sh"; R2="$ST_HERE/hxrun_v2.sh"
PURGE="delete from eventlog where type in ('combat','combat_start','combat_end','knockout','major_damage','limb_loss','recovered')"

# ---- 1. syntax
bash -n "$D2" && chk bash-n-defs ok || chk bash-n-defs bad
bash -n "$R2" && chk bash-n-run ok || chk bash-n-run bad

# ---- 2. rd_16bx v2 in the fake lane: PASS line with the exact stub argv, purge after BOTH loads (and before the first sample / the control resolve)
. "$A/go-row.sh"; . "$ST_HERE/hxdefs.sh"; . "$D2"
PY="$ST_HERE/pywrap_hx.sh"
lt_fake() { "$PYB" "$ST_HERE/hxfake.py" "$@"; }
export HX_ASSERT_DIR="$T/stubs"
export FAKE_SCEN="$T/scen.json"; "$PYB" "$ST_HERE/hxscen.py" base > "$FAKE_SCEN"; : > "$KAH_ROW_FAKE_LOG"
L=5090-i3
r=$(gr_main --allow-retry selftest 16-bx $L 2>/dev/null)
case "$r" in "RESULT 16-bx PASS"*) chk 16-bx-v2-pass ok;; *) chk 16-bx-v2-pass bad "$r";; esac
got=$(tail -1 "$STUB_LOG" 2>/dev/null | tr '\\' '/' | sed -E 's#[^ ]*/##g')
[ "$got" = "16-bx --target R1 R2 R3 --ctl O1 O2 O3 --trait reserved" ] && chk 16-bx-v2-assert-argv ok || chk 16-bx-v2-assert-argv bad "$got"
np=$(grep -cF -- "$PURGE" "$KAH_ROW_FAKE_LOG")
[ "$np" = 2 ] && chk purge-twice ok || chk purge-twice bad "count=$np"
# order per purge: nearest preceding dbclean is <= 2 lines before it, the nearest load before that dbclean is the load of this phase, and no load lies between load and purge
F="$KAH_ROW_FAKE_LOG"; ph_ok=0
for k in 1 2; do
  pk=$(grep -nF -- "$PURGE" "$F" | sed -n ${k}p | cut -d: -f1); [ -n "$pk" ] || continue
  dk=$(grep -n "UPDATE stobe_social_contract SET status='EXPIRED'" "$F" | cut -d: -f1 | awk -v p="$pk" '$1<p{d=$1} END{print d}')
  lk=$(grep -n 'stobe-auto load ' "$F" | cut -d: -f1 | awk -v d="${dk:-0}" '$1<d{l=$1} END{print l}')
  nl=$(grep -n 'stobe-auto load ' "$F" | cut -d: -f1 | awk -v l="${lk:-0}" '$1>l{print $1; exit}')
  [ -n "$dk" ] && [ -n "$lk" ] && [ "$lk" -lt "$dk" ] && [ "$dk" -lt "$pk" ] && [ "$((pk - dk))" -le 2 ] && { [ -z "$nl" ] || [ "$nl" -gt "$pk" ]; } && ph_ok=$((ph_ok+1))
done
[ "$ph_ok" = 2 ] && chk purge-right-after-dbclean-of-each-load ok || chk purge-right-after-dbclean-of-each-load bad "ok_phases=$ph_ok"
EVD="$KAH_ROWS_BASE/imm26-5090-i3/rows/16-bx"
grep -q 'lock_profile=true' "$KAH_ROW_FAKE_LOG" && [ -f "$EVD/R3/haff.txt" ] && [ -f "$EVD/O3/inv_after.txt" ] && chk rest-of-16bx-unchanged ok || chk rest-of-16bx-unchanged bad
# the v1 rd_16bx must NOT purge (v1 stays as the operators have it)
n1=$(declare -f hx16_purge | wc -l); [ "$n1" -gt 1 ] && ! sed -n '/^rd_16bx()/,/^}/p' "$ST_HERE/hxdefs.sh" | grep -q 'combat_start' && chk v1-rd_16bx-unpurged ok || chk v1-rd_16bx-unpurged bad

# ---- 3. hxrun_v2.sh: row gate, default v2 assert dir, dry run
r=$(bash "$R2" 17-bx $L --dry 2>&1 | tail -1); echo "$r" | grep -q '^RESULT 17-bx SETUP-FAIL not a v2 row' && chk run-refuses-other-rows ok || chk run-refuses-other-rows bad "$r"
r=$(bash "$R2" 15-bx $L --dry 2>&1 | tail -1); echo "$r" | grep -q 'SETUP-FAIL not a v2 row' && chk run-refuses-15bx ok || chk run-refuses-15bx bad "$r"
grep -q 'export HX_ASSERT_DIR="${HX_ASSERT_DIR:-$(cd "$HX_HERE/../v2" && pwd)}"' "$R2" && grep -q 'hxdefs_v2.sh' "$R2" && chk run-sources-v2-and-exports-assert-dir ok || chk run-sources-v2-and-exports-assert-dir bad
# the export really resolves to the v2 directory that holds the asserters
r=$(env -u HX_ASSERT_DIR bash -c "HX_HERE='$ST_HERE'; $(grep -m1 '^export HX_ASSERT_DIR=' "$R2" | sed 's/   #.*//'); echo \$HX_ASSERT_DIR")
[ -f "$r/assert_stance.py" ] && [ -f "$r/imm26_lib.py" ] && case "$r" in */imm26-assert/v2) chk assert-dir-is-v2 ok;; *) chk assert-dir-is-v2 bad "$r";; esac || chk assert-dir-is-v2 bad "$r"
# whole hxrun_v2.sh in dry mode for each allowed row: ends in exactly one RESULT line (no real lane)
for row in 16-bx 02-ax 02-cx; do
  r=$(env KAH_ROW_DRY=1 HX_ASSERT_DIR="$T/stubs" bash "$R2" $row $L --dry --no-reload --save s1 --allow-retry selftest 2>&1 | grep -c "^RESULT $row ")
  [ "$r" = 1 ] && chk "run-dry-$row-one-result" ok || chk "run-dry-$row-one-result" bad "lines=$r"
done

# ---- 4. v1 files untouched
git -C "$A/../../.." diff --quiet -- testing/live-stobe-queue/imm26-assert/rowtools/hxdefs.sh testing/live-stobe-queue/imm26-assert/rowtools/hxrun.sh testing/live-stobe-queue/imm26-assert/rowtools/hxcheck.py testing/live-stobe-queue/imm26-assert/assert_stance.py 2>/dev/null && chk v1-files-untouched ok || chk v1-files-untouched bad "modified"

rm -rf "$T"
if [ "$ok" = "$n" ]; then echo "SELFTEST HXV2 ALL PASS $ok/$n"; exit 0; else echo "SELFTEST HXV2 ALL FAIL $ok/$n"; exit 1; fi
