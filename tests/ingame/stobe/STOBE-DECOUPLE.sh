#!/usr/bin/env bash
# id: STOBE-DECOUPLE
# covers: the KenshiFP -> Stobe decoupling (Stobe DFADCCF6+, KenshiFP 97A469B5+): goal code now runs in Stobe.dll
#   DC1 log:       stobe_goals.log is written this session; KenshiFP.log has no goal/action/panel lines any more
#   DC2 panel:     stobe_goals.log `GOAL_PANEL created`, no `GOAL_LABEL faulted` / `GOAL_PANEL ... disabled`
#   DC3 interrupt: a fresh lifelike_interrupt.flag is consumed (file gone) + `lifelike danger preempted`
#   DC4 stale:     a flag 60 s old is dropped: `lifelike interrupt flag stale`
#   DC5 hold:      stobe_action.request `<mate>\tHOLD_POSITION` -> ACTION_BRIDGE result=ok, mate teleported 200 units (positions are in dm: ~20 m) away stays >150
#   DC6 bodyguard: stobe_action.request `<mate>\tBODYGUARD\t<player>` -> `squad->squad: using FOLLOW_PLAYER_ORDER`,
#                  result=ok, mate (started next to the player, who then walks 250 away) comes within 60 units or chases a second walk (game state)
#   DC7 fp truce:  (not in the default set; after an FP manual-combat test) KenshiFP.log `truce bridge: ... resolved`
# fixture: any squad save on a kah-* copy (default Shay + Malzin; PLAYER/MATE env for others); works with KenshiFP absent
# usage: [PLAYER=..] [MATE=..] STOBE-DECOUPLE.sh [rows]   rows = space list of DC1..DC6 (default all)
set -u
. "$(dirname "$0")/stobe-fight-lib.sh"
MODS=/mnt/d/Steam/steamapps/common/Kenshi/RE_Kenshi/mods/Stobe
KFPLOG=/mnt/d/Steam/steamapps/common/Kenshi/KenshiFP.log
ROWS="${*:-DC1 DC2 DC3 DC4 DC5 DC6}"
want() { case " $ROWS " in *" $1 "*) return 0 ;; esac; return 1; }
BASE_G=$(grep -a -c "" "$KFP" 2>/dev/null || echo 0)
since_goals() { tail -n +"$((BASE_G + 1))" "$KFP"; }   # +1: line BASE_G itself is old
# wait_goals <secs> <regex>: poll stobe_goals.log (new lines only) for a line
wait_goals() { local t=$(( $(date +%s) + $1 )); until since_goals | grep -a -q -E "$2"; do [ "$(date +%s)" -ge "$t" ] && return 1; sleep 1; done; }
serial_of() { stobe-auto where "$1" 2>/dev/null | grep -oE '#[0-9]+' | head -1 | tr -d '#'; }
# dist_of <npc>: distance to PLAYER from both `where` pos= fields (where's own dist= is from the camera)
pos_of() { stobe-auto where "$1" 2>/dev/null | grep -oE 'pos=[-0-9.,]+' | head -1 | cut -d= -f2; }
dist_of() { local a b; a=$(pos_of "$1"); b=$(pos_of "$PLAYER"); [ -n "$a" ] && [ -n "$b" ] || return 0
  awk -v a="$a" -v b="$b" 'BEGIN{split(a,p,",");split(b,q,",");printf "%d\n", sqrt((p[1]-q[1])^2+(p[2]-q[2])^2+(p[3]-q[3])^2)}'; }
trap 'stobe-auto speed 1 >/dev/null 2>&1' EXIT
preflight DC "$PLAYER" "$MATE"

if want DC1; then
  [ -s "$KFP" ] || verdict DC1 "FAIL stobe_goals.log missing/empty"
  if [ -s "$KFP" ]; then
    n=$(grep -a -c "" "$KFP"); old=0
    [ -f "$KFPLOG" ] && old=$(grep -a -c -E "WORK_GOAL|TASK_GOAL|ACTION_BRIDGE|GOAL_PANEL|BUY_FALLBACK|lifelike" "$KFPLOG")
    if [ "$old" -eq 0 ]; then verdict DC1 "PASS stobe_goals.log lines=$n, KenshiFP.log goal lines=0"
    else verdict DC1 "FAIL KenshiFP.log still has $old goal/action lines: $(grep -a -E "WORK_GOAL|ACTION_BRIDGE|GOAL_PANEL" "$KFPLOG" | tail -1 | cut -c1-120)"; fi
  fi
