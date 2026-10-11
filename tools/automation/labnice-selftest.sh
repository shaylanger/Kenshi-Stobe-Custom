#!/usr/bin/env bash
# labnice-selftest.sh [script dir]   (WSL) selftest of labnice.sh + lab-recpause.sh on a private LAB_D/LAB_RECDIR
# (never touches /tmp/labnice or C:\KenshiTestRuns\recording; real jobs have no held file there, so they are never paused).
# Bug 2026-10-11: a labnice job sat 8 min at 0/16 slots: the recpause daemon SIGSTOPped it before its held file existed.
# Cases: recording flag -> job starts at once with 12 slots; no flag -> 16; stale marker / stale ffmpeg gdigrab -> 16;
# root with no held file never paused; over-budget job paused while recording, resumed after; small jobs never paused.
# Prints one line per case + "RESULT labnice-selftest PASS|FAIL n/m".
set -u
DIR=${1:-$(dirname "$(readlink -f "$0")")}
T=$(mktemp -d /tmp/labnice-selftest.XXXX); trap 'kill $DPID $FPID $BPID $RPID 2>/dev/null; sleep 0.3; rm -rf "$T"' EXIT
DPID=; FPID=; BPID=; RPID=
export LAB_D=$T/d LAB_RECDIR=$T/rec LABNICE_SLOTS=16 LABNICE_REC_SLOTS=12 LAB_GDIGRAB_PAT="gdigrab-selftest-$$" LAB_TICK=1
mkdir -p "$LAB_D" "$LAB_RECDIR"; pass=0; tot=0
ok() { local r=0 m=${1:-}; [ $# -ge 2 ] && { r=$1; m=$2; }; tot=$((tot + 1)); if [ "$r" = 1 ]; then pass=$((pass + 1)); echo "PASS $m"; else echo "FAIL $m"; fi; }   # ok [1] <msg>
job() {  # job <-s N> -> "J=<LABNICE_J> t=<seconds to start>"
  local t0=$(date +%s); LAB_NODAEMON=1 timeout 60 bash "$DIR/labnice.sh" -s "$1" bash -c 'echo "$LABNICE_J"' 2>/dev/null | tail -1 | { read j; echo "J=$j t=$(( $(date +%s) - t0 ))"; }
}
st() { ps -o stat= -p "$1" 2>/dev/null | cut -c1; }

r=$(job 16); ok $([ "$r" = "J=16 t=0" ] || [ "$r" = "J=16 t=1" ] && echo 1) "no flag: -s 16 starts at once with 16 ($r)"
touch "$LAB_RECDIR/5090-take"
r=$(job 16); ok $([[ "$r" =~ ^J=12\ t=[012]$ ]] && echo 1) "recording flag: -s 16 starts at once with 12 ($r)"
r=$(job 4); ok $([[ "$r" =~ ^J=4\ t=[012]$ ]] && echo 1) "recording flag: -s 4 starts at once with 4 ($r)"
touch -d '-31 min' "$LAB_RECDIR/5090-take"
bash "$DIR/lab-recpause.sh" --recording; ok $([ $? = 1 ] && echo 1) "stale marker (31 min) is not a recording"
r=$(job 16); ok $([[ "$r" =~ ^J=16\ t=[012]$ ]] && echo 1) "stale marker: -s 16 starts at once with 16 ($r)"
rm -f "$LAB_RECDIR/5090-take"
cp /bin/bash "$T/ffmpeg.exe"; "$T/ffmpeg.exe" -c 'sleep 60; :' "x-$LAB_GDIGRAB_PAT" & FPID=$!; sleep 0.5
LAB_RECMAX=3 bash "$DIR/lab-recpause.sh" --recording; ok $([ $? = 0 ] && echo 1) "fresh ffmpeg gdigrab is a recording"
sleep 4
LAB_RECMAX=3 bash "$DIR/lab-recpause.sh" --recording; ok $([ $? = 1 ] && echo 1) "ffmpeg gdigrab running > LAB_RECMAX is stale"
r=$(LAB_RECMAX=3 job 16); ok $([[ "$r" =~ ^J=16\ t=[012]$ ]] && echo 1) "stale ffmpeg: -s 16 starts at once with 16 ($r)"
kill $FPID 2>/dev/null; FPID=
# -p (build line): with all 16 slots held it starts at once on the reserve; a normal job still waits
LAB_NODAEMON=1 bash "$DIR/labnice.sh" -s 16 sleep 8 & HP=$!; sleep 1
r=$(t0=$(date +%s); LAB_NODAEMON=1 timeout 20 bash "$DIR/labnice.sh" -p -s 6 bash -c 'echo "$LABNICE_J $LABNICE_SLOT"' 2>/dev/null | tail -1; echo " t=$(( $(date +%s) - t0 ))")
ok $([[ "$(echo $r)" =~ ^6\ 17\ 18\ 19\ 20\ 21\ 22\ t=[01]$ ]] && echo 1) "-p -s 6 with 16/16 held: reserve slots at once ($(echo $r))"
r=$(LAB_NODAEMON=1 LABNICE_PARTIAL=999 timeout 3 bash "$DIR/labnice.sh" -s 1 echo ran 2>/dev/null)
ok $([ -z "$r" ] && echo 1) "normal -s 1 with 16/16 held waits (no reserve)"
kill $HP 2>/dev/null; pkill -f "sleep 8" -P $HP 2>/dev/null; wait $HP 2>/dev/null

# daemon cases (private daemon; jobs with LAB_NODAEMON so they don't start another one)
bash "$DIR/lab-recpause.sh" & DPID=$!; sleep 1
LAB_NODAEMON=1 bash "$DIR/labnice.sh" -s 3 sleep 3 & A=$!; sleep 1   # slots 1..3, gone after 3 s
LAB_NODAEMON=1 bash "$DIR/labnice.sh" -s 13 sleep 60 & BPID=$!; wait $A; sleep 1   # holds slots 4..16 (no recording yet)
printf '#!/bin/bash\nsleep 60\n' > "$T/labnice.sh"; bash "$T/labnice.sh" & RPID=$!   # a root with no held file
touch "$LAB_RECDIR/5090-take"; sleep 3
ok $([ "$(st $BPID)" = T ] && echo 1) "recording: job holding slots 4..16 paused (stat $(st $BPID))"
ok $([ "$(st $RPID)" != T ] && echo 1) "recording: root with no held file not paused (stat $(st $RPID))"
t0=$(date +%s); LAB_NODAEMON=1 timeout 20 bash "$DIR/labnice.sh" -s 2 sleep 2 & a=$!; wait $a; w=$(( $(date +%s) - t0 ))
ok $([ $w -le 4 ] && echo 1) "recording: new -s 2 job in budget ran through in ${w}s"
rm -f "$LAB_RECDIR/5090-take"; sleep 3
ok $([ "$(st $BPID)" != T ] && echo 1) "recording ended: over-budget job resumed (stat $(st $BPID))"
pkill -P $BPID 2>/dev/null; kill $BPID $RPID 2>/dev/null; pkill -f "$T/labnice.sh" 2>/dev/null; BPID=; RPID=
# daemon started by a job: detached (setsid -f), no labnice subshell left behind after the job ends
bash "$DIR/labnice.sh" bash -c ": selftest-$$" 2>/dev/null; sleep 1
left=$(pgrep -f "selftest-$$" | grep -vx $$ | wc -l)
dp=$(grep -lz "^LAB_D=$LAB_D\$" /proc/[0-9]*/environ 2>/dev/null | cut -d/ -f3 | while read p; do grep -qa lab-recpause "/proc/$p/cmdline" 2>/dev/null && echo $p; done | head -1)
ok $([ "$left" = 0 ] && [ -n "$dp" ] && echo 1) "job-started daemon detached, nothing of the job left (left=$left daemon=${dp:-none})"
[ -n "$dp" ] && kill $dp 2>/dev/null
echo "RESULT labnice-selftest $([ $pass = $tot ] && echo PASS || echo FAIL) $pass/$tot"
[ $pass = $tot ]
