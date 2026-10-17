#!/usr/bin/env bash
# sffc_selftest.sh (imm26-sfFixC): offline unit test (stubbed rl_say/lt_h/lt_sql/sft_arm; no game, ssh, WSL, DB) of tripdefs_sffc.sh (tr_trip_setup, rd19_trip, sffc_propose_fallback, sffc_accept)
# plus drift checks: sfrrun_fc.sh = sfrrun.sh + header + one source line, reloadrun-b_fc.sh = reloadrun-b.sh + header + one source line, and (optional, SFFC_DRY=1) the full dry-runs.
# Usage: bash rowtools/sffc_selftest.sh   ->  "SELFTEST SFFC ALL PASS n/n"
H="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
n=0; ok=0; chk() { n=$((n+1)); if [ "$2" = ok ]; then ok=$((ok+1)); echo "SELFTEST sffc-$1 PASS ${3:-}"; else echo "SELFTEST sffc-$1 FAIL ${3:-}"; fi; }
T=$(mktemp -d); EV="$T/ev"; mkdir -p "$EV"; LOG="$T/calls.log"; : > "$LOG"
LT_LANE=4080-i4; RL_NPC_FULL="Cind [Hungry Bandit]"; ROW_NPC="$RL_NPC_FULL"; TR_DEST=Squin
rl_q() { printf "'%s'" "$1"; }
rl_resolve() { RL_NPC_ID="#1/2"; }
rd_need_npc() { echo "need_npc" >> "$LOG"; return 0; }
lt_h() { cat >> "$LOG"; }
lt_sql() { :; }
rd19_dump() { echo "dump $1" >> "$LOG"; }
rd19_load() { echo "load $1" >> "$LOG"; return 0; }
tr_agr() { :; }
sleep() { :; }
PROPSTEPS=""; ACCSTEPS=""; OWNSTEPS=""; PLAYERFAC=""
rl_say() {  # rl_say <step> <text>: records the call and fabricates the step evidence from PROPSTEPS / ACCSTEPS / OWNSTEPS (space separated step names)
  echo "say $1|$2" >> "$LOG"; mkdir -p "$EV/s$1"
  if [ -n "$PLAYERFAC" ]; then printf 'This NPC is already in the player faction/squad\n' > "$EV/s$1/prompt.txt"; else printf 'Live willingness and travel consent\nThe NPC is outside the player faction\n' > "$EV/s$1/prompt.txt"; fi
  : > "$EV/s$1/ev_full.txt"; : > "$EV/s$1/reply.txt"
  case " $PROPSTEPS " in *" $1 "*) echo '"status":"PROPOSED"' >> "$EV/s$1/ev_full.txt";; esac
  case " $ACCSTEPS " in *" $1 "*) echo '"status":"ACCEPTED"' >> "$EV/s$1/ev_full.txt";; esac
  case " $OWNSTEPS " in *" $1 "*) echo 'OWNED_TRAVEL x accepted=1' >> "$EV/s$1/reply.txt";; esac
  return 0
}
. "$H/tripdefs.sh"
. "$H/tripdefs_sffc.sh"
ARM_RC=0; sft_arm() { echo "ARM rc=$ARM_RC" >> "$LOG"; [ "$ARM_RC" = 0 ] || RL_REASON="stub arm failed"; return $ARM_RC; }; sft_disarm() { echo "DISARM" >> "$LOG"; return 0; }
reset() { rm -rf "$EV"/s*; : > "$LOG"; PROPSTEPS=""; ACCSTEPS=""; OWNSTEPS=""; PLAYERFAC=""; ARM_RC=0; unset SFFC_INJECT KAH_ROW_FAKE TRIP_ACCEPT_RETRY; RL_REASON=""; }
calls() { grep -E '^(say|ARM|DISARM|load|dump)' "$LOG" | cut -d'|' -f1 | tr '\n' ';'; }

