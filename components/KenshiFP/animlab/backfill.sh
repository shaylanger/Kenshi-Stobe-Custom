#!/bin/bash
# backfill.sh -- run a lab check once over the WHOLE evidence corpus (+ kept material) when the check is added or changed,
#   and report new FAILs on material that so far counted as passed (manifest expect PASS, or kept/backfill/INFO rows).
#   Usage (WSL): backfill.sh <rec|video> <name> '<command, {} = file>' [verdict regex, default ' FAIL']
#     e.g. backfill.sh rec guard 'python3 $L/animlab.py guard {}'
#          backfill.sh video cursor 'python3 $L/frames.py cursor {}'
#   $L = harness tools/animlab. Prints one line per file (`BF <name> PASS|FAIL|ERR <file> <expect> <last line>`) and
#   `RESULT BACKFILL <name> files=<n> fail=<n> skip=<n> new=<files that FAIL but were passed>`.
#   SKIP = the check does not apply to that material (its last line matches BF_NA, default: n/a, no swing, no block,
#   block frames=0, band_frames=0, NO_FULL_SWING); not counted as FAIL. `new` = FAIL with no manifest row for this file
#   whose check names <name> and expects FAIL (an expected FAIL of another check does not hide a new find); logs to /root/animlab-gate/backfill-<name>.txt.
#   A `new` file is a lab find on old material: check it by eye, then add a Misses row (or an expected-FAIL manifest row).
set -u
C=${ANIMLAB_CORPUS:-/mnt/c/KenshiTestRuns/corpus}; export L=/mnt/c/KenshiModding/Kenshi-Automation-Harness/tools/animlab
kind=${1:?rec|video}; name=${2:?name}; cmd=${3:?command}; re=${4:- FAIL}
NA=${BF_NA:-n/a|no swing|no block|block frames=0 |band_frames=0|NO_FULL_SWING}
mkdir -p /root/animlab-gate; LOG=/root/animlab-gate/backfill-$name.txt; : > "$LOG"
case "$kind" in rec) pat='\.txt$';; video) pat='\.mp4$';; *) echo "kind rec|video"; exit 2;; esac
files=$(awk -F'\t' -v k="$kind" 'NR>1 && $7!="pending" && ($2==k || (k=="video" && $2=="video")) {print $1}' "$C/MANIFEST.tsv" | grep -E "$pat" | sort -u)
n=0; nf=0; ns=0; new=()
for f in $files; do [ -f "$C/$f" ] || continue; n=$((n+1))
  exp=$(awk -F'\t' -v f="$f" 'NR>1 && $1==f {print $4}' "$C/MANIFEST.tsv" | sort -u | tr '\n' ',' | sed 's/,$//')
  xf=$(awk -F'\t' -v f="$f" -v c="$name" 'NR>1 && $1==f && $4=="FAIL" && index($3,c) {print "y"; exit}' "$C/MANIFEST.tsv")
  out=$(cd /tmp && eval "${cmd//\{\}/\"$C/$f\"}" 2>&1 | grep -v '^\s*$' | tail -1)
  if [ -z "$out" ] || echo "$out" | grep -q 'Traceback\|Error'; then v=ERR; elif echo "$out" | grep -qE "$NA"; then v=SKIP; ns=$((ns+1)); elif echo "$out" | grep -qE "$re"; then v=FAIL; else v=PASS; fi
  echo "BF $name $v $f $exp ${out:0:160}" | tee -a "$LOG"
  if [ $v = FAIL ]; then nf=$((nf+1)); [ -n "$xf" ] || new+=("$f"); fi
done
echo "RESULT BACKFILL $name files=$n fail=$nf skip=$ns new=$(IFS=,; echo "${new[*]:-none}")" | tee -a "$LOG"