fi

if want DC2; then
  t=$(( $(date +%s) + 60 ))
  until grep -a -q "GOAL_PANEL created" "$KFP" 2>/dev/null || [ "$(date +%s)" -ge "$t" ]; do sleep 2; done
  c=$(grep -a "GOAL_PANEL created" "$KFP" | tail -1 | sed -E 's/.*GOAL_PANEL //' | cut -c1-80)
  bad=$(grep -a -E "GOAL_LABEL faulted|GOAL_PANEL .*disabled" "$KFP" | tail -1 | cut -c1-120)
  if [ -n "$c" ] && [ -z "$bad" ]; then verdict DC2 "PASS GOAL_PANEL $c"
  else verdict DC2 "FAIL panel=[$c] fault=[$bad]"; fi
fi

if want DC3; then
  stobe-auto speed 1 >/dev/null
  printf 'danger\n' > "$MODS/lifelike_interrupt.flag"
  if wait_goals 10 "lifelike danger preempted"; then
    if [ -e "$MODS/lifelike_interrupt.flag" ]; then verdict DC3 "FAIL preempt logged but flag file still there"
    else verdict DC3 "PASS flag consumed, $(since_goals | grep -a 'lifelike danger preempted' | tail -1 | sed -E 's/.*\] //' | cut -c1-80)"; fi
  else verdict DC3 "FAIL no preempt line in 10 s, flag_present=$([ -e "$MODS/lifelike_interrupt.flag" ] && echo 1 || echo 0)"; rm -f "$MODS/lifelike_interrupt.flag"; fi
fi

if want DC4; then
  BASE_G=$(grep -a -c "" "$KFP")
  printf 'danger\n' > "$MODS/lifelike_interrupt.flag"; touch -d "60 seconds ago" "$MODS/lifelike_interrupt.flag"
  if wait_goals 10 "lifelike interrupt flag stale"; then
    pre=$(since_goals | grep -a -c "lifelike danger preempted")
    if [ "$pre" -eq 0 ]; then verdict DC4 "PASS $(since_goals | grep -a 'flag stale' | tail -1 | sed -E 's/.*\] //' | cut -c1-80)"
    else verdict DC4 "FAIL stale flag also preempted"; fi
  else verdict DC4 "FAIL no stale line in 10 s"; rm -f "$MODS/lifelike_interrupt.flag"; fi
fi

if want DC7; then   # run after an FP manual-combat test (KenshiFP 661A87A8+): its aim path asks Stobe for the truce
  r=$(grep -a "truce bridge: StobeFightTruceActive resolved" "$KFPLOG" 2>/dev/null | tail -1)
  if [ -n "$r" ]; then verdict DC7 "PASS KenshiFP.log truce bridge resolved ($(grep -a -c 'truce bridge: active=' "$KFPLOG") edges)"
  else verdict DC7 "FAIL KenshiFP.log has no truce bridge resolved line (fp aim lines=$(grep -a -c '\[combat\]' "$KFPLOG" 2>/dev/null))"; fi
fi

if want DC5 || want DC6; then
  ms=$(serial_of "$MATE"); ps=$(serial_of "$PLAYER")
  [ -n "$ms" ] && [ -n "$ps" ] || setup_fail DC5 "no serials mate=$ms player=$ps"
  stobe-auto speed 1 >/dev/null
fi

if want DC5; then
  BASE_G=$(grep -a -c "" "$KFP")
  printf '%s\tHOLD_POSITION\n' "$ms" > "$MODS/stobe_action.request"
  if wait_goals 10 "ACTION_BRIDGE command=HOLD_POSITION actor=$ms .*result=ok"; then
    stobe-auto teleport "$MATE" "$PLAYER" dist 200 | grep -oE "moved=[01]"
    sleep 15; d=$(dist_of "$MATE")
    if [ -n "$d" ] && [ "$d" -gt 150 ]; then verdict DC5 "PASS HOLD_POSITION result=ok, mate stayed at dist=$d after 15 s"
    else verdict DC5 "FAIL HOLD_POSITION ok but mate dist=$d after 15 s (did not hold)"; fi
  else verdict DC5 "FAIL no ACTION_BRIDGE ok: $(since_goals | grep -a ACTION_BRIDGE | tail -1 | cut -c1-140)"; fi
