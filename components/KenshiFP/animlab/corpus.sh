#!/bin/bash
# corpus.sh -- the animation lab's evidence corpus: every recording / video / take a lab check or regress step depends on.
#   Root: $ANIMLAB_CORPUS (default /mnt/c/KenshiTestRuns/corpus = C:\KenshiTestRuns\corpus). PROTECTED: cleanup never
#   touches it (CLAUDE.md clean-up rules, tools/automation cleanup scripts skip it). Files are never modified in place.
#   Layout: rec/<name>            game/replay recordings (+ sidecars like <rec>.bolt), flat, the names regress.sh uses in $W
#           pools/<pool>/         animlab-maintainer's pools (sword-swing = E6 `animlab.py pool`, block-guard), lists relative
#           agree/, logs/animlive/ maintainer's replay-agreement set and animlive KenshiFP logs (README in each)
#           takes/<take>/         labelled takes (labels.txt, ev.txt, video-len.txt); takes/videos/*.mp4 (regress videos)
#           kept/<name>           kept material no check pins yet (backfill only: newest VMQUICK, reviewed videos, tables)
#           MANIFEST.tsv          name kind check expect build source status notes (one row per file x check)
#           SHA256SUMS            sha256 of every file (verify)
#   status: ok = present and pinned by a check; pending = expected file, not recorded yet (the check INFO-skips until it
#   exists); kept = backfill only. expect: FAIL / PASS / INFO / "-" (backfill only).
# Usage (WSL):
#   corpus.sh add <file> <name> <kind> <check> <expect> <build> <source> [notes]   copy a file in + manifest row(s)
#   corpus.sh row <name> <kind> <check> <expect> <build> <source> <status> [notes] add a manifest row only (pending etc.)
#   corpus.sh verify        every ok/kept row has its file and the sha matches; prints RESULT CORPUS PASS|FAIL
#   corpus.sh sync <dir>    copy rec/* (flat) + takes/ pools/ agree/ logs/ (trees) into a work dir (regress $W)
#   corpus.sh stats         files, size, rows, pairs (check with an ok FAIL and an ok PASS row), pending rows
#   corpus.sh files [kind]  list ok+kept files (relative names) of a kind (rec|video|take|sidecar|table|list)
set -u
C=${ANIMLAB_CORPUS:-/mnt/c/KenshiTestRuns/corpus}; M=$C/MANIFEST.tsv; S=$C/SHA256SUMS
hdr() { [ -f "$M" ] || printf 'name\tkind\tcheck\texpect\tbuild\tsource\tstatus\tnotes\n' > "$M"; }
sumfile() { (cd "$C" && { grep -v "  $1\$" SHA256SUMS 2>/dev/null; sha256sum "$1"; } > SHA256SUMS.new && mv SHA256SUMS.new SHA256SUMS); }
cmd=${1:-stats}; shift || true
case "$cmd" in
add)
  [ $# -ge 7 ] || { echo "usage: corpus.sh add <file> <name> <kind> <check> <expect> <build> <source> [notes]"; exit 2; }
  f=$1 n=$2; [ -f "$f" ] || { echo "corpus: $f missing"; exit 1; }
  mkdir -p "$C/$(dirname "$n")"; hdr
  if [ -f "$C/$n" ] && ! cmp -s "$f" "$C/$n"; then echo "corpus: $n exists with other content (never overwritten; pick a new name)"; exit 1; fi
  cp -n "$f" "$C/$n"; chmod a-w "$C/$n" 2>/dev/null; sumfile "$n"
  awk -F'\t' -v n="$n" -v c="$4" '!($1==n && $3==c)' "$M" > "$M.new" && mv "$M.new" "$M"   # replaces a pending row
  printf '%s\t%s\t%s\t%s\t%s\t%s\tok\t%s\n' "$n" "$3" "$4" "$5" "$6" "$7" "${8:-}" >> "$M"; echo "corpus: added $n ($4 $5)";;
row)
  [ $# -ge 7 ] || { echo "usage: corpus.sh row <name> <kind> <check> <expect> <build> <source> <status> [notes]"; exit 2; }
  hdr; printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$4" "$5" "$6" "$7" "${8:-}" >> "$M";;
verify)
  bad=0; n=0
  while IFS=$'\t' read -r name kind check expect build src status notes; do
    [ "$name" = name ] && continue; [ "$status" = pending ] && continue; n=$((n+1))
    [ -f "$C/$name" ] || { echo "corpus MISSING $name ($check)"; bad=1; }
  done < "$M"
  (cd "$C" && sha256sum --quiet -c SHA256SUMS 2>&1) | sed 's/^/corpus /' | grep . && bad=1
  [ $bad = 0 ] && echo "RESULT CORPUS PASS rows=$n files=$(wc -l < "$S")" || { echo "RESULT CORPUS FAIL (missing or changed files above)"; exit 1; };;
sync)
  d=${1:?sync <dir>}; mkdir -p "$d"
  find "$C/rec" -maxdepth 1 -type f -exec cp -n {} "$d/" \;
  [ -e "$d/rec" ] || ln -s . "$d/rec"   # agree.list etc. name ../rec/<x> = the flat rec copies
  for t in pools agree logs; do [ -d "$C/$t" ] && { mkdir -p "$d/$t"; cp -rn "$C/$t/." "$d/$t/"; }; done
  [ -d "$C/takes" ] && { mkdir -p "$d/takes"; cp -rn "$C/takes/." "$d/takes/"; }; chmod -R u+w "$d" 2>/dev/null; true;;
stats)
  awk -F'\t' 'NR>1{rows++; if($7=="pending")pend++; split($3,a," "); k=a[1]; sub(/[a-z]+$/,"",k)
    if($7=="ok"){if($4=="FAIL")f[k]=1; if($4=="PASS")p[k]=1}}
    END{for(c in f) if(c in p) pairs++; printf "rows=%d pairs=%d pending=%d", rows, pairs, pend}' "$M"
  echo " files=$(wc -l < "$S") size=$(du -sh "$C" | cut -f1)";;
files)
  awk -F'\t' -v k="${1:-}" 'NR>1 && $7!="pending" && (k=="" || $2==k) {print $1}' "$M" | sort -u;;
*) sed -n 2,20p "$0"; exit 2;;
esac
