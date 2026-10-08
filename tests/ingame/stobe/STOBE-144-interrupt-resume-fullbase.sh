#!/usr/bin/env bash
# id: STOBE-144-interrupt-resume-fullbase
# covers: items 137, 138, 139, 141, 142, 144 (Shay's 2026-10-07 play, compound: the way he hit them)
#   140      goal panel moved above the TownPanel in her own outpost (stobe_goals.log line)
#   137      "Hey <mate> can you make me 1 bread?" -> a Bread work goal (no refusal); Stobe's
#            stobe_production_catalog.txt has the bread chain (P line with output Bread)
#   144-fight  goal running -> a raider fights her -> raider KO'd -> the SAME goal id is ACTIVE again and moving
#              (current step changes), no second Bread goal
#   138      follow me -> "resume your task" -> stobe_goals.log `WORK_GOAL resume id=<same id>`, still one live goal
#   144-pause  "pause your work" -> PAUSED; "resume your work" -> ACTIVE, same id
#   144-switch selection switched to the mate and back: same goal still ACTIVE; "get to work" (the m51 duplicate
#              trigger) adds no second live Bread goal
#   139-cancel "cancel the bread" -> CANCELLED and her job count back to the start value (every job the goal added removed)
#   139-clear  two goals + one manual job, "clear all your tasks, goals and jobs" -> no live goal, GOAL_CLEARJOBS line, jobs=0
#   141      spar: "let's spar, attack me" -> she fights <player>; "enough, stop" -> stobe.log `spar rejoin ... in_faction_after=1`
#            (NEG_TEST_INJECT gives her reply Attack@<player>; row 141-live, not default, = same without injection)
#   142      <player> hurt, she has a medkit: "patch me up" -> stobe_goals.log `FIRST_AID verify ... result=healed|treating`
# fixture: Testing-Save-Full-Base (copy kah-fullbase); squad Beaks + Avarek. reset: fresh load of the copy
# needs: Stobe 8AF6F9B5+ (m52), StobeServer 331f845+, harness with jobs/clearjobs/protect/attack/ko/spawn
# usage: [PLAYER=Beaks] [MATE=Avarek] [ROWS="137 140 fight 138 pause switch cancel clear 143 141 142"] STOBE-144-interrupt-resume-fullbase.sh
# output: one `RESULT <row> PASS|FAIL <evidence>` per row (rows after a failed goal start are FAIL "no goal")
set -u
export PLAYER="${PLAYER:-Beaks}" MATE="${MATE:-Avarek}"
. "$(dirname "$0")/stobe-fight-lib.sh"
. "$(dirname "$0")/stobe-switch-lib.sh"
ROWS="${ROWS:-137 140 fight 138 pause switch cancel clear 143 141 142}"
MOD=/mnt/d/Steam/steamapps/common/Kenshi/RE_Kenshi/mods/Stobe
STW=$MOD/stobe_work_goal.status
CTL=$MOD/stobe_work_goal.control
CAT=$MOD/stobe_production_catalog.txt
trap 'sw_off; raid_guard_stop; heal_stop; stobe-auto speed 0 >/dev/null 2>&1' EXIT
want() { case " $ROWS " in *" $1 "*) return 0 ;; esac; return 1; }
gl_mark() { grep -a -c "" "$KFP" 2>/dev/null || echo 0; }
gl_since() { tail -n +"$(( $1 + 1 ))" "$KFP"; }
st_mark() { grep -a -c "" "$L" 2>/dev/null || echo 0; }
st_since() { tail -n +"$(( $1 + 1 ))" "$L"; }
row_of() { awk -F'\t' -v i="$1" '$1==i' "$STW" 2>/dev/null | head -1; }
state_of() { row_of "$1" | cut -f3; }
step_of() { row_of "$1" | cut -f8; }
live_ids() { awk -F'\t' -v a="$MATE" -v it="${2:-}" 'tolower($2)==tolower(a) && ($3=="ACTIVE"||$3=="PAUSED") && (it=="" || tolower($4)==tolower(it)) {print $1}' "$STW" 2>/dev/null; }
jobs_of() { stobe-auto jobs "$1" | grep -oE 'jobs=[0-9]+' | cut -d= -f2; }
say_mate() { stobe-auto select "$PLAYER" >/dev/null; stobe-say say "$MATE" "$1" >/dev/null 2>&1 || log "say failed: $1"; sleep "${2:-18}"; }
state_is() { [ "$(state_of "$1")" = "$2" ]; }
# ensure_squad <row>: MATE back in PLAYER's squad (an earlier row may have left her outside: 141 spar); else SETUP FAIL
ensure_squad() {
  srv_squad_synced && return 0
  log "$1 setup: $MATE not in ${PLAYER}'s squad, recruiting"
  stobe-auto recruit "$MATE" >/dev/null 2>&1; stobe-auto select "$PLAYER" >/dev/null
  wait_for 90 srv_squad_synced && return 0
  verdict "$1" "SETUP FAIL $MATE not in ${PLAYER}'s squad (server faction '$(srv_faction "$MATE")' vs '$(srv_faction "$PLAYER")')"; return 1
}
# cancel every live goal of hers and empty her job list (setup, not under test)
reset_mate() {
  local i; for i in $(live_ids); do printf '%s\tCANCEL\n' "$i" >> "$CTL"; done
  wait_for 30 bash -c "[ -z \"\$(awk -F'\t' -v a='$MATE' 'tolower(\$2)==tolower(a) && (\$3==\"ACTIVE\"||\$3==\"PAUSED\")' '$STW')\" ]" || log "reset: live goals left"
  stobe-auto clearjobs "$MATE" >/dev/null
}
# start_goal <line>: says it, waits for a NEW live Bread goal; prints its id
start_goal() {
  local before id; before=$(cut -f1 "$STW" 2>/dev/null | sort)
  say_mate "$1" 5
  for i in $(seq 1 20); do
    id=$(comm -13 <(echo "$before") <(cut -f1 "$STW" 2>/dev/null | sort) | while read -r x; do
      [ -n "$x" ] && row_of "$x" | awk -F'\t' '{if(tolower($4) ~ /bread/ && ($3=="ACTIVE"||$3=="PAUSED")) print $1}'; done | head -1)
    [ -n "$id" ] && { echo "$id"; return 0; }
    sleep 3
  done
  return 1
}
moving() { local s0="$2" s; s=$(step_of "$1"); state_is "$1" ACTIVE && [ -n "$s" ] && [ "$s" != "$s0" ] && ! echo "$s" | grep -q "Queued behind"; }

