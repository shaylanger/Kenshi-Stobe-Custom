#!/bin/bash
# fp-agree-rec.sh <out dir> <name>   (WSL; stobe-auto on PATH; Kenshi running; lab-calibrate2 2026-10-11)
# Record-only take for the animlab replay-agreement corpus (corpus/agree/pose.list, gate step 2b agree-pose.sh): katana
# drawn at zoom 0 on open ground, sword ONLY (crash safety: every crossbow unequipped, pf_noxbow): ready, stroke 1 forced
# x4 (the 0.62 dm stroke-1 start residual), stroke 0 x2, free blocks x4 (RMB held 2.5 s), swing cut into a block x3.
# One fp_vm rec over all of it, no video (rows that don't film run `# gfx: low`). Needs a KenshiFP build whose rec carries
# the native group with bone roll (pending-fixes/kfp-fist-recnative.py: 27+ tokens in rec group 5).
# Output: <out dir>/<name>.vmrec.txt (+ .lab labels); last line:
#   RESULT AGREEREC-<name> PASS|FAIL up=<viewmodel-up records> nok=<frac with native group> roll=<frac with bone roll>
#          blk=<blocking records> s1=<stroke-1 records> src=<# src line> rec=<path>
OUT=$1; N=$2
[ -n "$OUT" ] && [ -n "$N" ] || { echo "usage: fp-agree-rec.sh <out dir> <name>"; exit 2; }
export KAH_OWNER=${KAH_OWNER:-kfp-fixer}
mkdir -p "$OUT" 2>/dev/null; cd "$OUT" 2>/dev/null || { echo "RESULT AGREEREC-$N FAIL setup: out dir $OUT not usable"; exit 2; }
SH=Axima; SPOT="-54190 633 4380"
HERE=${CR:-/mnt/c}/KenshiModding/components/KenshiFP
KDIR=${KDIR:-/mnt/d/Steam/steamapps/common/Kenshi}
A(){ stobe-auto "$@" </dev/null 2>&1; }
fld(){ grep -o " $1=[^ ]*" | head -1 | cut -d= -f2; }
st(){ A fp_vm state | fld state; }
waitst(){ local e=$((SECONDS+$2)); while [ $SECONDS -lt $e ]; do [ "$(st)" = "$1" ] && return 0; sleep 0.2; done; return 1; }
cleanup(){ A fp_vm rec off >/dev/null; A fp_vm set stroke -1 >/dev/null; A fp_keys release rmb >/dev/null; A fp_keys release lmb >/dev/null; A chatter on >/dev/null; }
PF_ROW=AGREEREC-$N; PF_ON_FAIL=cleanup; . $HERE/tests/ingame/take-preflight.sh
pf_begin "$PF_ROW"
T0=$(date +%s.%N); lab(){ echo "$(awk -v a="$(date +%s.%N)" -v b="$T0" 'BEGIN{printf "%.2f", a-b}') $*" >> "$N.lab"; }
ready(){ [ "$(st)" = ready ] || { [ "$(st)" = holstered ] || { A key_inject r tap 120 >/dev/null; waitst holstered 6; }; A key_inject r tap 120 >/dev/null; waitst ready 6; }; }
# ---- preflight (fails before recording)
pf_load
A speed 1 hold >/dev/null; A chatter off >/dev/null
A pin Malzin at -53900 633 6850 >/dev/null; A pin Tassilo at -53940 640 6850 >/dev/null; A pin Shay at -53980 640 6850 >/dev/null
A select $SH >/dev/null; A fp_control take >/dev/null
pf_rig
pf_clean -54190 4380 6000
pf_day
A teleport $SH $SPOT >/dev/null; sleep 2
for c in $SH Malzin; do A health $c 100 >/dev/null; done
A fp_combat physical >/dev/null; A fp_combat on >/dev/null; A combatmode $SH ranged off >/dev/null
A inv $SH | grep -q '"name":"Chisa Katana"' || { A unequip Malzin "Chisa Katana" >/dev/null; A transfer Malzin $SH "Chisa Katana" >/dev/null; A pickup $SH "Chisa Katana" radius 80 >/dev/null; }
A equip $SH "Chisa Katana" >/dev/null; sleep 1
pf_noxbow $SH Malzin Tassilo Shay || pf_fail "crossbow still equipped ($PF_WHY)"
A fp_camera distance 0 >/dev/null; A fp_camera orbit 0 >/dev/null; A fp_camera look 3.14 0.05 >/dev/null; sleep 1
pf_iso; ready; [ "$(st)" = ready ] || pf_fail "katana not ready (state=$(st))"
cl_=$(A fp_vm state | grep -o "class=[a-z0-9]*" | head -1); case "$cl_" in *xbow*|*ranged*|*bow*) A key_inject r tap 120 >/dev/null; pf_fail "drawn weapon $cl_ (sword only)";; esac
pf_nofight
# ---- take (rec only)
: > "$N.lab"; A fp_vm rec on >/dev/null; T0=$(date +%s.%N)
lab "Katana ready, zoom 0"; sleep 3
A fp_vm set stroke 1 >/dev/null
for k in 1 2 3 4; do lab "Stroke 1 swing $k"; A fp_keys press lmb 80 >/dev/null; sleep 2.4; done
A fp_vm set stroke 0 >/dev/null
for k in 1 2; do lab "Stroke 0 swing $k"; A fp_keys press lmb 80 >/dev/null; sleep 2.4; done
A fp_vm set stroke -1 >/dev/null
for k in 1 2 3 4; do lab "RMB held: block $k"; A fp_keys press rmb 2500 >/dev/null; sleep 2.2; lab "RMB released: ready"; sleep 2.4; done
for k in 1 2 3; do lab "LMB then RMB 0.35 s: swing cut into block $k"; A fp_keys press lmb 80 >/dev/null; sleep 0.35; A fp_keys press rmb 2200 >/dev/null; sleep 2.3
  lab "RMB released: ready"; sleep 2.0; done