# ---- tr_trip_setup
reset; PROPSTEPS="1"; ACCSTEPS="2"; OWNSTEPS="2"; tr_trip_setup; rc=$?
[ $rc = 0 ] && [ "$(calls)" = "say 1;say 2;" ] && chk ts-happy-path ok || chk ts-happy-path bad "rc=$rc $(calls)"
reset; PROPSTEPS="1b"; ACCSTEPS="2"; OWNSTEPS="2"; tr_trip_setup; rc=$?
[ $rc = 0 ] && [ "$(calls)" = "say 1;say 1b;say 2;" ] && chk ts-proposed-on-1b ok || chk ts-proposed-on-1b bad "rc=$rc $(calls)"
reset; PROPSTEPS="1c"; ACCSTEPS="2"; OWNSTEPS="2"; tr_trip_setup; rc=$?
[ $rc = 0 ] && [ "$(calls)" = "say 1;say 1b;say 1c;say 2;" ] && ! grep -q ARM "$LOG" && chk ts-proposed-on-1c-no-arm ok || chk ts-proposed-on-1c-no-arm bad "rc=$rc $(calls)"
reset; SFFC_INJECT=0; tr_trip_setup; rc=$?
[ $rc = 3 ] && [ "$(calls)" = "say 1;say 1b;say 1c;" ] && echo "$RL_REASON" | grep -q 'SFFC_INJECT=0' && chk ts-no-proposed-inject-off-setup-fail ok || chk ts-no-proposed-inject-off-setup-fail bad "rc=$rc $(calls) $RL_REASON"
reset; PROPSTEPS="1d"; ACCSTEPS="2"; OWNSTEPS="2"; tr_trip_setup; rc=$?
[ $rc = 0 ] && [ "$(calls)" = "say 1;say 1b;say 1c;ARM rc=0;say 1d;DISARM;say 2;" ] && grep -q 'say 1d|Take me to Squin.' "$LOG" && chk ts-fallback-arms-then-1d ok || chk ts-fallback-arms-then-1d bad "rc=$rc $(calls)"
reset; ARM_RC=4; tr_trip_setup; rc=$?
[ $rc = 3 ] && ! grep -q '^say 1d' "$LOG" && ! grep -q '^say 2|' "$LOG" && echo "$RL_REASON" | grep -q 'fallback arm failed' && chk ts-arm-fails-setup-fail ok || chk ts-arm-fails-setup-fail bad "rc=$rc $(calls) $RL_REASON"
reset; tr_trip_setup; rc=$?   # armed 1d turn stores nothing either
[ $rc = 3 ] && grep -q '^say 1d' "$LOG" && ! grep -q '^say 2|' "$LOG" && echo "$RL_REASON" | grep -q 'also stored no PROPOSED' && chk ts-1d-no-proposed-setup-fail ok || chk ts-1d-no-proposed-setup-fail bad "rc=$rc $(calls) $RL_REASON"
reset; KAH_ROW_FAKE=1; tr_trip_setup; rc=$?
[ $rc = 3 ] && ! grep -q ARM "$LOG" && chk ts-no-fallback-in-fake-mode ok || chk ts-no-fallback-in-fake-mode bad "rc=$rc $(calls)"
reset; PLAYERFAC=1; tr_trip_setup; rc=$?
[ $rc = 3 ] && [ "$(calls)" = "say 1;" ] && echo "$RL_REASON" | grep -q 'player faction' && chk ts-player-faction-setup-fail-after-s1 ok || chk ts-player-faction-setup-fail-after-s1 bad "rc=$rc $(calls) $RL_REASON"
# s2 handling
reset; PROPSTEPS="1"; tr_trip_setup; rc=$?   # s2 stored no ACCEPTED (empty stream): retry in the s2b slot with the clearer accept
[ $rc = 0 ] && [ "$(calls)" = "say 1;say 2;say 2b;" ] && grep -q 'say 2b|Yes, I accept. Please lead the way to Squin.' "$LOG" && chk s2-retry-when-no-accepted ok || chk s2-retry-when-no-accepted bad "rc=$rc $(calls)"
reset; PROPSTEPS="1"; ACCSTEPS="2"; tr_trip_setup; rc=$?   # ACCEPTED but no OWNED_TRAVEL line: the old 'Lead the way.'
[ $rc = 0 ] && [ "$(calls)" = "say 1;say 2;say 2b;" ] && grep -q 'say 2b|Lead the way.' "$LOG" && chk s2-lead-the-way-when-accepted-no-native ok || chk s2-lead-the-way-when-accepted-no-native bad "rc=$rc $(calls)"
reset; PROPSTEPS="1"; TRIP_ACCEPT_RETRY="Sure, go ahead."; tr_trip_setup; rc=$?
grep -q 'say 2b|Sure, go ahead.' "$LOG" && chk s2-retry-text-env ok || chk s2-retry-text-env bad "rc=$rc $(calls)"

