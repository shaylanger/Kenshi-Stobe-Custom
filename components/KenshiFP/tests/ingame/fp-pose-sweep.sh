#!/usr/bin/env bash
# fp-pose-sweep.sh: KenshiFP live-tables pose sweep = the "render pass" (Shay 2026-10-10: tune poses/strokes in the running
# game, no rebuild). ONE launch, a list of animation-table variants; per variant:
#   fp_tables load <variant file> (KenshiFP kfp_tables.inc; reply hash= logged = exactly which variant was filmed), then
#   the VMQUICK segment of the weapon at every zoom in SWEEP_ZOOMS (default "0 $ZO"): sword draw/ready/walk/block/
#   wind-up/strike/follow-through (zoom 0 frozen sw_pose)/live swing/swing->block/holster, crossbow draw/ready/walk/aim/
#   fire/reload/holster; screenshots labelled "<variant> #<hash>", fp_vm rec per segment (its dump carries
#   "# tables <hash>" + the variant's values, so the lab replays it) checked by vmcheck (zoom 0) / zo (zoomed out);
#   one sheet per variant (<out>/<variant>/sheet.jpg + final-<weapon>-zoom<z>.jpg) and one line
#   RESULT POSESWEEP-<variant> PASS|FAIL hash=<game hash> lab=<lab hash> <vmcheck results> sheet=<path>.
#   At the end fp_tables reset (compiled values) and <out>/sweep-index.tsv (variant, hash, verdict, sheet, recs) for the
#   auto-review agent (frames judged there, not here).
# Usage: fp-pose-sweep.sh <variants list> [player] [mate] [hostile] [outdir]     (kah-fpxbow fixture, like fp-viewmodel.sh)
#   list (fptables.py expand format, "#" comments): <name> [<base tables file>|-] [<lhs>=<v>[,<v>..]]...
#     e.g.  base -                                       (compiled values: the reference row)
#           rdy-low - pose.m_ready.py=-1.4
#           s2-k3   C:/KenshiTestRuns/tables/s2.txt swk_alt.s2_k3.pz=4.9
#   env: SWEEP_WEAPON=sword|crossbow (sword; one weapon per take), SWEEP_ZOOMS ("0 $ZO"), TOOLS (harness tools/animlab dir),
#        KFP_TABLES_ADAPTER (lab kfpvm_tables, optional: lab hash cross-check), plus fp-viewmodel.sh's env (KDIR, ZO, PY..)
# Needs a KenshiFP build with kfp-live-tables (fp_tables command) and the take preflight (take-preflight.sh).
# Setup + segment code = fp-viewmodel.sh up to its VMQUICK main block, from a private copy taken at start (an edit of
# fp-viewmodel.sh during the run cannot break it; a changed marker line = setup FAIL naming it).
LIST=$1; shift || true
HERE=$(cd "$(dirname "$0")" && pwd); OUTD=${4:-/tmp/fp-pose-sweep}; mkdir -p "$OUTD"
TOOLS=${TOOLS:-$HERE/../../../../Kenshi-Automation-Harness/tools/animlab}; PYX=${PY:-python3}
winp() { if command -v wslpath >/dev/null 2>&1; then wslpath -m "$1"; elif command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else echo "$1"; fi; }
early() { echo "RESULT POSESWEEP FAIL setup: $*"; exit 1; }
[ -r "$LIST" ] || early "no variants list ($LIST)"
if ! "$PYX" -I "$TOOLS/fptables.py" expand "$LIST" "$OUTD/variants" > "$OUTD/expand.txt" 2>&1; then
  early "variant files bad in the lab: $(grep '^BAD' "$OUTD/expand.txt" | head -2 | tr '\n' ';')$(tail -1 "$OUTD/expand.txt")"; fi
[ -s "$OUTD/variants/variants.tsv" ] || early "fptables expand wrote no variants ($(tail -1 "$OUTD/expand.txt"))"
VNAMES=$(cut -f1 "$OUTD/variants/variants.tsv" | tr '\n' ' ')
ROWS=""; for v in $VNAMES; do ROWS+=" POSESWEEP-$v"; done; export ROWS
VMLIB="$OUTD/.vm-lib.sh"
awk '/^if want VMQUICK && vmq_gate; then/{f=1; exit} {print} END{exit !f}' "$HERE/fp-viewmodel.sh" > "$VMLIB" \
  || early "fp-viewmodel.sh has no 'if want VMQUICK && vmq_gate; then' marker line (the sweep reuses the code above it)"
grep -q '^vmq_seg()' "$VMLIB" || early "fp-viewmodel.sh: vmq_seg() not above the VMQUICK marker"
set -- "${1:-${PLAYER:-Axima}}" "${2:-${MATE:-Malzin}}" "${3:-${HOSTILE:-Skaera}}" "$OUTD"
VMQ_GATE=0
. "$VMLIB"   # setup (protect, take control, isolation, raid sweep, RESULT/finish/cleanup trap) + helpers + vmq_seg

