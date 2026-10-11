#!/usr/bin/env bash
# fp-xbow-newgun.sh: row NEWGUN (tdr-xbow 2026-10-11), the GPU TDR repro. Every measured TDR (nvlddmkm 153) landed 9-13 ms
# after a KenshiFP manual GunClass::shoot, and the three 5090 ones with per-shot diag (08:34, 11:00 #162, 11:29 #25) were the
# FIRST manual shot by a new character object (pc/gun pointer never seen before in that launch). A save load makes every
# character (and its gun, pc+0x3AF0, and its per-character 'Character_<n>' material) new. This row loops exactly that:
#   N x { load the save; [fp_combat hmat <HMAT>]; arm the shooter's crossbow; fire ONE manual shot at the pinned target;
#         check the game still answers + no TDR (System log nvlddmkm 153 / Display 4101) }
# Out: $OUT/iters.csv (i,epoch,fired,pc,gun_create line), $OUT/log.txt. Stops at the first TDR/hang (a TDR hangs Kenshi).
# PASS: >= 90% of N first shots fired, no TDR, the game answered after every shot. FAIL: TDR/hang at iteration k (named),
#   or too few shots. Env NEWGUN_HMAT=weapon|body: the kfp-tdr-hmat A/B switch, set right after each load (before the
#   gun's physical is created); empty = the build's default (builds before kfp-tdr-hmat: always body).
# Usage: fp-xbow-newgun.sh [shooter] [target] [outdir] [N] [save]   (WSL or Git Bash via rig-env, Kenshi in the world)
# One `RESULT NEWGUN PASS|FAIL <evidence>` line.
SH=${1:-Axima}; TG=${2:-Skaera}; OUT=${3:-/tmp/fp-xbow-newgun}; N=${4:-30}; SAVE=${5:-kah-fpxbow}
HMAT=${NEWGUN_HMAT:-}; DIST=40
. "$(dirname "$0")/take-preflight.sh"; pf_begin NEWGUN; pf_outdir "$OUT"
LOG="$OUT/log.txt"; : > "$LOG"; ICSV="$OUT/iters.csv"; echo "i,epoch,fired,load_s,pc,gun_create" > "$ICSV"
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
cleanup() { A fp_combat input 0 0 0 >/dev/null; A fp_combat off >/dev/null; A fp_combat physical >/dev/null; }
PF_ON_FAIL=cleanup
trap "exit 143" TERM INT HUP
T0=$(date +%s)
A status | grep -q phase=world || pf_fail "not in world"
tdrcheck 5 | grep -q 'TDR NONE' || pf_fail "a TDR in the 5 min before the row (stale device?)"

fired=0; hung=""; TDR="TDR NONE"; setupf=0; hm_bad=""
for ((i=1; i<=N; i++)); do
  l0=$(date +%s); pf_load "$SAVE" >> "$LOG" 2>&1; ls=$(( $(date +%s)-l0 ))
  A status | grep -q phase=world || { hung="load $i never reached the world"; break; }
  if [ -n "$HMAT" ]; then r=$(A fp_combat hmat "$HMAT"); grep -q "hmat=$HMAT" <<<"$r" || [ "$HMAT" = body ] || { hm_bad="fp_combat hmat $HMAT refused: $r"; break; }; fi
  A protect "$SH" on >/dev/null; A pin "$TG" at "$SH" dist $DIST face "$SH" >/dev/null; A protect "$TG" on >/dev/null
  A select "$SH" >/dev/null; A fp_mode on >/dev/null; sleep 1; A fp_control take >/dev/null
  read -r sx sz <<<"$(A where "$SH" | grep -o 'pos=[^ ]*' | cut -d= -f2 | awk -F, '{print $1, $3}')"
  read -r tx tz <<<"$(A where "$TG" | grep -o 'pos=[^ ]*' | cut -d= -f2 | awk -F, '{print $1, $3}')"
  YAW=$(awk -v a="$sx" -v b="$sz" -v c="$tx" -v d="$tz" 'BEGIN{printf "%.4f", atan2(c-a, d-b)}')
  A fp_camera look "$YAW" 0.02 >/dev/null
  A fp_combat on | grep -q requested || { echo "iter $i: fp_combat on refused" >> "$LOG"; setupf=$((setupf+1)); continue; }
  inp 0 0 0
  if ! pf_ranged_inj "$SH" >> "$LOG" 2>&1; then echo "iter $i: arm failed: $PF_WHY" >> "$LOG"; setupf=$((setupf+1)); cleanup; continue; fi
  A fp_camera look "$YAW" 0.02 >/dev/null
  s0=$(cs actual_shots); shot=0; inp 1 0 0
  if waitfor 12 shot_ready 1; then
    inp 1 1 0; end=$((SECONDS+3))
    while [ $SECONDS -lt $end ]; do s1=$(cs actual_shots); [ -n "$s1" ] && [ "$s1" != "$s0" ] && { shot=1; break; }; sleep 0.1; done
  fi
  inp 1 0 0; sleep 1.5; s1=$(cs actual_shots)
  gc=$(grep -a '\[tdr\] gun_create' "$KFPLOG" 2>/dev/null | tail -1 | cut -c1-160 | tr ',' ';')
  pc=$(grep -a '\[tdr\] manual shot #' "$KFPLOG" 2>/dev/null | tail -1 | grep -o 'pc=[0-9a-f]*' | cut -d= -f2)
  echo "$i,$(date +%s),$shot,$ls,$pc,$gc" >> "$ICSV"
  [ "$shot" = 1 ] && fired=$((fired+1))
  [ -z "$s1" ] && { hung="game silent after first shot of load $i"; break; }
  TDR=$(tdrcheck $(( ($(date +%s)-T0)/60 + 2 ))); [ "$TDR" != "TDR NONE" ] && { hung="TDR after first shot of load $i"; break; }
  cleanup
done
[ -z "$hung" ] && TDR=$(tdrcheck $(( ($(date +%s)-T0)/60 + 2 )))
pf_game_done
names=$(grep -a '\[tdr\] gun_create' "$KFPLOG" 2>/dev/null | grep -o "src=[^ ]* name='[^']*'" | sed "s/name='Character_[0-9]*'/name='Character_N'/" | sort | uniq -c | tr -s ' ' | tr '\n' ';')
ev="loads=$((i>N?N:i))/$N first_shots_fired=$fired setup_fail=$setupf hmat=${HMAT:-default} $TDR${hung:+ stop='$hung'} gun_creates={${names:-none}} csv=$ICSV"
[ -z "$hung" ] && cleanup
if [ -n "$hm_bad" ]; then pf_result FAIL "setup: $hm_bad"
elif [ "$TDR" != "TDR NONE" ] || [ -n "$hung" ]; then pf_result FAIL "$ev log=$LOG"
elif [ "$fired" -lt $((N*9/10)) ]; then pf_result FAIL "too few first shots: $ev log=$LOG"
else pf_result PASS "$ev"; fi
