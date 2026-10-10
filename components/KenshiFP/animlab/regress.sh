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
#      wb_max <= 50, default since 2026-10-09). The game recording f14/e0 (back of the blade first) must FAIL; the current solver replaying it must
#      FAIL too while the source has no edge lead (g_vm_swlead). The pending E1 patch (+ patches/e1-lead-variants.py
#      defaults) is reported as INFO (2026-10-09: arc_ok 1.00 but wb_max 107 = the lead folds the wrist); the E1 candidate
#      pending-fixes/kfp-e1-keys.py must PASS with wb_max <= 50.
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
  # E1 candidate (lab hill climb, 2026-10-09): swlead + rollcap + re-authored strike keys must pass the arc gate with the
  # wrist no worse than the current swing (wb_max <= 50) on e0 and on f13/sw0 (not used by the climb)
  E1K=/mnt/c/KenshiModding/pending-fixes/kfp-e1-keys.py
  if [ -f "$E1K" ] && bash "$HERE/build.sh" "${P[@]}" --patch "$E1K" --out "$BLD/kfpvm_e1k" >/tmp/al-build7.txt 2>&1; then
    [ -f "$W/f13-sw0.txt" ] || cp /mnt/c/KenshiTestRuns/f13/sw0.txt "$W/f13-sw0.txt" 2>/dev/null
    for r in f14-e0 f13-sw0; do "$BLD/kfpvm_e1k" "$W/$r.txt" /tmp/al-e1k.txt --quiet >/dev/null 2>&1
      r2=$(python3 "$L/animlab.py" metrics /tmp/al-e1k.txt | grep '^arc ')
      case "$r2" in "arc PASS"*) ok "E1 candidate kfp-e1-keys.py on $r: $r2";; *) bad "E1 candidate kfp-e1-keys.py on $r: ${r2:-no arc line}";; esac; done
  else echo "REGRESS INFO E1 candidate kfp-e1-keys.py not built (missing or does not apply)"; fi
