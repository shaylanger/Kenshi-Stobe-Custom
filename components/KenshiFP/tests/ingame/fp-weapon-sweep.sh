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
# VMSET="<key> <value>" (e.g. "twomask 0"): reference takes (old look for side-by-side videos): fp_vm set before each take,
#   slug suffix -ref, PASS = recorded + takecheck/cursor/openground (no matrix / 2H checks); VMRESET (default "twomask 264") at the end.
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
NI=; command -v nice >/dev/null 2>&1 && NI="nice -n 15"   # offline lab checks at low priority (CLAUDE.md rig uptime 5)
fld(){ grep -o " $1=[^ ]*" | head -1 | cut -d= -f2; }
cleanup(){ A fp_keys release rmb >/dev/null; A fp_keys release lmb >/dev/null; A fp_camera distance 0 >/dev/null; A fp_camera orbit 0 >/dev/null; A chatter on >/dev/null; }
PF_ROW=WEAPONSWEEP-$NAME; PF_ON_FAIL=cleanup; . $HERE/tests/ingame/take-preflight.sh
pf_begin "$PF_ROW"
[ -s "$WCAT" ] || pf_fail "weapon catalog $WCAT missing (animlab.py weapons --catalog writes it next to sweep.list)"
# ---- setup once
pf_load   # studio fixture kah-fpstudio where installed, else kah-fpxbow (take-preflight.sh; PF_SAVE=<save> forces one)
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
# give probe (2026-10-10 wm5090-2: the harness weapon factory refused every weapon, 18 takes failed one by one): the row's first
# weapon must be creatable, else the whole row stops here with one setup FAIL (a dry run can't see a real factory refusal)
PSID=$(awk -F'|' -v s="${WSTART:-1}" '$1!~/^(#|$)/{k++; if(k==s){print $1; exit}}' "$LIST")
if [ -n "$PSID" ] && ! A inv $SH | grep -q "$PSID"; then
  r=$(A give $SH "$PSID" 1); echo "$r" | grep -q " got 1/" || pf_fail "give probe $PSID (weapon factory): $(echo "$r" | cut -c1-140)"
