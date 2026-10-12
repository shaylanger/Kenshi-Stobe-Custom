#!/bin/bash
# fp-ready-diag.sh <out dir> [sid] [name]   (WSL 5090 or 4080 Git Bash via rig-env.sh; kah-fpxbow; no video: gfx-low lane OK)
# Ready-pose diagnostic (cleaver-fix 2026-10-11, STATUS.md Misses "ready pose at take start"): in 139-wc-clv (4080,
# B17B98D5) and REEL-Long_Cleaver (3F1AD4F8) the FIRST ready after equip + draw held a pose the lab replay of the same
# recording never produces (blade rolled ~95 deg, elbow 4 dm off, arm stretch 3.36 vs 2.08) until the first swing; after
# that and after every later holster/draw at zoom 0 game == lab. This row loops exactly that trigger with the solver state
# logged: fresh load -> equip <sid> (default Long Cleaver) -> draw -> `fp_vm state` + `fp_vm probe` at 0.5/2/4 s -> one
# swing -> state -> R holster + R draw (control: same weapon, no equip) -> state -> unequip + equip + draw (re-equip) ->
# state. One fp_vm rec over all of it (<out>/diag.vmrec.txt), snapshots in <out>/snaps.txt.
# Prints `RESULT READYDIAG-<slug> PASS repro start=<0|1>(..) zoomret=<0|1>(..)`: PASS = every phase recorded (a diagnostic
# row: the evidence is the recording + snapshots); start=1 / zoomret=1 when the first ready / the ready after a zoom 25 -> 0
# return holds a forearm hinge > 20 deg off the post-swing ready (zoomret=1 is the bug kfp-elb-zoomreset fixes).
OUT=$1; SID=${2:-478-gamedata.base}; NM=${3:-Long Cleaver}
RE=${CR:-/mnt/c}/KenshiModding/tools/automation/rig-env.sh; [ -f "$RE" ] && . "$RE"
HERE=${CR:-/mnt/c}/KenshiModding/components/KenshiFP
KDIR=${KDIR:-/mnt/d/Steam/steamapps/common/Kenshi}
SLUG=$(echo "$NM" | tr -c 'A-Za-z0-9\n' '_' | cut -c1-24)
SH=Axima; SPOT="-54190 633 4380"; HOLD=Tassilo
A(){ stobe-auto "$@" </dev/null 2>&1; }
fld(){ grep -o " $1=[^ ]*" | head -1 | cut -d= -f2; }
cleanup(){ A fp_keys release lmb >/dev/null; A fp_vm rec off >/dev/null; A chatter on >/dev/null; }
PF_ROW=READYDIAG-$SLUG; PF_ON_FAIL=cleanup; . $HERE/tests/ingame/take-preflight.sh
pf_begin "$PF_ROW"
pf_outdir "$OUT"; cd "$OUT" || pf_fail "out dir $OUT"
S=$OUT/snaps.txt; : > "$S"
snap(){ local st pr; st=$(A fp_vm state); pr=$(A fp_vm probe)
  echo "SNAP $1 t=$(date +%s.%N) state=$(pf_st) stretch=$(fld stretch <<<"$st") st_max=$(fld st_max <<<"$st") elb=$(fld elb <<<"$st") wfix=$(fld wfix <<<"$st") rsd=$(fld rsd <<<"$st") pl=$(fld pl <<<"$st") omode=$(fld omode <<<"$st") pom=$(fld pom <<<"$pr") 2h=$(fld 2h <<<"$pr") cat=$(fld cat <<<"$pr")" >> "$S"
  { echo "FULL $1 $st"; echo "PROBE $1 $pr"; } >> "$OUT/snaps-full.txt"; }
