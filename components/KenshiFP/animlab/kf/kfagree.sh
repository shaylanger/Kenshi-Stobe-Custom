#!/bin/bash
# kfagree.sh <game rec>... [-- agree-pose args]: does the lab replay of a FILMED keyframe stroke match the game? (kf-lab 2026-10-11)
# One source: the lab adapter compiles the plugin's own kfp_viewmodel.inc incl. kfp-keyframe-stroke.py, so the keyframe
# interpolation is the same C code in both; this checks it end to end on a game take. Each recording must be a kf take
# (`# set -1 vm.kfmask`/`t.kf.` lines from the plugin; else FAIL "not a keyframe take"); it is then replayed by a lab built
# from the EXACT source of the DLL that recorded it (agree-pose.sh: `# src` header -> kfp-pipeline source snapshot) and
# every arm joint / hand axis is compared with what the game measured.
# Recs: absolute paths or relative to the corpus (/mnt/c/KenshiTestRuns/corpus). Keep a passing take with
# `corpus.sh add` + a line in corpus/agree/pose.list so every later build re-checks it.
# Prints `RESULT KFAGREE PASS|FAIL n=.. fail=..` (WSL root).
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"; C=${ANIMLAB_CORPUS:-/mnt/c/KenshiTestRuns/corpus}
L=$(mktemp /tmp/kfagree-XXXX.list); nf=0; n=0
for r in "$@"; do
  [ "$r" = -- ] && break
  R=$r; case "$r" in /*) ;; *) R=$C/$r;; esac
  n=$((n + 1))
  if ! grep -q -E '^# set .*(kfmask|t\.kf\.)' "$R" 2>/dev/null; then echo "KFAGREE FAIL $(basename "$r"): not a keyframe take (no kfmask / t.kf set lines)"; nf=$((nf + 1)); continue; fi
  echo "$(realpath --relative-to="$C" "$R")" >> "$L"
done
[ -s "$L" ] && { nice -n 15 bash "$HERE/../agree-pose.sh" --list "$L" --out /root/animlab-work/kfagree | tee /tmp/kfagree.out | grep '^AGREE-POSE'; \
  nf=$((nf + $(grep -c '^AGREE-POSE FAIL' /tmp/kfagree.out))); }
rm -f "$L"
[ $nf = 0 ] && [ $n -gt 0 ] && V=PASS || V=FAIL
echo "RESULT KFAGREE $V n=$n fail=$nf"; [ $V = PASS ]
