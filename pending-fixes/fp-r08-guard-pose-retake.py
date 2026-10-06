#!/usr/bin/env python3
"""fp-manual-hits.sh (R08) measurement fix after 5090 dec-5090-1 (KenshiFP 661A87A8, R08 FAIL 6/9):
 R08-GUARD: the 3 chest bolts hit arm_l because the target (hostile Hungry Bandit, aggro since R07's hit) stood upright in a
   guard stance with forearms/hands held ~1.9-2.3 dm in front of her neck toward the shooter (aims.txt pick_bw_lfarm/lhand vs
   pick_bw_neck); the bolts (scatter +-1.6 dm) landed on the raised arm. Routing matched the impact point (no product bug).
   Fix (test only): guard_fwd = the largest horizontal distance any forearm/hand (pick_bw_lfarm/lhand/rfarm/rhand) sits in
   front of the neck (pick_bw_neck) along the neck->FP eye direction (fp_camera state camera_x/z). > 1.0 dm = guard pose.
   Before each R08 shot: bounded wait (10 s) for a neutral pose (target set to passive combat mode for R08, restored after);
   after it, the pose at the trigger (the aims.txt line shot() writes just before firing) is checked again: a guard-pose shot
   is not counted and is retaken, <= 3 tries per counted shot. Fewer than 9 counted shots = SETUP FAIL reason=guard_pose.
   PASS rule (good >= total-1) unchanged.
Usage: fp-r08-guard-pose-retake.py <KenshiFP root>"""
import sys, pathlib
p = pathlib.Path(sys.argv[1]) / "tests" / "ingame" / "fp-manual-hits.sh"
s = p.read_text(encoding="utf-8")
if "guard_pose" in s:
    print("already applied"); sys.exit(0)

def rep(old, new):
    global s
    assert s.count(old) == 1, "anchor not unique/found: " + old[:80]
    s = s.replace(old, new)

# helpers before the R08 setup
rep(r'''SK0=$(A stat "$SH" crossbows | grep -o 'base=[0-9.]*' | cut -d= -f2)''',
    r'''# guard_fwd <fp_combat aim reply>: how far (dm, horizontal) the forearm/hand furthest toward the shooter sits in front of
# the neck, along the neck->FP eye direction (pick_bw_* bones, present when the ray is on the victim); "none" if unknown.
# 5090 dec-5090-1 R08: a guard stance (forearms/hands 1.9-2.3 dm in front of the neck) put the left arm in the line of the
# chest shots (3/3 arm_l). > 1.0 dm = guard pose: the shot is not counted (wait for a neutral pose, retake).
guard_fwd() { local r=$1 cam ex ez nk la lh ra rh; cam=$(A fp_camera state); ex=$(fld camera_x <<<"$cam"); ez=$(fld camera_z <<<"$cam")
  [ -n "$ex" ] && [ -n "$ez" ] || read -r ex _ ez <<<"$(pos "$SH")"
  nk=$(fld pick_bw_neck <<<"$r"); la=$(fld pick_bw_lfarm <<<"$r"); lh=$(fld pick_bw_lhand <<<"$r")
  ra=$(fld pick_bw_rfarm <<<"$r"); rh=$(fld pick_bw_rhand <<<"$r")
  if [ -z "$nk" ] || [ -z "$la" ] || [ -z "$lh" ] || [ -z "$ra" ] || [ -z "$rh" ] || [ -z "$ex" ]; then echo none; return; fi
  awk -v e="$ex" -v f="$ez" -v n="$nk" -v pts="$la $lh $ra $rh" 'BEGIN{split(n,N,","); dx=e-N[1]; dz=f-N[3]; L=sqrt(dx*dx+dz*dz)
    if (L<1) { print "none"; exit } dx/=L; dz/=L; m=-99; k=split(pts,P," ")
    for (i=1;i<=k;i++) { split(P[i],Q,","); v=(Q[1]-N[1])*dx+(Q[3]-N[3])*dz; if (v>m) m=v } printf "%.2f", m}'; }
is_guard() { awk -v g="$1" 'BEGIN{exit !(g!="none" && g!="" && g+0>1.0)}'; }
# neutral_wait: bounded poll (10 s) until the target's pose is not a guard pose (crosshair on her chest); NW = last guard_fwd
neutral_wait() { local end=$((SECONDS+10)); NW=""
  while [ $SECONDS -lt $end ]; do aim_at "$TG" "$MAC"; NW=$(guard_fwd "$(A fp_combat aim)"); is_guard "$NW" || return 0; sleep 0.5; done
  return 1; }
SK0=$(A stat "$SH" crossbows | grep -o 'base=[0-9.]*' | cut -d= -f2)''')

