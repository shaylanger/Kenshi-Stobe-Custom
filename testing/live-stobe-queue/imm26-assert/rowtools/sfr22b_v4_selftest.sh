#!/usr/bin/env bash
# sfr22b_v4_selftest.sh (imm26-fix22b): OFFLINE self-test of sfrrun_v4.sh / sfr22b_keep.sh (22-b walk that keeps Shay inside the native participation separation).
# The checks marked [old-fails] FAIL when run against the old walk (sfrrun_v3.sh): `SELFTEST_RUNNER=sfrrun_v3.sh bash rowtools/sfr22b_v4_selftest.sh` shows them failing.
# Run (WSL): wsl.exe -d DwemerAI4Skyrim3 -u root --cd /mnt/c/KenshiModding/testing/live-stobe-queue/imm26-assert -- bash rowtools/sfr22b_v4_selftest.sh
# Prints `SELFTEST sfr22bv4-<name> PASS|FAIL` and `SELFTEST SFR22BV4 ALL PASS|FAIL n/m`.
# Model constants come from the native rule (ParticipationEvidence.h: separation>35 u breaks the window; Freeze needs last-first>=30, partner_d>=30, progress>=30 in the LAST window) and from the op26 evidence
# (walk_progress.txt: Shay 7-35 u from the NPC 1.5 s after a teleport => drift up to ~23 u/s; teleport offset ~8 u; one ssh/sql gap between old cycles ~6 s).
ST_HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUNNER="${SELFTEST_RUNNER:-sfrrun_v4.sh}"
REAL_PY=$(command -v python3 || command -v python)
T=$(mktemp -d); export KAH_ROWS_BASE="$T/runs" KAH_ROW_FAKE=1 KAH_ROW_FAKE_LOG="$T/fake.log" KAH_PF_ISOLATION=0 FAKE_STATE="$T/state.json"
export ROW_SETTLE=0 ROW_WAIT=1 TRIP_SE_TRIES=2 RW_SAY_WAIT=0 SFK_23A_TRIES=3 SFK_KO_WAIT=1 SFT_INJECT=0
unset KAH_AGENT_NAME KAH_ROW_DRY TRIP_TRAP TRIP_GATE TRIP_SAVE TRIP_DEST TRIP_ACCEPT TRIP_ALT SFK_23A_BACK SFK_23A_SPEED SR_22B_TICKS TRIP_13C_STAGE SFK_KEEP_N SFK_KEEP_SLEEP SFK_KEEP_CHK SFK_KEEP_WH
mkdir -p "$KAH_ROWS_BASE"
n=0; ok=0
chk() { n=$((n+1)); if [ "$2" = ok ]; then ok=$((ok+1)); echo "SELFTEST sfr22bv4-$1 PASS ${3:-}"; else echo "SELFTEST sfr22bv4-$1 FAIL ${3:-}"; fi; }
L=4080-i4; EVB="$KAH_ROWS_BASE/imm26-4080-i4/rows"; F="$KAH_ROW_FAKE_LOG"
REAL_FIN='[2026-10-16 09:47:21.019] [Stobe] NATIVE_TRAVEL_FINISH: task=order:2529907200:22 phase=completed reason=measured_route_arrival planar=7.7 dy=-3.9'
REAL_PHC='[2026-10-16 09:47:21.807] [Stobe] NATIVE_TRAVEL: task=order:2529907200:22 actor=2529907200 phase=completed reason=measured_route_arrival terminal=1 released=1 arrived=1 participation_qualified=1'
REAL_PHF='[2026-10-16 12:51:40.100] [Stobe] NATIVE_TRAVEL: task=order:2529907200:18 actor=2529907200 phase=failed reason=native_order_ended_before_goal terminal=1'
scen() { rm -f "$FAKE_STATE" "$FAKE_STATE".*; export FAKE_SCEN="$T/scen.json"
  "$REAL_PY" "$ST_HERE/sfrscen.py" sfr22-pass | "$REAL_PY" -c 'import json,sys,os; S=json.load(sys.stdin); S["nend"]=sys.argv[1:]; (S.update(term_seq=[""]) if os.environ.get("NOTERM") else None); json.dump(S,sys.stdout)' "$@" > "$FAKE_SCEN"; : > "$F"; }
cli() { local script="$1"; shift
  bash -c ". '$ST_HERE/lane.sh'; lt_fake() { '$REAL_PY' '$ST_HERE/sfr22b_keep_fake.py' \"\$@\"; }; export -f lt_fake; export REAL_PY; exec bash '$ST_HERE/$script' \"\$@\"" _ "$@" 2>/dev/null; }
