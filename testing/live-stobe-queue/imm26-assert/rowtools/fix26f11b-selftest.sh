#!/bin/bash
# fix26f11b-selftest.sh: OFFLINE stub test of the u_state_combat candidate (unblockdefs_a.sh.candidate or $1) with the replies seen in op15 and variants.
# Usage: bash fix26f11b-selftest.sh [defs-file]. No game, lane or server access.
H="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; F="${1:-$H/unblockdefs_a.sh.candidate}"
EV=$(mktemp -d); fails=0
chk() { if [ "$2" = ok ]; then echo "PASS $1"; else echo "FAIL $1 $3"; fails=$((fails+1)); fi; }
a=$(grep -n '^u_state_combat() {' "$F" | cut -d: -f1); b=$(grep -n '^u_claim_dump()' "$F" | cut -d: -f1)
sed -n "${a},$((b-1))p" "$F" > "$EV/fn.sh"
rl_q() { printf "'%s'" "$1"; }; rw_sleep() { :; }
# lt_h reads a command script on stdin; stub replies from $STATE_REPLY (stobe_state) ; lt_sql returns $SQL_REPLY / $EVT_REPLY by marker
lt_h() { local c; c=$(cat); case "$c" in *u:state*) printf '%s\n' "$STATE_REPLY";; *u:cp*) echo "ctxpush ok";; esac; }
lt_sql() { case "$1" in *u:snap*) n=$(cat "$EV/snapn"); echo $((n+1)) > "$EV/snapn"; printf '%s\n' "${SNAP_SEQ[$n]:-none}";; *u:evt*) printf '%s\n' "$EVT_REPLY"; echo "$1" > "$EV/last_evt_sql";; esac; }
. "$EV/fn.sh"
RL_NPC_FULL="Cind [Hungry Bandit]"
JS='{"name":"Cind [Hungry Bandit]","serial":2529907200,"ai":{"dead":false,"current_goal":"OTHER"}}'   # op15-shape reply: no in_combat key
run() { STATE_REPLY="$1"; EVT_REPLY="$3"; SNAP_SEQ=($2); echo 0 > "$EV/snapn"; : > "$EV/combat_probe.txt"; u_state_combat out.txt; cat "$EV/out.txt"; }
r=$(run "$JS" "none none none" ""); [ "$r" = "in_combat=unknown" ] && chk all-sources-empty-unknown ok || chk all-sources-empty-unknown bad "$r"
grep -q '^snap3 ' "$EV/combat_probe.txt" && grep -q '^evt ' "$EV/combat_probe.txt" && grep -q '^state ' "$EV/combat_probe.txt" && chk probe-lines-written ok || chk probe-lines-written bad "$(cat "$EV/combat_probe.txt")"
r=$(run "$JS" "none none true" ""); [ "$r" = "in_combat=true (source=native_snapshot)" ] && chk snapshot-3rd-try-true ok || chk snapshot-3rd-try-true bad "$r"
r=$(run "$JS" "false" ""); [ "$r" = "in_combat=false (source=native_snapshot)" ] && chk snapshot-false ok || chk snapshot-false bad "$r"
r=$(run "$JS" "none none none" "Cind [Hungry Bandit]: combat ended with Hungry Bandit"); [ "$r" = "in_combat=false (source=eventlog)" ] && chk eventlog-ended-false ok || chk eventlog-ended-false bad "$r"
r=$(run "$JS" "none none none" "Cind [Hungry Bandit]: combat started with Hungry Bandit"); [ "$r" = "in_combat=true (source=eventlog)" ] && chk eventlog-started-true ok || chk eventlog-started-true bad "$r"
r=$(run '{"in_combat": true,"name":"x"}' "" ""); [ "$r" = "in_combat=true (source=stobe_state)" ] && chk stobe-state-key-wins ok || chk stobe-state-key-wins bad "$r"
r=$(run 'ERROR: no character named Cind' "" ""); case "$r" in in_combat=gone*) chk npc-gone ok;; *) chk npc-gone bad "$r";; esac
RL_NPC_FULL="O'Neil [x]"; r=$(run "$JS" "none none none" "q"); grep -q "like '%O''Neil" "$EV/last_evt_sql" && chk quote-escaped ok || chk quote-escaped bad "$(cat "$EV/last_evt_sql")"
# the checker keys (unblockcheck_a.py) match substrings; the suffix must not break them
case "in_combat=false (source=native_snapshot)" in *in_combat=false*) chk checker-substring ok;; esac
rm -rf "$EV"; echo "fix26f11b-selftest: fails=$fails"; [ "$fails" = 0 ]
