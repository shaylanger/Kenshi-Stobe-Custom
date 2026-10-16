#!/usr/bin/env bash
# sfr_selftest.sh: OFFLINE self-test of the imm26-sfR2 recipe v2 for rows 23-b, 22-b and 20-a (sfrdefs.sh / sfrrun.sh; checkers sfrcheck.py + the unchanged unblockcheck_c.py -> rowcheck.py
# via sfrpy.sh). No game, ssh, WSL lane or DB: lanes are simulated by sfrfake.py with scenarios from sfrscen.py. For every defect scenario the exact failing checks / SETUP-FAIL text is
# asserted, plus recipe statements (ini set before the follow and restored after, chunked advance, real walk, Shay onto the NPC and never the reverse, ...). The ini and FOLLOW-log shell
# bodies the recipe sends are also EXECUTED here against temp files (real bash/sed/awk) so a quoting or CRLF defect shows up offline.
# FAST: run in WSL: wsl.exe -d DwemerAI4Skyrim3 -u root --cd /mnt/c/KenshiModding/testing/live-stobe-queue/imm26-assert -- bash rowtools/sfr_selftest.sh
# Prints `SELFTEST sfr-<name> PASS|FAIL` lines and `SELFTEST SFR ALL PASS|FAIL n/m`.
ST_HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; A="$ST_HERE/.."
REAL_PY=$(command -v python3 || command -v python)
T=$(mktemp -d); export KAH_ROWS_BASE="$T/runs" KAH_ROW_FAKE=1 KAH_ROW_FAKE_LOG="$T/fake.log" KAH_PF_ISOLATION=0 FAKE_STATE="$T/state.json"
export ROW_SETTLE=0 ROW_WAIT=1 TRIP_SE_TRIES=2 RW_SAY_WAIT=0 SFK_23A_TRIES=3 SFK_KO_WAIT=1
unset KAH_AGENT_NAME KAH_ROW_DRY TRIP_TRAP TRIP_GATE TRIP_SAVE TRIP_DEST TRIP_ACCEPT TRIP_ALT SFK_23A_BACK SFK_23A_SPEED SR_23B_LIMIT_H SR_23B_NO_INI SR_23B_EXTRA_H SR_22B_TICKS SR_20A_MAXDIST SR_ADV_MAX SR_CTRL_FRAC
mkdir -p "$KAH_ROWS_BASE"
n=0; ok=0
chk() { n=$((n+1)); if [ "$2" = ok ]; then ok=$((ok+1)); echo "SELFTEST sfr-$1 PASS ${3:-}"; else echo "SELFTEST sfr-$1 FAIL ${3:-}"; fi; }
. "$A/go-row.sh"; . "$ST_HERE/reloaddefs_a.sh"; . "$ST_HERE/reloaddefs_b.sh"; . "$ST_HERE/unblockdefs_a.sh"; . "$ST_HERE/tripdefs_sfk.sh"; . "$ST_HERE/sfrdefs.sh"
PY="$ST_HERE/sfrpy.sh"
lt_fake() { "$REAL_PY" "$ST_HERE/sfrfake.py" "$@"; }
scen() { rm -f "$FAKE_STATE" "$FAKE_STATE".*; export FAKE_SCEN="$T/scen.json"; "$REAL_PY" "$ST_HERE/sfrscen.py" "$1" > "$FAKE_SCEN"; : > "$KAH_ROW_FAKE_LOG"; }
run() { gr_main --allow-retry selftest "$@" 2>/dev/null; }
L=4080-i4
EVB="$KAH_ROWS_BASE/imm26-4080-i4/rows"
F="$KAH_ROW_FAKE_LOG"
fl() { grep -n -m1 -- "$1" "$F" | cut -d: -f1; }
bad_set() {
  "$REAL_PY" -I -c '
import sys
sys.path.insert(0, sys.argv[1])
import sfrcheck as c
c.rc.V.emit = lambda s, e: print("BAD", ",".join(sorted(b.split("=")[0] for b in s.bad))) or 0
c.main(["x", sys.argv[2], sys.argv[3]])' "$ST_HERE" "$1" "$2" 2>&1 | sed -n 's/^BAD //p'
}
# expect <name> <scenario> <row> <RESULT prefix> [FAIL: exact failing-check set | other: substring that must occur in the line]
expect() {
  local name="$1" sc="$2" row="$3" pre="$4" want="${5-}" r ev got
  scen "$sc"; r=$(run "$row" "$L")
  case "$r" in "$pre"*) ;; *) chk "$name" bad "$(echo "$r" | cut -c1-400)"; return;; esac
  if [ "$pre" = "RESULT $row FAIL" ] && [ "$row" != 20-a ]; then
    ev=$(echo "$r" | sed -n 's/.*\[evidence=\([^]]*\)\].*/\1/p'); got=$(bad_set "$row" "$ev")
    [ "$got" = "$want" ] && chk "$name" ok "failing=$got" || chk "$name" bad "failing='$got' wanted '$want'"
  elif [ -n "$want" ]; then
    echo "$r" | grep -q -- "$want" && chk "$name" ok || chk "$name" bad "missing '$want' in: $(echo "$r" | cut -c1-300)"
  else chk "$name" ok; fi
}
# block_of <pattern> [file]: the first fake-log body (between '### ' headers) that contains the pattern
block_of() { awk -v pat="$1" 'function flush(){ if (hit && !done) { printf "%s", buf; done=1 } } /^### /{ flush(); buf=""; hit=0; next } { buf = buf $0 "\n"; if (index($0, pat)) hit=1 } END{ flush() }' "${2:-$F}"; }