# ---- rd19_trip
ROW_19_DEST=Squin; ROW_19A_NC=0
reset; PROPSTEPS="1"; OWNSTEPS="2"; rd19_trip; rc=$?
[ $rc = 0 ] && [ "$(calls)" = "say 1;say 2;dump agr_pre.txt;load kah-imm26-19a-4080-i4;" ] && chk r19-happy-path-s2-s3-names ok || chk r19-happy-path-s2-s3-names bad "rc=$rc $(calls)"
reset; PROPSTEPS="1"; rd19_trip; rc=$?   # no OWNED_TRAVEL in s2: s3 'Lead the way.' as before
[ $rc = 0 ] && grep -q 'say 3|Lead the way.' "$LOG" && chk r19-s3-lead-the-way ok || chk r19-s3-lead-the-way bad "rc=$rc $(calls)"
reset; PLAYERFAC=1; rd19_trip; rc=$?
[ $rc = 3 ] && [ "$(calls)" = "need_npc;say 1;" ] || [ $rc = 3 ] && ! grep -q '^say 1b' "$LOG" && echo "$RL_REASON" | grep -q 'player faction' && chk r19-player-faction-setup-fail ok || chk r19-player-faction-setup-fail bad "rc=$rc $(calls) $RL_REASON"
reset; PROPSTEPS="1c"; rd19_trip; rc=$?
[ $rc = 0 ] && grep -q 'say 1c|Walk with me to Squin.' "$LOG" && ! grep -q ARM "$LOG" && chk r19-third-opener ok || chk r19-third-opener bad "rc=$rc $(calls)"
reset; PROPSTEPS="1d"; rd19_trip; rc=$?
[ $rc = 0 ] && grep -q 'ARM rc=0' "$LOG" && grep -q 'say 1d|Take me to Squin.' "$LOG" && grep -q 'say 2|' "$LOG" && chk r19-fallback ok || chk r19-fallback bad "rc=$rc $(calls)"
reset; SFFC_INJECT=0; rd19_trip; rc=$?
[ $rc = 3 ] && ! grep -q '^say 2|' "$LOG" && ! grep -q '^load' "$LOG" && chk r19-no-proposed-setup-fail ok || chk r19-no-proposed-setup-fail bad "rc=$rc $(calls)"
unset ROW_19_DEST   # 19-a style: no forced destination -> original s1 text and the original 1b text; fallback destination Stumble Inn
reset; PROPSTEPS="1d"; rd19_trip; rc=$?
[ $rc = 0 ] && grep -q 'say 1|Walk with me to Stumble Inn.' "$LOG" && grep -q 'say 1b|Is there a town you need to get to? Lead me there.' "$LOG" && grep -q 'say 1d|Walk with me to Stumble Inn.' "$LOG" && chk r19-default-dest-texts ok || chk r19-default-dest-texts bad "rc=$rc $(calls)"

