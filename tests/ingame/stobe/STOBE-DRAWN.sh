#!/usr/bin/env bash
# id: STOBE-DRAWN
# covers: drawn-weapon reactions (Stobe fc1ead3+ / DLL F23B4432+, StobeServer 055e0c5+): NPCs who see a player character
#         with a weapon drawn within the radius speak (neutral+: why is it out; guards: put it away), hostile ones warn
#         and then attack (time or closing in), holstering cancels, own squad / unseen / in-combat never react,
#         per-NPC cooldown, the reaction turn is speech only.
# fixture: Crafting base (Shay + Malzin, Hub), on a kah-* copy (PLAYER/MATE env for other squads; PLAYER needs a weapon)
# usage: bash STOBE-DRAWN.sh [rows]   rows = space list of DW1..DW10 (default all; order fixed: friendly rows first,
#        the rows that end in a real attack last)
# needs: harness `stobe_drawn` (StobeHarnessBridge), NEG_TEST_INJECT context `react`, `pin`/`face`/`spawn`/`fight`
# switch: NEG_TEST_INJECT context react (DW1 DW2 DW9) for the spawned NPC; the native side is driven through
#         `stobe_drawn set` (hostile_below -101 = everyone neutral, 101 = everyone hostile; warn/cooldown per row).
#         All stobe_drawn settings read at start are restored on exit, `hold PLAYER off`, spawned NPCs unpinned + KO'd.
# verify: stobe.log `DRAWN_WEAPON: <action> npc=<n> ...` / `REACTION_TURN: dispatched react=drawn_weapon`, server log
#         `Drawn weapon reaction turn` + `NEG_TEST_INJECT fired`, eventlog infoaction row, NPC_SAY line, `stobe_drawn pair`
#         attack_target=. One RESULT line per row.
# note: DW5/DW3 make Drifters attack PLAYER (protected); the fixture copy should be reloaded afterwards.
set -u
. "$(dirname "$0")/stobe-fight-lib.sh"
. "$(dirname "$0")/stobe-switch-lib.sh"
ROWS="${*:-DW1 DW2 DW3 DW4 DW5 DW6 DW7 DW8 DW9 DW10}"
want() { case " $ROWS " in *" $1 "*) return 0 ;; esac; return 1; }
PSQLQ() { (cd /tmp && sudo -u postgres psql -d stobe -At -c "$1" 2>/dev/null); }

dw() { stobe-auto stobe_drawn "$@" 2>/dev/null | tail -1; }
cfg() { echo "$1" | grep -oE "(^| )$2=[^ ]+" | head -1 | sed -E 's/^ ?[a-z_]+=//'; }
# row marks: log slices since the row started
rowmark() { RL=$(grep -a -c "" "$L"); RS=$(grep -a -c "" "$SRV"); RT=$(date +%s); }
rlog() { tail -n +"$RL" "$L"; }
rsrv() { tail -n +"$RS" "$SRV"; }
rhas() { rlog | grep -a -q -F -- "$1"; }
rcount() { rlog | grep -a -c -F -- "$1"; }
# dline <action> <npc>: the newest `DRAWN_WEAPON: <action> npc=<npc> ` line of this row
dline() { rlog | grep -a -F -- "DRAWN_WEAPON: $1 npc=$2 player=" | tail -1; }
dcount() { rlog | grep -a -c -F -- "DRAWN_WEAPON: $1 npc=$2 player="; }
tof() { echo "$1" | grep -oE ' t=[0-9.]+' | tail -1 | cut -d= -f2; }
wait_line() { wait_for "$1" rhas "DRAWN_WEAPON: $2 npc=$3 player="; }
sees_player() { stobe-auto face "$1" "$PLAYER" 2>/dev/null | grep -q "sees=1"; }
pos_of() { stobe-auto where "$1" 2>/dev/null | grep -oE 'pos=[-0-9.,]+' | head -1 | cut -d= -f2; }
draw_on() { local r; r=$(dw hold "$PLAYER" on); log "draw: $r"; echo "$r" | grep -q "drawn=1"; }
draw_off() { dw hold "$PLAYER" off >/dev/null; }
said_has() { npc_said "$1" | grep -q -F -- "$2"; }
said_any() { [ -n "$(npc_said "$1")" ]; }
dcount_ge() { [ "$(dcount "$2" "$3")" -ge "$1" ]; }
targets_player() { dw pair "$1" | grep -q "attack_target=$PLAYER"; }

