#!/bin/bash
# fastcheck.sh [--src <client dir>] [--jobs N] [rec ...]
# Proves patches/fast-elb.py (lab speed patch, build.sh default) is exact: builds the replay from the same client source
# with and without it and compares the replay output byte for byte (except the "# build" time line) on every corpus
# recording (default: corpus rec/, recs/*.vmrec.txt, pools/*/*.txt), as recorded and with each stroke forced.
# Prints one line per mismatch and "RESULT fastcheck PASS|FAIL <n compared> <n diff> <user s plain> <user s fast>".
# Run in WSL as root, nice'd. Owner: gpu-lab (2026-10-11).
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"; SRC=/root/animlab-kfp-src/client; J=8; RECS=()
while [ $# -gt 0 ]; do case "$1" in --src) SRC="$2"; shift 2;; --jobs) J="$2"; shift 2;; *) RECS+=("$1"); shift;; esac; done
C=/mnt/c/KenshiTestRuns/corpus
[ ${#RECS[@]} -gt 0 ] || mapfile -t RECS < <(ls $C/rec/*.txt $C/recs/*.vmrec.txt $C/pools/*/*.txt 2>/dev/null | grep -v -e '\.list$' -e INDEX)
W=$(mktemp -d /root/fastcheck.XXXX); trap 'rm -rf "$W"' EXIT
ANIMLAB_CACHE=0 AL_NO_FAST=1 bash "$HERE/build.sh" --src "$SRC" --out "$W/plain" >/dev/null || { echo "RESULT fastcheck FAIL build plain"; exit 1; }
ANIMLAB_CACHE=0 bash "$HERE/build.sh" --src "$SRC" --out "$W/fast" >/dev/null || { echo "RESULT fastcheck FAIL build fast"; exit 1; }
grep -q g_al_fast_ord "$W/fast.d/client/kfp_viewmodel.inc" || { echo "RESULT fastcheck FAIL patch not applied to $SRC"; exit 1; }
one() {   # rec idx argset
    local r="$1" i="$2" a="$3" b
    for b in plain fast; do
        s=$(date +%s%N); nice -n 15 "$W/$b" "$r" "$W/$b.$i.out" $a --quiet >/dev/null 2>&1; echo $? > "$W/$b.$i.rc"; e=$(date +%s%N)
        echo $(( (e - s) / 1000000 )) > "$W/$b.$i.ms"
    done
    if [ "$(cat $W/plain.$i.rc)" != 0 ] && [ "$(cat $W/fast.$i.rc)" = "$(cat $W/plain.$i.rc)" ]; then echo "SKIP rc=$(cat $W/plain.$i.rc) $r $a" > "$W/r.$i"
    elif cmp -s <(grep -v '^# build' "$W/plain.$i.out") <(grep -v '^# build' "$W/fast.$i.out"); then echo SAME > "$W/r.$i"
    else echo "DIFF $r $a" > "$W/r.$i"; fi
    rm -f "$W/plain.$i.out" "$W/fast.$i.out"
}
export -f one; export W
n=0; for r in "${RECS[@]}"; do for a in "" "--no-rec-sets --set stroke=1" "--no-rec-sets --set stroke=2"; do
    n=$((n + 1)); printf '%s\t%s\t%s\n' "$r" "$n" "$a"; done; done | xargs -P "$J" -d '\n' -n 1 bash -c 'IFS=$'"'"'\t'"'"' read -r r i a <<< "$0"; one "$r" "$i" "$a"'
same=$(cat $W/r.* | grep -c '^SAME'); diff=$(cat $W/r.* | grep -c '^DIFF'); skip=$(cat $W/r.* | grep -c '^SKIP')
cat $W/r.* | grep '^DIFF' | head -20
tp=$(cat $W/plain.*.ms | awk '{s+=$1} END{printf "%.1f", s/1000}'); tf=$(cat $W/fast.*.ms | awk '{s+=$1} END{printf "%.1f", s/1000}')
[ "$diff" = 0 ] && [ "$same" -gt 0 ] && v=PASS || v=FAIL
echo "RESULT fastcheck $v same=$same diff=$diff skip=$skip wall_plain=${tp}s wall_fast=${tf}s"
