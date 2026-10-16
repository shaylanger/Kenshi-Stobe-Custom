#!/usr/bin/env bash
# unblock_c_selftest.sh: OFFLINE self-test of unblockdefs_c.sh / unblockcheck_c.py (rows 15-bx 20-a 10-b, imm26-u-rowsC). No game, ssh or DB: lanes are simulated by
# KAH_ROW_DRY (gr_default_fake) and the verdict logic is driven by synthetic evidence dirs; assert_witness.py / rowcheck.py are replaced by logging stubs.
# Prints `SELFTEST unblockC-<name> PASS|FAIL` and `SELFTEST UNBLOCK-C ALL PASS|FAIL n/m`.  Usage: bash rowtools/unblock_c_selftest.sh
ST_HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; A="$ST_HERE/.."
PYB=$(command -v python3 || command -v python); export PYB
T=$(mktemp -d); command -v cygpath >/dev/null && T=$(cygpath -m "$T"); export KAH_ROWS_BASE="$T/runs" KAH_ROW_FAKE_LOG="$T/fake.log" KAH_PF_ISOLATION=0 KAH_PF_LLM=0 ROW_SETTLE=0 ROW_WAIT=1 STUB_LOG="$T/assert.log"
unset KAH_AGENT_NAME KAH_ROW_DRY HX_OUT HX_SAVE HX_SAVE2 HX_PRELOADED UC_LOADED UB_VICTIM UB_GIFT
mkdir -p "$KAH_ROWS_BASE" "$T/stubs"
n=0; ok=0
chk() { n=$((n+1)); if [ "$2" = ok ]; then ok=$((ok+1)); echo "SELFTEST unblockC-$1 PASS ${3:-}"; else echo "SELFTEST unblockC-$1 FAIL ${3:-}"; fi; }
U="$ST_HERE/unblockdefs_c.sh"; C="$ST_HERE/unblockcheck_c.py"

# ---- 1. syntax
bash -n "$U" && chk bash-n ok || chk bash-n bad
"$PYB" -m py_compile "$C" && chk py-compile ok || chk py-compile bad
[ -x "$U" ] && chk defs-executable ok || chk defs-executable bad "chmod +x"
"$PYB" "$C" --has 15-bx && "$PYB" "$C" --has IMM-20-a && "$PYB" "$C" --has 10-b && ! "$PYB" "$C" --has 13-ax && chk checker-has ok || chk checker-has bad

