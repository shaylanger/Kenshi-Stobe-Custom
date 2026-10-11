#!/bin/bash
# gfx-measure.sh <save> <out> [sec]  (row script, both rigs: 5090 WSL / 4080 Git Bash; res-graphics 2026-10-10)
# Measures the test-launch frame cap + low graphics mode (kenshi-gfx.ps1) on the running game:
#   full graphics (as launched): uncapped vs cap 60 at speed 1 (fps, GPU %, Kenshi CPU %, private MB), and game hours per
#   real second at speed 50 uncapped vs cap 60 (the cap must not slow game time); then stop, gfx low, relaunch <save>,
#   low + cap 60 (and low uncapped) at speed 1; then gfx full + relaunch <save> again so the next list gets full graphics.
# Needs a harness with FrameCap (framecap.txt, Plugin.cpp 2026-10-10): checked from harness.log "KAH: frame cap".
# PASS = cap 60 holds (avg fps <= 63) and speed-50 game time with the cap >= 90% of uncapped; one RESULT GFXM line.
# Row line: GFXM | <save> | - | - | 1500 | STALL_MIN=20 bash {CR}/KenshiModding/tools/automation/gfx-measure.sh <save> {OUT}/GFXM
set -u; RIG=${RIG:-}   # rig-env.sh reads $RIG (unset under set -u = abort)
. "$(dirname "$0")/rig-env.sh"
SAVE=${1:?save}; OUT=${2:?out}; SEC=${3:-30}
mkdir -p "$OUT"; LOG="$OUT/gfx-measure.log"; : > "$LOG"
CAPF="$KDIR/mods/AutomationHarness/framecap.txt"
A() { local r; r=$(stobe-auto "$@" 2>&1); echo "> $* | $r" >> "$LOG"; echo "$r"; }
ps() { powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$@" 2>&1 | tr -d '\r'; }
WPS() { if [ "$RIG" = 4080 ]; then cygpath -w "$1"; else wslpath -w "$1"; fi; }
SAMPLE=$(WPS "$CR/KenshiModding/tools/automation/gfx-sample.ps1")
cap() { if [ "$1" = 0 ]; then echo 0 > "$CAPF"; else echo "$1" > "$CAPF"; fi; sleep 3; }
fail() { echo "RESULT GFXM FAIL $*"; echo "FAIL $*" >> "$LOG"; cap 60; exit 1; }
# phase <label> <cap>: speed 1, cap, settle, fps window + resource sample
phase() { local f s; cap "$2"; A speed 1 >/dev/null; sleep 5; A fps reset >/dev/null
  s=$(ps "$SAMPLE" -Sec "$SEC" | tail -1); f=$(A fps | grep -o 'avg=[0-9.]*' | cut -d= -f2)
  echo "$1 fps=$f $s" >> "$LOG"; echo "$1: fps=$f $s"; }
ghours() { A time | grep -oE '(game_)?hours=[0-9.]+' | head -1 | cut -d= -f2; }
rate() { local h0 h1 t0 t1; cap "$1"; A speed 50 >/dev/null; sleep 3; h0=$(ghours); t0=$(date +%s.%N); sleep 20; h1=$(ghours); t1=$(date +%s.%N)
  A speed 1 >/dev/null; awk -v a="$h0" -v b="$h1" -v s="$t0" -v e="$t1" 'BEGIN { if (a == "" || b == "") print "?"; else printf "%.4f", (b - a) / (e - s) }'; }
setgfx() { if [ "$RIG" = 4080 ]; then ps 'C:\KAH\kcfg.ps1' test -Gfx "$1"; else ps 'C:\KenshiModding\tools\automation\kenshi-ctl.ps1' gfx "$1"; fi; }
# 5090: kenshi-ctl launch applies the gfx mode itself (KAH_GFX passed through WSLENV); 4080: ctl.ps1 keeps what kcfg set
relaunch() { rig_stop >> "$LOG" 2>&1; sleep 3; setgfx "$1" >> "$LOG"; KAH_GFX=$1 WSLENV="${WSLENV:+$WSLENV:}KAH_GFX" rig_launch "$SAVE" >> "$LOG" 2>&1 &
  local lp=$!; A wait-world 900 >/dev/null || { kill $lp 2>/dev/null; return 1; }; kill $lp 2>/dev/null; sleep 5
  # the killed launch proxy skipped kenshi-ctl's re-place + render fit (as run-batch.sh launch does it afterwards)
  [ "$RIG" = 4080 ] || ps 'C:\KenshiModding\tools\automation\kenshi-ctl.ps1' postlaunch >> "$LOG"; sleep 5; }

A wait-world 300 | grep -q . || fail "setup: game not in the world"
grep -q 'KAH: frame cap' "$KDIR/mods/AutomationHarness/harness.log" 2>/dev/null || { cap 60; sleep 2; A status >/dev/null
  grep -q 'KAH: frame cap' "$KDIR/mods/AutomationHarness/harness.log" || fail "setup: installed harness has no frame cap (no 'KAH: frame cap' in harness.log)"; }
G0=$(ps 'C:\KenshiModding\tools\automation\kenshi-gfx.ps1' status 2>/dev/null | tail -1); [ "$RIG" = 4080 ] && G0=$(ps 'C:\KAH\kenshi-gfx.ps1' status | tail -1)
echo "rig=$RIG start: $G0" >> "$LOG"
FU=$(phase full_uncapped 0); FC=$(phase full_cap60 60)
RU=$(rate 0); RC=$(rate 60)
relaunch low || fail "setup: low-graphics relaunch did not reach the world | $FU | $FC"
LC=$(phase low_cap60 60); LU=$(phase low_uncapped 0)
relaunch full || echo "NOTE full relaunch did not reach the world" >> "$LOG"
cap 60
EV="rig=$RIG $FU | $FC | $LC | $LU | speed50 game_h/s uncapped=$RU cap60=$RC"
CF=$(sed -n 's/.*fps=\([0-9.]*\).*/\1/p' <<<"$FC"); LF=$(sed -n 's/.*fps=\([0-9.]*\).*/\1/p' <<<"$LC")
OK=$(awk -v c="$CF" -v l="$LF" -v ru="$RU" -v rc="$RC" 'BEGIN { ok = (c != "" && c <= 63 && l != "" && l <= 63); if (ru != "?" && rc != "?" && ru > 0) ok = ok && (rc >= 0.9 * ru); print ok ? 1 : 0 }')
[ "$OK" = 1 ] && echo "RESULT GFXM PASS $EV" || echo "RESULT GFXM FAIL $EV (log $LOG)"
