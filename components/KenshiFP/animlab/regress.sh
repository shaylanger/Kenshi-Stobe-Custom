#!/bin/bash
# regress.sh -- regression (phase 1 REPLAY, 2 METRICS, 3 VISUAL) of the animation lab; run in WSL before every animlab commit.
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
# ---- phase 2 (METRICS LAB): drive adapter (kfpvm_drive.c) + tools/animlab/metricslab.py ----
#   4. metricslab offline tests; 5. drive gate: the game's rendered weapon pose as the target on a still-body segment
#      must give the game's arm (crossbow-z0 345-1097 with its own source 6c9516b; sword-z0-a 83-232 with the current
#      source and with 6c9516b: the drive seeds the elbow branch from the recording, see STATUS.md); 6. dual-wield example PASS
python3 "$HARN/tests/animlab/test_metricslab.py" >/tmp/al-unit2.txt 2>&1 && ok metricslab-tests || { bad metricslab-tests; tail -5 /tmp/al-unit2.txt; }
bash "$HERE/build.sh" --rev 6c9516b --drive --out "$BLD/kfpvm_drive_6c9516b" >/tmp/al-build3.txt 2>&1 || { bad build-drive-6c9516b; tail -5 /tmp/al-build3.txt; }
bash "$HERE/build.sh" "${P[@]}" --drive --out "$BLD/kfpvm_drive_cur" >/tmp/al-build4.txt 2>&1 || { bad build-drive-current; tail -5 /tmp/al-build4.txt; }
for g in "6c9516b vmrec-q-crossbow-z0.txt 345 1097" "cur vmrec-q-sword-z0-a.txt 83 232" "6c9516b vmrec-q-sword-z0-a.txt 83 232"; do set -- $g
  r=$(cd "$W" && python3 "$L/metricslab.py" faithful "$2" "$3" "$4" --adapter "$BLD/kfpvm_drive_$1" --args=--quiet --out /tmp/al-faith 2>&1 | tail -1)
  case "$r" in "RESULT faithful-drive PASS"*) ok "$r";; *) bad "drive gate $1 $2: $r";; esac; done
r=$(cd "$W" && python3 "$L/metricslab.py" run "$HERE/motions/dualwield-alternate.json" --adapter "$BLD/kfpvm_drive_cur" --body vmrec-q-sword-z0-a.txt --body-frame 100 --out /tmp/al-dw --args=--quiet --quiet 2>&1 | tail -1)
case "$r" in "RESULT dualwield-alternate PASS"*) ok "$r";; *) bad "dual-wield example: $r";; esac
# ---- phase 3 (VISUAL LAB): harness tools/animlab/visual + visual.json ----
#   7. visual offline tests (synthetic Ogre binaries); 8. real game assets (skipped when the install is missing): the
#      dual-wield pose rendered with both katanas, posed hand X axes must match the solver's (< 1 deg, both sides)
python3 "$HARN/tests/animlab/test_visual.py" >/tmp/al-unit3.txt 2>&1 && ok visual-tests || { bad visual-tests; tail -5 /tmp/al-unit3.txt; }
GD=$(python3 -c "import json,os;c=json.load(open('$HERE/visual.json'));print(os.environ.get('ANIMLAB_GAME_DIR',c['game_dir']))")
if [ -d "$GD/data" ]; then
  r=$(python3 "$L/visual/render.py" still /tmp/al-dw/pose.txt --config "$HERE/visual.json" --weapons R,L --frame 30 --size 320x180 -o /tmp/al-vis.png 2>&1 | tail -1)
  if echo "$r" | python3 -c "import sys,re;e=[float(x) for x in re.findall(r\"'[LR]': ([0-9.]+)\",sys.stdin.read())];sys.exit(not(len(e)==2 and max(e)<1))"; then ok "visual dual-wield still: $r"; else bad "visual dual-wield still: $r"; fi
