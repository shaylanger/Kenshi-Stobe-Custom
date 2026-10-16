#!/usr/bin/env bash
# hxa-selftest.sh: OFFLINE self-test of the family-A hardening rows (hxdefs_a.sh / hxcheck_a.py via hxrun.sh: 01-bx 01-cx 02-cx). No game, ssh or DB: lanes are simulated by
# hxfake_a.py (-> hxfake.py -> fakelane.py), scenarios by hxscen_a.py, the assert_*.py scripts are logging stubs (HX_ASSERT_DIR) to check the exact command lines; real
# asserts run once over garbage bundles (must FAIL cleanly).  Prints `SELFTEST hxa-<name> PASS|FAIL` and `SELFTEST HXA ALL PASS|FAIL n/m`.  Run in WSL:
#   bash testing/live-stobe-queue/imm26-assert/rowtools/hxa-selftest.sh      (about 1-2 min)
ST_HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; A="$ST_HERE/.."
PYB=$(command -v python3 || command -v python); export PYB
T=$(mktemp -d); export KAH_ROWS_BASE="$T/runs" KAH_ROW_FAKE=1 KAH_ROW_FAKE_LOG="$T/fake.log" KAH_PF_ISOLATION=0 KAH_PF_LLM=0 FAKE_STATE="$T/state.json"
export ROW_SETTLE=0 ROW_WAIT=1 STUB_LOG="$T/assert.log" HX02C_PANEL_TRIES=2
unset KAH_AGENT_NAME KAH_ROW_DRY HX_OUT HX_SAVE HX_SAVE2 HX_PRELOADED HX_NATIVE HX01C_H HX01C_A HX01C_PF HX02C_CTL
mkdir -p "$KAH_ROWS_BASE" "$T/stubs"
printf '%s\n' 'import os, sys' "open(os.environ['STUB_LOG'], 'a').write(' '.join(sys.argv[1:]) + chr(10))" "print('RESULT %s %s stub-evidence' % (sys.argv[1], os.environ.get('STUB_KIND', 'PASS')))" > "$T/stubs/assert_stance.py"
cp "$T/stubs/assert_stance.py" "$T/stubs/assert_principle.py"
n=0; ok=0
chk() { n=$((n+1)); if [ "$2" = ok ]; then ok=$((ok+1)); echo "SELFTEST hxa-$1 PASS ${3:-}"; else echo "SELFTEST hxa-$1 FAIL ${3:-}"; fi; }
. "$A/go-row.sh"; . "$ST_HERE/hxdefs.sh"; . "$ST_HERE/hxdefs_a.sh"
PY="$ST_HERE/pywrap_hx.sh"
lt_fake() { "$PYB" "$ST_HERE/hxfake_a.py" "$@"; }
scen() { rm -f "$FAKE_STATE" "$FAKE_STATE.hx" "$FAKE_STATE.hxa" "$STUB_LOG"; export FAKE_SCEN="$T/scen.json"; "$PYB" "$ST_HERE/hxscen_a.py" "$1" > "$FAKE_SCEN"; : > "$KAH_ROW_FAKE_LOG"; }
run() { gr_main --allow-retry "selftest" "$@" 2>/dev/null; }
L=5090-i3; EVD="$KAH_ROWS_BASE/imm26-5090-i3/rows"
export HX_ASSERT_DIR="$T/stubs"
expect() { local r; scen "$2"; r=$(run "$3" $L); case "$r" in "$4"*) if [ -z "${5:-}" ] || echo "$r" | grep -q -- "$5"; then chk "$1" ok; else chk "$1" bad "missing '$5' in: $r"; fi;; *) chk "$1" bad "$r";; esac; }
logn() { grep -c -- "$1" "$KAH_ROW_FAKE_LOG"; }
argn() { sed -E 's#[^ ]*/##g' "$STUB_LOG" 2>/dev/null | sed -n "${1}p"; }

