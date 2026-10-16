#!/usr/bin/env bash
# selftest.sh: OFFLINE self-test of preflight.sh / go-row.sh / go-batch.sh / heartbeat (no game, no ssh, no WSL, no DB; fake lane dirs under a temp base).
# Usage: bash rowtools/selftest.sh   -> prints `SELFTEST <name> PASS|FAIL ...` lines and a final `SELFTEST ALL PASS|FAIL n/m`.
ST_HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; A="$ST_HERE/.."
PY=$(command -v python3 || command -v python)
T=$(mktemp -d); export KAH_ROWS_BASE="$T/runs" KAH_ROW_FAKE=1 KAH_ROW_FAKE_LOG="$T/fake.log" KAH_PF_ISOLATION=0 FAKE_STATE="$T/state.json"
export ROW_SETTLE=0 ROW_WAIT=1
unset KAH_AGENT_NAME KAH_ROW_DRY
mkdir -p "$KAH_ROWS_BASE"
n=0; ok=0
chk() { n=$((n+1)); if [ "$2" = ok ]; then ok=$((ok+1)); echo "SELFTEST $1 PASS ${3:-}"; else echo "SELFTEST $1 FAIL ${3:-}"; fi; }
. "$A/go-row.sh"                                                        # sources lane/rowlib/rowdefs/heartbeat/preflight (no main: sourced)
lt_fake() { "$PY" "$ST_HERE/fakelane.py" "$@"; }
scen() { rm -f "$FAKE_STATE"; export FAKE_SCEN="$T/scen.json"; cat > "$FAKE_SCEN"; }
run() { gr_main "$@" 2>/dev/null; }
dom='Recorded experience (data): promises: broken x2; property: no record; safety: no record; fighting beside: no record; secrets: no record'

# 1 12-b PASS (domains in prompt, replies differ)
scen <<EOF
{"steps":[{"reply":"You've got my attention, go on.","prompt":"$dom\nrecorded_experiences_with_addressee"},{"reply":"A raid? You are leading with the exciting part and leaving out the rest.","prompt":"x"}]}
EOF
r=$(run 12-b 5090-i3); case "$r" in "RESULT 12-b PASS"*) chk 12-b-pass ok;; *) chk 12-b-pass bad "$r";; esac
echo "$r" | grep -q 'evidence=' && [ -f "$KAH_ROWS_BASE/imm26-5090-i3/rows/12-b/s2/prompt.txt" ] && chk evidence-dir ok || chk evidence-dir bad
[ "$(echo "$r" | wc -l)" = 1 ] && chk one-line-output ok || chk one-line-output bad

# 2 12-d: aff75 gift transfers but no gate log line -> FAIL
scen <<EOF
{"inv0":{"SHAY":{"Machete":1},"CIND":{"Katana":1}},"steps":[{"reply":"As a gift, no."},{"reply":"Fine, take it.","give":["Katana"]}]}
EOF
r=$(run 12-d 4080-i4); case "$r" in "RESULT 12-d FAIL"*aff40_gate_reason_in_log*) echo "$r" | grep -q 'aff75_transferred=shay_gained' && chk 12-d-fail-gate-missing-transfer-ok ok || chk 12-d-fail-gate-missing-transfer-ok bad "$r";; *) chk 12-d-fail-gate-missing-transfer-ok bad "$r";; esac

# 3 08-a PASS (open personal_plan followup, negatives create none)
jq() { printf '%s' "${1//\"/\\\"}"; }   # escape for a JSON string
fu='followup-v1:x:y:{"topic_id":"t1","kind":"personal_plan","status":"open","ask_count":0,"not_before_gamets":3600,"expires_gamets":600000}'
scen <<EOF
{"steps":[{"reply":"I hope you find him.","full":[["social_followup","$(jq "$fu")"]]},{"reply":"a"},{"reply":"b"},{"reply":"c"}]}
EOF
r=$(run 08-a 5090-i4); case "$r" in "RESULT 08-a PASS"*neg3_no_followup*) chk 08-a-pass ok;; *) chk 08-a-pass bad "$r";; esac

