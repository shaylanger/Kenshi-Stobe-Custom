#!/usr/bin/env bash
# hx-selftest.sh: OFFLINE self-test of the hardening rows (hxdefs.sh / hxcheck.py / hxrun.sh: 17-bx 18-cx 16-bx 15-bx 13-ax 02-ax). No game, ssh or DB: lanes are
# simulated by hxfake.py (+ fakelane.py), scenarios from hxscen.py, the assert_*.py scripts are replaced by logging stubs (HX_ASSERT_DIR) to check the exact
# command lines; one real-assert run with garbage files must FAIL cleanly.  Prints `SELFTEST hx-<name> PASS|FAIL` and `SELFTEST HX ALL PASS|FAIL n/m`.  Usage: bash rowtools/hx-selftest.sh
ST_HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; A="$ST_HERE/.."
PYB=$(command -v python3 || command -v python); export PYB
T=$(mktemp -d); export KAH_ROWS_BASE="$T/runs" KAH_ROW_FAKE=1 KAH_ROW_FAKE_LOG="$T/fake.log" KAH_PF_ISOLATION=0 KAH_PF_LLM=0 FAKE_STATE="$T/state.json"
export ROW_SETTLE=0 ROW_WAIT=1 STUB_LOG="$T/assert.log" HX13_SAVES="s1 s2 s3 s4 s5"
unset KAH_AGENT_NAME KAH_ROW_DRY HX_OUT HX_SAVE HX_SAVE2 HX13_RUNS HX_KEEP HX_PRELOADED HX_NATIVE
mkdir -p "$KAH_ROWS_BASE" "$T/stubs"
printf '%s\n' 'import os, sys' "open(os.environ['STUB_LOG'], 'a').write(' '.join(sys.argv[1:]) + chr(10))" "print('RESULT %s %s stub-evidence' % (sys.argv[1], os.environ.get('STUB_KIND', 'PASS')))" > "$T/stubs/assert_claims.py"
for s in stance witness principle; do cp "$T/stubs/assert_claims.py" "$T/stubs/assert_$s.py"; done
n=0; ok=0
chk() { n=$((n+1)); if [ "$2" = ok ]; then ok=$((ok+1)); echo "SELFTEST hx-$1 PASS ${3:-}"; else echo "SELFTEST hx-$1 FAIL ${3:-}"; fi; }
. "$A/go-row.sh"; . "$ST_HERE/hxdefs.sh"
PY="$ST_HERE/pywrap_hx.sh"
lt_fake() { "$PYB" "$ST_HERE/hxfake.py" "$@"; }
scen() { rm -f "$FAKE_STATE" "$FAKE_STATE.hx" "$STUB_LOG"; export FAKE_SCEN="$T/scen.json"; "$PYB" "$ST_HERE/hxscen.py" "$1" > "$FAKE_SCEN"; : > "$KAH_ROW_FAKE_LOG"; }
run() { gr_main --allow-retry "selftest" "$@" 2>/dev/null; }
L=5090-i3; EVD="$KAH_ROWS_BASE/imm26-5090-i3/rows"
export HX_ASSERT_DIR="$T/stubs"
# expect <name> <scenario> <row> <RESULT prefix> [must-contain]
expect() { local r; scen "$2"; r=$(run "$3" $L); case "$r" in "$4"*) if [ -z "${5:-}" ] || echo "$r" | grep -q -- "$5"; then chk "$1" ok; else chk "$1" bad "missing '$5' in: $r"; fi;; *) chk "$1" bad "$r";; esac; }
argline() { tail -1 "$STUB_LOG" 2>/dev/null | sed -E 's#[^ ]*/##g'; }

