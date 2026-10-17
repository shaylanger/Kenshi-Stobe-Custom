#!/usr/bin/env bash
# reloadselftest_b.sh: OFFLINE self-test of the set-B save/load rows (reloaddefs_b.sh / reloadcheck_b.py / reloadrun-b.sh / pywrap_b.sh / reloadfake_b.py):
# 14-e 13-f 13-g 10-e 19-e 19-f. No game, ssh, WSL or DB (lanes simulated by reloadfake_b.py -> tripfake.py -> fakelane.py, scenarios from reloadscen_b.py).
# Every PASS scenario must give RESULT PASS with no failing assertion, and every defect variant must fail ALONE on its named assertion
# (RELOAD_B_DEBUG makes reloadcheck_b.py write `BADCHECKS n=<k> :: a ## b` to run.log). Prints `SELFTEST rb-<name> PASS|FAIL` lines and `SELFTEST RELOAD-B ALL PASS|FAIL n/m`.
# Usage: bash rowtools/reloadselftest_b.sh
ST_HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; A="$ST_HERE/.."
P=$(command -v python3 || command -v python)
T=$(mktemp -d); export KAH_ROWS_BASE="$T/runs" KAH_ROW_FAKE=1 KAH_ROW_FAKE_LOG="$T/fake.log" KAH_PF_ISOLATION=0 FAKE_STATE="$T/state.json" RELOAD_B_DEBUG=1
export ROW_SETTLE=0 ROW_WAIT=1 TRIP_SE_TRIES=2
unset KAH_AGENT_NAME KAH_ROW_DRY TRIP_TRAP TRIP_GATE TRIP_SAVE TRIP_DEST TRIP_ACCEPT ROW_BACKDATE_S ROW_19F_N ROW_19F_MODE ROW_19F_CAP ROW_13_TALK
mkdir -p "$KAH_ROWS_BASE"
n=0; ok=0
chk() { n=$((n+1)); if [ "$2" = ok ]; then ok=$((ok+1)); echo "SELFTEST rb-$1 PASS ${3:-}"; else echo "SELFTEST rb-$1 FAIL ${3:-}"; fi; }
. "$A/go-row.sh"; . "$ST_HERE/reloaddefs_b.sh"
PY="$ST_HERE/pywrap_b.sh"
lt_fake() { "$P" "$ST_HERE/reloadfake_b.py" "$@"; }
scen() { rm -f "$FAKE_STATE" "$FAKE_STATE.trip" "$FAKE_STATE.rb"; export FAKE_SCEN="$T/scen.json"; "$P" "$ST_HERE/reloadscen_b.py" "$1" > "$FAKE_SCEN" || echo "SCENARIO ERROR $1" >&2; : > "$KAH_ROW_FAKE_LOG"; }
L=5090-i3
EVD() { echo "$KAH_ROWS_BASE/imm26-5090-i3/rows/$1"; }
run() { gr_main --no-preflight --allow-retry selftest "$@" 2>/dev/null; }
bad_line() { grep -a '^BADCHECKS' "$(EVD "$1")/run.log" 2>/dev/null | tail -1; }
# expect_pass <name> <scenario> <row>
expect_pass() {
  local name="$1" sc="$2" row="$3" r b; scen "$sc"; r=$(run "$row" $L); b=$(bad_line "$row")
  case "$r" in
    "RESULT $row PASS"*) case "$b" in "BADCHECKS n=0 ::"*) chk "$name" ok;; *) chk "$name" bad "bad=$b";; esac;;
    *) chk "$name" bad "$r";;
  esac
}
# expect_alone <name> <scenario> <row> <assertion-prefix>: FAIL, exactly one failing assertion and it is the named one
expect_alone() {
  local name="$1" sc="$2" row="$3" want="$4" r b; scen "$sc"; r=$(run "$row" $L); b=$(bad_line "$row")
  case "$r" in
    "RESULT $row FAIL"*) case "$b" in "BADCHECKS n=1 :: $want"*) chk "$name" ok;; *) chk "$name" bad "bad=$b";; esac;;
    *) chk "$name" bad "$r";;
  esac
}
# expect_has <name> <scenario> <row> <RESULT kind> <substring in the BADCHECKS line or the result line>
expect_has() {
  local name="$1" sc="$2" row="$3" kind="$4" has="$5" r b; scen "$sc"; r=$(run "$row" $L); b=$(bad_line "$row")
  case "$r" in
    "RESULT $row $kind"*) if echo "$r $b" | grep -qF -- "$has"; then chk "$name" ok; else chk "$name" bad "missing '$has': $r | $b"; fi;;
    *) chk "$name" bad "$r";;
  esac
}

