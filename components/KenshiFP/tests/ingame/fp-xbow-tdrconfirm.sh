#!/usr/bin/env bash
# fp-xbow-tdrconfirm.sh: TDR confirm rows for the crossbow fixes kfp-tdr-hmat + kfp-tdr-pinguard (xbow-confirm 2026-10-11,
# safe-confirm plan in C:\KenshiTestRuns\agents\tdr-offline.handoff.md section 5). Two short modes (one RESULT line each):
#   cycle  (row XBCYC): N x { R draw; aim (adapter input) until shot_ready; release; R holster }, NO trigger ever pulled.
#          Reads the `[vm] pinguard` lines KenshiFP.log wrote during the row (mode 40 stale gun / 41 off-thread: proves the
#          pin suspect was live with no shot fired). PASS = N cycles reached shot_ready, 0 shots, no TDR, game answered.
#   reload (row XBRLD): N x { aim; one manual shot at the pinned target; auto reload; wait until loaded again }.
#          PASS = N shots fired, N reloads finished (loaded=1 after each), no TDR, game answered after every shot.
# Every iteration checks the System log (nvlddmkm 153 / Display 4101, gpu-tdr-check.ps1) and stops at the first TDR.
# Usage: fp-xbow-tdrconfirm.sh cycle|reload [shooter] [target] [outdir] [N]  (WSL or Git Bash via rig-env, kah-fpxbow)
MODE=${1:-cycle}; SH=${2:-Axima}; TG=${3:-Skaera}; OUT=${4:-/tmp/fp-xbow-tdrconfirm}; N=${5:-5}
case "$MODE" in cycle) ROW=XBCYC;; reload) ROW=XBRLD;; *) echo "RESULT XBCYC FAIL setup: unknown mode $MODE"; exit 1;; esac
. "$(dirname "$0")/take-preflight.sh"; pf_begin $ROW; pf_outdir "$OUT"
LOG="$OUT/log.txt"; : > "$LOG"
KFPLOG=${KFPLOG:-${KDIR:-/mnt/d/Steam/steamapps/common/Kenshi}/KenshiFP.log}
A() { local r; r=$(stobe-auto "$@" </dev/null 2>&1); echo "> $* | $r" >> "$LOG"; echo "$r"; }
PF_A() { A "$@"; }
fld() { grep -o "\b$1=[^ ]*" | head -1 | cut -d= -f2; }
cs() { A fp_combat state | fld "$1"; }
inp() { A fp_combat input "$1" "$2" "$3" >/dev/null; }
waitfor() { local end=$((SECONDS+$1)); while [ $SECONDS -lt $end ]; do [ "$(cs "$2")" = "$3" ] && return 0; sleep 0.2; done; return 1; }
TDRF="$(cd "$(dirname "$0")/../../../../tools/automation" 2>/dev/null && pwd)/gpu-tdr-check.ps1"
tdrcheck() { if [ -f "$TDRF" ]; then powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$( (command -v wslpath >/dev/null && wslpath -w "$TDRF") || cygpath -w "$TDRF")" -Minutes "$1"
  else powershell.exe -NoProfile -Command "\$e=Get-WinEvent -FilterHashtable @{LogName='System'; Id=4101,153; StartTime=(Get-Date).AddMinutes(-$1)} -ErrorAction SilentlyContinue | Where-Object { \$_.ProviderName -in 'nvlddmkm','Display' }; if (\$e) { 'TDR {0} last={1}' -f @(\$e).Count, @(\$e)[0].TimeCreated.ToString('HH:mm:ss') } else { 'TDR NONE' }"
  fi </dev/null | tr -d '\r' | tail -1; }
tdrnow() { tdrcheck $(( ($(date +%s)-T0)/60 + 2 )); }
cleanup() { A fp_combat input 0 0 0 >/dev/null; A fp_combat off >/dev/null; A fp_combat physical >/dev/null; }
PF_ON_FAIL=cleanup
trap "exit 143" TERM INT HUP
T0=$(date +%s); KL0=$(wc -l < "$KFPLOG" 2>/dev/null || echo 0)
A status | grep -q phase=world || pf_fail "not in world"
[ "$(A rangedinfo "$SH" | fld bow)" != none ] || pf_fail "$SH has no ranged weapon"
tdrcheck 5 | grep -q 'TDR NONE' || pf_fail "a TDR in the 5 min before the row (stale device?)"
pf_day >> "$LOG" 2>&1
A protect "$SH" on >/dev/null; A pin "$TG" at "$SH" dist 25 face "$SH" >/dev/null; A protect "$TG" on >/dev/null
A select "$SH" >/dev/null; A fp_mode on >/dev/null; sleep 1; A fp_control take >/dev/null; A fp_camera distance 0 >/dev/null
pf_iso >> "$LOG" || pf_fail "input isolation off"
read -r sx sz <<<"$(A where "$SH" | grep -o 'pos=[^ ]*' | cut -d= -f2 | awk -F, '{print $1, $3}')"
read -r tx tz <<<"$(A where "$TG" | grep -o 'pos=[^ ]*' | cut -d= -f2 | awk -F, '{print $1, $3}')"
YAW=$(awk -v a="$sx" -v b="$sz" -v c="$tx" -v d="$tz" 'BEGIN{printf "%.4f", atan2(c-a, d-b)}')
A fp_camera look "$YAW" 0.02 >/dev/null
arm() { pf_combat_on "$SH" || pf_fail "$PF_WHY"; inp 0 0 0; pf_ranged_inj "$SH" >> "$LOG" 2>&1 || pf_fail "$PF_WHY"
        A fp_camera look "$YAW" 0.02 >/dev/null; }
