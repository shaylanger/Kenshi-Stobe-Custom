#!/bin/bash
# build.sh [--preprocess] [--sync] [--src <client dir> | --rev <KenshiModding git rev (components/KenshiFP/client snapshot)>] [--patch <file.patch|file.py>]... [--out <binary>] [--drive]
# Builds the offline KenshiFP viewmodel replay (kfpvm_replay) in WSL against a COPY of the KenshiFP client source.
#   --l1     the game L1 model in a --drive build too (fist candidates: the fists sit near full reach, where the game
#            over-reaches its targets by ~0.6 dm; native.py fists --adapter <this build>)
#   --no-hoff leave out the game weapon-hand offset model (patches/hand-offset.py, hand-frame target offset $AL_HOFF or
#            0.19,0.02,-0.10 dm; default ON for the replay, off for --drive unless --l1)
#   --no-l1  leave out the game L1 model (patches/l1-scale.py, l1k 0.871 = the game's short cached upper arm; default ON for the replay, off for --drive)
#   --no-fast leave out patches/fast-elb.py (exact speed patch of the elbow search, default ON; AL_NO_FAST=1 too)
#   --main   build another main in this dir (kfpvm_fist.c, fist-equiv.sh)
#   --drive  build the phase-2 drive adapter (kfpvm_drive.c: authored targets, metricslab.py) instead of the replay
#   --sync   refresh the copy /root/animlab-kfp-src/client from /root/KenshiFP/client first (read-only use)
#   --patch  apply a variant to a private copy before compiling (.patch = patch -p1 from the client dir's parent,
#            .py = python3 script called with the client dir); variants never touch the base copy
set -e
HERE="$(cd "$(dirname "$0")" && pwd)"
SRC=/root/animlab-kfp-src/client; OUT=/root/animlab-build/kfpvm_replay; PATCHES=(); MAIN=kfpvm_replay.c
while [ $# -gt 0 ]; do case "$1" in
  --drive) MAIN=kfpvm_drive.c; shift;;
  --main) MAIN="$2"; shift 2;;   # another harness main in this dir (kfpvm_fist.c: fist-equiv.sh)
  --no-l1) NOL1=1; shift;;
  --no-hoff) NOHOFF=1; shift;;
  --no-fast) NOFAST=1; shift;;
  --built) BUILT="$2"; shift 2;;   # gpu-lab: reuse an existing <adapter>.d build dir (patched client + gen_helpers.h) as is: no copy, no patches (GPU build of the exact source of a CPU adapter)
  --preprocess) PREP=1; shift;;   # gpu-lab: write <out>.i (gcc -E, same flags/defs) instead of compiling (gpu/gpugen.py input)   # leave out patches/fast-elb.py (exact lab speed patch; also AL_NO_FAST=1)
  --l1) L1=1; shift;;   # the game L1 model in a --drive build too (fist candidates: native.py fists --adapter; FIST-shoteiL op-b6)
  --sync) mkdir -p /root/animlab-kfp-src && rsync -a --delete /root/KenshiFP/client/ /root/animlab-kfp-src/client/; shift;;
  --src) SRC="$2"; shift 2;;
  --rev) R_=/root/animlab-build/rev-$2; rm -rf "$R_"; mkdir -p "$R_"; git -C /mnt/c/KenshiModding archive "$2" components/KenshiFP/client | tar -x -C "$R_"; SRC="$R_/components/KenshiFP/client"; shift 2;; --out) OUT="$2"; shift 2;; --patch) PATCHES+=("$2"); shift 2;;
  *) echo "build.sh: unknown arg $1" >&2; exit 2;; esac; done
if [ -n "$BUILT" ]; then B="$BUILT"; [ -f "$B/gen_helpers.h" ] && [ -d "$B/client" ] || { echo "build.sh: --built $B is not an adapter build dir" >&2; exit 2; }
else
B="$(dirname "$OUT")/$(basename "$OUT").d"; rm -rf "$B"; mkdir -p "$B"; cp -r "$SRC" "$B/client"
for p in "${PATCHES[@]}"; do case "$p" in
  *.py) python3 "$p" "$B/client" ;;
  *) (cd "$B" && patch -s -p1 < "$p") ;; esac; done
