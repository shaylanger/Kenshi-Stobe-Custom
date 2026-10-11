#!/bin/bash
# fp-fists.sh <out dir> <technique 0-3> [reps 3] [lab dir]   (WSL on the 5090, Git Bash on the 4080: RIG=5090|4080)
# NA1 fists take: ONE unarmed technique per take (0 badpunch, 1 ma chudan, 2 ma 2strike, 3 shoteiL = the fist table
# order of pending-fixes/kfp-fists-na1.py), Axima unarmed at zoom 0 on the VMQUICK open-ground spot of kah-fpxbow
# (the spot the lab's unarmed body recording vmrec-fist-z0-a.txt came from), daytime, clear sky.
# Needs a KenshiFP build with the NA1 fists patch (`fp_vm fist` answers "fist ua=..."; else RESULT FAIL setup).
# Preflight (take-preflight.sh, before recording): rig, display keeper, day + clear sky, area clean, no weapon in the
# hands, R -> unarmed ready stance with fist mode on (fp_vm fist on=1 fists=1 wih=0), open ground (lab openground +
# cursor + luma). The technique is forced with `fp_vm set fist_tech <i>` (restored to -1 on exit).
# Evidence: <name>.mp4 + .lab labels, take-sample ev + takecheck.py, fp_vm rec dump judged by fist-take-check.py against
# the lab candidate (<lab dir>/<tech>/pose.txt + keys.json, default C:\KenshiTestRuns\fists-cand), every swing logged
# with the forced technique and fallback=0, then review-pack.py (1 fps + 8 fps around every label).
# Output in <out dir>: fist-<tech>.{mp4,lab,ev.txt,vmrec.txt,lab.txt,video-len.txt} + review/; last line:
#   RESULT FIST-<tech> PASS|FAIL <evidence>
# FIST_NATIVE=1 (default; kfp-fist-native.py, Shay 2026-10-10 18:20): the FP fists show the game's own unarmed animation
# moved into view, no key tables: no lab gate / fist-take-check; judged by the sampled `fp_vm fist` lines instead
# (both measured wrists on screen above the HUD in >= 90% of samples, the native wrist moved >= 1 dm during the swings).
# FIST_NATIVE=0 = the old NA1 key tables vs the lab candidate.
for d in /mnt/c /c; do [ -f $d/KenshiModding/tools/automation/rig-env.sh ] && { . $d/KenshiModding/tools/automation/rig-env.sh; break; }; done
OUT=$1; TI=$2; REPS=${3:-3}; LABD=${4:-${CR:-/mnt/c}/KenshiTestRuns/fists-cand}
TN=(badpunch ma_chudan ma_2strike shoteiL); TA=("badpunch" "ma chudan" "ma 2strike" "shoteiL")
case "$TI" in [0-3]) ;; *) echo "RESULT FIST-? FAIL setup: technique '$TI' not 0-3 (usage: fp-fists.sh <out> <0-3> [reps] [lab dir])"; exit 2;; esac
T=${TN[$TI]}; N=fist-$T; ROW=FIST-$T
# fists-cand (published for Shay) carries keys.json + sheets, not pose.txt: fall back to the lab output of the same version (WSL rig)
[ -f "$LABD/$T/pose.txt" ] || { V=$(head -1 "$LABD/VERSION.txt" 2>/dev/null | tr -dc A-Za-z0-9._-); [ -n "$V" ] && [ -f "/root/animlab-work/fists/$V/$T/pose.txt" ] && LABD=/root/animlab-work/fists/$V; }
[ -n "$OUT" ] || { echo "RESULT $ROW FAIL setup: no out dir"; exit 2; }
export KAH_OWNER=${KAH_OWNER:-$([ "${RIG:-5090}" = 4080 ] && echo rig4080 || echo fists)}
SH=Axima; SPOT=$(echo "${FIST_SPOT:--54100,669.2,7300}" | tr , " ")   # FIST_SPOT=x,y,z (commas: run-batch rows split on spaces) / FIST_LOOK: another open spot (4080: palm fronds at look 0 tripped the overlay check, fist4080b)
HERE=${CR:-/mnt/c}/KenshiModding/components/KenshiFP; L=${CR:-/mnt/c}/KenshiModding/Kenshi-Automation-Harness/tools/animlab
FFX=${FFX:-/mnt/c/Users/Shay/AppData/Local/Microsoft/WinGet/Packages/Gyan.FFmpeg_Microsoft.Winget.Source_8wekyb3d8bbwe/ffmpeg-8.0.1-full_build/bin/ffmpeg.exe}
KDIR=${KDIR:-/mnt/d/Steam/steamapps/common/Kenshi}
A(){ stobe-auto "$@" </dev/null 2>&1; }
fld(){ grep -o " $1=[^ ]*" | head -1 | cut -d= -f2; }
fist(){ A fp_vm fist; }
restore(){ A fp_vm set fist_tech -1 >/dev/null; A chatter on >/dev/null; [ -n "$MA0" ] && A setstat $SH martial_arts "$MA0" >/dev/null; }
# op-fist1/fist4080e: the force never landed for ma chudan / ma 2strike: CharStats::chooseAttack only offers techniques whose
# min/max skill window (game data, native.py catalog) holds the actor's Martial Arts (Axima ~15-20: shoteiL + badpunch only).
# Windows: badpunch -1000..20, ma chudan 35+, ma 2strike 25+, shoteiL 15+ -> set MA inside the forced technique's window.
MA_FOR=(10 70 60 18)   # 2strike/chudan well inside their windows: the unarmed encumbrance penalty may not show in stat effective
PF_ROW=$ROW; PF_ON_FAIL='restore; [ -n "$_TS_RUN" ] && take_sample_stop; [ -n "$FP" ] && { touch "$N.stop"; wait $FP; }'
. $HERE/tests/ingame/take-preflight.sh
pf_begin "$ROW"
pf_outdir "$OUT"; cd "$OUT" || pf_fail "cd $OUT"
NAT=${FIST_NATIVE:-1}
[ "$NAT" = 1 ] || { [ -f "$LABD/$T/pose.txt" ] && [ -f "$LABD/$T/keys.json" ]; } || pf_fail "lab candidate $LABD/$T (pose.txt + keys.json) missing: the take is lab-gated"
T0=0; lab(){ echo "$(awk -v a="$(date +%s.%N)" -v b="$T0" 'BEGIN{printf "%.2f", a-b}') $*" >> "$N.lab"; if type take_mark >/dev/null 2>&1; then take_mark "$*"; fi; }
# ---- setup: fresh load, squad out of frame, time, spot, raiders, unarmed
pf_load   # studio fixture kah-fpstudio where installed, else kah-fpxbow (take-preflight.sh; PF_SAVE=<save> forces one)
A speed 1 hold >/dev/null; A kill "Hungry Bandit" >/dev/null; A chatter off >/dev/null
A pin Malzin at -53900 633 6850 >/dev/null; A pin Shay at -53980 640 6850 >/dev/null
A select $SH >/dev/null; A fp_control take >/dev/null
fist | grep -q '^fist ua=\|fist ua=' || pf_fail "KenshiFP has no NA1 fists (fp_vm fist: $(fist | head -1 | cut -c1-80)): install a build with pending-fixes/kfp-fists-na1.py"
pf_rig; pf_display; pf_day
r=$(A teleport $SH $SPOT); grep -q 'moved=1' <<<"$r" || pf_fail "teleport $SH $SPOT: $(cut -c1-100 <<<"$r")"; sleep 2
pf_clean ${SPOT%% *} ${SPOT##* } 3000
A health $SH 100 >/dev/null
A fp_combat physical >/dev/null; A fp_combat on >/dev/null; A combatmode $SH ranged off >/dev/null
# no weapon in the hands: unequip every worn weapon (inv JSON entries with a weapon_model), check none is left
for w in $(A inv $SH | python3 -c "import sys,json,re
s=sys.stdin.read(); j=s.split(' items=',1)[1].split(' ',1)[1] if ' items=' in s else '[]'
try: it=json.loads(j)
except Exception: it=[]
print(' '.join(x['name'].replace(' ','_') for x in it if x.get('equipped') and x.get('weapon_model')))" 2>/dev/null); do A unequip $SH "${w//_/ }" >/dev/null; done
# op-b5 fist0: the fixture crossbow (no weapon_model in inv JSON) stayed on the back and R drew it (wih=1): unequip it too
b=$(A rangedinfo $SH | sed -n 's/.* bow=\(.*\) has_ammo=.*/\1/p' | head -1)
[ -n "$b" ] && [ "$b" != none ] && A unequip $SH "$b" >/dev/null
# b4080c fists 2/3: after the unequip KenshiFP's R still drew the bow from the inventory (class=ranged, wih=1): move it to Malzin
[ -n "$b" ] && [ "$b" != none ] && { A transfer $SH Malzin "$b" >/dev/null; A inv $SH | grep -q "\"name\":\"$b\"" && pf_fail "$b still in $SH's inventory after transfer to Malzin (R would draw it, not fists)"; }
sleep 1
b=$(A rangedinfo $SH | sed -n 's/.* bow=\(.*\) has_ammo=.*/\1/p' | head -1)
[ -z "$b" ] || [ "$b" = none ] || pf_fail "crossbow $b still equipped on $SH after unequip (R would draw it, not fists)"
A fp_camera distance 0 >/dev/null; A fp_camera orbit 0 >/dev/null; A fp_camera look ${FIST_LOOK:-0} 0.05 >/dev/null; sleep 1
pf_area $SH "Malzin|Shay"
pf_ready
f=$(fist); [ "$(fld on <<<"$f")" = 1 ] && [ "$(fld fists <<<"$f")" = 1 ] && [ "$(fld wih <<<"$f")" = 0 ] \
  || pf_fail "fist mode not on after R (want on=1 fists=1 wih=0): $(cut -c1-120 <<<"$f")"
pf_open 3
MA0=$(A stat $SH martial_arts | grep -o 'base=[0-9.]*' | cut -d= -f2); [ -n "$MA0" ] || pf_fail "stat $SH martial_arts unreadable"
A setstat $SH martial_arts ${MA_FOR[$TI]} >/dev/null
ma=$(A stat $SH martial_arts | grep -o 'base=[0-9.]*' | cut -d= -f2); [ "${ma%.*}" = "${MA_FOR[$TI]}" ] || pf_fail "martial_arts ${MA_FOR[$TI]} not set (base=$ma): forced technique out of its skill window"
# 4080 fist4080f (2E66CB37, MA base 30 for ma 2strike, window 25+): the picks still included badpunch (max skill 20) =
# the skill chooseAttack sees is the EFFECTIVE one (gear/encumbrance/medical modifiers), not the base: raise the base
# until the effective level sits inside the window (badpunch: lower it), else stop the take
MA_LO=(-1000 35 25 15); MA_HI=(20 999 999 999); mab=${MA_FOR[$TI]}
for _i in 1 2 3 4 5 6 7 8 9; do me=$(A stat $SH martial_arts | grep -o 'effective=[-0-9.]*' | cut -d= -f2); me=${me%.*}; [ -n "$me" ] || break
  if [ "$me" -lt "$(( ${MA_LO[$TI]} + 3 ))" ] && [ "$mab" -lt 100 ]; then mab=$(( mab + 10 > 100 ? 100 : mab + 10 ))
  elif [ "$me" -gt "$(( ${MA_HI[$TI]} - 3 ))" ] && [ "$mab" -gt 0 ]; then mab=$(( mab - 10 < 0 ? 0 : mab - 10 )); else break; fi
  A setstat $SH martial_arts $mab >/dev/null; done
[ -n "$me" ] && { [ "$me" -ge "${MA_LO[$TI]}" ] && [ "$me" -le "${MA_HI[$TI]}" ] || pf_fail "martial_arts effective $me (base $mab) outside the forced technique's window ${MA_LO[$TI]}..${MA_HI[$TI]}"; }
echo "martial_arts base $mab effective ${me:-?} (window ${MA_LO[$TI]}..${MA_HI[$TI]})"
A fp_vm set fist_tech $TI >/dev/null
f=$(fist); [ "$(fld force <<<"$f")" = "$TI" ] || pf_fail "fp_vm set fist_tech $TI not taken: $(cut -c1-80 <<<"$f")"
A fp_vm set fist_native $NAT >/dev/null
[ "$NAT" = 1 ] && { [ "$(fist | fld nat)" = 1 ] || pf_fail "native fists not on (fp_vm fist has no nat=1): install a build with pending-fixes/kfp-fist-native.py"; }
# ---- take
: > "$N.lab"; rm -f "$N.stop"
SW0=$(fist | fld swings); IK0=$(fist | fld ikfail); LOG0=$(wc -l < "$KDIR/KenshiFP.log")
# recorder stopped by "q" through a plain pipe (stop file): a native ffmpeg on the 4080 (Git Bash) never reads q from
# an MSYS fifo and would run the full -t 120 past the end label (found by tools/automation/dryrun.sh --rig 4080)
( while [ ! -f "$N.stop" ]; do sleep 0.1; done; echo q ) | "$FFX" -hide_banner -loglevel error -y -f gdigrab -draw_mouse 0 -framerate 30 -t 120 -i "title=${WIN_TITLE:-Kenshi 1.0.65 - x64 (Newland)}" -c:v libx264 -preset veryfast -crf 18 -pix_fmt yuv420p "$N.mp4" & FP=$!
. $HERE/animlab/take-sample.sh
A fp_vm rec on >/dev/null
T0=$(date +%s.%N); take_sample_start "$N.ev.txt" "$T0" $SH "Malzin|Shay"; sleep 1
lab "Fists ready (guard), zoom 0"; sleep 1; : > "$N.fist.txt"; fist >> "$N.fist.txt"; sleep 0.5
lab "Technique ${TA[$TI]} (LMB) x$REPS"
UMAX=0
for r in $(seq 1 $REPS); do
  A fp_keys press lmb 60 >/dev/null
  e=$((SECONDS+3)); while [ $SECONDS -lt $e ]; do f=$(fist); echo "$f" >> "$N.fist.txt"; u=$(fld u <<<"$f"); UMAX=$(awk -v a="$UMAX" -v b="${u:-0}" 'BEGIN{print (b>a?b:a)}'); sleep 0.15; done
done
lab "Guard"; sleep 1.5; fist >> "$N.fist.txt"
lab end; touch "$N.stop"; take_sample_stop; wait $FP; FP=; rm -f "$N.stop"
A fp_vm rec off >/dev/null; rm -f "$KDIR/vmrec-$N.txt"; A fp_vm rec dump "vmrec-$N.txt" >/dev/null; sleep 2
cp "$KDIR/vmrec-$N.txt" "$N.vmrec.txt" || { restore; pf_result FAIL "no vmrec dump"; exit 1; }
restore
SW1=$(fist | fld swings); IK1=$(fist | fld ikfail)
# op-b5 fist1: a stray char in the ikfail value broke $(( )) at the RESULT line (no RESULT): digits only
IK0=$(tr -dc 0-9 <<<"$IK0"); IK1=$(tr -dc 0-9 <<<"$IK1"); SW0=$(tr -dc 0-9 <<<"$SW0"); SW1=$(tr -dc 0-9 <<<"$SW1")
tail -n +$((LOG0+1)) "$KDIR/KenshiFP.log" | grep -o "\[vm\] fist swing tech='[^']*' table=.* fallback=[0-9]" > "$N.swings.txt"
# 4080 fist4080f: the force miss line ("not picked in 96 tries (seen: ...)") was lost with the session log: keep it
tail -n +$((LOG0+1)) "$KDIR/KenshiFP.log" | grep -o "\[vm\] fist force: .*" > "$N.force.txt"
FM=$(head -1 "$N.force.txt" | cut -c1-200)
pf_game_done   # game part over (vmrec copied, restore done, KenshiFP.log read): run-batch.sh starts the next row
"$FFX" -hide_banner -i "$N.mp4" 2>&1 | grep -o 'Duration: [0-9:.]*' | awk -F'[: ]' '{print $3*3600+$4*60+$5}' > "$N.video-len.txt"
# ---- verdict
ok=1
TC=$(python3 $L/takecheck.py --labels "$N.lab" --ev "$N.ev.txt" --rules $HERE/animlab/take-rules.txt --video "$N.mp4" 2>&1 | tail -1)
echo "$TC" | grep -qE "^RESULT (take )?PASS" || ok=0   # takecheck prints "RESULT take PASS"
NS=$(wc -l < "$N.swings.txt"); NG=$(grep -c "tech='${TA[$TI]}' table=${TA[$TI]%% *}.* fallback=0" "$N.swings.txt")
# native fists (NAT=1): the game picks its own unarmed technique (fist4080n: NA1 names never picked natively): count swings only
[ "$NS" -ge "$REPS" ] && { [ "$NAT" = 1 ] || [ "$NG" = "$NS" ]; } || ok=0
[ "${IK1:-0}" = "${IK0:-0}" ] || ok=0
if [ "$NAT" = 1 ]; then   # native fists: on screen above the HUD + the native motion shows (sampled fp_vm fist lines)
FG=$(python3 - "$N.fist.txt" <<'PY' 2>&1 | tee "$N.lab.txt" | tail -1
import sys, re
L = [l for l in open(sys.argv[1]) if 'fist ua=' in l]
def v(l, k):
    m = re.search(' %s=([-0-9.]+),([-0-9.]+),([-0-9.]+)' % k, l); return tuple(map(float, m.groups())) if m else None
on = n = 0; mv = 0.0; g = None
for l in L:
    w = [v(l, 'wrL'), v(l, 'wrR')]; nr = v(l, 'natR'); nl = v(l, 'natL')
    if None in w: continue
    n += 1; on += all(p[2] > 1.0 and abs(p[0] / p[2]) <= 1.15 and -0.42 <= p[1] / p[2] <= 0.65 for p in w)
    if g is None and nr and nl: g = (nl, nr)
    elif g and nr and nl: mv = max(mv, max(sum((a - b) ** 2 for a, b in zip(x, y)) ** 0.5 for x, y in zip((nl, nr), g)))
sh = on / n if n else 0
ok = n >= 10 and sh >= 0.9 and mv >= 1.0
print('fistnative %s samples=%d onscreen=%.2f native_move=%.2fdm' % ('PASS' if ok else 'FAIL', n, sh, mv))
PY
)
else
FG=$(python3 $HERE/animlab/fist-take-check.py "$N.vmrec.txt" "$LABD/$T" --swings "$N.swings.txt" 2>&1 | tee "$N.lab.txt" | tail -1)
fi
echo "$FG" | grep -qE "^fist(game|native) PASS" || ok=0
python3 ${CR:-/mnt/c}/KenshiModding/tools/automation/review-pack.py "$N.mp4" review --labels "$N.lab" --lab "$N.lab.txt" "$N.swings.txt" > review.log 2>&1
[ -f review/INDEX.txt ] || ok=0
pf_result "$([ $ok = 1 ] && echo PASS || echo FAIL)" "swings=$NS forced_ok=$NG umax=$UMAX ikfail+=$(( ${IK1:-0} - ${IK0:-0} )) lab=[$FG] takecheck=[$TC] ${FM:+force_miss=[$FM] }review=$OUT/review/INDEX.txt len=$(cat "$N.video-len.txt") rig=${RIG:-5090}"
