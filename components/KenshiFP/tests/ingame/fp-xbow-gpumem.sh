#!/usr/bin/env bash
# fp-xbow-gpumem.sh: row GPUMEM (tdr-xbow 2026-10-11). The 5090 had a GPU TDR (nvlddmkm 153 + Display 4101) on FP
# crossbow fire #50 of a launch (64-xbf-r11c R11, a miss shot aimed at nothing 25 m+ away); the 4080 had five, all right
# after FP crossbow fire. This row fires N manual crossbow shots on kah-fpxbow, cycling HIT (aimed at the pinned,
# protected target) and MISS (camera turned off the target, slightly up: the bolt flies into the distance, as the TDR
# shot did) and SKY (pitch -0.9 up, as the 4080 rg-01 K-row TDR during a reload), and records GPU memory per shot:
#   shots.csv   n,kind,epoch,shot(1/0),actual_shots,nvsmi_used_MB (nvidia-smi right after the shot)
#   mem.csv     epoch,adapter_dedicated_MB,kenshi_dedicated_MB,kenshi_shared_MB (PowerShell sampler, every 2 s)
# PASS: >= 90% of N shots fired, no TDR during the row (gpu-tdr-check.ps1), the game answered after every shot, and
#   Kenshi's dedicated GPU memory grew < MEMMB (default 64) from the median of shots 6-10 to the median of the last 5
#   (growth/shot reported: a per-shot leak of even 1 MB shows over 100 shots).
# FAIL: TDR / game hang after shot k (named), or memory growth >= MEMMB.
# Usage: fp-xbow-gpumem.sh [shooter] [target] [outdir] [shots] [mem_bound_mb]   (WSL or Git Bash, Kenshi in the world)
# One `RESULT GPUMEM PASS|FAIL <evidence>` line. Restores fp_combat off + physical input + FP mode as found.
SH=${1:-Axima}; TG=${2:-Skaera}; OUT=${3:-/tmp/fp-xbow-gpumem}; N=${4:-100}; MEMMB=${5:-64}
DIST=40
. "$(dirname "$0")/take-preflight.sh"; pf_begin GPUMEM; pf_outdir "$OUT"
LOG="$OUT/log.txt"; : > "$LOG"; SCSV="$OUT/shots.csv"; MCSV="$OUT/mem.csv"
echo "n,kind,epoch,shot,actual_shots,nvsmi_used_MB" > "$SCSV"
A() { local r; r=$(stobe-auto "$@" </dev/null 2>&1); echo "> $* | $r" >> "$LOG"; echo "$r"; }
PF_A() { A "$@"; }
fld() { grep -o "\b$1=[^ ]*" | head -1 | cut -d= -f2; }
cs() { A fp_combat state | fld "$1"; }
inp() { A fp_combat input "$1" "$2" "$3" >/dev/null; }
waitfor() { local end=$((SECONDS+$1)); while [ $SECONDS -lt $end ]; do [ "$(cs "$2")" = "$3" ] && return 0; sleep 0.2; done; return 1; }
NVSMI=$(command -v nvidia-smi.exe || ls /mnt/c/Windows/System32/nvidia-smi.exe /c/Windows/System32/nvidia-smi.exe 2>/dev/null | head -1)
nvmem() { "$NVSMI" --query-gpu=memory.used --format=csv,noheader,nounits 2>/dev/null | head -1 | tr -d '\r '; }
TDRF="$(cd "$(dirname "$0")/../../../../tools/automation" && pwd)/gpu-tdr-check.ps1"
# tdrcheck <minutes>: "TDR NONE" or "TDR <n> last=<t>" (gpu-tdr-check.ps1; an inline query where the rig lacks the script)
tdrcheck() { if [ -f "$TDRF" ]; then powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$(wslpath -w "$TDRF")" -Minutes "$1"
  else powershell.exe -NoProfile -Command "\$e=Get-WinEvent -FilterHashtable @{LogName='System'; Id=4101,153; StartTime=(Get-Date).AddMinutes(-$1)} -ErrorAction SilentlyContinue | Where-Object { \$_.ProviderName -in 'nvlddmkm','Display' }; if (\$e) { 'TDR {0} last={1}' -f @(\$e).Count, @(\$e)[0].TimeCreated.ToString('HH:mm:ss') } else { 'TDR NONE' }"
  fi | tr -d '\r' | tail -1; }
T0=$(date +%s)

