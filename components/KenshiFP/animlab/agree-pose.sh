#!/bin/bash
# agree-pose.sh -- does the lab still PREDICT THE GAME? Per-bone replay agreement of corpus game recordings (lab-calibrate,
#   2026-10-11). For every line of $C/agree/pose.list the recording is replayed by a lab built from the EXACT KenshiFP
#   source of the DLL that recorded it (its `# src <rev> <DLL sha8>` header -> source snapshot KenshiFP-<sha8>.client.tar.gz
#   in $C/src/ or /root/kfp-pipeline/src/, written by kfp-pipeline at every stage), and posedump.py compares the replayed
#   arm joints / hand axes with the ones the game measured (fromrec) on every viewmodel-up record.
#   Why exact source: replaying a recording with the CURRENT source + pending-fixes put the sword forearm 3-5 dm off in
#   swings (the game ran older versions of the pending patches: e6sw DF24EB64 had s1-edge-swing without the stroke-1
#   refit); with its own source the same recording agrees within 0.15 dm median.
# Usage: agree-pose.sh [--out DIR] [--list FILE]   (WSL root)
#   pose.list lines: <rec path relative to $C> [skip=N] [tol=DM] [ang=DEG] [args...]   (# comments)
#   Prints one `AGREE-POSE PASS|FAIL <rec>: <evidence>` per line and `RESULT AGREE-POSE PASS|FAIL n=.. fail=..`; exit 1 on FAIL.
#   A recording whose source snapshot is missing FAILS (a recording nobody can replay exactly is not evidence).
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"; L=/mnt/c/KenshiModding/Kenshi-Automation-Harness/tools/animlab
C=${ANIMLAB_CORPUS:-/mnt/c/KenshiTestRuns/corpus}; OUT=""; LIST=""
while [ $# -gt 0 ]; do case "$1" in --out) OUT=$2; shift;; --list) LIST=$2; shift;; *) echo "agree-pose.sh: unknown arg $1"; exit 2;; esac; shift; done
LIST=${LIST:-$C/agree/pose.list}; OUT=${OUT:-/root/animlab-work/agree-pose}; mkdir -p "$OUT"
PD=/mnt/c/KenshiModding/pending-fixes/kfp-posedump.py
# srcdir <sha8>: extracted client dir of that DLL's source (cached in /root/animlab-build/src-<sha8>)
srcdir() { local h=$1 t d=/root/animlab-build/src-$1
  [ -f "$d/client/kfp_viewmodel.inc" ] && { echo "$d/client"; return 0; }
  for t in "$C/src/KenshiFP-$h.client.tar.gz" "/root/kfp-pipeline/src/KenshiFP-$h.client.tar.gz"; do
    [ -f "$t" ] && { rm -rf "$d"; mkdir -p "$d"; tar xzf "$t" -C "$d" && echo "$d/client"; return 0; }; done; return 1; }
n=0; nf=0
while read -r rec rest; do
  case "$rec" in ''|'#'*) continue;; esac
  n=$((n + 1)); R=$C/$rec; name=$(basename "$rec" .txt)
  skip=3; tol=0.5; ang=15; xa=()
  for a in $rest; do case "$a" in skip=*) skip=${a#skip=};; tol=*) tol=${a#tol=};; ang=*) ang=${a#ang=};; *) xa+=("$a");; esac; done
  h=$(grep -m1 '^# src ' "$R" 2>/dev/null | awk '{print $NF}' | tr -d '\r')
  if [ ! -f "$R" ]; then echo "AGREE-POSE FAIL $name: recording missing $R"; nf=$((nf + 1)); continue; fi
  sd=$(srcdir "$h") || { echo "AGREE-POSE FAIL $name: no source snapshot for DLL ${h:-?} (KenshiFP-$h.client.tar.gz)"; nf=$((nf + 1)); continue; }
  B=/root/animlab-build/kfpvm_pd_$h; pa=(); grep -q vm_pd_write "$sd/kfp_viewmodel.inc" || pa=(--patch "$PD")
  nice -n 15 bash "$HERE/build.sh" --src "$sd" "${pa[@]}" --out "$B" < /dev/null > "$OUT/$name.build.txt" 2>&1 \
    || { echo "AGREE-POSE FAIL $name: lab build failed ($OUT/$name.build.txt)"; nf=$((nf + 1)); continue; }
  python3 "$L/posedump.py" fromrec "$R" "$OUT/$name.pd" < /dev/null > /dev/null 2>&1
  r=$(KFPVM_POSEDUMP=$B python3 "$L/posedump.py" compare "$OUT/$name.pd" --rec "$R" --skip "$skip" --pos-tol "$tol" --ang-tol "$ang" \
      --row "$name" --out "$OUT/$name" "${xa[@]}" < /dev/null 2>&1 | grep '^RESULT' | tail -1)
  v=$(echo "$r" | awk '{print $3}'); [ "$v" = PASS ] || { v=FAIL; nf=$((nf + 1)); }
  echo "AGREE-POSE $v $name: dll=$h ${r#RESULT $name * }"
done < "$LIST"
[ $nf = 0 ] && [ $n -gt 0 ] && V=PASS || V=FAIL
echo "RESULT AGREE-POSE $V n=$n fail=$nf list=$LIST out=$OUT"
[ $V = PASS ]