lab end
A fp_vm rec off >/dev/null; rm -f "$KDIR/vmrec-agree-$N.txt"; A fp_vm rec dump "vmrec-agree-$N.txt" >/dev/null; sleep 2
cp "$KDIR/vmrec-agree-$N.txt" "$N.vmrec.txt" 2>/dev/null; rm -f "$KDIR/vmrec-agree-$N.txt"
A chatter on >/dev/null
pf_game_done
[ -s "$N.vmrec.txt" ] || { PF_DONE=1; echo "RESULT AGREEREC-$N FAIL no vmrec dump"; exit 1; }
EV=$(python3 - "$N.vmrec.txt" <<'PY'
import sys
import re
up = nok = roll = blk = s1 = 0; src = '?'
hdr = open(sys.argv[1], errors='replace').readline()
if hdr.startswith('# dryrun canned'):   # dryrun.sh fake game (kahstub canned dump): only proves rec on/dump ran
    m = re.search(r'frames=(\d+)', hdr); n = int(m.group(1)) if m else 0
    print('%s dryrun-canned frames=%d' % ('PASS' if n > 0 else 'FAIL', n)); sys.exit(0)
for ln in open(sys.argv[1]):
    if ln.startswith('# src '): src = ln.split()[-1]
    if ln[0] == '#' or '|' not in ln: continue
    g = ln.split('|'); h = g[0].split()
    try: on, w = int(h[6]), float(h[7])
    except Exception: continue
    zf = 1.0
    if len(g) > 4:
        x = g[4].split()
        if len(x) >= 4: zf = float(x[3])
    if not (on and w * zf > 0.001): continue
    up += 1
    nat = g[5].split() if len(g) > 5 else []
    if nat and nat[0] == '1':
        nok += 1
        if len(nat) >= 27 and nat[15] != '0.0000,0.0000,0.0000': roll += 1
    if h[3] == 'blocking': blk += 1
    for gg in g[5:]:
        x = gg.split()
        if len(x) >= 4 and x[0] == 'H' and x[3] == '1': s1 += 1
f = lambda a: '%.2f' % (a / up) if up else '0'
ok = up >= 300 and nok >= 0.9 * up and roll >= 0.9 * up and blk >= 60 and s1 >= 60
print('%s up=%d nok=%s roll=%s blk=%d s1=%d src=%s' % ('PASS' if ok else 'FAIL', up, f(nok), f(roll), blk, s1, src))
PY
)
PF_DONE=1; echo "RESULT AGREEREC-$N $EV rec=$OUT/$N.vmrec.txt"