rep('''A fp_combat wound reset >/dev/null; r8=""; good=0; total=0
HS=""
''',
    '''A fp_combat wound reset >/dev/null; r8=""; good=0; total=0
HS=""; disturbed=0; GD=""
# the target is hostile and aggro since R07's hit: passive combat mode for R08 (restored after) to let her drop the guard
PV0=$(A combatmode "$TG" | fld passive); A combatmode "$TG" passive on >/dev/null
''')

rep('''  for _ in 1 2 3; do ht=$(pose_follow "$col"); [ "$col" = 1 ] && ht=$(on_victim "$ht"); HS+="$ht,"; aim_at "$TG" "$ht"
    read -r ok h <<<"$(shot "$TG")"; got+="${h:-miss};"; total=$((total+1))
    for w in ${want//,/ }; do [[ ",$h" == *",$w("* ]] && { good=$((good+1)); break; }; done; done''',
    '''  for _ in 1 2 3; do cnt=0
    # counted shot = the target not in a guard pose at the trigger (guard_fwd <= 1.0 dm); <= 3 tries per counted shot
    for try in 1 2 3; do
      neutral_wait || { disturbed=$((disturbed+1)); GD+="$name:wait(fwd=$NW);"; continue; }
      ht=$(pose_follow "$col"); [ "$col" = 1 ] && ht=$(on_victim "$ht"); aim_at "$TG" "$ht"
      read -r ok h <<<"$(shot "$TG")"; gf=$(guard_fwd "$(tail -n 1 "$OUT/aims.txt")")
      if is_guard "$gf"; then disturbed=$((disturbed+1)); GD+="$name:${h:-miss}(fwd=$gf);"; continue; fi
      cnt=1; break; done
    [ "$cnt" = 1 ] || continue
    HS+="$ht,"; got+="${h:-miss};"; total=$((total+1))
    for w in ${want//,/ }; do [[ ",$h" == *",$w("* ]] && { good=$((good+1)); break; }; done; done''')

rep('''A setstat "$SH" crossbows "$SK0" >/dev/null; A setstat "$SH" perception "$PE0" >/dev/null
WS=$(''',
    '''A setstat "$SH" crossbows "$SK0" >/dev/null; A setstat "$SH" perception "$PE0" >/dev/null
case "$PV0" in 1|on|true) A combatmode "$TG" passive on >/dev/null;; *) A combatmode "$TG" passive off >/dev/null;; esac
WS=$(''')

rep('''ev="aimed part hit $good/$total: ${r8% } $BONES aim_h=$AH/$AC/$AL shot_h=${HS%,} ${WS% } $(ui_summary)"
if [ "$good" -ge $((total-1)) ]; then row R08 PASS "$ev"; else row R08 FAIL "$ev"; fi''',
    '''ev="aimed part hit $good/$total: ${r8% } $BONES aim_h=$AH/$AC/$AL shot_h=${HS%,} guard_retaken=$disturbed${GD:+ [${GD%;}]} ${WS% } $(ui_summary)"
if [ "$total" -lt 9 ]; then row R08 SETUP "FAIL reason=guard_pose: only $total of 9 shots without the target's forearms/hands > 1.0 dm in front of her neck: $ev"
elif [ "$good" -ge $((total-1)) ]; then row R08 PASS "$ev"; else row R08 FAIL "$ev"; fi''')

# never edit a possibly running script in place: write .new, keep the mode, then rename over it
import os, shutil
n = p.with_name(p.name + ".new"); n.write_text(s, encoding="utf-8"); shutil.copymode(p, n); os.replace(n, p)
print("patched", p)