# ------------------------------------------------------------------ 23-b
expect 23-b-pass sfr23-pass 23-b "RESULT 23-b PASS" "expired_at_or_after_limit"
EV23="$EVB/23-b"
[ "$(head -1 "$EV23/limit_hours.txt")" = 2 ] && grep -q '^now: FollowExpiryGameHours=2$' "$EV23/ini_set.txt" && chk 23-b-ini-limit-2-written ok || chk 23-b-ini-limit-2-written bad "$(cat "$EV23/limit_hours.txt" "$EV23/ini_set.txt" 2>/dev/null | head -3)"
a=$(fl '# sr:iniset'); b=$(fl 'Follow me\.'); c=$(fl '# sr:inirestore')
[ -n "$a" ] && [ -n "$b" ] && [ -n "$c" ] && [ "$a" -lt "$b" ] && [ "$b" -lt "$c" ] && [ "$(grep -c '# sr:inirestore' "$F")" = 1 ] && chk 23-b-ini-set-before-follow-restored-once-after ok || chk 23-b-ini-set-before-follow-restored-once-after bad "set=$a say=$b restore=$c"
grep -q '^restored; key now' "$EV23/ini_restore.txt" && chk 23-b-ini-restore-evidence ok || chk 23-b-ini-restore-evidence bad
[ "$(grep -c 'stobe-auto speed 10' "$F")" -ge 2 ] && grep -q '^chunk=' "$EV23/advance.txt" && chk 23-b-chunked-advance ok || chk 23-b-chunked-advance bad "speed10 bodies $(grep -c 'stobe-auto speed 10' "$F")"
mid=$(head -1 "$EV23/time_mid.txt"); t0=$(head -1 "$EV23/time0.txt"); t1=$(head -1 "$EV23/time1.txt")
awk -v m="$mid" -v a="$t0" -v b="$t1" 'BEGIN{exit !((m-a)>0 && (m-a)<2 && (b-a)>=2)}' && chk 23-b-control-inside-limit-then-past-limit ok "mid=+$(awk -v m="$mid" -v a="$t0" 'BEGIN{printf "%.2f",m-a}') end=+$(awk -v b="$t1" -v a="$t0" 'BEGIN{printf "%.2f",b-a}')" || chk 23-b-control-inside-limit-then-past-limit bad "t0=$t0 mid=$mid t1=$t1"
grep -q 'stobe-auto speed 0.5' "$F" && chk 23-b-speed-restored ok || chk 23-b-speed-restored bad
expect 23-b-no-expiry-is-a-real-fail sfr23-noexp 23-b "RESULT 23-b FAIL" "follow_ended_by_expiry"
expect 23-b-early-expiry-fails-control sfr23-early 23-b "RESULT 23-b FAIL" "expired_at_or_after_limit,no_expiry_before_limit"
expect 23-b-tick-after-expiry-fail sfr23-ticks-after 23-b "RESULT 23-b FAIL" "no_tick_after_expiry"
SR_ADV_MAX=3 expect 23-b-stalled-clock-setup-fail sfr23-stall 23-b "RESULT 23-b SETUP-FAIL" "did not reach"
grep -q '# sr:inirestore' "$F" && chk 23-b-ini-restored-on-setup-fail ok || chk 23-b-ini-restored-on-setup-fail bad
expect 23-b-ini-missing-setup-fail sfr23-ini-missing 23-b "RESULT 23-b SETUP-FAIL" "could not set FollowExpiryGameHours=2"
! grep -q 'Follow me\.' "$F" && grep -q '# sr:inirestore' "$F" && chk 23-b-ini-missing-aborts-before-follow ok || chk 23-b-ini-missing-aborts-before-follow bad
expect 23-b-ini-key-not-sticking-setup-fail sfr23-ini-stuck 23-b "RESULT 23-b SETUP-FAIL" "could not set"
expect 23-b-no-follow-order-setup-fail sfr23-nofollow 23-b "RESULT 23-b SETUP-FAIL" "no follow order"
scen sfr23-pass; SR_23B_NO_INI=1 run 23-b $L > "$T/noini.out"
grep -q '^RESULT 23-b PASS' "$T/noini.out" && [ "$(head -1 "$EV23/limit_hours.txt")" = 24 ] && ! grep -q '# sr:ini' "$F" && [ "$(grep -c 'stobe-auto speed 10' "$F")" -ge 4 ] && chk 23-b-no-ini-path-24h ok || chk 23-b-no-ini-path-24h bad "$(cut -c1-300 "$T/noini.out")"
scen sfr23-pass; SR_23B_LIMIT_H=3 SR_23B_EXTRA_H=2 run 23-b $L > "$T/lim3.out"
grep -q '^RESULT 23-b PASS' "$T/lim3.out" && grep -q '# sr:iniset h=3' "$F" && chk 23-b-limit-env-override ok || chk 23-b-limit-env-override bad "$(cut -c1-300 "$T/lim3.out")"

