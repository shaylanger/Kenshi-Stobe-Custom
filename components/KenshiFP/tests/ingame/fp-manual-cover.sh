#!/usr/bin/env bash
# fp-manual-cover.sh: in-game row R10 (cover/parallax) of the manual ranged adapter (COMBAT_TEST_PLAN.md).
# Run with Kenshi in the world on kah-fpxbow (Axima = squad crossbow user, Skaera = hostile Hungry Bandit).
# Setup: a building from `buildings` near the shooter; shooter and target on opposite sides along x (game units = dm),
# both pinned. The FP aim ray at the target's chest must report a nearer non-target hit (the wall) before the shot
# counts as covered; a building that doesn't occlude is skipped (next candidate, up to 6).
# Rows: R10 shot at a covered target -> the bolt leaves (actual_shots +1) and the target is unhurt;
#       R10-CTRL the same target moved into the open at the same distance -> the aim ray hits the target (geometry check).
# Usage: fp-manual-cover.sh [shooter] [target] [outdir]. Ends with one `RESULT <row> PASS|FAIL <evidence>` per row.
SH=${1:-Axima}; TG=${2:-Skaera}; OUT=${3:-/tmp/fp-manual-cover}
mkdir -p "$OUT"; LOG="$OUT/log.txt"; : > "$LOG"
A() { local r; r=$(stobe-auto "$@" 2>&1); echo "> $* | $r" >> "$LOG"; echo "$r"; }
fld() { grep -o "\b$1=[^ ]*" | head -1 | cut -d= -f2; }
cs() { A fp_combat state | fld "$1"; }
inp() { A fp_combat input "$1" "$2" "$3" >/dev/null; }
waitfor() { local end=$((SECONDS+$1)); while [ $SECONDS -lt $end ]; do [ "$(cs "$2")" = "$3" ] && return 0; sleep 0.2; done; return 1; }
pos() { A where "$1" | grep -o 'pos=[^ ]*' | cut -d= -f2 | tr , ' '; }
flesh() { A hp "$1" | grep -o '[0-6]:[-0-9.]*/' | tr -d / | cut -d: -f2 | awk '{s+=$1}END{printf "%.1f", s}'; }
serial() { A where "$1" | grep -o '#[0-9]*' | head -1 | tr -d '#'; }
RESULTS=()
row() { RESULTS+=("RESULT $1 $2 $3"); echo "RESULT $1 $2 $3" >> "$LOG"; }
setup_fail() { echo "RESULT SETUP FAIL $1 log=$LOG"; exit 1; }
FP0=$(A fp_state | fld fp_mode)
cleanup() { A fp_combat input 0 0 0 >/dev/null; A fp_combat off >/dev/null; A fp_combat physical >/dev/null
            A fp_mode "$([ "$FP0" = 1 ] && echo on || echo off)" >/dev/null; }
trap cleanup EXIT
# aim_at <npc> <height dm>: FP camera at the npc's feet + height
aim_at() { read -r sx sy sz <<<"$(pos "$SH")"; read -r tx ty tz <<<"$(pos "$1")"; local e
  local cam cx cz; cam=$(A fp_camera state); e=$(fld camera_y <<<"$cam"); cx=$(fld camera_x <<<"$cam"); cz=$(fld camera_z <<<"$cam")
  [ -n "$cx" ] && [ -n "$cz" ] && { sx=$cx; sz=$cz; }   # aim from the eye, not the feet: the FP eye can sit ~3 dm aside (R09 5090 b7)
  read -r YAW PIT <<<"$(awk -v a="$sx" -v b="$sz" -v c="$tx" -v d="$tz" -v ey="$e" -v py="$(awk -v y="$ty" -v h="$2" 'BEGIN{print y+h}')" \
     'BEGIN{h=sqrt((c-a)^2+(d-b)^2); printf "%.4f %.4f", atan2(c-a, d-b), atan2(ey-py, h)}')"
  A fp_camera look "$YAW" "$PIT" >/dev/null; sleep 0.4; }
# ray_hits_target: the current aim ray's first hit is the target (id4 = its serial)
# one settled aim read: retry ~2 s while physical=0 (4080 b27: the first read came before the ray updated, id4=0, and
# the next read hit the Grain Silo at 164 dm; separate id/distance reads mixed the two), then id4 and distance from it
ray() { local l; for _ in $(seq 1 10); do l=$(A fp_combat aim); echo "$l" | grep -q 'physical=1' && break; sleep 0.2; done
  echo "$(echo "$l" | grep -o 'id4=[0-9]*' | cut -d= -f2) $(echo "$l" | grep -o 'distance=[0-9.]*' | cut -d= -f2)"; }
ray_id() { ray | cut -d' ' -f1; }
ray_dist() { ray | cut -d' ' -f2; }

# ---- setup ----
A status | grep -q phase=world || setup_fail "not in world"
for c in "$SH" "$TG"; do A where "$c" | grep -q 'pos=' || setup_fail "$c not found"; done
[ "$(A rangedinfo "$SH" | fld bow)" != none ] || setup_fail "$SH has no ranged weapon"
A protect "$SH" on >/dev/null
for m in $(A chars 3000 "[nameless]" | tr '|' '
' | sed -n 's/^[0-9]* within [0-9.]*: //; s/^ *//; s/ #.*//p'); do
  case "$m" in "$SH") ;; *) A protect "$m" on >/dev/null; A pin "$m" at "$SH" dist 600 >/dev/null;; esac; done
