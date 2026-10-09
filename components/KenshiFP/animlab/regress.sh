#!/bin/bash
# regress.sh -- phase-1 (REPLAY) regression of the animation lab; run in WSL before every animlab commit.
#   1. harness offline tests (tests/animlab, synthetic data)
#   2. faithfulness gate: vmq-f8c recordings (made with workspace commit 6c9516b) replayed through the 6c9516b solver:
#      sword-z0-a + crossbow-z0 must PASS (steady states; docs/animlab/USAGE.md "Faithfulness gate")
#   3. native round trip: replay crossbow-z0 with the CURRENT KenshiFP source + rec-native patch, replay that output
#      again from its recorded native pose: must reproduce itself exactly (grip/elbow p95 0.00, reload included)
# Recordings are copied (never modified) from C:\KenshiTestRuns\vmq-f8c into /root/animlab-work; nothing is committed.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
HARN=/mnt/c/KenshiModding/Kenshi-Automation-Harness; L=$HARN/tools/animlab
W=/root/animlab-work; BLD=/root/animlab-build; mkdir -p "$W" "$BLD"
fail=0; ok() { echo "REGRESS PASS $*"; }; bad() { echo "REGRESS FAIL $*"; fail=1; }
for f in sword-z0-a crossbow-z0; do
  [ -f "$W/vmrec-q-$f.txt" ] || cp "/mnt/c/KenshiTestRuns/vmq-f8c/vmrec-q-$f.txt" "$W/" 2>/dev/null || bad "missing recording vmrec-q-$f.txt"
done
python3 "$HARN/tests/animlab/test_animlab.py" >/tmp/al-unit.txt 2>&1 && ok unit-tests || { bad unit-tests; tail -5 /tmp/al-unit.txt; }
bash "$HERE/build.sh" --rev 6c9516b --out "$BLD/kfpvm_6c9516b" >/tmp/al-build1.txt 2>&1 || { bad build-6c9516b; tail -5 /tmp/al-build1.txt; }
(cd "$W" && python3 "$L/animlab.py" gate vmrec-q-sword-z0-a.txt vmrec-q-crossbow-z0.txt --adapter "$BLD/kfpvm_6c9516b" --args=--quiet --quiet) >/tmp/al-gate.txt 2>&1 \
  && ok "gate $(grep -o 'GATE PASS [^ ]* frames=[0-9]*' /tmp/al-gate.txt | tr '\n' ' ')" || { bad gate; grep GATE /tmp/al-gate.txt; }
mkdir -p /root/animlab-kfp-src && rsync -a --delete /root/KenshiFP/client/ /root/animlab-kfp-src/client/
P=(); grep -q vm_rec_native /root/animlab-kfp-src/client/kfp_viewmodel.inc || P=(--patch /mnt/c/KenshiModding/pending-fixes/kfp-rec-native-meta.py)
if [ ${#P[@]} -gt 0 ] && [ ! -f "${P[1]}" ]; then bad "rec-native patch script missing and source not patched"; P=(); fi
bash "$HERE/build.sh" "${P[@]}" --out "$BLD/kfpvm_cur" >/tmp/al-build2.txt 2>&1 || { bad build-current; tail -5 /tmp/al-build2.txt; }
"$BLD/kfpvm_cur" "$W/vmrec-q-crossbow-z0.txt" /tmp/al-rt1.txt --quiet >/dev/null
(python3 "$L/animlab.py" gate /tmp/al-rt1.txt --adapter "$BLD/kfpvm_cur" --args=--quiet) >/tmp/al-rt.txt 2>&1
if grep -q "GATE PASS" /tmp/al-rt.txt && grep -E "^reload\(info\)" /tmp/al-rt.txt | head -1 | awk '{exit !($4=="0.00" && $5=="0.00")}'; then ok "native round trip (reload exact)"; else bad "native round trip"; sed -n 1,6p /tmp/al-rt.txt; fi
[ $fail = 0 ] && echo "REGRESS ALL PASS" || echo "REGRESS FAILED"
exit $fail