# --- 01-bx
scen base; r=$(run 01-bx $L); D="$EVD/01-bx"
case "$r" in "RESULT 01-bx PASS"*) chk 01-bx-pass ok;; *) chk 01-bx-pass bad "$r";; esac
w1="01-bx --target T1 T2 T3 --ctl-nohist CN1 CN2 CN3 --ctl-pos CP1 CP2 CP3 --seed Sure, a walk sounds good.|Fine, lead the way.|Count me in."
[ "$(wc -l < "$STUB_LOG")" = 2 ] && [ "$(argn 1)" = "$w1" ] && [ "$(argn 2)" = "$w1" ] && grep -q 'savA/T1' "$STUB_LOG" && grep -q 'savB/CP3' "$STUB_LOG" && chk 01-bx-assert-argv-per-save ok || chk 01-bx-assert-argv-per-save bad "$(cat "$STUB_LOG")"
[ "$(logn 'stobe-auto load')" = 19 ] && chk 01-bx-reload-before-every-sample ok || chk 01-bx-reload-before-every-sample bad "loads=$(logn 'stobe-auto load')"
[ "$(logn 'insert into eventlog')" = 36 ] && chk 01-bx-seed-only-T-and-CP ok || chk 01-bx-seed-only-T-and-CP bad "inserts=$(logn 'insert into eventlog') (want 36 = 3 rows x 12 seeded samples)"
[ "$(logn "haff.php .*-80 platonic")" = 12 ] && [ "$(logn "haff.php .* 60 platonic")" = 6 ] && chk 01-bx-haff-set-counts ok || chk 01-bx-haff-set-counts bad
head -1 "$D/savA/T2/haff.txt" | grep -q '^aff=-80$' && head -1 "$D/savB/CN3/haff.txt" | grep -q '^aff=-80$' && head -1 "$D/savA/CP1/haff.txt" | grep -q '^aff=60$' && chk 01-bx-haff-files ok || chk 01-bx-haff-files bad "$(head -1 "$D/savA/T2/haff.txt")"
[ "$(cat "$D/savA/T1/utterance.txt")" != "$(cat "$D/savA/T2/utterance.txt")" ] && [ "$(cat "$D/savA/T1/utterance.txt")" = "$(cat "$D/savA/CN1/utterance.txt")" ] && [ -s "$D/savB/CP3/effects_full.txt" ] && chk 01-bx-utterances-and-effects-full ok || chk 01-bx-utterances-and-effects-full bad
grep -q 'sav\|kah-imm26-5090-hxA' "$D/savB/save.txt" && chk 01-bx-save-recorded ok || chk 01-bx-save-recorded bad
scen base; r=$(HX_SAVE=sA HX_SAVE2=sB run 01-bx $L); grep -q 'stobe-auto load sB' "$KAH_ROW_FAKE_LOG" && grep -q 'stobe-auto load sA' "$KAH_ROW_FAKE_LOG" && chk 01-bx-save-A-and-B-loaded ok || chk 01-bx-save-A-and-B-loaded bad
unset HX_SAVE HX_SAVE2
scen base; r=$(STUB_KIND=FAIL run 01-bx $L); case "$r" in "RESULT 01-bx FAIL"*savA=FAIL*savB=FAIL*) chk 01-bx-fail-passes-through ok;; *) chk 01-bx-fail-passes-through bad "$r";; esac
expect 01-bx-noseed noseed 01-bx "RESULT 01-bx SETUP-FAIL" "seed rows not inserted"
expect 01-bx-noreply noreply 01-bx "RESULT 01-bx SETUP-FAIL" "resolved_speaker is not Shay in"

