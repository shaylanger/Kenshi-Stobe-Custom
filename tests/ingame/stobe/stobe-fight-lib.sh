#!/usr/bin/env bash
# stobe-fight-lib.sh: shared helpers for the STOBE fight/deal wrappers (source it; WSL, harness on).
# Paths, a background healer that keeps Shay (and optionally Malzin) up, one-raider setup that waits for
# a real fight, deal lookups via negotiation_admin.php, and log slices since the wrapper started.
# Squad names (m16: the 4080 fixtures have other squads; nothing may depend on Shay/Malzin)
PLAYER="${PLAYER:-Shay}"; MATE="${MATE:-Malzin}"
L=/mnt/d/Steam/steamapps/common/Kenshi/RE_Kenshi/mods/Stobe/stobe.log
KFP=/mnt/d/Steam/steamapps/common/Kenshi/KenshiFP.log
SRV=/var/www/html/StobeServer/log/stobeserver.log
SC=/mnt/c/KenshiModding/tools/automation/scenarios.sh
BASE_L=$(grep -a -c "" "$L" 2>/dev/null || echo 0)
BASE_SRV=$(grep -a -c "" "$SRV" 2>/dev/null || echo 0)
HEALER=""
PROTECTED=""

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

log() { echo "[$(date +%H:%M:%S)] $*" >&2; }  # stderr: functions whose stdout is captured (wait_accept) stay clean
since_stobe() { tail -n +"$BASE_L" "$L"; }
since_srv() { tail -n +"$BASE_SRV" "$SRV"; }

# heal_start "Shay [Malzin]": health 100 every 10 s (A13 v4: keeps Shay up against Hungry Bandits / weakened raiders)
# m16 fights2: every 10 s was not enough against raiders/the Dust King (Shay KO'd in 61/21/22/20 within 30 s, and a
# KO'd speaker can't talk: stobe.log `CHAT_VALIDATE: fail speaker unavailable`). Now every HEAL_EVERY s (2) + blood.
heal_start() {
  local who="${*:-${PLAYER}}"
  # m16 fights3: even 2-s heals didn't stop knockouts. Preferred: harness `protect <npc> on` (KAH: wakes a KO'd
  # character at once, keeps HP/blood full every frame). Fallback when the harness doesn't know it: the heal loop.
  PROTECTED=""
  for n in $who; do
    if stobe-auto protect "$n" on >/dev/null 2>&1; then PROTECTED="$PROTECTED $n"; fi
  done
  if [ -n "$PROTECTED" ]; then log "protect on:$PROTECTED"; return 0; fi
  log "harness has no 'protect': heal loop every ${HEAL_EVERY:-2} s"
  ( while :; do for n in $who; do stobe-auto health "$n" 100 >/dev/null 2>&1; stobe-auto blood "$n" 100% >/dev/null 2>&1; done; sleep "${HEAL_EVERY:-2}"; done ) </dev/null &
  HEALER=$!
}
heal_stop() {
  [ -n "$HEALER" ] && kill "$HEALER" 2>/dev/null; HEALER=""
  for n in ${PROTECTED:-}; do stobe-auto protect "$n" off >/dev/null 2>&1; done
  [ -n "${PROTECTED:-}" ] && log "protect off:$PROTECTED"; PROTECTED=""
}
trap 'heal_stop; stobe-auto speed 0 >/dev/null 2>&1' EXIT

# talk_ready <npc handle>: the player awake (waits out a KO, up to 150 s) and the NPC next to them (fled raiders
# were 290 m off). Restored after m16 fights4 (the protect change had dropped it: "say_to: command not found").
talk_ready() {
  local h="$1"
  for i in $(seq 1 50); do stobe-auto where ${PLAYER} | grep -q " KO" || break; [ "$i" = 1 ] && log "${PLAYER} is knocked out: waiting"; stobe-say speed 1 >/dev/null; sleep 3; done
  stobe-auto where ${PLAYER} | grep -q " KO" && log "${PLAYER} still KO"
  if [ -n "$h" ]; then
    local dist; dist=$(stobe-auto where "$h" | grep -oE 'dist=[0-9.]+' | cut -d= -f2 | cut -d. -f1)
    [ "${dist:-0}" -gt 12 ] && { stobe-auto teleport "$h" ${PLAYER} dist 4 >/dev/null; log "brought $h back from ${dist} m"; }
  fi
  stobe-auto select ${PLAYER} >/dev/null
}
# say_to <npc handle> <name> <text>: talk_ready, then the line (no --wait: sleeps 15 s after)
say_to() { talk_ready "$1"; stobe-say say "$2" "$3" --wait 15 >/dev/null 2>&1 || log "say failed"; }

