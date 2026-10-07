#!/bin/bash
# fp-navcrash-repro.sh: repro for the 5090 NavMesh-thread crash (m50 K/M/N): Havok A* reads a garbage navmesh face map
# 4-5 s after the KenshiFP `[weld] world-scale centre jump` + `[weld] rebase shift`, which came right after the
# fp-control/fp-stealth setup (protect + ko Skaera) on kah-fpxbow loaded in-session.
# Root cause (found with this script, 2026-10-07): the ranged free-aim pose override wrote the crosshair point
# through animationUpdate's const aimpos reference (a caller stack local); fixed by passing KenshiFP's own vector.
# Variants: FP=off clean 3/3, KO=0 still crashed, ranged_freeaim=0 clean 3/3.
# Each try: in-session `load <save>` -> wait-world -> FP on/off/keep -> protect squad + ko target -> watch WAIT s for the
# crash dump / Kenshi gone. Stops at the first crash (the game is dead or pathing is broken).
# Usage (WSL): fp-navcrash-repro.sh [tries] [outdir]. Env: SAVE (kah-fpxbow), PLAYER (Axima), MATE (Malzin),
# TARGET (Skaera), FP (on|off|keep, default on), KO (1|0, default 1), WAIT (45), LABEL (free text for the RESULT lines).
# Prints one line per try: RESULT navcrash-<label>-<n> CRASH|CLEAN rebase=<n> jump=<n>, then a summary line.
TRIES=${1:-3}; OUT=${2:-/tmp/navcrash}; mkdir -p "$OUT"; LOG="$OUT/repro.log"
SAVE=${SAVE:-kah-fpxbow}; SH=${PLAYER:-Axima}; MT=${MATE:-Malzin}; TG=${TARGET:-Skaera}; FP=${FP:-on}; KO=${KO:-1}
WAIT=${WAIT:-45}; LABEL=${LABEL:-fp$FP-ko$KO}
K=/mnt/d/Steam/steamapps/common/Kenshi; KFP="$K/KenshiFP.log"; DMP="$K/crashDump1.0.65_x64.dmp"
A() { local r; r=$(timeout 30 stobe-auto "$@" 2>&1); echo "[$(date +%T.%N | cut -c1-12)] > $* | $r" >> "$LOG"; echo "$r"; }
alive() { tasklist.exe 2>/dev/null | grep -qi '^kenshi_x64' ; }
crashed() { [ -f "$DMP" ] || ! alive; }
cnt() { local n; n=$(grep -c "$1" "$KFP" 2>/dev/null); echo "${n:-0}"; }
crash=0; clean=0
[ -f "$DMP" ] && { echo "SETUP: old crash dump at $DMP: move it away first"; exit 2; }
for i in $(seq 1 "$TRIES"); do
  A load "$SAVE" >/dev/null; A wait-world 180 >/dev/null
  A status | grep -q 'phase=world' || { echo "SETUP: try $i not in the world ($(A status))"; exit 2; }
  R0=$(cnt 'rebase shift'); J0=$(cnt 'world-scale centre jump')
  A select "$SH" >/dev/null
  case "$FP" in on) A fp_mode on >/dev/null;; off) A fp_mode off >/dev/null;; esac
  sleep 3
  for c in "$SH" "$MT"; do A protect "$c" on >/dev/null; done
  if [ "$KO" = 1 ]; then A protect "$TG" off >/dev/null; A ko "$TG" 3600 >/dev/null; fi
  A speed 1 >/dev/null
  t=0; while [ $t -lt "$WAIT" ]; do crashed && break; sleep 1; t=$((t + 1)); done
  sleep 2; R=$(( $(cnt 'rebase shift') - R0 )); J=$(( $(cnt 'world-scale centre jump') - J0 ))
  if crashed; then crash=$((crash + 1)); echo "RESULT navcrash-$LABEL-$i CRASH rebase=$R jump=$J t=${t}s dump=$([ -f "$DMP" ] && echo 1 || echo 0) log=$LOG"; break
  else clean=$((clean + 1)); echo "RESULT navcrash-$LABEL-$i CLEAN rebase=$R jump=$J"; fi
done
echo "SUMMARY navcrash-$LABEL crash=$crash clean=$clean tries=$TRIES"