else echo "REGRESS SKIP visual game assets ($GD missing)"; fi
#   9. mirror check: the left weapon hand (adapter grip mirror + patches/left-hand-mirror.py) on a symmetric body must
#      reproduce the right hand exactly (motions/dualwield-sync-mirror.json, sword-z0 frame 541: wb per segment L == R)
bash "$HERE/build.sh" "${P[@]}" --patch "$HERE/patches/left-hand-mirror.py" --drive --out "$BLD/kfpvm_drive_lhm" >/tmp/al-build5.txt 2>&1 || { bad build-drive-lhm; tail -5 /tmp/al-build5.txt; }
[ -f "$W/vmrec-q-sword-z0.txt" ] || cp /mnt/c/KenshiTestRuns/vmq-f8c/vmrec-q-sword-z0.txt "$W/" 2>/dev/null
rm -rf /tmp/al-dwm; (cd "$W" && python3 "$L/metricslab.py" run "$HERE/motions/dualwield-sync-mirror.json" --adapter "$BLD/kfpvm_drive_lhm" --body vmrec-q-sword-z0.txt --body-frame 541 --out /tmp/al-dwm --args=--quiet --quiet >/dev/null 2>&1)
r=$(awk '/^[LR]:/ && !/\*all/ {s=substr($1,1,1); seg=substr($1,3); sub(/^[LR]-/,"",seg); v[s,seg]=$4; segs[seg]=1} END{n=0; d=0; for (g in segs) {n++; x=v["L",g]-v["R",g]; if (x<0) x=-x; if (x>d) d=x}; printf "segments=%d max_wb_diff=%.2f", n, d}' /tmp/al-dwm/report.txt 2>/dev/null)
case "$r" in *"max_wb_diff=0.0"[0-5]*) ok "mirror L==R $r";; *) bad "mirror L==R ${r:-no report}";; esac
#  10. miss "sword elbow branch drift": 6c9516b has no S2 re-seed, so its elbow branch is history-dependent; a cold drive
#      (--cold-elbow) must land on the other branch (elbow95 ~5 dm) = the lab reproduces the miss; seeded = PASS (step 5)
r=$(cd "$W" && python3 "$L/metricslab.py" faithful vmrec-q-sword-z0-a.txt 83 232 --adapter "$BLD/kfpvm_drive_6c9516b" "--args=--quiet --cold-elbow" --out /tmp/al-faith 2>&1 | tail -1)
case "$r" in "RESULT faithful-drive FAIL"*) ok "miss elbow-branch reproduced (cold @6c9516b): ${r#RESULT faithful-drive }";; *) bad "miss elbow-branch not reproduced: $r";; esac
#  11. miss E1 "edge leads the arc": metrics arc gate (stroke frames after the wind-up: edge_arc >= 0.7 on >= 85%, swing
#      wb_max <= 30). The game recording f14/e0 (back of the blade first) must FAIL; the current solver replaying it must
#      FAIL too while the source has no edge lead (g_vm_swlead). The pending E1 patch (+ patches/e1-lead-variants.py
#      defaults) is reported as INFO (2026-10-09: arc_ok 1.00 but wb_max 107 = the lead folds the wrist).
[ -f "$W/f14-e0.txt" ] || cp /mnt/c/KenshiTestRuns/f14/e0.txt "$W/f14-e0.txt" 2>/dev/null || bad "missing recording f14/e0.txt"
r=$(python3 "$L/animlab.py" metrics "$W/f14-e0.txt" | grep '^arc ')
case "$r" in "arc FAIL"*) ok "miss E1 reproduced (game f14-e0): $r";; *) bad "miss E1 game f14-e0 not failing: ${r:-no arc line}";; esac
"$BLD/kfpvm_cur" "$W/f14-e0.txt" /tmp/al-e1base.txt --quiet >/dev/null 2>&1
r=$(python3 "$L/animlab.py" metrics /tmp/al-e1base.txt | grep '^arc ')
if grep -q g_vm_swlead /root/animlab-kfp-src/client/kfp_viewmodel.inc; then echo "REGRESS INFO E1 current source (has swlead) replay f14-e0: $r"
else case "$r" in "arc FAIL"*) ok "miss E1 reproduced (replay f14-e0, current solver): $r";; *) bad "miss E1 replay not failing: ${r:-no arc line}";; esac
  E1P=/mnt/c/KenshiModding/pending-fixes/kfp-e1-swlead.py
  if [ -f "$E1P" ] && bash "$HERE/build.sh" "${P[@]}" --patch "$E1P" --patch "$HERE/patches/e1-lead-variants.py" --out "$BLD/kfpvm_e1v" >/tmp/al-build6.txt 2>&1; then
    "$BLD/kfpvm_e1v" "$W/f14-e0.txt" /tmp/al-e1v.txt --quiet >/dev/null 2>&1
    echo "REGRESS INFO E1 patch kfp-e1-swlead.py replay f14-e0: $(python3 "$L/animlab.py" metrics /tmp/al-e1v.txt | grep '^arc ')"
  else echo "REGRESS INFO E1 patch not built (missing or does not apply)"; fi
fi
[ $fail = 0 ] && echo "REGRESS ALL PASS" || echo "REGRESS FAILED"
exit $fail