preflight 144 squad advancing
bash "$(dirname "$0")/fullbase-guard.sh"
raid_guard_start
stobe-auto hunger "$PLAYER" 280 >/dev/null; stobe-auto hunger "$MATE" 280 >/dev/null
stobe-say speed 1 >/dev/null
reset_mate
J0=$(jobs_of "$MATE"); log "start: $MATE jobs=$J0"
GID=""

# --- 137: plain polite question -> work goal
if want 137 || want fight || want 138 || want pause || want switch || want cancel; then
  GID=$(start_goal "Hey $MATE can you make me 1 bread?")
  cat_line=$(grep -a -P '^P\t[^\t]*\tBread\t' "$CAT" 2>/dev/null | head -1 | tr '\t' '|')
  if [ -n "$GID" ] && [ -n "$cat_line" ]; then verdict 137 "PASS goal $GID $(state_of "$GID"); catalog: $cat_line"
  else verdict 137 "FAIL goal='${GID}' catalog_bread='${cat_line}' ($(wc -l < "$CAT" 2>/dev/null || echo 0) catalog lines)"; fi
fi
[ -z "$GID" ] && { for r in fight 138 pause switch cancel; do want "$r" && verdict "144-$r" "FAIL no goal (137 failed to start one)"; done; }

stobe-auto speed 3 >/dev/null
if [ -n "$GID" ]; then wait_for 90 bash -c "[ -n \"\$(awk -F'\t' -v i='$GID' '\$1==i{print \$8}' '$STW')\" ]"; fi