[ -n "$NOL1" ] || { [ "$MAIN" = kfpvm_drive.c ] && [ -z "$L1" ]; } || python3 "$HERE/patches/l1-scale.py" "$B/client"
[ -n "$NOHOFF" ] || { [ "$MAIN" = kfpvm_drive.c ] && [ -z "$L1" ]; } || python3 "$HERE/patches/hand-offset.py" "$B/client"
# lab speed (gpu-lab 2026-10-11): exact branch-and-bound + hoisted trig in the elbow search, bit-identical output (fastcheck.sh), ~1.5x
[ -n "$NOFAST" ] || [ -n "${AL_NO_FAST:-}" ] || python3 "$HERE/patches/fast-elb.py" "$B/client"
python3 "$HERE/extract_helpers.py" "$B/client/kenshifp_client.c" "$B/gen_helpers.h" quat_mul quat_conj quat_norm quat_slerp quat_rotvec
fi
DEFS=""; grep -q "g_vm_elb_cb" "$B/client/kfp_viewmodel.inc" && DEFS="$DEFS -DAL_HAVE_ELB_CB"
grep -q "g_vm_eclamp_n" "$B/client/kfp_viewmodel.inc" && DEFS="$DEFS -DAL_HAVE_ECLAMP"
grep -q "g_vm_hcap_n" "$B/client/kfp_viewmodel.inc" && DEFS="$DEFS -DAL_HAVE_HINGE"
grep -q "g_vm_2htau" "$B/client/kfp_viewmodel.inc" && DEFS="$DEFS -DAL_HAVE_2H"   # warm start snaps the 2H blend (lab-calibrate)
grep -q "g_vm_2hbw" "$B/client/kfp_viewmodel.inc" && DEFS="$DEFS -DAL_HAVE_2HB"
grep -q "vm_pd_write" "$B/client/kfp_viewmodel.inc" && DEFS="$DEFS -DAL_HAVE_POSEDUMP"
grep -q "g_al_hoff" "$B/client/kfp_viewmodel.inc" && DEFS="$DEFS -DAL_HAVE_HOFF"   # recorded hand scale replaces it (lab-calibrate2)
grep -q "g_al_l1n_rec" "$B/client/kfp_viewmodel.inc" && DEFS="$DEFS -DAL_HAVE_L1REC"   # recorded solver upper-arm length (lab-calibrate2)   # kfp-posedump: kfpvm_replay --posedump
if [ -n "$PREP" ]; then gcc -E -std=gnu11 $DEFS '-DAL_LOOP_HOOK(n)=al_gpu_loop(n)' -I"$B" -I"$B/client" -I"$HERE" -o "$OUT.i" "$HERE/$MAIN"; echo "preprocessed $OUT.i defs:$DEFS"; exit 0; fi
# build cache (labcache.py, Shay 2026-10-10 CPU cut): key = content of every compile input (patched client copy +
# generated helpers, the harness mains/headers here, -D flags, gcc version), not paths: the same source built under
# another name or in another pipeline tree restores the same binary, so its replays hit the result cache too.
LC=/mnt/c/KenshiModding/Kenshi-Automation-Harness/tools/animlab/labcache.py
if [ -f "$LC" ] && [ "${ANIMLAB_CACHE:-1}" != 0 ]; then
  { (cd "$B" && find . -type f -print0 | LC_ALL=C sort -z | xargs -0 sha256sum); (cd "$HERE" && sha256sum ./*.c ./*.h); echo "main=$MAIN defs=$DEFS"; gcc --version | head -1; } > "$B.inputs"
  python3 "$LC" run --nocmd --tag "build-gcc" --in "$B.inputs" --out "$OUT" -- gcc -O2 -std=gnu11 -w $DEFS -I"$B" -I"$B/client" -I"$HERE" -o "$OUT" "$HERE/$MAIN" -lm
  rm -f "$B.inputs"; [ -x "$OUT" ] || chmod +x "$OUT" 2>/dev/null
else gcc -O2 -std=gnu11 -w $DEFS -I"$B" -I"$B/client" -I"$HERE" -o "$OUT" "$HERE/$MAIN" -lm; fi
echo "built $OUT"