run22() { cli "$RUNNER" 22-b $L --no-reload --ticks 1 --tries 3 --allow-retry selftest; }
# the walk call(s) of a recipe run: fake-log blocks (### h ...) that teleport Shay inside a loop
walkblocks() { "$REAL_PY" - "$F" <<'PY'
import re,sys
t=open(sys.argv[1],encoding='utf-8',errors='replace').read()
for b in re.split(r'(?m)^### ',t):
    if 'teleport Shay' in b and re.search(r'\bfor i in\b',b): print(b.replace('\n','\n'))
PY
}
# --- behaviour: recipe still passes / classifies on the fake lane
scen "$REAL_FIN" "$REAL_PHC"; o=$(run22); echo "$o" | tail -1 | grep -q '^RESULT 22-b PASS' && head -1 "$EVB/22-b/arrival.txt" | grep -q '^end=ARRIVED' && chk recipe-pass ok || chk recipe-pass bad "$(echo "$o" | tail -1 | cut -c1-200)"
W=$(walkblocks)
[ -n "$W" ] && chk walk-block-found ok || chk walk-block-found bad
# [old-fails] the end-of-walk detection is inside the teleport call (no per-cycle ssh/sql gap with Shay unmoved)
echo "$W" | grep -q 'uf:nend' && chk keeper-checks-native-end-in-call ok || chk keeper-checks-native-end-in-call bad
# [old-fails] teleport interval: sleep between Shay teleports <= 0.7 s (old: 1.5 s)
SL=$(echo "$W" | grep -oE 'sleep [0-9.]+' | head -1 | cut -d' ' -f2)
"$REAL_PY" -c 'import sys; s=float(sys.argv[1]); sys.exit(0 if 0<s<=0.7 else 1)' "${SL:-9}" && chk teleport-sleep-le-0.7 ok "sleep=$SL" || chk teleport-sleep-le-0.7 bad "sleep=${SL:-none}"
# [old-fails] model: max separation between teleports = offset 8 + drift 23 u/s * (sleep + 0.5 s command latency) must stay <= 35 u (native Break(1))
"$REAL_PY" -c 'import sys; s=float(sys.argv[1]); m=8+23*(s+0.5); print("max_sep_model=%.1f"%m); sys.exit(0 if m<=35 else 1)' "${SL:-9}" >/dev/null && chk model-max-separation-le-35 ok || chk model-max-separation-le-35 bad
# [old-fails] model: one unbroken window must cover >= 30 game-s (Freeze last-first>=30) between unavoidable gaps: iterations*(sleep+0.5) per call
IT=$(echo "$W" | grep -oE 'seq 1 [0-9]+' | head -1 | awk '{print $3}')
"$REAL_PY" -c 'import sys; it=int(sys.argv[1]); s=float(sys.argv[2]); w=it*(s+0.5); print("window_s=%.0f"%w); sys.exit(0 if w>=45 else 1)' "${IT:-0}" "${SL:-9}" >/dev/null && chk model-window-ge-45s ok "iters=$IT" || chk model-window-ge-45s bad "iters=${IT:-none}"
# arrival still classified strictly (v3 behaviour kept): phase=failed => SETUP-FAIL end=FAILED
scen "$REAL_PHF"; o=$(run22); head -1 "$EVB/22-b/arrival.txt" | grep -q '^end=FAILED' && echo "$o" | tail -1 | grep -q '^RESULT 22-b SETUP-FAIL' && chk phase-failed-setupfail ok || chk phase-failed-setupfail bad
NOTERM=1 scen; o=$(run22); echo "$o" | tail -1 | grep -q '^RESULT 22-b SETUP-FAIL' && head -1 "$EVB/22-b/arrival.txt" | grep -q '^end=TIMEOUT' && chk no-end-timeout ok || chk no-end-timeout bad
scen "$REAL_FIN" "$REAL_PHC"; o=$(run22); [ "$(wc -l < "$EVB/22-b/walk_progress.txt")" -ge 1 ] && grep -q 'pos=' "$EVB/22-b/walk_progress.txt" && chk walk-progress-written ok || chk walk-progress-written bad
scen "$REAL_FIN"; o=$(TRIP_13C_STAGE="-62380 330 16250" run22); grep -q -- '-62380 330 16250 dist 0' "$F" && echo "$o" | tail -1 | grep -q '^RESULT 22-b PASS' && chk stage-env-honoured ok || chk stage-env-honoured bad
# files / originals
for f in sfr22b_keep.sh sfrrun_v4.sh sfr22b_v4_selftest.sh; do bash -n "$ST_HERE/$f" 2>/dev/null && chk "bash-n-$f" ok || chk "bash-n-$f" bad; done
if git -C "$ST_HERE" rev-parse --git-dir >/dev/null 2>&1; then
  git -C "$ST_HERE" diff --quiet -- unblockdefs_f.sh unblockdefs_f2.sh sfrrun.sh sfrrun_v3.sh sfrdefs.sh sfrfake.py && chk originals-unmodified ok || chk originals-unmodified bad "git diff shows an edit"
fi
rm -rf "$T"
if [ $ok = $n ]; then echo "SELFTEST SFR22BV4 ALL PASS $ok/$n"; exit 0; else echo "SELFTEST SFR22BV4 ALL FAIL $ok/$n"; exit 1; fi