# ---- GPU memory sampler (PowerShell, every 2 s until the stop file) ----
STOPF="$OUT/.sampler-stop"; rm -f "$STOPF"; echo "epoch,adapter_dedicated_MB,kenshi_dedicated_MB,kenshi_shared_MB" > "$MCSV"
WMCSV=$(wslpath -w "$MCSV"); WSTOP=$(wslpath -w "$STOPF")
cat > "$OUT/sampler.ps1" <<EOF
\$ProgressPreference='SilentlyContinue'

while (-not (Test-Path '$WSTOP')) {
  \$p = (Get-Process kenshi_x64 -ErrorAction SilentlyContinue | Select-Object -First 1).Id
  \$ad = ((Get-Counter '\GPU Adapter Memory(*)\Dedicated Usage' -ErrorAction SilentlyContinue).CounterSamples | Measure-Object CookedValue -Maximum).Maximum
  \$kd = 0; \$ks = 0
  if (\$p) { \$c = (Get-Counter "\GPU Process Memory(pid_\${p}_*)\Dedicated Usage","\GPU Process Memory(pid_\${p}_*)\Shared Usage" -ErrorAction SilentlyContinue).CounterSamples
    \$kd = (\$c | Where-Object Path -like '*dedicated*' | Measure-Object CookedValue -Sum).Sum
    \$ks = (\$c | Where-Object Path -like '*shared*' | Measure-Object CookedValue -Sum).Sum }
  '{0},{1:F0},{2:F0},{3:F0}' -f [DateTimeOffset]::UtcNow.ToUnixTimeSeconds(), (\$ad/1MB), (\$kd/1MB), (\$ks/1MB) | Out-File -Append -Encoding ascii '$WMCSV'
  Start-Sleep -Seconds 2 }
EOF
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$(wslpath -w "$OUT/sampler.ps1")" >/dev/null 2>&1 &
SPID=$!

FP0=$(A fp_state | fld fp_mode)
cleanup() { : > "$STOPF"; A fp_combat input 0 0 0 >/dev/null; A fp_combat off >/dev/null; A fp_combat physical >/dev/null
            A fp_mode "$([ "$FP0" = 1 ] && echo on || echo off)" >/dev/null; }
PF_ON_FAIL=cleanup
trap "exit 143" TERM INT HUP

# ---- setup (no retries: a failed check stops the row) ----
A status | grep -q phase=world || pf_fail "not in world"
A where "$SH" | grep -q 'pos=' || pf_fail "shooter $SH not found"
A where "$TG" | grep -q 'pos=' || pf_fail "target $TG not found"
[ "$(A rangedinfo "$SH" | fld bow)" != none ] || pf_fail "$SH has no ranged weapon"
[ -n "$NVSMI" ] || { echo "GPUMEM: nvidia-smi not found, nvsmi column empty (Kenshi counters still gate)" >> "$LOG"; NVSMI=true; }
tdrcheck 5 | grep -q 'TDR NONE' || pf_fail "a TDR in the 5 min before the row (stale device?)"
A protect "$SH" on >/dev/null
A pin "$TG" at "$SH" dist $DIST face "$SH" >/dev/null
A protect "$TG" on >/dev/null
A select "$SH" >/dev/null; A fp_mode on >/dev/null; sleep 1
A fp_control take >/dev/null
read -r sx sz <<<"$(A where "$SH" | grep -o 'pos=[^ ]*' | cut -d= -f2 | awk -F, '{print $1, $3}')"
read -r tx tz <<<"$(A where "$TG" | grep -o 'pos=[^ ]*' | cut -d= -f2 | awk -F, '{print $1, $3}')"
YAW=$(awk -v a="$sx" -v b="$sz" -v c="$tx" -v d="$tz" 'BEGIN{printf "%.4f", atan2(c-a, d-b)}')
YAWM=$(awk -v y="$YAW" 'BEGIN{printf "%.4f", y+0.7}')
A fp_camera look "$YAW" 0.02 >/dev/null
A fp_combat on | grep -q requested || pf_fail "fp_combat on refused"
inp 0 0 0; pf_ranged_inj "$SH" || pf_fail "$PF_WHY"
A fp_combat autoreload 1 >/dev/null
bolts() { A inv "$SH" | grep -o '"name":"Bolts[^"]*","count":[0-9]*' | grep -o '[0-9]*$' | awk '{n+=$1} END{print n+0}'; }
BOLTS=$(bolts)
# top up so N shots really fire (66c 4080: 19 bolts in the fixture capped the row at 19 shots)
need=$((N-BOLTS+5)); while [ "$BOLTS" -lt "$N" ] && [ $need -gt 0 ]; do   # give takes at most 50 per call
  k=$((need>50?50:need)); echo "GPUMEM: give $SH Bolts $k: $(A give "$SH" Bolts $k)" >> "$LOG"; need=$((need-k)); done
