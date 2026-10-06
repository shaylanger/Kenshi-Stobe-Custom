#!/usr/bin/env bash
# fp-manual-hits.sh: in-game rows R07 (native damage/XP), R08 (spatial body part) and R09 (intervening NPC) of the
# manual ranged adapter (COMBAT_TEST_PLAN.md). Run in WSL with Kenshi in the world on kah-fpxbow (Axima = squad crossbow
# user, Skaera = hostile Hungry Bandit, Shay = squad mate used as the intervening body).
# Input: `fp_combat input <aim> <fire> <reload>`; aim: `fp_camera look <yaw> <pitch>` from the FP eye (fp_camera state
# camera_y) to a point at a given height over the target's feet (game units = dm). Evidence: the victim's flesh per body
# part (`hp`: 0 head 1 chest 2 stomach 3 left_arm 4 right_arm 5 left_leg 6 right_leg) before/after each manual shot,
# the shooter's crossbows base skill, the adapter's actual_shots.
# Usage: fp-manual-hits.sh [shooter] [target] [blocker] [outdir]. Ends with one `RESULT <row> PASS|FAIL <evidence>` per row.
SH=${1:-Axima}; TG=${2:-Skaera}; BL=${3:-Shay}; OUT=${4:-/tmp/fp-manual-hits}
mkdir -p "$OUT"; LOG="$OUT/log.txt"; : > "$LOG"
A() { local r; r=$(stobe-auto "$@" 2>&1); echo "> $* | $r" >> "$LOG"; echo "$r"; }
fld() { grep -o "\b$1=[^ ]*" | head -1 | cut -d= -f2; }
. "$(dirname "$0")/fp-ui-guard.sh" 2>/dev/null ||   # ui_guard_setup / ui_clear (an NPC dialogue blocks manual shots)
  { ui_guard_setup() { :; }; ui_clear() { return 0; }; ui_summary() { echo "ui_guard=missing"; }; }
