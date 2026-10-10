#!/bin/bash
# backfill.sh -- run a lab check once over the WHOLE evidence corpus (+ kept material) when the check is added or changed,
#   and report new FAILs on material that so far counted as passed (manifest expect PASS, or kept/backfill/INFO rows).
#   Usage (WSL): backfill.sh <rec|video> <name> '<command, {} = file>' [verdict regex, default ' FAIL']
#     e.g. backfill.sh rec guard 'python3 $L/animlab.py guard {}'
#          backfill.sh video cursor 'python3 $L/frames.py cursor {}'
#   $L = harness tools/animlab. Prints one line per file (`BF <name> PASS|FAIL|ERR <file> <expect> <last line>`) and
#   `RESULT BACKFILL <name> files=<n> fail=<n> new=<files that FAIL but were passed>`; logs to /root/animlab-gate/backfill-<name>.txt.
#   A `new` file is a lab find on old material: check it by eye, then add a Misses row (or an expected-FAIL manifest row).
set -u
C=${ANIMLAB_CORPUS:-/mnt/c/KenshiTestRuns/corpus}; export L=/mnt/c/KenshiModding/Kenshi-Automation-Harness/tools/animlab
kind=${1:?rec|video}; name=${2:?name}; cmd=${3:?command}; re=${4:- FAIL}
mkdir -p /root/animlab-gate; LOG=/root/animlab-gate/backfill-$name.txt; : > "$LOG"
case "$kind" in rec) pat='\.txt$';; video) pat='\.mp4$';; *) echo "kind rec|video"; exit 2;; esac
files=$(awk -F'\t' -v k="$kind" 'NR>1 && $7!="pending" && ($2==k || (k=="video" && $2=="video")) {print $1}' "$C/MANIFEST.tsv" | grep -E "$pat" | sort -u)
n=0; nf=0; new=()
for f in $files; do [ -f "$C/$f" ] || continue; n=$((n+1))
  exp=$(awk -F'\t' -v f="$f" 'NR>1 && $1==f {print $4}' "$C/MANIFEST.tsv" | sort -u | tr '\n' ',' | sed 's/,$//')
  out=$(cd /tmp && eval "${cmd//\{\}/\"$C/$f\"}" 2>&1 | grep -v '^\s*$' | tail -1)
  if [ -z "$out" ] || echo "$out" | grep -q 'Traceback\|Error'; then v=ERR; elif echo "$out" | grep -qE "$re"; then v=FAIL; else v=PASS; fi
  echo "BF $name $v $f $exp ${out:0:160}" | tee -a "$LOG"
  if [ $v = FAIL ]; then nf=$((nf+1)); case ",$exp," in *,FAIL,*) ;; *) new+=("$f");; esac; fi
done
echo "RESULT BACKFILL $name files=$n fail=$nf new=$(IFS=,; echo "${new[*]:-none}")" | tee -a "$LOG"