# ---- 14-e
expect_pass 14-e-pass 14e-pass 14-e
expect_alone 14-e-expired-by-reload 14e-expired 14-e "offer_not_expired_by_the_reload"
expect_alone 14-e-new-contract-id 14e-newid 14-e "same_contract_id_before_and_after_reload"
expect_alone 14-e-no-pause-shift 14e-noshift 14-e "deal_pause_0<shift<=1200"
expect_alone 14-e-shift-over-cap 14e-bigshift 14-e "deal_pause_0<shift<=1200"
expect_alone 14-e-no-resume-shifts-entry 14e-noshifts 14-e "deal_resume_shift_recorded"
expect_alone 14-e-bread-missing 14e-nobread 14-e "bread_reached_the_player"
expect_alone 14-e-not-performed 14e-notperformed 14-e "deal_performs_after_reload"
expect_alone 14-e-inject-fired-once 14e-fired1 14-e "inject_fired_exactly_2_steps"
expect_has 14-e-weak-setup-fail 14e-weak 14-e SETUP-FAIL "row does not prove the pause"
expect_has 14-e-no-open-offer 14e-notopen 14-e SETUP-FAIL "no open counter-offer after s1"

# ---- 13-g
expect_pass 13-g-pass 13g-pass 13-g
expect_pass 13-g-direct-accept-pass 13g-direct 13-g
expect_alone 13-g-not-complete 13g-notcomplete 13-g "deal_COMPLETE_after_paying_post_reload"
expect_alone 13-g-cats-leg-pending 13g-nocatsleg 13-g "player_leg_GIVE_CATS_VERIFIED"
expect_alone 13-g-no-kept-promise 13g-nokept 13-g "kept_promise_row_delta_1..3"
expect_alone 13-g-kept-promise-delta-7 13g-keptbig 13-g "kept_promise_row_delta_1..3"
expect_alone 13-g-broken-promise-too 13g-broken 13-g "no_broken_promise_for_this_deal"
expect_alone 13-g-expired-after-load 13g-expired 13-g "deal_alive_after_load"
expect_alone 13-g-new-contract-id 13g-newid 13-g "same_contract_id_across_the_reload"
expect_alone 13-g-no-pause-shift 13g-noshift 13-g "deal_pause_0<shift<=1200"
expect_alone 13-g-clock-token-unchanged 13g-sameclock 13-g "negotiation_clock_saw_a_new_load_token"
expect_has 13-g-not-pending-setup-fail 13g-notpending 13-g SETUP-FAIL "deal not pending before the save"
expect_pass 13-g-countered-price-353-pass 13g-counter353 13-g
expect_has 13-g-no-price-setup-fail 13g-noprice 13-g SETUP-FAIL "cannot read the GIVE_CATS price"

# ---- 13-f
expect_pass 13-f-pass 13f-pass 13-f
expect_alone 13-f-not-breached 13f-notbreached 13-f "deal_BREACHED_PLAYER_when_deadline_passes"
expect_alone 13-f-no-broken-promise 13f-nobroken 13-f "broken_promise_row_delta_-15..-5"
expect_alone 13-f-broken-delta--30 13f-brokenbig 13-f "broken_promise_row_delta_-15..-5"
expect_alone 13-f-kept-promise-too 13f-keptpromise 13-f "no_kept_promise_for_this_deal"