# --- PASS path per row: the exact assert command line
for pair in "17-bx|17-bx --false F1 F2 F3 --true T1 T2 T3 --item Sabreclaw" "18-cx|18-cx --combat C1 C2 C3 --calm K1 K2 K3 --target Vethra" \
  "16-bx|16-bx --target R1 R2 R3 --ctl O1 O2 O3 --trait reserved" "15-bx|15-bx --out X1 X2 X3 --inrange P1 P2 P3 --asleep S1 --fighters Malzin,Korin,Dalla --starter Malzin" \
  "13-ax|13-ax --pos P1 P2 --neg N1 N2 --ctl C1" "02-ax|02-ax --target T1 T2 T3 --ctl F1 F2 F3"; do
  row=${pair%%|*}; want=${pair#*|}; sc=base; [ "$row" = 18-cx ] && sc=combat
  expect "$row-pass" "$sc" "$row" "RESULT $row PASS" "stub-evidence"
  got=$(argline); [ "$got" = "$want" ] && chk "$row-assert-argv" ok || chk "$row-assert-argv" bad "got '$got' want '$want'"
done
# --- row-specific facts behind the PASS lines
D="$EVD/17-bx"; scen base; run 17-bx $L >/dev/null
grep -qi Sabreclaw "$D/F1/inv.txt" && ! grep -qi Sabreclaw "$D/T1/inv.txt" && chk 17-bx-item-present-then-moved ok || chk 17-bx-item-present-then-moved bad "F1=$(cat "$D/F1/inv.txt" 2>&1) T1=$(cat "$D/T1/inv.txt" 2>&1)"
grep -q 'insert into eventlog' "$KAH_ROW_FAKE_LOG" && grep -q 'Sabreclaw' "$D/item.txt" && chk 17-bx-seed-inserted ok || chk 17-bx-seed-inserted bad
grep -q 'transfer .*Malzin' "$KAH_ROW_FAKE_LOG" && grep -q 'stobe-auto give' "$KAH_ROW_FAKE_LOG" && chk 17-bx-give-and-transfer ok || chk 17-bx-give-and-transfer bad
scen warm; run 17-bx $L >/dev/null; [ -d "$D/F0warm" ] && [ -d "$D/T0warm" ] && chk 17-bx-warmup-when-no-row ok || chk 17-bx-warmup-when-no-row bad
scen combat; run 18-cx $L >/dev/null; D="$EVD/18-cx"
grep -q 'in_combat=true target=Vethra' "$D/C1/state.txt" && grep -q 'in_combat=false' "$D/K1/state.txt" && chk 18-cx-state-combat-then-calm ok || chk 18-cx-state-combat-then-calm bad "$(cat "$D/C1/state.txt" "$D/K1/state.txt" 2>&1)"
grep -q 'Vethra' "$D/target.txt" && grep -qE '^extras_after=0' "$D/phases.txt" && [ "$(grep -c '#' "$D/roster.txt")" = 3 ] && chk 18-cx-target-and-roster ok || chk 18-cx-target-and-roster bad
scen base; run 16-bx $L >/dev/null; D="$EVD/16-bx"
grep -q 'lock_profile=true' "$KAH_ROW_FAKE_LOG" && [ -f "$D/R3/haff.txt" ] && [ -f "$D/O1/inv_before.txt" ] && [ -f "$D/O3/inv_after.txt" ] && grep -q 'Malzin' "$EVD/16-bx/ctl_npc.txt" && chk 16-bx-control-set-up ok || chk 16-bx-control-set-up bad
scen base; run 15-bx $L >/dev/null; D="$EVD/15-bx"
grep -q 'Cind' "$D/X1/distance.txt" && [ -f "$D/X1/distance_after.txt" ] && [ -f "$D/S1/distance.txt" ] && [ -f "$D/P3/distance_after.txt" ] && chk 15-bx-distance-files ok || chk 15-bx-distance-files bad
scen base; run 13-ax $L >/dev/null; D="$EVD/13-ax"
[ "$(cat "$D"/{P1,P2,N1,N2,C1}/save.txt | tr '\n' ' ')" = "s1 s2 s3 s4 s5 " ] && grep -q 'price=20' "$D/P1/deal.txt" && grep -q 'shay_before=100' "$D/P1/cats.txt" && [ ! -f "$D/C1/deal.txt" ] && chk 13-ax-runs-saves-price ok || chk 13-ax-runs-saves-price bad "$(cat "$D/P1/deal.txt" 2>&1)"
grep -q "NEG_TEST_INJECT" "$KAH_ROW_FAKE_LOG" && grep -q 'deadline_unix' "$KAH_ROW_FAKE_LOG" && chk 13-ax-inject-and-breach ok || chk 13-ax-inject-and-breach bad
scen base; run 02-ax $L >/dev/null; D="$EVD/02-ax"
grep -q 'hx_bak_core_npc_master' "$KAH_ROW_FAKE_LOG" && grep -q 'Proud' "$D/F1/profile.txt" && grep -q 'Thoke' "$D/ctl_npc.txt" && chk 02-ax-blank-and-profile ok || chk 02-ax-blank-and-profile bad

# --- a failing assert is a FAIL (stub FAIL), and a GATED partial 13-ax
scen base; r=$(STUB_KIND=FAIL run 17-bx $L); case "$r" in "RESULT 17-bx FAIL"*) chk assert-fail-passes-through ok;; *) chk assert-fail-passes-through bad "$r";; esac
scen base; r=$(HX13_RUNS="P1 P2" run 13-ax $L); case "$r" in "RESULT 13-ax GATED PARTIAL"*N1*C1*) chk 13-ax-partial-gated ok;; *) chk 13-ax-partial-gated bad "$r";; esac

