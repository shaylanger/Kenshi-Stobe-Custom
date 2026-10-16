#!/usr/bin/env bash
# unblock_e_selftest.sh: OFFLINE self-test of unblockdefs_e.sh / unblockcheck_e.py (row 10-b, imm26-sfD2). No game, ssh or DB: dry-run transcripts + synthetic evidence dirs.
# Prints `SELFTEST unblockE-<name> PASS|FAIL` and `SELFTEST UNBLOCK-E ALL PASS|FAIL n/m`.  Usage: bash rowtools/unblock_e_selftest.sh   (WSL python3 is faster)
ST_HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; A="$ST_HERE/.."
PYB=$(command -v python3 || command -v python)
T=$(mktemp -d); export KAH_ROWS_BASE="$T/runs" KAH_ROW_FAKE_LOG="$T/fake.log" KAH_PF_ISOLATION=0 KAH_PF_LLM=0 ROW_SETTLE=0 ROW_WAIT=1
unset KAH_AGENT_NAME KAH_ROW_DRY HX_OUT HX_SAVE HX_SAVE2 HX_PRELOADED UC_LOADED UB_VICTIM UB_GIFT
mkdir -p "$KAH_ROWS_BASE"
n=0; ok=0
chk() { n=$((n+1)); if [ "$2" = ok ]; then ok=$((ok+1)); echo "SELFTEST unblockE-$1 PASS ${3:-}"; else echo "SELFTEST unblockE-$1 FAIL ${3:-}"; fi; }
U="$ST_HERE/unblockdefs_e.sh"; C="$ST_HERE/unblockcheck_e.py"

# ---- 1. syntax
bash -n "$U" && chk bash-n ok || chk bash-n bad
"$PYB" -m py_compile "$C" && chk py-compile ok || chk py-compile bad
[ -x "$U" ] && chk defs-executable ok || chk defs-executable bad "chmod +x"
"$PYB" "$C" --has 10-b && ! "$PYB" "$C" --has 15-bx && chk checker-has ok || chk checker-has bad

