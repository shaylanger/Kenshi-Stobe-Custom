#!/bin/bash
# zoomret-take.sh <take.vmrec.txt> [--set k=v]...   (WSL; lab-rules 2026-10-11)
#   zoomret-check.py for a GAME take: replays the take with the exact source of the DLL that recorded it (its
#   `# src <rev> <DLL sha8>` header -> KenshiFP-<sha8>.client.tar.gz in the corpus src/ or /root/kfp-pipeline/src/, like
#   agree-pose.sh; adapter cached as /root/animlab-build/kfpvm_src-<sha8>) and compares the whole replay with a fresh start at
#   every zoom return (class "carried solver state", Misses 139-wc-clv). Prints ONE line:
#     zoomret=PASS|FAIL|n/a(<why>) <detail>
#   Exit 0 PASS / n/a, 1 FAIL. Used by fp-weapon-sweep.sh's take analysis; run under labnice / nice.
R=$1; shift
C=${ANIMLAB_CORPUS:-/mnt/c/KenshiTestRuns/corpus}; HERE=$(cd "$(dirname "$0")" && pwd)
[ -s "$R" ] || { echo "zoomret=n/a(no rec)"; exit 0; }
grep -q -m1 . <(awk '!/^#/ && NF {z=$17+0; if (z >= 8) hi=1; else if (hi && z < 1) {print "ret"; exit}}' "$R") \
  || { echo "zoomret=n/a(no zoom return)"; exit 0; }
h=$(grep -m1 '^# src ' "$R" | awk '{print $NF}' | tr -d '\r')
[ -n "$h" ] || { echo "zoomret=n/a(no # src header)"; exit 0; }
B=/root/animlab-build/kfpvm_src-$h
if [ ! -x "$B" ]; then
  d=/root/animlab-build/src-$h
  if [ ! -d "$d/client" ]; then
    for t in "$C/src/KenshiFP-$h.client.tar.gz" "/root/kfp-pipeline/src/KenshiFP-$h.client.tar.gz"; do
      [ -f "$t" ] && { rm -rf "$d"; mkdir -p "$d"; tar xzf "$t" -C "$d"; break; }; done
  fi
  [ -d "$d/client" ] || { echo "zoomret=n/a(no source snapshot for DLL $h)"; exit 0; }
  nice -n 15 bash "$HERE/build.sh" --src "$d/client" --out "$B" < /dev/null > /tmp/zoomret-build-$h.txt 2>&1
  [ -x "$B" ] || { echo "zoomret=n/a(adapter build failed: /tmp/zoomret-build-$h.txt)"; exit 0; }
fi
out=$(nice -n 15 python3 "$HERE/zoomret-check.py" "$R" --adapter "$B" "$@" --row ZR 2>&1)
v=$(echo "$out" | awk '/^RESULT ZR /{print $3}'); d=$(echo "$out" | awk '/^RESULT ZR /{$1=$2=$3=""; print substr($0,4)}')
case "$v" in PASS) echo "zoomret=PASS $d (src $h)"; exit 0;; FAIL) echo "zoomret=FAIL $d (src $h) $(echo "$out" | grep -m1 ' BAD ' | cut -c1-120)"; exit 1;;
  *) echo "zoomret=n/a(check error: $(echo "$out" | tail -1 | cut -c1-100))"; exit 0;; esac