# --- SETUP-FAIL variants (each a different defect, the reason names it)
expect 17-bx-no-reply noreply 17-bx "RESULT 17-bx SETUP-FAIL" "resolved_speaker is not Shay in F2"
expect 17-bx-no-seed noseed 17-bx "RESULT 17-bx SETUP-FAIL" "seed row not inserted"
expect 17-bx-item-not-movable nomove 17-bx "RESULT 17-bx SETUP-FAIL" "could not make the item"
expect 17-bx-npc-missing nocind 17-bx "RESULT 17-bx SETUP-FAIL" "PREFLIGHT-FAIL cannot read dist_to_target"
expect 18-cx-spawn-fails spawnfail 18-cx "RESULT 18-cx SETUP-FAIL" "spawn failed or unparseable"
expect 18-cx-roster-over-3 roster4 18-cx "RESULT 18-cx SETUP-FAIL" "not a strict 1v1"
expect 15-bx-no-fight nostarter 15-bx "RESULT 15-bx SETUP-FAIL" "Initiated attack"
expect 16-bx-no-reply noreply 16-bx "RESULT 16-bx SETUP-FAIL" "resolved_speaker is not Shay in R2"
expect 13-ax-no-price noprice 13-ax "RESULT 13-ax SETUP-FAIL" "no price in the offer reply"
expect 02-ax-no-reply noreply 02-ax "RESULT 02-ax SETUP-FAIL" "resolved_speaker is not Shay in T2"
scen base; r=$(HX13_SAVES="" run 13-ax $L); case "$r" in "RESULT 13-ax SETUP-FAIL no save for run P1"*) chk 13-ax-no-saves ok;; *) chk 13-ax-no-saves bad "$r";; esac
E="$T/empty"; mkdir -p "$E"; r=$("$PYB" "$ST_HERE/hxcheck.py" 17-bx "$E"); case "$r" in "RESULT 17-bx SETUP-FAIL bundle dirs missing"*) chk missing-bundle-dir ok;; *) chk missing-bundle-dir bad "$r";; esac
for d in C1 C2 C3 K1 K2 K3; do mkdir -p "$E/$d"; done; r=$("$PYB" "$ST_HERE/hxcheck.py" 18-cx "$E"); case "$r" in "RESULT 18-cx SETUP-FAIL the row script wrote no value for --target"*) chk missing-target-value ok;; *) chk missing-target-value bad "$r";; esac

# --- the REAL assert on empty/garbage bundles: FAIL or SETUP-FAIL, never a crash
G="$T/garbage"; mkdir -p "$G"; for d in T1 T2 T3 F1 F2 F3; do mkdir -p "$G/$d"; echo x > "$G/$d/reply.txt"; : > "$G/$d/profile.txt"; done
r=$(HX_ASSERT_DIR="" "$PYB" "$ST_HERE/hxcheck.py" 02-ax "$G" 2>&1); case "$r" in *Traceback*) chk real-assert-garbage bad "$r";; "RESULT 02-ax FAIL"*|"RESULT 02-ax SETUP-FAIL"*) chk real-assert-garbage ok;; *) chk real-assert-garbage bad "$r";; esac

