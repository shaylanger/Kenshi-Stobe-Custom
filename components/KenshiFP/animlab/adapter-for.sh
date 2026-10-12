#!/bin/bash
# adapter-for.sh <sha8 | rec.txt> [--drive]   (WSL root) print the path of the lab replay adapter built from EXACTLY the
# KenshiFP DLL <sha8> (or the `# src` build of a recording); builds + caches it on first use as
# /root/animlab-build/kfpvm_src-<sha8> (drive: kfpvm_dsrc-<sha8>) from the pipeline source snapshot
# (/root/kfp-pipeline/src/KenshiFP-<sha8>.client.tar.gz), at nice 15 through labnice.sh, and writes <adapter>.d/MATCHES.
# Why (polearm-fix 2026-10-11): a lab replay with an adapter older than the take build predicted the wrong framing
# (STATUS Misses: kfpvm_wc vs B17B98D5); every new staged build needed a hand-built adapter. Exit 2 = no snapshot/build failed.
set -e
HERE="$(cd "$(dirname "$0")" && pwd)"
a=$1; DR=; [ "${2:-}" = --drive ] && DR=1
if [ -f "$a" ]; then h=$(grep -m1 '^# src ' "$a" | awk '{print $NF}' | tr -d '\r'); else h=$a; fi
[ -n "$h" ] || { echo "adapter-for: no build id (no # src header in $a)" >&2; exit 2; }
B=/root/animlab-build/kfpvm_${DR:+d}src-$h
if [ ! -x "$B" ] || ! grep -qx "$h" "$B.d/MATCHES" 2>/dev/null; then
  d=/root/animlab-build/src-$h
  if [ ! -d "$d/client" ]; then
    t=/root/kfp-pipeline/src/KenshiFP-$h.client.tar.gz
    [ -f "$t" ] || { echo "adapter-for: no source snapshot $t" >&2; exit 2; }
    rm -rf "$d"; mkdir -p "$d"; tar xzf "$t" -C "$d"
  fi
  bash /mnt/c/KenshiModding/tools/automation/labnice.sh bash "$HERE/build.sh" --src "$d/client" ${DR:+--drive} --out "$B" \
    < /dev/null > /tmp/adapter-for-$h.txt 2>&1 || { echo "adapter-for: build failed /tmp/adapter-for-$h.txt" >&2; exit 2; }
  echo "$h" > "$B.d/MATCHES"
fi
echo "$B"
