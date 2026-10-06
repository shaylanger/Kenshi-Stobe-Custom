#!/usr/bin/env python3
"""fp-manual-anatomy.sh R11-RACE: aim at the spawn's bone world points, not at its feet column + a height.
Why (5090 dec-5090-4, KenshiFP 661A87A8, Shek Drifter "Mu"): aim_at() points the crosshair at `where` pos (feet) +
height, but the Shek's skull/neck sit 3-5 dm SIDEWAYS of the feet column (bw_head vs pos, perpendicular to the line of
sight: -4.4, -4.7, -3.0 ... -4.9 dm on ~50 reads; pelvis ~0-1.7). The ray at head/chest height passes beside the body:
the pre-trigger `fp_combat aim` reply had victim=0 / id4=0 (distance 245-290 = ground behind) on all 4 head/chest
shots -> on_target=0, no bolt on the target (bolts converge on the crosshair point). Leg aims (pelvis/legs are near the
feet column) were on target. The 4080 b21 PASS had a target whose upper body stood over its feet.
Fix: RACE aims at bone points from the fresh `fp_combat aim` reply (skull = neck->head extended 1.8x, chest = 70% pelvis->neck
as bonept_of, thigh_r = 70% rthigh->rcalf (lower thigh)), re-read right before the trigger (jit_bone, like jit_aim). Criteria unchanged.
Writes <file>.new then renames (never edits a running script in place).
Usage: fp-r11-race-bonepoint.py <KenshiFP root>"""
import sys, os, pathlib
p = pathlib.Path(sys.argv[1]) / "tests" / "ingame" / "fp-manual-anatomy.sh"
s = p.read_text(encoding="utf-8")
if "jit_bone()" in s:
    print("already applied"); sys.exit(0)

def rep(old, new):
    global s
    assert s.count(old) == 1, "anchor not unique/found: " + old[:80]
    s = s.replace(old, new)

# shot(): bone jit before the column jit
rep('''  p0=$(pos "$AIM_NPC"); if [ -n "$AIM_COL" ] && [ -z "$AIM_PT" ]; then jit_aim; else reaim; fi; waitfor 3 shot_ready 1''',
    '''  p0=$(pos "$AIM_NPC"); if [ -n "$AIM_BONE" ]; then jit_bone; elif [ -n "$AIM_COL" ] && [ -z "$AIM_PT" ]; then jit_aim; else reaim; fi; waitfor 3 shot_ready 1''')