# ---- 2. checker: 15-bx (assert_witness replaced by a logging stub; hxcheck.py builds the command line)
printf '%s\n' 'import os, sys' "open(os.environ['STUB_LOG'], 'a').write(' '.join(sys.argv[1:]) + chr(10))" "print('RESULT %s %s stub-evidence' % (sys.argv[1], os.environ.get('STUB_KIND', 'PASS')))" > "$T/stubs/assert_witness.py"
export HX_ASSERT_DIR="$T/stubs"
mk15() {  # mk15 <dir> [xdist] [pdist] [sleeper] [fighters] [starter] [xprompt-has-combat]
  local d="$1" xd="${2:-300}" pd="${3:-10}" sd="${4:-60}" fi="${5:-Vren,Dalla,Hungry}" st="${6:-Vren}" xc="${7:-no}" l
  rm -rf "$d"; mkdir -p "$d"; echo "$d" > "$d/bundle_dir.txt"
  for l in X1 X2 X3; do mkdir -p "$d/$l"; echo "Cind [Hungry Bandit]|$xd" > "$d/$l/distance.txt"; echo "x" > "$d/$l/prompt.txt"; done
  [ "$xc" = yes ] && echo "[combat Vren attacked Dalla] Vren: Initiated attack" > "$d/X1/prompt.txt"
  for l in P1 P2 P3; do mkdir -p "$d/$l"; echo "Cind [Hungry Bandit]|$pd" > "$d/$l/distance.txt"; done
  mkdir -p "$d/S1"; echo "Drifter One|$sd" > "$d/S1/distance.txt"
  echo "$fi" > "$d/fighters.txt"; echo "$st" > "$d/starter.txt"
}
c15() { "$PYB" "$C" 15-bx "$1" 2>/dev/null | head -1; }
mk15 "$T/e15a"; rm -f "$STUB_LOG"; r=$(STUB_KIND=PASS c15 "$T/e15a")
case "$r" in "RESULT 15-bx PASS"*) chk 15bx-good-scene-pass ok;; *) chk 15bx-good-scene-pass bad "$r";; esac
tr "\\\\" "/" < "$STUB_LOG" | grep -q -- "--out $T/e15a/X1 $T/e15a/X2 $T/e15a/X3 --inrange $T/e15a/P1 $T/e15a/P2 $T/e15a/P3 --asleep $T/e15a/S1 --fighters Vren,Dalla,Hungry --starter Vren" && chk 15bx-assert-argv ok || chk 15bx-assert-argv bad "$(cat "$STUB_LOG" 2>&1)"
mk15 "$T/e15b" 300 10 60 "Malzin,Vren,Dalla" Vren; r=$(c15 "$T/e15b"); case "$r" in "RESULT 15-bx SETUP-FAIL"*Malzin*) chk 15bx-malzin-in-roster-setupfail ok;; *) chk 15bx-malzin-in-roster-setupfail bad "$r";; esac
mk15 "$T/e15c" 218; r=$(c15 "$T/e15c"); case "$r" in "RESULT 15-bx SETUP-FAIL"*"X1 distance"*) chk 15bx-x-too-close-setupfail ok;; *) chk 15bx-x-too-close-setupfail bad "$r";; esac
mk15 "$T/e15d" 300 10 5267; r=$(c15 "$T/e15d"); case "$r" in "RESULT 15-bx SETUP-FAIL"*"S1 distance"*) chk 15bx-sleeper-far-setupfail ok;; *) chk 15bx-sleeper-far-setupfail bad "$r";; esac
mk15 "$T/e15e" 300 31; r=$(c15 "$T/e15e"); case "$r" in "RESULT 15-bx SETUP-FAIL"*"P1 distance"*) chk 15bx-p-far-setupfail ok;; *) chk 15bx-p-far-setupfail bad "$r";; esac
mk15 "$T/e15f" 300 10 60 "Vren,Dalla" "Ukil"; r=$(c15 "$T/e15f"); case "$r" in "RESULT 15-bx SETUP-FAIL"*Ukil*) chk 15bx-foreign-starter-setupfail ok;; *) chk 15bx-foreign-starter-setupfail bad "$r";; esac
mk15 "$T/e15g" 300 10 60 Vren Vren; r=$(c15 "$T/e15g"); case "$r" in "RESULT 15-bx SETUP-FAIL"*"<2 names"*) chk 15bx-one-fighter-setupfail ok;; *) chk 15bx-one-fighter-setupfail bad "$r";; esac
mk15 "$T/e15h" 300 10 60 "Vren,Dalla" Vren yes; r=$(STUB_KIND=FAIL c15 "$T/e15h"); case "$r" in "RESULT 15-bx FAIL"*"SERVER X combat lines"*"[1, 0, 0]"*"witnesses > 277 u"*) chk 15bx-clean-scene-fail-names-server ok;; *) chk 15bx-clean-scene-fail-names-server bad "$r";; esac
mk15 "$T/e15i"; rm -rf "$T/e15i/P2"; r=$(c15 "$T/e15i"); case "$r" in "RESULT 15-bx SETUP-FAIL"*"missing"*P2*) chk 15bx-missing-bundle-setupfail ok;; *) chk 15bx-missing-bundle-setupfail bad "$r";; esac