# ---- 10-e
expect_pass 10-e-pass 10e-pass 10-e
expect_has 10-e-no-later-load 10e-samesession 10-e SETUP-FAIL "no later load of the same campaign observed"
expect_has 10-e-ingest-off 10e-ingestoff 10-e SETUP-FAIL "SOCIAL_RELATIONSHIP_MODE is 'off'"
expect_alone 10-e-rescope-switch-off 10e-norescope 10-e "rescope_kill_switch_on"
expect_alone 10-e-later-load-scope-changed 10e-scopechanged 10-e "later_load_same_campaign_keeps_term_alive"
expect_alone 10-e-other-save-not-impossible 10e-othersave 10-e "other_save_IMPOSSIBLE_exact_restitution_scope_changed"
expect_alone 10-e-older-epoch-not-impossible 10e-older 10-e "older_epoch_IMPOSSIBLE_exact_restitution_scope_changed"
expect_alone 10-e-unprovable-is-UNMET 10e-unmet 10-e "unprovable_after_reload_IMPOSSIBLE_not_UNMET"
expect_alone 10-e-control-not-UNMET 10e-control 10-e "control_same_load_deadline_stays_UNMET"

# ---- 19-e (lazy resume: nothing before the chat line, then exactly one resume)
expect_pass 19-e-pass 19e-pass 19-e
expect_pass 19-e-pass-no-interrupt-row 19e-pass-noint 19-e
expect_alone 19-e-ran-off-during-quiet-window 19e-early-start 19-e "control_no_OWNED_TRAVEL_before_any_chat"
expect_alone 19-e-moved-before-any-chat 19e-early-rows 19-e "control_agreement_not_moved_before_any_chat"
expect_alone 19-e-chat-turn-starts-nothing 19e-no-start-on-chat 19-e "chat_turn_resumes_exactly_one_OWNED_TRAVEL_accepted"
expect_alone 19-e-two-starts 19e-dup 19-e "chat_turn_resumes_exactly_one_OWNED_TRAVEL_accepted"
expect_alone 19-e-wrong-destination 19e-wrongdest 19-e "final_destination_within_0.5"
expect_alone 19-e-no-native-order 19e-nostate 19-e "final_first_order_MOVE_CUS_ORDERED"
expect_has 19-e-chat-without-resume 19e-chat-no-resume 19-e FAIL "chat_turn_resumes_exactly_one_OWNED_TRAVEL_accepted"
expect_has 19-e-no-pre-start 19e-nostart 19-e SETUP-FAIL "no pre-load OWNED_TRAVEL accepted=1"
# fix19erecipe: Cind must be teleported next to Shay right before s4 and verified <= 40 u (else SETUP-FAIL with the cause)
expect_has 19-e-far-at-s4-setup-fail 19e-far-at-s4 19-e SETUP-FAIL "107.6 u from Shay after 2 teleports"
expect_pass 19-e-near-retry-pass 19e-near-retry 19-e
# 19E-FIX: the running receipt needs the second post-load line (s5); without a running row after requested the row must still FAIL
expect_alone 19-e-requested-never-running 19e-requested-never-running 19-e "phase_running_after_requested"
expect_alone 19-e-receipt-turn-restarts-trip 19e-s5-second-start 19-e "second_post_load_line_starts_no_second_OWNED_TRAVEL"

# ---- 19-f
export ROW_19F_N=4
expect_pass 19-f-pass 19f-pass 19-f
expect_alone 19-f-two-starts-in-reload2 19f-dup-start 19-f "reload2_exactly_one_OWNED_TRAVEL_accepted"
expect_alone 19-f-wrong-resume-count 19f-wrongcount 19-f "reload3_resume_count_is_3"
expect_alone 19-f-second-agreement 19f-newagr 19-f "one_agreement_id_throughout"
expect_has 19-f-default-cap-fails-target 19f-cap-default-fails 19-f FAIL "reload4_still_ACCEPTED_and_resumed"
expect_has 19-f-default-cap-note 19f-cap-default-fails 19-f FAIL "expected FAIL on a build with the resume cap of 3"
export ROW_19F_MODE=cap ROW_19F_CAP=2
expect_pass 19-f-capmode-pass 19f-capmode-pass 19-f
expect_alone 19-f-cap-not-terminal 19f-cap-notterminal 19-f "reload3_FAILED_honestly_resume_count"
expect_alone 19-f-cap-new-travel 19f-cap-newtravel 19-f "reload3_no_new_OWNED_TRAVEL"
expect_alone 19-f-cap-reproposal-loop 19f-cap-loop 19-f "reload3_no_new_PROPOSED_row"
unset ROW_19F_N ROW_19F_MODE ROW_19F_CAP