cs() { A fp_combat state | fld "$1"; }
inp() { A fp_combat input "$1" "$2" "$3" >/dev/null; }
waitfor() { local end=$((SECONDS+$1)); while [ $SECONDS -lt $end ]; do [ "$(cs "$2")" = "$3" ] && return 0; sleep 0.2; done; return 1; }
pos() { A where "$1" | grep -o 'pos=[^ ]*' | cut -d= -f2 | tr , ' '; }
# flesh of parts 0..6; with EFF=1 flesh minus stun damage (armour can stop flesh damage but a hit still stuns: R09)
parts() { A hp "$1" | sed 's/.*parts //' | awk -v eff="${EFF:-0}" '{ s=$0; gsub(/ [0-6]:/, "\n&", s); n=split(s, L, "\n"); o=""
  for (i=1;i<=n;i++) if (match(L[i], /[0-6]:[-0-9.]+\//)) { f=substr(L[i], RSTART+2, RLENGTH-3); st=0
    if (match(L[i], /stun [-0-9.]+/)) st=substr(L[i], RSTART+5, RLENGTH-5); if (eff) f=f-st; o=o f " " } print o }'; }
# hurt <before> <after>: indices of parts that lost > 0.5 flesh, e.g. "1(-12.3)"
hurt() { awk -v a="$1" -v b="$2" 'BEGIN{n=split(a,x," ");split(b,y," ");s="";for(i=1;i<=n;i++){d=y[i]-x[i];if(d<-0.5)s=s (s?",":"") (i-1) "(" sprintf("%.1f",d) ")"};print s}'; }
skill() { A rangedinfo "$SH" | grep -o 'crossbows=[0-9.]*' | cut -d= -f2; }       # 4 decimals
RESULTS=()
row() { RESULTS+=("RESULT $1 $2 $3"); echo "RESULT $1 $2 $3" >> "$LOG"; }
setup_fail() { echo "RESULT SETUP FAIL $1 log=$LOG"; exit 1; }
FP0=$(A fp_state | fld fp_mode)
cleanup() { A fp_combat input 0 0 0 >/dev/null; A fp_combat off >/dev/null; A fp_combat physical >/dev/null
            A fp_mode "$([ "$FP0" = 1 ] && echo on || echo off)" >/dev/null; }
trap cleanup EXIT

# aim_at <npc> <height dm>: point the FP camera at the npc's feet + height
aim_at() { local s t e; read -r sx sy sz <<<"$(pos "$SH")"; read -r tx ty tz <<<"$(pos "$1")"
  local cam cx cz; cam=$(A fp_camera state); e=$(fld camera_y <<<"$cam"); cx=$(fld camera_x <<<"$cam"); cz=$(fld camera_z <<<"$cam")
  [ -n "$cx" ] && [ -n "$cz" ] && { sx=$cx; sz=$cz; }   # aim from the eye, not the feet: the FP eye can sit ~3 dm aside (R09 5090 b7)
  read -r YAW PIT <<<"$(awk -v a="$sx" -v b="$sz" -v c="$tx" -v d="$tz" -v ey="$e" -v py="$(awk -v y="$ty" -v h="$2" 'BEGIN{print y+h}')" \
     'BEGIN{h=sqrt((c-a)^2+(d-b)^2); printf "%.4f %.4f", atan2(c-a, d-b), atan2(ey-py, h)}')"
  A fp_camera look "$YAW" "$PIT" >/dev/null; AIM_NPC=$1; AIM_H=$2; sleep 0.4
  # AIM_BONE=neck|chest: aim at the spine (x/z of the neck bone, or 70% pelvis->neck), not the root position: in a guard pose
  # the neck sits ~1.3 dm aside of getPosition as the shooter sees it, so a "central" head shot hit the right shoulder
  # (5090 b9 R08: arm_r 3/3, core_s 0.32 > margin 0.3; ranged fixer r6). Bones from the reply with the ray on the npc.
  if [ -n "$AIM_BONE" ]; then local r nk pv bx bz; r=$(A fp_combat aim); nk=$(fld bw_neck <<<"$r"); pv=$(fld bw_pelvis <<<"$r")
    if [ -n "$nk" ] && [ -n "$pv" ]; then
      # AIM_LAT (dm, R08 occlusion): shift the point sideways, perpendicular to the horizontal eye->spine line (as occl)
      read -r bx bz <<<"$(awk -v n="$nk" -v p="$pv" -v m="$AIM_BONE" -v sx="$sx" -v sz="$sz" -v lat="${AIM_LAT:-0}" 'BEGIN{split(n,a,",");split(p,b,",");f=(m=="neck")?1:0.7
        x=b[1]+f*(a[1]-b[1]); z=b[3]+f*(a[3]-b[3]); dx=x-sx; dz=z-sz; L=sqrt(dx*dx+dz*dz); if (L>1) { x+=lat*dz/L; z-=lat*dx/L }
        printf "%.2f %.2f", x, z}')"
      read -r YAW PIT <<<"$(awk -v a="$sx" -v b="$sz" -v c="$bx" -v d="$bz" -v ey="$e" -v py="$(awk -v y="$ty" -v h="$2" 'BEGIN{print y+h}')"          'BEGIN{h=sqrt((c-a)^2+(d-b)^2); printf "%.4f %.4f", atan2(c-a, d-b), atan2(ey-py, h)}')"
      A fp_camera look "$YAW" "$PIT" >/dev/null; sleep 0.4; fi; fi; }