# ---- 3. checker: 20-a (stock rowcheck.py replaced by a stub whose verdict is STUB_KIND)
printf '%s\n' 'import os, sys' "print('RESULT 20-a %s stub-evidence' % os.environ.get('STUB_KIND', 'PASS'))" > "$T/stubs/rowcheck20a.py"; export UB_ROWCHECK="$T/stubs/rowcheck20a.py"
mk20() {  # mk20 <dir> [combat yes|no] [reaction text]
  local d="$1"; rm -rf "$d"; mkdir -p "$d/s4" "$d/s4b"
  for t in pre s3 s4 s4b; do echo "STATE {\"in_combat\":$([ "${2:-no}" = yes ] && [ $t = s4 ] && echo true || echo false)}" > "$d/calm_$t.txt"; done
  echo "ACTION_EXEC: SAY [Cind]: ${3:-Sure, the Stumble Inn it is.} (NPC)" > "$d/s4/reply.txt"; echo "ACTION_EXEC: SAY [Cind]: Fine. (NPC)" > "$d/s4b/reply.txt"
}
c20() { "$PYB" "$C" 20-a "$1" 2>/dev/null | head -1; }
mk20 "$T/e20a"; r=$(STUB_KIND=PASS c20 "$T/e20a"); case "$r" in "RESULT 20-a PASS"*"Shay sheathed, not in combat"*) chk 20a-pass-calm ok;; *) chk 20a-pass-calm bad "$r";; esac
mk20 "$T/e20b" no "You already swung at me once today."; r=$(STUB_KIND=FAIL c20 "$T/e20b"); case "$r" in "RESULT 20-a SETUP-FAIL"*"drawn-weapon reaction"*"already swung"*) chk 20a-drawn-reaction-setupfail ok;; *) chk 20a-drawn-reaction-setupfail bad "$r";; esac
mk20 "$T/e20c" yes; r=$(STUB_KIND=FAIL c20 "$T/e20c"); case "$r" in "RESULT 20-a SETUP-FAIL"*"in_combat at s4"*) chk 20a-combat-setupfail ok;; *) chk 20a-combat-setupfail bad "$r";; esac
mk20 "$T/e20d"; r=$(STUB_KIND=FAIL c20 "$T/e20d"); case "$r" in "RESULT 20-a FAIL"*) chk 20a-calm-fail-passes-through ok;; *) chk 20a-calm-fail-passes-through bad "$r";; esac
mk20 "$T/e20e" no "You already swung at me once today."; r=$(STUB_KIND=PASS c20 "$T/e20e"); case "$r" in "RESULT 20-a PASS"*) chk 20a-pass-never-downgraded ok;; *) chk 20a-pass-never-downgraded bad "$r";; esac

