#!/usr/bin/env bash
# fix20a19e_selftest.sh: offline unit test (stubbed lt_sql/lt_h/rl_resolve; no game, ssh, WSL, DB) of tripdefs.sh.candidate tr_faction_guard / tr_prompt_guard / tr_trip_setup openers
# and of the sfrdefs.sh.candidate rd_20a guard. Usage: bash rowtools/fix20a19e_selftest.sh [suffix]   (suffix "" = test the installed tripdefs.sh/sfrdefs.sh, default ".candidate")
H="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; SUF="${1-.candidate}"
n=0; ok=0; chk() { n=$((n+1)); if [ "$2" = ok ]; then ok=$((ok+1)); echo "SELFTEST f20-$1 PASS ${3:-}"; else echo "SELFTEST f20-$1 FAIL ${3:-}"; fi; }
T=$(mktemp -d); EV="$T/ev"; mkdir -p "$EV"; LOG="$T/calls.log"; : > "$LOG"
rl_q() { printf "'%s'" "$1"; }
rl_resolve() { RL_NPC_FULL="${RL_NPC_FULL:-Cind [Hungry Bandit]}"; RL_NPC_ID="#1/2"; echo "resolve $*" >> "$LOG"; }
rd_need_npc() { rl_resolve; }; rd_aff() { :; }; tr_quiet() { :; }
lt_h() { cat >> "$LOG"; }
FAC="Nameless [204-gamedata.base]"; lt_sql() { case "$1" in *"from core_npc"*) echo "$FAC";; *) :;; esac; }
rl_say() { echo "say $1|$2" >> "$LOG"; mkdir -p "$EV/s$1"; [ -n "${SAYPROP:-}" ] && printf '%s\n' "$SAYPROP" > "$EV/s$1/prompt.txt"; [ -n "${AGRFILE_PROPOSED:-}" ] && [ "$1" = "$AGRFILE_PROPOSED" ] && echo '"status":"PROPOSED"' > "$EV/s$1/ev_full.txt"; return 0; }
tr_agr() { :; }
. "$H/tripdefs.sh$SUF"
RL_NPC_FULL="Cind [Hungry Bandit]"; ROW_NPC="$RL_NPC_FULL"
# faction guard: DB says Nameless -> the lane's stobe-auto faction command is sent, with the Traders Guild target; never a SQL write
: > "$LOG"; rm -f "$EV/faction.txt"; tr_faction_guard
grep -q "stobe-auto faction 'Cind \[Hungry Bandit\]' \"Traders Guild\"" "$LOG" && chk faction-restore-sent ok || chk faction-restore-sent bad "$(cat "$LOG")"
grep -q 'db_faction_before=Nameless' "$EV/faction.txt" && chk faction-evidence ok || chk faction-evidence bad
# DB says Traders Guild -> nothing sent
FAC="Traders Guild [1088-gamedata.base]"; : > "$LOG"; tr_faction_guard
grep -q "stobe-auto faction" "$LOG" && chk faction-untouched-when-ok bad || chk faction-untouched-when-ok ok
FAC="Nameless [204-gamedata.base]"; : > "$LOG"; TRIP_REFACTION=0 tr_faction_guard
grep -q "stobe-auto faction" "$LOG" && chk faction-skip-env bad || chk faction-skip-env ok
# the guard writes only through stobe-auto (no direct SQL write): the stub lt_sql only sees selects
# prompt guard
unset KAH_ROW_FAKE; mkdir -p "$EV/s1"
printf 'x\nThis NPC is already in the player faction/squad\n' > "$EV/s1/prompt.txt"; tr_prompt_guard 1; rc=$?
[ $rc = 3 ] && echo "$RL_REASON" | grep -q 'player faction' && chk prompt-guard-player-faction ok || chk prompt-guard-player-faction bad "rc=$rc"
printf 'x\nThe NPC is outside the player faction\n' > "$EV/s1/prompt.txt"; tr_prompt_guard 1; rc=$?
[ $rc = 3 ] && echo "$RL_REASON" | grep -q "Live willingness and travel consent" && chk prompt-guard-missing-section ok || chk prompt-guard-missing-section bad "rc=$rc $RL_REASON"
printf 'x\nLive willingness and travel consent\nThe NPC is outside the player faction\n' > "$EV/s1/prompt.txt"; tr_prompt_guard 1; rc=$?
[ $rc = 0 ] && chk prompt-guard-ok ok || chk prompt-guard-ok bad "rc=$rc"
# tr_trip_setup: three openers, accept only after PROPOSED
TR_DEST=Squin; SAYPROP=$'Live willingness and travel consent\n'
rm -rf "$EV"/s*; : > "$LOG"; tr_trip_setup; rc=$?
[ $rc = 3 ] && grep -q 'say 1c|Walk with me to Squin.' "$LOG" && ! grep -q '^say 2|' "$LOG" && echo "$RL_REASON" | grep -q 'no PROPOSED' && chk no-proposed-no-accept ok || chk no-proposed-no-accept bad "rc=$rc $(grep '^say' "$LOG" | tr '\n' ';')"
rm -rf "$EV"/s*; : > "$LOG"; AGRFILE_PROPOSED=1c tr_trip_setup; rc=$?
[ $rc = 0 ] && grep -q '^say 2|' "$LOG" && chk proposed-on-1c-then-accept ok || chk proposed-on-1c-then-accept bad "rc=$rc"
rm -rf "$EV"/s*; : > "$LOG"; AGRFILE_PROPOSED=1 tr_trip_setup; rc=$?
[ $rc = 0 ] && ! grep -q '^say 1b' "$LOG" && chk proposed-on-1 ok || chk proposed-on-1 bad "rc=$rc"
# SETUP-FAIL when the s1 prompt is the player-faction one (before any accept)
rm -rf "$EV"/s*; : > "$LOG"; SAYPROP=$'This NPC is already in the player faction/squad' tr_trip_setup; rc=$?
[ $rc = 3 ] && ! grep -q '^say 1b' "$LOG" && chk s1-player-faction-setup-fail ok || chk s1-player-faction-setup-fail bad "rc=$rc"
# rd_20a guard (sfrdefs): static checks of the candidate text
S="$H/sfrdefs.sh$SUF"
grep -q 'TR_SCENE="${TR_SCENE:-${HX_SPOT_DEF:--48000 1500 2960}}"' "$S" && chk rd20a-quiet-spot ok || chk rd20a-quiet-spot bad
grep -q 'tr_has s2 ACCEPTED || tr_has s2b ACCEPTED' "$S" && chk rd20a-accepted-guard ok || chk rd20a-accepted-guard bad
for f in tripdefs.sh sfrdefs.sh hxdefs.sh unblockdefs_sfs.sh trip-selftest.sh; do [ -f "$H/$f$SUF" ] && { bash -n "$H/$f$SUF" && chk "bash-n-$f" ok || chk "bash-n-$f" bad; }; done
[ "$ok" = "$n" ] && echo "SELFTEST F20 ALL PASS $ok/$n" || echo "SELFTEST F20 ALL FAIL $ok/$n"
rm -rf "$T"
