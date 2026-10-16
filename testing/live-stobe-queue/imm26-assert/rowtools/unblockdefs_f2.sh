#!/usr/bin/env bash
# unblockdefs_f2.sh (imm26-4080-i3op24, 2026-10-16): STRICT native-arrival variant of uf_walk_stage. NEW file; unblockdefs_f.sh is NOT edited. Sourced by sfrrun_v3.sh AFTER sfrdefs.sh
# (shadows uf_native_end / uf_walk_stage only inside that process).
# Why: unblockdefs_f.sh UF_ARRIVE_RE counts NATIVE_TRAVEL_ORDER_ENDED as arrival, so row 22-b run 4 (order ended planar=747 dy=1246 arrived8=0, phase=failed
#   native_order_ended_before_goal) was reported end=ARRIVED. Here the walk ends ARRIVED only on NATIVE_TRAVEL_FINISH phase=completed, NATIVE_TRAVEL phase=completed or
#   NATIVE_TRAVEL_ORDER_ENDED with arrived8=1. NATIVE_TRAVEL(_FINISH) phase=failed, or ORDER_ENDED without arrived8=1, => UB_WALK_END=FAILED. Completed wins when both are seen.
UF2_END_RE='NATIVE_TRAVEL_FINISH|NATIVE_TRAVEL[: ].*phase=(completed|failed)|NATIVE_TRAVEL_ORDER_ENDED'
uf2_classify() {   # uf2_classify <lines on stdin> : prints ARRIVED | FAILED | "" (none yet)
  local l ok=0 bad=0
  while IFS= read -r l; do
    case "$l" in
      *NATIVE_TRAVEL_OBS*) ;;
      *NATIVE_TRAVEL_FINISH*phase=completed*|*NATIVE_TRAVEL:*phase=completed*|*NATIVE_TRAVEL\ *phase=completed*) ok=1;;
      *NATIVE_TRAVEL_ORDER_ENDED*arrived8=1*) ok=1;;
      *NATIVE_TRAVEL_ORDER_ENDED*) bad=1;;
      *NATIVE_TRAVEL_FINISH*phase=failed*|*NATIVE_TRAVEL:*phase=failed*|*NATIVE_TRAVEL\ *phase=failed*) bad=1;;
    esac
  done
  [ $ok = 1 ] && { echo ARRIVED; return 0; }
  [ $bad = 1 ] && { echo FAILED; return 0; }
  echo ""
}
uf_native_end() {   # uf_native_end : sets UF2_CLASS (ARRIVED|FAILED|""); returns 0 when a classified end line exists after UF_N0
  UF2_CLASS=$(printf 'tail -n +%s %s 2>/dev/null | grep -a -E "%s" | grep -av NATIVE_TRAVEL_OBS | head -6 | cut -c1-260 # uf:nend\n' "$(( ${UF_N0:-0} + 1 ))" "$LT_STOBELOG" "$UF2_END_RE" | lt_h 2>&1 | uf2_classify)
  [ -n "$UF2_CLASS" ]
}
uf_walk_stage() {   # same staging/loop as unblockdefs_f.sh uf_walk_stage (TRIP_13C_STAGE honoured), strict native-end classification
  local n="$1" g="$2" back="$3" neg="$4" gap="$5" spd="$6" tries="$7" k c f w d stage nstage t
  if [ -n "${TRIP_13C_STAGE:-}" ]; then stage="${TRIP_13C_STAGE} dist 0"; nstage="${TRIP_13C_STAGE} dist $gap"; else stage="$g dist $back"; nstage="$g dist $(( back + gap ))"; fi
  echo "$stage" > "$EV/stage.txt"
  lt_h <<EOT >> "$EV/stage.txt" 2>&1
stobe-auto teleport $n $stage </dev/null | head -1 | cut -c1-120
EOT
  if [ "$neg" = 1 ]; then
    lt_h <<EOT >> "$EV/stage.txt" 2>&1
stobe-auto teleport Shay $nstage </dev/null | head -1 | cut -c1-120
EOT
  else
    lt_h <<EOT >> "$EV/stage.txt" 2>&1
stobe-auto teleport Shay $n </dev/null | head -1 | cut -c1-120
EOT
  fi
  lt_h <<EOT >> "$EV/walk.txt" 2>&1
stobe-auto speed $spd </dev/null | head -1
EOT
  UB_WALK_END=TIMEOUT; : > "$EV/walk_progress.txt"
  for k in $(seq 1 "$tries"); do
    if [ "$neg" = 1 ]; then ub_sleep 8; w=$(printf 'stobe-auto where %s </dev/null | head -1 | cut -c1-140\n' "$n" | lt_h 2>&1 | head -1)
    else
      w=$(lt_h <<EOT 2>&1 | tail -1
for i in 1 2 3 4 5; do stobe-auto teleport Shay $n </dev/null >/dev/null; sleep 1.5; done
stobe-auto where $n </dev/null | head -1 | cut -c1-140
EOT
)
    fi
    d=$(echo "$w" | sed -nE 's/.*pos=(-?[0-9.]+),(-?[0-9.]+),(-?[0-9.]+).*/\1 \3/p' | head -1 | awk -v g="$g" 'BEGIN{}{split(g,a," "); dx=$1-a[1]; dz=$2-a[3]; printf "%.0f", sqrt(dx*dx+dz*dz)}')
    t=$(uf_terminal)
    c=0; f=0; [ "$t" = COMPLETED ] && c=1; [ "$t" = FAILED ] && f=1
    echo "$k|$(echo "$w" | cut -c1-100)|${d:-?}|${c}|${f}" >> "$EV/walk_progress.txt"
    [ "$c" = 1 ] && { UB_WALK_END=COMPLETED; break; }
    [ "$f" = 1 ] && { UB_WALK_END=FAILED; break; }
    if uf_native_end; then UB_WALK_END="$UF2_CLASS"; break; fi
  done
  lt_h <<EOT >> "$EV/walk.txt" 2>&1
stobe-auto speed 0.5 </dev/null | head -1
EOT
}
