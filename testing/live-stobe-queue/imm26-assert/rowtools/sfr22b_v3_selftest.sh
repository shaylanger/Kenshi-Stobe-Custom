#!/usr/bin/env bash
# sfr22b_v3_selftest.sh: OFFLINE self-test of sfrrun_v3.sh / unblockdefs_f2.sh (strict native arrival for 22-b). Reuses sfrfake.py/sfrscen.py; only the `nend` log lines of the sfr22-pass scenario are swapped.
# Run (WSL): wsl.exe -d DwemerAI4Skyrim3 -u root --cd /mnt/c/KenshiModding/testing/live-stobe-queue/imm26-assert -- bash rowtools/sfr22b_v3_selftest.sh
# Prints `SELFTEST sfr22bv3-<name> PASS|FAIL` and `SELFTEST SFR22BV3 ALL PASS|FAIL n/m`.
ST_HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; A="$ST_HERE/.."
REAL_PY=$(command -v python3 || command -v python)
T=$(mktemp -d); export KAH_ROWS_BASE="$T/runs" KAH_ROW_FAKE=1 KAH_ROW_FAKE_LOG="$T/fake.log" KAH_PF_ISOLATION=0 FAKE_STATE="$T/state.json"
export ROW_SETTLE=0 ROW_WAIT=1 TRIP_SE_TRIES=2 RW_SAY_WAIT=0 SFK_23A_TRIES=3 SFK_KO_WAIT=1
export SFT_INJECT=0
unset KAH_AGENT_NAME KAH_ROW_DRY TRIP_TRAP TRIP_GATE TRIP_SAVE TRIP_DEST TRIP_ACCEPT TRIP_ALT SFK_23A_BACK SFK_23A_SPEED SR_22B_TICKS TRIP_13C_STAGE
mkdir -p "$KAH_ROWS_BASE"
n=0; ok=0
chk() { n=$((n+1)); if [ "$2" = ok ]; then ok=$((ok+1)); echo "SELFTEST sfr22bv3-$1 PASS ${3:-}"; else echo "SELFTEST sfr22bv3-$1 FAIL ${3:-}"; fi; }
L=4080-i4; EVB="$KAH_ROWS_BASE/imm26-4080-i4/rows"; F="$KAH_ROW_FAKE_LOG"
REAL_FIN='[2026-10-16 09:47:21.019] [Stobe] NATIVE_TRAVEL_FINISH: task=order:2529907200:22 phase=completed reason=measured_route_arrival planar=7.7 dy=-3.9'
REAL_PHC='[2026-10-16 09:47:21.807] [Stobe] NATIVE_TRAVEL: task=order:2529907200:22 actor=2529907200 phase=completed reason=measured_route_arrival terminal=1 released=1 arrived=1'
REAL_END0='[2026-10-16 12:51:39.962] [Stobe] NATIVE_TRAVEL_ORDER_ENDED: task=order:2529907200:18 planar=746.6 dy=1246.7 arrived8=0 near16=0 leader_ok=1 viable=1'
REAL_RUN='[2026-10-16 12:51:39.963] [Stobe] NATIVE_TRAVEL: task=order:2529907200:18 actor=2529907200 phase=running reason=native_order_gone_end_unverified terminal=0 released=0 arrived=0'
REAL_END1='[2026-10-16 12:51:39.962] [Stobe] NATIVE_TRAVEL_ORDER_ENDED: task=order:2529907200:18 planar=6.1 dy=0.4 arrived8=1 near16=1 leader_ok=1 viable=1'
REAL_PHF='[2026-10-16 12:51:40.100] [Stobe] NATIVE_TRAVEL: task=order:2529907200:18 actor=2529907200 phase=failed reason=native_order_ended_before_goal terminal=1'
scen() {   # scen <nend lines...> : sfr22-pass with the native end lines replaced
  rm -f "$FAKE_STATE" "$FAKE_STATE".*; export FAKE_SCEN="$T/scen.json"
  "$REAL_PY" "$ST_HERE/sfrscen.py" sfr22-pass | "$REAL_PY" -c 'import json,sys,os; S=json.load(sys.stdin); S["nend"]=sys.argv[1:]; (S.update(term_seq=[""]) if os.environ.get("NOTERM") else None); json.dump(S,sys.stdout)' "$@" > "$FAKE_SCEN"; : > "$F"
}
cli() {
  local script="$1"; shift
  bash -c ". '$ST_HERE/lane.sh'; lt_fake() { '$REAL_PY' '$ST_HERE/sfrfake.py' \"\$@\"; }; export -f lt_fake; export REAL_PY; exec bash '$ST_HERE/$script' \"\$@\"" _ "$@" 2>/dev/null
}
run22() { cli sfrrun_v3.sh 22-b $L --no-reload --ticks 1 --tries 3 --allow-retry selftest; }
# classifier unit checks (the function that decides ARRIVED / FAILED)
. "$ST_HERE/unblockdefs_f2.sh"
cl() { printf '%s\n' "$@" | uf2_classify; }
[ "$(cl "$REAL_FIN")" = ARRIVED ] && chk cls-finish-completed ok || chk cls-finish-completed bad
[ "$(cl "$REAL_PHC")" = ARRIVED ] && chk cls-phase-completed ok || chk cls-phase-completed bad
[ "$(cl "$REAL_END1")" = ARRIVED ] && chk cls-order-ended-arrived8-1 ok || chk cls-order-ended-arrived8-1 bad
[ "$(cl "$REAL_END0" "$REAL_RUN")" = FAILED ] && chk cls-order-ended-arrived8-0-is-failed ok || chk cls-order-ended-arrived8-0-is-failed bad "$(cl "$REAL_END0" "$REAL_RUN")"
[ "$(cl "$REAL_PHF")" = FAILED ] && chk cls-phase-failed ok || chk cls-phase-failed bad
[ "$(cl "$REAL_END0" "$REAL_FIN")" = ARRIVED ] && chk cls-completed-wins ok || chk cls-completed-wins bad
[ -z "$(cl '[x] NATIVE_TRAVEL: task=a phase=running reason=x arrived=0')" ] && chk cls-running-none ok || chk cls-running-none bad
[ -z "$(cl)" ] && chk cls-empty-none ok || chk cls-empty-none bad
# recipe scenarios
scen "$REAL_FIN" "$REAL_PHC"; o=$(run22); echo "$o" | tail -1 | grep -q '^RESULT 22-b PASS' && head -1 "$EVB/22-b/arrival.txt" | grep -q '^end=ARRIVED' && chk recipe-finish-completed-pass ok || chk recipe-finish-completed-pass bad "$(echo "$o" | tail -1 | cut -c1-240)"
scen "$REAL_END1"; o=$(run22); head -1 "$EVB/22-b/arrival.txt" | grep -q '^end=ARRIVED' && chk recipe-order-ended-arrived8-1-arrived ok || chk recipe-order-ended-arrived8-1-arrived bad "$(head -1 "$EVB/22-b/arrival.txt")"
scen "$REAL_END0" "$REAL_RUN"; o=$(run22); echo "$o" | tail -1 | grep -q '^RESULT 22-b SETUP-FAIL' && echo "$o" | tail -1 | grep -q 'ended FAILED' && head -1 "$EVB/22-b/arrival.txt" | grep -q '^end=FAILED' && ! grep -q 'tick1' "$EVB/22-b/sr_ticks.txt" 2>/dev/null && chk recipe-order-ended-arrived8-0-failed-no-ticks ok || chk recipe-order-ended-arrived8-0-failed-no-ticks bad "$(echo "$o" | tail -1 | cut -c1-240) / $(head -1 "$EVB/22-b/arrival.txt")"
scen "$REAL_PHF"; o=$(run22); head -1 "$EVB/22-b/arrival.txt" | grep -q '^end=FAILED' && chk recipe-phase-failed-failed ok || chk recipe-phase-failed-failed bad
NOTERM=1 scen; o=$(run22); echo "$o" | tail -1 | grep -q '^RESULT 22-b SETUP-FAIL' && head -1 "$EVB/22-b/arrival.txt" | grep -q '^end=TIMEOUT' && chk recipe-no-end-timeout ok || chk recipe-no-end-timeout bad
# TRIP_13C_STAGE honoured and gate unchanged
scen "$REAL_FIN"; o=$(TRIP_13C_STAGE="-62380 330 16250" run22); grep -q -- '-62380 330 16250 dist 0' "$F" && echo "$o" | tail -1 | grep -q '^RESULT 22-b PASS' && chk stage-env-honoured ok || chk stage-env-honoured bad "$(echo "$o" | tail -1 | cut -c1-200)"
# original (v2) runner still shows the old behaviour (documents the defect) and the originals are untouched
scen "$REAL_END0" "$REAL_RUN"; o=$(cli sfrrun.sh 22-b $L --no-reload --ticks 1 --tries 3 --allow-retry selftest); head -1 "$EVB/22-b/arrival.txt" | grep -q '^end=ARRIVED' && chk v2-original-still-old-behaviour ok || chk v2-original-still-old-behaviour bad
for f in sfr22b_bored_g.sh unblockdefs_f2.sh sfrrun_v3.sh sfr22b_v3_selftest.sh; do bash -n "$ST_HERE/$f" 2>/dev/null && chk "bash-n-$f" ok || chk "bash-n-$f" bad; done
if git -C "$ST_HERE" rev-parse --git-dir >/dev/null 2>&1; then
  git -C "$ST_HERE" diff --quiet -- unblockdefs_f.sh sfrrun.sh tripdefs_sftrav.sh && chk originals-unmodified ok || chk originals-unmodified bad "git diff shows an edit"
fi
grep -q "observed_gamets" "$ST_HERE/sfr22b_bored_g.sh" && chk bored-g-uses-snapshot-gamets ok || chk bored-g-uses-snapshot-gamets bad
rm -rf "$T"
if [ $ok = $n ]; then echo "SELFTEST SFR22BV3 ALL PASS $ok/$n"; exit 0; else echo "SELFTEST SFR22BV3 ALL FAIL $ok/$n"; exit 1; fi