fi
# ---- one weapon (subshell: pf_fail ends only this weapon)
take(){   # k sid name type animcls ammo
  local k=$1 sid=$2 nm=$3 ty=$4 ac=$5 am=$6 slug D N T0 FP
  slug=$(echo "$nm" | tr -c 'A-Za-z0-9\n' '_' | cut -c1-24)${VMSET:+-ref}
  D="$OUT/$(printf %03d $k)-$slug"; mkdir -p "$D"; cd "$D" || { echo "RESULT WEAPON-$slug FAIL setup: dir $D"; return; }
  N=take; PF_ROW=WEAPON-$slug; PF_DONE=""
  PF_ON_FAIL='A fp_keys release rmb >/dev/null; A fp_camera distance 0 >/dev/null; [ -n "$_TS_RUN" ] && take_sample_stop; [ -n "$FP" ] && { touch "$N.stop"; wait $FP; FP=; }'
  lab(){ echo "$(awk -v a="$(date +%s.%N)" -v b="$T0" 'BEGIN{printf "%.2f", a-b}') $*" >> "$N.lab"; if type take_mark >/dev/null 2>&1; then take_mark "$*"; fi; }
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
  if [ -n "$VMSET" ]; then r=$(A fp_vm set $VMSET); echo "$r" | grep -q "keys:\|ERROR" && pf_fail "fp_vm set $VMSET: $r"; sleep 0.5; fi
  # kfp-two-hand builds (probe has 2h=; it is NOT in `fp_vm state`, so this check never ran in 03-twohand 2026-10-10 and
  # the takes filmed with cat=-1): the category KenshiFP read must be the catalog's item class, 2H on exactly for 3/8
  st2=$(A fp_vm probe); if [ -z "$VMSET" ] && [ "$ty" != crossbow ] && echo "$st2" | grep -q ' 2h='; then
    wc_=$(python3 -c "import json,sys; print(next((w['cls'] for w in json.load(open(sys.argv[1]))['weapons'] if w['sid']==sys.argv[2]), -1))" "$WCAT" "$sid" 2>/dev/null)
    c2=$(echo "$st2" | fld cat); h2=$(echo "$st2" | fld 2h); w2=$([ "$wc_" = 3 ] || [ "$wc_" = 8 ] && echo 1 || echo 0)
    [ "$c2" = "$wc_" ] && [ "$h2" = "$w2" ] || pf_fail "2H state cat=$c2 2h=$h2, catalog class $wc_ wants 2h=$w2"
  fi
  pf_open 2
  # take
  : > "$N.lab"; rm -f "$N.stop"
  # recorder stopped by "q" through a plain pipe (stop file): a native ffmpeg on the 4080 (Git Bash) never reads q from
  # an MSYS fifo and would run the full -t 120 past the end label (dryrun.sh --rig 4080; same fix as fp-fists.sh 08bd7d5)
  ( while [ ! -f "$N.stop" ]; do sleep 0.1; done; echo q ) | "$FFX" -hide_banner -loglevel error -y -f gdigrab -draw_mouse 0 -framerate 30 -t 120 -i "title=$TITLE" -c:v libx264 -preset veryfast -crf 18 -pix_fmt yuv420p "$N.mp4" & FP=$!
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
      # block from ready (swing 2 may still recover) and label once RMB is down: blocking came 0.62 s after a pre-press label
      # (takecheck grace 0.6; 03-twohand Katana/Naginata 2026-10-10); release label stays 1.8 s after the press
      pf_waitst ready 3; A fp_keys press rmb 2200 >/dev/null; sleep 0.25; lab "RMB held: block guard"; sleep 1.55
      lab "RMB released: back to ready"; sleep 2.2
    fi
    lab "R: sheathe"; A key_inject r tap 120 >/dev/null; pf_waitst holstered 6; sleep 0.3
    lab "Holstered (zoom $z)"; sleep 1.2
    lab "R: draw"; A key_inject r tap 120 >/dev/null; pf_waitst ready 6; sleep 0.3
    lab "Back to ready stance"; sleep 1.5
  done
  lab end; touch "$N.stop"; take_sample_stop; _TS_RUN=; wait $FP; FP=; rm -f "$N.stop"
  A fp_camera distance 0 >/dev/null; A fp_camera orbit 0 >/dev/null
  A fp_vm rec off >/dev/null; rm -f "$KDIR/vmrec-ws-$slug.txt"; A fp_vm rec dump "vmrec-ws-$slug.txt" >/dev/null; sleep 2
  cp "$KDIR/vmrec-ws-$slug.txt" "$N.vmrec.txt" 2>/dev/null; rm -f "$KDIR/vmrec-ws-$slug.txt"
  # hand the weapon on (keeps the inventory free; the next take starts clean)
  A key_inject r tap 120 >/dev/null; pf_waitst holstered 6
  A unequip $SH "$sid" >/dev/null; A transfer $SH $HOLD "$sid" >/dev/null
  # offline checks in the background (no game use) while the next weapon records (Shay 2026-10-10: the game never waits
  # for analysis); the sweep collects $D/result.txt after the last take. Own stdout/stderr = file: the caller's $( ) returns now.
  PF_ON_FAIL=""; PF_DONE=1
  ( analyse > "$D/analysis.log" 2>&1 ) </dev/null >/dev/null 2>&1 &
  echo "TAKE-RECORDED $D"
}
analyse(){   # runs in $D with take()'s variables; writes the weapon's RESULT line to $D/result.txt
  "$FFX" -hide_banner -i "$N.mp4" 2>&1 | grep -o 'Duration: [0-9:.]*' | awk -F'[: ]' '{print $3*3600+$4*60+$5}' > "$N.video-len.txt"
  TC=$($NI python3 $L/takecheck.py --labels "$N.lab" --ev "$N.ev.txt" --rules $HERE/animlab/take-rules.txt --video "$N.mp4" 2>&1 | tail -1)
  CU=$($NI python3 $L/frames.py cursor "$N.mp4" 2>&1 | tail -1)
  OG=$($NI python3 $L/frames.py openground "$N.mp4" 2>&1 | tail -1)
  WM=""; MV=""
  if [ -s "$N.vmrec.txt" ]; then
    WM=$($NI python3 $L/animlab.py weapons --run --weapons-json "$WCAT" --only "$sid" --recs "$N.vmrec.txt" -o wm 2>&1 | grep '^WEAPON ' | head -1)
    MV=$($NI python3 $L/animlab.py metrics "$N.vmrec.txt" 2>&1 | grep '^moves ' | head -1)
  fi
  printf '%s\n' "takecheck $TC" "cursor $CU" "openground $OG" "matrix $WM" "$MV" > lab.txt
  $NI python3 ${CR:-/mnt/c}/KenshiModding/tools/automation/review-pack.py "$N.mp4" review --ts "$N.ev.txt" --labels "$N.lab" --lab lab.txt > review.log 2>&1
  ok=1; for r in "$TC" "$CU" "$OG" "$MV"; do echo "$r" | grep -q "PASS" || ok=0; done
  [ -n "$VMSET" ] || echo "$WM" | grep -q "^WEAPON [^ ]* PASS" || ok=0
  [ -s "$N.vmrec.txt" ] || ok=0
  echo "RESULT WEAPON-$slug $([ $ok = 1 ] && echo PASS || echo FAIL) sid=$sid class=$ac matrix=[$(echo "$WM" | cut -d' ' -f6- | cut -c1-260)] moves=[$(echo "$MV" | cut -c1-80)] takecheck=[$TC] cursor=[$CU] openground=[$OG] review=$D/review/INDEX.txt len=$(cat "$N.video-len.txt" 2>/dev/null)" > "$D/result.tmp" && mv "$D/result.tmp" "$D/result.txt"
}
# ---- sweep
PEND=(); k=0; n=0; np=0; S=${WSTART:-1}; C=${WCOUNT:-9999}
while IFS='|' read -r sid nm ty ac am; do
  case "$sid" in ''|'#'*) continue;; esac
  k=$((k + 1)); [ $k -lt $S ] && continue; [ $k -ge $((S + C)) ] && break
  n=$((n + 1))
  r=$( (take "$k" "$sid" "$nm" "$ty" "$ac" "$am") 2>&1 | tee -a "$OUT/sweep.log" | grep -E '^(RESULT WEAPON-|TAKE-RECORDED )' | tail -1)
  [ -n "$r" ] || r="RESULT WEAPON-$(echo "$nm" | tr -c 'A-Za-z0-9\n' '_' | cut -c1-24) FAIL setup: take ended without a RESULT line"
  case "$r" in TAKE-RECORDED*) PEND+=("${r#TAKE-RECORDED }");; *) echo "$r"; echo "$r" | grep -q "^RESULT [^ ]* PASS" && np=$((np + 1));; esac
  cd "$OUT"
