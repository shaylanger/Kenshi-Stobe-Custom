#!/usr/bin/env bash
# reloaddefs_sff.sh (imm26-sfFixA2): ANCHOR PING-PONG chase for the SETUP-FAIL ticket 23-e (5090-i3 NC20, sfJ run). Source it AFTER reloaddefs_sfj.sh (reload-run-sff.sh does); it REPLACES
# rw_chase_sfj in that shell only (rd_23e of sfJ calls it by name), so reloaddefs_a.sh / reloaddefs_sfj.sh / reload-run-sfj.sh / reloadcheck_sfj.py stay untouched (queued lists use them).
#
# ROOT CAUSE (evidence C:\KenshiTestRuns\imm26-5090-i3\rows\23-e): rw_chase_sfj read Shay's CURRENT position and teleported him +RW_AWAY_F (120) u in x from there on EVERY chase (ctrl, pre, post),
# and the NPC is teleported to Shay between the chases, so the offsets accumulated: chase_ctrl 121.7 flat, chase_pre 269.0 for 8 samples (Shay landed on a plateau about 240 u higher; the follower
# cannot path to a cliff top: FOLLOW_TICK keeps firing, the NPC stands still), chase_post 295 -> 281. It was not a FOLLOW defect (the follow worked on flat ground in the earlier run).
#
# FIX: the first chase records the ANCHOR P0 = Shay's position (anchor.txt). Every chase then PING-PONGS between P0 and P1 = P0 + RW_AWAY_F in RW_AWAY_DIR (anchor_far.txt, anchor_dir.txt):
# Shay near P0 -> teleport to P1, Shay near P1 -> teleport back to P0, otherwise rc 3 (RL_REASON). So the sequence is P1, P0, P1 and never drifts. After EVERY teleport the landing is VALIDATED
# (landing_<tag>.txt): Shay and the NPC must be within RW_LAND_DY (40) u in height and RW_AWAY_F*0.5 .. *1.6 (a follower may stand 40-60 u from Shay) u apart horizontally. A bad landing of the outbound leg sends Shay back to where he
# stood and tries the next direction from the anchor (RW_AWAY_DIR first, then x -x z -z); all directions bad (or a bad return landing) = rc 3 with RL_REASON "Shay landed N u above/below the NPC
# (cliff)" = the existing SETUP-FAIL path (the row is NOT judged on a cliff). Chase timing, series files (chase_<tag>.txt/.series), follow logs and the checker thresholds are those of sfJ.
# Env: RW_AWAY_F (120) RW_AWAY_DIR (x; first direction tried) RW_CHASE_S (45) RW_LAND_DY (40) RW_ANCHOR_TOL (60 u: how far from P0/P1 Shay may stand at the start of a chase).