fi
#  11b. E1 wb36 accepted (Shay 2026-10-09): the game recording of the approved swing (KenshiFP 9E5422A6, f23 anim-sword-z0:
#      4 swings incl. the first after a draw, wb_max 36) must PASS the arc gate at the default wrist limit (50).
[ -f "$W/f23-sword-z0d.txt" ] || cp /mnt/c/KenshiTestRuns/vid/vmrec-anim-f23-sword-z0d.txt "$W/f23-sword-z0d.txt" 2>/dev/null || bad "missing recording vid/vmrec-anim-f23-sword-z0d.txt"
r=$(python3 "$L/animlab.py" metrics "$W/f23-sword-z0d.txt" | grep '^arc ')
case "$r" in "arc PASS"*) ok "E1 wb36 game f23-sword-z0d: $r";; *) bad "E1 wb36 game f23-sword-z0d: ${r:-no arc line}";; esac
#  12. miss X1 "crossbow jitter / jitter under-reported": `animlab.py compare` jitter line (game jit_p95 > 1 px may be at
#      most 2.5x the replay's, swings skipped). vmq-f8c crossbow-z0 (pre-e948f86 bone-world map) replayed by its own
#      solver 6c9516b must FAIL (ready x4.2, reload x6.6); f14/xb0 (node map) replayed by d40b6ad (first node-map snapshot)
#      must PASS (pinned: the live source's replay jitter moves, 2026-10-09 it dropped to 0.59 = x2.8).
r=$(cd "$W" && "$BLD/kfpvm_6c9516b" vmrec-q-crossbow-z0.txt /tmp/al-x1a.txt --quiet >/dev/null 2>&1; python3 "$L/animlab.py" compare vmrec-q-crossbow-z0.txt /tmp/al-x1a.txt | grep '^jitter ')
case "$r" in "jitter FAIL"*) ok "miss X1 reproduced (crossbow-z0 @6c9516b): $r";; *) bad "miss X1 not reproduced: ${r:-no jitter line}";; esac
[ -f "$W/f14-xb0.txt" ] || cp /mnt/c/KenshiTestRuns/f14/xb0.txt "$W/f14-xb0.txt" 2>/dev/null || bad "missing recording f14/xb0.txt"
bash "$HERE/build.sh" --rev d40b6ad --out "$BLD/kfpvm_d40b6ad" >/tmp/al-build8.txt 2>&1 || bad build-d40b6ad
r=$("$BLD/kfpvm_d40b6ad" "$W/f14-xb0.txt" /tmp/al-x1b.txt --quiet >/dev/null 2>&1; python3 "$L/animlab.py" compare "$W/f14-xb0.txt" /tmp/al-x1b.txt | grep '^jitter ')
case "$r" in "jitter PASS"*) ok "X1 fixed build (f14-xb0, node-map solver d40b6ad): $r";; *) bad "X1 jitter on f14-xb0: ${r:-no jitter line}";; esac
#  13. miss C3 "bolt jitter on walk": `animlab.py bolt` (game recording + its <rec>.bolt sidecar: the bolt node in the
#      post-IK Prop2 frame (column group 5 "sl", builds with the C3 pin code) must stay within 0.1 dm of its median,
#      per-frame step <= 0.05 dm; group 1 "bl" uses mp, measured at another time: false drift, only a fallback).
#      f16/r0 (pin off) must FAIL, f16/r1 (pin on, KenshiFP F8041381) must PASS.
for f in r0.txt r0.txt.bolt r1.txt r1.txt.bolt; do [ -f "$W/f16-$f" ] || cp "/mnt/c/KenshiTestRuns/f16/$f" "$W/f16-$f" 2>/dev/null || bad "missing recording f16/$f"; done
r=$(python3 "$L/animlab.py" bolt "$W/f16-r0.txt")
case "$r" in "bolt FAIL ready:"*src=sl) ok "miss C3 reproduced (f16-r0, pin off): $r";; *) bad "miss C3 not reproduced: ${r:-no bolt line}";; esac
r=$(python3 "$L/animlab.py" bolt "$W/f16-r1.txt")
case "$r" in "bolt PASS ready:"*src=sl) ok "C3 fixed (f16-r1, pin on): $r";; *) bad "C3 pin on f16-r1: ${r:-no bolt line}";; esac
#  14. miss C1 "aim pose did not play" (combat layer read real keys only; fixed by the fp_combat input path): `animlab.py
#      metrics` moves line. f14/xb0 (pre-fix, game st never 'aim') must FAIL aim:MISSING; vmq-125c crossbow-z0 (build
#      Oct 9 19:32:36, post-fix) must PASS.
[ -f "$W/vmq125c-crossbow-z0.txt" ] || cp /mnt/c/KenshiTestRuns/vmq-125c/vmrec-q-crossbow-z0.txt "$W/vmq125c-crossbow-z0.txt" 2>/dev/null || bad "missing recording vmq-125c/vmrec-q-crossbow-z0.txt"
r=$(python3 "$L/animlab.py" metrics "$W/f14-xb0.txt" | grep '^moves ')
case "$r" in "moves FAIL aim:MISSING"*) ok "miss C1 reproduced (f14-xb0): $r";; *) bad "miss C1 not reproduced: ${r:-no moves line}";; esac
r=$(python3 "$L/animlab.py" metrics "$W/vmq125c-crossbow-z0.txt" | grep '^moves ')
case "$r" in "moves PASS"*aim:*) ok "C1 fixed build (vmq-125c crossbow-z0): $r";; *) bad "C1 fixed build moves: ${r:-no moves line}";; esac
#  15. miss C2 "crossbow stock too high" + "C2 fix rotated the crossbow" (Shay): `animlab.py stock` (stock top line
#      mp - k*mf + 1.45*mu, highest visible point p95 <= 25% of the screen from the bottom in ready; --ref: ready forward/up
#      within 3 deg of f14/xb0, the d40b6ad-era pose). f16/c2a (build 18:21, 67%) FAILs the height, f16/c2c (18:21,
#      rotated 24.5 deg) FAILs the orientation, vmq-125c crossbow-z0 (19:32) PASSes both.
for f in c2a.txt c2c.txt; do [ -f "$W/f16-$f" ] || cp "/mnt/c/KenshiTestRuns/f16/$f" "$W/f16-$f" 2>/dev/null || bad "missing recording f16/$f"; done
r=$(python3 "$L/animlab.py" stock "$W/f16-c2a.txt" --ref "$W/f14-xb0.txt")
case "$r" in "stock FAIL ready:"*":BAD ori:"*) ok "miss C2 height reproduced (f16-c2a): $r";; *) bad "miss C2 height not reproduced: ${r:-no stock line}";; esac
r=$(python3 "$L/animlab.py" stock "$W/f16-c2c.txt" --ref "$W/f14-xb0.txt")
case "$r" in "stock FAIL"*"ori:"*":BAD") ok "miss C2 rotation reproduced (f16-c2c): $r";; *) bad "miss C2 rotation not reproduced: ${r:-no stock line}";; esac
r=$(python3 "$L/animlab.py" stock "$W/vmq125c-crossbow-z0.txt" --ref "$W/f14-xb0.txt")
case "$r" in "stock PASS"*ori:*) ok "C2 fixed build (vmq-125c crossbow-z0): $r";; *) bad "C2 fixed build stock: ${r:-no stock line}";; esac
#  16. miss "sword elbow drift on long drives": faithful-drive with the RENDERED pose as the target (default) drifts to the
#      other elbow branch at the end of every swing (the rendered swing tail differs from what the game's solver was
#      commanded) and never comes back: sword-z0 0-520 @6c9516b seeded FAIL elbow95 ~5.2. Driving the COMMANDED pose
#      (--commanded, what the game solver got) tracks the game through the swings: PASS. Long replays do not drift.
r=$(cd "$W" && python3 "$L/metricslab.py" faithful vmrec-q-sword-z0.txt 0 520 --adapter "$BLD/kfpvm_drive_6c9516b" --args=--quiet --out /tmp/al-faith 2>&1 | tail -1)
case "$r" in *"faithful-drive FAIL"*) ok "miss elbow drift reproduced (rendered targets): $r";; *) bad "miss elbow drift not reproduced: $r";; esac
r=$(cd "$W" && python3 "$L/metricslab.py" faithful vmrec-q-sword-z0.txt 0 520 --commanded --adapter "$BLD/kfpvm_drive_6c9516b" --args=--quiet --out /tmp/al-faith 2>&1 | tail -1)
case "$r" in *"faithful-drive PASS"*) ok "elbow drift fixed (commanded targets): $r";; *) bad "elbow drift with commanded targets: $r";; esac
#  17. miss E1 "arm churn + hand roll in the wind-up" (Shay rejected the kfp-e1-keys candidate video): `animlab.py churn`
#      (rev = visible forearm end out-and-back px within 0.4 s with the grip within 250 px, gate 450; windup_roll = hand
#      roll about the forearm from the first swing frame to u 0.28, gate 15 deg). Game vmq-f8c sword-z0 must PASS
#      (rev ~98, roll ~10); the candidate kfp-e1-keys.py replaying f14-e0 must FAIL both (rev ~556, roll ~159).
r=$(python3 "$L/animlab.py" churn "$W/vmrec-q-sword-z0.txt")
case "$r" in "churn PASS"*) ok "churn game vmq-f8c sword-z0: $r";; *) bad "churn game vmq-f8c sword-z0: ${r:-no churn line}";; esac
if [ -x "$BLD/kfpvm_e1k" ] && [ -f /mnt/c/KenshiModding/pending-fixes/kfp-e1-keys.py ]; then
  "$BLD/kfpvm_e1k" "$W/f14-e0.txt" /tmp/al-e1kc.txt --quiet >/dev/null 2>&1
  r=$(python3 "$L/animlab.py" churn /tmp/al-e1kc.txt)
  case "$r" in "churn FAIL rev="*":BAD@"*"windup_roll="*":BAD"*) ok "miss E1 churn reproduced (kfp-e1-keys candidate, f14-e0): $r";; *) bad "miss E1 churn not reproduced: ${r:-no churn line}";; esac
