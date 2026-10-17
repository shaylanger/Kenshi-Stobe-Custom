#!/usr/bin/env bash
# hxd_retry_selftest.sh: offline test of the cancelled-reply retry-once in hxd_sample (hxdefs.sh.candidate), imm26-fix17bxcheck.
# Usage: bash rowtools/hxd_retry_selftest.sh [hxdefs.sh|hxdefs.sh.candidate]   -> prints SELFTEST hxrt-<name> PASS|FAIL and SELFTEST HXRT ALL PASS|FAIL n/m
H="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; F="${1:-$H/hxdefs.sh.candidate}"; [ -f "$F" ] || F="$H/$F"
n=0; ok=0; chk() { n=$((n+1)); if [ "$2" = ok ]; then ok=$((ok+1)); echo "SELFTEST hxrt-$1 PASS ${3:-}"; else echo "SELFTEST hxrt-$1 FAIL ${3:-}"; fi; }
T=$(mktemp -d); EV="$T/ev"; HXD="$T/hxd"; mkdir -p "$EV" "$HXD"
eval "$(sed -n '/^hxd_sample() {/,/^}/p' "$F")"
declare -F hxd_sample >/dev/null && chk defined ok || { chk defined bad "no hxd_sample in $F"; echo "SELFTEST HXRT ALL FAIL $ok/$n"; exit 1; }
# stubs: MODE=ok (spoken first try) | cancel1 (first try cancelled, second spoken) | cancel2 (both cancelled) | silent (no reply, no cancelled row)
calls=0; MODE=ok
ROW_NPC="Cind [Hungry Bandit]"; ROW_SETTLE=0; LT_STOBELOG=/dev/null
rl_resolve() { RL_NPC_FULL="Cind [Hungry Bandit]"; RL_NPC_ID="#1/1"; return 0; }
rl_prep_player() { return 0; }
rl_mark() { echo 0; }
rl_q() { printf "'%s'" "$1"; }
lt_h() { cat >/dev/null; }
hxd_sleep() { :; }
hxd_dry() { return 1; }
rl_bundle() {  # $1 = bundle dir
  calls=$((calls+1)); local spoken=0 canc=0
  case "$MODE" in ok) spoken=1;; cancel1) [ $calls = 1 ] && canc=1 || spoken=1;; cancel2) canc=1;; esac
  : > "$1/events.txt"; : > "$1/effects.txt"; : > "$1/meta.txt"; echo "resolved_speaker=Shay" > "$1/reply.txt"
  [ $canc = 1 ] && echo "44006|chat|Cind: x (talking to: Shay)|cancelled" > "$1/events.txt"
  [ $spoken = 1 ] && echo "ACTION_EXEC: SAY [Cind] hello (NPC)" >> "$1/reply.txt"
  return 0
}
MODE=ok; calls=0; unset HXD_RETRIED; hxd_sample S1 hi "$ROW_NPC" 1 >/dev/null 2>&1; rc=$?
[ $rc = 0 ] && [ $calls = 1 ] && chk spoken-first-try-no-retry ok || chk spoken-first-try-no-retry bad "rc=$rc calls=$calls"
rm -rf "$HXD"/* "$EV"/*; MODE=cancel1; calls=0; unset HXD_RETRIED; hxd_sample S1 hi "$ROW_NPC" 1 >/dev/null 2>&1; rc=$?
[ $rc = 0 ] && [ $calls = 2 ] && chk cancelled-then-spoken-retried-once ok || chk cancelled-then-spoken-retried-once bad "rc=$rc calls=$calls"
[ -d "$EV/retry/S1-try1" ] && [ -s "$EV/retry/S1-cancelled.txt" ] && grep -q cancelled "$EV/phases.txt" && chk first-try-kept-as-evidence ok || chk first-try-kept-as-evidence bad
rm -rf "$HXD"/* "$EV"/*; MODE=cancel2; calls=0; unset HXD_RETRIED; RL_REASON=""; hxd_sample S1 hi "$ROW_NPC" 1 >/dev/null 2>&1; rc=$?
[ $rc = 3 ] && [ $calls = 2 ] && chk second-cancellation-fails-after-one-retry ok || chk second-cancellation-fails-after-one-retry bad "rc=$rc calls=$calls"
case "$RL_REASON" in *"no reply of"*"AND the retry produced a cancelled"*) chk second-cancellation-named ok;; *) chk second-cancellation-named bad "$RL_REASON";; esac
rm -rf "$HXD"/* "$EV"/*; MODE=silent; calls=0; unset HXD_RETRIED; RL_REASON=""; hxd_sample S1 hi "$ROW_NPC" 1 >/dev/null 2>&1; rc=$?
[ $rc = 3 ] && [ $calls = 1 ] && chk plain-no-reply-fails-without-retry ok || chk plain-no-reply-fails-without-retry bad "rc=$rc calls=$calls"
rm -rf "$HXD"/* "$EV"/*; MODE=silent; calls=0; unset HXD_RETRIED; hxd_sample S1 hi "$ROW_NPC" 1 noreply >/dev/null 2>&1; rc=$?
[ $rc = 0 ] && [ $calls = 1 ] && chk noreply-ok-flag-unchanged ok || chk noreply-ok-flag-unchanged bad "rc=$rc calls=$calls"
rm -rf "$T"
[ "$ok" = "$n" ] && echo "SELFTEST HXRT ALL PASS $ok/$n" || echo "SELFTEST HXRT ALL FAIL $ok/$n"