SPAWNED=""
# rows run in subshells (a setup fail ends only that row): spawned handles also go to a file the parent reads
SPAWN_FILE=$(mktemp /tmp/stobe-drawn-spawn.XXXXXX); RETIRED=0
track() { SPAWNED="$SPAWNED $1"; echo "$1" >> "$SPAWN_FILE"; }
# fresh <name> [dist]: a neutral Drifter <name> pinned <dist> game units (10 = ~1 m; default 60 = 6 m, inside the 10 m
# radius, outside the 3 m attack distance) from PLAYER, facing PLAYER and seeing him; sets h (not in $(): setup_fail must end the wrapper)
fresh() {
  local row="$1" n="$2" r
  mate_holster "$row"
  h=$(spawn_neutral "$n" 12) || setup_fail "$row" "spawn of $n failed"
  track "$h"
  pin_seen "$row" "$n" "$h" "${3:-60}"
}
# pin_seen <row> <name> <handle> <dist>: pins him <dist> units from PLAYER on the first side (of 8) with a clear view
# (m50-c: +x alone put every NPC behind a Crafting-base wall: sees=0 los=0); setup_fail if no side works
pin_seen() {
  local row="$1" n="$2" h="$3" d="$4" pp px py pz dx dz r k=0
  pp=$(pos_of "$PLAYER"); [ -n "$pp" ] || setup_fail "$row" "no position for $PLAYER"
  IFS=, read -r px py pz <<<"$pp"
  for o in "1 0" "-1 0" "0 1" "0 -1" "0.7 0.7" "-0.7 0.7" "0.7 -0.7" "-0.7 -0.7"; do
    read -r dx dz <<<"$o"; k=$((k+1))
    r=$(stobe-auto pin "$h" at $(awk -v x="$px" -v y="$py" -v z="$pz" -v a="$dx" -v b="$dz" -v d="$d" 'BEGIN{printf "%.1f %.1f %.1f", x+a*d, y, z+b*d}') face "$PLAYER" 2>&1 | tail -1)
    log "pin $n side $k ($o): $r"
    wait_for 6 sees_player "$h" && return 0
  done
  setup_fail "$row" "$n does not see $PLAYER from any of 8 sides ($(stobe-auto face "$h" "$PLAYER" 2>&1 | tail -1 | cut -c1-120))"
}
# mate_holster <row>: MATE's weapon away (an AI combat stance left over from the previous row must not be in the row)
mate_holster() {
  [ -n "${MATE:-}" ] || return 0
  local r; r=$(dw sheathe "$MATE")
  case "$r" in *drawn=0*) return 0 ;; esac
  sleep 2; r=$(dw sheathe "$MATE")
  case "$r" in *drawn=0*) return 0 ;; esac
  setup_fail "$1" "$MATE still has a weapon drawn: $r"
}
# row_done: after each row subshell: weapon away, switches off, retire what the row spawned (also after a setup fail)
row_done() {
  draw_off; sw_off >/dev/null 2>&1
  local all; all=$(cat "$SPAWN_FILE" 2>/dev/null | tail -n +$((RETIRED + 1)))
  [ -n "$all" ] && retire $all
  RETIRED=$(grep -c "" "$SPAWN_FILE" 2>/dev/null || echo 0)
}
retire() { for h in "$@"; do [ -n "$h" ] && { stobe-auto pin "$h" off >/dev/null 2>&1; stobe-auto ko "$h" 900 >/dev/null 2>&1; }; done; }
# row_cfg <hostile_below> <warn> <cooldown>: forget per-NPC state/cooldowns/counters, then the row's knobs
row_cfg() { draw_off; dw reset >/dev/null; dw set hostile_below "$1" >/dev/null; dw set warn "$2" >/dev/null; dw set cooldown "$3" >/dev/null; sleep 2; }