# 4 24-b FAIL (no region_plan row)
scen <<EOF
{"steps":[{"reply":"General area changes the answer."}]}
EOF
r=$(run 24-b 5090-i5); case "$r" in "RESULT 24-b FAIL"*region_plan_row*) chk 24-b-fail ok;; *) chk 24-b-fail bad "$r";; esac

# 4b-4g 24-b strict (amended 2026-10-16): first leg offered + grounded destination + the Yes starts a real trip; 'no current offer' can never pass
rrj='{"stage":"route_ready","region":"Vain","proposed_region":"Vain","endpoint_label":"Hive Village E","endpoint_point":{"x":1,"y":2,"z":3}}'
prj='{"status":"PROPOSED","regional_goal":{"region":"Vain","endpoint_label":"Hive Village E"}}'
acj='{"status":"ACCEPTED","regional_goal":{"region":"Vain","endpoint_label":"Hive Village E"}}'
offer="Sure, let's head toward Vain. I'd lead us to Hive Village E first. Shall we set out?"
own='ACTION_EXEC: OWNED_TRAVEL accepted=1 agreement=a1'
scen <<EOF
{"steps":[{"reply":"$offer","full":[["region_plan","$(jq "$rrj")"],["travel_agreement","$(jq "$prj")"]]},{"reply":"Lead on, then.","full":[["travel_agreement","$(jq "$acj")"]],"log":["$own"]}]}
EOF
rm -rf "$KAH_ROWS_BASE/row-attempts"; r=$(run 24-b 5090-i5); case "$r" in "RESULT 24-b PASS"*first_leg_offered*trip_started_OWNED_TRAVEL*) chk 24-b-strict-pass ok;; *) chk 24-b-strict-pass bad "$r";; esac
scen <<EOF
{"steps":[{"reply":"I don't have a current offer for that area to act on yet.","full":[["region_plan","$(jq '{"stage":"awaiting_route","region":"Vain"}')"]]},{"reply":"ok"}]}
EOF
rm -rf "$KAH_ROWS_BASE/row-attempts"; r=$(run 24-b 5090-i5); case "$r" in "RESULT 24-b FAIL"*reply_not_fallback*first_leg_offered*) chk 24-b-no-current-offer-fails ok;; *) chk 24-b-no-current-offer-fails bad "$r";; esac
scen <<EOF
{"steps":[{"reply":"I understand the area you mean: Vain. I do not have a confirmed reachable point there yet.","full":[["region_plan","$(jq '{"stage":"cannot_route_yet","region":"Vain"}')"]]},{"reply":"ok"}]}
EOF
rm -rf "$KAH_ROWS_BASE/row-attempts"; r=$(run 24-b 5090-i5); case "$r" in "RESULT 24-b FAIL"*first_leg_offered*) chk 24-b-cannot-route-fails ok;; *) chk 24-b-cannot-route-fails bad "$r";; esac
scen <<EOF
{"steps":[{"reply":"Sure, let's head toward Vain.","full":[["region_plan","$(jq '{"stage":"route_ready","region":"Vain"}')"]]},{"reply":"Lead on, then.","full":[["travel_agreement","$(jq "$acj")"]],"log":["$own"]}]}
EOF
rm -rf "$KAH_ROWS_BASE/row-attempts"; r=$(run 24-b 5090-i5); case "$r" in "RESULT 24-b FAIL"*grounded_destination*) chk 24-b-ungrounded-fails ok;; *) chk 24-b-ungrounded-fails bad "$r";; esac
scen <<EOF
{"steps":[{"reply":"$offer","full":[["region_plan","$(jq "$rrj")"],["travel_agreement","$(jq "$prj")"]]},{"reply":"Hm, maybe later."}]}
EOF
rm -rf "$KAH_ROWS_BASE/row-attempts"; r=$(run 24-b 5090-i5); case "$r" in "RESULT 24-b FAIL"*yes_accepted_with_regional_goal*trip_started_OWNED_TRAVEL*) chk 24-b-no-started-trip-fails ok;; *) chk 24-b-no-started-trip-fails bad "$r";; esac
scen <<EOF
{"steps":[{"reply":"$offer","full":[["region_plan","$(jq "$rrj")"]]},{"reply":"ok"}]}
EOF
rm -rf "$KAH_ROWS_BASE/row-attempts"; r=$(run 24-b 5090-i5); case "$r" in "RESULT 24-b FAIL"*trip_started*) chk 24-b-offer-only-fails ok;; *) chk 24-b-offer-only-fails bad "$r";; esac

