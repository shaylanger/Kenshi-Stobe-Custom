#!/bin/bash
# fp-zoomfade.sh <out dir> <name> [bandhide 1|0] [states "ready block swing"]   (WSL; stobe-auto on PATH; Kenshi running windowed)
# Z1 zoom crossfade take (COMBAT_TEST_PLAN Gate 6): the sword (katana; no crossbow: crash quarantine) held in ONE state
# while the zoom camera steps 0 -> 25 dm (`fp_camera distance d`, held until applied = d): 0.5 dm steps through the
# g_vm_zf0/zf1 (2/8 dm) smoothstep crossfade, 1-3 dm beyond. States: ready, block (RMB held), swing (one LMB swing per
# step at game speed 0.5). Camera orbited (ZF_ORBIT, default 2.36 rad) so zoomed-out frames show the body from the
# side/front over open ground. Per step: a screenshot (labelled d / zf / band_hidden) + the fp_vm recording.
# bandhide 1 = the shipped config (whole character hidden 0.65-16 dm: the half-mix is never on screen); 0 = the raw
# crossfade (A/B: what the half-mix itself looks like).
# Preflight (take-preflight.sh) before recording: fresh load, pins, area clean, day + clear sky, katana ready, no crossbow
# equipped anywhere, no fight, open ground at zoom 0 AND at the zoomed-out orbit view; a failed check = RESULT ... FAIL setup.
# Checks: zoomfade-check.py per state (band, hand-head, weapon visible, stretch limits, per-step limb jump, basis).
# Output in <out dir>: <name>-<state>.sheet.jpg (one labelled contact sheet per state), <name>-<state>-c<k>.vmrec.txt,
# <name>-<state>.check.txt, <name>.steps.tsv; last line: RESULT ZOOMFADE-<name> PASS|FAIL <evidence>
OUT=$1; N=$2; BH=${3:-1}; STATES=${4:-ready block swing}
[ -n "$OUT" ] && [ -n "$N" ] && { [ "$BH" = 1 ] || [ "$BH" = 0 ]; } || { echo "usage: fp-zoomfade.sh <out dir> <name> [bandhide 1|0] [states]"; exit 2; }
case "$STATES" in *[!a-z[:space:]]*|"") echo "RESULT ZOOMFADE-$N FAIL setup: states '$STATES' not a word list"; exit 2;; esac
export KAH_OWNER=${KAH_OWNER:-kfp-fixer}
mkdir -p "$OUT" 2>/dev/null; cd "$OUT" 2>/dev/null || { echo "RESULT ZOOMFADE-$N FAIL setup: out dir $OUT not usable"; exit 2; }
SH=Axima; SPOT="-54190 633 4380"
HERE=${CR:-/mnt/c}/KenshiModding/components/KenshiFP; TI=$HERE/tests/ingame
KDIR=${KDIR:-/mnt/d/Steam/steamapps/common/Kenshi}; SHOTS=$KDIR/mods/AutomationHarness/shots
FFX=${FFX:-${CR:-/mnt/c}/Users/Shay/AppData/Local/Microsoft/WinGet/Packages/Gyan.FFmpeg_Microsoft.Winget.Source_8wekyb3d8bbwe/ffmpeg-8.0.1-full_build/bin/ffmpeg.exe}
STEPS=${ZF_STEPS:-"0 0.5 1 1.5 2 2.5 3 3.5 4 4.5 5 5.5 6 6.5 7 7.5 8 8.5 9 9.5 10 11 12 13 14 15 16 17 18 20 22 25"}
ORB=${ZF_ORBIT:-2.36}; CHUNK=${ZF_CHUNK:-11}
A(){ stobe-auto "$@" </dev/null 2>&1; }
fld(){ grep -o " $1=[^ ]*" | head -1 | cut -d= -f2; }
st(){ A fp_vm state | fld state; }
waitst(){ local e=$((SECONDS+$2)); while [ $SECONDS -lt $e ]; do [ "$(st)" = "$1" ] && return 0; sleep 0.2; done; return 1; }
restore(){ A fp_keys release rmb >/dev/null; A fp_keys release lmb >/dev/null; A fp_vm rec off >/dev/null; A speed 1 hold >/dev/null
  A fp_camera bandhide 1 >/dev/null; A fp_camera zoommode switch >/dev/null; A fp_camera orbit 0 >/dev/null; A fp_camera distance 0 >/dev/null; A chatter on >/dev/null; }