# shot <victim...>: one manual shot; prints "<shot 0|1> <hurt on victim1>|<hurt on victim2>..."
shot() { local s0 b=() v r=""; s0=$(cs actual_shots)
  for v in "$@"; do A protect "$v" off >/dev/null; A health "$v" 100 >/dev/null; done; sleep 0.3
  for v in "$@"; do b+=("$(parts "$v")"); done
  ui_clear; inp 1 0 0
  waitfor 8 shot_ready 1 || { ui_clear && inp 0 0 0 && sleep 0.4 && inp 1 0 0 && waitfor 8 shot_ready 1; }   # fresh aim press: a dialogue holsters the bow (4080 b17) || { echo "0 not_ready"; return; }
  aim_at "$AIM_NPC" "$AIM_H"; waitfor 3 shot_ready 1                  # the shooter can step while aiming: re-aim
  A fp_combat aim >> "$OUT/aims.txt"
  inp 1 1 0; local end=$((SECONDS+3)) ok=0
  while [ $SECONDS -lt $end ]; do [ "$(cs actual_shots)" != "$s0" ] && { ok=1; break; }; sleep 0.1; done
  inp 1 0 0; sleep 2.5
  local i=0; for v in "$@"; do r+="$(hurt "${b[$i]}" "$(parts "$v")")|"; i=$((i+1)); A protect "$v" on >/dev/null; done
  inp 1 0 0; waitfor 6 reloading 0 >/dev/null; echo "$ok ${r%|}"; }

# ---- setup ----
A status | grep -q phase=world || setup_fail "not in world"
for c in "$SH" "$TG" "$BL"; do A where "$c" | grep -q 'pos=' || setup_fail "$c not found"; done
[ "$(A rangedinfo "$SH" | fld bow)" != none ] || setup_fail "$SH has no ranged weapon"
A protect "$SH" on >/dev/null; A protect "$TG" on >/dev/null; A protect "$BL" on >/dev/null   # off only around each shot
ui_guard_setup
A pin "$BL" at "$SH" dist 400 >/dev/null
# every other squad member far away + protected (a mate meleeing the target or standing in the line of fire spoils it)
for m in $(A chars 3000 "[nameless]" | tr '|' '
' | sed -n 's/^[0-9]* within [0-9.]*: //; s/^ *//; s/ #.*//p'); do
  case "$m" in "$SH"|"$BL") ;; *) A protect "$m" on >/dev/null; A pin "$m" at "$SH" dist 600 >/dev/null;; esac; done
A pin "$TG" at "$SH" dist 30 face "$SH" >/dev/null
A select "$SH" >/dev/null; A fp_mode on >/dev/null; sleep 1
A fp_control take >/dev/null
A fp_control state | grep -q "control_ids=.*/$(A where "$SH" | grep -o '#[0-9]*' | tr -d '#')" || setup_fail "fp_control did not take $SH"
A fp_combat autoreload 1 >/dev/null
A fp_combat on | grep -q requested || setup_fail "fp_combat on refused"
inp 0 0 0; waitfor 3 armed 1 || setup_fail "adapter never armed (enabled=$(cs enabled) fault=$(cs fault) why=$(cs why))"

# ---- R13 raise outside native ranged combat: holstered crossbow, aim -> drawn by the adapter -> shot-ready ----
for _ in $(seq 1 30); do [ "$(cs why)" = holstered ] && break; inp 0 0 0; sleep 0.5; done   # wait for the AI combat to end
W0=$(cs why); D0=$(cs draws); RI0=$(A rangedinfo "$SH" | grep -o 'in_ranged_combat=[0-9]')
inp 1 0 0; SR=0; waitfor 10 shot_ready 1 && SR=1; W1=$(cs why); D1=$(cs draws);   # SR from the wait: readiness can drop again when the aim timer restarts
 DG=$(A fp_combat state | grep -o "wih=.*"); inp 0 0 0; sleep 1
ev="before why=$W0 $RI0; aim: draws $D0->$D1 why=$W1 shot_ready=$SR $DG"
if [ "$W0" = holstered ] && [ "$SR" = 1 ] && [ $((D1-D0)) -ge 1 ]; then row R13 PASS "$ev"; else row R13 FAIL "$ev"; fi