# --- hxd_extras pipeline (sed/grep quoting) run for real against a canned `chars` output: keeps Shay/Cind/target/Malzin, moves the other two
r=$( (export EV="$T/exev"; mkdir -p "$EV"; HX_FAR="1 2 3"; unset KAH_ROW_FAKE
  stobe-auto() { case "$1" in chars) echo "5 within 300.0: Shay #1/1 [N] pos=0 | Cind [Hungry Bandit] #2529907200/2 [T] pos=1 | Vethra [Hungry Bandit] #5/1 [H] pos=2 | Rethar Dax #7/1 [O] pos=3 | Bob #8/3 [O] pos=4";; teleport) echo "$*" >> "$EV/tp.txt";; esac; }
  export -f stobe-auto; lt_h() { bash; }; hxd_extras 300 "Shay #|^ *Cind |Vethra |Malzin #" >/dev/null; echo $(sort -u "$EV/extras.txt") $(grep -c 'teleport #7/1 1 2 3' "$EV/tp.txt") ) 2>&1 )
[ "$r" = "7/1 8/3 2" ] && chk extras-pipeline-real-shell ok || chk extras-pipeline-real-shell bad "$r"

# --- CLI hxrun.sh as a separate process (reload, preflight, ONE RESULT line, exit codes, dry run, options)
cli() { bash -c ". '$ST_HERE/lane.sh'; lt_fake() { \"\$PYB\" '$ST_HERE/hxfake.py' \"\$@\"; }; export -f lt_fake; exec bash '$ST_HERE/hxrun.sh' \"\$@\"" _ "$@" 2>/dev/null; }
scen base; o=$(cli 17-bx $L --allow-retry selftest); rc=$?
[ "$(echo "$o" | grep -c '^RESULT ')" = 1 ] && echo "$o" | tail -1 | grep -q '^RESULT 17-bx PASS' && [ $rc = 0 ] && chk cli-hxrun ok || chk cli-hxrun bad "rc=$rc $o"
grep -q 'stobe-auto load kah-imm26-5090-hxA' "$KAH_ROW_FAKE_LOG" && [ "$(grep -c 'stobe-auto load' "$KAH_ROW_FAKE_LOG")" = 2 ] && chk cli-reload-once-then-second-phase-load ok || chk cli-reload-once-then-second-phase-load bad "$(grep 'stobe-auto load' "$KAH_ROW_FAKE_LOG")"
scen base; o=$(cli 17-bx 5090-i4 --no-reload --save my-save --out "$T/out" --allow-retry selftest); echo "$o" | tail -1 | grep -q '^RESULT 17-bx PASS' && [ -d "$T/out/17-bx/F1" ] && chk cli-out-and-no-reload ok || chk cli-out-and-no-reload bad "$o"
scen base; o=$(cli 17-bx $L --dry); echo "$o" | grep -q '^RESULT 17-bx DRY-RUN' && chk cli-dry-run ok || chk cli-dry-run bad "$o"
scen base; o=$(cli 17-bx 4080-i4 --allow-retry selftest); echo "$o" | grep -q 'RESULT 17-bx SETUP-FAIL RELOAD-FAIL no base save known' && chk cli-no-base-save-setup-fail ok || chk cli-no-base-save-setup-fail bad "$o"
o=$(cli 99-z $L); echo "$o" | grep -q 'RESULT 99-z SETUP-FAIL not a hardening row' && chk cli-unknown-row ok || chk cli-unknown-row bad "$o"
scen base; o=$(cli 13-ax $L --runs "P1" --allow-retry selftest); echo "$o" | tail -1 | grep -q '^RESULT 13-ax GATED PARTIAL' && chk cli-13ax-runs-subset-gated ok || chk cli-13ax-runs-subset-gated bad "$o"
grep -q 'stobe-auto load s1' "$KAH_ROW_FAKE_LOG" && chk cli-13ax-first-run-save ok || chk cli-13ax-first-run-save bad "$(grep 'stobe-auto load' "$KAH_ROW_FAKE_LOG" | head -2)"

# --- originals untouched
dd=$(cd "$A" && git diff HEAD --stat -- rowtools/rowdefs.sh rowtools/tripdefs.sh rowtools/rowcheck.py rowtools/rowcheck_trip.py go-row.sh 2>/dev/null)
[ -z "$dd" ] && chk originals-untouched ok || chk originals-untouched bad "$dd"

rm -rf "$T"
if [ $ok = $n ]; then echo "SELFTEST HX ALL PASS $ok/$n"; exit 0; else echo "SELFTEST HX ALL FAIL $ok/$n"; exit 1; fi
