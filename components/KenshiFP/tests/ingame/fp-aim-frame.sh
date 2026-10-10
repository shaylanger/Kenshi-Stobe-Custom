#!/usr/bin/env bash
# fp-aim-frame.sh: B14 vertical frame probe for spatial aim (R08/R10). Run in WSL, Kenshi in the world on kah-fpcam.
# Fires native physics rays (`fp_combat ray`, read-only) horizontally from <shooter> toward <target> 5 units away at several
# heights above the harness `where` y, and reads the FP eye anchor (`fp_camera state` anchor_y). Shows which frame the
# physics bodies live in: a hit whose ids carry the target's serial = the target's body shape at that height.
# Units are game units = dm (a human is ~17-18 tall, the FP eye ~18.4 above where y: FP-EYE). rg-01 2026-10-10: the probe
# used to read them as metres and failed every run on the body itself ("17 m column" in m41 = the 1.7 m tall body).
# PASS = rays at body height (dy<=16) hit the target near its front surface (d 2.5-4.3; centre 4.2 from the ray start),
# no target shape exists above head height (dy>=22: a frame mismatch would put shapes there) and the eye anchor sits
# at head height (14 <= eye-where <= 22).
# Usage: fp-aim-frame.sh [shooter] [target] [outdir]. Ends with `RESULT B14-frame PASS|FAIL <evidence>`.
SH=${1:-Shay}; TG=${2:-Malzin}; OUT=${3:-/tmp/fp-aim-frame}
mkdir -p "$OUT"; LOG="$OUT/log.txt"; : > "$LOG"
A() { local r; r=$(stobe-auto "$@" 2>&1); echo "> $* | $r" >> "$LOG"; echo "$r"; }
fld() { grep -o "\b$1=[^ ]*" | head -1 | cut -d= -f2; }
fail() { echo "RESULT B14-frame FAIL $1 log=$LOG"; exit 1; }
A status | grep -q phase=world || fail "not in world"
A select "$SH" >/dev/null; A fp_mode on >/dev/null; sleep 1; A fp_control take >/dev/null
A pin "$SH" >/dev/null; A pin "$TG" at "$SH" dist 5 face "$SH" >/dev/null; sleep 1.5
read -r sx sy sz <<<"$(A where "$SH" | grep -o 'pos=[^ ]*' | cut -d= -f2 | tr , ' ')"
read -r tx ty tz <<<"$(A where "$TG" | grep -o 'pos=[^ ]*' | cut -d= -f2 | tr , ' ')"
TSER=$(A where "$TG" | grep -o '#[0-9]*' | head -1 | tr -d '#')
[ -n "$sx" ] && [ -n "$tx" ] && [ -n "$TSER" ] || fail "where failed"
YAW=$(awk -v a="$sx" -v b="$sz" -v c="$tx" -v d="$tz" 'BEGIN{printf "%.5f", atan2(c-a, d-b)}')
# start 0.8 m toward the target so the shooter's own shape isn't the first hit
read -r ox oz <<<"$(awk -v a="$sx" -v b="$sz" -v y="$YAW" 'BEGIN{printf "%.4f %.4f", a+0.8*sin(y), b+0.8*cos(y)}')"
A fp_camera look "$YAW" 0 >/dev/null; sleep 0.5
EYE=$(A fp_camera state | fld anchor_y)
HITS=""; BODY=""; GOOD=""
for dy in 0.3 0.8 1.2 1.6 2.5 5 10 16 17 18 19 20 21 22 25 30 40; do
  y=$(awk -v a="$sy" -v b="$dy" 'BEGIN{printf "%.4f", a+b}')
  r=$(A fp_combat ray "$ox" "$y" "$oz" "$YAW" 0)
  h=$(echo "$r" | fld hit); hy=$(echo "$r" | fld y); dist=$(echo "$r" | fld distance)
  ids=$(echo "$r" | grep -o 'id[0-4]=[0-9]*' | cut -d= -f2 | tr '\n' ' ')
  own=0; for i in $ids; do [ "$i" = "$TSER" ] && own=1; done
  HITS+=" dy=$dy:hit=$h,d=${dist},tgt=$own"
  [ "$own" = 1 ] && BODY+=" $dy"
  # a real body hit: body height (dy<=16) and on the target's front half (centre 4.2 from the ray start; torso front ~3.0)
  [ "$own" = 1 ] && awk -v d="$dy" -v x="$dist" 'BEGIN{exit !(d<=16 && x>=2.5 && x<=4.3)}' && GOOD+=" $dy"
done
# eye anchor vs where (the anchor is in the Ogre scene frame for y)
EOFF=$(awk -v e="$EYE" -v y="$sy" 'BEGIN{printf "%.2f", e-y}')
A pin "$SH" off >/dev/null; A pin "$TG" off >/dev/null
ev="where_y=$sy eye_anchor_y=$EYE (eye-where=$EOFF) target_shape_at_dy=[${BODY# }] body_height_hits=[${GOOD# }] rays:$HITS"
HIGH=$(for d in $BODY; do awk -v d="$d" 'BEGIN{exit !(d>=22)}' && echo "$d"; done | tr '\n' ' ')
ev+=" above_head=[${HIGH% }]"
EYEOK=0; awk -v e="$EOFF" 'BEGIN{exit !(e>=14 && e<=22)}' && EYEOK=1
if [ -n "$GOOD" ] && [ -z "$HIGH" ] && [ $EYEOK = 1 ]; then echo "RESULT B14-frame PASS $ev"; else echo "RESULT B14-frame FAIL $ev log=$LOG"; fi