fi

if want DC6; then
  # m49 (dec-5090-4/5): teleports put PLAYER on a spot 49 dm above the mate (roof/cliff, harness.log y 690.6 vs 641.7):
  # neither the Stobe follow nor the game's own FOLLOW_PLAYER_ORDER could path there. Now the mate starts next to the
  # player and the player WALKS away (walktime: a navmesh move order, so the follower has a reachable path).
  # walk_away <dist>: PLAYER runs <dist> units along the first axis that works; WAX = that axis (kept for the second walk)
  walk_away() { local ax r; for ax in ${WAX:-+x -x +z -z}; do r=$(stobe-auto walktime "$PLAYER" "$1" "$ax" run 2>&1)
      log "DC6 walktime $1 $ax: $(cut -c1-140 <<<"$r")"; grep -q ' walked ' <<<"$r" && { WAX=$ax; return 0; }; done; return 1; }
  stobe-auto teleport "$MATE" "$PLAYER" dist 10 >/dev/null; sleep 2
  WAX=""; walk_away 250 || setup_fail DC6 "$PLAYER could not walk 250 along any axis"
  sleep 2; d0=$(dist_of "$MATE")
  BASE_G=$(grep -a -c "" "$KFP")
  printf '%s\tBODYGUARD\t%s\n' "$ms" "$ps" > "$MODS/stobe_action.request"
  if wait_goals 10 "ACTION_BRIDGE command=BODYGUARD actor=$ms .*result=ok"; then
    sw=$(since_goals | grep -a -c "squad->squad: using FOLLOW_PLAYER_ORDER")
    # closes_in <secs> <max>: poll until the mate is within <max> dm of PLAYER (d = last distance)
    closes_in() { local t=$(( $(date +%s) + $1 )); while [ "$(date +%s)" -lt "$t" ]; do d=$(dist_of "$MATE"); [ -n "$d" ] && [ "$d" -le "$2" ] && return 0; log "DC6 dist=$d (want <=$2)"; sleep 3; done; return 1; }
    d=$d0; how=""; d1=""
    if closes_in 45 60; then how="closed at rest $d0 -> $d"
    else
      # a follower must at least chase a moving leader: PLAYER walks 250 further, want her >=150 closer than right after
      walk_away 250 && { d1=$(dist_of "$MATE"); closes_in 60 $(( ${d1:-400} - 150 )) && how="followed the walking leader $d1 -> $d (at rest stayed $d0)"; }
    fi
    if [ "$sw" -ge 1 ] && [ -n "$how" ]; then verdict DC6 "PASS BODYGUARD->FOLLOW_PLAYER_ORDER result=ok, $how"
    else
      # control: the game's own follow order, to tell a Stobe dispatch bug from game follow behaviour
      stobe-auto order "$MATE" FOLLOW_PLAYER_ORDER target "$PLAYER" >/dev/null; dc0=$(dist_of "$MATE")
      closes_in 60 $(( ${dc0:-400} - 150 )) && ctl="control harness FOLLOW_PLAYER_ORDER moved her ${dc0} -> $d (Stobe dispatch bug)" || ctl="control harness FOLLOW_PLAYER_ORDER also did not move her ${dc0} -> $d"
      cm=$(stobe-auto combatmode "$MATE" 2>/dev/null | grep -oE "(block|hold|passive)=[^ ]*" | tr '\n' ' ')
      verdict DC6 "FAIL follow_switch=$sw axis=$WAX mate dist $d0 -> ${d1:-?} -> stayed; $ctl; mate combatmode: ${cm% }"; fi
  else verdict DC6 "FAIL no ACTION_BRIDGE ok: $(since_goals | grep -a ACTION_BRIDGE | tail -1 | cut -c1-140)"; fi
fi