# bonept_of: bone point math moved into bpt (same chest formula) + skull / thigh_r
rep('''bonept_of() { local h r q; BPT=""; for h in 12 9 6 4 2.5 1.5 0.8; do ensure_fp || return 1
    aim_at "$1" "$h"; r=$(A fp_combat aim); BREPLY=$r; AIMR=$r; [ "$(on_target "$1")" = 1 ] || continue
    if [ "$2" = chest ]; then q=$(awk -v p="$(gf bw_pelvis "$r")" -v n="$(gf bw_neck "$r")" 'BEGIN{split(p,a,",");split(n,b,",");
        if(a[1]==""||b[1]==""||a[1]~/nan/||b[1]~/nan/)exit;printf "%.2f %.2f %.2f",a[1]+0.7*(b[1]-a[1]),a[2]+0.7*(b[2]-a[2]),a[3]+0.7*(b[3]-a[3])}')
    else q=$(gf "bw_$2" "$r" | tr , ' '); fi
    [ -n "$q" ] && [[ "$q" != *nan* ]] && { BPT=$q; return 0; }; done; return 1; }''',
    '''# bpt <aim reply> <bone>: world point "x y z" of a bone in the reply (bw_<bone>), or a derived point: chest = 70%
# pelvis->neck, skull = neck->head extended 1.8x (~skull centre; the reply has no victim headnub point), thigh_r = 70% rthigh->rcalf (lower thigh); "" when missing/nan
mixpt() { awk -v p="$1" -v n="$2" -v f="$3" 'BEGIN{split(p,a,",");split(n,b,",");
  if(a[3]==""||b[3]==""||p~/nan/||n~/nan/)exit;printf "%.2f %.2f %.2f",a[1]+f*(b[1]-a[1]),a[2]+f*(b[2]-a[2]),a[3]+f*(b[3]-a[3])}'; }
bpt() { local q; case $2 in chest) q=$(mixpt "$(gf bw_pelvis "$1")" "$(gf bw_neck "$1")" 0.7);;
    skull) q=$(mixpt "$(gf bw_neck "$1")" "$(gf bw_head "$1")" 1.8);; thigh_r) q=$(mixpt "$(gf bw_rthigh "$1")" "$(gf bw_rcalf "$1")" 0.7);;
    *) q=$(gf "bw_$2" "$1" | tr , ' ');; esac; [[ "$q" == *nan* ]] && q=""; echo "$q"; }
bonept_of() { local h r q; BPT=""; for h in 12 9 6 4 2.5 1.5 0.8; do ensure_fp || return 1
    aim_at "$1" "$h"; r=$(A fp_combat aim); BREPLY=$r; AIMR=$r; [ "$(on_target "$1")" = 1 ] || continue
    q=$(bpt "$r" "$2")
    [ -n "$q" ] && { BPT=$q; return 0; }; done; return 1; }
# jit_bone: with AIM_BONE set (a bpt name), re-read that bone's world point right before the trigger and aim at it
# (R11-RACE 5090 dec-5090-4: a Shek's skull/neck stood 3-5 dm sideways of its feet column, so feet+height aims passed
# beside it: on_target=0 on all head/chest shots). From the crosshair as aimed when the ray is on the npc, else
# bonept_of; JIT_H = the point's height over the npc's feet, "stale" = no fresh point (the previous aim is restored).
AIM_BONE=""
jit_bone() { local r q="" p0=$AIM_PT h0=$AIM_H; r=$(A fp_combat aim); AIMR=$r
  [ "$(on_target "$AIM_NPC")" = 1 ] && q=$(bpt "$r" "$AIM_BONE")
  [ -z "$q" ] && bonept_of "$AIM_NPC" "$AIM_BONE" && q=$BPT
  if [ -n "$q" ]; then JIT_H=$(awk -v y="$(cut -d' ' -f2 <<<"$q")" -v f="$(pos "$AIM_NPC" | cut -d' ' -f2)" 'BEGIN{printf "%.2f", y-f}')
    aim_pt "$AIM_NPC" $q
  else JIT_H=stale; if [ -n "$p0" ]; then aim_pt "$AIM_NPC" $p0; else aim_at "$AIM_NPC" "$h0"; fi; fi; }''')

# RACE loop: bone per aimed group
rep('''    for spec in "head 1 0" "chest 2 1" "legs 3 5,6"; do read -r name col want <<<"$spec"''',
    '''    # aim at bone points (bpt), not feet column + height: the body can stand 3-5 dm sideways of its feet (jit_bone)
    for spec in "head 1 0 skull" "chest 2 1 chest" "legs 3 5,6 thigh_r"; do read -r name col want bone <<<"$spec"''')
rep('''        aim_at "$SPAWN" "$ht"; AIM_COL=$col; JIT_H=""; shot "$SPAWN"; AIM_COL=""; judge "${S_HURT[0]}"; shots=$((shots+1))''',
    '''        q=""; [ -n "$BAIM" ] && q=$(bpt "$AIMR" "$bone")   # fresh_bones left AIMR = an on-target reply when BAIM is set
        if [ -n "$q" ]; then aim_pt "$SPAWN" $q; else aim_at "$SPAWN" "$ht"; fi
        AIM_BONE=$bone; JIT_H=""; shot "$SPAWN"; AIM_BONE=""; judge "${S_HURT[0]}"; shots=$((shots+1))''')

tmp = p.with_name(p.name + ".new")
tmp.write_text(s, encoding="utf-8", newline="\n")
os.chmod(tmp, os.stat(p).st_mode)
os.replace(tmp, p)
print("patched", p)
