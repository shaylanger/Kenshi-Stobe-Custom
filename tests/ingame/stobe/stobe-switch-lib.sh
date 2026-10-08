#!/usr/bin/env bash
# stobe-switch-lib.sh: helpers for the test-switch wrappers (source after stobe-fight-lib.sh; WSL, harness on).
# Server test switches (StobeServer 2b2b52d+, general_settings, OFF by default, logged when they fire):
#   NEG_TEST_INJECT            JSON {row, npc, context chat|directive|react|any, steps:[{reply fields...}]}: the model's
#                              structured reply gets these fields for the next matching turns (one step per turn).
#                              Placeholders {player} {npc} {weapon} {worn}. Server log `NEG_TEST_INJECT fired (test switch, row N)`.
#                              Context react = the drawn-weapon reaction turn (StobeServer 055e0c5+, STOBE-DRAWN.sh).
#                              Context relationship = the relationship evaluator's JSON after her turn, e.g. {"disclosed":[...]}
#                              (StobeServer 9c0fc10+, STOBE-NPCPANEL.sh NP5; fires only if the real gate evaluates the turn).
#   NEG_TEST_FORCE_INITIATIVE  JSON {row, kind surrender|assist, npc, queue_as_old_name}: the next initiative check for
#                              that NPC queues the offer without health/cooldown gates; one-shot.
#                              Server log `NEG_TEST_FORCE_INITIATIVE fired (test switch, row N)`.
# Every wrapper calls `sw_trap` right after sourcing: both switches are deleted on exit (also on errors / Ctrl-C).
PSQL() { (cd /tmp && sudo -u postgres psql -d stobe -At -c "$1"); }
sq() { printf '%s' "$1" | sed "s/'/''/g"; }  # SQL-quote
sw_set() { PSQL "DELETE FROM general_settings WHERE id='$1'; INSERT INTO general_settings (id, value) VALUES ('$1', '$(sq "$2")')" >/dev/null; log "test switch $1 on: $(echo "$2" | cut -c1-160)"; }
sw_off() { PSQL "DELETE FROM general_settings WHERE id IN ('NEG_TEST_INJECT','NEG_TEST_FORCE_INITIATIVE')" >/dev/null; log "test switches NEG_TEST_INJECT/NEG_TEST_FORCE_INITIATIVE off"; }
sw_trap() { trap 'sw_off; heal_stop; stobe-auto speed 0 >/dev/null 2>&1' EXIT; trap 'exit 130' INT TERM; }
sw_value() { PSQL "SELECT value FROM general_settings WHERE id='$1'"; }
# inject_on <row> <npc> <context> <steps json array>
inject_on() { sw_set NEG_TEST_INJECT "{\"row\":\"$1\",\"npc\":\"$2\",\"context\":\"$3\",\"steps\":$4}"; }
# force_on <row> <kind> <npc> [queue_as_old_name true|false]
force_on() { sw_set NEG_TEST_FORCE_INITIATIVE "{\"row\":\"$1\",\"kind\":\"$2\",\"npc\":\"$3\",\"queue_as_old_name\":${4:-false}}"; }
# server log since the wrapper started (fixed string grep)
srv_has() { since_srv | grep -a -F -- "$1"; }
srv_count() { since_srv | grep -a -c -F -- "$1"; }
fired() { srv_count "NEG_TEST_INJECT fired (test switch, row $1)"; }

# spawn_neutral <name> [dist]: a neutral Drifter ("Hungry Bandit", faction Drifters) renamed <name>, <dist> m (default 12;
# closer gets him attacked by the squad) from the player. Prints the handle #serial/index.
spawn_neutral() {
  local out h
  out=$(stobe-auto spawn "Hungry Bandit" Drifters near ${PLAYER} dist "${2:-12}" count 1)
  h=$(echo "$out" | grep -oE '#[0-9]+/[0-9]+' | head -1)
  [ -n "$h" ] || { log "spawn failed: $out"; return 1; }
  stobe-auto setname "$h" "$1" >/dev/null
  echo "$h"
}
# talk <npc name> <text> [wait s]: the player says it (stobe-say speaks as the selected character), then waits
talk() { stobe-auto select ${PLAYER} >/dev/null; stobe-say say "$1" "$2" >/dev/null 2>&1 || log "say failed"; sleep "${3:-18}"; }
# greet <npc name>: a first line so the server has his profile
greet() { talk "$1" "Hello $1. Easy, I'm just talking." 15; }
# equipped item names of a handle (one per line)
equipped_items() { stobe-auto inv "$1" | grep -oE '"name":"[^"]*","count":[0-9]+,"equipped":true' | sed -E 's/"name":"([^"]*)".*/\1/'; }
WEAPON_RE='katana|sabre|saber|sword|nodachi|wakizashi|machete|cleaver|blade|knife|dagger|jitte|club|mace|hammer|axe|plank|stick|pick|polearm|naginata|halberd|spear|staff|chopper|falling sun|cross|topknot|bow|harpoon|weapon'
first_worn() { equipped_items "$1" | grep -v -i -E "$WEAPON_RE" | head -1; }
first_weapon() { equipped_items "$1" | grep -i -E "$WEAPON_RE" | head -1; }
# newest deal row for <npc> since the wrapper started: id|status|kind|proposer|terms json|evidence json
deal_row() {
  PSQL "SELECT contract_id||'|'||status||'|'||COALESCE(kind,'')||'|'||COALESCE(proposer,'')||'|'||COALESCE(terms::text,'')||'|'||COALESCE(evidence::text,'')
        FROM stobe_social_contract WHERE LOWER(npc_name)=LOWER('$(sq "$1")') AND created_at >= to_timestamp(${WRAP_START} - 5)
        ORDER BY updated_at DESC LIMIT 1"
}
# cancel_deals <npc>: close the wrapper's open deals with him (no reputation effect)
cancel_deals() {
  PSQL "UPDATE stobe_social_contract SET status='CANCELLED', consequences_applied=TRUE, resolved_at=NOW(), updated_at=NOW()
        WHERE LOWER(npc_name)=LOWER('$(sq "$1")') AND status IN ('PROPOSED','COUNTERED','ACCEPTED','AWAITING_PERFORMANCE')
          AND created_at >= to_timestamp(${WRAP_START} - 5)" >/dev/null
}
# the NPC's spoken lines since the wrapper started, one per utterance. m22 (C29 m21): each line is logged twice
# (CHAT_TIMING "pipe queued" + HOOK_MSG_PROC "Processing", same UTTERANCEID), which counted as a repeat; only the
# HOOK_MSG_PROC lines count, once per UTTERANCEID (lines without an id are kept as they are).
npc_said() {
  since_stobe | grep -a -F "NPC_SAY: $1|" | grep -a -F "HOOK_MSG_PROC" \
    | awk 'match($0, /\[UTTERANCEID:[^]]*\]/) { u = substr($0, RSTART, RLENGTH); if (seen[u]++) next } { print }' | cut -c1-300
}
# put a spawned helper NPC out of the way (knocked out 15 min)
put_away() { for h in "$@"; do [ -n "$h" ] && stobe-auto ko "$h" 900 >/dev/null 2>&1; done; }