# ---- drift: the _fc runners are the originals plus exactly the header comment and the one source line
d1=$(diff "$H/sfrrun.sh" "$H/sfrrun_fc.sh" | grep -c '^[<>]'); d1l=$(diff "$H/sfrrun.sh" "$H/sfrrun_fc.sh" | grep -c '^<')
[ "$d1" = 2 ] && [ "$d1l" = 0 ] && grep -q 'tripdefs_sffc.sh' "$H/sfrrun_fc.sh" && chk sfrrun_fc-is-sfrrun-plus-one-line ok || chk sfrrun_fc-is-sfrrun-plus-one-line bad "changed=$d1 removed=$d1l"
d2=$(diff "$H/reloadrun-b.sh" "$H/reloadrun-b_fc.sh" | grep -c '^[<>]'); d2l=$(diff "$H/reloadrun-b.sh" "$H/reloadrun-b_fc.sh" | grep -c '^<')
[ "$d2" = 2 ] && [ "$d2l" = 0 ] && grep -q 'tripdefs_sffc.sh' "$H/reloadrun-b_fc.sh" && chk reloadrun-b_fc-is-original-plus-one-line ok || chk reloadrun-b_fc-is-original-plus-one-line bad "changed=$d2 removed=$d2l"
# the source line comes after the defs it overrides
a=$(grep -n 'sfrdefs.sh' "$H/sfrrun_fc.sh" | head -1 | cut -d: -f1); b=$(grep -n '^\. .*tripdefs_sffc.sh' "$H/sfrrun_fc.sh" | head -1 | cut -d: -f1)
[ -n "$a" ] && [ -n "$b" ] && [ "$b" -gt "$a" ] && chk sfrrun_fc-source-order ok || chk sfrrun_fc-source-order bad "a=$a b=$b"
a=$(grep -n 'reloaddefs_b.sh' "$H/reloadrun-b_fc.sh" | grep '^[0-9]*:\. ' | head -1 | cut -d: -f1); b=$(grep -n '^\. .*tripdefs_sffc.sh' "$H/reloadrun-b_fc.sh" | head -1 | cut -d: -f1)
[ -n "$a" ] && [ -n "$b" ] && [ "$b" -gt "$a" ] && chk reloadrun-b_fc-source-order ok || chk reloadrun-b_fc-source-order bad "a=$a b=$b"
for f in tripdefs_sffc.sh sfrrun_fc.sh reloadrun-b_fc.sh sffc_selftest.sh; do bash -n "$H/$f" && chk "bash-n-$f" ok || chk "bash-n-$f" bad; done

# ---- optional full dry-runs against the offline fake lane (no game); evidence goes to a temp rows base, never the lane's rows dir.
# (the 19-e fake lane never fakes a PROPOSED row, so the ORIGINAL reloadrun-b.sh 19-e --dry also ends in SETUP-FAIL at s1b: the dry run only proves the script loads and reaches the trip step)
if [ "${SFFC_DRY:-0}" = 1 ]; then
  export KAH_ROWS_BASE="$T/rows" KAH_PF_ISOLATION=0
  o=$(timeout 200 bash "$H/sfrrun_fc.sh" 20-a 4080-i3 --dry --allow-retry "sffc selftest" 2>&1 | tail -3); echo "$o" | grep -q 'RESULT 20-a DRY-RUN planned' && chk dry-sfrrun_fc-20a ok || chk dry-sfrrun_fc-20a bad "$(echo "$o" | tail -1 | cut -c1-200)"
  o=$(timeout 200 bash "$H/reloadrun-b_fc.sh" 19-e 4080-i4 --dry --allow-retry "sffc selftest" 2>&1 | tail -3); echo "$o" | grep -qE 'RESULT 19-e (DRY-RUN planned|SETUP-FAIL no (trip proposed|PROPOSED travel_agreement row))' && chk dry-reloadrun-b_fc-19e ok || chk dry-reloadrun-b_fc-19e bad "$(echo "$o" | tail -1 | cut -c1-200)"
fi
[ "$ok" = "$n" ] && echo "SELFTEST SFFC ALL PASS $ok/$n" || echo "SELFTEST SFFC ALL FAIL $ok/$n"
rm -rf "$T"
[ "$ok" = "$n" ]