# --- setup ---
stobe-auto select "$PLAYER" >/dev/null
stobe-say speed 1 >/dev/null
preflight DW advancing
# daylight: at night NPCs only notice the player within a few metres (m50-5090-d: 02:00, sees=0 los=0 on all 8 sides at 6 m),
# so the rows run in daytime: fast-forward (squad protected) until 09:00-15:59
hour_now() { stobe-auto time 2>/dev/null | grep -oE 'time=[0-9]+' | cut -d= -f2 | sed 's/^0//'; }
daylight() {
  local h end=$(( $(date +%s) + 180 )); h=$(hour_now); [ -n "$h" ] || setup_fail DW "no game time ($(stobe-auto time 2>&1 | tail -1))"
  [ "$h" -ge 9 ] && [ "$h" -le 15 ] && return 0
  for c in "$PLAYER" "$MATE"; do stobe-auto protect "$c" on >/dev/null; done
  stobe-auto speed 50 >/dev/null
  until h=$(hour_now); [ -n "$h" ] && [ "$h" -ge 9 ] && [ "$h" -le 15 ]; do
    [ "$(date +%s)" -ge "$end" ] && { stobe-auto speed 1 >/dev/null; setup_fail DW "game time never reached 09:00 (hour=$h)"; }; sleep 1; done
  stobe-auto speed 1 >/dev/null
  for c in "$PLAYER" "$MATE"; do stobe-auto protect "$c" off >/dev/null; done
  log "daylight: fast-forwarded to $(stobe-auto time | grep -oE 'time=[0-9:]+')"
}
daylight
ST0=$(dw status)
case "$ST0" in *enabled=*) ;; *) setup_fail DW "no stobe_drawn command (Stobe.dll older than fc1ead3?): $ST0" ;; esac
log "drawn status at start: $ST0"
cleanup() {
  draw_off
  for k in enabled radius warn attack_dist min_warn close_margin cooldown rewarn hostile_below min_fov; do
    v=$(cfg "$ST0" "$k"); [ -n "$v" ] && dw set "$k" "$v" >/dev/null
  done
  retire $(cat "$SPAWN_FILE" 2>/dev/null); rm -f "$SPAWN_FILE"
  log "drawn settings restored: $(dw status | cut -c1-160)"
}
trap 'cleanup; sw_off; heal_stop; stobe-auto speed 0 >/dev/null 2>&1' EXIT; trap 'exit 130' INT TERM
draw_on || setup_fail DW "$PLAYER cannot draw a weapon: $(dw hold "$PLAYER" on)"
draw_off; sleep 2

