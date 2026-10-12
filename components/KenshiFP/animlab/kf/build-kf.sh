#!/bin/bash
# build-kf.sh [tag]: keyframe-player lab binaries (WSL root): the replay adapter and the path sampler (kfpvm_kfpath.c)
# on /root/KenshiFP + the sword patches of the staged line + pending-fixes/kfp-keyframe-stroke.py.
#   /root/animlab-build/kfpvm_kf<tag>      replay adapter (kfpvm_replay: --tables / --set, pool replays)
#   /root/animlab-build/kfpvm_kfpath<tag>  stroke path sampler (commanded pose, no IK)
# Runs under nice 15 (labnice rule); build cache (labcache) makes unchanged rebuilds instant.
set -e
T="${1:-}"; P=/mnt/c/KenshiModding/pending-fixes; A=/mnt/c/KenshiModding/components/KenshiFP/animlab
PL=(); for p in kfp-2h-light kfp-e6-default-mask kfp-pt30-followthrough kfp-s1-edge-swing kfp-stroke-line kfp-stroke-recedge kfp-keyframe-stroke; do
  [ -f "$P/$p.py" ] && PL+=(--patch "$P/$p.py"); done
nice -n 15 bash "$A/build.sh" --sync "${PL[@]}" --out "/root/animlab-build/kfpvm_kf$T" | tail -1
nice -n 15 bash "$A/build.sh" --main kfpvm_kfpath.c "${PL[@]}" --out "/root/animlab-build/kfpvm_kfpath$T" | tail -1
