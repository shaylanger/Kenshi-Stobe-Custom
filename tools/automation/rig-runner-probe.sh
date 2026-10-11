#!/usr/bin/env bash
# rig-runner-probe.sh <out-dir> [kill-step|kill-game]   (5090: WSL; 4080: Git Bash over ssh)
# One line about a run-batch.sh batch, for rig-runner.ps1's 60 s tick (no state kept here, the runner compares ticks):
#   PROBE done=0|1 age=<s since the newest file under out-dir changed> gh=<game hours|-> phase=<harness phase|-> kenshi=0|1
#         crash=0|1 step=<running row|-> stallmin=<row STALL_MIN|-> launched=0|1 alive=0|1
#   crash=1: a Kenshi crash dump newer than the batch start (RE_Kenshi's handler can leave the game alive on a hidden dialog)
#   stallmin: a STALL_MIN=<min> word in the row's command (list.txt in the out dir) = the row may sit still that long
#   launched=0: no row has started yet (launch / first load: the runner allows more time)
#   gamedone=1: <out>/GAMEDONE (every row past its game part; background analyses may still run): the rig is free
#   ana=1: the running row analyses in the foreground while nothing records = game idle (5090 only)
#   alive=0: the run-batch.sh process (batch.pid; 4080: its Windows pid) is gone without DONE (killed/crashed batch)
# kill-step: TERM the running row's `timeout` (pid in <out>/step.pid, written by run-batch.sh): that row FAILs, the batch
#            goes on with the next row. kill-game: also kill kenshi_x64 (crashed game; run-batch.sh relaunches it).
set -u
O=${1:?usage: rig-runner-probe.sh <out-dir> [kill-step|kill-game]}; act=${2:-}
if grep -qi microsoft /proc/version 2>/dev/null; then KD=${KDIR:-/mnt/d/Steam/steamapps/common/Kenshi}; else RIG=${RIG:-}; . /c/KenshiModding/tools/automation/rig-env.sh >/dev/null 2>&1; KD=$KDIR; fi
if [ "$act" = kill-step ] || [ "$act" = kill-game ]; then
  [ "$act" = kill-game ] && taskkill.exe //F //IM kenshi_x64.exe </dev/null >/dev/null 2>&1
  if [ -f "$O/step.pid" ]; then read -r p n w < "$O/step.pid"
    if [ -n "${w:-}" ]; then taskkill.exe //F //T //PID "$w" </dev/null >/dev/null 2>&1 && echo "KILLED step $n winpid $w" || echo "KILL failed winpid $w ($n)"   # 4080: other msys session
    else kill -TERM "$p" 2>/dev/null && echo "KILLED step $n pid $p" || echo "KILL failed pid $p ($n)"; fi
    # every other process of the row (killtree 2026-10-11: taskkill /T missed the MSYS forks of 59-hits-r09b HIT, which
    # kept aiming the crossbow for 42 min into later batches): match the row dir in the command lines
    R=$(dirname "$0")/row-reaper.sh; [ -f "$R" ] && echo "REAPED $(bash "$R" kill "$O/$n" </dev/null 2>&1 | grep -c '^REAPED') more process(es) of $n"
  else echo "KILL no step.pid in $O"; fi
  exit 0
fi
done=0; [ -f "$O/DONE" ] && done=1
now=$(date +%s); nf=$(find "$O" -type f ! -name step.pid -printf '%T@\n' 2>/dev/null | sort -n | tail -1); nf=${nf%%.*}; age=$(( now - ${nf:-$now} ))   # no file/dir: age 0 (an empty $nf aborted the probe: "probe failed" forever)
if tasklist.exe </dev/null 2>/dev/null | grep -qi kenshi_x64; then k=1; else k=0; fi
gh=-; ph=-
if [ $k = 1 ]; then
  st=$(timeout 20 stobe-auto status </dev/null 2>&1 | tr -d '\r' | head -1); ph=$(grep -oE 'phase=[a-z]+' <<<"$st" | cut -d= -f2); ph=${ph:--}
  gh=$(timeout 20 stobe-auto time </dev/null 2>/dev/null | tr -d '\r' | grep -oE 'game_hours=[0-9.]+' | head -1 | cut -d= -f2); gh=${gh:--}