fail(){ restore; PF_DONE=1; echo "RESULT ZOOMFADE-$N FAIL $*"; exit 1; }
PF_ROW=ZOOMFADE-$N; PF_ON_FAIL=restore; . $TI/take-preflight.sh
pf_begin "$PF_ROW"   # RESULT guard (shared preflight)
ready(){ [ "$(st)" = ready ] || { [ "$(st)" = holstered ] || { A key_inject r tap 120 >/dev/null; waitst holstered 6; }; A key_inject r tap 120 >/dev/null; waitst ready 6; }; }
# zoom <d>: target d, wait until the applied distance is there (easing; <= 4 s), print applied
zoom(){ local e=$((SECONDS+4)) a; A fp_camera distance "$1" >/dev/null
  while :; do a=$(A fp_camera state | fld applied); awk -v a="${a:-99}" -v d="$1" 'BEGIN{exit !((a-d)^2 < 0.0009)}' && break
    [ $SECONDS -ge $e ] && break; sleep 0.15; done; echo "${a:-?}"; }
# ---- setup: fresh load, pins, daytime, take spot, katana, hostiles, sky (same spot/fixture as fp-e6-strokes.sh)
pf_load
A speed 1 hold >/dev/null; A kill "Hungry Bandit" >/dev/null; A chatter off >/dev/null
A pin Malzin at -53900 633 6850 >/dev/null; A pin Tassilo at -53940 640 6850 >/dev/null; A pin Shay at -53980 640 6850 >/dev/null
A select $SH >/dev/null; A fp_control take >/dev/null
pf_rig; pf_display
pf_clean -54190 4380 6000
pf_day
A teleport $SH $SPOT >/dev/null; sleep 2
for c in $SH Malzin; do A health $c 100 >/dev/null; done
A fp_combat physical >/dev/null; A fp_combat on >/dev/null; A combatmode $SH ranged off >/dev/null
pf_noxbow $SH Malzin Tassilo Shay || pf_fail "$PF_WHY"
A inv $SH | grep -q '"name":"Chisa Katana"' || { A unequip Malzin "Chisa Katana" >/dev/null; A transfer Malzin $SH "Chisa Katana" >/dev/null; A pickup $SH "Chisa Katana" radius 80 >/dev/null; }
A equip $SH "Chisa Katana" >/dev/null; sleep 1
A inv $SH | grep -q '"name":"Chisa Katana","equipped":true' || { pf_melee_arm $SH || pf_fail "$PF_WHY"; }
pf_noxbow $SH Malzin Tassilo Shay || pf_fail "$PF_WHY"
A fp_camera distance 0 >/dev/null; A fp_camera orbit "$ORB" >/dev/null; A fp_camera look 3.14 0.05 >/dev/null
A fp_camera zoommode fade >/dev/null; A fp_camera bandhide "$BH" | grep -q "bandhide=$BH" || pf_fail "fp_camera bandhide $BH refused (build without Z1 band hide?)"
pf_iso; ready; [ "$(st)" = ready ] || pf_fail "katana not ready (state=$(st))"
cl_=$(A fp_vm state | grep -o "class=[a-z0-9]*" | head -1); case "$cl_" in *xbow*|*ranged*|*bow*) A key_inject r tap 120 >/dev/null; pf_fail "drawn weapon $cl_ (crash-safety: sword only)";; esac
pf_nofight
sleep 1; pf_open 2                                                         # zoom 0 view
[ "$(zoom 25)" != "?" ] || pf_fail "fp_camera state gave no applied distance"; A fp_camera bandhide 1 >/dev/null; sleep 1
pf_open 2                                                                  # zoomed-out orbit view (body shown at 25 dm)
A fp_camera bandhide "$BH" >/dev/null; zoom 0 >/dev/null
# ---- take: one sweep per state, rec dumped in chunks of $CHUNK steps (recorder holds 6000 frames)
printf 'state\td\tapplied\tzf\tband_hidden\tvm_state\n' > "$N.steps.tsv"; CK=""
dump(){ local f="vmrec-zf-$N-$1-c$2.txt"; A fp_vm rec off >/dev/null; rm -f "$KDIR/$f"; A fp_vm rec dump "$f" >/dev/null
  local e=$((SECONDS+6)); while [ ! -s "$KDIR/$f" ] && [ $SECONDS -lt $e ]; do sleep 0.3; done
  cp "$KDIR/$f" "$N-$1-c$2.vmrec.txt" 2>/dev/null && rm -f "$KDIR/$f" && echo "$N-$1-c$2.vmrec.txt"; }