done < "$LIST"
# ---- restore
cleanup; A combatmode $SH ranged off >/dev/null; [ -n "$VMSET" ] && A fp_vm set ${VMRESET:-twomask 264} >/dev/null
[ -n "$BOWN" ] && { A inv $SH | grep -qF "\"$BOWN\"" || A transfer $HOLD $SH "$BOWN" >/dev/null; A equip $SH "$BOWN" >/dev/null; }
pf_game_done   # game part over (every weapon recorded, restore done): run-batch.sh starts the next row
# ---- collect the background analyses (each writes <dir>/result.txt; 20 min cap for all)
END=$((SECONDS + ${WS_ANALYSE_MAX:-1200}))
for d in "${PEND[@]}"; do
  while [ ! -s "$d/result.txt" ] && [ $SECONDS -lt $END ]; do sleep 2; done
  r=$(cat "$d/result.txt" 2>/dev/null); [ -n "$r" ] || r="RESULT WEAPON-${d##*/} FAIL analysis: no result.txt (timeout; log $d/analysis.log)"
  echo "$r" | tee -a "$OUT/sweep.log"; echo "$r" | grep -q "^RESULT [^ ]* PASS" && np=$((np + 1))
done
pf_result "$([ $np = $n ] && [ $n -gt 0 ] && echo PASS || echo FAIL)" "pass=$np/$n list=$LIST out=$OUT"