else echo "REGRESS INFO E1 churn: candidate kfp-e1-keys.py not built"; fi
#  18. miss E1 "blade ~90 deg to the forearm, wrist-driven" (Shay 2026-10-09, reference photos e1*.png vs Chivalry):
#      `animlab.py inline` (wind-up + stroke: forearm-blade angle median <= 30, max <= 40 deg, on screen max <= 40; stroke
#      wrist share of the tip motion <= 0.6). The game recordings f14/e0 and f13/sw0 and the current solver replaying e0
#      must FAIL (stroke ~50/62 deg, wrist share ~0.9-1.0).
for r in f14-e0 f13-sw0; do r2=$(python3 "$L/animlab.py" inline "$W/$r.txt")
  case "$r2" in "inline FAIL"*"stroke:"*":BAD"*) ok "miss E1 inline reproduced (game $r): ${r2%% follow:*}";; *) bad "miss E1 inline game $r not failing: ${r2:-no inline line}";; esac; done
r2=$(python3 "$L/animlab.py" inline /tmp/al-e1base.txt)
if grep -q g_vm_swlead /root/animlab-kfp-src/client/kfp_viewmodel.inc; then   # E1 merged (c6a1eda wb36): the current solver must PASS
  case "$r2" in "inline PASS"*) ok "E1 inline fixed in the current solver (replay f14-e0): ${r2%% follow:*}";; *) bad "E1 inline current replay: ${r2:-no inline line}";; esac