# 5 14-a GATED on old DLL (ctxpush unsupported)
scen <<EOF
{"ctxpush":"ERROR unknown command stobe_ctxpush","steps":[{"reply":"x"}]}
EOF
r=$(run 14-a 4080-i3); case "$r" in "RESULT 14-a GATED native-context blocker E607"*) chk 14-a-gated-E607 ok;; *) chk 14-a-gated-E607 bad "$r";; esac

# 6 preflight FAIL FAST: dist 126 / lane backend down / game down / unknown lane
scen <<EOF
{"dist":126.4,"steps":[]}
EOF
r=$(run 12-b 5090-i4); case "$r" in "RESULT 12-b SETUP-FAIL PREFLIGHT-FAIL dist_to_target=126.4 >= 80"*) chk preflight-dist ok;; *) chk preflight-dist bad "$r";; esac
scen <<EOF
{"backend_down":true,"steps":[]}
EOF
r=$(run 12-b 5090-i4); case "$r" in *"PREFLIGHT-FAIL lane backend down"*) chk preflight-backend-down ok;; *) chk preflight-backend-down bad "$r";; esac
scen <<EOF
{"game_down":true,"steps":[]}
EOF
pf=$(pf_run 4080-i3; echo "rc=$?"); case "$pf" in *"PREFLIGHT-FAIL game down"*"rc=2") chk preflight-game-down ok;; *) chk preflight-game-down bad "$pf";; esac
pf=$(pf_run 9999-i9; echo "rc=$?"); case "$pf" in *"PREFLIGHT-FAIL unknown lane"*"rc=2") chk preflight-unknown-lane ok;; *) chk preflight-unknown-lane bad "$pf";; esac
# PI-15: dead chat LLM provider (connection refused on a fake local base_url) -> PREFLIGHT-FAIL llm provider down before any lane/DB step; KAH_PF_LLM=0 skips the check
printf '{"base_url":"http://127.0.0.1:1/v1","model":"m"}' > "$T/llm-dead.json"
pf=$(unset KAH_ROW_FAKE; KAH_LLM_ALLOW_LOCAL=1 KAH_LLM_CONFIG="$T/llm-dead.json" KAH_LLM_CACHE_DIR="$T" KAH_LLM_TIMEOUT=3 pf_run 5090-i3; echo "rc=$?"); case "$pf" in "PREFLIGHT-FAIL llm provider down: LLM-HEALTH FAIL http=000"*"rc=2") chk preflight-llm-down ok;; *) chk preflight-llm-down bad "$pf";; esac
case "$pf" in *"down"*) chk preflight-llm-batch-stops-on-down ok;; *) chk preflight-llm-batch-stops-on-down bad "$pf";; esac
# preflight DB statements were issued (PLAYER_NAME, deals, agreements, anchor) and the OK line is printed
scen <<EOF
{"steps":[]}
EOF
pf=$(pf_run 5090-i3); case "$pf" in "PREFLIGHT-OK 5090-i3 dist=9.0 player_name=Shay open_deals/agreements=0/0"*) chk preflight-ok ok;; *) chk preflight-ok bad "$pf";; esac
grep -q "INSERT INTO general_settings (id,value) VALUES ('PLAYER_NAME','Shay')" "$KAH_ROW_FAKE_LOG" && grep -q "stobe_social_contract SET status='EXPIRED'" "$KAH_ROW_FAKE_LOG" \
  && grep -q "type='travel_agreement'" "$KAH_ROW_FAKE_LOG" && grep -q "imm26_anchor" "$KAH_ROW_FAKE_LOG" && chk preflight-clean-statements ok || chk preflight-clean-statements bad