# ---- the ini / FOLLOW-log bodies the recipe sends, EXECUTED against temp files
scen sfr23-pass; run 23-b $L >/dev/null
block_of '# sr:iniset' > "$T/iniset.body"; block_of '# sr:inirestore' > "$T/inirestore.body"; block_of '# sr:follow' > "$T/follow.body"
ini_run() {   # ini_run <body-file> <ini path> : the body with F= pointed at the temp ini
  sed "s#^F='[^']*'#F='$2'#" "$1" | bash 2>&1
}
printf '[Settings]\r\nFollowExpiryGameHours=24\r\nOther=1\r\n' > "$T/c1.ini"; cp "$T/c1.ini" "$T/c1.orig"
o=$(ini_run "$T/iniset.body" "$T/c1.ini")
echo "$o" | grep -q '^was: FollowExpiryGameHours=24$' && echo "$o" | grep -q '^now: FollowExpiryGameHours=2$' && grep -q $'^FollowExpiryGameHours=2\r$' "$T/c1.ini" && grep -q $'^Other=1\r$' "$T/c1.ini" && [ -f "$T/c1.ini.sfR.bak" ] && chk ini-real-key-present-crlf-kept ok || chk ini-real-key-present-crlf-kept bad "$o | $(od -c "$T/c1.ini" | head -3)"
o=$(ini_run "$T/inirestore.body" "$T/c1.ini"); cmp -s "$T/c1.ini" "$T/c1.orig" && [ ! -f "$T/c1.ini.sfR.bak" ] && echo "$o" | grep -q '^restored; key now: \[FollowExpiryGameHours=24\]' && chk ini-real-restore-byte-identical ok || chk ini-real-restore-byte-identical bad "$o"
printf '[Settings]\nA=1\n' > "$T/c2.ini"; cp "$T/c2.ini" "$T/c2.orig"
o=$(ini_run "$T/iniset.body" "$T/c2.ini")
echo "$o" | grep -q '^was: (unset' && echo "$o" | grep -q '^now: FollowExpiryGameHours=2$' && [ "$(sed -n 1p "$T/c2.ini")" = '[Settings]' ] && [ "$(sed -n 2p "$T/c2.ini")" = 'FollowExpiryGameHours=2' ] && [ "$(sed -n 3p "$T/c2.ini")" = 'A=1' ] && chk ini-real-key-absent-lf-inserted ok || chk ini-real-key-absent-lf-inserted bad "$o | $(cat "$T/c2.ini" | tr '\n' '/')"
ini_run "$T/inirestore.body" "$T/c2.ini" >/dev/null; cmp -s "$T/c2.ini" "$T/c2.orig" && chk ini-real-restore-after-insert-identical ok || chk ini-real-restore-after-insert-identical bad
printf '[Settings]\r\nA=1\r\n' > "$T/c3.ini"; cp "$T/c3.ini" "$T/c3.orig"
o=$(ini_run "$T/iniset.body" "$T/c3.ini")
[ "$(grep -c $'\r$' "$T/c3.ini")" = 3 ] && [ "$(wc -l < "$T/c3.ini")" = 3 ] && grep -q $'^FollowExpiryGameHours=2\r$' "$T/c3.ini" && chk ini-real-key-absent-crlf-inserted ok || chk ini-real-key-absent-crlf-inserted bad "$(od -c "$T/c3.ini" | head -4)"
o2=$(ini_run "$T/iniset.body" "$T/c3.ini")   # a second set while the backup is still there: the leftover backup is restored first, so the final restore returns the ORIGINAL
echo "$o2" | grep -q 'leftover backup restored first' && ini_run "$T/inirestore.body" "$T/c3.ini" >/dev/null && cmp -s "$T/c3.ini" "$T/c3.orig" && chk ini-real-double-set-restores-original ok || chk ini-real-double-set-restores-original bad "$o2"
o=$(ini_run "$T/iniset.body" "$T/nonexistent.ini"); echo "$o" | grep -q '^NO-INI ' && chk ini-real-missing-file-reported ok || chk ini-real-missing-file-reported bad "$o"
o=$(ini_run "$T/inirestore.body" "$T/c1.ini"); echo "$o" | grep -q '^no-backup' && chk ini-real-restore-without-backup-harmless ok || chk ini-real-restore-without-backup-harmless bad "$o"
# FOLLOW log slicer (the awk that counts ticks after THIS follower's expiry)
LOGT="$T/stobe.test.log"; : > "$LOGT"; for i in $(seq 1 200); do echo "[x] noise $i" >> "$LOGT"; done
{ echo '[10:00:00] FOLLOW target resolved follower=2529907200 target=Shay'
  for i in 1 2 3; do echo "[10:00:1$i] FOLLOW_TICK: follower=2529907200 dist=6"; done
  echo '[10:01:00] FOLLOW_EXPIRED: follower=2529907200 started_gamets=100 now_gamets=7300'
  echo '[10:01:01] FOLLOW_TICK: follower=2529907200 dist=6'; echo '[10:01:02] FOLLOW_TICK: follower=2529907200 dist=6'
  echo '[10:01:03] FOLLOW_TICK: follower=1111111111 dist=6'; } >> "$LOGT"
