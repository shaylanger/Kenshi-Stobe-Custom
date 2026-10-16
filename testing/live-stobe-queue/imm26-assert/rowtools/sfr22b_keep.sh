#!/usr/bin/env bash
# sfr22b_keep.sh (imm26-fix22b, 2026-10-16): CONTINUOUS-PROXIMITY walk stage for row 22-b. NEW file; unblockdefs_f.sh / unblockdefs_f2.sh are NOT edited. Sourced by sfrrun_v4.sh AFTER
# unblockdefs_f2.sh (shadows uf_walk_stage only inside that process).
# Why (4080-i3 op26, 22-b SETUP-FAIL x2): the walk arrived but NATIVE_TRAVEL said participation_qualified=0. Rule = Stobe::Participation::Evidence (ParticipationEvidence.h Sample/Freeze,
#   NativeTravelLifecycle.cpp:99): the player (partner) must stay within 35 u of the NPC at EVERY controller sample (separation>35 => Break(): the window restarts); then at the terminal event the
#   LAST unbroken window needs samples>=4, last-first>=30 game-s, actor_d>=30, partner_d>=30, endpoint_progress>=30 and terminal within 2 game-s of the last sample. The old uf_walk_stage teleported
#   Shay onto the NPC 5x (1.5 s apart) and then ran `where`, two SQL counts and a log grep (several seconds of ssh round trips) with Shay NOT moved while the NPC kept walking:
#   lane stobe.log showed brk_sep=50..54 per walk, last window span 59 s but partner_d 17 / progress 29 (<30) => qualified=0 => the server never got a participation-qualified receipt.
# Here ONE harness call keeps Shay on the NPC every ~0.5-1 s for up to SFK_KEEP_N iterations, checks the native end lines (stobe.log, same regex as unblockdefs_f2.sh) INSIDE that loop every
#   SFK_KEEP_CHK iterations and stops teleporting only after the terminal line (qualification is decided when the terminal line is written), and prints the NPC position every SFK_KEEP_WH iterations.
#   The SQL terminal check runs only between calls. tries = number of calls (default set by sfrrun_v4.sh: 8 calls x ~60-80 s).
# Env: SFK_KEEP_N (80 iterations/call, ~60-80 s) SFK_KEEP_SLEEP (0.5 s between teleports; old recipe 1.5 s: walk_progress.txt of op26 run 2 showed Shay 7-35 u from the NPC 1.5 s after a teleport, i.e. up to ~23 u/s drift, so 1.5 s sat on the 35 u limit) SFK_KEEP_CHK (8) SFK_KEEP_WH (16).
uf_walk_stage() {   # uf_walk_stage <npc-quoted> <gate> <back> <neg 0|1> <gap> <speed> <tries>   (neg is ignored: Shay always rides on the NPC)
  local n="$1" g="$2" back="$3" neg="$4" gap="$5" spd="$6" tries="$7" k c f w d stage t o kn ks kc kw s1
  kn="${SFK_KEEP_N:-80}"; ks="${SFK_KEEP_SLEEP:-0.5}"; kc="${SFK_KEEP_CHK:-8}"; kw="${SFK_KEEP_WH:-16}"
  if [ -n "${TRIP_13C_STAGE:-}" ]; then stage="${TRIP_13C_STAGE} dist 0"; else stage="$g dist $back"; fi
  echo "$stage" > "$EV/stage.txt"
  lt_h <<EOT >> "$EV/stage.txt" 2>&1
stobe-auto teleport $n $stage </dev/null | head -1 | cut -c1-120
EOT
  lt_h <<EOT >> "$EV/stage.txt" 2>&1
stobe-auto teleport Shay $n </dev/null | head -1 | cut -c1-120
EOT
  lt_h <<EOT >> "$EV/walk.txt" 2>&1
stobe-auto speed $spd </dev/null | head -1
EOT
  s1=$(( ${UF_N0:-0} + 1 ))
  UB_WALK_END=TIMEOUT; : > "$EV/walk_progress.txt"
  for k in $(seq 1 "$tries"); do
    o=$(lt_h <<EOT 2>&1
for i in \$(seq 1 $kn); do
  stobe-auto teleport Shay $n </dev/null >/dev/null 2>&1
  sleep $ks
  if [ \$((i % $kw)) = 0 ]; then stobe-auto where $n </dev/null | head -1 | cut -c1-140; fi
  if [ \$((i % $kc)) = 0 ]; then
    E=\$(tail -n +$s1 $LT_STOBELOG 2>/dev/null | grep -a -E "$UF2_END_RE" | grep -av NATIVE_TRAVEL_OBS | head -6 | cut -c1-260) # uf:nend
    if [ -n "\$E" ]; then printf '%s\n' "\$E"; break; fi
  fi
done
stobe-auto where $n </dev/null | head -1 | cut -c1-140
EOT
)
    w=$(printf '%s\n' "$o" | grep -a 'pos=' | tail -1)
    d=$(echo "$w" | sed -nE 's/.*pos=(-?[0-9.]+),(-?[0-9.]+),(-?[0-9.]+).*/\1 \3/p' | head -1 | awk -v g="$g" 'BEGIN{}{split(g,a," "); dx=$1-a[1]; dz=$2-a[3]; printf "%.0f", sqrt(dx*dx+dz*dz)}')
    t=$(uf_terminal)
    c=0; f=0; [ "$t" = COMPLETED ] && c=1; [ "$t" = FAILED ] && f=1
    echo "$k|$(echo "$w" | cut -c1-100)|${d:-?}|${c}|${f}" >> "$EV/walk_progress.txt"
    [ "$c" = 1 ] && { UB_WALK_END=COMPLETED; break; }
    [ "$f" = 1 ] && { UB_WALK_END=FAILED; break; }
    UF2_CLASS=$(printf '%s\n' "$o" | grep -a NATIVE_TRAVEL | grep -av NATIVE_TRAVEL_OBS | uf2_classify)
    [ -z "$UF2_CLASS" ] && uf_native_end   # the in-call grep saw nothing: one more look (also covers a line written during the sql gap)
    if [ -n "$UF2_CLASS" ]; then UB_WALK_END="$UF2_CLASS"; break; fi
  done
  lt_h <<EOT >> "$EV/walk.txt" 2>&1
stobe-auto speed 0.5 </dev/null | head -1
EOT
}