# Malzin out of the way (the surrender recipe): KO'd 40 m off for <s> seconds, so she doesn't finish the raider
park_malzin() { stobe-auto protect ${MATE} off >/dev/null 2>&1; stobe-auto teleport ${MATE} ${PLAYER} dist 40 >/dev/null; stobe-auto ko ${MATE} "${1:-300}" >/dev/null; }  # protect (fullbase-guard) would block the ko

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
    stobe-auto spawn "$t" "Starving Bandits" near ${PLAYER} dist 4 count 1 target ${PLAYER} size 0.1 >/dev/null
  else
    stobe-auto spawn "$t" "Starving Bandits" near ${PLAYER} dist 4 count 1 >/dev/null
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
      stobe-auto teleport "$s" ${PLAYER} dist 3 >/dev/null
      [ "${KEEP_TEMPLATE_NAME:-0}" = 1 ] || stobe-auto setname "$s" "${names[$k]}" >/dev/null
      echo "$s"; k=$((k+1))
    else stobe-auto teleport "$s" ${PLAYER} dist 3000 >/dev/null; fi
  done
}

# wait_accept <name> <seconds>: until the newest deal for <name> is accepted; a COUNTERED deal is printed and
# accepted once per round ("<name>, deal.") - m16: Senlin countered and the wrapper never answered
# wait_accept <name> [seconds] [handle]: accepts his counter-offer with "<name>, deal.". m22 (STOBE-18 m21): his
# reply to "deal." came while he was knocked out and was dropped (item 48), the counter stayed at rounds=0 and the
# old code never answered again. Now the same counter is answered again after 25 s without a change (max 3 tries),
# and with a handle a KO'd NPC is woken first (protect on + wait for the KO to clear) so his answer is kept.
wait_accept() {
  local who="$1" end=$(( $(date +%s) + ${2:-60} )) h="${3:-}" answered="" line id tries=0 last=0 i
  while [ "$(date +%s)" -lt "$end" ]; do
    line=$(deal_line "$who")
    if echo "$line" | grep -q -E "ACCEPTED|AWAITING|WAITING_FOR_PLAYER|COMPLETE"; then echo "$line"; return 0; fi
    if echo "$line" | grep -q COUNTERED; then
      id=$(echo "$line" | awk '{print $1}'); local key="$id/$(echo "$line" | grep -oE 'rounds=[0-9]+')"
      if [ "$key" != "$answered" ] || { [ "$tries" -lt 3 ] && [ $(( $(date +%s) - last )) -ge 25 ]; }; then
        [ "$key" != "$answered" ] && tries=0
        if [ -n "$h" ]; then
          for i in 1 2 3 4 5; do stobe-auto where "$h" | grep -q " KO" || break; [ "$i" = 1 ] && { log "$who is KO: waking before accepting"; stobe-auto protect "$h" on >/dev/null 2>&1; }; sleep 3; done
        fi
        tries=$((tries+1)); log "counter-offer: accepting (try $tries)"; [ "$tries" = 1 ] && deal_block "$id" | sed 's/^/    /' >&2
        stobe-say say "$who" "$who, deal." >/dev/null 2>&1; answered="$key"; last=$(date +%s)
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
    stobe-auto attack "$r" ${PLAYER} >/dev/null; stobe-auto attack ${PLAYER} "$r" >/dev/null
    sleep 4
    since_stobe | grep -a -F "[EVENT] combat: $name" | grep -a -q -- "-> ${PLAYER}" && break
  done
  for i in $(seq 1 10); do since_stobe | grep -a -F "[EVENT] combat_start" | grep -a -q -F "$name" && return 0; sleep 2; done
  return 1
}

