#!/bin/bash
# gate.sh -- the animation lab's per-build gate: EVERY lab check on the WHOLE evidence corpus, one RESULT line.
#   Run in WSL after every KenshiFP viewmodel build, before VMQUICK (fp-viewmodel.sh runs it itself when no result for
#   the current source exists). Fully offline (no game).
#   1. corpus.sh verify (every pinned file present, sha unchanged)
#   2b. agree-pose.sh: per-bone replay agreement of corpus/agree/pose.list recordings (exact source per DLL)
#   2. regress.sh in an EMPTY work dir filled only from the corpus (all FAIL-old/PASS-new pairs, replays of the current
#      /root/KenshiFP source); a REGRESS FAIL, or an INFO saying a corpus file is missing, fails the gate
#   3. E6 swing pool (`animlab.py pool` over corpus pools/sword-swing/pool-all.list, maintainer's E6 gate) on the current source's adapter for every stroke
#      with key tables (0..VM_NSTROKE-1 in kfp_viewmodel.inc) + its default mask + strokes listed in corpus pool/strokes.tsv;
#      checks arc,blade,stroke,churn -> verdict `POOL stroke s`, the take judge's inline -> its own verdict `POOL-INLINE stroke s`
#      (Misses 2026-10-11 "E6 stroke 3 wind-up inline": the pool judged no inline), both judged against the baseline
#   3b. stroke-cycle.py: E6 default stroke cycle per weapon class (unforced swings, the source's own default mask; Misses
#      2026-10-11 "E6 default stroke cycle": 6E7C0363 kept the 2H-light katana on stroke 0); a FAIL fails the gate
#   3c. e6-takes.py: every corpus E6 GAME take (pools/e6-takes/takes.list) replayed with the current source, per take x stroke
#      inline + arc like the take judge (Misses 2026-10-11 "E6-s1pt30-s1": the pool aggregate hid a per-take FAIL); baseline
#   4. mutation tests (mutate.py): every check must FAIL its own synthetic corruption of known-good corpus material
#   5. flips vs the last accepted baseline (corpus gate-baseline.tsv): any PASS that became FAIL or stopped running
#      (a fixed miss coming back, a check silently skipped) fails the gate
#   Prints: RESULT ANIMLAB-REGRESS PASS|FAIL checks=<n> pass=<n> fail=<n> pairs=<n> pending=<n> pool=<s:verdict..>
#           pinl=<s:verdict,..> cycle=<verdict> e6takes=<n>/<fail> mutations=<caught>/<n> flipped=<keys|none> log=<dir>
# Usage: gate.sh hash   (print the source/lab/corpus hash a cached result is keyed by)
#        gate.sh [--update-baseline] [--src /root/KenshiFP] [--out DIR] [--no-mutate]
#   --update-baseline: after a PASS (or an accepted change: read the flips first) store this run as the baseline.
#   Result cache: /root/animlab-gate/result-<srchash>.txt (srchash = sha of the KenshiFP client source + lab + corpus manifest).
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"; L=/mnt/c/KenshiModding/Kenshi-Automation-Harness/tools/animlab
# Snapshot (animlab-maintainer 2026-10-11): the gate runs from a private copy of this dir, so editing regress.sh / mutate.py /
# any lab script while a gate runs (pipelines start every few minutes) cannot corrupt it (bash reads scripts incrementally).
if [ -z "${GATE_SNAP:-}" ]; then GATE_SNAP=$(mktemp -d /tmp/animlab-gatesnap.XXXXXX) && cp -a "$HERE"/. "$GATE_SNAP"/ && export GATE_SNAP && { trap 'rm -rf "$GATE_SNAP"' EXIT; bash "$GATE_SNAP/gate.sh" "$@"; exit $?; }; fi
C=${ANIMLAB_CORPUS:-/mnt/c/KenshiTestRuns/corpus}; SRC=/root/KenshiFP; UPD=0; MUT=1; G=/root/animlab-gate; OUT=""
HASHONLY=0; [ "${1:-}" = hash ] && { HASHONLY=1; shift; }
while [ $# -gt 0 ]; do case "$1" in --update-baseline) UPD=1;; --src) SRC=$2; shift;; --out) OUT=$2; shift;; --no-mutate) MUT=0;;
*) echo "gate.sh: unknown arg $1"; exit 2;; esac; shift; done
srchash() { (cd "$SRC/client" && find . -type f \( -name '*.inc' -o -name '*.c' -o -name '*.cpp' -o -name '*.h' \) -print0 | sort -z | xargs -0 cat
  cat "$L"/*.py "$HERE"/regress.sh "$HERE"/mutate.py "$HERE"/stroke-cycle.py "$HERE"/e6-takes.py "$HERE"/fist-*.py "$C/MANIFEST.tsv" 2>/dev/null) | sha256sum | cut -c1-12; }
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
# 2b. replay agreement (lab-calibrate 2026-10-11): every corpus/agree/pose.list game recording, replayed by a lab built from
#     the exact source of the DLL that recorded it, must match the game's arm joints per record within its tolerance
bash "$HERE/agree-pose.sh" --out "$OUT/agree-pose" > "$OUT/agree-pose.txt" 2>&1 || { fail=1; why+=(agree-pose); }
grep '^AGREE-POSE ' "$OUT/agree-pose.txt" | awk '{n=$3; sub(/:$/,"",n); print "AGREE-POSE", n, $2}' >> "$OUT/verdicts.raw"; rm -rf "$OUT/agree-pose"
# 3. E6 pool for EVERY stroke that has key tables (0 .. VM_NSTROKE-1 in kfp_viewmodel.inc), not only the default mask:
#    gate coverage class (Misses 2026-10-10): the pt30 change dropped stroke 1 take_all 0.95 -> 0.64 and passed the gate
#    because only mask stroke 0 was pooled (game take kfx-b9 e6r4 confirmed the snap). Strokes are switched on at run time
#    (fp_vm set strokes), so every stroke the source can play is pooled; corpus pool/strokes.tsv adds extra adapter args.
mask=$(grep -o 'static int g_vm_strokes = 0x[0-9a-fA-F]*' "$SRC/client/kfp_viewmodel.inc" 2>/dev/null | grep -o '0x.*'); mask=$((${mask:-0x1}))
nstk=$(grep -o '#define VM_NSTROKE [0-9]*' "$SRC/client/kfp_viewmodel.inc" 2>/dev/null | awk '{print $3}'); nstk=${nstk:-1}
strokes=$(for n in $(seq 0 $((nstk - 1))); do echo $n; done; for n in 0 1 2 3 4 5 6 7; do [ $(( (mask >> n) & 1 )) = 1 ] && echo $n; done; awk '!/^#/ && NF {print $1}' "$C/pool/strokes.tsv" 2>/dev/null)
PR=""; PI=""; : > "$OUT/pool.txt"
for s in $(echo "$strokes" | sort -un); do
  xa=$(awk -v s=$s '!/^#/ && $1==s {$1=""; print}' "$C/pool/strokes.tsv" 2>/dev/null)
  r=$(cd "$W/pools/sword-swing" && python3 "$L/animlab.py" pool @pool-all.list --adapter /root/animlab-build/kfpvm_cur --stroke $s --overhead 2 --checks arc,blade,stroke,churn,inline $xa --keep "$OUT/pool-s$s" 2>&1 | tail -1)
  echo "$r" >> "$OUT/pool.txt"
  # one pool run, two verdicts: inline token (inline:...:BAD) vs every other check / the swing count (any other :BAD)
  vv=$(echo "$r" | sed 's/ (.*$//' | awk '$1=="pool" && ($4=="PASS" || $4=="FAIL") {b="PASS"; i="PASS"; for (k=5; k<=NF; k++) if (index($k, ":BAD")) { if ($k ~ /^inline:/) i="FAIL"; else b="FAIL" }
    if ($4=="FAIL" && b=="PASS" && i=="PASS") b="FAIL"; print b, i}')
  v=${vv% *}; vi=${vv#* }; [ -n "$vv" ] || { v=ERR; vi=ERR; }
  PR="$PR s$s:$v"; PI="$PI,s$s:$vi"
  echo "POOL stroke $s $v" >> "$OUT/verdicts.raw"; echo "POOL-INLINE stroke $s $vi" >> "$OUT/verdicts.raw"
done
rm -rf "$OUT"/pool-s*
# 3b. E6 default stroke cycle (stroke-cycle.py, the adapter's own source copy kfpvm_cur.d = what the pool replayed)
CS=/root/animlab-build/kfpvm_cur.d/client; [ -f "$CS/kfp_viewmodel.inc" ] || CS=$SRC/client
python3 "$HERE/stroke-cycle.py" --adapter /root/animlab-build/kfpvm_cur --src "$CS" > "$OUT/stroke-cycle.txt" 2>&1
CY=$(grep -o '^RESULT STROKE-CYCLE [A-Z]*' "$OUT/stroke-cycle.txt" | awk '{print $3}'); CY=${CY:-ERR}
[ "$CY" = PASS ] || { fail=1; why+=(stroke-cycle); }
grep '^CYCLE ' "$OUT/stroke-cycle.txt" | awk '{print "CYCLE", $2, $3}' >> "$OUT/verdicts.raw"
# 3c. corpus E6 game takes replayed with the current source, per take x stroke (e6-takes.py; judged against the baseline)
python3 "$HERE/e6-takes.py" --adapter /root/animlab-build/kfpvm_cur > "$OUT/e6-takes.txt" 2>&1
ET=$(grep -o '^RESULT E6-TAKES [A-Z]* n=[0-9]* fail=[0-9]*' "$OUT/e6-takes.txt" | awk '{sub(/n=/,"",$4); sub(/fail=/,"",$5); print $4 "/" $5}'); ET=${ET:-ERR}
grep -q '^RESULT E6-TAKES' "$OUT/e6-takes.txt" || echo "E6-TAKES run ERR" >> "$OUT/verdicts.raw"
grep '^E6TAKE ' "$OUT/e6-takes.txt" | awk '{print "E6TAKE", $2, $3, $4, $5}' >> "$OUT/verdicts.raw"
# 4. mutations
MR="skipped"
if [ $MUT = 1 ]; then python3 "$HERE/mutate.py" --work "$W" --out "$OUT/mut" > "$OUT/mutate.txt" 2>&1
  MR=$(grep -o '^RESULT MUTATIONS.*' "$OUT/mutate.txt" | awk '{print $4}'); grep -q '^RESULT MUTATIONS PASS' "$OUT/mutate.txt" || { fail=1; why+=(mutation-missed); }
  # key = the mutation id (was "MUT <status>" with the id as the value: one key for all, a MISSED mutation never flipped)
  grep '^MUT ' "$OUT/mutate.txt" | awk '{print "MUT", $2, ($3=="CAUGHT" || $3=="FIXED") ? "PASS" : "FAIL"}' >> "$OUT/verdicts.raw"; rm -rf "$OUT/mut"; fi
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
line="RESULT ANIMLAB-REGRESS $V checks=$nc pass=$np fail=$nf $pairs $pend pool=${PR# } pinl=${PI#,} cycle=$CY e6takes=$ET mutations=$MR flipped=${FL:-none} src=$H$( [ $fail = 1 ] && echo " why=$(IFS=,; echo "${why[*]}")") log=$OUT"
echo "$line" | tee "$OUT/RESULT.txt"; cp "$OUT/RESULT.txt" "$G/result-$H.txt"
if [ $UPD = 1 ]; then chmod u+w "$B" 2>/dev/null; cp "$OUT/verdicts.tsv" "$B"; echo "gate: baseline updated ($nc verdicts) -> $B"; fi
ls -dt "$G"/run-* 2>/dev/null | tail -n +7 | xargs -r rm -rf   # keep the newest 6 runs
exit $fail