# 7 19-a (see below); 06-c missing tombstone FAIL; 23-b no follow order SETUP-FAIL; 04-c PASS
acc='travel-v1:a:b:{"status":"ACCEPTED","plan_hash":"0dfde8c0","expires_gamets":374858,"accepted_by":["Cind","Shay"],"leader":"npc","destination":"Stumble Inn"}'
# 7 19-a trip resume (option B): the SAME agreement continues after save+load; defect variants; 19-a-nc2; 19-d (needs tripdefs.sh)
rs() { "$PY" "$ST_HERE/resume_scen.py" "$1" | scen; }
rexp() {  # rexp <name> <scenario> <row> <RESULT prefix> [must-contain]
  local r; rs "$2"; r=$(gr_main --allow-retry "selftest" "$3" 5090-i4 2>/dev/null)
  case "$r" in "$4"*) if [ -z "${5:-}" ] || echo "$r" | grep -q -- "$5"; then chk "$1" ok; else chk "$1" bad "missing '$5' in: $r"; fi;; *) chk "$1" bad "$r";; esac
}
rexp 19-a-resume-pass 19a-pass 19-a "RESULT 19-a PASS" "post_s5_first_order_MOVE_CUS_ORDERED"
rexp 19-a-failed-and-reproposed 19a-failed 19-a "RESULT 19-a FAIL" "phase_interrupted_by_load"
rexp 19-a-no-pre-start-setup-fail 19a-nostart 19-a "RESULT 19-a SETUP-FAIL no pre-load OWNED_TRAVEL"
rexp 19-a-two-starts 19a-dup-start 19-a "RESULT 19-a FAIL" "exactly_one_post_load_OWNED_TRAVEL_accepted"
rexp 19-a-accept-in-s3-pass 19a-accept-s3 19-a "RESULT 19-a PASS" "agreement_ACCEPTED"
rexp 19-a-nc-starts-a-trip 19a-nc-bad 19-a "RESULT 19-a FAIL" "NC_no_OWNED_TRAVEL"
rexp 19-a-wrong-destination 19a-wrong-order 19-a "RESULT 19-a FAIL" "post_s5_destination_within_0.5"
rexp 19-a-nc2-pass nc2-pass 19-a-nc2 "RESULT 19-a-nc2 PASS" "no_resume_rows"
rexp 19-a-nc2-resumed-despite-range nc2-resumed 19-a-nc2 "RESULT 19-a-nc2 FAIL" "no_OWNED_TRAVEL_accepted"
if declare -F tr_arrive >/dev/null; then
  rexp 19-d-completed 19d-pass 19-d "RESULT 19-d PASS" "owned_work_released_true=true"
  grep -qE "teleport 'Cind \[Hungry Bandit\]' -62380(\.0)? 330(\.0)? 16250(\.0)?" "$KAH_ROW_FAKE_LOG" && chk 19-d-gate-from-agr_pre ok || chk 19-d-gate-from-agr_pre bad "no teleport to the agr_pre destination_point"
  rexp 19-d-not-completed 19d-notdone 19-d "RESULT 19-d FAIL" "agreement_COMPLETED"
