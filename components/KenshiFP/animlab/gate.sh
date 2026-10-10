#!/bin/bash
# gate.sh -- the animation lab's per-build gate: EVERY lab check on the WHOLE evidence corpus, one RESULT line.
#   Run in WSL after every KenshiFP viewmodel build, before VMQUICK (fp-viewmodel.sh runs it itself when no result for
#   the current source exists). Fully offline (no game).
#   1. corpus.sh verify (every pinned file present, sha unchanged)
#   2. regress.sh in an EMPTY work dir filled only from the corpus (all FAIL-old/PASS-new pairs, replays of the current
#      /root/KenshiFP source); a REGRESS FAIL, or an INFO saying a corpus file is missing, fails the gate
#   3. E6 swing pool (`animlab.py pool` over corpus pools/sword-swing/pool-all.list, maintainer's E6 gate) on the current source's adapter for every stroke enabled in
#      its default mask (g_vm_strokes in kfp_viewmodel.inc) + strokes listed in corpus pool/strokes.tsv
#   4. mutation tests (mutate.py): every check must FAIL its own synthetic corruption of known-good corpus material
#   5. flips vs the last accepted baseline (corpus gate-baseline.tsv): any PASS that became FAIL or stopped running
#      (a fixed miss coming back, a check silently skipped) fails the gate
#   Prints: RESULT ANIMLAB-REGRESS PASS|FAIL checks=<n> pass=<n> fail=<n> pairs=<n> pending=<n> pool=<s:verdict..>
#           mutations=<caught>/<n> flipped=<keys|none> log=<dir>
# Usage: gate.sh hash   (print the source/lab/corpus hash a cached result is keyed by)
#        gate.sh [--update-baseline] [--src /root/KenshiFP] [--out DIR] [--no-mutate]
#   --update-baseline: after a PASS (or an accepted change: read the flips first) store this run as the baseline.
#   Result cache: /root/animlab-gate/result-<srchash>.txt (srchash = sha of the KenshiFP client source + lab + corpus manifest).
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"; L=/mnt/c/KenshiModding/Kenshi-Automation-Harness/tools/animlab
C=${ANIMLAB_CORPUS:-/mnt/c/KenshiTestRuns/corpus}; SRC=/root/KenshiFP; UPD=0; MUT=1; G=/root/animlab-gate; OUT=""
HASHONLY=0; [ "${1:-}" = hash ] && { HASHONLY=1; shift; }
while [ $# -gt 0 ]; do case "$1" in --update-baseline) UPD=1;; --src) SRC=$2; shift;; --out) OUT=$2; shift;; --no-mutate) MUT=0;;
*) echo "gate.sh: unknown arg $1"; exit 2;; esac; shift; done
srchash() { (cd "$SRC/client" && find . -type f \( -name '*.inc' -o -name '*.c' -o -name '*.cpp' -o -name '*.h' \) -print0 | sort -z | xargs -0 cat
  cat "$L"/*.py "$HERE"/regress.sh "$HERE"/mutate.py "$C/MANIFEST.tsv" 2>/dev/null) | sha256sum | cut -c1-12; }
[ $HASHONLY = 1 ] && { srchash; exit 0; }
H=$(srchash); mkdir -p "$G"; OUT=${OUT:-$G/run-$(date +%m%d-%H%M%S)-$H}; mkdir -p "$OUT"; W=$G/work
fail=0; why=()
# 1. corpus
bash "$HERE/corpus.sh" verify > "$OUT/corpus.txt" 2>&1 || { fail=1; why+=(corpus); }
# 2. regress on a fresh work dir
rm -rf "$W"; mkdir -p "$W"
ANIMLAB_WORK=$W bash "$HERE/regress.sh" > "$OUT/regress.txt" 2>&1
grep -q '^REGRESS FAIL' "$OUT/regress.txt" && { fail=1; why+=(regress); }
if grep -E '^REGRESS INFO' "$OUT/regress.txt" | grep -viE 'not built|not recorded yet' | grep -qiE 'missing|recording or build'; then fail=1; why+=(corpus-file-missing); fi
# 3. E6 pool for each enabled stroke
mask=$(grep -o 'static int g_vm_strokes = 0x[0-9a-fA-F]*' "$SRC/client/kfp_viewmodel.inc" 2>/dev/null | grep -o '0x.*'); mask=$((${mask:-0x1}))
strokes=$(for n in 0 1 2 3 4 5 6 7; do [ $(( (mask >> n) & 1 )) = 1 ] && echo $n; done; awk '!/^#/ && NF {print $1}' "$C/pool/strokes.tsv" 2>/dev/null)
PR=""; : > "$OUT/pool.txt"
for s in $(echo "$strokes" | sort -un); do
  xa=$(awk -v s=$s '!/^#/ && $1==s {$1=""; print}' "$C/pool/strokes.tsv" 2>/dev/null)
  r=$(cd "$W/pools/sword-swing" && python3 "$L/animlab.py" pool @pool-all.list --adapter /root/animlab-build/kfpvm_cur --stroke $s --overhead 2 $xa --keep "$OUT/pool-s$s" 2>&1 | tail -1)
  echo "$r" >> "$OUT/pool.txt"; v=$(echo "$r" | awk '{print $4}'); PR="$PR s$s:${v:-ERR}"
  echo "POOL stroke $s ${v:-ERR}" >> "$OUT/verdicts.raw"
done
rm -rf "$OUT"/pool-s*
# 4. mutations
MR="skipped"
if [ $MUT = 1 ]; then python3 "$HERE/mutate.py" --work "$W" --out "$OUT/mut" > "$OUT/mutate.txt" 2>&1
  MR=$(grep -o '^RESULT MUTATIONS.*' "$OUT/mutate.txt" | awk '{print $4}'); grep -q '^RESULT MUTATIONS PASS' "$OUT/mutate.txt" || { fail=1; why+=(mutation-missed); }
  grep '^MUT ' "$OUT/mutate.txt" | awk '{print "MUT", $3, $2}' >> "$OUT/verdicts.raw"; rm -rf "$OUT/mut"; fi
# 5. verdict keys + flips (key = line text before the first ': ', digits folded; repeated keys numbered)
grep -E '^REGRESS (PASS|FAIL)' "$OUT/regress.txt" | awk '{v=$2; $1=$2=""; t=substr($0,3); i=index(t,": "); if (i) t=substr(t,1,i-1);
  gsub(/[0-9]+(\.[0-9]+)?/,"#",t); t=substr(t,1,90); k[t]++; if (k[t]>1) t=t " [" k[t] "]"; print t "\t" v}' > "$OUT/verdicts.tsv"
[ -f "$OUT/verdicts.raw" ] && awk '{v=$NF; $NF=""; sub(/ $/,""); print $0 "\t" v}' "$OUT/verdicts.raw" >> "$OUT/verdicts.tsv"
B=$C/gate-baseline.tsv; FL=""
if [ -f "$B" ]; then
  FL=$(awk -F'\t' 'NR==FNR {b[$1]=$2; next} {n[$1]=$2} END {for (k in b) { if (!(k in n)) { if (b[k]=="PASS") print "GONE:" k }
        else if (b[k]!=n[k]) print b[k] "->" n[k] ":" k }}' "$B" "$OUT/verdicts.tsv" | sort | tr '\n' ';' | tr ' ' '_')
  echo "$FL" | grep -qE '(PASS->|GONE:)' && { fail=1; why+=(flipped); }
fi
st=$(bash "$HERE/corpus.sh" stats); pairs=$(echo "$st" | grep -o 'pairs=[0-9]*'); pend=$(echo "$st" | grep -o 'pending=[0-9]*')
np=$(grep -c $'\tPASS$' "$OUT/verdicts.tsv"); nf=$(grep -c $'\tFAIL$' "$OUT/verdicts.tsv"); nc=$(wc -l < "$OUT/verdicts.tsv")
# pool FAILs are judged against the baseline only (stroke 0 = Shay-accepted baseline exception fails blade/arc by design)
[ $fail = 0 ] && V=PASS || V=FAIL
line="RESULT ANIMLAB-REGRESS $V checks=$nc pass=$np fail=$nf $pairs $pend pool=${PR# } mutations=$MR flipped=${FL:-none} src=$H$( [ $fail = 1 ] && echo " why=$(IFS=,; echo "${why[*]}")") log=$OUT"
echo "$line" | tee "$OUT/RESULT.txt"; cp "$OUT/RESULT.txt" "$G/result-$H.txt"
if [ $UPD = 1 ]; then chmod u+w "$B" 2>/dev/null; cp "$OUT/verdicts.tsv" "$B"; echo "gate: baseline updated ($nc verdicts) -> $B"; fi
ls -dt "$G"/run-* 2>/dev/null | tail -n +7 | xargs -r rm -rf   # keep the newest 6 runs
exit $fail