slice() { sed -e "s#tail -n +[0-9]* [^ ]*stobe.log#tail -n +201 $LOGT#" "$T/follow.body" | bash 2>&1; }
o=$(slice)
echo "$o" | grep -q 'FOLLOW target resolved' && echo "$o" | grep -q 'FOLLOW_EXPIRED: follower=2529907200' && ! echo "$o" | grep -q '^\[10:00:11\] FOLLOW_TICK' && echo "$o" | grep -q '^# ticks=6$' && echo "$o" | grep -q '^# ticks_after_expiry=2$' && chk follow-slice-real-awk-counts-own-ticks-after-expiry ok || chk follow-slice-real-awk-counts-own-ticks-after-expiry bad "$(echo "$o" | tr '\n' '/' | cut -c1-400)"
head -n 204 "$LOGT" > "$LOGT.2"; mv "$LOGT.2" "$LOGT"
o=$(slice); echo "$o" | grep -q '^# ticks_after_expiry=0$' && ! echo "$o" | grep -q FOLLOW_EXPIRED && chk follow-slice-real-no-expiry-zero ok || chk follow-slice-real-no-expiry-zero bad "$(echo "$o" | tr '\n' '/' | cut -c1-300)"

# ------------------------------------------------------------------ 22-b
expect 22-b-pass sfr22-pass 22-b "RESULT 22-b PASS" "single_remark_claim"
EV22="$EVB/22-b"
[ "$(grep -c 'u:stream' "$F")" = 2 ] && grep -q '^tick1|' "$EV22/sr_ticks.txt" && grep -q '^tick_silent|res=nothing_claimable' "$EV22/sr_ticks.txt" && grep -q 'claimed_before_silent=1' "$EV22/sr_summary.txt" && chk 22-b-one-claim-tick-then-silent-tick ok || chk 22-b-one-claim-tick-then-silent-tick bad "streams $(grep -c 'u:stream' "$F") $(cat "$EV22/sr_ticks.txt" 2>/dev/null | tr '\n' '/')"
grep -q 'people=Cind|2529907200,Shay|' "$EV22/bored_people.txt" && chk 22-b-people-with-serials ok || chk 22-b-people-with-serials bad "$(cat "$EV22/bored_people.txt" 2>/dev/null)"
grep -q -- '-62461 328.779 16346.8 dist 400' "$F" && ! grep -q "teleport Shay -62461" "$F" && chk 22-b-real-walk-not-a-gate-teleport ok || chk 22-b-real-walk-not-a-gate-teleport bad
! grep -E 'stobe-auto order ' "$F" | grep -v 'order Shay' | grep -q . && chk 22-b-npc-gets-no-harness-order ok || chk 22-b-npc-gets-no-harness-order bad
nat=$(grep -n 'teleport Shay' "$F" | tail -1 | cut -d: -f1); fs1=$(fl 'u:stream')
[ -n "$nat" ] && [ -n "$fs1" ] && [ "$nat" -lt "$fs1" ] && [ -s "$EV22/mark_rowid.txt" ] && [ -f "$EV22/sit_after1.txt" ] && [ -f "$EV22/sit_after_silent.txt" ] && chk 22-b-shay-onto-npc-before-first-tick-evidence ok || chk 22-b-shay-onto-npc-before-first-tick-evidence bad "tp=$nat tick=$fs1"
grep -q 'end=ARRIVED' "$EV22/arrival.txt" && chk 22-b-arrival-evidence ok || chk 22-b-arrival-evidence bad "$(cat "$EV22/arrival.txt" 2>/dev/null)"
expect 22-b-claim-on-second-tick-passes sfr22-second-tick 22-b "RESULT 22-b PASS" "single_remark_claim"
[ "$(grep -c 'u:stream' "$F")" = 3 ] && grep -q '^tick1|res=nothing_claimable|claims=0' "$EV22/sr_ticks.txt" && grep -q '^tick2|res=sent|claims=1' "$EV22/sr_ticks.txt" && chk 22-b-second-tick-sent-only-after-empty-first ok || chk 22-b-second-tick-sent-only-after-empty-first bad "streams $(grep -c 'u:stream' "$F") $(cat "$EV22/sr_ticks.txt" 2>/dev/null | tr '\n' '/')"
expect 22-b-no-arrival-event-is-a-real-fail sfr22-noevent 22-b "RESULT 22-b FAIL" "single_remark_claim,situated_event_arrival"
expect 22-b-two-claims-fail sfr22-two-claims 22-b "RESULT 22-b FAIL" "single_remark_claim"
expect 22-b-silent-tick-speaks-fail sfr22-silent-speaks 22-b "RESULT 22-b FAIL" "second_tick_silent,single_remark_claim"
expect 22-b-no-native-arrival-setup-fail sfr22-timeout 22-b "RESULT 22-b SETUP-FAIL" "no native arrival"
! grep -q 'u:stream' "$F" && chk 22-b-no-tick-without-arrival ok || chk 22-b-no-tick-without-arrival bad
expect 22-b-all-http-errors-setup-fail sfr22-http 22-b "RESULT 22-b SETUP-FAIL" "every targeted bored request failed"
scen sfr22-pass; SR_22B_TICKS=1 SFK_23A_BACK=123 TRIP_GATE="7 8 9" run 22-b $L >/dev/null
grep -q -- '7 8 9 dist 123' "$F" && chk 22-b-env-overrides ok || chk 22-b-env-overrides bad