# --- 140: in her own outpost the goal panel sits above Kenshi's TownPanel (Stobe logs the move once per session)
if [ -n "$GID" ] && want 140; then
  sleep 5
  mv=$(grep -a "GOAL_PANEL moved above the TownPanel" "$KFP" | tail -1 | cut -c1-160)
  pc=$(grep -a "GOAL_PANEL created" "$KFP" | tail -1 | cut -c1-120)
  [ -n "$mv" ] && verdict 140 "PASS $mv" || verdict 140 "FAIL no TownPanel move line (panel: '$pc'); TownPanel hidden or not overlapping"
fi

# --- fight interrupt, auto-resume
if [ -n "$GID" ] && want fight; then
  heal_start "$MATE"
  out=$(stobe-auto spawn "Hungry Bandit" "Starving Bandits" near "$MATE" dist 6 count 1)
  rh=$(echo "$out" | grep -oE '#[0-9]+/[0-9]+' | head -1)
  [ -n "$rh" ] || log "fight setup: spawn failed: $(echo "$out" | head -1 | cut -c1-160)"
  m=$(st_mark); fought=0
  if [ -n "$rh" ]; then
    for i in $(seq 1 10); do stobe-auto attack "$rh" "$MATE" >/dev/null; sleep 4
      st_since "$m" | grep -a -q -E "\[EVENT\] combat: .* -> $MATE " && { fought=1; break; }; done
    sleep 10; stobe-auto ko "$rh" 900 >/dev/null
  fi
  s0=$(step_of "$GID")
  if [ "$fought" = 1 ] && wait_for 150 moving "$GID" "$s0"; then
    n=$(live_ids "" Bread | wc -l)
    [ "$n" = 1 ] && verdict 144-fight "PASS same goal $GID ACTIVE after the fight, step '$(step_of "$GID" | cut -c1-60)', live Bread goals=1" \
      || verdict 144-fight "FAIL live Bread goals=$n after the fight (want 1)"
  else verdict 144-fight "FAIL fought=$fought state=$(state_of "$GID") step='$(step_of "$GID" | cut -c1-60)' (was '$s0')"; fi
  heal_stop
fi

# --- 138: follow me, then resume
if [ -n "$GID" ] && want 138; then
  say_mate "$MATE, follow me." 15
  g=$(gl_mark)
  say_mate "$MATE, resume your task." 20
  rs=$(gl_since "$g" | grep -a -c "WORK_GOAL resume id=$GID")
  n=$(live_ids "" Bread | wc -l)
  if [ "$rs" -ge 1 ] && state_is "$GID" ACTIVE && [ "$n" = 1 ]; then verdict 138 "PASS resume line x$rs, $GID ACTIVE, live Bread goals=1"
  else verdict 138 "FAIL resume_lines=$rs state=$(state_of "$GID") live_bread=$n"; fi
fi

# --- pause / resume
if [ -n "$GID" ] && want pause; then
  say_mate "$MATE, pause your work for now." 20
  p=$(state_of "$GID")
  say_mate "$MATE, resume your work." 20
  r=$(state_of "$GID")
  [ "$p" = PAUSED ] && [ "$r" = ACTIVE ] && verdict 144-pause "PASS $GID PAUSED -> ACTIVE" || verdict 144-pause "FAIL after pause=$p after resume=$r"
fi