fi
jax='social-pref-v1:z:{"entries":{"personal:address":{"value":"Jax","status":"active"}}}'
scen <<EOF
{"steps":[{"reply":"Boss it is.","full":[["social_preferences","social-pref-v1:z:{\"entries\":{\"personal:address\":{\"value\":\"Boss\",\"status\":\"active\"}}}"]]},{"reply":"Jax.","full":[["social_preferences","$(jq "$jax")"]]},{"reply":"Not sure."},{"reply":"Fine."}]}
EOF
r=$(run 06-c 5090-i5); case "$r" in "RESULT 06-c FAIL"*forget_wrote_tombstone*) echo "$r" | grep -q 'call_me_Jax_replaced_row=' && chk 06-c-fail-no-tombstone ok || chk 06-c-fail-no-tombstone bad "$r";; *) chk 06-c-fail-no-tombstone bad "$r";; esac
scen <<EOF
{"follow_log":[[]],"steps":[{"reply":"I'll walk with you."}]}
EOF
r=$(run 23-b 5090-i3); case "$r" in "RESULT 23-b SETUP-FAIL no follow order"*) chk 23-b-setup-fail ok;; *) chk 23-b-setup-fail bad "$r";; esac
# SETUP-FAIL unblock tickets (tools/automation/setupfail.py via attempts.py): the SETUP-FAIL above opened <runs>/setupfail/23-b.json + an inbox note for the coordinator
[ -f "$KAH_ROWS_BASE/setupfail/23-b.json" ] && grep -q '"state": "open"' "$KAH_ROWS_BASE/setupfail/23-b.json" && grep -q '"lane": "5090-i3"' "$KAH_ROWS_BASE/setupfail/23-b.json" && ls "$KAH_ROWS_BASE"/inbox/coordinator/*-setupfail-23-b.msg >/dev/null 2>&1 && chk setupfail-ticket-opened ok || chk setupfail-ticket-opened bad "$(ls "$KAH_ROWS_BASE/setupfail" 2>&1)"
"$PY" "$ST_HERE/attempts.py" reset "$KAH_ROWS_BASE/row-attempts" 5090-i3 23-b "selftest: deliberate setup-fail then pass" >/dev/null
scen <<EOF
{"follow_log":[["HOOK_MSG_PROC: FOLLOW target resolved arg='Shay'","FOLLOW_TICK: follower=Cind"],["HOOK_MSG_PROC: FOLLOW target resolved arg='Shay'","FOLLOW_TICK: follower=Cind","FOLLOW_EXPIRED: follower=2529907200 started_gamets=1"]],"steps":[{"reply":"I'll walk with you."}]}
EOF
r=$(run 23-b 5090-i3); case "$r" in "RESULT 23-b PASS"*follow_ended_by_expiry*) chk 23-b-pass ok;; *) chk 23-b-pass bad "$r";; esac
grep -q '"state": "closed"' "$KAH_ROWS_BASE/setupfail/23-b.json" && chk setupfail-ticket-closed-on-pass ok || chk setupfail-ticket-closed-on-pass bad
scen <<EOF
{"steps":[{"reply":"Dax? He owes you nothing.","prompt":"Your ties to people just named:\n- Rethar Dax: familial (you)"}]}
EOF
r=$(run 04-c 5090-i5); case "$r" in "RESULT 04-c PASS"*tie_line_names_B*) chk 04-c-pass ok;; *) chk 04-c-pass bad "$r";; esac

# 8 heartbeat: status latest = RESULT line when KAH_AGENT_NAME is set and RUNNING; DONE status is never touched
# the status dir must be readable by BOTH this shell and powershell.exe: Git Bash $T via cygpath; WSL needs a /mnt/c dir (a \wsl$ path is slow, and an unreadable path made agent-status.ps1 fall back to the REAL C:\KenshiTestRuns and leave a fake RUNNING hbagent there)
HB="$T/hbruns"; if command -v wslpath >/dev/null 2>&1 && [ -d /mnt/c/KenshiTestRuns ]; then HB="/mnt/c/KenshiTestRuns/selftest-hb-$$"; export KAH_RUNS_DIR=$(wslpath -w "$HB"); else export KAH_RUNS_DIR=$(cygpath -w "$HB" 2>/dev/null || echo "$HB"); fi
export WSLENV="${WSLENV:+$WSLENV:}KAH_RUNS_DIR"   # WSL does not pass env vars to powershell.exe unless listed in WSLENV; without it agent-status.ps1 wrote to the REAL runs dir
mkdir -p "$HB/agents" "$HB/inflight"; case "$KAH_RUNS_DIR" in [A-Za-z]:*) ;; *) echo "SELFTEST heartbeat-runs-dir FAIL KAH_RUNS_DIR=$KAH_RUNS_DIR is not a Windows path; skipping heartbeat checks"; HB_SKIP=1;; esac
printf '\xef\xbb\xbfhbagent | RUNNING | 2026-10-15 17:00\ntask: my rows\nlatest: x\noutputs: \nnext: more\n' > "$HB/agents/hbagent.status"
printf 'dagent | DONE | 2026-10-15 17:00\ntask: t\nlatest: final\noutputs: \nnext: \n' > "$HB/agents/dagent.status"
export KAH_HB_DRY=1
scen <<EOF
{"steps":[{"reply":"You've got my attention.","prompt":"$dom"},{"reply":"A raid? Sounds fun... maybe."}]}
EOF
out=$(KAH_AGENT_NAME=hbagent run 12-b 5090-i3 2>&1 | tr '\n' ' '); echo "$out" | grep -q 'HB hbagent RUNNING latest=RESULT 12-b ' && chk heartbeat-latest-is-RESULT ok || chk heartbeat-latest-is-RESULT bad "$out"
scen <<EOF
{"steps":[{"reply":"You've got my attention.","prompt":"$dom"},{"reply":"A raid? Sounds fun... maybe."}]}
EOF
out=$(KAH_AGENT_NAME=dagent run 12-b 5090-i3 2>&1 | tr '\n' ' '); echo "$out" | grep -q 'HB dagent' && chk heartbeat-skips-DONE bad "$out" || chk heartbeat-skips-DONE ok
unset KAH_HB_DRY
# real agent-status.ps1 call against a temp runs dir (proves argv + latest line); needs powershell.exe
if command -v powershell.exe >/dev/null 2>&1 && [ -z "${HB_SKIP:-}" ]; then
  scen <<EOF
{"steps":[{"reply":"You've got my attention.","prompt":"$dom"},{"reply":"A raid? Sounds fun... maybe."}]}
EOF
  KAH_AGENT_NAME=hbagent run 12-b 5090-i3 >/dev/null 2>&1
  grep -q '^latest: RESULT 12-b' "$HB/agents/hbagent.status" && grep -q '^task: my rows' "$HB/agents/hbagent.status" && chk heartbeat-agent-status-ps1 ok || chk heartbeat-agent-status-ps1 bad "$(cat "$HB/agents/hbagent.status")"
fi
unset KAH_RUNS_DIR; rm -rf "$HB"

# 9 batch (foreground): one RESULT per row in results.txt, DONE + summary; lane-down skips the rest
scen <<EOF
{"steps":[{"reply":"You've got my attention.","prompt":"$dom"},{"reply":"A raid? Sounds fun... maybe."}]}
EOF
o=$(bash -c ". '$ST_HERE/lane.sh'; lt_fake() { '$PY' '$ST_HERE/fakelane.py' \"\$@\"; }; export -f lt_fake; export PY; exec bash '$A/go-batch.sh' --fg 5090-i3 12-b 24-b zz-9" 2>&1)
res=$(echo "$o" | sed -nE 's/.*results=(.*)/\1/p'); d=$(dirname "$res")
[ -f "$d/DONE" ] && [ "$(wc -l < "$res")" = 3 ] && grep -q '^RESULT 12-b PASS' "$res" && grep -q '^RESULT zz-9 SETUP-FAIL row not ported' "$res" && chk batch-fg ok || chk batch-fg bad "$o | $(cat "$res" 2>/dev/null)"
# 10 DRY-RUN prints DRY-RUN and the planned steps (default simulator)
unset FAKE_SCEN; unset -f lt_fake
r=$(KAH_ROW_DRY=1 run 12-d 4080-i4); case "$r" in "RESULT 12-d DRY-RUN planned lane=4080-i4 steps=2"*) chk dry-run ok;; *) chk dry-run bad "$r";; esac

# 11 PI-06 attempt guard + PI-09 timing: first attempt runs, second after FAIL blocks, override permits, PASS clears
lt_fake() { "$PY" "$ST_HERE/fakelane.py" "$@"; }
AD="$KAH_ROWS_BASE/row-attempts"; TL="$KAH_ROWS_BASE/row-timing.log"; L=4080-i3
scen <<EOF
{"steps":[{"reply":"x","prompt":"no domains here"},{"reply":"x"}]}
EOF
r=$(run 12-b $L); rc=$?; case "$r" in "RESULT 12-b FAIL"*) [ $rc = 1 ] && chk guard-first-attempt-runs ok || chk guard-first-attempt-runs bad "rc=$rc";; *) chk guard-first-attempt-runs bad "$r";; esac
n0=$(wc -l < "$KAH_ROW_FAKE_LOG")
r=$(run 12-b $L); rc=$?; n1=$(wc -l < "$KAH_ROW_FAKE_LOG")
case "$r" in "ROW-NEEDS-FIXER 12-b $L cause="*) [ $rc = 4 ] && [ "$n0" = "$n1" ] && [ "$(echo "$r" | wc -l)" = 1 ] && chk guard-second-attempt-blocked ok || chk guard-second-attempt-blocked bad "rc=$rc fake_lines=$n0/$n1";; *) chk guard-second-attempt-blocked bad "$r";; esac
r=$(run 12-b $L); case "$r" in ROW-NEEDS-FIXER*) chk guard-stays-blocked ok;; *) chk guard-stays-blocked bad "$r";; esac
r=$(run --allow-retry "selftest: operator override" 12-b $L); rc=$?; case "$r" in "RESULT 12-b FAIL"*) [ $rc = 1 ] && chk guard-allow-retry-runs ok || chk guard-allow-retry-runs bad "rc=$rc";; *) chk guard-allow-retry-runs bad "$r";; esac
grep -q 'row=12-b event=ALLOW attempt=2 reason=selftest: operator override' "$AD/attempts.log" && chk guard-allow-logged ok || chk guard-allow-logged bad "$(tail -3 "$AD/attempts.log")"
r=$(run 12-b $L); case "$r" in ROW-NEEDS-FIXER*) chk guard-override-is-one-shot ok;; *) chk guard-override-is-one-shot bad "$r";; esac
"$PY" "$ST_HERE/attempts.py" reset "$AD" $L 12-b "selftest: reset" | grep -q '^RESET' && grep -q 'event=RESET .*reason=selftest: reset' "$AD/attempts.log" && chk guard-reset-logged ok || chk guard-reset-logged bad
"$PY" "$ST_HERE/attempts.py" reset "$AD" $L 12-b "" >/dev/null; [ $? = 2 ] && chk guard-reset-needs-reason ok || chk guard-reset-needs-reason bad
scen <<EOF
{"steps":[{"reply":"You've got my attention.","prompt":"$dom"},{"reply":"A raid? Sounds fun... maybe."}]}
EOF
r=$(run 12-b $L); case "$r" in "RESULT 12-b PASS"*) chk guard-after-reset-runs-and-passes ok;; *) chk guard-after-reset-runs-and-passes bad "$r";; esac
"$PY" -c 'import json,sys;sys.exit(0 if "12-b" not in json.load(open(sys.argv[1]))["rows"] else 1)' "$AD/$L.json" && chk guard-pass-clears-state ok || chk guard-pass-clears-state bad
scen <<EOF
{"steps":[{"reply":"You've got my attention.","prompt":"$dom"},{"reply":"A raid? Sounds fun... maybe."}]}
EOF
r=$(run 12-b $L); case "$r" in "RESULT 12-b PASS"*) chk guard-rerun-after-pass-allowed ok;; *) chk guard-rerun-after-pass-allowed bad "$r";; esac
# a PREFLIGHT-FAIL (row never ran) does not count as an attempt
scen <<EOF
{"dist":126.4,"steps":[]}
EOF
run 24-b $L >/dev/null; run 24-b $L >/dev/null; r=$(run 24-b $L); case "$r" in "RESULT 24-b SETUP-FAIL PREFLIGHT-FAIL"*) chk guard-preflight-fail-not-counted ok;; *) chk guard-preflight-fail-not-counted bad "$r";; esac
[ ! -e "$KAH_ROWS_BASE/setupfail/24-b.json" ] && chk setupfail-preflight-fail-no-ticket ok || chk setupfail-preflight-fail-no-ticket bad
# every attempt is logged (audit): VERDICT lines for the 12-b runs above, plus the BLOCK
[ "$(grep -c "lane=$L row=12-b event=VERDICT" "$AD/attempts.log")" -ge 4 ] && grep -q 'row=12-b event=BLOCK' "$AD/attempts.log" && chk guard-audit-log ok || chk guard-audit-log bad
# PI-09: row-timing.log has one line per go-row call incl. the blocked ones
grep -E "^[0-9T:-]+ lane=$L row=12-b verdict=FAIL wall_s=[0-9]+ steps=[0-9]+ attempt=1 agent=-" "$TL" >/dev/null && grep -q 'row=12-b verdict=NEEDS-FIXER wall_s=0' "$TL" && grep -q 'row=12-b verdict=PASS wall_s=' "$TL" && chk timing-log-lines ok || chk timing-log-lines bad "$(tail -4 "$TL")"
# batch: a blocked row shows as ROW-NEEDS-FIXER, others still run, summary counts it; --allow-retry passes through
scen <<EOF
{"steps":[{"reply":"x","prompt":"no domains here"},{"reply":"x"}]}
EOF
run 12-b $L >/dev/null; run 12-b $L >/dev/null   # FAIL (attempt 1), then blocked
bo() { bash -c ". '$ST_HERE/lane.sh'; lt_fake() { '$PY' '$ST_HERE/fakelane.py' \"\$@\"; }; export -f lt_fake; export PY; exec bash '$A/go-batch.sh' --fg $*" 2>&1; }
o=$(bo $L 12-b zz-9); res=$(echo "$o" | sed -nE 's/.*results=(.*)/\1/p'); d=$(dirname "$res")
grep -q '^ROW-NEEDS-FIXER 12-b' "$res" && grep -q '^RESULT zz-9 SETUP-FAIL' "$res" && grep -q '^NEEDS-FIXER=1' "$d/summary.txt" && chk batch-needs-fixer ok || chk batch-needs-fixer bad "$(cat "$res" 2>/dev/null)"
o=$(bo --allow-retry "selftest-batch-override" $L 12-b); res=$(echo "$o" | sed -nE 's/.*results=(.*)/\1/p')
grep -q '^RESULT 12-b FAIL' "$res" && grep -q 'event=ALLOW .*reason=selftest-batch-override' "$AD/attempts.log" && chk batch-allow-retry ok || chk batch-allow-retry bad "$(cat "$res" 2>/dev/null)"

# 12 trip-family rows (13-b 20-a 20-b 23-a 23-c 23-d 24-a + wrapped 19-a/23-b/24-b): own temp dir, see README_TRIP.md
ts=$(bash "$ST_HERE/trip-selftest.sh" 2>&1 | tail -1); case "$ts" in "SELFTEST TRIP ALL PASS"*) chk trip-family-selftest ok "$ts";; *) chk trip-family-selftest bad "$ts";; esac
# 6 hardening rows (17-bx 18-cx 16-bx 15-bx 13-ax 02-ax): README_HX.md
hs=$(bash "$ST_HERE/hx-selftest.sh" 2>&1 | tail -1); case "$hs" in "SELFTEST HX ALL PASS"*) chk hx-hardening-selftest ok "$hs";; *) chk hx-hardening-selftest bad "$hs";; esac

rm -rf "$T"
if [ $ok = $n ]; then echo "SELFTEST ALL PASS $ok/$n"; exit 0; else echo "SELFTEST ALL FAIL $ok/$n"; exit 1; fi