BOLTS=$(bolts)
[ "$BOLTS" -ge 10 ] || echo "GPUMEM: bolt count read $BOLTS (inv format?), firing N=$N; a dry bow shows as too few shots" >> "$LOG"
[ "$BOLTS" -ge 10 ] && [ "$BOLTS" -lt "$N" ] && { echo "GPUMEM: $BOLTS bolts < $N shots, firing $BOLTS" >> "$LOG"; N=$BOLTS; }
echo "GPUMEM setup ok: N=$N bolts=$BOLTS yaw=$YAW miss_yaw=$YAWM nvsmi0=$(nvmem)" | tee -a "$LOG"

# ---- shots ----
fired=0; hung=""
for ((i=1; i<=N; i++)); do
  case $((i%3)) in 1) kind=hit; A fp_camera look "$YAW" 0.02 >/dev/null;; 2) kind=miss; A fp_camera look "$YAWM" -0.06 >/dev/null;; *) kind=sky; A fp_camera look "$YAWM" -0.9 >/dev/null;; esac
  s0=$(cs actual_shots); [ -n "$s0" ] || { hung="no fp_combat answer before shot $i"; break; }
  inp 1 0 0; shot=0
  if waitfor 12 shot_ready 1; then
    inp 1 1 0; end=$((SECONDS+3))
    while [ $SECONDS -lt $end ]; do s1=$(cs actual_shots); [ -n "$s1" ] && [ "$s1" != "$s0" ] && { shot=1; break; }; sleep 0.1; done
  fi
  inp 1 0 0
  sleep 0.5; m=$(nvmem); s1=$(cs actual_shots)
  echo "$i,$kind,$(date +%s),$shot,$s1,$m" >> "$SCSV"
  [ "$shot" = 1 ] && fired=$((fired+1))
  if [ -z "$s1" ]; then hung="game silent after shot $i ($kind)"; break; fi
done
inp 0 0 0
: > "$STOPF"; sleep 3; kill $SPID 2>/dev/null
MIN=$(( ($(date +%s)-T0)/60 + 2 ))
TDR=$(tdrcheck $MIN)
pf_game_done

# ---- verdict ----
# kenshi dedicated MB: median of the samples in shots 6-10 vs the last 5 samples
read -r e6 e10 <<<"$(awk -F, 'NR>1 && $1==6{a=$3} NR>1 && $1==10{b=$3} END{print a+0, b+0}' "$SCSV")"
GROW=$(awk -F, -v a="$e6" -v b="$e10" 'function med(x,n){asort(x);return n?x[int((n+1)/2)]:0}
  NR>1 && $3>0 {all[++na]=$3; if ($1>=a-1 && $1<=b+1) w[++nw]=$3}
  END{for(i=(na>5?na-4:1);i<=na;i++) l[++nl]=all[i]; m0=med(w,nw); m1=med(l,nl); printf "%d %d %d", m0, m1, m1-m0}' "$MCSV")
read -r M0 M1 DM <<<"$GROW"; M0=${M0:-0}; M1=${M1:-0}; DM=${DM:-0}
NV=$(awk -F, 'NR==2{a=$6} NR>1{b=$6} END{printf "%s->%s", a, b}' "$SCSV")
PER=$(awk -v d="$DM" -v n="$fired" 'BEGIN{printf "%.2f", (n>0)?d/n:0}')
ev="fired=$fired/$N kenshi_dedicated_MB=$M0->$M1 (+$DM, $PER/shot) nvsmi_used_MB=$NV $TDR${hung:+ hang='$hung'} csv=$SCSV mem=$MCSV"
cleanup
if [ "$TDR" != "TDR NONE" ] || [ -n "$hung" ]; then pf_result FAIL "$ev log=$LOG"
elif [ "$fired" -lt $((N*9/10)) ]; then pf_result FAIL "too few shots: $ev log=$LOG"
elif [ "${DM:-0}" -ge "$MEMMB" ]; then pf_result FAIL "GPU memory grew >= ${MEMMB} MB: $ev"
else pf_result PASS "$ev"; fi