# ---- R07 native damage + XP at the fixture's own skill (chest aim) ----
aim_at "$TG" 13
# up to 6 shots: at the fixture's skill (acc ~0.44) bolts miss (4080 fp-4080-23: 3 misses in a row, p~0.18); XP accrues per shot either way
K0=$(skill); n7=0; for _ in 1 2 3 4 5 6; do read -r ok h <<<"$(shot "$TG")"; n7=$((n7+1)); [ -n "$h" ] && [ "$h" != not_ready ] && break; done; K1=$(skill)
ev="shot=$ok after $n7 $TG hurt=${h:-none} crossbows_base $K0->$K1"
if [ "$ok" = 1 ] && [ -n "$h" ] && [ "$h" != not_ready ] && awk -v a="$K0" -v b="$K1" 'BEGIN{exit !(b>a)}'; then row R07 PASS "$ev"; else row R07 FAIL "$ev"; fi

# ---- R08 spatial body part: low-spread diagnostic (crossbows/perception 100), 3 shots per height ----
# Aim heights come from the victim's own skeleton (`fp_combat aim` with the crosshair on it: bones=head,headnub,neck,
# pelvis,calf and aim=head,chest,legs dm above its feet): head = mid head->headnub, chest = 70% pelvis->neck, legs = knees.
# Fixed 17 dm-human heights only when no bone reply comes (evidence shows bones=none).
# The target's pose changes (4080 batch 14: bones read 4 dm low right after R07's hit, she stood up again before the
# shots: every head/chest shot landed on the stomach). measure_r08 reads the bones until two reads 1 s apart agree
# (neck within 0.5 dm); each block re-measures, and each shot re-reads the pose and follows it (pose_follow).
settled_br() { local prev="" n k; BR=""; for k in 1 2 3 4 5 6 7 8; do
    aim_at "$TG" "${1:-12}"; BR=$(A fp_combat aim); grep -q '\baim=[-0-9.]*,' <<<"$BR" || { BR=""; sleep 0.5; continue; }
    n=$(grep -o '\bbones=[^ ]*' <<<"$BR" | cut -d= -f2 | cut -d, -f3)
    [ -n "$prev" ] && awk -v a="$n" -v b="$prev" 'BEGIN{d=a-b;exit !(d<0.5&&d>-0.5)}' && return 0
    prev=$n; sleep 1; done; [ -n "$BR" ]; }
measure_r08() {
settled_br 12
BONES=$(grep -o '\bbones=[^ ]*' <<<"$BR"); read -r AH AC AL <<<"$(grep -o '\baim=[-0-9.,]*' <<<"$BR" | cut -d= -f2 | tr , ' ')"
[ -n "$AL" ] || { AH=16.5; AC=12.5; AL=4; BONES="bones=none"; }
# Head: the physics shape tops out near the neck bone, far below the Head bone (fp-5090-3/5: no ray hit 17.25-17.99 dm,
# neck 16.95, Head 18.0). The product's head zone starts one head radius (1.0 dm) under the neck bone (shoulder line).
# Probe the camera ray down from the Head bone in 0.2 dm steps (to the pelvis) to the highest height that still hits this
# victim = shape top HT, then aim halfway between the shoulder line and HT (else the reply's head aim, neck - 0.5).
VIC=$(grep -o '\bvictim=[0-9a-f]*' <<<"$BR" | cut -d= -f2); read -r BH BN BP <<<"$(grep -o '\bbones=[^ ]*' <<<"$BR" | cut -d= -f2 | awk -F, '{print $1, $3, $4}')"
HT=""; if [ -n "$VIC" ] && [ "$VIC" != 0 ] && [ -n "$BP" ]; then
  for h in $(awk -v a="$BH" -v p="$BP" 'BEGIN{for(x=a;x>p;x-=0.2)printf "%.2f ",x}'); do
    aim_at "$TG" "$h"; grep -q "\bvictim=$VIC " <<<"$(A fp_combat aim)" && { HT=$h; break; }; done
  [ -n "$HT" ] && awk -v n="$BN" -v t="$HT" 'BEGIN{exit !(t>n-1.0+0.2)}' && AH=$(awk -v n="$BN" -v t="$HT" 'BEGIN{printf "%.2f", (n-1.0+t)/2}'); fi
BONES+=" head_top=${HT:-none} shoulder=$(awk -v n="${BN:-nan}" 'BEGIN{printf "%.2f", n-1.0}')"
MBN=$BN; MAH=$AH; MAC=$AC; MAL=$AL; }
# pose_follow <col 1|2|3>: the aim height for this shot from a settled re-read of the pose: chest/legs = the reply's
# aim=, head = the measured head aim shifted by the neck's move since measure_r08 (the shape top follows the neck)
pose_follow() { local n a b c; settled_br "$(cut -d' ' -f"$1" <<<"$MAH $MAC $MAL")" || { cut -d' ' -f"$1" <<<"$MAH $MAC $MAL"; return; }
  n=$(grep -o '\bbones=[^ ]*' <<<"$BR" | cut -d= -f2 | cut -d, -f3)
  read -r a b c <<<"$(grep -o '\baim=[-0-9.,]*' <<<"$BR" | cut -d= -f2 | tr , ' ')"
  case $1 in 1) awk -v h="$MAH" -v n="$n" -v m="$MBN" 'BEGIN{printf "%.2f", h+(n-m)}';; 2) echo "$b";; 3) echo "$c";; esac; }