fi
crash=0; cd_="$KD/crashDump1.0.65_x64.dmp"
if [ -f "$cd_" ] && [ -f "$O/batch.log" ]; then
  first=$(stat -c %Y "$O/list.txt" 2>/dev/null || stat -c %Y "$O/batch.log")   # list.txt: written once by the runner at start
  [ "$(stat -c %Y "$cd_")" -gt "$first" ] && crash=1
fi
step=-; [ -f "$O/step.pid" ] && step=$(cut -d' ' -f2 "$O/step.pid")
sm=-; if [ "$step" != - ] && [ -f "$O/list.txt" ]; then
  sm=$(awk -F'|' -v n="$step" '{g=$1; gsub(/^[ \t]+|[ \t]+$/, "", g)} g==n {print $NF}' "$O/list.txt" | grep -oE 'STALL_MIN=[0-9]+' | head -1 | cut -d= -f2); sm=${sm:--}; fi
al=1; if [ -f "$O/batch.pid" ] && [ $done = 0 ]; then read -r bp bw < "$O/batch.pid"
  if [ -n "${bw:-}" ]; then tasklist.exe //NH //FI "PID eq $bw" </dev/null 2>/dev/null | grep -q " $bw " || al=0; else kill -0 "$bp" 2>/dev/null || al=0; fi; fi
# race (op-b8 2026-10-10): DONE is written as run-batch.sh exits; re-read it after the pid check, else done=0 alive=0
[ $al = 0 ] && [ -f "$O/DONE" ] && { done=1; al=1; }
la=0; grep -a -q -E '^[0-9]{2}:[0-9]{2} .*: (prepare|run) ' "$O/batch.log" 2>/dev/null && la=1
gd=0; [ -f "$O/GAMEDONE" ] && gd=1
# ana=1: the running row (step) is doing offline analysis in the foreground (a lab tool with RESULT_LOG=<out>/<step>.txt
# runs) and nothing records: the game sits unused (Shay 2026-10-10: that counts as idle; the row should call pf_game_done)
ana=0
if [ "$step" != - ] && grep -qi microsoft /proc/version 2>/dev/null; then
  for p in $(pgrep -f 'takecheck\.py|frames\.py|animlab\.py|review-pack\.py|fist-take-check\.py|vm-sheet\.py|labcheck' 2>/dev/null); do
    tr '\0' '\n' < "/proc/$p/environ" 2>/dev/null | grep -qxF "RESULT_LOG=$O/$step.txt" && { ana=1; break; }
  done
  [ $ana = 1 ] && tasklist.exe </dev/null 2>/dev/null | grep -qi '^ffmpeg.exe' && ana=0
fi
# setupstreak: trailing run of rows that FAILed setup within 90 s of the previous row's end (row out file mtime): a list of
# instant setup failures keeps the rig "busy" while the game does nothing (Shay 2026-10-10)
ss=0; pe=$(stat -c %Y "$O/list.txt" 2>/dev/null || echo 0)
while read -r _ rn rv rest; do e=$(stat -c %Y "$O/$rn.txt" 2>/dev/null || echo "$pe")
  if [ "$rv" = FAIL ] && [[ "$rest" == setup* ]] && [ $((e - pe)) -lt 90 ]; then ss=$((ss + 1)); else ss=0; fi; pe=$e
done < <(grep -a '^RESULT ' "$O/batch.log" 2>/dev/null)
st=0; bpid=-; bmt=0; [ -f "$O/batch.pid" ] && { st=1; read -r bpid _ < "$O/batch.pid"; bmt=$(stat -c %Y "$O/batch.pid"); }
# bpid/bmt: which run-batch.sh owns the out dir (the runner refuses to adopt a batch someone else started there)
echo "PROBE setupstreak=$ss bpid=${bpid:--} bmt=$bmt started=$st done=$done age=$age gh=$gh phase=$ph kenshi=$k crash=$crash step=$step stallmin=$sm launched=$la alive=$al gamedone=$gd ana=$ana"