# ---- statements the rows send (recipe checks)
F="$KAH_ROW_FAKE_LOG"
last_line() { grep -n -a -F -- "$1" "$F" | tail -1 | cut -d: -f1; }
scen 14e-pass; run 14-e $L >/dev/null
i=$(last_line "INSERT INTO general_settings (id,value) VALUES ('NEG_TEST_INJECT'"); d=$(last_line "DELETE FROM general_settings WHERE id='NEG_TEST_INJECT'")
[ -n "$i" ] && [ -n "$d" ] && [ "$d" -gt "$i" ] && chk 14-e-injection-removed-at-the-end ok || chk 14-e-injection-removed-at-the-end bad "insert@$i delete@$d"
grep -q "make_interval(secs => 540::double precision)" "$F" && chk 14-e-backdate-default-540 ok || chk 14-e-backdate-default-540 bad
grep -q "stobe-auto save kah-imm26-14e-$L" "$F" && grep -q "stobe-auto load kah-imm26-14e-$L" "$F" && chk 14-e-save-and-load ok || chk 14-e-save-and-load bad
scen 14e-pass; ROW_BACKDATE_S=300 run 14-e $L >/dev/null; grep -q "make_interval(secs => 300::double precision)" "$F" && chk 14-e-backdate-knob ok || chk 14-e-backdate-knob bad
last_inj() { grep -a -F -- "INSERT INTO general_settings (id,value) VALUES ('NEG_TEST_INJECT'" "$F" | tail -1; }
scen 13g-counter353; run 13-g $L >/dev/null
last_inj | grep -q '"amount":353' && ! last_inj | grep -q '"amount":20' && chk 13-g-reinject-accept-at-read-price-353 ok || chk 13-g-reinject-accept-at-read-price-353 bad "$(last_inj | cut -c1-300)"
grep -q "stobe-auto money Shay -353" "$F" && chk 13-g-counter353-pays-353 ok || chk 13-g-counter353-pays-353 bad
scen 14e-pass; run 14-e $L >/dev/null
last_inj | grep -q '"amount":353' && ! last_inj | grep -q '"amount":20' && chk 14-e-reinject-accept-at-read-price-353 ok || chk 14-e-reinject-accept-at-read-price-353 bad "$(last_inj | cut -c1-300)"
scen 13f-pass; run 13-f $L >/dev/null
last_inj | grep -q '"amount":' && chk 13-f-reinject-uses-read-price ok || chk 13-f-reinject-uses-read-price bad
scen 13g-pass; run 13-g $L >/dev/null
grep -q "stobe-auto money Shay -20" "$F" && grep -q "stobe-auto money '#2529907200/2' 20" "$F" && chk 13-g-pay-statements ok || chk 13-g-pay-statements bad "$(grep -a 'stobe-auto money' "$F" | head -3)"
grep -q "STOBE_TRIP_RESUME_MAX_COUNT" "$F" && chk 13-g-never-touches-resume-cap bad || chk 13-g-never-touches-resume-cap ok
scen 13f-pass; run 13-f $L >/dev/null
grep -q "update stobe_social_contract set deadline_unix=extract(epoch from now())::int-(300+60), deadline_gamets=5000-30" "$F" && chk 13-f-deadline-forced-past-incl-shift ok || chk 13-f-deadline-forced-past-incl-shift bad "$(grep -a 'deadline_unix' "$F" | head -1)"
grep -q "stobe-auto money" "$F" && chk 13-f-never-pays bad || chk 13-f-never-pays ok
scen 10e-pass; run 10-e $L >/dev/null
[ "$(grep -a -c 'repairprobe.php' "$F")" = 3 ] && chk 10-e-three-probe-calls ok || chk 10-e-three-probe-calls bad "$(grep -a -c 'repairprobe.php' "$F")"
grep -a -E 'repairprobe.php' "$F" | grep -q -E 'INSERT|UPDATE|DELETE' && chk 10-e-probe-no-write bad || chk 10-e-probe-no-write ok
grep -q -i -E "insert into|update stobe|delete from" <(sed -n '/rb:probe/,$p' "$F" | grep -a -v '^###' | head -0) ;
scen 19e-pass; run 19-e $L >/dev/null
tl=$(grep -a -n "stobe-auto teleport" "$F" | tail -1 | cut -d: -f1); s4=$(grep -a -n "stobe_say" "$F" | tail -2 | head -1 | cut -d: -f1); wh=$(grep -a -n "rb:near19e" "$F" | tail -1 | cut -d: -f1)
[ -n "$tl" ] && [ -n "$wh" ] && [ -n "$s4" ] && [ "$tl" -lt "$wh" ] && [ "$wh" -lt "$s4" ] && chk 19-e-teleport-then-where-then-s4 ok || chk 19-e-teleport-then-where-then-s4 bad "tele@$tl where@$wh s4@$s4"
grep -a -c "stobe_say" "$F" | grep -q '^4$' && chk 19-e-exactly-two-post-load-says ok || chk 19-e-exactly-two-post-load-says bad "$(grep -a -c stobe_say "$F")"
grep -a -F "stobe_say" "$F" | tail -2 | head -1 | grep -q "Where were we going" && chk 19-e-first-post-load-line-is-the-resume-turn ok || chk 19-e-first-post-load-line-is-the-resume-turn bad
grep -a -F "stobe_say" "$F" | tail -1 | grep -q "right behind you" && chk 19-e-second-post-load-line-is-the-receipt-turn ok || chk 19-e-second-post-load-line-is-the-receipt-turn bad
grep -q "stobe-auto speed 2 " "$F" && grep -q "stobe-auto speed 0.5 " "$F" && chk 19-e-speed-up-and-restore ok || chk 19-e-speed-up-and-restore bad
export ROW_19F_N=3 ROW_19F_CAP=2 ROW_19F_MODE=cap; scen 19f-capmode-pass; run 19-f $L >/dev/null; unset ROW_19F_N ROW_19F_CAP ROW_19F_MODE
i=$(last_line "VALUES ('STOBE_TRIP_RESUME_MAX_COUNT','2')"); d=$(last_line "DELETE FROM general_settings WHERE id='STOBE_TRIP_RESUME_MAX_COUNT'")
[ -n "$i" ] && [ -n "$d" ] && [ "$d" -gt "$i" ] && chk 19-f-cap-setting-set-then-removed ok || chk 19-f-cap-setting-set-then-removed bad "set@$i del@$d"

