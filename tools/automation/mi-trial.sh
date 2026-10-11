#!/bin/bash
# mi-trial.sh <out-dir>: multi-instance trial row MI-TRIAL (C:\KenshiTestRuns\multi-instance\PLAN.md). Runs as ONE row of a
# 5090 runner list while the batch's own game (instance 1, the list's save, normally kah-fpxbow) is in the world:
#   preflight (instance 1 in the world, instance 2 copy synced + not running, commit headroom) -> launch instance 2
#   (D:\KenshiInst\2, gfx low, lock game-2.lock, owner multi-instance) on the same save -> the same KenshiFP row
#   (fp-combat-settings.sh, row CS: key_inject + KenshiFP.ini + KenshiFP.log, all per install) on BOTH games at the
#   same time -> instance 1 still healthy, game time advanced on both, the two row results agree -> stop instance 2.
# Prints exactly one `RESULT MI-TRIAL PASS|FAIL <evidence>` line; sub-row output goes to files (their RESULT lines are
# not echoed, so SUMMARY.txt counts one row). Instance 2 is always stopped on exit. Env: MI_SAVE (kah-fpxbow),
# MI_PLAYER (Axima), MI_MATE (Malzin), MI_ROW (fp-combat-settings.sh), MI_MIN_COMMIT_GB (16).
set -u
OUT=${1:?usage: mi-trial.sh <out-dir>}; mkdir -p "$OUT"; LOG=$OUT/mi-trial.log; : > "$LOG"
A=/mnt/c/KenshiModding/tools/automation; KT=/mnt/c/KenshiModding/components/KenshiFP/tests/ingame
SAVE=${MI_SAVE:-kah-fpxbow}; PL=${MI_PLAYER:-Axima}; MATE=${MI_MATE:-Malzin}; SUB=${MI_ROW:-fp-combat-settings.sh}
K1='D:\Steam\steamapps\common\Kenshi\mods\AutomationHarness'; K2='D:\KenshiInst\2\mods\AutomationHarness'
KD1=/mnt/d/Steam/steamapps/common/Kenshi; KD2=/mnt/d/KenshiInst/2
CTL='C:\KenshiModding\tools\automation\kenshi-ctl.ps1'; INSTPS='C:\KenshiModding\tools\automation\kenshi-instance.ps1'
s1() { KAH_DIR=$K1 timeout 60 stobe-auto "$@" 2>&1 </dev/null; }
s2() { KAH_DIR=$K2 timeout 60 stobe-auto "$@" 2>&1 </dev/null; }
ctl2() { KAH_INSTANCE=2 KAH_OWNER=multi-instance KAH_GFX=low WSLENV=KAH_INSTANCE:KAH_OWNER:KAH_GFX \
  timeout 420 powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$CTL" "$@" 2>&1 </dev/null | tr -d '\r'; }
log() { echo "$(date +%T) $*" >> "$LOG"; }
STARTED=0
cleanup() { [ "$STARTED" = 1 ] && { log "stop instance 2: $(ctl2 stop | tail -1)"; ctl2 release >> "$LOG"; }; STARTED=0; }
trap cleanup EXIT
fin() { echo "RESULT MI-TRIAL $1 $2 log=$LOG"; exit 0; }
gh() { grep -o 'game_hours=[0-9.]*\|hours=[0-9.]*' | head -1 | cut -d= -f2; }
procs() { powershell.exe -NoProfile -Command 'Get-Process kenshi_x64 -ErrorAction SilentlyContinue | ForEach-Object { "{0}:{1:N1}GB" -f ($(if ($_.Path -like "D:\KenshiInst\*") {"i2"} else {"i1"})), ($_.WorkingSet64/1GB) }' 2>/dev/null </dev/null | tr -d '\r' | tr '\n' ' '; }
gpu() { /usr/lib/wsl/lib/nvidia-smi --query-gpu=memory.used,utilization.gpu --format=csv,noheader 2>/dev/null | tr -d ' ' | head -1; }

# --- preflight (setup failures stop here, before instance 2 is touched) ---
st1=$(s1 status); log "i1 status: $st1"
echo "$st1" | grep -q 'phase=world' || fin FAIL "setup: instance 1 not in the world ($st1)"
c=$(ctl2 status | tail -1); log "i2 ctl status: $c"
[ "$c" = "not running" ] || fin FAIL "setup: instance 2 already running or broken ($c)"
free=$(powershell.exe -NoProfile -Command '$o=Get-CimInstance Win32_OperatingSystem; "{0:N0}" -f ($o.FreeVirtualMemory/1MB)' 2>/dev/null | tr -d '\r,')
log "commit headroom ${free} GB"
[ "${free:-0}" -ge "${MI_MIN_COMMIT_GB:-16}" ] || fin FAIL "setup: commit headroom ${free} GB < ${MI_MIN_COMMIT_GB:-16}"
sy=$(powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$INSTPS" sync -Instance 2 -Saves "$SAVE" 2>&1 </dev/null | tr -d '\r'); log "sync: $sy"
echo "$sy" | grep -q "save $SAVE ->" || fin FAIL "setup: instance 2 sync failed ($(echo "$sy" | head -2 | tr '\n' ' '))"
self=$(powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$INSTPS" selftest -Instance 2 2>&1 </dev/null | tr -d '\r'); log "$self"
echo "$self" | grep -q 'SELFTEST PASS' || fin FAIL "setup: instance 2 copy selftest ($self)"
gpu0=$(gpu); p0=$(procs); log "before: gpu=$gpu0 procs=$p0"

# --- launch instance 2 next to instance 1 ---
t0=$SECONDS; STARTED=1
ctl2 launch -Save "$SAVE" >> "$LOG"; rc=$?
ctl2 window >> "$LOG"
tl=$((SECONDS - t0)); log "i2 launch rc=$rc after ${tl}s"
w=$(s2 wait-world 300); log "i2 wait-world: $w"
st2=$(s2 status); log "i2 status: $st2"
echo "$st2" | grep -q 'phase=world' || fin FAIL "instance 2 not in the world after launch (rc=$rc ${tl}s; $st2)"
st1=$(s1 status); echo "$st1" | grep -q 'phase=world' || fin FAIL "instance 1 left the world when instance 2 started ($st1)"
s2 select "$PL" >> "$LOG"; sleep 5
h1a=$(s1 time | gh); h2a=$(s2 time | gh); log "game hours before: i1=$h1a i2=$h2a"

# --- the same KenshiFP row on both games at once ---
run_sub() {   # $1 = instance tag, $2 = KAH_DIR, $3 = KDIR
  local o=$OUT/$1; mkdir -p "$o"; echo "start $(date +%s)" > "$o/span"
  KAH_DIR=$2 KDIR=$3 PLAYER=$PL MATE=$MATE RESULT_LOG=$o/row.txt timeout 900 bash "$KT/$SUB" "$PL" "$MATE" "$o" > "$o/out.txt" 2>&1 </dev/null
  echo "end $(date +%s) rc=$?" >> "$o/span"
}
run_sub i1 "$K1" "$KD1" & pa=$!
run_sub i2 "$K2" "$KD2" & pb=$!
sleep 30; g1=$(gpu); p1=$(procs); log "during: gpu=$g1 procs=$p1"
wait $pa $pb
# a sub-row may print several RESULT lines (CS01..CS0n): compare the per-row verdict sets
vs() { grep -h '^RESULT' "$1" | awk '{print $2":"$3}' | sort -u | paste -sd' '; }
r1=$(vs "$OUT/i1/out.txt"); r2=$(vs "$OUT/i2/out.txt")
log "i1: $r1"; log "i2: $r2"; log "spans i1: $(tr '\n' ' ' < "$OUT/i1/span") i2: $(tr '\n' ' ' < "$OUT/i2/span")"
s1a=$(awk '/^start/{print $2}' "$OUT/i1/span"); e1=$(awk '/^end/{print $2}' "$OUT/i1/span")
s2a=$(awk '/^start/{print $2}' "$OUT/i2/span"); e2=$(awk '/^end/{print $2}' "$OUT/i2/span")
ov=$(( (e1 < e2 ? e1 : e2) - (s1a > s2a ? s1a : s2a) ))
h1b=$(s1 time | gh); h2b=$(s2 time | gh); log "game hours after: i1=$h1b i2=$h2b"
st1=$(s1 status); h1ok=$(echo "$st1" | grep -c 'phase=world')
dh1=$(awk -v a="${h1a:-0}" -v b="${h1b:-0}" 'BEGIN{printf "%.3f", b-a}'); dh2=$(awk -v a="${h2a:-0}" -v b="${h2b:-0}" 'BEGIN{printf "%.3f", b-a}')
cnt() { local p f; p=$(echo "$1" | grep -o ':PASS[^ ]*' | wc -l); f=$(echo "$1" | grep -o ':FAIL' | wc -l); [ -n "$1" ] && echo "${p}P/${f}F"; }
v1=$(cnt "$r1"); v2=$(cnt "$r2")
ev="launch=${tl}s overlap=${ov}s i1=${v1:-none}($((e1-s1a))s) i2=${v2:-none}($((e2-s2a))s) dgh i1=$dh1 i2=$dh2 gpu ${gpu0}->${g1} procs $p1 (i1 rows: ${r1:0:160}) (i2 rows: ${r2:0:160})"
cleanup
[ "$h1ok" = 1 ] || fin FAIL "instance 1 left the world during the trial $ev"
[ -n "$v1" ] && [ -n "$v2" ] || fin FAIL "a sub-row printed no RESULT line $ev"
[ "$ov" -gt 30 ] || fin FAIL "the two rows did not overlap $ev"
awk -v a="$dh1" -v b="$dh2" 'BEGIN{exit !(a>0 && b>0)}' || fin FAIL "game time did not advance on both $ev"
[ "$(echo "$r1" | sed 's/PASS-REC/PASS/g')" = "$(echo "$r2" | sed 's/PASS-REC/PASS/g')" ] || fin FAIL "the two games disagree $ev"
fin PASS "$ev"
