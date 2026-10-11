#!/bin/bash
# kfp-pipeline-selftest.sh -- offline selftest of kfp-pipeline.sh's gate decisions (seconds, no build, no gate).
# Sources the "decide-fns" block (metrics, compare, kb_eval, guard_cut) and feeds it fake gate outputs:
#   1 empty agree text on 'all' (run-watch-1011-1606): verdict INFRA, compare flags infra, never BREAK/newfail
#   2 a regress FAIL that fails identically on base (agree + overlay miss, run-watch-1011-1705): known-base, not blocking
#   3 a FAIL only on 'all': blocking (new-fail)
#   4 guard: 14/14 patches BREAK in-set with no per-patch breaker -> refused; with one clear breaker -> only it is cut
# Usage (WSL): bash kfp-pipeline-selftest.sh [path/to/kfp-pipeline.sh]   -> last line "SELFTEST kfp-pipeline PASS|FAIL"
P=${1:-$(dirname "$0")/kfp-pipeline.sh}
T=$(mktemp -d /tmp/kfpst-XXXX); trap 'rm -rf "$T"' EXIT
sed -n '/^# >>> decide-fns/,/^# <<< decide-fns/p' "$P" > "$T/fns.sh"
grep -q '^guard_cut()' "$T/fns.sh" || { echo "SELFTEST kfp-pipeline FAIL decide-fns block not found in $P"; exit 1; }
. "$T/fns.sh"; DROP=0.05; F=0
ck() { if [ "$2" = "$3" ]; then echo "ok   $1"; else echo "FAIL $1: got [$2] want [$3]"; F=1; fi; }
mk() { # mk <run> <label> <regress lines> <verdict lines> [RESULT line]
  mkdir -p "$1/gate-$2" "$1/logs"; printf '%b' "$3" > "$1/gate-$2/regress.txt"; printf '%b' "$4" > "$1/gate-$2/verdicts.tsv"
  [ -n "${5:-}" ] && echo "$5" > "$1/gate-$2/RESULT.txt"; echo 1 > "$1/logs/gate-$2.rc"; }