# ---- the verdict comes from reloadcheck_b.py through pywrap_b.sh, never from rowcheck.py; rowcheck.py rows still pass through
"$P" "$ST_HERE/reloadcheck_b.py" --has 14-e && "$P" "$ST_HERE/reloadcheck_b.py" --has IMM-19-f && ! "$P" "$ST_HERE/reloadcheck_b.py" --has 19-a && chk checker-ownership ok || chk checker-ownership bad
"$ST_HERE/pywrap_b.sh" -c 'print("x")' | grep -q '^x$' && chk pywrap-passthrough ok || chk pywrap-passthrough bad
o=$("$ST_HERE/pywrap_b.sh" "$ST_HERE/rowcheck.py" 19-a "$T/none" 2>&1); echo "$o" | grep -q 'RESULT 19-a' && chk pywrap-other-rows-go-to-rowcheck ok || chk pywrap-other-rows-go-to-rowcheck bad "$o"
# the shared files are unmodified by set B: no set-B marker may appear in their diff against HEAD (other fixers may have their own edits there)
dd=$(cd "$A" && git diff HEAD -- rowtools/rowdefs.sh rowtools/tripdefs.sh rowtools/rowcheck.py rowtools/rowcheck_trip.py go-row.sh 2>/dev/null)
echo "$dd" | grep -q -E 'rd_(14e|13f|13g|10e|19e|19f)|c_(14e|13f|13g|10e|19e|19f)|reloaddefs_b|reloadcheck_b|pywrap_b|rb_' && chk shared-files-untouched-by-set-B bad || chk shared-files-untouched-by-set-B ok