ok=0; stop=""; TDR="TDR NONE"; S0=""; extra=""
if [ "$MODE" = cycle ]; then
  arm; S0=$(cs actual_shots); A fp_combat autoreload 1 >/dev/null
  for ((i=1; i<=N; i++)); do
    # holster (R) -> draw (R) -> combat on -> aim to shot_ready -> release; never a trigger
    cleanup; sleep 1
    [ "$(pf_st)" = holstered ] || { A key_inject r tap 120 >/dev/null; pf_waitst holstered 6 || { stop="cycle $i: R holster failed (vm=$(pf_st))"; break; }; }
    sleep 1; A key_inject r tap 120 >/dev/null; e=$((SECONDS+6)); s=holstered
    while [ $SECONDS -lt $e ]; do s=$(pf_st); [ -n "$s" ] && [ "$s" != holstered ] && break; sleep 0.2; done
    [ -n "$s" ] && [ "$s" != holstered ] || { stop="cycle $i: R draw: crossbow never in hand (vm=$s)"; break; }
    pf_combat_on "$SH" || { stop="cycle $i: $PF_WHY"; break; }
    A fp_camera look "$YAW" 0.02 >/dev/null
    inp 1 0 0; if waitfor 16 shot_ready 1; then sleep 1.0; ok=$((ok+1)); else echo "cycle $i: no shot_ready (why=$(cs why))" >> "$LOG"; fi
    A fp_vm state | fld pin >> "$LOG"; inp 0 0 0; sleep 1.0
    [ -z "$(cs actual_shots)" ] && { stop="game silent after cycle $i"; break; }
    TDR=$(tdrnow); [ "$TDR" != "TDR NONE" ] && { stop="TDR after cycle $i"; break; }
  done
  S1=$(cs actual_shots); extra="shots ${S0:-?}->${S1:-?}"
  [ -n "$S0" ] && [ "$S0" != "$S1" ] && stop="${stop:+$stop; }a shot was fired in a no-fire row"
else
  arm; A fp_combat autoreload 1 >/dev/null; rl=0
  for ((i=1; i<=N; i++)); do
    s0=$(cs actual_shots); rs0=$(cs reload_starts); shot=0; inp 1 0 0
    if waitfor 15 shot_ready 1; then
      inp 1 1 0; end=$((SECONDS+3))
      while [ $SECONDS -lt $end ]; do s1=$(cs actual_shots); [ -n "$s1" ] && [ "$s1" != "$s0" ] && { shot=1; break; }; sleep 0.1; done
    fi
    inp 1 0 0
    TDR=$(tdrnow); [ "$TDR" != "TDR NONE" ] && { stop="TDR after shot $i"; break; }
    [ -z "$(cs actual_shots)" ] && { stop="game silent after shot $i"; break; }
    # auto reload while aiming the empty bow; wait for it to finish (native ~6 s) and the bow to be loaded again
    rsee=0; waitfor 6 reloading 1 && rsee=1; waitfor 20 reloading 0; sleep 0.5
    l=$(pf_loaded_n); rs1=$(cs reload_starts)
    echo "shot $i: fired=$shot reloading_seen=$rsee reload_starts $rs0->$rs1 loaded=$l" >> "$LOG"
    [ "$shot" = 1 ] && [ "${l:-0}" -ge 1 ] && { [ "$rsee" = 1 ] || [ "$rs1" != "$rs0" ]; } && { ok=$((ok+1)); rl=$((rl+1)); }
    RS1=$rs1; [ -z "$RS0" ] && RS0=$rs0
    inp 0 0 0; sleep 0.8
    TDR=$(tdrnow); [ "$TDR" != "TDR NONE" ] && { stop="TDR after reload $i"; break; }
    [ -z "$(cs actual_shots)" ] && { stop="game silent after reload $i"; break; }
  done
  extra="reloads_done=${rl:-0} reload_starts=${RS0:-?}->${RS1:-?}"
fi
[ -z "$stop" ] && TDR=$(tdrnow)
PG=$(tail -n +$((KL0+1)) "$KFPLOG" 2>/dev/null | grep -a '\[vm\] pinguard' | sed 's/ (.*//' | sort | uniq -c | tr -s ' ' | tr '\n' ';')
SC=$(tail -n +$((KL0+1)) "$KFPLOG" 2>/dev/null | grep -ac '\[tdr\] manual shot #')
[ -z "$stop" ] && cleanup
pf_game_done
ev="mode=$MODE ok=$ok/$N $extra manual_shot_lines=$SC pinguard={${PG:-none}} $TDR${stop:+ stop='$stop'}"
if [ "$TDR" != "TDR NONE" ] || [ -n "$stop" ]; then pf_result FAIL "$ev log=$LOG"
elif [ "$ok" -lt "$N" ]; then pf_result FAIL "only $ok/$N: $ev log=$LOG"
else pf_result PASS "$ev"; fi