# --- DW1 friendly line (+ DW7 own squad: MATE stands next to PLAYER and sees him during DW1) ---
if want DW1 || want DW7; then (
  N="Dorn Hask"; row_cfg -101 4 5
  fresh DW1 "$N"
  stobe-auto teleport "$MATE" "$PLAYER" dist 5 >/dev/null; wait_for 20 sees_player "$MATE"; msee=$?
  rowmark
  inject_on DW1 "$N" react '[{"message":"Why is that blade out, {player}? Put it away and we can talk."}]'
  draw_on || setup_fail DW1 "draw failed"
  wait_line 25 speak_friendly "$N"; wait_for 40 said_has "$N" "Why is that blade out"
  sleep 3
  l=$(dline speak_friendly "$N"); rt=$(rlog | grep -a -F "REACTION_TURN: dispatched react=drawn_weapon" | grep -a -c -F "speaker=$N")
  ev=$(PSQLQ "SELECT COUNT(*) FROM eventlog WHERE type='infoaction' AND data LIKE '%$(sq "$N")%' AND data LIKE '%drawn%' AND localts >= $RT - 5")
  srvt=$(rsrv | grep -a -c -F "Drawn weapon reaction turn"); f=$(fired DW1)
  said=$(npc_said "$N" | grep -c -F "Why is that blade out")
  mlines=$(rlog | grep -a "DRAWN_WEAPON: " | grep -a -v "DRAWN_WEAPON: test " | grep -a -c -F "npc=$MATE ")
  mpair=$(dw pair "$MATE")
  draw_off
  if want DW1; then
    if [ "$f" -lt 1 ] && [ -n "$l" ]; then verdict DW1 "INCONCLUSIVE speak_friendly logged but injection never fired (rt=$rt srv=$srvt)"
    elif echo "$l" | grep -q "speech=sent" && [ "$rt" -ge 1 ] && [ "$srvt" -ge 1 ] && [ "${ev:-0}" -ge 1 ] && [ "$said" -ge 1 ]; then
      verdict DW1 "PASS speak_friendly $(echo "$l" | grep -oE 'stance=[^ ]+ dist=[^ ]+ sees=1') REACTION_TURN=$rt srv_turn=$srvt infoaction=$ev injected line said"
    else verdict DW1 "FAIL line='$(echo "$l" | cut -c1-120)' reaction_turn=$rt srv_turn=$srvt infoaction=${ev:-?} fired=$f said=$said"; fi
  fi
  if want DW7; then
    if [ "$msee" != 0 ]; then verdict DW7 "SETUP FAIL $MATE does not see $PLAYER"
    elif [ -z "$l" ]; then verdict DW7 "INCONCLUSIVE control (DW1 neutral NPC) never reacted: scan not proven"
    elif [ "$mlines" = 0 ] && echo "$mpair" | grep -q "no_pair"; then verdict DW7 "PASS $MATE (sees=1, own squad) no DRAWN_WEAPON line, no pair, while $N reacted"
    else verdict DW7 "FAIL $MATE lines=$mlines pair='$(echo "$mpair" | cut -c1-120)'"; fi
  fi
  retire "$h"; sw_off; sleep 3
); row_done
fi

# --- DW2 guard line ---
if want DW2; then (
  N="Town Guard"; row_cfg -101 4 5
  fresh DW2 "$N"; rowmark
  N=$(name_of "$h"); [ -n "$N" ] || setup_fail DW2 "no live name for the guard"; log "DW2 guard live name: $N"   # a spawned guard gets a name (m50-e: Rhuk [Town Guard])
  inject_on DW2 "$N" react '[{"message":"Sheathe that weapon, {player}. Now."}]'
  draw_on || setup_fail DW2 "draw failed"
  wait_line 25 speak_guard "$N"; wait_for 40 said_has "$N" "Sheathe that weapon"
  l=$(dline speak_guard "$N"); fr=$(dcount speak_friendly "$N"); f=$(fired DW2)
  said=$(npc_said "$N" | grep -c -F "Sheathe that weapon")
  rt=$(rlog | grep -a -F "REACTION_TURN: dispatched react=drawn_weapon" | grep -a -F "speaker=$N" | grep -a -c "kind=guard")
  draw_off
  if [ "$f" -lt 1 ] && [ -n "$l" ]; then verdict DW2 "INCONCLUSIVE speak_guard logged but injection never fired"
  elif echo "$l" | grep -q "kind=guard" && echo "$l" | grep -q "speech=sent" && [ "$fr" = 0 ] && [ "$rt" -ge 1 ] && [ "$said" -ge 1 ]; then
    verdict DW2 "PASS speak_guard kind=guard REACTION_TURN kind=guard=$rt injected line said, no friendly line"
  else verdict DW2 "FAIL line='$(echo "$l" | cut -c1-120)' friendly=$fr reaction_turn_guard=$rt fired=$f said=$said"; fi
  retire "$h"; sw_off; sleep 3
); row_done
fi