# --- 01-cx
scen base; r=$(run 01-cx $L); D="$EVD/01-cx"
case "$r" in "RESULT 01-cx PASS"*) chk 01-cx-pass ok;; *) chk 01-cx-pass bad "$r";; esac
w2="01-cx --target H1 H2 H3 --ctl A1 A2 A3"
[ "$(wc -l < "$STUB_LOG")" = 2 ] && [ "$(argn 1)" = "$w2" ] && [ "$(argn 2)" = "$w2" ] && grep -q 'savB/A3' "$STUB_LOG" && chk 01-cx-assert-argv-per-save ok || chk 01-cx-assert-argv-per-save bad "$(cat "$STUB_LOG")"
grep -q 'H Bob Faction -> Nameless: before=20.0 set=-100 after=-100.0' "$D/faction_rel_set.txt" && grep -q 'A Rethar Faction -> Nameless: before=20.0 set=70 after=70.0' "$D/faction_rel_set.txt" && chk 01-cx-relation-set-recorded ok || chk 01-cx-relation-set-recorded bad "$(cat "$D/faction_rel_set.txt" 2>&1 | head -3)"
head -1 "$D/savA/H1/faction_rel.txt" | grep -q '^rel=-100' && head -1 "$D/savB/A3/faction_rel.txt" | grep -q '^rel=70' && chk 01-cx-faction-rel-files ok || chk 01-cx-faction-rel-files bad "$(head -1 "$D/savA/H1/faction_rel.txt")"
grep -q 'H=Bob Smith .*A=Rethar Dax' "$D/strangers.txt" && chk 01-cx-strangers-picked-from-chars ok || chk 01-cx-strangers-picked-from-chars bad "$(cat "$D/strangers.txt")"
[ "$(logn 'stobe-auto load')" = 2 ] && chk 01-cx-two-saves-two-loads ok || chk 01-cx-two-saves-two-loads bad "loads=$(logn 'stobe-auto load')"
[ -f "$D/savA/H3/state.txt" ] && [ -s "$D/savB/A1/effects_full.txt" ] && chk 01-cx-state-and-effects-full ok || chk 01-cx-state-and-effects-full bad
scen rel-inband; r=$(run 01-cx $L); case "$r" in "RESULT 01-cx PASS"*) [ "$(logn 'update faction_relation_state')" = 0 ] && grep -q 'kept' "$EVD/01-cx/faction_rel_set.txt" && chk 01-cx-inband-relations-untouched ok || chk 01-cx-inband-relations-untouched bad "writes=$(logn 'update faction_relation_state')";; *) chk 01-cx-inband-relations-untouched bad "$r";; esac
scen base; r=$(HX01C_H="Bob Smith" HX01C_A="Rethar Dax" run 01-cx $L); [ "$(logn 'chars 3000')" = 0 ] && case "$r" in "RESULT 01-cx PASS"*) chk 01-cx-named-strangers-skip-chars ok;; *) chk 01-cx-named-strangers-skip-chars bad "$r";; esac || chk 01-cx-named-strangers-skip-chars bad "chars queried"
expect 01-cx-relation-not-in-band norelwrite 01-cx "RESULT 01-cx SETUP-FAIL" "not in the H band"
expect 01-cx-same-faction samefac 01-cx "RESULT 01-cx SETUP-FAIL" "no stranger pair found"
expect 01-cx-no-stranger nostranger 01-cx "RESULT 01-cx SETUP-FAIL" "no stranger pair found"
expect 01-cx-listener-in-combat combat 01-cx "RESULT 01-cx SETUP-FAIL" "is in combat"
expect 01-cx-noreply noreply 01-cx "RESULT 01-cx SETUP-FAIL" "resolved_speaker is not Shay in"

