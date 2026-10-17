#!/usr/bin/env bash
# tripdefs_23a2.sh (imm26-fix23arecipe, ticket 23-a SETUP-FAIL "needs: recipe", evidence op35 a1/a2/a3): recipe v3 for row 23-a. Sourced by unblockrun_23a2.sh AFTER tripdefs_sfk.sh and
# tripdefs_23acheck.sh; it REDEFINES rd_23a_sfk only (tripdefs_23acheck's rd_23a wrapper still adds s3/plugin_out.txt + the s4 following turn). tripdefs_sfk.sh, tripdefs_23acheck.sh,
# tripdefs.sh, rowcheck_trip.py, tripscen.py and unblockrun_23acheck.sh are NOT edited (the verdict is still the option-A c_23a, unchanged).
# Why (3 live attempts, none a product verdict):
#   a1  the game cleared the native order 0.4 s after the assignment (NATIVE_TRAVEL_ORDER_ENDED, phase=failed native_order_ended_before_goal) 9 s BEFORE the runner's stage teleport;
#       the runner then walked 30 cycles for nothing.                       -> a2_native_live: START + no ORDER_ENDED/failed + OBS orders>=1, checked after the accept AND again right before the stage.
#   a2  the stage teleport from lane-setup's quiet spot (y~1530) put Cind in the air (y=1570.8 vs goal y=328.8); she fell, orders=0, agreement FAILED. Green runs staged from the
#       Hub origin (y~960) and landed at y=329.2 with orders=1.             -> a2_anchor (Shay+squad to the Hub origin BEFORE s1; SETUP-FAIL if y is not in the Hub band) and a pre-stage y check
#                                                                              and a post-stage landing check (SETUP-FAIL before walking when she is in the air).
#   a3  the LLM left the agreement PROPOSED (no OWNED_TRAVEL); the runner walked 30 cycles anyway.  -> accept re-say (steps s2, s2b, s2c; TRIP_A2_ACCEPT_TRIES, default 3) judged on the DB's newest
#       travel_agreement status, then SETUP-FAIL early (no staging, no walk) naming the reason.
#   lane-setup.sh --with Cind --teleport does not move 'Cind [Hungry Bandit]': a2_anchor teleports Shay, then Cind/Malzin onto Shay by full name (the pattern tr_quiet uses).
# Every guard is one line tagged `# a2:guard-<name>`; unblock_23a2_selftest.sh deletes each in turn (mutation test) and requires the scenario that needs it to change.
# fix23agate2 (op38 21:34): 'Take me to Squin.' made the agreement's gate the Squin gate (-62461,328.8,16346.8), 14.5 km away, so the 400 u stage still teleported Cind AND Shay there and Shay was attacked/KO'd (shay_guard).
#   The recipe now ASKS FOR A NEARBY PLACE (A2_LOCAL=1 default; off when --dest/TRIP_DEST or --gate/TRIP_GATE is given, or A2_LOCAL=0), judges every PROPOSED reply with a2_gate_local (gate within A2_NO_STAGE_MAX of Cind,
#   `# a2:guard-local-dest`), asks again (s1b, s1c) when the LLM named a far place, and SETUP-FAILs BEFORE the accept/stage when all three asks proposed a far place. A local gate takes the no-stage path (gate_dist ~200-500).
# Env: TRIP_HUB ("-53200 960 4860") A2_HUB_DY (120: allowed |y - hub y|) TRIP_A2_ACCEPT_TRIES (3, max 3) A2_NATIVE_TRIES (8 probes x 2.5 s) A2_STAGE_DY (200: allowed Cind y above the gate
#      y after the stage teleport; 0 disables) A2_STAGE_MOVED_SKIP (1000: skip that landing check when the stage teleport moved x/z more than this, the y read is stale, op37; a huge value = always check)
#      A2_NO_STAGE_MAX (1500: no stage teleport when the gate is within this many units of Cind, the live order walks the mesh route, inv23a/fix23agate; only the 14.7 km Squin gate stages) A2_ANCHOR=0 (skip the Hub anchor) plus the sfK2 knobs (SFK_23A_BACK/SPEED/TRIES/WAIT, TRIP_GATE). Evidence: a2_setup.txt, a2_native_*.txt.
declare -F rd_23a_sfk >/dev/null || { echo "tripdefs_23a2.sh: source tripdefs_sfk.sh and tripdefs_23acheck.sh first" >&2; return 1 2>/dev/null || exit 1; }
declare -F uf_walk_stage >/dev/null || . "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/unblockdefs_f.sh"