else case "$r2" in "inline FAIL"*"stroke:"*":BAD"*) ok "miss E1 inline reproduced (replay f14-e0, current solver): ${r2%% follow:*}";; *) bad "miss E1 inline current replay not failing: ${r2:-no inline line}";; esac; fi
#      E1 inline candidate pending-fixes/kfp-e1-inline.py (al10 hill climb) must PASS inline + arc (stroke, wb <= 50) +
#      churn --stroke on f14-e0 and vmq-85a7 sword-z0; f13-sw0 = INFO (its first swing starts from the replay-only ready
#      branch B after the draw: no wind-up roll allowed, so the edge cannot line up; STATUS "E1 INLINE STATE").
E1I=/mnt/c/KenshiModding/pending-fixes/kfp-e1-inline.py
[ -f "$W/vmq85a7-sw.txt" ] || cp /mnt/c/KenshiTestRuns/vmq-85a7/vmrec-q-sword-z0.txt "$W/vmq85a7-sw.txt" 2>/dev/null
if [ -f "$E1I" ] && bash "$HERE/build.sh" "${P[@]}" --patch "$E1I" --out "$BLD/kfpvm_e1inl" >/tmp/al-build8.txt 2>&1; then
  for r in f14-e0 vmq85a7-sw f13-sw0; do "$BLD/kfpvm_e1inl" "$W/$r.txt" /tmp/al-e1i.txt --quiet >/dev/null 2>&1
    a1=$(python3 "$L/animlab.py" inline /tmp/al-e1i.txt | cut -d' ' -f1-2); a2=$(python3 "$L/animlab.py" metrics /tmp/al-e1i.txt | grep '^arc ' | cut -d' ' -f1-3)
    a3=$(python3 "$L/animlab.py" churn --stroke /tmp/al-e1i.txt | cut -d' ' -f1-5); all="$a1 | $a2 | $a3"
    if [ $r = f13-sw0 ]; then echo "REGRESS INFO E1 inline candidate on $r (first swing from ready branch B): $all"
    else case "$all" in "inline PASS | arc PASS"*"| churn PASS"*) ok "E1 inline candidate on $r: $all";; *) bad "E1 inline candidate on $r: $all";; esac; fi; done
else echo "REGRESS INFO E1 inline candidate kfp-e1-inline.py not built (missing or does not apply)"; fi
# 19. sword ready elbow branch (lab #11 2026-10-09): replays of the 74A481A8 solver (f41f862 snapshot) start f13-sw0 swing 1
#     (first after the draw) and f14-e0 runs 87/495 from ready branch B (elbow 5.1,-4.1,5.0, edge ~100 deg off A): `animlab.py
#     branch` must FAIL them; game f14-e0 + vmq85a7 PASS (one branch). Fix: kfp-rb-single.py (fixer #21) + kfp-rb-camup.py
#     (A reference in a frame that doesn't roll with the edge) must PASS all three against the game f14-e0 ready.
#     kfpvm_rb0 is built --no-l1: B only exists in the old lab model (l1k 1); with the game L1 model it never shows (step 20).
#     Game f13-sw0 = INFO (older build: the game itself alternates two ready branches, edge 155 deg apart).
for r in f14-e0 vmq85a7-sw; do b=$(python3 "$L/animlab.py" branch "$W/$r.txt" | cut -c1-120)
  case "$b" in "branch PASS"*) ok "ready branch game $r: $b";; *) bad "ready branch game $r: $b";; esac; done
echo "REGRESS INFO ready branch game f13-sw0: $(python3 "$L/animlab.py" branch "$W/f13-sw0.txt" | cut -d' ' -f1-2)"
if bash "$HERE/build.sh" --rev f41f862 --no-l1 --out "$BLD/kfpvm_rb0" >/tmp/al-build9.txt 2>&1; then
  for r in f13-sw0 f14-e0; do "$BLD/kfpvm_rb0" "$W/$r.txt" /tmp/al-rb0.txt --quiet >/dev/null 2>&1
    b=$(python3 "$L/animlab.py" branch /tmp/al-rb0.txt | cut -c1-160)
    case "$b" in "branch FAIL"*":BAD"*) ok "miss ready branch B reproduced (replay $r @f41f862): $b";; *) bad "ready branch B not caught on $r @f41f862: $b";; esac; done