# on_victim <h>: head aim only; the followed height can land above the head shape when the neck bone read is ahead of
# the physics shape (4080 b16: 17.12 vs head_top 17.02, 3 misses): step down 0.2 dm (<= 1.2) until the camera ray hits
# the victim, as a player lowers the sight onto the head. Height unchanged if no victim id or nothing hits.
on_victim() { local x; [ -n "$VIC" ] && [ "$VIC" != 0 ] || { echo "$1"; return; }
  for x in $(awk -v a="$1" 'BEGIN{for(i=0;i<=6;i++)printf "%.2f ", a-0.2*i}'); do aim_at "$TG" "$x"
    grep -q "\bvictim=$VIC " <<<"$(A fp_combat aim)" && { echo "$x"; return; }; done; echo "$1"; }
# occl <fp_combat aim reply> <h dm above the feet> <lateral dm>: the arm (arm_l|arm_r) that lies on the camera ray to the
# aim point (the spine point aim_at targets with AIM_BONE, shifted by AIM_LAT) at least 0.6 dm in front of it, else none
# (unknown without the pick_bw_* arm bones, i.e. the ray is not on the victim). Arm = upper arm (radius 0.5), forearm
# (0.45), hand (1 dm past the wrist, 0.45), + 0.15 dm margin, sampled at 21 points per segment.
# m49 (dec-5090-1/4/5): Skaera stands side-on in her Iron Stick stance, the left arm ~3 dm in front of the spine in every
# combat mode/faction; chest shots through it hit arm_l 3/3 (physically blocked) and a "neutral pose" wait never ended.
occl() { local r=$1 cam ex ey ez ty f b="" k v; cam=$(A fp_camera state); ex=$(fld camera_x <<<"$cam"); ey=$(fld camera_y <<<"$cam")
  ez=$(fld camera_z <<<"$cam"); read -r _ ty _ <<<"$(pos "$TG")"; f=0.7; [ "$AIM_BONE" = neck ] && f=1
  for k in neck pelvis luarm lfarm lhand ruarm rfarm rhand; do v=$(fld "pick_bw_$k" <<<"$r"); [ -n "$v" ] || { echo unknown; return; }; b+="$v "; done
  [ -n "$ex" ] && [ -n "$ey" ] && [ -n "$ez" ] && [ -n "$ty" ] || { echo unknown; return; }
  awk -v e="$ex,$ey,$ez" -v b="$b" -v ty="$ty" -v h="$2" -v lat="$3" -v f="$f" 'BEGIN{split(e,E,","); n=split(b,B," ")
    for (i=1;i<=n;i++) { split(B[i],T,","); X[i]=T[1]; Y[i]=T[2]; Z[i]=T[3] }
    px=X[2]+f*(X[1]-X[2]); pz=Z[2]+f*(Z[1]-Z[2]); dx=px-E[1]; dz=pz-E[3]; L=sqrt(dx*dx+dz*dz); if (L>1) { px+=lat*dz/L; pz-=lat*dx/L }
    py=ty+h; rx=px-E[1]; ry=py-E[2]; rz=pz-E[3]; LP2=rx*rx+ry*ry+rz*rz; LP=sqrt(LP2); best=2; who="none"
    for (s=0;s<2;s++) { u=3+3*s; fo=u+1; hd=u+2; nm=s?"arm_r":"arm_l"
      hx=X[hd]-X[fo]; hy=Y[hd]-Y[fo]; hz=Z[hd]-Z[fo]; hl=sqrt(hx*hx+hy*hy+hz*hz); if (hl<0.01) hl=1
      a[1]=u; c[1]=fo; R[1]=0.5; a[2]=fo; c[2]=hd; R[2]=0.45
      for (g=1;g<=3;g++) { if (g<3) { ax=X[a[g]]; ay=Y[a[g]]; az=Z[a[g]]; bx=X[c[g]]; by=Y[c[g]]; bz=Z[c[g]]; rr=R[g] }
        else { ax=X[hd]; ay=Y[hd]; az=Z[hd]; bx=ax+hx/hl; by=ay+hy/hl; bz=az+hz/hl; rr=0.45 }
        for (j=0;j<=20;j++) { qx=ax+(bx-ax)*j/20; qy=ay+(by-ay)*j/20; qz=az+(bz-az)*j/20
          t=((qx-E[1])*rx+(qy-E[2])*ry+(qz-E[3])*rz)/LP2; if (t<0) t=0; if (t>1) t=1
          d=sqrt((E[1]+t*rx-qx)^2+(E[2]+t*ry-qy)^2+(E[3]+t*rz-qz)^2)
          if (d<rr+0.15 && (1-t)*LP>0.6 && t<best) { best=t; who=nm } } } }
    print who}'; }