a2_log() { echo "$(date +%H:%M:%S) $*" >> "$EV/a2_setup.txt"; }
a2_sleep() { [ -n "${KAH_ROW_FAKE:-}" ] || sleep "$1"; }
a2_pos() {   # a2_pos <quoted-name> : "x y z" of the actor (stobe-auto where), empty when unknown
  printf 'stobe-auto where %s </dev/null 2>&1 | head -1 | cut -c1-220 # a2:where\n' "$1" | lt_h 2>&1 | head -1 | sed -nE 's/.*pos=(-?[0-9.]+),(-?[0-9.]+),(-?[0-9.]+).*/\1 \2 \3/p' | head -1
}
a2_in_band() {   # a2_in_band <y> <centre> <dy> : rc 0 when |y-centre| <= dy
  awk -v y="${1:-x}" -v c="$2" -v d="$3" 'BEGIN{ if (y !~ /^-?[0-9.]+$/) exit 1; v = y - c; if (v < 0) v = -v; exit (v <= d) ? 0 : 1 }'
}
a2_anchor() {   # Shay and the squad on the Hub origin before s1 (nothing is ordered yet, so a teleport cannot disturb a trip). rc 3 = SETUP-FAIL
  [ "${A2_ANCHOR:-1}" = 0 ] && return 0
  local hub hy dy n pc ps yc ys k
  hub="${TRIP_HUB:--53200 960 4860}"; hy=$(echo "$hub" | awk '{print $2}'); dy="${A2_HUB_DY:-120}"; n=$(rl_q "$RL_NPC_FULL")
  for k in 1 2; do
    pc=$(a2_pos "$n"); ps=$(a2_pos Shay); yc=$(echo "$pc" | awk '{print $2}'); ys=$(echo "$ps" | awk '{print $2}')
    a2_log "anchor try $k: Cind=[$pc] Shay=[$ps] hub=[$hub] band=$hy+-$dy"
    if a2_in_band "$yc" "$hy" "$dy" && a2_in_band "$ys" "$hy" "$dy"; then a2_log "anchor OK"; return 0; fi
    [ "$k" = 2 ] && break
    lt_h <<EOT >> "$EV/a2_anchor.txt" 2>&1
stobe-auto teleport Shay $hub </dev/null | head -1 | cut -c1-140
stobe-auto teleport $n Shay </dev/null | head -1 | cut -c1-140
stobe-auto teleport Malzin Shay </dev/null | head -1 | cut -c1-140
stobe-auto health Shay 100 </dev/null >/dev/null 2>&1
EOT
    a2_sleep 3
  done
  RL_REASON="squad is not on the Hub origin (Cind y='${yc:-?}' Shay y='${ys:-?}', wanted $hy +-$dy at $hub) after one hand teleport: a stage teleport from another height drops the NPC from the air (op35 a2: quiet spot y~1530 -> y=1570.8, order lost); needs: recipe/lane (teleport the squad to the Hub by hand, see $EV/a2_anchor.txt)"
  return 3
}
a2_agr_status() {   # a2_agr_status <polls> : newest travel_agreement "STATUS|phase" (polls every 2 s until ACCEPTED/terminal or the polls run out)
  local k s=""
  for k in $(seq 1 "${1:-1}"); do
    s=$(lt_sql "select coalesce(j->>'status','')||'|'||coalesce(j->'execution'->>'phase','') from (select substring(data from position('{' in data))::json as j from eventlog where type='travel_agreement' order by rowid desc limit 1) t /* a2:agr */" 2>&1 | head -1 | tr -d '\r')
    case "$s" in ACCEPTED*|FAILED*|ENDED*|CANCELLED*|COMPLETED*) break;; esac
    [ "$k" -lt "${1:-1}" ] && a2_sleep 2
  done
  echo "$s"
}
a2_native_live() {   # a2_native_live <N0> <tag> : the native order of THIS trip is alive. rc 0 = START seen, no ORDER_ENDED/failed, newest OBS orders>=1; rc 3 = RL_REASON
  local n0="$1" tag="$2" k out start ended obs
  for k in $(seq 1 "${A2_NATIVE_TRIES:-8}"); do
    out=$(lt_h <<EOT 2>&1
S=\$(tail -n +$(( n0 + 1 )) $LT_STOBELOG 2>/dev/null) # a2:nlog
echo "START: \$(printf '%s\n' "\$S" | grep -a -c NATIVE_TRAVEL_START)"
echo "ENDED: \$(printf '%s\n' "\$S" | grep -a -m1 -E 'NATIVE_TRAVEL_ORDER_ENDED|NATIVE_TRAVEL: .*phase=failed' | cut -c1-300)"
echo "OBS: \$(printf '%s\n' "\$S" | grep -a NATIVE_TRAVEL_OBS | tail -1 | cut -c1-300)"
EOT
)
    printf '%s probe %s\n%s\n' "$tag" "$k" "$out" >> "$EV/a2_native_$tag.txt"
    start=$(printf '%s\n' "$out" | sed -n 's/^START: *//p' | head -1 | tr -dc 0-9); start=${start:-0}
    ended=$(printf '%s\n' "$out" | sed -n 's/^ENDED: *//p' | head -1)
    obs=$(printf '%s\n' "$out" | sed -n 's/^OBS: *//p' | head -1)
    if [ -n "$ended" ]; then   # a2:guard-native-ended
      RL_REASON="[$tag] the native order of the trip was cleared by the game before the stage teleport (op35 a1): ${ended:0:200}; needs: recipe/lane (see $EV/a2_native_$tag.txt; a brawl or another order near the Hub drops it, rerun after a quiet scene)"
      return 3
    fi
    if [ "$start" -gt 0 ] && printf '%s' "$obs" | grep -qE 'orders=[1-9]'; then a2_log "native live [$tag] probe $k: START=$start obs=${obs:0:120}"; return 0; fi   # a2:guard-native-orders
    a2_sleep 2.5
  done
  if [ "$start" -gt 0 ]; then
    RL_REASON="[$tag] NATIVE_TRAVEL_START was logged but no NATIVE_TRAVEL_OBS with orders>=1 within ${A2_NATIVE_TRIES:-8} probes (last OBS: '${obs:0:140}'): the order is not live; needs: recipe/lane (see $EV/a2_native_$tag.txt)"
  else
    RL_REASON="[$tag] no NATIVE_TRAVEL_START in the lane stobe.log after the accept (agreement ACCEPTED but the native order never started: old DLL, or the accept was not executed; see $EV/a2_native_$tag.txt)"
  fi
  return 3
}
a2_gate_local() {   # rc 0 when the newest agreement's destination_point is within A2_NO_STAGE_MAX (1500) planar units of Cind; sets A2_GATE_MSG. An unreadable gate/position counts as far (fix23agate2: the LLM named Squin, 14.5 km away)
  local g p d
  g=$(sfk_gate); p=$(a2_pos "$(rl_q "$RL_NPC_FULL")")
  d=$(echo "$p $g" | awk 'NF>=6{dx=$1-$4; dz=$3-$6; printf "%.0f", sqrt(dx*dx+dz*dz)}')
  A2_GATE_MSG="gate [${g:-?}] is ${d:-?} u from Cind [${p:-?}]"
  [ -n "$d" ] && [ "$d" -le "${A2_NO_STAGE_MAX:-1500}" ]
}
a2_trip_setup() {   # s1 propose (three openers), s2 accept with bounded re-say while the DB agreement is still PROPOSED, then native-live assert. Sets A2_N0 (log line before s1)
  local lines steps i tries st s2b=0
  A2_N0=$(echo "wc -l < $LT_STOBELOG" | lt_h | tail -1 | tr -dc 0-9); A2_N0=${A2_N0:-0}
  ROW_NATIVE=1
  local ask1 ask2 ask3 want_local=0 step txt good=0 far=0 farmsg=""
  ask1="Take me to $TR_DEST."; ask2="Would you lead me to $TR_DEST?"; ask3="Walk with me to $TR_DEST."
  lines=("${TRIP_ACCEPT:-I'm fine. Yes, let's go.}" "Yes, I accept. Please lead the way to $TR_DEST now." "I accept your offer. Let's go to $TR_DEST."); steps=(2 2b 2c)
  if [ "${A2_LOCAL:-1}" != 0 ] && [ -z "${TRIP_DEST:-}" ] && [ -z "${TRIP_GATE:-}" ]; then   # fix23agate2: ask for a NEARBY place so the gate is local (no 14 km stage into a town that attacks Shay)
    want_local=1
    ask1="Cind, take me somewhere close by, just a short walk from here."; ask2="Lead me to the nearest landmark you can see from here."; ask3="Walk with me to a spot right outside, nearby."
    lines[1]="Yes, I accept. Please lead the way there now."; lines[2]="I accept your offer. Let's go there."
  fi
  a2_log "openers: local=$want_local (A2_LOCAL=${A2_LOCAL:-1} TRIP_DEST='${TRIP_DEST:-}' TRIP_GATE='${TRIP_GATE:-}')"
  for step in 1 1b 1c; do
    case "$step" in 1) txt="$ask1";; 1b) txt="$ask2";; *) txt="$ask3";; esac
    rl_say "$step" "$txt" || return $?
    [ "$step" = 1 ] && { tr_prompt_guard 1 || return $?; }
    tr_has "s$step" PROPOSED || continue
    if [ "$want_local" = 1 ] && ! a2_gate_local; then far=1; farmsg="$A2_GATE_MSG"; a2_log "ask $step: PROPOSED but the destination is far ($A2_GATE_MSG)"; continue; fi   # a2:guard-local-dest
    good=1; break
  done
  if [ "$good" != 1 ] && [ "$far" = 1 ]; then RL_REASON="the LLM proposed a FAR destination in every local ask (s1/s1b/s1c; last: $farmsg, limit ${A2_NO_STAGE_MAX:-1500} u): accepting would stage a 14 km teleport into a town that attacks Shay (fix23agate2); not a product verdict; needs: recipe/LLM (rerun, or --gate 'x y z' of a landmark near the Hub; see $EV/s1b/reply.txt)"; return 3; fi
  [ "$good" = 1 ] || { RL_REASON="no PROPOSED travel_agreement row after three asks (s1/s1b/s1c): an accept would be refused ('requires an existing concrete offer'); needs: recipe (see s1b/reply.txt)"; return 3; }
  tries="${TRIP_A2_ACCEPT_TRIES:-3}"; [ "$tries" -gt 3 ] && tries=3; [ "$tries" -lt 1 ] && tries=1
  for (( i = 0; i < tries; i++ )); do
    rl_say "${steps[i]}" "${lines[i]}" || return $?
    st=$(a2_agr_status 3); a2_log "accept step ${steps[i]}: agreement=[$st]"
    case "$st" in ACCEPTED*) break;; PROPOSED*|"") ;; *) break;; esac   # a2:guard-resay
  done
  case "$st" in
    ACCEPTED*)   # the option-A checker only reads ACCEPTED rows from s1/s1b/s2/s2b (rowcheck_trip.STEPS): a third-attempt accept (s2c) is mirrored into s2b/ev_full.txt
      if [ "${steps[i]}" = 2c ]; then { echo "# mirrored from s2c/ev_full.txt by tripdefs_23a2.sh (the checker only reads s1/s1b/s2/s2b)"; cat "$EV/s2c/ev_full.txt" 2>/dev/null; } >> "$EV/s2b/ev_full.txt"; a2_log "third-attempt accept mirrored s2c -> s2b/ev_full.txt"; fi;;
    *) RL_REASON="agreement is ${st:-missing} (not ACCEPTED) after $(( i < tries ? i + 1 : tries )) accept line(s) (${steps[*]:0:tries}): the LLM did not accept the trip (op35 a3: PROPOSED, no OWNED_TRAVEL); not a product verdict; needs: recipe/LLM (see $EV/s2/reply.txt); nothing was staged"; return 3;;   # a2:guard-accepted
  esac
  if ! a2_native_live "$A2_N0" setup; then
    if [ "$s2b" = 0 ] && printf '%s' "$RL_REASON" | grep -q 'no NATIVE_TRAVEL_START'; then   # accepted but never started: one "Lead the way." as tr_trip_setup does, then judge again
      s2b=1; rl_say 2d "Lead the way." || return $?
      a2_native_live "$A2_N0" setup2 || return $?
    else return 3; fi
  fi
  tr_agr agr_trip.txt 4
  return 0
}
a2_stage_walk() {   # a2_stage_walk <quoted-npc> <gate> <back> <speed> <tries> : pre-stage asserts, stage teleport with a landing check, then the walk loop of uf_walk_stage (positive leg). rc 3 = SETUP-FAIL
  local n="$1" g="$2" back="$3" spd="$4" tries="$5" hub hy dy gy p pre y k w d t c f stage gd mv
  hub="${TRIP_HUB:--53200 960 4860}"; hy=$(echo "$hub" | awk '{print $2}'); dy="${A2_HUB_DY:-120}"; gy=$(echo "$g" | awk '{print $2}')
  p=$(a2_pos "$n"); pre="$p"; y=$(echo "$p" | awk '{print $2}'); a2_log "pre-stage Cind=[$p]"
  if [ "${A2_ANCHOR:-1}" != 0 ]; then
    a2_in_band "$y" "$hy" "$dy" || { RL_REASON="Cind is at y='${y:-?}' before the stage teleport, not the Hub band $hy +-$dy (staging from there drops her in the air, op35 a2); needs: recipe/lane (see $EV/a2_setup.txt)"; return 3; }   # a2:guard-ypre
  fi
  a2_native_live "$A2_N0" prestage || return 3   # a2:guard-native-pre-stage
  UF_N0=$(echo "wc -l < $LT_STOBELOG" | lt_h | tail -1 | tr -dc 0-9); UF_N0=${UF_N0:-0}
  gd=$(echo "$pre $g" | awk 'NF>=6{dx=$1-$4; dz=$3-$6; printf "%.0f", sqrt(dx*dx+dz*dz)}')
  if [ -n "$gd" ] && [ "$gd" -le "${A2_NO_STAGE_MAX:-1500}" ]; then   # a2:guard-near-gate
    a2_log "no stage: gate is ${gd} u from Cind (<= ${A2_NO_STAGE_MAX:-1500}); the live order walks the mesh route from the Hub (inv23a: a raw +${back} x teleport landed on an unmeshed hilltop)"
    echo "no-stage gate_dist=$gd" > "$EV/stage.txt"
  else
  stage="$g dist $back"; echo "$stage" > "$EV/stage.txt"
  lt_h <<EOT >> "$EV/stage.txt" 2>&1
stobe-auto teleport $n $stage </dev/null | head -1 | cut -c1-120
stobe-auto teleport Shay $n </dev/null | head -1 | cut -c1-120
EOT
  a2_sleep 2
  p=$(a2_pos "$n"); y=$(echo "$p" | awk '{print $2}'); a2_log "post-stage Cind=[$p] gate_y=$gy"
  mv=$(echo "$pre $p" | awk 'NF>=6{dx=$1-$4; dz=$3-$6; printf "%.0f", sqrt(dx*dx+dz*dz)}')   # planar distance the stage teleport moved her
  if [ "${A2_STAGE_DY:-200}" != 0 ] && [ -n "$gy" ] && [ -n "$y" ] && ! [ "${mv:-0}" -gt "${A2_STAGE_MOVED_SKIP:-1000}" ] && awk -v y="$y" -v g="$gy" -v d="${A2_STAGE_DY:-200}" 'BEGIN{exit (y - g > d) ? 0 : 1}'; then   # a2:guard-air
    RL_REASON="the stage teleport left Cind in the air (y=$y, gate y=$gy, allowed +${A2_STAGE_DY:-200}): she falls and the native order is lost (op35 a2); needs: recipe (stage from the Hub origin, see $EV/a2_setup.txt)"
    UB_WALK_END=SETUP; return 3
  fi
  [ "${mv:-0}" -gt "${A2_STAGE_MOVED_SKIP:-1000}" ] && a2_log "landing check skipped: x/z moved ${mv} u (> ${A2_STAGE_MOVED_SKIP:-1000}), the read y is stale (op37)"
  fi
  lt_h <<EOT >> "$EV/walk.txt" 2>&1
stobe-auto speed $spd </dev/null | head -1
EOT
  UB_WALK_END=TIMEOUT; : > "$EV/walk_progress.txt"
  for k in $(seq 1 "$tries"); do
    w=$(lt_h <<EOT 2>&1 | tail -1
for i in 1 2 3 4 5; do stobe-auto teleport Shay $n </dev/null >/dev/null; sleep 1.5; done
stobe-auto where $n </dev/null | head -1 | cut -c1-140
EOT
)
    d=$(echo "$w" | sed -nE 's/.*pos=(-?[0-9.]+),(-?[0-9.]+),(-?[0-9.]+).*/\1 \3/p' | head -1 | awk -v g="$g" '{split(g,a," "); dx=$1-a[1]; dz=$2-a[3]; printf "%.0f", sqrt(dx*dx+dz*dz)}')
    t=$(uf_terminal); c=0; f=0; [ "$t" = COMPLETED ] && c=1; [ "$t" = FAILED ] && f=1
    echo "$k|$(echo "$w" | cut -c1-100)|${d:-?}|${c}|${f}" >> "$EV/walk_progress.txt"
    [ "$c" = 1 ] && { UB_WALK_END=COMPLETED; break; }
    [ "$f" = 1 ] && { UB_WALK_END=FAILED; break; }
    uf_native_end && { UB_WALK_END=ARRIVED; break; }
  done
  lt_h <<EOT >> "$EV/walk.txt" 2>&1
stobe-auto speed 0.5 </dev/null | head -1
EOT
  return 0
}

