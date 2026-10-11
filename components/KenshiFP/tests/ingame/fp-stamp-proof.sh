#!/bin/bash
# fp-stamp-proof.sh <out dir> [e6|t6]   (WSL on the 5090, Git Bash on the 4080: RIG=5090|4080, rig-env.sh)
# Frame-stamp proof row (frame-stamp 2026-10-10): one short take with TAKE_STAMP=1 and the harness writing its stamp log:
# e6 (default on the 5090) = fp-e6-strokes.sh strokes "0 1" x1 (launch kah-fpxbow; 5090 only: fifo recorder),
# t6 (default on the 4080) = fp-turret-take.sh (launch kah-fpturret-e; rig-neutral), decoded from its raw video; then the decoder (harness tools/animlab/stamp.py) reads every frame of the take video and checks
# (1) every label mark shows (no `label k MISSING`), (2) every logged stamp change inside the decoded range shows at
# exactly its game frame (agree=yes mismatch=0), (3) the take's own checks ran on the stamp (takecheck "stamp" source).
# Needs KenshiFP with kfp-frame-stamp (payload) and harness >= 342C2851 (`stamp` command).
# Output in <out dir>: the take's files, e6.txt (take output), stamp-table.tsv, stamp-labels.txt, stamp.txt; last line:
#   RESULT STAMP-PROOF PASS|FAIL <decoder RESULT fields>
OUT=$1; MODE=$2
[ -n "$OUT" ] || { echo "usage: fp-stamp-proof.sh <out dir> [e6|t6]"; exit 2; }
mkdir -p "$OUT" && cd "$OUT" || { echo "RESULT STAMP-PROOF FAIL setup: out dir $OUT not usable"; exit 2; }
HERE=$(cd "$(dirname "$0")/../.." && pwd)
[ -n "$RIG" ] || . "$HERE/../../tools/automation/rig-env.sh"; CRR=${CR:-/mnt/c}
L=$CRR/KenshiModding/Kenshi-Automation-Harness/tools/animlab
LOGN=take-stamp-$$.log; KD=${KDIR:-/mnt/d/Steam/steamapps/common/Kenshi}; SLOG=$KD/mods/AutomationHarness/$LOGN
rm -f "$SLOG"
[ -n "$MODE" ] || { [ "${RIG:-5090}" = 4080 ] && MODE=t6 || MODE=e6; }
if [ "$MODE" = t6 ]; then V=t6raw.mp4 LB=labels.txt EV=ts.txt TC=T6.takecheck
  TAKE_STAMP=1 TAKE_STAMP_LOG=$LOGN bash "$HERE/tests/ingame/fp-turret-take.sh" "$OUT" > e6.txt 2>&1
else V=stp.mp4 LB=stp.lab EV=stp.ev.txt TC=stp.takecheck.txt
  TAKE_STAMP=1 TAKE_STAMP_LOG=$LOGN bash "$HERE/tests/ingame/fp-e6-strokes.sh" "$OUT" stp "0 1" 1 > e6.txt 2>&1
fi
E6=$(grep "^RESULT " e6.txt | tail -1); echo "take: $E6"
case "$E6" in *"FAIL setup"*|"") echo "RESULT STAMP-PROOF FAIL setup: $MODE take did not record (${E6:-no RESULT line}; $OUT/e6.txt)"; exit 1;; esac
[ -s $V ] || { echo "RESULT STAMP-PROOF FAIL no video $V ($OUT/e6.txt)"; exit 1; }
grep -q 'mark stamp=on' $EV 2>/dev/null || { echo "RESULT STAMP-PROOF FAIL stamp not turned on (harness reply: $(grep -h 'mark stamp=' $EV 2>/dev/null | head -1); KAH stamp command missing?)"; exit 1; }
[ -s "$SLOG" ] && cp "$SLOG" stamp.log
LG=; [ -s stamp.log ] && LG="--log stamp.log"
python3 "$L/stamp.py" $V --name STAMP-PROOF --out stamp-table.tsv --labels $LB --labels-out stamp-labels.txt $LG > stamp.txt 2>&1
R=$(grep '^RESULT ' stamp.txt | tail -1)
miss=$(grep -c 'MISSING' stamp.txt); tcs=$(grep -ci 'stamp' $TC e6.txt 2>/dev/null | awk -F: '{s+=$NF} END{print s+0}')
rest=${R#RESULT STAMP-PROOF }; rest=${rest#PASS }; rest=${rest#FAIL }
ok=1; why=
case "$R" in "RESULT STAMP-PROOF PASS"*) ;; *) ok=0; why="decoder FAIL;";; esac
[ -s stamp.log ] || { ok=0; why="$why no harness stamp log;"; }
case "$R" in *"agree=yes"*"mismatch=0"*) ;; *) ok=0; why="$why log agreement not exact;";; esac
[ "$miss" = 0 ] || { ok=0; why="$why $miss label marks missing;"; }
[ "${tcs:-0}" -gt 0 ] || why="$why (takecheck output does not mention stamp)"
rm -f "$SLOG"
if [ $ok = 1 ]; then echo "RESULT STAMP-PROOF PASS $rest take=[${E6#RESULT }] $why"
else echo "RESULT STAMP-PROOF FAIL $why $rest log=$OUT/stamp.txt"; exit 1; fi