# ------------------------------------------------------------------ 20-a
expect 20-a-pass-in-range sfr20-pass 20-a "RESULT 20-a PASS" "dist_to_target s3=8"
EV20="$EVB/20-a"
sl=($(grep -n 'stobe_say' "$F" | cut -d: -f1)); tp=($(grep -n "teleport Shay '" "$F" | cut -d: -f1))
okp=1; for want in 2 3; do   # a placement teleport between say#want and say#want+1 (say index 0-based: s1=0 s2=1 s3=2 s4=3)
  lo=${sl[$((want-1))]}; hi=${sl[$want]}; hit=0; for t in "${tp[@]}"; do [ "$t" -gt "$lo" ] && [ "$t" -lt "$hi" ] && hit=1; done; [ $hit = 1 ] || okp=0; done
[ "${#sl[@]}" = 4 ] && [ $okp = 1 ] && chk 20-a-shay-teleported-onto-npc-before-s3-and-s4 ok || chk 20-a-shay-teleported-onto-npc-before-s3-and-s4 bad "says=${#sl[@]} teleports=${tp[*]} says@${sl[*]}"
tail -n +"${sl[1]}" "$F" > "$T/after-accept.log"   # the common tr_quiet setup (before the trip) may put the NPC next to Shay; after the accept turn she must never be moved or ordered
! grep -qE "teleport '[^']*' Shay" "$T/after-accept.log" && ! grep -E 'stobe-auto order ' "$T/after-accept.log" | grep -v 'order Shay' | grep -q . && chk 20-a-npc-never-moved-or-ordered-after-accept ok || chk 20-a-npc-never-moved-or-ordered-after-accept bad
grep -q '^s3|8' "$EV20/place_dist.txt" && grep -q '^s4|8' "$EV20/place_dist.txt" && chk 20-a-place-dist-evidence ok || chk 20-a-place-dist-evidence bad "$(cat "$EV20/place_dist.txt" 2>/dev/null)"
[ "$(grep -c 'stobe_drawn sheathe Shay' "$F")" -ge 4 ] && [ -f "$EV20/calm_s3.txt" ] && [ -f "$EV20/calm_s4.txt" ] && [ -f "$EV20/calm_pre.txt" ] && chk 20-a-sheathed-and-calm-evidence ok || chk 20-a-sheathed-and-calm-evidence bad
grep -q 'dist_to_target=8' "$EV20/s3/reply.txt" && chk 20-a-dist-to-target-in-reply-evidence ok || chk 20-a-dist-to-target-in-reply-evidence bad
expect 20-a-fail-in-range-stays-fail sfr20-fail 20-a "RESULT 20-a FAIL" "dist_to_target s3=8"
expect 20-a-s4b-pass-places-shay-again sfr20-s4b-pass 20-a "RESULT 20-a PASS"
grep -q '^s4b|' "$EV20/place_dist.txt" && chk 20-a-s4b-place-dist ok || chk 20-a-s4b-place-dist bad "$(cat "$EV20/place_dist.txt" 2>/dev/null)"
expect 20-a-npc-keeps-walking-setup-fail-before-the-say sfr20-stuck 20-a "RESULT 20-a SETUP-FAIL" "could not bring Shay within 70"
! grep -q 'Actually, go to' "$F" && [ "$(grep -c 'stobe_say' "$F")" = 2 ] && chk 20-a-no-say-when-not-in-range ok || chk 20-a-no-say-when-not-in-range bad "says $(grep -c 'stobe_say' "$F")"
expect 20-a-outside-talk-radius-fail-becomes-setup-fail sfr20-far-fail 20-a "RESULT 20-a SETUP-FAIL" "outside TalkRadius"
expect 20-a-pass-never-downgraded sfr20-far-pass 20-a "RESULT 20-a PASS"
scen sfr20-pass; SR_20A_MAXDIST=5 run 20-a $L | grep -q '^RESULT 20-a SETUP-FAIL.*within 5 u' && chk 20-a-maxdist-env ok || chk 20-a-maxdist-env bad

