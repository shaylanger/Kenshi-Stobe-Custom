#!/bin/bash
# live-tune.sh <out dir> <name> [spec file] [budget 30] [stroke 1]   (WSL or 4080 Git Bash; stobe-auto on PATH; Kenshi running)
# Closed-loop pose tuning INSIDE the running game (live-tune agent, 2026-10-11; the offline lab disagrees with the game by
# 3-5 dm on the sword forearm). One launch, dozens of candidates, no video:
#   per candidate (live_tune.py proposes it: CMA-ES / Nelder-Mead from harness optim.py, early stop at score 0):
#   fp_tables load <variant> -> holster + draw (R, key_inject, isolation on) -> forced stroke <stroke> swung SWINGS times
#   (fp_keys press lmb) -> fp_vm rec dump -> score the GAME recording with the lab code (S1 edge-to-camera, PT30-FLIP
#   elbow jumps + vmcheck flags, wrist bend, stroke-start roll step, edge-arc share, animlab inline/metrics/churn/blade).
# Setup = fp-e6-strokes.sh (fresh fixture load, day, open spot, katana, crossbow quarantine: NO crossbow anywhere).
# Output in <out dir>: score-log.tsv, cand-*.txt (variant files), result.json, winner.txt (full variant),
#   winner-values.txt (tuned values only), winner-dump.txt (fp_tables dump diff of the winner in game), recs/;
#   C:\KenshiTestRuns\tables\live-<name>.txt = winner-values; LT_INSTALL=1 (default) also writes it to the rig's
#   <KenshiFP dll folder>\fp_tables.txt when the winner's worst-case score beats the base AND is 0 (every gate passes);
#   else the game's tables are reset. Last line: RESULT LIVETUNE-<name> PASS|FAIL <evidence>
#   (PASS = a winner with score 0 found and confirmed; FAIL = best found is still > 0, values + parts in the line).
# Spec (live_tune.py header): "<lhs> [step|auto] [lo|auto] [hi|auto]" per line; default: $HERE/live-tune-sword-s1.spec
# env: LT_CYCLES (draw+swings per candidate, 1), LT_SWINGS (2), LT_METHOD (cma), LT_INSTALL (1), KDIR, CR, RIG
# Internal modes (called by live_tune.py): --get <table> [key] | --eval <variant file> <id> [cycles]
# dryrun: norec   (no video by design: the game recording is the evidence)
HERE=${CR:-/mnt/c}/KenshiModding/components/KenshiFP/tests/ingame
[ -d "$HERE" ] || HERE=$(cd "$(dirname "$0")" && pwd)
KDIR=${KDIR:-/mnt/d/Steam/steamapps/common/Kenshi}
A(){ stobe-auto "$@" </dev/null 2>&1; }
fld(){ grep -o " $1=[^ ]*" | head -1 | cut -d= -f2; }
st(){ A fp_vm state | fld state; }
waitst(){ local e=$((SECONDS+$2)); while [ $SECONDS -lt $e ]; do [ "$(st)" = "$1" ] && return 0; sleep 0.2; done; return 1; }
# Windows path for the game; python path (Windows python on the 4080 wants C:/..)
winp(){ case "$1" in /mnt/[a-zA-Z]/*) local d=${1:5:1}; echo "${d^^}:/${1:7}";; /[a-zA-Z]/*) local d=${1:1:1}; echo "${d^^}:/${1:3}";;
  *) if command -v wslpath >/dev/null 2>&1; then wslpath -m "$1"; elif command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else echo "$1"; fi;; esac; }
pyp(){ if [ -d /mnt/c ]; then echo "$1"; else winp "$1"; fi; }
unp(){ case "$1" in [A-Za-z]:[/\\]*) local d=${1:0:1} r=${1:3}; r=${r//\\//}; if [ -d /mnt/c ]; then echo "/mnt/${d,,}/$r"; else echo "/${d,,}/$r"; fi;; *) echo "$1";; esac; }

# ---------------- internal: one value
if [ "$1" = --get ]; then shift; A fp_tables get "$@"; exit 0; fi
# ---------------- internal: one candidate
if [ "$1" = --eval ]; then
  VF=$(unp "$2"); ID=$3; CY=${4:-${LT_CYCLES:-1}}; SWN=${LT_SWINGS:-2}; STK=${LT_STROKE:-1}; RD=$(dirname "$VF")/recs; mkdir -p "$RD"
  r=$(A fp_tables load "$(winp "$VF")"); h=$(grep -o 'hash=[0-9a-f]*' <<<"$r" | head -1 | cut -d= -f2)
  [ -n "$h" ] && grep -q ' bad=0' <<<"$r" || { echo "EVAL FAIL load: $(tr '\n' ' ' <<<"$r" | cut -c1-160)"; exit 1; }
  cl=$(A fp_vm state | grep -o "class=[a-z0-9]*" | head -1); case "$cl" in *xbow*|*ranged*|*bow*) echo "EVAL FAIL crash-safety: drawn class $cl"; exit 1;; esac
  A fp_vm set strokes 15 >/dev/null; A fp_vm set stroke "$STK" >/dev/null
  rm -f "$KDIR/vmrec-lt-$ID.txt"; A fp_vm rec on >/dev/null
  for c in $(seq 1 "$CY"); do
    [ "$(st)" = ready ] && { A key_inject r tap 120 >/dev/null; waitst holstered 6 || { echo "EVAL FAIL no holster (state=$(st))"; A fp_vm rec off >/dev/null; exit 1; }; }
    A key_inject r tap 120 >/dev/null; waitst ready 6 || { echo "EVAL FAIL no draw (state=$(st))"; A fp_vm rec off >/dev/null; exit 1; }
    sleep 0.4
    for s in $(seq 1 "$SWN"); do A fp_keys press lmb 60 >/dev/null; sleep 2.4; done
  done
  A fp_vm rec off >/dev/null; A fp_vm rec dump "vmrec-lt-$ID.txt" >/dev/null
  for i in 1 2 3 4 5 6 7 8 9 10; do [ -s "$KDIR/vmrec-lt-$ID.txt" ] && break; sleep 0.5; done; sleep 0.5
  cp "$KDIR/vmrec-lt-$ID.txt" "$RD/$ID.txt" 2>/dev/null && rm -f "$KDIR/vmrec-lt-$ID.txt" || { echo "EVAL FAIL no rec dump $KDIR/vmrec-lt-$ID.txt"; exit 1; }
  echo "EVAL OK hash=$h rec=$(pyp "$RD/$ID.txt")"; exit 0
fi

# ---------------- main
OUT=$1; N=$2; SPEC=${3:-$HERE/live-tune-sword-s1.spec}; BUD=${4:-30}; export LT_STROKE=${5:-1}
[ -n "$OUT" ] && [ -n "$N" ] || { echo "usage: live-tune.sh <out dir> <name> [spec] [budget] [stroke]"; exit 2; }
case "$BUD$LT_STROKE" in *[!0-9]*) echo "RESULT LIVETUNE-$N FAIL setup: budget/stroke not numbers ($BUD $LT_STROKE)"; exit 2;; esac
export KAH_OWNER=${KAH_OWNER:-live-tune}
mkdir -p "$OUT" 2>/dev/null; cd "$OUT" 2>/dev/null || { echo "RESULT LIVETUNE-$N FAIL setup: out dir $OUT not usable"; exit 2; }
OUT=$(pwd)
[ -r "$SPEC" ] || { echo "RESULT LIVETUNE-$N FAIL setup: no spec $SPEC"; exit 2; }
SH=Axima; SPOT="-54190 633 4380"
HARN=${CR:-/mnt/c}/KenshiModding/Kenshi-Automation-Harness; L=$HARN/tools/animlab
PYX=python3; command -v python3 >/dev/null 2>&1 || PYX=python
fail(){ PF_DONE=1; echo "RESULT LIVETUNE-$N FAIL $*"; A fp_vm set stroke -1 >/dev/null; A fp_vm set strokes 1 >/dev/null; A fp_tables reset >/dev/null; A chatter on >/dev/null; exit 1; }
PF_ROW=LIVETUNE-$N; PF_ON_FAIL='A fp_vm set stroke -1 >/dev/null; A fp_vm set strokes 1 >/dev/null; A fp_tables reset >/dev/null'
. "$HERE/take-preflight.sh"
pf_begin "$PF_ROW"
# private copies (an edit of a source script during the run cannot break it)
cp "$HERE/live_tune.py" "$OUT/.live_tune.py"; cp "$SPEC" "$OUT/spec.txt"; cp "$0" "$OUT/.live-tune.sh" 2>/dev/null || cp "$HERE/live-tune.sh" "$OUT/.live-tune.sh"
awk '/^cat > "\$OUT\/vmcheck.py" <<.VMCHECK.$/{f=1;next} /^VMCHECK$/{f=0} f' "$HERE/fp-viewmodel.sh" > "$OUT/.vmcheck.py"
[ -s "$OUT/.vmcheck.py" ] || fail "setup: vmcheck.py not found in fp-viewmodel.sh"
# ---- setup (fp-e6-strokes.sh): fresh load, pins, daytime, take spot, katana, crossbow quarantine
pf_load
A speed 1 hold >/dev/null; A kill "Hungry Bandit" >/dev/null; A chatter off >/dev/null
A fp_tables state | grep -q 'hash=' || fail "setup: fp_tables missing (KenshiFP build without kfp-live-tables): $(A fp_tables state | cut -c1-80)"
A pin Malzin at -53900 633 6850 >/dev/null; A pin Tassilo at -53940 640 6850 >/dev/null; A pin Shay at -53980 640 6850 >/dev/null
A select $SH >/dev/null; A fp_control take >/dev/null
pf_rig; pf_display
pf_clean -54190 4380 6000
pf_day
A teleport $SH $SPOT >/dev/null; sleep 2
for c in $SH Malzin; do A health $c 100 >/dev/null; done
A fp_combat physical >/dev/null; A fp_combat on >/dev/null; A combatmode $SH ranged off >/dev/null
A inv $SH | grep -q '"name":"Chisa Katana"' || { A unequip Malzin "Chisa Katana" >/dev/null; A transfer Malzin $SH "Chisa Katana" >/dev/null; A pickup $SH "Chisa Katana" radius 80 >/dev/null; }
A equip $SH "Chisa Katana" >/dev/null; sleep 1
# crash safety (2026-10-11 BSOD: every TDR was on a crossbow shot/reload frame): no crossbow equipped on anyone in the scene
for c in $SH Malzin Tassilo Shay; do A inv $c | grep -o '"name":"[^"]*"' | cut -d'"' -f4 | grep -iE 'bow|toothpick|harpoon|eagle' | sort -u | while read -r b; do A unequip $c "$b" >/dev/null; done; done; sleep 1
for c in $SH Malzin Tassilo Shay; do A inv $c | grep -o '"name":"[^"]*","equipped":true' | grep -iqE 'bow|toothpick|harpoon|eagle' && fail "setup: crossbow still equipped on $c (crash-safety quarantine)"; done
A fp_camera distance 0 >/dev/null; A fp_camera orbit 0 >/dev/null; A fp_camera look 3.14 0.05 >/dev/null; pf_iso
[ "$(st)" = ready ] || { [ "$(st)" = holstered ] || { A key_inject r tap 120 >/dev/null; waitst holstered 6; }; A key_inject r tap 120 >/dev/null; waitst ready 6; }
[ "$(st)" = ready ] || fail "setup: katana not ready (state=$(st))"
cl_=$(A fp_vm state | grep -o "class=[a-z0-9]*" | head -1); case "$cl_" in *xbow*|*ranged*|*bow*) A key_inject r tap 120 >/dev/null; fail "setup: drawn weapon $cl_ (crash-safety: sword only)";; esac
pf_nofight
# ---- base = the game's tables now (non-default values kept under every candidate)
A fp_tables dump "$(winp "$OUT/base-diff.txt")" diff >/dev/null; sleep 1
B0=$(A fp_tables state | grep -o 'hash=[0-9a-f]*' | head -1); echo "note: base tables $B0 class=$cl_"
# ---- tune (python drives the game through --eval of the private script copy)
BASHX=$(command -v bash); [ -d /mnt/c ] || BASHX=$(cygpath -m "$BASHX" 2>/dev/null || echo "$BASHX")
"$PYX" -I "$(pyp "$OUT/.live_tune.py")" tune --out "$(pyp "$OUT")" --spec "$(pyp "$OUT/spec.txt")" --stroke "$LT_STROKE" --budget "$BUD" \
  --method "${LT_METHOD:-cma}" --tools "$(pyp "$L")" --vmcheck "$(pyp "$OUT/.vmcheck.py")" --row "LIVETUNE-$N" \
  --eval-cmd "\"$BASHX\" \"$(pyp "$OUT/.live-tune.sh")\"" 2>&1 | tee "$OUT/tune.log" | grep -E '^(EVAL|TUNE|ABORT|Traceback|[A-Za-z]*Error)'
TL=$(grep -E '^(TUNE|ABORT)' "$OUT/tune.log" | tail -1)
case "$TL" in ABORT*) fail "${TL#ABORT LIVETUNE-$N }";; TUNE*) ;; *) fail "driver: $(tail -2 "$OUT/tune.log" | tr '\n' ' ' | cut -c1-200)";; esac
[ -s "$OUT/winner.txt" ] || fail "no winner (every evaluation missed: $TL)"
# ---- winner: dump in game, publish, install if it passes everything
r=$(A fp_tables load "$(winp "$OUT/winner.txt")"); WH=$(grep -o 'hash=[0-9a-f]*' <<<"$r" | head -1 | cut -d= -f2)
A fp_tables dump "$(winp "$OUT/winner-dump.txt")" diff >/dev/null
read -r WS BS <<<"$("$PYX" -I -c 'import json,sys; r=json.load(open(sys.argv[1])); print(r.get("win_score",1e9), r["base_score"])' "$(pyp "$OUT/result.json")")"
TD=${CR:-/mnt/c}/KenshiTestRuns/tables; mkdir -p "$TD"; cp "$OUT/winner-values.txt" "$TD/live-$N.txt"
INST=no
if [ "${LT_INSTALL:-1}" = 1 ] && awk -v w="$WS" -v b="$BS" 'BEGIN{exit !(w==0 && w<b)}'; then
  if cp "$OUT/winner-values.txt" "$KDIR/mods/KenshiFP/fp_tables.txt"; then INST="$KDIR/mods/KenshiFP/fp_tables.txt"; sleep 2; fi
fi
[ "$INST" = no ] && A fp_tables reset >/dev/null
A fp_vm set stroke -1 >/dev/null; A fp_vm set strokes 1 >/dev/null; A chatter on >/dev/null
pf_game_done
WL=$(awk -F'	' '$1 ~ /-conf$/' "$OUT/score-log.tsv" | sort -t$'	' -k2 -g | head -1 | cut -f4 | cut -c1-260)
ok=0; awk -v w="$WS" 'BEGIN{exit !(w==0)}' && ok=1
PF_DONE=1; echo "RESULT LIVETUNE-$N $([ $ok = 1 ] && echo PASS || echo FAIL) best=$WS base=$BS $(echo "$TL" | cut -c1-80) hash=$WH values=$TD/live-$N.txt installed=$INST winner-detail=[$WL] log=$OUT/score-log.tsv"