# deal_line <name> [state regex]: newest deal header line for <name> (negotiation_admin deals 8)
deals() { (cd /tmp && sudo -u www-data php /var/www/html/StobeServer/tools/negotiation_admin.php deals "${1:-8}" 2>/dev/null); }
# m16 next (18): names repeat across runs (Garro Vex), so only deals created since this wrapper started count.
WRAP_START=$(date +%s)
deal_line() {
  (cd /tmp && sudo -u postgres psql -d stobe -At -F '  ' -c "SELECT contract_id, npc_name, status, 'kind=' || COALESCE(kind,'') || ' by=' || COALESCE(proposer,'') || ' rounds=' || COALESCE(rounds,0) || ' updated=' || updated_at
      FROM stobe_social_contract WHERE LOWER(npc_name)=LOWER('$(echo "$1" | sed "s/'/''/g")') AND created_at >= to_timestamp(${WRAP_START} - 5)
      ORDER BY updated_at DESC LIMIT 5" 2>/dev/null) | grep -E "${2:-.}" | head -1
}
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
# m22: game-time helpers. PSQLQ runs one query; srv_gamets = the newest game time the server has seen (the clock the
# deal deadlines use: MAX(eventlog.gamets) over the last 10 min); deal_field <id> <column>; deal_terms <id> prints
# "by:KIND:STATUS" per term (space separated), so a wrapper can see an NPC action still in flight (DISPATCHED).
PSQLQ() { (cd /tmp && sudo -u postgres psql -d stobe -At -c "$1" 2>/dev/null); }
srv_gamets() { PSQLQ "SELECT COALESCE(MAX(gamets),0) FROM eventlog WHERE localts >= EXTRACT(EPOCH FROM NOW())::bigint - 600"; }
deal_field() { PSQLQ "SELECT COALESCE($2::text,'') FROM stobe_social_contract WHERE contract_id='$1'"; }
deal_terms() {
  PSQLQ "SELECT string_agg(COALESCE(t->>'by','') || ':' || COALESCE(t->>'kind','') || ':' || COALESCE(t->>'status',''), ' ')
         FROM stobe_social_contract c, jsonb_array_elements(CASE WHEN jsonb_typeof(c.term_state::jsonb)='array' THEN c.term_state::jsonb ELSE '[]'::jsonb END) t
         WHERE c.contract_id='$1'"
}
money_of() { stobe-auto money "$1" 0 | grep -oE -- '-> -?[0-9]+' | grep -oE -- '-?[0-9]+$'; }  # reply: "<npc> cats A -> B"
# verdict <row> <text>: the human line, plus ONE token-light line per row (Shay, 2026-10-03):
# "RESULT <row> PASS|FAIL <evidence>" (anything that isn't PASS counts as FAIL; INCONCLUSIVE/SETUP kept in the text),
# with the run's log path on FAIL (RESULT_LOG, default the wrapper's stdout file if the caller exports it).
verdict() {
  echo "VERDICT $1: $2"
  local st=FAIL; case "$2" in PASS*) st=PASS ;; esac
  local ev="${2#PASS }"; ev="${ev//$'
'/ }"
  if [ "$st" = PASS ]; then echo "RESULT $1 PASS ${ev:0:200}"; else echo "RESULT $1 FAIL ${ev:0:200}${RESULT_LOG:+ log=$RESULT_LOG}"; fi
}
# RAID_RE: world-raid factions that reach the squad on Full-Base (m17 Band of Bones; m24 Bele'coz, Hill Marauders,
# Black Dragon Ninjas; m22 J Kral's Chosen). RAID_FILTER: the same for the harness `chars <r> <filter>` (m26).
RAID_RE="${RAID_RE:-Band of Bones|Kral.s Chosen|Dust Bandits|Hungry Bandits|Starving Bandits|Bele.coz|Hill Marauders|Black Dragon Ninjas}"
RAID_FILTER="${RAID_FILTER:-[band of bones]|[kral|[dust bandits]|[hungry bandits]|[starving bandits]|[bele|[hill marauders]|[black dragon ninjas]}"
# calm_raiders [radius] [factions-regex]: knock out world raiders near the squad for RAID_KO_S game seconds (Full-Base
# gets raids that reach the squad mid-test, m17); logs how many
calm_raiders() {
  local n=0 h re="${2:-$RAID_RE}" flt=""
  [ -z "${2:-}" ] && flt="$RAID_FILTER"
  # m24 fixer 14: `chars` prints ONE line ("a | b | c"), so the faction grep matched the whole line whenever any raider
  # was in range and every handle in it was knocked out, the squad included (harness.log: `ko Beaks`/`ko Avarek` every
  # 30 s; 16-fullbase Avarek KO x3, A8-grow-fb Beaks KO). Split per character first; never touch the squad; skip ones
  # already KO/DEAD.
  # m26: `chars` lists at most 40 (unsorted) and Full-Base has more within 1500 m, so raiders were cut off (m22 J:
  # Kral's Chosen hit Beaks in 16-fullbase, Band of Bones KO'd Beaks in A8). The harness filter (KAH chars [filter])
  # applies before the cap; an older harness ignores it and the faction grep below still filters.
  # m26: `ko` seconds are game seconds: 900 lasted ~18 s at 50x; RAID_KO_S (6 game hours) outlasts a sweep interval.
  local r lines seen=" "
  for r in 400 "${1:-400}"; do
    lines=$(stobe-auto chars "$r" ${flt:+"$flt"} | sed 's/^[0-9]* within [0-9.]*: //' | tr '|' '\n' | sed 's/^ *//' \
      | grep -E "\[(${re})\]" | grep -v -E ' (KO|DEAD)( |$)' | grep -v -E "^(${PLAYER:-Shay}|${MATE:-Malzin}) #")
    for h in $(echo "$lines" | grep -oE '#[0-9]+/[0-9]+'); do
      case "$seen" in *" $h "*) continue ;; esac; seen="$seen$h "
      stobe-auto ko "$h" "${RAID_KO_S:-21600}" >/dev/null && n=$((n+1))
    done
    [ "${1:-400}" = 400 ] && break
  done
  log "calm_raiders: knocked out $n"
}
# raid_guard_start [every_s] / raid_guard_stop (m26, Full-Base rows): the squad stays protected (fullbase-guard.sh)
# and a background sweep knocks out raiders within 1500 m every RAID_GUARD_EVERY s (10) for the whole row; knockouts
# are logged (stderr) so a row shows when raids happened. Call raid_guard_stop in the EXIT trap.
raid_guard_start() {
  local every="${1:-${RAID_GUARD_EVERY:-10}}"
  calm_raiders 1500
  ( while sleep "$every"; do calm_raiders 1500 2>&1 | grep -v 'knocked out 0$' >&2; done ) </dev/null &
  RAID_GUARD=$!
  log "raid_guard: sweeping raiders within 1500 m every ${every} s (pid $RAID_GUARD)"
}
raid_guard_stop() { [ -n "${RAID_GUARD:-}" ] && kill "$RAID_GUARD" 2>/dev/null; RAID_GUARD=""; }
# raid_event <stobe [EVENT] line>: 0 when a combat/knockout event against the squad comes from a world raider
# (RAID_RE faction; a knockout names only the attacker, so his faction comes from his combat lines since the test
# start). Alerts skip these on protected Full-Base rows; anything else (guards, shop owners, the mate) still alerts.
raid_event() {
  local line who
  line=$(printf '%s' "$1" | tr -d '\r')
  echo "$line" | grep -q -a -E "combat: .* \((${RAID_RE})\) -> " && return 0
  who=$(echo "$line" | grep -a -oE "knockout: .* from .*\)$" | sed -E 's/.* from (.*)\)$/\1/')
  [ -n "$who" ] || return 1
  since_stobe | grep -a -F "combat: $who (" | grep -q -a -E "combat: .* \((${RAID_RE})\) -> "
}
awake() { ! stobe-auto where "$1" 2>&1 | grep -q -E " (KO|DEAD)( |$)"; }

