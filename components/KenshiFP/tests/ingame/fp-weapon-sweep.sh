#!/bin/bash
# fp-weapon-sweep.sh <out dir> <list> [name]   (5090 WSL or 4080 Git Bash through tools/automation/rig-env.sh; stobe-auto on
# PATH; Kenshi running windowed, kah-fpxbow fixture copy). Weapon matrix game takes (weapon-matrix, Shay 2026-10-10: "test
# every weapon in game ... mods that add new weapons must not break our animations").
# <list>: lines `sid|name|type|anim class|ammo` (# = comment), written by
#   python3 Kenshi-Automation-Harness/tools/animlab/animlab.py weapons --catalog -o <dir>   -> <dir>/sweep.list + weapons.json
# (representatives: one per anim class x size bucket of the base game, every mod weapon with its own mesh/scale/anim set,
# every crossbow; the reference weapons Chisa Katana + Oldworld Bow MkII first). Split long lists (one short take per
# weapon, ~1 min each); WSTART/WCOUNT pick a slice (1-based) so two rigs can share one list.
# Setup once: fixture load, pins, take spot, daytime + clear sky, hostiles cleared (pf_* in take-preflight.sh). Then per
# weapon, in a subshell (a failed weapon stops only itself, no retry): give by sid if missing (harness `give` creates weapons
# since the weapon-matrix MakeWeapon build; crossbows also get 10 of their ammo), equip by sid (reply must say equipped),
# fp_vm class melee/ranged must match, drawn ready (pf_ready), crossbow loaded (pf_loaded), open ground + no cursor (pf_open);
# then ONE recording: zoom 0 ready, 2 LMB swings, RMB block, sheathe + draw, then zoom 25 (side view, orbit 2.3) ready,
# swing, block, holster (crossbow: ready, aim (RMB) + release instead of swings/blocks). Evidence: take-sample.sh +
# takecheck.py, frames.py cursor/openground, the fp_vm rec judged by `animlab.py weapons --run --only <sid>` with that
# weapon's real mesh (near clip / visible / two-hand / arc / seen), metrics moves; review pack (review-pack.py).
# Per weapon dir <out>/<k>-<slug>/: take.mp4 take.lab take.ev.txt take.vmrec.txt lab.txt review/ ; per weapon one line
#   RESULT WEAPON-<slug> PASS|FAIL <evidence>          and last  RESULT WEAPONSWEEP-<name> PASS|FAIL pass=<n>/<m>
# The weapon is unequipped and handed to Tassilo after its take; the original bow goes back on the back slot at the end.
OUT=$1; LIST=$2; NAME=${3:-sweep}
[ -n "$OUT" ] && [ -n "$LIST" ] || { echo "usage: fp-weapon-sweep.sh <out dir> <list> [name]"; exit 2; }
export KAH_OWNER=${KAH_OWNER:-weapon-matrix}
RE=${CR:-/mnt/c}/KenshiModding/tools/automation/rig-env.sh; [ -f "$RE" ] && . "$RE"
mkdir -p "$OUT" 2>/dev/null; cd "$OUT" 2>/dev/null || { echo "RESULT WEAPONSWEEP-$NAME FAIL setup: out dir $OUT not usable"; exit 2; }
[ -s "$LIST" ] || { echo "RESULT WEAPONSWEEP-$NAME FAIL setup: list $LIST missing"; exit 2; }
SH=Axima; SPOT="-54190 633 4380"; HOLD=Tassilo
HARN=${CR:-/mnt/c}/KenshiModding/Kenshi-Automation-Harness; HERE=${CR:-/mnt/c}/KenshiModding/components/KenshiFP; L=$HARN/tools/animlab
FFX=${FFX:-${CR:-/mnt/c}/Users/Shay/AppData/Local/Microsoft/WinGet/Packages/Gyan.FFmpeg_Microsoft.Winget.Source_8wekyb3d8bbwe/ffmpeg-8.0.1-full_build/bin/ffmpeg.exe}
KDIR=${KDIR:-/mnt/d/Steam/steamapps/common/Kenshi}; TITLE=${WIN_TITLE:-Kenshi 1.0.65 - x64 (Newland)}
WCAT=${WCAT:-$(dirname "$LIST")/weapons.json}
A(){ stobe-auto "$@" </dev/null 2>&1; }
fld(){ grep -o " $1=[^ ]*" | head -1 | cut -d= -f2; }
cleanup(){ A fp_keys release rmb >/dev/null; A fp_keys release lmb >/dev/null; A fp_camera distance 0 >/dev/null; A fp_camera orbit 0 >/dev/null; A chatter on >/dev/null; }
PF_ROW=WEAPONSWEEP-$NAME; PF_ON_FAIL=cleanup; . $HERE/tests/ingame/take-preflight.sh
pf_begin "$PF_ROW"
[ -s "$WCAT" ] || pf_fail "weapon catalog $WCAT missing (animlab.py weapons --catalog writes it next to sweep.list)"
# ---- setup once
A load kah-fpxbow | cut -c1-80; sleep 8
for i in $(seq 1 60); do sleep 3; A wait-world | grep -qE "phase=world|ready" && break; done
A speed 1 hold >/dev/null; A chatter off >/dev/null
A pin Malzin at -53900 633 6850 >/dev/null; A pin $HOLD at -53940 640 6850 >/dev/null; A pin Shay at -53980 640 6850 >/dev/null
A select $SH >/dev/null; A fp_control take >/dev/null
pf_rig; pf_display
pf_clean -54190 4380 6000
pf_day
A teleport $SH $SPOT >/dev/null; sleep 2; A health $SH 100 >/dev/null
A fp_combat physical >/dev/null; A fp_combat on >/dev/null
BOWN=$(A rangedinfo $SH | grep -o 'bow=.* has_ammo' | sed 's/^bow=//; s/ has_ammo$//'); [ "$BOWN" = none ] && BOWN=""
echo "setup ok: bow=${BOWN:-none} list=$LIST catalog=$WCAT"
# ---- one weapon (subshell: pf_fail ends only this weapon)
take(){   # k sid name type animcls ammo
  local k=$1 sid=$2 nm=$3 ty=$4 ac=$5 am=$6 slug D N T0 FP
  slug=$(echo "$nm" | tr -c 'A-Za-z0-9\n' '_' | cut -c1-24)
  D="$OUT/$(printf %03d $k)-$slug"; mkdir -p "$D"; cd "$D" || { echo "RESULT WEAPON-$slug FAIL setup: dir $D"; return; }
  N=take; PF_ROW=WEAPON-$slug; PF_DONE=""
  PF_ON_FAIL='A fp_keys release rmb >/dev/null; A fp_camera distance 0 >/dev/null; [ -n "$_TS_RUN" ] && take_sample_stop'
  lab(){ echo "$(awk -v a="$(date +%s.%N)" -v b="$T0" 'BEGIN{printf "%.2f", a-b}') $*" >> "$N.lab"; }
  place(){ A teleport $SH $SPOT >/dev/null; A fp_camera distance 0 >/dev/null; A fp_camera orbit 0 >/dev/null; A fp_camera look 3.14 0.02 >/dev/null; sleep 1; }
  # preflight: weapon in hand
  if ! A inv $SH | grep -qF "\"$nm\""; then
    r=$(A give $SH "$sid" 1); echo "$r" | grep -q " got 1/" || pf_fail "give $sid: $(echo "$r" | cut -c1-140)"
  fi
  if [ "$ty" = crossbow ]; then
    [ -n "$am" ] && { A give $SH "$am" 10 | grep -q " got " || pf_fail "give ammo $am"; }
    A combatmode $SH ranged on >/dev/null
  else A combatmode $SH ranged off >/dev/null; fi
  r=$(A equip $SH "$sid"); case "$r" in equipped*) ;; *) pf_fail "equip $sid: $(echo "$r" | cut -c1-140)";; esac
  sleep 1; place; pf_ready
  cl=$(A fp_vm state | fld class); want=$([ "$ty" = crossbow ] && echo ranged || echo melee)
  case "$cl" in $want|$([ "$ty" = crossbow ] && echo 1 || echo 0)) ;; *) pf_fail "fp_vm class=$cl, want $want ($nm in hand?)";; esac
  [ "$ty" = crossbow ] && pf_loaded
  pf_open 2
  # take
  : > "$N.lab"; FIFO=/tmp/kfp-ws-$$.ffin; rm -f "$FIFO"; mkfifo "$FIFO" || pf_fail "mkfifo"
  "$FFX" -hide_banner -loglevel error -y -f gdigrab -draw_mouse 0 -framerate 30 -t 120 -i "title=$TITLE" -c:v libx264 -preset veryfast -crf 18 -pix_fmt yuv420p "$N.mp4" < "$FIFO" & FP=$!
  exec 7>"$FIFO"
  . $HERE/animlab/take-sample.sh
  A fp_vm rec on >/dev/null
  T0=$(date +%s.%N); take_sample_start "$N.ev.txt" "$T0" $SH "Malzin|$HOLD|Shay"; sleep 1
  for z in 0 25; do
    if [ $z = 25 ]; then A fp_camera distance 25 >/dev/null; A fp_camera orbit 2.3 >/dev/null; sleep 2; fi
    lab "Zoom $z: $nm ready stance ($ac)"; sleep 2.0
    if [ "$ty" = crossbow ]; then
      lab "Crossbow aim (RMB) zoom $z"; A fp_keys press rmb 2200 >/dev/null; sleep 1.8
      lab "RMB released: back to ready"; sleep 2.2
    else
      for s in 1 2; do lab "LMB: free swing $s"; A fp_keys press lmb 60 >/dev/null; sleep 2.4; done
      lab "RMB held: block guard"; A fp_keys press rmb 2200 >/dev/null; sleep 1.8
      lab "RMB released: back to ready"; sleep 2.2
    fi
    lab "R: sheathe"; A key_inject r tap 120 >/dev/null; pf_waitst holstered 6; sleep 0.3
    lab "Holstered (zoom $z)"; sleep 1.2
    lab "R: draw"; A key_inject r tap 120 >/dev/null; pf_waitst ready 6; sleep 0.3
    lab "Back to ready stance"; sleep 1.5
  done
  lab end; echo q >&7; exec 7>&-; take_sample_stop; _TS_RUN=; wait $FP; rm -f "$FIFO"
  A fp_camera distance 0 >/dev/null; A fp_camera orbit 0 >/dev/null
  A fp_vm rec off >/dev/null; rm -f "$KDIR/vmrec-ws-$slug.txt"; A fp_vm rec dump "vmrec-ws-$slug.txt" >/dev/null; sleep 2
  cp "$KDIR/vmrec-ws-$slug.txt" "$N.vmrec.txt" 2>/dev/null; rm -f "$KDIR/vmrec-ws-$slug.txt"
  "$FFX" -hide_banner -i "$N.mp4" 2>&1 | grep -o 'Duration: [0-9:.]*' | awk -F'[: ]' '{print $3*3600+$4*60+$5}' > "$N.video-len.txt"
  TC=$(python3 $L/takecheck.py --labels "$N.lab" --ev "$N.ev.txt" --rules $HERE/animlab/take-rules.txt --video "$N.mp4" 2>&1 | tail -1)
  CU=$(python3 $L/frames.py cursor "$N.mp4" 2>&1 | tail -1)
  OG=$(python3 $L/frames.py openground "$N.mp4" 2>&1 | tail -1)
  WM=""; MV=""
  if [ -s "$N.vmrec.txt" ]; then
    WM=$(python3 $L/animlab.py weapons --run --weapons-json "$WCAT" --only "$sid" --recs "$N.vmrec.txt" -o wm 2>&1 | grep '^WEAPON ' | head -1)
    MV=$(python3 $L/animlab.py metrics "$N.vmrec.txt" 2>&1 | grep '^moves ' | head -1)
  fi
  printf '%s\n' "takecheck $TC" "cursor $CU" "openground $OG" "matrix $WM" "$MV" > lab.txt
  python3 ${CR:-/mnt/c}/KenshiModding/tools/automation/review-pack.py "$N.mp4" review --ts "$N.ev.txt" --labels "$N.lab" --lab lab.txt > review.log 2>&1
  ok=1; for r in "$TC" "$CU" "$OG" "$MV"; do echo "$r" | grep -q "PASS" || ok=0; done
  echo "$WM" | grep -q "^WEAPON [^ ]* PASS" || ok=0
  [ -s "$N.vmrec.txt" ] || ok=0
  # hand the weapon on (keeps the inventory free; the next take starts clean)
  A key_inject r tap 120 >/dev/null; pf_waitst holstered 6
  A unequip $SH "$sid" >/dev/null; A transfer $SH $HOLD "$sid" >/dev/null
  PF_DONE=1; echo "RESULT WEAPON-$slug $([ $ok = 1 ] && echo PASS || echo FAIL) sid=$sid class=$ac matrix=[$(echo "$WM" | cut -d' ' -f6- | cut -c1-260)] moves=[$(echo "$MV" | cut -c1-80)] takecheck=[$TC] cursor=[$CU] openground=[$OG] review=$D/review/INDEX.txt len=$(cat "$N.video-len.txt" 2>/dev/null)"
}
# ---- sweep
k=0; n=0; np=0; S=${WSTART:-1}; C=${WCOUNT:-9999}
while IFS='|' read -r sid nm ty ac am; do
  case "$sid" in ''|'#'*) continue;; esac
  k=$((k + 1)); [ $k -lt $S ] && continue; [ $k -ge $((S + C)) ] && break
  n=$((n + 1))
  r=$( (take "$k" "$sid" "$nm" "$ty" "$ac" "$am") 2>&1 | tee -a "$OUT/sweep.log" | grep '^RESULT WEAPON-' | tail -1)
  [ -n "$r" ] || r="RESULT WEAPON-$(echo "$nm" | tr -c 'A-Za-z0-9\n' '_' | cut -c1-24) FAIL setup: take ended without a RESULT line"
  echo "$r"; echo "$r" | grep -q "^RESULT [^ ]* PASS" && np=$((np + 1))
  cd "$OUT"
done < "$LIST"
# ---- restore
cleanup; A combatmode $SH ranged off >/dev/null
[ -n "$BOWN" ] && { A inv $SH | grep -qF "\"$BOWN\"" || A transfer $HOLD $SH "$BOWN" >/dev/null; A equip $SH "$BOWN" >/dev/null; }
pf_result "$([ $np = $n ] && [ $n -gt 0 ] && echo PASS || echo FAIL)" "pass=$np/$n list=$LIST out=$OUT"