# --- DW6 not seen: he faces a decoy straight away from PLAYER -> no line; control: turned back he speaks ---
if want DW6; then (
  N="Ollo Brisk"; row_cfg -101 4 5
  fresh DW6 "$N"
  d=$(spawn_neutral "Pell Decoy" 12) || setup_fail DW6 "decoy spawn failed"; track "$d"
  pn=$(pos_of "$h"); ps=$(pos_of "$PLAYER")
  tgt=$(awk -v a="$pn" -v b="$ps" 'BEGIN{split(a,n,",");split(b,s,",");dx=n[1]-s[1];dz=n[3]-s[3];m=sqrt(dx*dx+dz*dz);if(m<0.01)m=1;printf "%.1f %.1f %.1f", n[1]+dx/m*12, n[2], n[3]+dz/m*12}')
  stobe-auto teleport "$d" $tgt >/dev/null
  stobe-auto pin "$d" >/dev/null 2>&1
  stobe-auto pin "$h" at $(echo "$pn" | tr ',' ' ') face "$d" >/dev/null
  sleep 3
  fsee=$(stobe-auto face "$h" "$d" 2>/dev/null | tail -1); log "DW6 facing decoy: $fsee"
  rowmark
  draw_on || setup_fail DW6 "draw failed"
  sleep 12
  neg=$(rlog | grep -a "DRAWN_WEAPON: " | grep -a -v "DRAWN_WEAPON: test " | grep -a -c -F "npc=$N ")
  p=$(dw pair "$N")
  # control: face him back toward PLAYER (pin face), he must now react
  stobe-auto pin "$h" at $(echo "$pn" | tr ',' ' ') face "$PLAYER" >/dev/null
  wait_for 20 sees_player "$h"
  wait_line 25 speak_friendly "$N"; ctl=$(dcount speak_friendly "$N")
  draw_off
  if [ "$ctl" -lt 1 ]; then verdict DW6 "INCONCLUSIVE control: facing $PLAYER again he never spoke (unseen lines=$neg pair='$(echo "$p" | cut -c1-100)')"
  elif [ "$neg" = 0 ] && ! echo "$p" | grep -q "sees=1"; then verdict DW6 "PASS facing away: no line ($(echo "$p" | grep -oE 'sees=[01] fov=[^ ]+' | head -1 || echo no_pair)); facing back: speak_friendly"
  else verdict DW6 "FAIL facing away: lines=$neg pair='$(echo "$p" | cut -c1-140)'"; fi
  retire "$h" "$d"; sleep 3
); row_done
fi

# --- DW9 cooldown: second draw inside the cooldown gives no second line; with a short cooldown it does ---
if want DW9; then (
  N="Kessa Rook"; row_cfg -101 4 60
  fresh DW9 "$N"; rowmark
  inject_on DW9 "$N" react '[{"message":"That blade again, {player}?"},{"message":"Still waving that blade around, {player}?"}]'
  draw_on || setup_fail DW9 "draw failed"
  wait_line 25 speak_friendly "$N"; c1=$(dcount speak_friendly "$N")
  draw_off; sleep 4; draw_on; sleep 15
  c2=$(dcount speak_friendly "$N")
  dw set cooldown 5 >/dev/null; draw_off; sleep 6; draw_on
  wait_for 25 dcount_ge 2 speak_friendly "$N"
  c3=$(dcount speak_friendly "$N")
  draw_off
  if [ "$c1" -lt 1 ]; then verdict DW9 "INCONCLUSIVE first line never came"
  elif [ "$c2" = 1 ] && [ "$c3" -ge 2 ]; then verdict DW9 "PASS cooldown 60: redraw gave no second line (1); cooldown 5: second line ($c3)"
  else verdict DW9 "FAIL lines first=$c1 after_redraw_in_cooldown=$c2 after_short_cooldown=$c3"; fi
  retire "$h"; sw_off; sleep 3
); row_done
fi