# ---- 2. checker
mk10() {  # mk10 <dir> <effects> <inbox> <aff> [interp] [judged]
  local d="$1"; rm -rf "$d"; mkdir -p "$d"; echo "Cind [Hungry Bandit]" > "$d/victim.txt"; echo "Iron Plates" > "$d/gift.txt"
  printf '%b' "$2" > "$d/effects_c.txt"; printf '%b' "$3" > "$d/inbox_transfer.txt"; echo "{\"before\":{\"Shay\":{\"aff\":0}},\"after\":{\"Shay\":{\"aff\":$4}}}" > "$d/aff_end.txt"
  echo "SOCIAL_CAPTURE kind=item_transfer actor=#1(Cind) target=#2(Shay) verified:true" > "$d/transfer_log.txt"
  printf '%s\n' "${5-}" > "$d/interp.txt"; printf '%s\n' "${6-}" > "$d/judged.txt"
}
HARM='aggression|-24|Cind|Shay|100\n'; APO='apology_relief|2|Cind|Shay|110\n'; GIFT='gift|3|Cind|Shay|120\n'
# newest inbox row is the unrelated bread transfer (the sfD defect); the Iron Plates row is older
INB='Shay|true|Cind|false|{"bread": 1}||{"bread": 1}\nCind|false|Shay|true|{}|{}|{"Iron Plates": 1}\n'
INB_FOOD='Cind|false|Shay|true|{"Iron Plates": 1}|{}|{"Iron Plates": 1}\n'
c10() { "$PYB" "$C" 10-b "$1" 2>/dev/null | head -1; }
mk10 "$T/e1" "$HARM$APO$GIFT" "$INB" -30; r=$(c10 "$T/e1"); case "$r" in "RESULT 10-b PASS"*) chk pass ok;; *) chk pass bad "$r";; esac
mk10 "$T/e2" "$HARM$APO" "$INB" -30 '' 'SOCIAL_INTERPRET kind=item_transfer seq=1737 game_ts=1 results=[{"status":"deal_payment"}]'
r=$(c10 "$T/e2"); case "$r" in "RESULT 10-b SETUP-FAIL"*"deal_payment"*inDeal*) chk deal-payment-setupfail-names-inDeal ok;; *) chk deal-payment-setupfail-names-inDeal bad "$r";; esac
case "$r" in *FOOD*) chk newest-bread-row-not-misread-as-food bad "$r";; *) chk newest-bread-row-not-misread-as-food ok;; esac
mk10 "$T/e3" "$APO$GIFT" "$INB" -30 'SOCIAL_INTERPRET kind=harm seq=1433 results=[{"status":"no_encounter"}]'
r=$(c10 "$T/e3"); case "$r" in "RESULT 10-b SETUP-FAIL"*"no harm row"*no_encounter*) chk no-encounter-setupfail ok;; *) chk no-encounter-setupfail bad "$r";; esac
mk10 "$T/e4" "$HARM$APO" "$INB_FOOD" -30; r=$(c10 "$T/e4"); case "$r" in "RESULT 10-b SETUP-FAIL"*FOOD*) chk food-matching-gift-setupfail ok;; *) chk food-matching-gift-setupfail bad "$r";; esac
mk10 "$T/e5" "$HARM$APO" 'Malzin|true|Shay|true|{}|{}|{"Iron Plates": 1}\n' -30; r=$(c10 "$T/e5"); case "$r" in "RESULT 10-b SETUP-FAIL"*"exempt by design"*) chk squad-gift-setupfail ok;; *) chk squad-gift-setupfail bad "$r";; esac
mk10 "$T/e6" "$HARM$APO" "$INB" -30; r=$(c10 "$T/e6"); case "$r" in "RESULT 10-b FAIL"*gift_row_present*) chk clean-transfer-no-gift-fail ok;; *) chk clean-transfer-no-gift-fail bad "$r";; esac
mk10 "$T/e7" "$HARM$APO"'gift|12|Cind|Shay|120\n' "$INB" -30; r=$(c10 "$T/e7"); case "$r" in "RESULT 10-b FAIL"*"repair_sum<=25%harm-1"*) chk cap-exceeded-fail ok;; *) chk cap-exceeded-fail bad "$r";; esac
mk10 "$T/e8" "$HARM$APO$GIFT" "$INB" 12; r=$(c10 "$T/e8"); case "$r" in "RESULT 10-b FAIL"*affinity_still_negative*) chk affinity-positive-fail ok;; *) chk affinity-positive-fail bad "$r";; esac
mk10 "$T/e9" "$HARM$GIFT" "$INB" -30; r=$(c10 "$T/e9"); case "$r" in "RESULT 10-b SETUP-FAIL"*"0 apology_relief"*) chk no-apology-setupfail ok;; *) chk no-apology-setupfail bad "$r";; esac
r=$("$PYB" "$C" 15-bx "$T/e1" 2>&1 | head -1); case "$r" in usage*|"") chk other-rows-refused ok;; *) chk other-rows-refused bad "$r";; esac