# ---- 4. checker: 10-b
mk10() {  # mk10 <dir> <effects (\n separated)> <inbox line> <aff> [transfer_log]
  local d="$1"; rm -rf "$d"; mkdir -p "$d"; echo "Cind [Hungry Bandit]" > "$d/victim.txt"; echo Bandages > "$d/gift.txt"
  printf '%b' "$2" > "$d/effects_c.txt"; printf '%b' "$3" > "$d/inbox_transfer.txt"; echo "{\"before\":{\"Shay\":{\"aff\":0}},\"after\":{\"Shay\":{\"aff\":$4}}}" > "$d/aff_end.txt"
  echo "${5-SOCIAL_CAPTURE kind=item_transfer actor=#1(Cind) target=#2(Shay) verified:true}" > "$d/transfer_log.txt"
}
HARM='aggression|-46|Cind|Shay|100\n'; APO='apology_relief|2|Cind|Shay|110\n'; GIFT='gift|3|Cind|Shay|120\n'
INB_OK='Cind|f|Shay|t|{}|{}|{"Bandages":1}\n'
c10() { "$PYB" "$C" 10-b "$1" 2>/dev/null | head -1; }
mk10 "$T/e10a" "$HARM$APO$GIFT" "$INB_OK" -30; r=$(c10 "$T/e10a"); case "$r" in "RESULT 10-b PASS"*"repair=5"*"cap=10.5"*) chk 10b-pass ok;; *) chk 10b-pass bad "$r";; esac
mk10 "$T/e10b" "$HARM$APO" 'Malzin|t|Shay|t|{}|{}|{"Dried Meat":1}\n' -30; r=$(c10 "$T/e10b"); case "$r" in "RESULT 10-b SETUP-FAIL"*"exempt by design"*) chk 10b-squad-gift-setupfail ok;; *) chk 10b-squad-gift-setupfail bad "$r";; esac
mk10 "$T/e10c" "$HARM$APO" 'Cind|f|Shay|t|{"Dried Meat":1}|{}|{"Dried Meat":1}\n' -30; r=$(c10 "$T/e10c"); case "$r" in "RESULT 10-b SETUP-FAIL"*FOOD*) chk 10b-food-gift-setupfail ok;; *) chk 10b-food-gift-setupfail bad "$r";; esac
mk10 "$T/e10d" "$HARM$APO" '' -30 ''; r=$(c10 "$T/e10d"); case "$r" in "RESULT 10-b SETUP-FAIL"*"no item_transfer capture"*) chk 10b-not-captured-setupfail ok;; *) chk 10b-not-captured-setupfail bad "$r";; esac
mk10 "$T/e10e" "$HARM$APO" "$INB_OK" -30; r=$(c10 "$T/e10e"); case "$r" in "RESULT 10-b FAIL"*gift_row_present*) chk 10b-clean-transfer-no-gift-fail ok;; *) chk 10b-clean-transfer-no-gift-fail bad "$r";; esac
mk10 "$T/e10f" "$HARM$APO"'gift|12|Cind|Shay|120\n' "$INB_OK" -30; r=$(c10 "$T/e10f"); case "$r" in "RESULT 10-b FAIL"*"repair_sum<=25%harm-1"*"repair=14"*) chk 10b-cap-exceeded-fail ok;; *) chk 10b-cap-exceeded-fail bad "$r";; esac
mk10 "$T/e10g" "$HARM$APO$GIFT" "$INB_OK" 12; r=$(c10 "$T/e10g"); case "$r" in "RESULT 10-b FAIL"*affinity_still_negative*) chk 10b-affinity-positive-fail ok;; *) chk 10b-affinity-positive-fail bad "$r";; esac
mk10 "$T/e10h" "$HARM$APO$APO$GIFT" "$INB_OK" -30; r=$(c10 "$T/e10h"); case "$r" in "RESULT 10-b SETUP-FAIL"*"2 apology_relief rows"*) chk 10b-two-apologies-setupfail ok;; *) chk 10b-two-apologies-setupfail bad "$r";; esac
mk10 "$T/e10i" "$APO$GIFT" "$INB_OK" -30; r=$(c10 "$T/e10i"); case "$r" in "RESULT 10-b SETUP-FAIL"*"no harm row"*) chk 10b-no-harm-setupfail ok;; *) chk 10b-no-harm-setupfail bad "$r";; esac
mk10 "$T/e10j" "$HARM$APO"'apology_relief|9|Cind|Shay|1\n'"$GIFT" "$INB_OK" -30; r=$(c10 "$T/e10j"); case "$r" in "RESULT 10-b SETUP-FAIL"*) chk 10b-apology-count-guard ok;; *) chk 10b-apology-count-guard bad "$r";; esac
mk10 "$T/e10k" "${HARM}apology_relief|5|Cind|Shay|110\n$GIFT" "$INB_OK" -30; r=$(c10 "$T/e10k"); case "$r" in "RESULT 10-b FAIL"*"apology_relief<=2"*) chk 10b-apology-over-2-fail ok;; *) chk 10b-apology-over-2-fail bad "$r";; esac