# --- squad switching + the m51 duplicate trigger
if [ -n "$GID" ] && want switch; then
  stobe-auto select "$MATE" >/dev/null; sleep 8; stobe-auto select "$PLAYER" >/dev/null; sleep 4
  a=$(state_of "$GID")
  say_mate "$MATE, get to work." 20
  n=$(live_ids "" Bread | wc -l)
  [ "$a" = ACTIVE ] && [ "$n" = 1 ] && state_is "$GID" ACTIVE && verdict 144-switch "PASS $GID ACTIVE across selection switch; 'get to work' left live Bread goals=1" \
    || verdict 144-switch "FAIL state_after_switch=$a live_bread=$n now=$(state_of "$GID")"
fi

# --- 139 cancel: the goal and every job it added go
if [ -n "$GID" ] && want cancel; then
  say_mate "$MATE, cancel the bread, stop that work." 20
  wait_for 30 state_is "$GID" CANCELLED
  j=$(jobs_of "$MATE")
  [ "$(state_of "$GID")" = CANCELLED ] && [ "${j:-99}" -le "${J0:-0}" ] && verdict 139-cancel "PASS $GID CANCELLED, jobs $J0 -> $j" \
    || verdict 139-cancel "FAIL state=$(state_of "$GID") jobs start=$J0 now=$j ($(stobe-auto jobs "$MATE" | cut -c1-120))"
fi

# --- 139 clear all
if want clear; then
  reset_mate
  start_goal "$MATE, make me 1 bread." >/dev/null
  stobe-auto job "$MATE" "Wheat Farm" >/dev/null 2>&1
  sleep 20
  j1=$(jobs_of "$MATE"); l1=$(live_ids | wc -l)
  g=$(gl_mark)
  say_mate "$MATE, clear all your tasks, goals and jobs." 25
  cj=$(gl_since "$g" | grep -a "GOAL_CLEARJOBS" | tail -1 | cut -c1-160)
  l2=$(live_ids | wc -l); j2=$(jobs_of "$MATE")
  if [ "$l1" -ge 1 ] && [ "$l2" = 0 ] && [ "${j2:-9}" = 0 ] && [ -n "$cj" ]; then verdict 139-clear "PASS live goals $l1 -> 0, jobs $j1 -> 0; $cj"
  else verdict 139-clear "FAIL live goals $l1 -> $l2, jobs $j1 -> $j2, clearjobs='$cj'"; fi
fi
# --- 143 (live model): an ended bread goal is not dragged into unrelated talk (server 331f845 ended-goal prompt rule)
#   own goal: start "1 bread", cancel it, then two backstory questions; PASS = both replies arrive, neither mentions bread.
if want 143; then
  reset_mate
  g143=$(start_goal "$MATE, make me 1 bread.")
  [ -n "$g143" ] && { say_mate "$MATE, cancel the bread, stop that work." 20; wait_for 30 state_is "$g143" CANCELLED; }
  if [ -z "$g143" ] || [ "$(state_of "$g143")" != CANCELLED ]; then verdict 143 "SETUP FAIL bread goal '${g143}' not started/cancelled ($(state_of "$g143"))"
  else
    m=$(st_mark)
    say_mate "$MATE, tell me about yourself. Where did you grow up?" 25
    say_mate "What did you do before you joined us, $MATE?" 25
    rp=$(st_since "$m" | grep -a "Queuing SAY for $MATE:" | sed "s/.*Queuing SAY for $MATE: //")
    n=$(printf '%s\n' "$rp" | grep -c .); b=$(printf '%s\n' "$rp" | grep -i -c "bread\|bak")
    if [ "$n" -ge 2 ] && [ "$b" = 0 ]; then verdict 143 "PASS $n reply lines, none mention bread (goal $g143 CANCELLED): $(printf '%s ' "$rp" | cut -c1-160)"
    else verdict 143 "FAIL replies=$n bread_mentions=$b: $(printf '%s ' "$rp" | cut -c1-300)"; fi
  fi
fi
stobe-auto speed 1 >/dev/null

