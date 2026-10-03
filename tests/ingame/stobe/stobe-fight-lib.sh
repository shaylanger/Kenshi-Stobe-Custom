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

log() { echo "[$(date +%H:%M:%S)] $*"; }
since_stobe() { tail -n +"$BASE_L" "$L"; }
since_srv() { tail -n +"$BASE_SRV" "$SRV"; }

# heal_start "Shay [Malzin]": health 100 every 10 s (A13 v4: keeps Shay up against Hungry Bandits / weakened raiders)
heal_start() {
  local who="${*:-Shay}"
  ( while :; do for n in $who; do stobe-auto health "$n" 100 >/dev/null 2>&1; done; sleep 10; done ) </dev/null &
  HEALER=$!
}
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
  for s in $(bash "$SC" raiders); do
    if [ "$k" -lt "$n" ]; then stobe-auto teleport "$s" Shay dist 3 >/dev/null; echo "$s"; k=$((k+1))
    else stobe-auto teleport "$s" Shay dist 3000 >/dev/null; fi
  done
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