# ---- CLI: reloadrun-b.sh as its own process (reload, preflight, EVIDENCE lines, ONE RESULT line, exit codes, options)
cli() {
  bash -c ". '$ST_HERE/lane.sh'; lt_fake() { '$P' '$ST_HERE/reloadfake_b.py' \"\$@\"; }; export -f lt_fake; export P; exec bash '$ST_HERE/reloadrun-b.sh' \"\$@\"" _ "$@" 2>/dev/null
}
scen 14e-pass; o=$(cli 14-e $L --allow-retry selftest); rc=$?
[ "$(echo "$o" | grep -c '^RESULT ')" = 1 ] && echo "$o" | grep -q '^EVIDENCE 14-e deal_end.txt: C1|AWAITING_PERFORMANCE' && echo "$o" | tail -1 | grep -q '^RESULT 14-e PASS' && [ $rc = 0 ] && chk cli-reloadrun-b ok || chk cli-reloadrun-b bad "rc=$rc $o"
grep -q "load kah-imm26-5090-ready" "$KAH_ROW_FAKE_LOG" && chk cli-reload-ready-save ok || chk cli-reload-ready-save bad
scen 14e-pass; o=$(cli 14-e 5090-i4 --no-reload --allow-retry selftest --backdate 420); grep -q "make_interval(secs => 420::double precision)" "$KAH_ROW_FAKE_LOG" && ! grep -q "stobe-auto load kah-imm26-i4-trip2" "$KAH_ROW_FAKE_LOG" && chk cli-no-reload-and-backdate-option ok || chk cli-no-reload-and-backdate-option bad "$o"
scen 19f-capmode-pass; o=$(cli 19-f $L --no-reload --allow-retry selftest --mode cap --cap 2 --n 4 --dest Squin); echo "$o" | tail -1 | grep -q '^RESULT 19-f PASS' && grep -q "VALUES ('STOBE_TRIP_RESUME_MAX_COUNT','2')" "$KAH_ROW_FAKE_LOG" && chk cli-19f-cap-options ok || chk cli-19f-cap-options bad "$o"
scen 14e-pass; o=$(cli 14-e 4080-i4 --allow-retry selftest); echo "$o" | grep -q 'RESULT 14-e SETUP-FAIL' && chk cli-unknown-save-setup-fail ok || chk cli-unknown-save-setup-fail bad "$o"
o=$(cli 99-z $L); echo "$o" | grep -q 'RESULT 99-z SETUP-FAIL not a set-B reload row' && chk cli-unknown-row ok || chk cli-unknown-row bad "$o"
o=$(cli 10-f $L); echo "$o" | grep -q 'RESULT 10-f SETUP-FAIL not a set-B reload row' && chk cli-10f-not-runnable ok || chk cli-10f-not-runnable bad "$o"
scen 14e-pass; o=$(cli 14-e $L --dry); echo "$o" | grep -q '^RESULT 14-e DRY-RUN' && chk cli-dry-run ok || chk cli-dry-run bad "$o"
scen 14e-pass; cli 13-g $L --no-reload --allow-retry selftest >/dev/null; o=$(bash -c ". '$ST_HERE/lane.sh'; lt_load $L; ls '$KAH_ROWS_BASE/imm26-5090-i3/rows/13-g' | head -30" 2>/dev/null); echo "$o" | grep -q 'result.txt' && chk cli-evidence-dir-written ok || chk cli-evidence-dir-written bad "$o"

# ---- attempt guard still applies (a FAIL blocks the next plain run), selftest overrides it
scen 14e-fired1; gr_main --no-preflight --allow-retry selftest 14-e $L >/dev/null 2>&1
scen 14e-pass; r=$(gr_main --no-preflight 14-e $L 2>/dev/null)
echo "$r" | grep -q '^ROW-NEEDS-FIXER 14-e' && chk attempt-guard-blocks-after-fail ok || chk attempt-guard-blocks-after-fail bad "$r"

rm -rf "$T"
if [ $ok = $n ]; then echo "SELFTEST RELOAD-B ALL PASS $ok/$n"; exit 0; else echo "SELFTEST RELOAD-B ALL FAIL $ok/$n"; exit 1; fi