TS=$(serial "$TG")
A select "$SH" >/dev/null; A fp_mode on >/dev/null; sleep 1; A fp_control take >/dev/null
A fp_combat autoreload 1 >/dev/null
A fp_combat on | grep -q requested || setup_fail "fp_combat on refused"
inp 0 0 0; waitfor 3 armed 1 || setup_fail "adapter never armed (why=$(cs why))"
# candidates: buildings within 3000 of the shooter, nearest first
A buildings 3000 near "$SH" | grep -o 'pos=[-0-9.]*,[-0-9.]*,[-0-9.]*' | cut -d= -f2 | head -6 > "$OUT/cands.txt"
[ -s "$OUT/cands.txt" ] || setup_fail "no building within 3000 of $SH"
COVER=""
while IFS=, read -r bx by bz; do
  A pin "$SH" off >/dev/null; A pin "$TG" off >/dev/null   # a kept pin snaps back to the previous candidate (4080 b26)
  A teleport "$SH" "$(awk -v x="$bx" 'BEGIN{print x-180}')" "$by" "$bz" >/dev/null; A pin "$SH" >/dev/null
  A teleport "$TG" "$(awk -v x="$bx" 'BEGIN{print x+120}')" "$by" "$bz" >/dev/null; A pin "$TG" >/dev/null
  sleep 2; A fp_control take >/dev/null; aim_at "$TG" 13
  inp 1 0 0; waitfor 10 aimed 1; aim_at "$TG" 13
  read -r id d <<<"$(ray)"
  # cover = a physical hit that isn't the target, nearer than the target (300 dm); no hit at all is not cover
  # (4080 batch 2: the 8 m aim ray accepted "id4=0 distance 0" as cover)
  if [ -n "$id" ] && [ "$id" != 0 ] && [ "$id" != "$TS" ] && awk -v d="$d" 'BEGIN{exit !(d>0 && d<300)}'; then COVER="$bx,$by,$bz"; RID=$id; RD=$d; break; fi
  inp 0 0 0
done < "$OUT/cands.txt"
[ -n "$COVER" ] || setup_fail "no candidate building occluded $TG (aim ray hit it each time; see $OUT/cands.txt)"

# ---- R10 covered shot: the bolt leaves, the covered target is unhurt ----
A protect "$TG" off >/dev/null; A health "$TG" 100 >/dev/null; sleep 0.5; H0=$(flesh "$TG"); S0=$(cs actual_shots)
waitfor 10 shot_ready 1; aim_at "$TG" 13; R2=$(ray_id)
inp 1 1 0; for _ in $(seq 1 30); do [ "$(cs actual_shots)" != "$S0" ] && break; sleep 0.1; done; inp 1 0 0
S1=$(cs actual_shots); sleep 3; H1=$(flesh "$TG"); A protect "$TG" on >/dev/null
ev="building=$COVER ray_first_hit id4=$RID (target $TS) at ${RD}dm, at_trigger id4=$R2; shots $S0->$S1 $TG flesh $H0->$H1"
[ "$S1" = "$S0" ] && { st=$(A fp_combat state); ev="$ev refused: gate=$(fld last_reject_gate <<<"$st") rejected=$(fld rejected <<<"$st") native=$(fld last_reject_native <<<"$st") latched=$(fld last_reject_latched <<<"$st") dip_s=$(fld last_reject_dip_s <<<"$st") dt=$(fld last_reject_dt <<<"$st")"; }
if [ "$S1" != "$S0" ] && [ "$R2" != "$TS" ] && [ "$R2" != 0 ] && awk -v a="$H0" -v b="$H1" 'BEGIN{exit !(b>=a-0.5)}'; then row R10 PASS "$ev"; else row R10 FAIL "$ev"; fi

# ---- R10-CTRL: the target in the open at the same distance -> the aim ray reaches it (first open spot of
#      8 offsets around the cover; a prop in one direction is not a product failure: 4080 batch 2 hit one at 4.7 m) ----
IFS=, read -r bx by bz <<<"$COVER"; C=""; TRIED=""
for off in "0 300" "0 -300" "-300 0" "-300 300" "-300 -300" "0 600" "0 -600" "-600 0"; do read -r ox oz <<<"$off"   # 4080 batch 4: props in all of the first 3
  A pin "$TG" off >/dev/null; A teleport "$TG" "$(awk -v x="$bx" -v o="$ox" 'BEGIN{print x-180+o}')" "$by" "$(awk -v z="$bz" -v o="$oz" 'BEGIN{print z+o}')" >/dev/null; A pin "$TG" >/dev/null
  sleep 2; aim_at "$TG" 13; C=$(ray_id); TRIED+="($off):id4=$C@$(ray_dist) "; [ "$C" = "$TS" ] && break; done
inp 0 0 0
ev="open target: ray id4=$C (target $TS) tried ${TRIED% }"
if [ "$C" = "$TS" ]; then row R10-CTRL PASS "$ev"; else row R10-CTRL FAIL "$ev"; fi

for r in "${RESULTS[@]}"; do case "$r" in *FAIL*) echo "$r log=$LOG";; *) echo "$r";; esac; done