# ---- 5. runner as a separate process (dry): command sequences, one RESULT line, shim, unknown row
dry() { ( export KAH_ROW_DRY=1 KAH_ROW_FAKE_LOG="$T/fake-$1.log"; : > "$T/fake-$1.log"; bash "$U" "$@" 2>/dev/null ); }
r=$(dry 15-bx 4080-i4); echo "$r" | grep -q '^RESULT 15-bx DRY-RUN' && [ "$(echo "$r" | grep -c '^RESULT')" = 1 ] && chk dry-15bx-one-line ok || chk dry-15bx-one-line bad "$r"
L="$T/fake-15-bx.log"
grep -q "delete from eventlog where type in ('combat','combat_start','combat_end')" "$L" && chk 15bx-old-fights-deleted ok || chk 15bx-old-fights-deleted bad
grep -q 'stobe-auto teleport Malzin' "$L" && chk 15bx-malzin-sent-away ok || chk 15bx-malzin-sent-away bad
[ "$(grep -c 'stobe-auto fight' "$L")" -ge 2 ] && ! grep -q 'fight Malzin' "$L" && chk 15bx-fight-is-two-spawns ok || chk 15bx-fight-is-two-spawns bad
grep -q 'stobe-auto sleep ' "$L" && grep -q 'dist 60' "$L" && grep -q 'dist 10' "$L" && chk 15bx-sleeper-and-p-placement ok || chk 15bx-sleeper-and-p-placement bad
[ "$(grep -c 'stobe_say' "$L")" = 7 ] && chk 15bx-seven-samples ok || chk 15bx-seven-samples bad "say count $(grep -c 'stobe_say' "$L")"
[ "$(grep -c 'kah-imm26-4080-i4h' "$L")" = 0 ] && ! grep -q 'load kah-imm26' "$L" || true
EV15="$KAH_ROWS_BASE/imm26-4080-i4/rows/15-bx"
for d in X1 X2 X3 P1 P2 P3 S1; do [ -d "$EV15/$d" ] || { chk 15bx-bundle-dirs bad "missing $d"; d=""; break; }; done; [ -n "$d" ] && chk 15bx-bundle-dirs ok
[ -s "$EV15/shout_radius.txt" ] && ! grep -qi shout "$EV15/X1/distance.txt" && chk 15bx-shout-not-in-distance ok || chk 15bx-shout-not-in-distance bad
r=$(dry 20-a 4080-i4); echo "$r" | grep -q '^RESULT 20-a DRY-RUN' && chk dry-20a-one-line ok || chk dry-20a-one-line bad "$r"
L="$T/fake-20-a.log"; EV20="$KAH_ROWS_BASE/imm26-4080-i4/rows/20-a"
[ "$(grep -c 'stobe_drawn hold Shay off' "$L")" -ge 4 ] && [ "$(grep -c 'stobe_drawn sheathe Shay' "$L")" -ge 4 ] && chk 20a-sheathed-before-every-turn ok || chk 20a-sheathed-before-every-turn bad "hold=$(grep -c 'hold Shay off' "$L")"
[ -f "$EV20/calm_pre.txt" ] && [ -f "$EV20/calm_s3.txt" ] && [ -f "$EV20/calm_s4.txt" ] && [ -f "$EV20/calm_s4b.txt" ] && chk 20a-calm-files ok || chk 20a-calm-files bad
grep -q 'Actually, go to' "$L" && grep -q 'Yes, I mean it' "$L" && grep -q 'Yes. Take me to' "$L" && chk 20a-two-confirm-turns ok || chk 20a-two-confirm-turns bad
r=$(dry 10-b 4080-i4); echo "$r" | grep -q '^RESULT 10-b DRY-RUN' && chk dry-10b-one-line ok || chk dry-10b-one-line bad "$r"
L="$T/fake-10-b.log"; EV10="$KAH_ROWS_BASE/imm26-4080-i4/rows/10-b"
grep -q 'stobe-auto protect .* off' "$L" && grep -q 'stobe-auto hit Shay' "$L" && grep -q 'head 130' "$L" && chk 10b-harm-recipe ok || chk 10b-harm-recipe bad
grep -q 'stobe-auto transfer Shay' "$L" && grep -q 'stobe-auto give Shay' "$L" && chk 10b-give-then-transfer-shay-to-victim ok || chk 10b-give-then-transfer-shay-to-victim bad
grep -q "sorry I knocked you out" "$L" && chk 10b-apology-wording ok || chk 10b-apology-wording bad
grep -q "from social_effect where game_ts" "$L" && [ -f "$EV10/effects_c.txt" ] && [ -f "$EV10/victim.txt" ] && chk 10b-evidence-files ok || chk 10b-evidence-files bad
grep -q "social_event_inbox" "$L" && chk 10b-inbox-classifier-query ok || chk 10b-inbox-classifier-query bad
r=$(KAH_ROW_DRY=1 KAH_ROW_FAKE_LOG="$T/fake-v.log" bash "$U" 10-b 4080-i4 --dry --victim Malzin 2>/dev/null); grep -q "stobe-auto where 'Malzin'" "$T/fake-v.log" && chk 10b-victim-option ok || chk 10b-victim-option bad "$(grep -m1 'where' "$T/fake-v.log")"
r=$(bash "$U" 99-z 4080-i4 2>/dev/null); rc=$?; [ "$rc" = 2 ] && echo "$r" | grep -q '^RESULT 99-z SETUP-FAIL' && chk unknown-row-setupfail ok || chk unknown-row-setupfail bad "rc=$rc $r"
r=$(bash "$U" 15-bx nolane 2>/dev/null); [ "$(echo "$r" | wc -l)" = 1 ] && echo "$r" | grep -q 'SETUP-FAIL' && chk unknown-lane-setupfail ok || chk unknown-lane-setupfail bad "$r"
r=$(UC_LOADED=1 bash "$U" -c 'print(40+2)' 2>&1); [ "$r" = 42 ] && chk shim-passes-python ok || chk shim-passes-python bad "$r"
mkdir -p "$T/e10s"; r=$(UC_LOADED=1 bash "$U" /x/rowtools/rowcheck.py 10-b "$T/e10s" 2>/dev/null | head -1); case "$r" in "RESULT 10-b SETUP-FAIL"*) chk shim-routes-10b-to-checker ok;; *) chk shim-routes-10b-to-checker bad "$r";; esac