# --- DW10 live model (no injection): the line is about the weapon; speech only (no attack, no deal) ---
if want DW10; then (
  N="Marro Fenn"; row_cfg -101 4 5
  fresh DW10 "$N"; rowmark
  draw_on || setup_fail DW10 "draw failed"
  wait_line 25 speak_friendly "$N"
  wait_for 45 said_any "$N"
  sleep 5
  l=$(dline speak_friendly "$N"); wn=$(echo "$l" | sed -E 's/.* weapon=(.*) speech=.*/\1/')
  s=$(npc_said "$N" | tail -1)
  # the spoken text only; on topic = a weapon word, or "put it/that/... down|away", lower/holster/stow/drop it (m50 DW10:
  # "Put it down and tell me what's going on." is on topic). Off-topic lines (trade, weather, greetings) still fail.
  st=$(echo "$s" | sed -E 's/.*NPC_SAY: [^|]*\|[0-9]*: //; s/ \[TALK.*//')
  mention=$(echo "$st" | grep -i -c -E "\b(${WEAPON_RE}|steel|drawn?|sheathe?|holster|stow|armed|arms)\b|\b(put|lower|drop|set|lay) (it|that|this|those|them|the|your)( [a-z]+)? (down|away)\b|\b(lower|drop|holster|sheathe|stow) (it|that|this|the|your)\b")
  p=$(dw pair "$N"); d=$(deal_row "$N"); srvt=$(rsrv | grep -a -c -F "Drawn weapon reaction turn")
  draw_off
  if [ -z "$l" ]; then verdict DW10 "FAIL no speak_friendly line"
  elif [ -z "$s" ]; then verdict DW10 "FAIL reaction turn sent (srv=$srvt) but $N said nothing"
  elif [ "$mention" -ge 1 ] && echo "$p" | grep -q "attack_target=none" && [ -z "$d" ]; then
    verdict DW10 "PASS live line mentions the weapon ($wn): '$(echo "$s" | sed -E 's/.*NPC_SAY: [^|]*\|//' | cut -c1-110)'; attack_target=none, no deal"
  else verdict DW10 "FAIL mention=$mention pair='$(echo "$p" | grep -oE 'attack_target=.*')' deal='${d:0:60}' said='$(echo "$s" | cut -c1-140)'"; fi
  retire "$h"; sleep 3
); row_done
fi

# hostile rows: PLAYER protected (DW3/DW5 end in a real attack)
if want DW4 || want DW8 || want DW5 || want DW3; then heal_start "$PLAYER"; fi

# --- DW4 holster cancels the pending warning: no attack ---
if want DW4; then (
  N="Grell Saddo"; row_cfg 101 8 5
  fresh DW4 "$N"; rowmark
  draw_on || setup_fail DW4 "draw failed"
  wait_line 25 warn "$N"; w=$(dline warn "$N")
  [ -n "$w" ] || { draw_off; retire "$h"; verdict DW4 "FAIL no warn line (stance hostile_below=101)"; }
  if [ -n "$w" ]; then
    draw_off
    wait_line 8 cancel_holstered "$N"; c=$(dline cancel_holstered "$N")
    sleep 12
    a=$(dcount attack "$N"); p=$(dw pair "$N")
    if [ -n "$c" ] && [ "$a" = 0 ] && ! echo "$p" | grep -q "attack_target=$PLAYER"; then
      verdict DW4 "PASS warn t=$(tof "$w") -> holster -> cancel_holstered t=$(tof "$c"); no attack after 8 s warn time"
    else verdict DW4 "FAIL cancel='$(echo "$c" | cut -c1-80)' attacks=$a $(echo "$p" | grep -oE 'attack_target=.*')"; fi
    retire "$h"; sleep 3
  fi
); row_done
fi

# --- DW8 combat gate: a warned NPC who gets into a fight cancels (cancel_combat), no line, no attack on PLAYER ---
if want DW8; then (
  N="Vosk Tamber"; row_cfg 101 30 5
  fresh DW8 "$N"; rowmark
  draw_on || setup_fail DW8 "draw failed"
  wait_line 25 warn "$N"; w=$(dline warn "$N")
  if [ -z "$w" ]; then draw_off; verdict DW8 "FAIL no warn line before the fight"
  else
    so=$(stobe-auto spawn "Hungry Bandit" Drifters near "$h" dist 30 count 1 2>&1); r=$(echo "$so" | grep -oE '#[0-9]+/[0-9]+' | head -1)
    [ -n "$r" ] || setup_fail DW8 "fight partner spawn failed: $(echo "$so" | tail -1 | cut -c1-120)"
    track "$r"
    stobe-auto fight "$h" "$r" >/dev/null
    wait_line 15 cancel_combat "$N"; c=$(dline cancel_combat "$N")
    sleep 10
    a=$(dcount attack "$N"); sp=$(rlog | grep -a -F "npc=$N player=" | grep -a -c -E "DRAWN_WEAPON: (speak_friendly|speak_guard|warn|rearm) ")
    draw_off
    if [ -n "$c" ] && [ "$a" = 0 ] && [ "$sp" = 1 ]; then verdict DW8 "PASS warn -> fight with $r -> cancel_combat t=$(tof "$c"); no attack order, no further line"
    else verdict DW8 "FAIL cancel_combat='$(echo "$c" | cut -c1-80)' attacks=$a lines=$sp (1 = the warn)"; fi
    retire "$r"
  fi
  retire "$h"; sleep 8
); row_done
fi

