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
#   Row POSESWEEP-TABLES (the live-tables proof): in game, fp_tables set pose m_ready.py changes the hash and get reads the
#   value back, dump -> reset -> load <dump> restores the same hash (dump == live state), reset returns the compiled
#   hash, lab adapter (if present) hashes the game dump the same; offline, every variant with changed values moved the
#   recorded arm/weapon positions vs the "base" variant (fp_tables set really changes the pose; diff in tables-check/).
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
# Windows path for the game: /mnt/c/x (WSL) and /c/x (Git Bash, 4080) mapped by string (the 4080 dryrun stub and
# wslpath on /c paths gave wrong paths, 2026-10-11); other paths through wslpath/cygpath.
winp() { case "$1" in /mnt/[a-zA-Z]/*) local d=${1:5:1}; echo "${d^^}:/${1:7}";; /[a-zA-Z]/*) local d=${1:1:1}; echo "${d^^}:/${1:3}";;
  *) if command -v wslpath >/dev/null 2>&1; then wslpath -m "$1"; elif command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else echo "$1"; fi;; esac; }
early() { echo "RESULT POSESWEEP FAIL setup: $*"; exit 1; }
[ -r "$LIST" ] || early "no variants list ($LIST)"
if ! "$PYX" -I "$TOOLS/fptables.py" expand "$LIST" "$OUTD/variants" > "$OUTD/expand.txt" 2>&1; then
  early "variant files bad in the lab: $(grep '^BAD' "$OUTD/expand.txt" | head -2 | tr '\n' ';')$(tail -1 "$OUTD/expand.txt")"; fi
[ -s "$OUTD/variants/variants.tsv" ] || early "fptables expand wrote no variants ($(tail -1 "$OUTD/expand.txt"))"
VNAMES=$(cut -f1 "$OUTD/variants/variants.tsv" | tr '\n' ' ')
ROWS="POSESWEEP-TABLES"; for v in $VNAMES; do ROWS+=" POSESWEEP-$v"; done; export ROWS
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
TBLD="$OUTD/tables-check"; mkdir -p "$TBLD"; TBLOK=1; TBLR=""; TBLH1=""
hof() { grep -o 'hash=[0-9a-f]*' <<<"$1" | head -1 | cut -d= -f2; }
tables_check() { local r h0 h1 h2 h3 g
  r=$(A fp_tables reset); h0=$(hof "$r"); grep -q 'default=1' <<<"$r" || { TBLOK=0; TBLR+=" reset not default ($(cut -c1-80 <<<"$r"));"; }
  r=$(A fp_tables set pose m_ready.py -1.6); h1=$(hof "$r"); TBLH1=$h1
  g=$(A fp_tables get pose m_ready.py); grep -q '^pose\[[0-9]*\] -1.6 ' <<<"$g" || { TBLOK=0; TBLR+=" get after set: $(cut -c1-60 <<<"$g");"; }
  [ -n "$h1" ] && [ "$h1" != "$h0" ] || { TBLOK=0; TBLR+=" set kept hash $h0->$h1 ($(cut -c1-80 <<<"$r"));"; }
  r=$(A fp_tables dump "$(winp "$TBLD/live-set.txt")"); grep -q 'which=all' <<<"$r" || { TBLOK=0; TBLR+=" dump: $(cut -c1-80 <<<"$r");"; }
  r=$(A fp_tables reset); h2=$(hof "$r"); [ "$h2" = "$h0" ] || { TBLOK=0; TBLR+=" reset hash $h2 != compiled $h0;"; }
  r=$(A fp_tables load "$(winp "$TBLD/live-set.txt")"); h3=$(hof "$r")
  { [ "$h3" = "$h1" ] && grep -q ' bad=0' <<<"$r"; } || { TBLOK=0; TBLR+=" reload of the dump: hash $h3 != set $h1 ($(cut -c1-80 <<<"$r"));"; }
  A fp_tables reset >/dev/null
  TBLR="compiled=$h0 set=$h1 dump-reload=$h3 reset=$h2 |$TBLR"; note "TABLES game check: $TBLR"; }
tables_check
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
cleanup game-done; trap - EXIT; HH_PRE=$(hostile_hit); hostile_hit() { echo "$HH_PRE"; }
if declare -F pf_game_done >/dev/null; then pf_game_done; else [ -n "${GAME_DONE_FILE:-}" ] && : > "$GAME_DONE_FILE"; fi
for s in $SHEETS; do n=${s%%:*}; W=${s#*:}
  "$PY" "$SHEETPY" "$OUTD/$n/sheet-$W.jpg" "$OUTD/$n/manifest-$W.tsv" --split "$OUTD/$n" >/dev/null 2>&1 || note "sheet $n $W failed"; done
# POSESWEEP-TABLES offline half: lab hash of the game's dump, then "did the pose move" per variant vs base (recs, per state)
if [ -f "$TBLD/live-set.txt" ] && [ -n "$TBLH1" ]; then
  lr=$("$PYX" -I "$TOOLS/fptables.py" check "$TBLD/live-set.txt" 2>&1); lh=$(hof "$lr")
  if [ -n "$lh" ]; then [ "$lh" = "$TBLH1" ] || { TBLOK=0; TBLR+=" lab hash of the game dump $lh != game $TBLH1;"; }; TBLR+=" lab-dump=$lh"
  else TBLR+=" lab-dump=n/a(no adapter)"; fi
else TBLOK=0; TBLR+=" no game dump file $TBLD/live-set.txt;"; fi
"$PYX" -I - "$OUTD" "$IDX" > "$TBLD/pose-diff.txt" 2>&1 <<'PYEOF'
import sys, os, glob, re
outd, idx = sys.argv[1], sys.argv[2]
rows = [l.rstrip('\n').split('\t') for l in open(idx)][1:]
def load(path):
    acc = {}
    for l in open(path):
        if l.startswith('#') or '|' not in l: continue
        g = l.split(' | '); h = g[0].split()
        if len(h) < 4 or len(g) < 2: continue   # g[1] = viewmodel-local arm/weapon vectors (g[3] is world position: a moving character is not a pose change)
        try: v = [float(x) for grp in (g[1],) for tok in grp.split() for x in tok.split(',')]
        except ValueError: continue
        s = acc.setdefault(h[3], [0, None]); s[0] += 1
        s[1] = v if s[1] is None else [a + b for a, b in zip(s[1], v)]
    return {k: [x / n for x in s] for k, (n, s) in acc.items()}
def recs(d): return {re.sub(r'-[0-9a-f]{8}\.txt$', '', os.path.basename(p)): p for p in glob.glob(os.path.join(d, 'vmrec-*.txt'))}
base = [r for r in rows if r[0] == 'base']
if not base: print('NOBASE'); sys.exit(0)
b = recs(base[0][5]); bad = []
for r in rows:
    if r[0] == 'base': continue
    v = recs(r[5]); best = 0.0; where = '-'
    for k in set(b) & set(v):
        bm, vm = load(b[k]), load(v[k])
        for st in set(bm) & set(vm):
            d = max(abs(x - y) for x, y in zip(bm[st], vm[st]))
            if d > best: best, where = d, f'{k}:{st}'
    print(f'{r[0]} hash={r[1]} maxdiff={best:.3f} at={where} recs={len(set(b) & set(v))}')
    if r[1] == base[0][1]: continue          # same tables as base: no move expected
    if best < 0.05: bad.append(f'{r[0]}:{best:.3f}')
print('MOVED' if not bad else 'STILL ' + ','.join(bad))
PYEOF
mv=$(tail -1 "$TBLD/pose-diff.txt")
case "$mv" in MOVED) TBLR+=" pose moved in every changed variant ($(grep -c maxdiff= "$TBLD/pose-diff.txt") vs base)";;
  NOBASE) TBLR+=" pose move not checked: no 'base' variant in the list";;
  *) TBLOK=0; TBLR+=" pose did not move: $mv ($TBLD/pose-diff.txt);";; esac
judge POSESWEEP-TABLES $TBLOK "$TBLR"
NOTE=/mnt/c/KenshiTestRuns/agents/auto-review.note-from-live-tables; [ -d "$(dirname "$NOTE")" ] || NOTE=/c/KenshiTestRuns/agents/auto-review.note-from-live-tables
{ echo "$(date '+%F %T') pose sweep done: $IDX (variant, game hash, lab hash, numeric verdict, sheet, rec dir); judge every variant's sheet + recs"; } >> "$NOTE" 2>/dev/null
finish