# ---- 6. library mode: sourced after go-row.sh + hxdefs.sh the rows are redefined and nothing runs
r=$(bash -c ". '$A/go-row.sh'; . '$ST_HERE/hxdefs.sh'; before=\$(declare -f rd_15bx | grep -c ub15_pair); . '$U'; echo \"\$before \$(declare -f rd_15bx | grep -c ub15_pair) \$(declare -f rd_20a | grep -c ub20_calm) \$(declare -f rd_10b | grep -c ub10_gift_pick)\"" 2>&1 | tail -1)
[ "${r%% *}" = 0 ] && [ "$(echo "$r" | awk '{print ($2>0 && $3>0 && $4>0)}')" = 1 ] && chk library-mode-redefines-rows ok || chk library-mode-redefines-rows bad "$r"
# ---- 7. the live-operator files are not touched by this tool
git -C "$A/../../.." diff --quiet -- testing/live-stobe-queue/imm26-assert/rowtools/rowdefs.sh testing/live-stobe-queue/imm26-assert/rowtools/tripdefs.sh 2>/dev/null && chk rowdefs-tripdefs-untouched ok || chk rowdefs-tripdefs-untouched bad "modified"

rm -rf "$T"
if [ "$ok" = "$n" ]; then echo "SELFTEST UNBLOCK-C ALL PASS $ok/$n"; exit 0; else echo "SELFTEST UNBLOCK-C ALL FAIL $ok/$n"; exit 1; fi