# SOCIAL_SPAR consent is a relationship log line (stobeLogRelationshipInfo -> relationship_worker.log), not stobeserver.log (m55)
REL_LOG=/var/www/html/StobeServer/log/relationship_worker.log
rel_count() { local n; n=$(grep -a -c -F -- "$1" "$REL_LOG" 2>/dev/null); echo "${n:-0}"; }

# --- 141 spar: she rejoins the squad when the fight is stopped
# 141 (deterministic): NEG_TEST_INJECT puts Attack@<player> into her reply to the spar line (before any parsing),
#   so the real path runs: spar recorded (SOCIAL_SPAR consent why=attack), "enough, stop" -> STOP_FIGHT guard
#   (not injected), Stobe `spar rejoin ... in_faction_after=1`, server squad synced.
# 141-live (not in the default ROWS): same without injection = does the model start the spar by itself.
for r141 in 141 141-live; do
if want "$r141" && ensure_squad "$r141"; then
  reset_mate
  heal_start "$PLAYER $MATE"
  m=$(st_mark); c0=$(rel_count "SOCIAL_SPAR consent"); s0=$(srv_count "Spar stopped by the player"); f0=$(fired 141)
  [ "$r141" = 141 ] && inject_on 141 "$MATE" chat "[{\"action\":\"Attack\",\"target\":\"{player}\",\"message\":\"Alright, guard yourself.\"}]"
  say_mate "$MATE, let's spar. Attack me, come on." 20
  sw_off
  left=$(st_since "$m" | grep -a -c "ATTACK@$PLAYER"); inj=$(( $(fired 141) - f0 )); cons=$(( $(rel_count "SOCIAL_SPAR consent") - c0 ))
  sleep 8
  say_mate "Enough $MATE, stop, we're done sparring." 25
  wait_for 30 bash -c "tail -n +$(( m + 1 )) '$L' | grep -a -q 'spar rejoin npc=$MATE'"
  rj=$(st_since "$m" | grep -a "spar rejoin npc=$MATE" | tail -1 | cut -c1-200)
  stp=$(( $(srv_count "Spar stopped by the player") - s0 ))
  ev="inject_fired=$inj attack_lines=$left spar_consent=$cons stop_fight_sent=$stp"
  if [ "$r141" = 141 ] && [ "$inj" -lt 1 ]; then verdict 141 "SETUP FAIL NEG_TEST_INJECT did not fire on her spar reply ($ev)"
  elif echo "$rj" | grep -q "in_faction_after=1" && srv_squad_synced && [ "$cons" -ge 1 ]; then verdict "$r141" "PASS $ev; $rj"
  elif [ "$left" = 0 ]; then verdict "$r141" "FAIL she never attacked (no ATTACK@$PLAYER; $ev)"
  else verdict "$r141" "FAIL $ev rejoin='${rj}' squad_synced=$(srv_squad_synced && echo 1 || echo 0)"; fi
  heal_stop
fi
done

# --- 142 first aid really treats
if want 142 && ensure_squad 142; then
  stobe-auto give "$MATE" "Basic First Aid Kit" 1 >/dev/null 2>&1
  stobe-auto health "$PLAYER" 55 >/dev/null
  g=$(gl_mark)
  say_mate "$MATE, I'm hurt. Patch me up please." 10
  wait_for 90 bash -c "tail -n +$(( g + 1 )) '$KFP' | grep -a -q 'FIRST_AID verify'"
  sleep 20
  fv=$(gl_since "$g" | grep -a "FIRST_AID verify" | tail -1 | cut -c1-200)
  fa=$(gl_since "$g" | grep -a -c "FIRST_AID")
  if echo "$fv" | grep -q -E "result=(healed|treating)"; then verdict 142 "PASS $fv"
  elif [ "$fa" = 0 ]; then verdict 142 "FAIL no FIRST_AID action (live-model miss)"
  else verdict 142 "FAIL $fv"; fi
  stobe-auto health "$PLAYER" 100 >/dev/null
fi
stobe-auto speed 0 >/dev/null