# screenshots per variant (vmq_seg names them by weapon/zoom/state only): own name + "[<variant> #<hash>]" on every tile
snap() { A screenshot "ps-$VN-$2" >/dev/null; printf '%s\t%s\t%s\n' "$1" "$3 [$VN #$VH]" "$SHOTD/ps-$VN-$2.png" >> "$MAN"; }
A fp_tables state | grep -q 'hash=' || setup_fail "fp_tables missing (KenshiFP build without kfp-live-tables): $(A fp_tables state | cut -c1-80)"
A fp_vm state | grep -q ' wb=' || setup_fail "fp_vm state has no wb= (needs the PT17 wrist build)"
VMQ_PF=1; PF_ROW=POSESWEEP; . "$HERE/take-preflight.sh"; pf_fail() { setup_fail "$*"; }
read -r _px _py _pz <<<"${VMQ_SPOT_P:-"-54100 669.2 7300"}"; note "$(pf_clean "$_px" "$_pz" "${VMQ_PF_R:-6000}")"; sleep 2
A fp_combat physical >/dev/null; [ -z "$EN0" ] && EN0=$(cs enabled); A fp_combat on >/dev/null; A fp_combat input 0 0 0 >/dev/null
waitf 4 csis armed 1 || note "SETUP POSESWEEP not armed after idle input (why=$(cs why))"; A fp_combat physical >/dev/null
trap 'A fp_tables reset >/dev/null; A fp_vm set sw_pose -1 >/dev/null; A fp_vm set kick_pose -1 >/dev/null; A fp_vm replay off >/dev/null; cleanup' EXIT
ZOOMS=${SWEEP_ZOOMS:-"0 $ZO"}; WPN=${SWEEP_WEAPON:-sword}; IDX="$OUTD/sweep-index.tsv"; : > "$IDX"
printf 'variant\thash\tlab_hash\tverdict\tsheet\trecs\n' >> "$IDX"
sweep_weapon() { local W=$1 n f lh r z
  while IFS=$'\t' read -r -u 3 n f lh; do [ -n "$n" ] || continue; VN=$n; VQOK=1; VQR=""
    mkdir -p "$OUTD/$n"; MAN="$OUTD/$n/manifest-$W.tsv"; : > "$MAN"
    r=$(A fp_tables load "$(winp "$f")"); VH=$(grep -o 'hash=[0-9a-f]*' <<<"$r" | head -1 | cut -d= -f2)
    if [ -z "$VH" ] || ! grep -q ' bad=0' <<<"$r"; then row "POSESWEEP-$n" FAIL "setup: fp_tables load $f: $(cut -c1-160 <<<"$r")"; continue; fi
    [ "$lh" = - ] || [ "$lh" = "$VH" ] || VQR+=" lab hash $lh != game $VH (registry differs: lab adapter built from another source);"
    note "POSESWEEP $n $W hash=$VH file=$f"
    for z in $ZOOMS; do vmq_seg "$W" "$z"; zoom 0; done
    for z in $ZOOMS; do for rf in "$KDIR"/vmrec-q-"$W"-z"$z"*.txt; do [ -f "$rf" ] && cp "$rf" "$OUTD/$n/$(basename "${rf%.txt}")-$VH.txt"; done; done
    SHEETS+=" $n:$W"; printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$n" "$VH" "$lh" "$([ $VQOK = 1 ] && echo PASS || echo FAIL)" "$OUTD/$n/sheet-$W.jpg" "$OUTD/$n" >> "$IDX"
    judge "POSESWEEP-$n" $VQOK "hash=$VH lab=$lh weapon=$W zooms=${ZOOMS// /,} sheet=$OUTD/$n/sheet-$W.jpg |$VQR"
  done 3< "$OUTD/variants/variants.tsv"; }
SHEETS=""
case "$WPN" in
  crossbow) if [ "$BOWOK" = 1 ] && [ "$(bow_now)" != none ]; then sweep_weapon crossbow; else setup_fail "no crossbow on $SH"; fi;;
  sword) draw_to 0
    give_melee || note "SETUP: could not give $SH a melee weapon"; bow_off || note "SETUP: bow would not unequip ($(bow_now))"
    arm_melee || setup_fail "no melee weapon for the sword variants ($(weapons | tr '\n' ';'))"
    sweep_weapon sword;;
  *) setup_fail "SWEEP_WEAPON=$WPN: sword or crossbow (one weapon per take)";; esac
# game part over: compiled tables back, analysis (sheets) offline while run-batch.sh moves the game on
A fp_tables reset >/dev/null; A fp_vm set sw_pose -1 >/dev/null; A fp_vm set kick_pose -1 >/dev/null; A fp_vm replay off >/dev/null
cleanup; trap - EXIT; HH_PRE=$(hostile_hit); hostile_hit() { echo "$HH_PRE"; }
if declare -F pf_game_done >/dev/null; then pf_game_done; else [ -n "${GAME_DONE_FILE:-}" ] && : > "$GAME_DONE_FILE"; fi
for s in $SHEETS; do n=${s%%:*}; W=${s#*:}
  "$PY" "$SHEETPY" "$OUTD/$n/sheet-$W.jpg" "$OUTD/$n/manifest-$W.tsv" --split "$OUTD/$n" >/dev/null 2>&1 || note "sheet $n $W failed"; done
NOTE=/mnt/c/KenshiTestRuns/agents/auto-review.note-from-live-tables; [ -d "$(dirname "$NOTE")" ] || NOTE=/c/KenshiTestRuns/agents/auto-review.note-from-live-tables
{ echo "$(date '+%F %T') pose sweep done: $IDX (variant, game hash, lab hash, numeric verdict, sheet, rec dir); judge every variant's sheet + recs"; } >> "$NOTE" 2>/dev/null
finish