# ------------------------------------------------------------------ CLI: sfrrun.sh as a separate process
cli() {
  local script="$1"; shift
  bash -c ". '$ST_HERE/lane.sh'; lt_fake() { '$REAL_PY' '$ST_HERE/sfrfake.py' \"\$@\"; }; export -f lt_fake; export REAL_PY; exec bash '$ST_HERE/$script' \"\$@\"" _ "$@" 2>/dev/null
}
scen sfr23-pass; o=$(cli sfrrun.sh 23-b $L --allow-retry selftest); rc=$?
[ "$(echo "$o" | grep -c '^RESULT ')" = 1 ] && echo "$o" | tail -1 | grep -q '^RESULT 23-b PASS' && [ $rc = 0 ] && chk cli-23b-one-result-line ok || chk cli-23b-one-result-line bad "rc=$rc $(echo "$o" | cut -c1-300)"
grep -q 'stobe-auto load kah-imm26-4080-i4h' "$F" && chk cli-4080-i4-default-ready-save ok || chk cli-4080-i4-default-ready-save bad
echo "$o" | grep -q '^EVIDENCE 23-b limit_hours.txt 2' && echo "$o" | grep -q '^EVIDENCE 23-b ini_restore.txt restored' && chk cli-23b-evidence-lines ok || chk cli-23b-evidence-lines bad "$(echo "$o" | grep EVIDENCE | head -4 | cut -c1-120)"
scen sfr23-pass; o=$(cli sfrrun.sh 23-b $L --no-reload --limit-h 3 --extra-h 2 --allow-retry selftest); grep -q '# sr:iniset h=3' "$F" && ! grep -q 'stobe-auto load kah-imm26-4080-i4h' "$F" && echo "$o" | tail -1 | grep -q '^RESULT 23-b PASS' && chk cli-23b-options ok || chk cli-23b-options bad "$(echo "$o" | tail -1 | cut -c1-200)"
scen sfr23-pass; o=$(cli sfrrun.sh 23-b $L --no-reload --no-ini --allow-retry selftest); ! grep -q '# sr:ini' "$F" && echo "$o" | tail -1 | grep -q '^RESULT 23-b PASS' && chk cli-23b-no-ini ok || chk cli-23b-no-ini bad "$(echo "$o" | tail -1 | cut -c1-200)"
scen sfr22-pass; o=$(cli sfrrun.sh 22-b $L --no-reload --ticks 1 --back 123 --gate "7 8 9" --speed 2 --tries 3 --allow-retry selftest); grep -q '7 8 9 dist 123' "$F" && grep -q 'stobe-auto speed 2 ' "$F" && echo "$o" | tail -1 | grep -q '^RESULT 22-b PASS' && echo "$o" | grep -q '^EVIDENCE 22-b sr_ticks.txt tick1' && chk cli-22b-options ok || chk cli-22b-options bad "$(echo "$o" | tail -1 | cut -c1-200)"
scen sfr20-pass; o=$(cli sfrrun.sh 20-a $L --no-reload --maxdist 5 --allow-retry selftest); rc=$?; [ $rc = 2 ] && echo "$o" | tail -1 | grep -q 'SETUP-FAIL' && chk cli-20a-maxdist-setup-fail-exit-2 ok || chk cli-20a-maxdist-setup-fail-exit-2 bad "rc=$rc"
scen sfr20-pass; o=$(cli sfrrun.sh 20-a $L --no-reload --allow-retry selftest); rc=$?; echo "$o" | tail -1 | grep -q '^RESULT 20-a PASS' && echo "$o" | grep -q '^EVIDENCE 20-a place_dist.txt s3|' && [ $rc = 0 ] && chk cli-20a-pass-evidence ok || chk cli-20a-pass-evidence bad "rc=$rc $(echo "$o" | tail -1 | cut -c1-200)"
scen sfr23-noexp; o=$(cli sfrrun.sh 23-b $L --allow-retry selftest); rc=$?; [ $rc = 1 ] && chk cli-fail-exit-1 ok || chk cli-fail-exit-1 bad "rc=$rc"
for r in 23-b 22-b 20-a; do
  scen sfr23-pass; o=$(cli sfrrun.sh $r $L --dry); echo "$o" | grep -q "^RESULT $r DRY-RUN" && chk "cli-dry-run-$r" ok || chk "cli-dry-run-$r" bad "$(echo "$o" | cut -c1-300)"