for S in $STATES; do
  case $S in ready|block|swing) ;; *) fail "setup: unknown state $S";; esac
  ready; zoom 0 >/dev/null; sleep 0.5; : > "$N-$S.man"; recs=""; k=0; i=0
  [ $S = swing ] && A speed 0.5 >/dev/null
  if [ $S = block ]; then A fp_keys press rmb 20000 >/dev/null; waitst blocking 4 || fail "setup: block did not start (state=$(st))"; sleep 0.6; fi
  A fp_vm rec on >/dev/null
  for d in $STEPS; do
    if [ $i -gt 0 ] && [ $((i % CHUNK)) = 0 ]; then r=$(dump $S $k) || fail "no vmrec dump ($S chunk $k)"; recs+="$r,"; k=$((k+1)); A fp_vm rec on >/dev/null; fi
    [ $S = block ] && A fp_keys press rmb 20000 >/dev/null   # hold refreshed every step (press max 20 s, no release gap)
    i=$((i+1)); ap=$(zoom "$d")
    if [ $S = swing ]; then waitst ready 4; A fp_keys press lmb 60 >/dev/null; sleep 0.55; else sleep 0.45; fi
    V=$(A fp_vm state); zf=$(fld zf <<<"$V"); vs=$(fld state <<<"$V"); bh=$(A fp_camera state | fld band_hidden)
    sn="zf-$N-$S-$i"; A screenshot "$sn" >/dev/null
    printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$S" "$d" "$ap" "$zf" "$bh" "$vs" >> "$N.steps.tsv"
    printf '%s\t%s\t%s\n' "$S bandhide $BH (orbit $ORB)" "d=$d zf=$zf $([ "$bh" = 1 ] && echo hidden) $vs" "$SHOTS/$sn.png" >> "$N-$S.man"
    [ $S = swing ] && { sleep 0.3; waitst ready 5; }
  done
  r=$(dump $S $k) || fail "no vmrec dump ($S chunk $k)"; recs+="$r"; CK+="$S=$recs "
  [ $S = block ] && { A fp_keys release rmb >/dev/null; waitst ready 4; }
  [ $S = swing ] && A speed 1 hold >/dev/null
  zoom 0 >/dev/null
done
restore
pf_game_done
# ---- checks + sheets (game no longer needed)
ok=1; SUM=""; SHEETS=""
for kv in $CK; do S=${kv%%=*}; recs=${kv#*=}
  python3 $TI/zoomfade-check.py "$recs" "$S" "$STEPS" --bandhide "$BH" > "$N-$S.check.txt" 2>&1
  l=$(tail -1 "$N-$S.check.txt"); echo "$l" | grep -q "^zoomfade $S PASS" || ok=0
  SUM+="$S: $(echo "$l" | cut -d' ' -f3- | cut -c1-230); "
  python3 $TI/vm-sheet.py "$N-$S.sheet.jpg" "$N-$S.man" --cols 6 --width 533 >/dev/null 2>&1 && [ -s "$N-$S.sheet.jpg" ] && SHEETS+="$OUT/$N-$S.sheet.jpg " || { ok=0; SUM+="$S sheet missing; "; }
  cut -f3 "$N-$S.man" | while read -r p; do rm -f "$p"; done   # raw PNGs: the sheet keeps them
done
PF_DONE=1; echo "RESULT ZOOMFADE-$N $([ $ok = 1 ] && echo PASS || echo FAIL) bandhide=$BH ${SUM}sheets=${SHEETS% } (detail $OUT/$N-<state>.check.txt)"