else bad "build @f41f862 (ready branch)"; fi
RB1=/mnt/c/KenshiModding/pending-fixes/kfp-rb-single.py; RB2=/mnt/c/KenshiModding/pending-fixes/kfp-rb-camup.py
if [ -f "$RB1" ] && [ -f "$RB2" ] && bash "$HERE/build.sh" --rev f41f862 --patch "$HERE/patches/rb-single-root.py" --patch "$RB2" --out "$BLD/kfpvm_rb1" >/tmp/al-build10.txt 2>&1; then
  for r in f13-sw0 f14-e0 vmq85a7-sw; do "$BLD/kfpvm_rb1" "$W/$r.txt" /tmp/al-rb1.txt --quiet >/dev/null 2>&1
    b=$(python3 "$L/animlab.py" branch /tmp/al-rb1.txt --ref "$W/f14-e0.txt" | cut -c1-120)
    case "$b" in "branch PASS"*) ok "ready branch fix on $r: $b";; *) bad "ready branch fix on $r: $b";; esac; done
else echo "REGRESS INFO ready branch fix kfp-rb-single.py + kfp-rb-camup.py not built (missing or committed: check the snapshot instead)"; fi
# 20. crossbow READY commanded->rendered 0.69 dm (miss, cause found by lab #11): in game the solver's cached native upper-arm
#     length g_vm_l1n (|fpn| * derived scale .x, l1fix since 484c8bc) is ~0.87 x the rendered one, so the upper arm stretches
#     15% too much and elbow/wrist/hand/prop overshoot along it. Lab key l1k (patches/l1-scale.py) emulates it: vmq-85a7
#     crossbow ready grip game-vs-replay median must be > 0.5 dm at l1k 1 and < 0.2 at l1k 0.871 (@69bc401 = its build);
#     vmq-85a7 sword plain gate FAIL at l1k 1, PASS at l1k 0.86 (@f41f862).
XB=/mnt/c/KenshiTestRuns/vmq-85a7/vmrec-q-crossbow-z0.txt
if [ -f "$XB" ] && bash "$HERE/build.sh" --rev 69bc401 --patch "$HERE/patches/l1-scale.py" --out "$BLD/kfpvm_l1k85" >/tmp/al-build11.txt 2>&1 \
   && bash "$HERE/build.sh" --rev f41f862 --patch "$HERE/patches/l1-scale.py" --out "$BLD/kfpvm_l1k" >/tmp/al-build12.txt 2>&1; then
  for k in 1 0.871; do "$BLD/kfpvm_l1k85" "$XB" /tmp/al-l1k-$k.txt --quiet --set l1k=$k >/dev/null 2>&1; done
  m=$(cd "$L" && python3 - "$XB" <<'PY'
import sys, recfmt, metrics as M
from recfmt import sub, ln
G = recfmt.parse(sys.argv[1]); PG = M.frame_metrics(G); out = []
for k in ('1', '0.871'):
    R = recfmt.parse('/tmp/al-l1k-%s.txt' % k); PR = M.frame_metrics(R)
    d = sorted(ln(sub(PG[i]['mp'], PR[i]['mp'])) for i in range(min(len(PG), len(PR))) if PG[i]['state'] == 'ready' == PR[i]['state'])
    out.append('%.2f' % d[len(d) // 2])
print(' '.join(out))
PY
)
  set -- $m
  if python3 -c "import sys; sys.exit(0 if float('$1') > 0.5 and float('$2') < 0.2 else 1)" 2>/dev/null; then ok "miss crossbow READY 0.69 reproduced + modelled: ready grip game-replay median l1k1 $1 dm, l1k0.871 $2 dm"
  else bad "crossbow READY l1 model: median l1k1 '$1' l1k0.871 '$2'"; fi
  for k in 1 0.86; do "$BLD/kfpvm_l1k" "$W/vmq85a7-sw.txt" /tmp/al-l1ks.txt --quiet --set l1k=$k >/dev/null 2>&1
    g=$(python3 "$L/animlab.py" compare "$W/vmq85a7-sw.txt" /tmp/al-l1ks.txt | grep '^GATE' | cut -c1-110)
    case "$k:$g" in "1:GATE FAIL"*|"0.86:GATE PASS"*) ok "sword ready vs game, l1k $k: $g";; *) bad "sword ready vs game, l1k $k: $g";; esac; done
else echo "REGRESS INFO l1 model: recording or build missing"; fi
[ $fail = 0 ] && echo "REGRESS ALL PASS" || echo "REGRESS FAILED"
exit $fail
