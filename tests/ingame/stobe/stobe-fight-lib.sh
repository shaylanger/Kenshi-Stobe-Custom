#!/usr/bin/env bash
# stobe-fight-lib.sh: shared helpers for the STOBE fight/deal wrappers (source it; WSL, harness on).
# Paths, a background healer that keeps Shay (and optionally Malzin) up, one-raider setup that waits for
# a real fight, deal lookups via negotiation_admin.php, and log slices since the wrapper started.
L=/mnt/d/Steam/steamapps/common/Kenshi/RE_Kenshi/mods/Stobe/stobe.log
KFP=/mnt/d/Steam/steamapps/common/Kenshi/KenshiFP.log
SRV=/var/www/html/StobeServer/log/stobeserver.log
SC=/mnt/c/KenshiModding/tools/automation/scenarios.sh
BASE_L=$(grep -a -c "" "$L" 2>/dev/null || echo 0)
BASE_SRV=$(grep -a -c "" "$SRV" 2>/dev/null || echo 0)
HEALER=""

# m16: the healer and the main flow wrote the harness inbox at the same moment (kah.py uses one fixed
# inbox.txt.tmp -> FileNotFoundError, lost commands: the raider spawn, the "deal." line). Every harness call from
# these wrappers goes through one lock. stobe-say's --wait would hold the lock (and stop the healer), so it is
# dropped here and the wrapper sleeps instead.
KAH_LOCK=/tmp/stobe-kah.lock
stobe-auto() { flock "$KAH_LOCK" stobe-auto "$@"; }
stobe-say() {
  local a=() w=0
  while [ $# -gt 0 ]; do if [ "$1" = "--wait" ]; then w="${2:-0}"; shift 2; else a+=("$1"); shift; fi; done
  flock "$KAH_LOCK" stobe-say "${a[@]}"
  local rc=$?
  [ "$w" -gt 0 ] && sleep 15
  return $rc
}
trust() { flock "$KAH_LOCK" bash "$SC" trust "$@"; }  # stobe-rel-stamp reads the game time through the harness

log() { echo "[$(date +%H:%M:%S)] $*"; }
since_stobe() { tail -n +"$BASE_L" "$L"; }
since_srv() { tail -n +"$BASE_SRV" "$SRV"; }

# heal_start "Shay [Malzin]": health 100 every 10 s (A13 v4: keeps Shay up against Hungry Bandits / weakened raiders)
# m16 fights2: every 10 s was not enough against raiders/the Dust King (Shay KO'd in 61/21/22/20 within 30 s, and a
# KO'd speaker can't talk: stobe.log `CHAT_VALIDATE: fail speaker unavailable`). Now every HEAL_EVERY s (2) + blood.
heal_start() {
  local who="${*:-Shay}"
  ( while :; do for n in $who; do stobe-auto health "$n" 100 >/dev/null 2>&1; stobe-auto blood "$n" 100% >/dev/null 2>&1; done; sleep "${HEAL_EVERY:-2}"; done ) </dev/null &
  HEALER=$!
}
# talk_ready <npc handle>: Shay awake (waits out a KO, up to 150 s) and the NPC next to her (fled raiders were 290 m off)
talk_ready() {
  local h="$1"
  for i in $(seq 1 50); do stobe-auto where Shay | grep -q " KO" || break; [ "$i" = 1 ] && log "Shay is knocked out: waiting"; stobe-say speed 1 >/dev/null; sleep 3; done
  stobe-auto where Shay | grep -q " KO" && log "Shay still KO"
  if [ -n "$h" ]; then
    local dist; dist=$(stobe-auto where "$h" | grep -oE 'dist=[0-9.]+' | cut -d= -f2 | cut -d. -f1)
    [ "${dist:-0}" -gt 12 ] && { stobe-auto teleport "$h" Shay dist 4 >/dev/null; log "brought $h back from ${dist} m"; }
  fi
  stobe-auto select Shay >/dev/null
}
# say_to <npc handle> <name> <text>: talk_ready, then the line (no --wait: sleeps 15 s after)
say_to() { talk_ready "$1"; stobe-say say "$2" "$3" --wait 15 >/dev/null 2>&1 || log "say failed"; }
heal_stop() { [ -n "$HEALER" ] && kill "$HEALER" 2>/dev/null; HEALER=""; }
trap 'heal_stop; stobe-auto speed 0 >/dev/null 2>&1' EXIT

# Malzin out of the way (the surrender recipe): KO'd 40 m off for <s> seconds, so she doesn't finish the raider
park_malzin() { stobe-auto teleport Malzin Shay dist 40 >/dev/null; stobe-auto ko Malzin "${1:-300}" >/dev/null; }

# wait_personal_guard: item 87, a previous personal fight's 180 s guard stands down new attackers
wait_personal_guard() {
  for i in $(seq 1 40); do
    local reg end
    reg=$(grep -a -n "PERSONAL_FIGHT: registered" "$L" | tail -1 | cut -d: -f1)
    end=$(grep -a -n "PERSONAL_FIGHT: ended" "$L" | tail -1 | cut -d: -f1)
    [ -z "$reg" ] && return 0
    [ -n "$end" ] && [ "$end" -gt "$reg" ] && return 0
    stobe-say speed 1 >/dev/null; sleep 5
  done
}

# spawn_raiders <n> [template]: n raiders of a weakened raid squad next to Shay (rest sent 3000 away); prints handles
spawn_raiders() {
  local n="${1:-1}" t="${2:-Bandit Raiders (weakened) 1}" k=0
  if [ "$t" = "Bandit Raiders (weakened) 1" ]; then
    stobe-auto spawn "$t" "Starving Bandits" near Shay dist 4 count 1 target Shay size 0.1 >/dev/null
  else
    stobe-auto spawn "$t" "Starving Bandits" near Shay dist 4 count 1 >/dev/null
  fi
  sleep 1
  # m16: in-process (scenarios.sh raiders ran outside the lock) and every kept raider gets a unique name:
  # three "Dust Bandit"s can't be told apart by stobe_say or the deal list (22), and reloads reuse old names (117)
  local names=("Garro Vex" "Tannik Rule" "Morb Ashel" "Vesk Arlo" "Quill Darrow")
  local found=""
  for try in 1 2 3; do  # m16 (21, 20): "no raider" right after the spawn; look again, wider
    found=$(stobe-auto chars 300 | tr '|' '\n' | grep 'Starving Bandits' | grep -v -e ' DEAD' -e ' KO' | grep -oE '#[0-9]+/[0-9]+')
    [ -n "$found" ] && break; sleep 2
  done
  [ -n "$found" ] || log "no Starving Bandits within 300 after the spawn: $(stobe-auto chars 300 | cut -c1-300)" >&2
  for s in $found; do
    if [ "$k" -lt "$n" ]; then
      stobe-auto teleport "$s" Shay dist 3 >/dev/null
      [ "${KEEP_TEMPLATE_NAME:-0}" = 1 ] || stobe-auto setname "$s" "${names[$k]}" >/dev/null
      echo "$s"; k=$((k+1))
    else stobe-auto teleport "$s" Shay dist 3000 >/dev/null; fi
  done
}

# wait_accept <name> <seconds>: until the newest deal for <name> is accepted; a COUNTERED deal is printed and
# accepted once per round ("<name>, deal.") - m16: Senlin countered and the wrapper never answered
wait_accept() {
  local who="$1" end=$(( $(date +%s) + ${2:-60} )) answered="" line id
  while [ "$(date +%s)" -lt "$end" ]; do
    line=$(deal_line "$who")
    if echo "$line" | grep -q -E "ACCEPTED|AWAITING|WAITING_FOR_PLAYER|COMPLETE"; then echo "$line"; return 0; fi
    if echo "$line" | grep -q COUNTERED; then
      id=$(echo "$line" | awk '{print $1}'); local key="$id/$(echo "$line" | grep -oE 'rounds=[0-9]+')"
      if [ "$key" != "$answered" ]; then
        log "counter-offer: accepting"; deal_block "$id" | sed 's/^/    /' >&2
        stobe-say say "$who" "$who, deal." >/dev/null 2>&1; answered="$key"
      fi
    fi
    sleep 4
  done
  return 1
}

name_of() { stobe-auto where "$1" | sed -E 's/ #[0-9].*//'; }

# engage <handle>: until he really swings at Shay and the encounter exists (combat_start)
engage() {
  local r="$1" name; name=$(name_of "$r")
  stobe-say speed 1 >/dev/null
  for i in $(seq 1 15); do
    stobe-auto attack "$r" Shay >/dev/null; stobe-auto attack Shay "$r" >/dev/null
    sleep 4
    since_stobe | grep -a -F "[EVENT] combat: $name" | grep -a -q -- "-> Shay" && break
  done
  for i in $(seq 1 10); do since_stobe | grep -a -F "[EVENT] combat_start" | grep -a -q -F "$name" && return 0; sleep 2; done
  return 1
}

# deal_line <name> [state regex]: newest deal header line for <name> (negotiation_admin deals 8)
deals() { (cd /tmp && sudo -u www-data php /var/www/html/StobeServer/tools/negotiation_admin.php deals "${1:-8}" 2>/dev/null); }
deal_line() { deals 8 | grep -F "$1" | grep -E "${2:-.}" | head -1; }
deal_id() { deal_line "$@" | awk '{print $1}'; }
# deal_block <id>: header + term lines of one deal
deal_block() { deals 12 | awk -v id="$1" '$1==id{p=1;print;next} /^deal-/{p=0} p'; }
# wait_deal <name> <state regex> <seconds>: poll until the newest deal for <name> matches
wait_deal() {
  local end=$(( $(date +%s) + ${3:-60} ))
  while [ "$(date +%s)" -lt "$end" ]; do
    deal_line "$1" | grep -q -E "$2" && { deal_line "$1"; return 0; }
    sleep 4
  done
  return 1
}
money_of() { stobe-auto money "$1" 0 | grep -oE -- '-> -?[0-9]+' | grep -oE -- '-?[0-9]+$'; }  # reply: "<npc> cats A -> B"
verdict() { echo "VERDICT $1: $2"; }