# --- DW5 closing in after the warning attacks (warn time 30 s, so only the distance can trigger it; not before min_warn) ---
if want DW5; then (
  N="Hadda Crane"; row_cfg 101 30 5
  fresh DW5 "$N"; rowmark
  draw_on || setup_fail DW5 "draw failed"
  wait_line 25 warn "$N"; w=$(dline warn "$N")
  if [ -z "$w" ]; then draw_off; verdict DW5 "FAIL no warn line"
  else
    stobe-auto pin "$h" at "$PLAYER" dist 15 face "$PLAYER" >/dev/null
    wait_line 10 attack "$N"; a=$(dline attack "$N")
    stobe-auto pin "$h" off >/dev/null 2>&1
    wait_for 15 targets_player "$N"
    p=$(dw pair "$N")
    dt=$(awk -v a="$(tof "$w")" -v b="$(tof "$a")" 'BEGIN{printf "%.1f", b-a}')
    draw_off
    if echo "$a" | grep -q "order=1" && awk -v d="$dt" 'BEGIN{exit !(d < 25)}' && { rhas "attack_confirmed npc=$N " || echo "$p" | grep -q "attack_target=$PLAYER"; }; then
      verdict DW5 "PASS warn -> closed to 1.5 m (15 units) -> attack order=1 after ${dt}s (warn time 30) $(echo "$p" | grep -oE 'attack_target=.*')"
    else verdict DW5 "FAIL attack='$(echo "$a" | cut -c1-100)' dt=$dt $(echo "$p" | grep -oE 'attack_target=.*')"; fi
  fi
  retire "$h"; sleep 8
); row_done
fi

# --- DW3 hostile: warn, weapon kept out in range -> attack after the warn time ---
if want DW3; then (
  N="Rusk Malver"; row_cfg 101 4 5
  fresh DW3 "$N"; rowmark
  draw_on || setup_fail DW3 "draw failed"
  wait_line 25 warn "$N"; w=$(dline warn "$N")
  if [ -z "$w" ]; then draw_off; verdict DW3 "FAIL no warn line"
  else
    wait_line 20 attack "$N"; a=$(dline attack "$N")
    stobe-auto pin "$h" off >/dev/null 2>&1
    wait_for 15 rhas "attack_confirmed npc=$N "
    p=$(dw pair "$N"); conf=$(rcount "attack_confirmed npc=$N ")
    dt=$(awk -v a="$(tof "$w")" -v b="$(tof "$a")" 'BEGIN{printf "%.1f", b-a}')
    draw_off
    if echo "$a" | grep -q "order=1" && awk -v d="$dt" 'BEGIN{exit !(d >= 3.5)}' && { [ "$conf" -ge 1 ] || echo "$p" | grep -q "attack_target=$PLAYER"; }; then
      verdict DW3 "PASS warn t=$(tof "$w") -> attack order=1 after ${dt}s (warn 4) confirmed=$conf $(echo "$p" | grep -oE 'attack_target=.*')"
    else verdict DW3 "FAIL attack='$(echo "$a" | cut -c1-100)' dt=$dt confirmed=$conf $(echo "$p" | grep -oE 'attack_target=.*')"; fi
  fi
  retire "$h"
); row_done
fi
log "STOBE-DRAWN done"
