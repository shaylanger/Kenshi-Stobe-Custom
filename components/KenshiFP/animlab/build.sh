#!/bin/bash
# build.sh [--sync] [--src <client dir> | --rev <KenshiModding git rev (components/KenshiFP/client snapshot)>] [--patch <file.patch|file.py>]... [--out <binary>]
# Builds the offline KenshiFP viewmodel replay (kfpvm_replay) in WSL against a COPY of the KenshiFP client source.
#   --sync   refresh the copy /root/animlab-kfp-src/client from /root/KenshiFP/client first (read-only use)
#   --patch  apply a variant to a private copy before compiling (.patch = patch -p1 from the client dir's parent,
#            .py = python3 script called with the client dir); variants never touch the base copy
set -e
HERE="$(cd "$(dirname "$0")" && pwd)"
SRC=/root/animlab-kfp-src/client; OUT=/root/animlab-build/kfpvm_replay; PATCHES=()
while [ $# -gt 0 ]; do case "$1" in
  --sync) mkdir -p /root/animlab-kfp-src && rsync -a --delete /root/KenshiFP/client/ /root/animlab-kfp-src/client/; shift;;
  --src) SRC="$2"; shift 2;;
  --rev) R_=/root/animlab-build/rev-$2; rm -rf "$R_"; mkdir -p "$R_"; git -C /mnt/c/KenshiModding archive "$2" components/KenshiFP/client | tar -x -C "$R_"; SRC="$R_/components/KenshiFP/client"; shift 2;; --out) OUT="$2"; shift 2;; --patch) PATCHES+=("$2"); shift 2;;
  *) echo "build.sh: unknown arg $1" >&2; exit 2;; esac; done
B="$(dirname "$OUT")/$(basename "$OUT").d"; rm -rf "$B"; mkdir -p "$B"; cp -r "$SRC" "$B/client"
for p in "${PATCHES[@]}"; do case "$p" in
  *.py) python3 "$p" "$B/client" ;;
  *) (cd "$B" && patch -s -p1 < "$p") ;; esac; done
python3 "$HERE/extract_helpers.py" "$B/client/kenshifp_client.c" "$B/gen_helpers.h" quat_mul quat_conj quat_norm quat_slerp quat_rotvec
DEFS=""; grep -q "g_vm_elb_cb" "$B/client/kfp_viewmodel.inc" && DEFS="$DEFS -DAL_HAVE_ELB_CB"
gcc -O2 -std=gnu11 -w $DEFS -I"$B" -I"$B/client" -I"$HERE" -o "$OUT" "$HERE/kfpvm_replay.c" -lm
echo "built $OUT"