# --- 02-cx
scen base; r=$(run 02-cx $L); D="$EVD/02-cx"
case "$r" in "RESULT 02-cx PASS"*) chk 02-cx-pass ok;; *) chk 02-cx-pass bad "$r";; esac
[ "$(argn 1)" = "02-cx --target C1 C2 C3 --ctl O1 O2 O3 --principle slavery" ] && chk 02-cx-assert-argv ok || chk 02-cx-assert-argv bad "$(cat "$STUB_LOG")"
grep -q 'stobe-auto save kah-imm26-hx-02c-1' "$KAH_ROW_FAKE_LOG" && grep -q 'stobe-auto save kah-imm26-hx-02c-2' "$KAH_ROW_FAKE_LOG" && [ "$(logn 'stobe-auto load kah-imm26-hx-02c-')" = 2 ] && chk 02-cx-two-lineages-save-and-load ok || chk 02-cx-two-lineages-save-and-load bad
grep -q 'slavery|opposed|firm' "$D/C1/principle_rows_pre.txt" && cmp -s "$D/C1/principle_rows_pre.txt" "$D/C1/principle_rows.txt" && cmp -s "$D/C3/principle_rows_pre.txt" "$D/C3/principle_rows.txt" && chk 02-cx-principle-rows-pre-and-post ok || chk 02-cx-principle-rows-pre-and-post bad
[ -s "$D/C2/profile_md5_before.txt" ] && cmp -s "$D/C2/profile_md5_before.txt" "$D/C2/profile_md5_after.txt" && chk 02-cx-profile-md5-equal ok || chk 02-cx-profile-md5-equal bad
grep -qi slavery "$D/C1/info_panel.txt" && grep -qi slavery "$D/C3/info_panel.txt" && chk 02-cx-info-panel-captured ok || chk 02-cx-info-panel-captured bad "$(cat "$D/C1/info_panel.txt" 2>&1 | head -2)"
[ ! -s "$D/O1/principle_rows.txt" ] && [ -f "$D/O3/reply.txt" ] && grep -q Karnic "$EV/ctl_npc.txt" 2>/dev/null || grep -q 'Karnic' "$D/ctl_npc.txt" && chk 02-cx-control-unrelated-npc ok || chk 02-cx-control-unrelated-npc bad
cmp -s "$D/profile_md5_original.txt" "$D/profile_md5_restored.txt" && grep -q "replace(personality" "$KAH_ROW_FAKE_LOG" && grep -q "personality||" "$KAH_ROW_FAKE_LOG" && chk 02-cx-profile-set-then-restored ok || chk 02-cx-profile-set-then-restored bad
scen profile_rewrite; run 02-cx $L >/dev/null; ! cmp -s "$EVD/02-cx/C1/profile_md5_before.txt" "$EVD/02-cx/C1/profile_md5_after.txt" && chk 02-cx-profile-rewrite-visible-in-md5s ok || chk 02-cx-profile-rewrite-visible-in-md5s bad
scen panel_silent; run 02-cx $L >/dev/null; ! grep -qi slavery "$EVD/02-cx/C1/info_panel.txt" && chk 02-cx-silent-panel-recorded-as-is ok || chk 02-cx-silent-panel-recorded-as-is bad
expect 02-cx-no-principle-row noprinciple 02-cx "RESULT 02-cx SETUP-FAIL" "no slavery row in imm26_npc_principle"
expect 02-cx-info-panel-command-fails panel_err 02-cx "RESULT 02-cx SETUP-FAIL" "stobe_npcinfo failed"
expect 02-cx-noreply noreply 02-cx "RESULT 02-cx SETUP-FAIL" "resolved_speaker is not Shay in"

# --- the stranger-list pipeline (sed quoting) run for real against a canned `chars` output
r=$( (unset KAH_ROW_FAKE; stobe-auto() { echo "4 within 3000.0: Shay #1/1 [N] pos=0 | Cind [Hungry Bandit] #2529907200/2 [T] pos=1 | Rethar Dax #5/1 [O] pos=2 | Bob Smith #8/3 [H] pos=3"; }
  export -f stobe-auto; lt_h() { bash; }; hxa01c_names 3000 | tr '
' ';') 2>&1 )
[ "$r" = "Bob Smith;Cind [Hungry Bandit];Rethar Dax;Shay;" ] && chk stranger-list-pipeline-real-shell ok || chk stranger-list-pipeline-real-shell bad "$r"

# --- hxcheck_a.py alone: missing dirs / no seed value / garbage bundles with the REAL asserts (FAIL or SETUP-FAIL, never a crash)
E="$T/empty"; mkdir -p "$E"
for rw in 01-bx 01-cx 02-cx; do r=$("$PYB" "$ST_HERE/hxcheck_a.py" $rw "$E"); case "$r" in "RESULT $rw SETUP-FAIL bundle dirs missing"*) chk "check-missing-dirs-$rw" ok;; *) chk "check-missing-dirs-$rw" bad "$r";; esac; done
for sv in savA savB; do for d in T1 T2 T3 CN1 CN2 CN3 CP1 CP2 CP3; do mkdir -p "$E/$sv/$d"; done; done
r=$("$PYB" "$ST_HERE/hxcheck_a.py" 01-bx "$E"); case "$r" in "RESULT 01-bx SETUP-FAIL savA: the row script wrote no value for --seed"*) chk check-missing-seed-value ok;; *) chk check-missing-seed-value bad "$r";; esac
G="$T/garbage"; mkdir -p "$G"; for sv in savA savB; do for d in T1 T2 T3 CN1 CN2 CN3 CP1 CP2 CP3 H1 H2 H3 A1 A2 A3; do mkdir -p "$G/$sv/$d"; echo x > "$G/$sv/$d/reply.txt"; echo "aff=0" > "$G/$sv/$d/haff.txt"; done; echo "a|b|c" > "$G/$sv/seed.txt"; done
for d in C1 C2 C3 O1 O2 O3; do mkdir -p "$G/$d"; echo x > "$G/$d/reply.txt"; done
for rw in 01-bx 01-cx 02-cx; do r=$(HX_ASSERT_DIR="" "$PYB" "$ST_HERE/hxcheck_a.py" $rw "$G" 2>&1); case "$r" in *Traceback*) chk "real-assert-garbage-$rw" bad "$r";; "RESULT $rw FAIL"*|"RESULT $rw SETUP-FAIL"*) chk "real-assert-garbage-$rw" ok;; *) chk "real-assert-garbage-$rw" bad "$r";; esac; done