# free_aim <col> <h>: AIM_LAT for this shot: the first sideways offset (head 0/+-0.3, chest 0/+-0.6/+-1.0 dm) whose camera
# ray is on the victim and not blocked by an arm; none free: AIM_LAT=0 (that shot's expected part = the blocking arm)
free_aim() { local l r o; for l in $([ "$1" = 1 ] && echo "0 0.3 -0.3" || echo "0 0.6 -0.6 1.0 -1.0"); do AIM_LAT=$l; aim_at "$TG" "$2"
    r=$(A fp_combat aim); { [ -z "$VIC" ] || [ "$VIC" = 0 ] || grep -q "\bvictim=$VIC " <<<"$r"; } || continue
    o=$(occl "$r" "$2" "$l"); [ "$o" = none ] && return 0; done; AIM_LAT=0; aim_at "$TG" "$2"; }
SK0=$(A stat "$SH" crossbows | grep -o 'base=[0-9.]*' | cut -d= -f2); PE0=$(A stat "$SH" perception | grep -o 'base=[0-9.]*' | cut -d= -f2)
A setstat "$SH" crossbows 100 >/dev/null; A setstat "$SH" perception 100 >/dev/null
A fp_combat wound reset >/dev/null; r8=""; good=0; total=0; HS=""; nocc=0; disturbed=0; GD=""
# the target is hostile and aggro since R07's hit: passive combat mode for R08 (restored after)
PV0=$(A combatmode "$TG" | fld passive); A combatmode "$TG" passive on >/dev/null
for spec in "head 1 0" "chest 2 1" "legs 3 5,6"; do
  read -r name col want <<<"$spec"; case $col in 1) AIM_BONE=neck;; 2) AIM_BONE=chest;; *) AIM_BONE="";; esac; AIM_LAT=0; measure_r08; got=""
  for _ in 1 2 3; do cnt=0
    # m49 (dec-5090-6): she ducks/staggers between the settled read and the trigger (neck 15.42 / 13.27 vs 16.95 upright):
    # a shot counts only if the pose AT the trigger (shot()'s aim reply) still fits the aim: neck within 0.5 dm of the
    # measured upright neck and the aim height within the part's zone tolerance; else retaken (<= 3 tries per counted shot)
    for try in 1 2 3; do AIM_LAT=0; ht=$(pose_follow "$col"); [ "$col" = 1 ] && ht=$(on_victim "$ht")
      # arms cannot cover the knees: legs keep the plain aim (no arm bones on the leg ray either)
      if [ "$col" = 3 ]; then aim_at "$TG" "$ht"; else free_aim "$col" "$ht"; fi
      read -r ok h <<<"$(shot "$TG")"; tr8=$(tail -n 1 "$OUT/aims.txt")
      pm=$(awk -v b="$(grep -o '\bbones=[^ ]*' <<<"$tr8" | cut -d= -f2)" -v a="$(grep -o '\baim=[-0-9.,]*' <<<"$tr8" | cut -d= -f2)" \
        -v mn="$MBN" -v mh="$MAH" -v c="$col" -v h="$ht" 'BEGIN{split(b,B,","); split(a,A,","); if (B[3]=="" || A[c]=="") { print "nobones"; exit }
          e=(c==1)?mh+(B[3]-mn):A[c]; tol=(c==1)?1.3:0.8; d=B[3]-mn; x=h-e
          if (d>0.5||d<-0.5||x>tol||x<-tol) printf "neck%+.2f,h%+.2f", d, x; else print "ok"}')
      [ "$pm" = ok ] && { cnt=1; break; }; disturbed=$((disturbed+1)); GD+="$name:${h:-miss}($pm);"; done
    [ "$cnt" = 1 ] || continue
    oc=none; exp=$want
    # arm on the line to the aim point at the trigger: the aimed part (core wins on its silhouette, kfp_wound_from_bones)
    # or that arm (a bolt stopped by the forearm) both count
    [ "$col" = 3 ] || oc=$(occl "$tr8" "$ht" "$AIM_LAT")
    case $oc in arm_l) exp+=",3"; nocc=$((nocc+1));; arm_r) exp+=",4"; nocc=$((nocc+1));; esac
    HS+="$ht$([ "$AIM_LAT" = 0 ] || echo "@$AIM_LAT"),"; got+="${h:-miss}$([ "$oc" = none ] || echo "[$oc]");"; total=$((total+1))
    for w in ${exp//,/ }; do [[ ",$h" == *",$w("* ]] && { good=$((good+1)); break; }; done; done
  r8+="$name:${got%;} "
done; AIM_BONE=""; AIM_LAT=0
A setstat "$SH" crossbows "$SK0" >/dev/null; A setstat "$SH" perception "$PE0" >/dev/null
case "$PV0" in 1|on|true) A combatmode "$TG" passive on >/dev/null;; *) A combatmode "$TG" passive off >/dev/null;; esac
WS=$(A fp_combat wound | grep -o 'wound_ready=[0-9]*\|wound_spatial=[0-9]*\|wound_native_fallback=[0-9]*\|last_fallback=[a-z_]*' | tr '\n' ' ')
ev="expected part hit $good/$total (arm-blocked $nocc: aimed part or [arm] counts): ${r8% } $BONES aim_h=$AH/$AC/$AL shot_h=${HS%,} pose_retaken=$disturbed${GD:+ [${GD%;}]} ${WS% } $(ui_summary)"
if [ "$total" -lt 9 ]; then row R08 SETUP "FAIL reason=pose_moved: only $total of 9 shots with her pose at the trigger matching the aim: $ev"
elif [ "$good" -ge $((total-1)) ]; then row R08 PASS "$ev"; else row R08 FAIL "$ev"; fi