done
scen sfr23-pass; o=$(cli sfrrun.sh --restore-ini $L); echo "$o" | grep -q '^RESULT restore-ini DONE' && grep -q '# sr:inirestore' "$F" && chk cli-restore-ini ok || chk cli-restore-ini bad "$o"
o=$(cli sfrrun.sh 99-z $L); echo "$o" | grep -q 'RESULT 99-z SETUP-FAIL not an sfR row' && chk cli-unknown-row ok || chk cli-unknown-row bad "$o"
o=$(cli sfrrun.sh 23-b nolane); echo "$o" | grep -q 'RESULT 23-b SETUP-FAIL PREFLIGHT-FAIL unknown lane' && chk cli-unknown-lane ok || chk cli-unknown-lane bad "$o"

# ------------------------------------------------------------------ shims + isolation from the live operators' files
echo hello | "$REAL_PY" -c 'import sys;print(sys.stdin.read().strip())' >/dev/null; [ "$("$ST_HERE/sfrpy.sh" -c 'print(7)')" = 7 ] && chk sfrpy-passthrough ok || chk sfrpy-passthrough bad
for f in sfrdefs.sh sfrrun.sh sfr_selftest.sh sfrpy.sh; do bash -n "$ST_HERE/$f" 2>/dev/null && chk "bash-n-$f" ok || chk "bash-n-$f" bad; done
for f in sfrcheck.py sfrfake.py sfrscen.py; do "$REAL_PY" -m py_compile "$ST_HERE/$f" 2>/dev/null && chk "py-compile-$f" ok || chk "py-compile-$f" bad; done
grep -q 'sfrdefs\|sfrcheck\|sfrpy' "$ST_HERE/rowdefs.sh" "$ST_HERE/hxdefs.sh" "$ST_HERE/tripdefs.sh" "$ST_HERE/unblockdefs_a.sh" "$ST_HERE/unblockdefs_c.sh" "$ST_HERE/unblockcheck_c.py" "$ST_HERE/reloaddefs_a.sh" "$ST_HERE/rowcheck.py" 2>/dev/null && chk originals-not-hooked bad "an operator file references the sfr files" || chk originals-not-hooked ok
if git -C "$ST_HERE" rev-parse --git-dir >/dev/null 2>&1; then
  git -C "$ST_HERE" diff --quiet -- tripdefs.sh unblockdefs_a.sh unblockdefs_c.sh unblockcheck_c.py rowdefs.sh rowcheck.py hxdefs.sh tripdefs_sfk.sh && chk queued-scripts-unmodified ok || chk queued-scripts-unmodified bad "git diff shows an edit"
fi

rm -rf "$T"
if [ $ok = $n ]; then echo "SELFTEST SFR ALL PASS $ok/$n"; exit 0; else echo "SELFTEST SFR ALL FAIL $ok/$n"; exit 1; fi