rd_23a_sfk() {   # redefines the sfK2 body: anchor -> setup with asserts -> guarded stage + walk -> arrival line (unchanged from tripdefs_sfk.sh)
  tr_prep || return $?
  a2_anchor || return $?   # a2:guard-anchor
  a2_trip_setup || return $?
  local n g i t
  n=$(rl_q "$RL_NPC_FULL"); g=$(sfk_gate)
  [ -n "$g" ] || { RL_REASON="no gate coordinates for '$TR_DEST' (set TRIP_GATE='x y z')"; return 3; }
  echo "$g" > "$EV/gate.txt"
  a2_stage_walk "$n" "$g" "${SFK_23A_BACK:-400}" "${SFK_23A_SPEED:-1}" "${SFK_23A_TRIES:-30}" || return $?
  uf_native_dump native_travel.txt
  printf 'end=%s gate=%s last_progress=%s\n' "$UB_WALK_END" "$g" "$(tail -1 "$EV/walk_progress.txt" 2>/dev/null)" > "$EV/arrival.txt"
  if [ "$UB_WALK_END" = TIMEOUT ]; then
    RL_REASON="no native arrival within ${SFK_23A_TRIES:-30} walk cycles (walk_progress.txt: $(tail -1 "$EV/walk_progress.txt" 2>/dev/null | cut -c1-120)); needs: recipe (raise SFK_23A_TRIES / lower SFK_23A_BACK) or native (no NATIVE_TRAVEL line = old DLL)"
    return 3
  fi
  lt_h <<EOT >> "$EV/walk.txt" 2>&1
stobe-auto teleport Shay $n </dev/null | head -1 | cut -c1-120
EOT
  sfk_shay_guard || return 3
  tr_state state_shay.txt Shay
  rl_say 3 "We're here. Thanks for guiding me." || return $?
  for i in $(seq 1 "$(( ${SFK_23A_WAIT:-60} / 5 ))"); do
    t=$(uf_terminal); [ -n "$t" ] && break
    ub_sleep 5
  done
  tr_state state_after.txt "$RL_NPC_FULL"; tr_agr agr_final.txt 8
}