# ---- R09 intervening body: blocker halfway, aim at the target's chest through it ----
A pin "$TG" off >/dev/null; A pin "$TG" at "$SH" dist 50 face "$SH" >/dev/null
read -r sx sy sz <<<"$(pos "$SH")"; read -r tx ty tz <<<"$(pos "$TG")"
# the blocker goes halfway along the EYE->target line: the FP eye sits ~4 dm aside of the feet, so a feet midpoint left
# the ray ~2 dm beside the blocker (5090 b8: the aim ray's victim was the target, all bolts hit it)
# ... and where the ray is ~13 dm above the ground: the eye sits ~23 dm up, so at the midpoint a ray aimed 12.5 dm up the
# target passed ~18 dm high, over the blocker's head (5090 b9: aim=target on every shot); fraction clamped to 0.5..0.85
place_bl() { local cam ex ey ez; cam=$(A fp_camera state); ex=$(fld camera_x <<<"$cam"); ey=$(fld camera_y <<<"$cam"); ez=$(fld camera_z <<<"$cam")
  read -r tx ty tz <<<"$(pos "$TG")"; [ -n "$ex" ] || { ex=$sx; ey=$((${sy%.*}+17)); ez=$sz; }
  A pin "$BL" off >/dev/null
  A pin "$BL" at $(awk -v a="$ex" -v b="$tx" -v c="$ez" -v d="$tz" -v y="$ty" -v e="$ey" 'BEGIN{E=e-y; f=(E>12.6)?(E-13)/(E-12.5):0.5
    if(f<0.5)f=0.5; if(f>0.85)f=0.85; print a+f*(b-a), y, c+f*(d-c)}') face "$SH" >/dev/null; sleep 0.5; }
# aim_victim: whose body the physical aim ray hits now (blocker|target|other)
BLID=$(A where "$BL" | grep -o '#[0-9]*' | head -1 | tr -d '#'); TGID=$(A where "$TG" | grep -o '#[0-9]*' | head -1 | tr -d '#')
aim_victim() { local v; v=$(A fp_combat aim | fld id4); case "$v" in "$BLID") echo blocker;; "$TGID") echo target;; *) echo "other:$v";; esac; }
place_bl
# low-spread (crossbows/perception 100) and up to 3 shots: PASS = some shot hurts the blocker, none ever hurts the target
A setstat "$SH" crossbows 100 >/dev/null; A setstat "$SH" perception 100 >/dev/null
EFF=1; aim_at "$TG" 12.5; r9=""; hitb=0; hitt=0
for _ in 1 2 3; do aim_at "$TG" 12.5; av=$(aim_victim); [ "$av" = blocker ] || { place_bl; aim_at "$TG" 12.5; av=$(aim_victim); }
  r9+="aim=$av "; read -r ok h <<<"$(shot "$BL" "$TG")"; hb=${h%%|*}; ht=${h#*|}; [ "$h" = not_ready ] && { hb=""; ht=""; }
  r9+="shot=$ok blocker=${hb:-none} target=${ht:-none}; "; [ -n "$hb" ] && hitb=1; [ -n "$ht" ] && hitt=1; [ $hitb = 1 ] && break; done
A setstat "$SH" crossbows "$SK0" >/dev/null; A setstat "$SH" perception "$PE0" >/dev/null
ev="$BL between, $TG behind: ${r9%; }"
if [ $hitb = 1 ] && [ $hitt = 0 ]; then row R09 PASS "$ev"; else row R09 FAIL "$ev"; fi
A protect "$BL" off >/dev/null; A protect "$TG" off >/dev/null; A pin "$BL" off >/dev/null; A pin "$TG" off >/dev/null

printf '%s\n' "${RESULTS[@]}" | while read -r l; do case "$l" in *FAIL*) echo "$l log=$LOG";; *) echo "$l";; esac; done