sff_pos() {   # sff_pos <shell-quoted name> : "x y z" of a character (stobe-auto where), empty when unreadable
  printf 'stobe-auto where %s </dev/null 2>&1 | head -1\n' "$1" | lt_h 2>&1 | sed -nE 's/.*pos=(-?[0-9.]+),(-?[0-9.]+),(-?[0-9.]+).*/\1 \2 \3/p' | head -1
}
sff_hz() { awk -v a="$1" -v b="$2" -v c="$3" -v d="$4" 'BEGIN{printf "%.1f", sqrt((a-c)^2+(b-d)^2)}'; }     # sff_hz x1 z1 x2 z2
sff_land() {   # sff_land <tag> <label> : validate Shay's landing against the NPC; line to landing_<tag>.txt; rc 0 ok, 1 bad (SFF_DY = signed Shay-minus-NPC height, SFF_HZ)
  local tag="$1" label="$2" away="${RW_AWAY_F:-120}" s n lo hi dy_max="${RW_LAND_DY:-40}" ok
  s=$(sff_pos Shay); n=$(sff_pos "$(rl_q "$RL_NPC_FULL")")
  if [ -z "$s" ] || [ -z "$n" ]; then SFF_DY="?"; SFF_HZ="?"; echo "$label shay='$s' npc='$n' UNREADABLE" >> "$EV/landing_$tag.txt"; return 1; fi
  set -- $s $n
  SFF_HZ=$(sff_hz "$1" "$3" "$4" "$6"); SFF_DY=$(awk -v a="$2" -v b="$5" 'BEGIN{printf "%.1f", a-b}')
  lo=$(awk -v a="$away" 'BEGIN{printf "%.1f", a*0.5}'); hi=$(awk -v a="$away" 'BEGIN{printf "%.1f", a*1.6}')
  ok=$(awk -v h="$SFF_HZ" -v d="$SFF_DY" -v lo="$lo" -v hi="$hi" -v m="$dy_max" 'BEGIN{ad=(d<0)?-d:d; print (h>=lo && h<=hi && ad<=m) ? 1 : 0}')
  echo "$label shay=$s npc=$n hz=$SFF_HZ dy=$SFF_DY band=$lo..$hi dymax=$dy_max $([ "$ok" = 1 ] && echo ok || echo BAD)" >> "$EV/landing_$tag.txt"
  [ "$ok" = 1 ]
}
sff_tp() {   # sff_tp <x> <y> <z> : protect + teleport Shay + HOLD_POSITION, then 2 s settle
  lt_h <<EOT >> "$EV/chase.txt" 2>&1
stobe-auto protect Shay on </dev/null | head -1
stobe-auto teleport Shay $1 $2 $3 </dev/null | head -1 | cut -c1-100
stobe-auto order Shay HOLD_POSITION keep </dev/null | head -1 | cut -c1-80
EOT
  rw_sleep 2
}
sff_off() {   # sff_off <dir> <x> <z> <away> : "tx tz" = the point <away> u from (x,z) in <dir>
  case "$1" in
    -x) awk -v v="$2" -v w="$3" -v d="$4" 'BEGIN{printf "%.0f %.0f", v-d, w}';;
    z)  awk -v v="$2" -v w="$3" -v d="$4" 'BEGIN{printf "%.0f %.0f", v, w+d}';;
    -z) awk -v v="$2" -v w="$3" -v d="$4" 'BEGIN{printf "%.0f %.0f", v, w-d}';;
    *)  awk -v v="$2" -v w="$3" -v d="$4" 'BEGIN{printf "%.0f %.0f", v+d, w}';;
  esac
}
rw_chase_sfj() { rw_chase_sff "$@"; }   # sfJ's rd_23e calls rw_chase_sfj: same name, anchor ping-pong body
rw_chase_sff() {   # rw_chase_sff <tag>: Shay ping-pongs P0 <-> P1 (validated landing), held; speed 3 for RW_CHASE_S (45) s, distance sampled every 5 s; chase_<tag>.txt = "dist_before|dist_after", chase_<tag>.series
  local tag="$1" away="${RW_AWAY_F:-120}" tol="${RW_ANCHOR_TOL:-60}" S sx sy sz ax ay az fx fy fz h0 h1 mode dirs d tx tz good="" d0 d1 k steps dd ser
  S=$(sff_pos Shay)
  [ -n "$S" ] || { RL_REASON="cannot read Shay's position (stobe-auto where Shay)"; return 3; }
  set -- $S; sx=$1; sy=$2; sz=$3
  [ -s "$EV/anchor.txt" ] || echo "$S" > "$EV/anchor.txt"
  read -r ax ay az < "$EV/anchor.txt"
  h0=$(sff_hz "$sx" "$sz" "$ax" "$az"); h1=""
  if [ -s "$EV/anchor_far.txt" ]; then read -r fx fy fz < "$EV/anchor_far.txt"; h1=$(sff_hz "$sx" "$sz" "$fx" "$fz"); fi
  if awk -v h="$h0" -v t="$tol" 'BEGIN{exit !(h+0<=t+0)}'; then mode=out
  elif [ -n "$h1" ] && awk -v h="$h1" -v t="$tol" 'BEGIN{exit !(h+0<=t+0)}'; then mode=back
  else RL_REASON="Shay stands ${h0} u from the anchor and ${h1:-n/a} u from the far point (>${tol}): the ping-pong chase needs him at P0/P1 (anchor.txt)"; return 3; fi
  echo "$tag mode=$mode shay=$S anchor=$ax $ay $az far=${fx:-} ${fy:-} ${fz:-} h0=$h0 h1=${h1:-n/a}" >> "$EV/landing_$tag.txt"
  if [ "$mode" = back ]; then                                    # P1 -> P0: one known-good target, validated
    sff_tp "$ax" "$ay" "$az"
    sff_land "$tag" "back" || { RL_REASON="Shay landed ${SFF_DY} u above(+)/below(-) the NPC at the anchor, ${SFF_HZ} u away horizontally (cliff/bad landing, landing_$tag.txt): set RW_AWAY_DIR / RW_AWAY_F"; return 3; }
  else                                                           # P0 -> P1: try the known direction first, then the others
    dirs="$(cat "$EV/anchor_dir.txt" 2>/dev/null) ${RW_AWAY_DIR:-x} x -x z -z"
    for d in $(echo $dirs | tr ' ' '\n' | awk '!s[$0]++'); do
      set -- $(sff_off "$d" "$ax" "$az" "$away"); tx=$1; tz=$2
      sff_tp "$tx" "$ay" "$tz"
      if sff_land "$tag" "out dir=$d target=$tx $ay $tz"; then good="$d"; echo "$tx $ay $tz" > "$EV/anchor_far.txt"; echo "$d" > "$EV/anchor_dir.txt"; break; fi
      sff_tp "$sx" "$sy" "$sz"                                   # bad landing: back to where he stood, next direction
    done
    [ -n "$good" ] || { RL_REASON="Shay landed ${SFF_DY} u above(+)/below(-) the NPC in every direction (x -x z -z; last hz=${SFF_HZ}; cliff, landing_$tag.txt): set RW_AWAY_F smaller or move the scene"; return 3; }
  fi
  rw_sleep 0; d0=$(rw_dist); ser="$d0"
  lt_h <<EOT >> "$EV/chase.txt" 2>&1
stobe-auto speed 3 </dev/null >/dev/null
EOT
  steps=$(( ${RW_CHASE_S:-45} / 5 )); [ "$steps" -ge 1 ] || steps=1
  for k in $(seq 1 "$steps"); do
    lt_h <<EOT >> "$EV/chase.txt" 2>&1
sleep 5
EOT
    dd=$(rw_dist); ser="$ser $dd"
  done
  lt_h <<EOT >> "$EV/chase.txt" 2>&1
stobe-auto speed 0.5 </dev/null >/dev/null
EOT
  d1=$(rw_dist); echo "$d0|$d1" > "$EV/chase_$tag.txt"; echo "$ser" > "$EV/chase_$tag.series"
  return 0
}