# --- CLI hxrun.sh as a separate process (shared with the other families: the gate and the checker dispatch)
cli() { bash -c ". '$ST_HERE/lane.sh'; lt_fake() { \"\$PYB\" '$ST_HERE/hxfake_a.py' \"\$@\"; }; export -f lt_fake; exec bash '$ST_HERE/hxrun.sh' \"\$@\"" _ "$@" 2>/dev/null; }
for rw in 01-bx 01-cx 02-cx; do
  scen base; o=$(cli $rw $L --allow-retry selftest); rc=$?
  [ "$(echo "$o" | grep -c '^RESULT ')" = 1 ] && echo "$o" | tail -1 | grep -q "^RESULT $rw PASS" && [ $rc = 0 ] && chk "cli-hxrun-$rw" ok || chk "cli-hxrun-$rw" bad "rc=$rc $(echo "$o" | tail -2)"
  scen base; o=$(cli $rw $L --dry); echo "$o" | grep -q "^RESULT $rw DRY-RUN" && chk "cli-dry-run-$rw" ok || chk "cli-dry-run-$rw" bad "$o"
done
scen base; o=$(cli 01-bx 4080-i3 --allow-retry selftest); echo "$o" | grep -q 'RESULT 01-bx SETUP-FAIL RELOAD-FAIL no base save known' && chk cli-4080-needs-save ok || chk cli-4080-needs-save bad "$o"
scen base; o=$(cli 01-bx 4080-i3 --save kah-imm26-4080 --save2 kah-imm26-4080 --out "$T/out" --allow-retry selftest); echo "$o" | tail -1 | grep -q '^RESULT 01-bx PASS' && [ -d "$T/out/01-bx/savB/CP3" ] && chk cli-4080-save-out ok || chk cli-4080-save-out bad "$o"

# --- the existing rows still reach their checker through the shared gate
scen base; o=$(cli 02-ax $L --allow-retry selftest); echo "$o" | tail -1 | grep -q '^RESULT 02-ax ' && chk cli-02ax-still-routed ok || chk cli-02ax-still-routed bad "$o"

# --- originals untouched by this family (hxdefs.sh hxcheck.py hxfake.py hxscen.py hx-selftest.sh)
dd=$(cd "$A" && git diff HEAD --stat -- rowtools/hxdefs.sh rowtools/hxcheck.py rowtools/hxfake.py rowtools/hxscen.py rowtools/hx-selftest.sh rowtools/rowdefs.sh rowtools/rowcheck.py go-row.sh 2>/dev/null)
[ -z "$dd" ] && chk originals-untouched ok || chk originals-untouched bad "$dd"

rm -rf "$T"
if [ $ok = $n ]; then echo "SELFTEST HXA ALL PASS $ok/$n"; exit 0; else echo "SELFTEST HXA ALL FAIL $ok/$n"; exit 1; fi