# --- setup checks (Shay 2026-10-04: check setup before long tests; bounded polls, specific SETUP FAIL reason) ---
# wait_for <secs> <cmd...>: poll every 2 s until cmd succeeds; 1 on timeout (use instead of long fixed sleeps)
wait_for() { local t=$(( $(date +%s) + $1 )); shift; until "$@" >/dev/null 2>&1; do [ "$(date +%s)" -ge "$t" ] && return 1; sleep 2; done; }
# selected_is <name>: the selected character (harness @selected) is <name>
selected_is() { stobe-auto where @selected 2>/dev/null | grep -q "^$1 #"; }
# setup_fail <row> <reason>: one SETUP FAIL verdict and exit 4 (run-batch counts it as FAIL; repair setup, then rerun)
setup_fail() { verdict "$1" "SETUP FAIL $2"; exit 4; }
# stobe_ready [secs] [base_line] / stobe_log_lines: wait for the Stobe NPC event sweep after a load (stobe-ready.sh)
source "$(dirname "${BASH_SOURCE[0]}")/stobe-ready.sh"
# srv_faction <name>: the server's core_npc faction for <name> ('' = unknown/not synced yet)
srv_faction() { PSQLQ "SELECT COALESCE(faction,'') FROM core_npc WHERE LOWER(name)=LOWER('$1') ORDER BY updated_at DESC LIMIT 1"; }
# srv_squad_synced: the server has PLAYER and MATE in the same (non-empty) faction. m25 (A8): right after a load the
# playthrough rollback could drop the squad rows and the next chat re-created them faction-less -> orders to the
# mate were treated as a stranger's (no goal inferred). Orders/goal rows wait for this.
srv_squad_synced() { local p m; p=$(srv_faction "$PLAYER"); m=$(srv_faction "$MATE"); [ -n "$p" ] && [ "$p" = "$m" ]; }
# preflight <row> [save=<name>] [advancing] [squad] [npc ...]: world loaded (and the expected save), OUT dir exists, PLAYER selected,
# PLAYER/MATE (and each npc) present and not KO/DEAD, game time advancing when asked (unpauses at 1x for the check),
# squad: the server knows MATE as PLAYER's faction member (bounded 90 s wait for the NPC sync after a load)
preflight() {
  local row="$1" save="" adv=0 sq=0 st w n h1 h2; shift
  [ -n "${OUT:-}" ] && { mkdir -p "$OUT" || setup_fail "$row" "cannot create OUT=$OUT"; }
  st=$(stobe-auto status)
  case "$st" in *phase=world*) ;; *) setup_fail "$row" "game not in the world: $st" ;; esac
  for n in "$@"; do case "$n" in save=*) save="${n#save=}" ;; advancing) adv=1 ;; squad) sq=1 ;; esac; done
  [ -n "$save" ] && ! echo "$st" | grep -q " save=$save " && setup_fail "$row" "wrong save (want $save): $st"
  # m23: status player= is the first squad member, not the selection (Full-Base lists Avarek first): check @selected
  selected_is "$PLAYER" || { stobe-auto select "$PLAYER" >/dev/null; wait_for 10 selected_is "$PLAYER" || setup_fail "$row" "cannot select $PLAYER (selected: $(stobe-auto where @selected 2>&1 | cut -c1-60))"; }
  for n in "$PLAYER" "$MATE" "$@"; do
    case "$n" in save=*|advancing|squad|'') continue ;; esac
    w=$(stobe-auto where "$n" 2>&1)
    echo "$w" | grep -q "#[0-9]" || setup_fail "$row" "no character '$n' ($w)"
    echo "$w" | grep -q -E " (KO|DEAD)" && setup_fail "$row" "'$n' is KO/DEAD ($w)"
  done
  if [ "$adv" = 1 ]; then
    local sp; sp=$(stobe-auto time | grep -oE "speed=[0-9.]+" | cut -d= -f2)
    [ "${sp%.*}" = 0 ] && stobe-auto speed 1 >/dev/null
    h1=$(stobe-auto time | grep -oE "game_hours=[0-9.]+" | cut -d= -f2); sleep 3
    h2=$(stobe-auto time | grep -oE "game_hours=[0-9.]+" | cut -d= -f2)
    awk -v a="${h1:-0}" -v b="${h2:-0}" 'BEGIN{exit !(b>a)}' || setup_fail "$row" "game time not advancing ($h1 -> $h2)"
    [ "${sp%.*}" = 0 ] && stobe-auto speed 0 >/dev/null
  fi
  if [ "$sq" = 1 ]; then
    wait_for 90 srv_squad_synced || setup_fail "$row" "server does not know $MATE as $PLAYER's squad (faction: $PLAYER='$(srv_faction "$PLAYER")' $MATE='$(srv_faction "$MATE")')"
  fi
  log "preflight $row ok"
}