# ---- setup (no filming: no pf_open / pf_day needed; area clean so no fight changes the stance)
pf_load
A speed 1 hold >/dev/null; A chatter off >/dev/null
A pin Malzin at -53900 633 6850 >/dev/null; A pin $HOLD at -53940 640 6850 >/dev/null; A pin Shay at -53980 640 6850 >/dev/null
A select $SH >/dev/null; A fp_control take >/dev/null
pf_rig
pf_clean -54190 4380 6000
A teleport $SH $SPOT >/dev/null; sleep 2; A health $SH 100 >/dev/null
A fp_combat physical >/dev/null; A fp_combat on >/dev/null; A combatmode $SH ranged off >/dev/null
pf_noxbow $SH Malzin $HOLD Shay || pf_fail "$PF_WHY"
pf_iso
A inv $SH | grep -qF "\"$NM\"" || { r=$(A give $SH "$SID" 1); echo "$r" | grep -q " got 1/" || pf_fail "give $SID: $(cut -c1-200 <<<"$r")"; }
r=$(A equip $SH "$SID"); case "$r" in equipped*) ;; *) pf_fail "equip $SID: $(cut -c1-140 <<<"$r")";; esac
sleep 1; A fp_camera distance 0 >/dev/null; A fp_camera orbit 0 >/dev/null; A fp_camera look 3.14 0.02 >/dev/null
A fp_vm rec on >/dev/null
snap pre-draw
pf_ready
snap ready-0.5; sleep 1.5; snap ready-2; sleep 2; snap ready-4
A fp_keys press lmb 60 >/dev/null; sleep 2.6; pf_waitst ready 4; sleep 1; snap after-swing1
# zoom return (the found trigger, kfp-elb-zoomreset): out to 25 and straight back to 0 while drawn, then the ready pose
A fp_camera distance 25 >/dev/null; sleep 2.5; snap zoom25; A fp_camera distance 0 >/dev/null; sleep 2.5; snap zoomret-2.5
A key_inject r tap 120 >/dev/null; pf_waitst holstered 6 || pf_fail "no holster after R"; sleep 1.2
A key_inject r tap 120 >/dev/null; pf_waitst ready 6 || pf_fail "no draw after R"; sleep 0.5
snap redraw-0.5; sleep 2; snap redraw-2.5
A key_inject r tap 120 >/dev/null; pf_waitst holstered 6; sleep 0.5
A unequip $SH "$SID" >/dev/null; sleep 1; r=$(A equip $SH "$SID"); case "$r" in equipped*) ;; *) pf_fail "re-equip $SID: $(cut -c1-140 <<<"$r")";; esac
sleep 1; pf_ready; snap reequip-0.5; sleep 2; snap reequip-2.5
A fp_keys press lmb 60 >/dev/null; sleep 2.6; snap after-swing2
A fp_vm rec off >/dev/null; rm -f "$KDIR/vmrec-rd-$SLUG.txt"; A fp_vm rec dump "vmrec-rd-$SLUG.txt" >/dev/null; sleep 2
cp "$KDIR/vmrec-rd-$SLUG.txt" diag.vmrec.txt 2>/dev/null; rm -f "$KDIR/vmrec-rd-$SLUG.txt"
A key_inject r tap 120 >/dev/null; cleanup
pf_game_done
[ -s diag.vmrec.txt ] || pf_fail "fp_vm rec dump empty"
# first ready (before the first swing) vs the ready after it: forearm hinge (rec 'H' group, 3rd vector) + arm stretch
EV=$(python3 - diag.vmrec.txt <<'PY'
import sys, math
R = []
for l in open(sys.argv[1]):
    if l.startswith('#') or not l.strip(): continue
    g = l.rstrip('\n').split('|'); h = g[0].split()
    try: int(h[0])
    except ValueError: continue
    try:
        H = next((x.split() for x in g if x.split()[:1] == ['H']), None)
        R.append((h[3], float(h[7]), float(h[16]), [float(v) for v in H[2].split(',')] if H else None, float(g[3].split()[5])))
    except (IndexError, ValueError):
        R.append((h[3], 0.0, 0.0, None, 0.0))   # short record (older build / dry-run stub): not judged
sw = next((i for i, r in enumerate(R) if r[0] == 'swinging'), None)
zo = next((i for i, r in enumerate(R) if r[2] >= 8), None)
zr = next((i for i in range(zo or 0, len(R)) if zo is not None and R[i][2] < 1), None)
ok = lambda r: r[0] == 'ready' and r[1] >= 0.999 and r[2] < 1 and r[3]
A_ = [r for r in R[:sw or 0] if ok(r)]
B_ = [r for r in R[(sw or 0):(zo or len(R))] if ok(r)]
C_ = []
for r in R[(zr + 15) if zr is not None else len(R):]:
    if not ok(r): break
    C_.append(r)
def d(u, v): return math.degrees(math.acos(max(-1, min(1, sum(x * y for x, y in zip(u, v)) / (math.hypot(*u) * math.hypot(*v))))))
if not B_: print('repro=? no ready after the first swing (pre=%d)' % len(A_)); sys.exit()
b = B_[-1]; out = []
for nm, X in (('start', A_), ('zoomret', C_)):
    if not X: out.append('%s=?' % nm); continue
    a = X[len(X) // 2]; h = d(a[3], b[3])
    out.append('%s=%d(hinge %.1fdeg stretch %.2f vs %.2f)' % (nm, h > 20, h, a[4], b[4]))
print('repro ' + ' '.join(out))
PY
)
pf_result PASS "$EV build=$(grep -m1 '^# src' diag.vmrec.txt | awk '{print $NF}') rec=$OUT/diag.vmrec.txt snaps=$S"