# ---- 3. dry runner as a separate process: recipe statements
( export KAH_ROW_DRY=1; : > "$KAH_ROW_FAKE_LOG"; bash "$U" 10-b 4080-i4 --dry > "$T/dry.out" 2>/dev/null )
L="$KAH_ROW_FAKE_LOG"; EV="$KAH_ROWS_BASE/imm26-4080-i4/rows/10-b"
grep -q '^RESULT 10-b DRY-RUN' "$T/dry.out" && [ "$(grep -c '^RESULT' "$T/dry.out")" = 1 ] && chk dry-one-line ok || chk dry-one-line bad "$(cat "$T/dry.out")"
a=$(grep -n 'stobe-auto attack Shay' "$L" | head -1 | cut -d: -f1); h=$(grep -n 'stobe-auto hit Shay' "$L" | head -1 | cut -d: -f1)
[ -n "$a" ] && [ -n "$h" ] && [ "$a" -lt "$h" ] && chk attack-order-before-hits ok || chk attack-order-before-hits bad "attack@$a hit@$h"
[ "$(grep -c 'head 130' "$L")" = 2 ] && chk two-hits ok || chk two-hits bad "$(grep -c 'head 130' "$L")"
grep -q 'order Shay NULL_TASK' "$L" && grep -q 'relation .* 0 ' "$L" && grep -q 'protect .* on' "$L" && chk fight-end-commands ok || chk fight-end-commands bad
q=$(grep -n 'teleport Shay -48000 1500 2960' "$L" | head -1 | cut -d: -f1)
[ -n "$q" ] && [ "$q" -lt "$a" ] && chk scene-at-quiet-spot-before-attack ok || chk scene-at-quiet-spot-before-attack bad "quiet@$q attack@$a"
grep -q 'set resolved_at=updated_at where resolved_at is null' "$L" && grep -q "'CANCELLED'" "$L" && chk deal-resolved-at-workaround ok || chk deal-resolved-at-workaround bad
d=$(grep -n 'set resolved_at=updated_at' "$L" | head -1 | cut -d: -f1)
[ -n "$d" ] && [ "$d" -lt "$a" ] && chk workaround-before-gift-leg ok || chk workaround-before-gift-leg bad
grep -q 'SOCIAL_INTERPRET kind=(item_transfer)' "$L" && grep -q 'kind=(harm|attack)' "$L" && chk worker-evidence-queries ok || chk worker-evidence-queries bad
grep -q 'stobe-auto transfer Shay' "$L" && grep -q 'sorry I knocked you out' "$L" && chk gift-and-apology-kept ok || chk gift-and-apology-kept bad
for f in victim.txt effects_c.txt inbox_transfer.txt deal_before.txt deal_after.txt interp.txt judged.txt; do [ -f "$EV/$f" ] || { chk evidence-files bad "missing $f"; f=""; break; }; done; [ -n "$f" ] && chk evidence-files ok
r=$(bash "$U" 15-bx 4080-i4 2>/dev/null); [ "$?" = 2 ] && echo "$r" | grep -q 'SETUP-FAIL.*10-b only' && chk other-rows-refused-by-runner ok || chk other-rows-refused-by-runner bad "$r"
r=$(UC_LOADED=1 bash "$U" -c 'print(40+2)' 2>&1); [ "$r" = 42 ] && chk shim-passes-python ok || chk shim-passes-python bad "$r"
mkdir -p "$T/es"; r=$(UC_LOADED=1 bash "$U" /x/rowtools/rowcheck.py 10-b "$T/es" 2>/dev/null | head -1); case "$r" in "RESULT 10-b SETUP-FAIL"*) chk shim-routes-10b-to-e-checker ok;; *) chk shim-routes-10b-to-e-checker bad "$r";; esac

# ---- 4. library mode: rd_10b is OURS after sourcing, nothing runs
r=$(bash -c ". '$A/go-row.sh'; . '$ST_HERE/hxdefs.sh'; . '$U'; declare -F rd_10b >/dev/null && declare -f rd_10b | grep -c 'attack Shay'" 2>&1 | tail -1)
[ "$r" -ge 1 ] 2>/dev/null && chk library-mode-redefines-rd_10b ok || chk library-mode-redefines-rd_10b bad "$r"
# ---- 5. the c files are untouched by this tool
git -C "$A/../../.." diff --quiet -- testing/live-stobe-queue/imm26-assert/rowtools/unblockdefs_c.sh testing/live-stobe-queue/imm26-assert/rowtools/unblockcheck_c.py 2>/dev/null && chk c-files-untouched ok || chk c-files-untouched bad "modified"

rm -rf "$T"
if [ "$ok" = "$n" ]; then echo "SELFTEST UNBLOCK-E ALL PASS $ok/$n"; exit 0; else echo "SELFTEST UNBLOCK-E ALL FAIL $ok/$n"; exit 1; fi