AGB='REGRESS FAIL agree: agree FAIL recs=23 checks: arc 15/15 disagreements=18\n'
RB='RESULT ANIMLAB-REGRESS FAIL fail=2 flipped=GONE:agree_(baseline_#);PASS->FAIL:overlay_miss; why=regress,flipped log=x'
# 1 empty agree on all
RUN=$T/r1; N=14
mk $RUN base "REGRESS PASS x: ok\n$AGB" 'x\tPASS\nagree\tFAIL\n' "$RB"
mk $RUN all 'REGRESS PASS x: ok\nREGRESS FAIL agree: \n' 'x\tPASS\nagree:\tFAIL\n' "$RB"
for l in base all; do metrics $l > "$RUN/metrics-$l.tsv"; done
ck "1 empty agree -> INFRA" "$(grep '^agree' "$RUN/metrics-all.tsv")" "$(printf 'agree\tINFRA')"
ck "1 compare flag infra" "$(compare SET set base all | cut -f3,7 | tr '\t' ' ')" "agree infra"
ck "1 no BREAK/newfail" "$(compare SET in-set base all | awk -F'\t' '$7=="BREAK"||$7=="newfail"' | wc -l)" 0
# 2 identical regress FAILs on base = known-base
RUN=$T/r2; N=15
mk $RUN base "$AGB"'REGRESS FAIL overlay miss: q\n' 'agree\tFAIL\noverlay miss\tFAIL\n' "$RB"
mk $RUN all "$AGB"'REGRESS FAIL overlay miss: q\n' 'agree\tFAIL\noverlay miss\tFAIL\n' "$RB"
for l in base all; do metrics $l > "$RUN/metrics-$l.tsv"; done
kb_eval; ck "2 known-base GB empty" "$GB" ""; ck "2 known-base KB names agree" "$(echo "$KB" | grep -o 'FAIL:agree')" "FAIL:agree"
ck "2 compare no rows" "$(compare SET set base all | wc -l)" 0
# 3 a FAIL only on all blocks
RUN=$T/r3; N=15
mk $RUN base "$AGB" 'agree\tFAIL\nzz\tPASS\n' "$RB"
mk $RUN all "$AGB"'REGRESS FAIL zz: broke\n' 'agree\tFAIL\nzz\tFAIL\n' "$RB"
for l in base all; do metrics $l > "$RUN/metrics-$l.tsv"; done
kb_eval; ck "3 new FAIL blocks" "$(echo "$GB" | grep -o 'new-fail=zz')" "new-fail=zz"
ck "3 compare in-set BREAK" "$(compare SET in-set base all | cut -f3,7 | tr '\t' ' ')" "zz BREAK"
# 4 guard
RUN=$T/r4; N=14; D=$RUN/delta.tsv; mkdir -p $RUN; ALLP=$(seq -s, -f 'p%g' 1 14)
printf 'patch\tcompare\tkey\tbefore\tafter\tdelta\tflag\n' > "$D"
for i in $(seq 1 14); do printf 'p%s\tin-set\tagree:\t-\tFAIL\t-\tBREAK\n' $i >> "$D"; done
g=$(guard_cut "$ALLP"); ck "4 guard refuses 14/14 without breaker" "$?:$(echo "$g" | grep -o 'would exclude 14/14')" "1:would exclude 14/14"
printf 'p7\talone\tzz\tPASS\tFAIL\t-\tflip\n' >> "$D"
ck "4 guard keeps only the clear breaker" "$(guard_cut "$ALLP")" "p7"
ck "4 small cut passes unchanged" "$(guard_cut p3,p4)" "p3,p4"
# 5 recency fast path: clean_minus accepts a minus-one tree with only base FAILs, refuses a new FAIL / INFRA
RUN=$T/r5; N=15
mk $RUN base "$AGB" 'agree\tFAIL\nzz\tPASS\n' "$RB"
mk $RUN -p1 "$AGB" 'agree\tFAIL\nzz\tPASS\n' "$RB"
mk $RUN -p2 "$AGB"'REGRESS FAIL zz: broke\n' 'agree\tFAIL\nzz\tFAIL\n' "$RB"
mk $RUN -p3 'REGRESS FAIL agree: \n' 'agree:\tFAIL\nzz\tPASS\n' "$RB"
for l in base -p1 -p2 -p3; do metrics $l > "$RUN/metrics-$l.tsv"; done
ck "5 clean minus-one accepted" "$(clean_minus -p1 && echo y || echo n)" y
ck "5 minus-one with new FAIL refused" "$(clean_minus -p2 && echo y || echo n)" n
ck "5 minus-one with INFRA refused" "$(clean_minus -p3 && echo y || echo n)" n
# 6 mutation-missed only from BASEFAIL (corpus recording missing) = known-base; a real MISSED blocks
RB6='RESULT ANIMLAB-REGRESS FAIL fail=1 flipped=none why=regress,mutation-missed log=x'
RUN=$T/r6; N=15
mk $RUN base "$AGB" 'agree\tFAIL\n' "${RB6/,mutation-missed/}"
mk $RUN all "$AGB" 'agree\tFAIL\n' "$RB6"
printf 'MUT a CAUGHT x\nMUT rec-path-late-drift BASEFAIL - base ab2h-5090.txt missing\nRESULT MUTATIONS FAIL 18/19 missed=rec-path-late-drift known=none\n' > $RUN/gate-all/mutate.txt
for l in base all; do metrics $l > "$RUN/metrics-$l.tsv"; done
kb_eval; ck "6 BASEFAIL mutation known-base" "$GB|$(echo "$KB" | grep -o 'MUT-BASEFAIL:rec-path-late-drift')" "|MUT-BASEFAIL:rec-path-late-drift"
printf 'MUT b MISSED chk x\nRESULT MUTATIONS FAIL 18/19 missed=b known=none\n' > $RUN/gate-all/mutate.txt
kb_eval; ck "6 real missed mutation blocks" "$(echo "$GB" | grep -o 'mutation-missed')" "mutation-missed"
[ $F = 0 ] && echo "SELFTEST kfp-pipeline PASS" || { echo "SELFTEST kfp-pipeline FAIL"; exit 1; }
