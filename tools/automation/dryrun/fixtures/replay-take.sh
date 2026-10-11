#!/bin/bash
# replay-take.sh <out dir> <mode>   (dry-run self-test only: tools/automation/dryrun/selftest.sh; never in a real batch)
# A minimal sword take on the kah-fpxbow spot that reproduces one take bug seen on 2026-10-10, so the self-test can prove
# dryrun.sh still FAILs it in seconds (and that the clean mode PASSes):
#   clean     full preflight (pf_day, pf_clean, pf_area, pf_open), labels in step with the state, RESULT line   -> PASS
#   bare      no preflight at all: filmed in whatever world the fixture gives (kfx-b1 night with --fixture night;
#             turret-fp / op-b4 VMQUICK bandits + "X is attacking!" popup with --fixture combat)
#   noresult  clean take that never prints its RESULT line (kfx-b2 T6 f36/take5.sh)
#   lag       "RMB held: block guard" label still claims blocking 2 s after the release (kfx-b7/b8 label lag)
#   popup     pf_open without pf_clean: the combat popup is still on screen (op-b4 VMQUICK sword-z25 tile)
#   early     "RMB held: block guard" stamped 1.5 s before the press (T6 labels stamped early)
#   dialog    (--fixture dialog, DRYRUN_NOREC=1) polls fp_state 60 s: ui_open=1 for 6 s+ = stalled in an NPC
#             conversation (5090 20-rg04 M08 Dust Bandit); passes only with the batch dialog guard (tools/automation/dialog-guard.sh)
#   actor     (--fixture raider-on-mate, DRYRUN_NOREC=1) control handed to Axima, whom a Dust Bandit fights (5090 33-rg04
#             M08-ACTOR): pf_calm clears the raider, ai_refused stays flat -> PASS; actor-bare without pf_calm -> FAIL
#   rmb-bare  (--fixture rmb-blocked, DRYRUN_NOREC=1) the old K01 control: native RMB at the unchecked yaw, crosshair on
#             the mate -> no walk -> FAIL (5090 31-rg01 K01); fp-controls.sh ROWS=K01 in the same world -> PASS
#   noiso     R sent with key_inject without pf_iso and no ready check (b4080c xbow takes filmed holstered: the 4080
#             launch leaves input isolation off); run with --rig 4080
#   (fixture stall: a 1.5 s hole in the take sampler, blkH; caught by takecheck cover, before filming by pf_latency)
OUT=$1; MODE=${2:-clean}; ROW=REPLAY-$MODE
for d in /mnt/c /c; do [ -f $d/KenshiModding/tools/automation/rig-env.sh ] && { . $d/KenshiModding/tools/automation/rig-env.sh; break; }; done
HERE=${CR:-/mnt/c}/KenshiModding/components/KenshiFP; L=${CR:-/mnt/c}/KenshiModding/Kenshi-Automation-Harness/tools/animlab
FFX=${FFX:-/mnt/c/Users/Shay/AppData/Local/Microsoft/WinGet/Packages/Gyan.FFmpeg_Microsoft.Winget.Source_8wekyb3d8bbwe/ffmpeg-8.0.1-full_build/bin/ffmpeg.exe}
SH=Axima; SPOT="-54190 633 4380"; N=rp-$MODE
A(){ stobe-auto "$@" </dev/null 2>&1; }
PF_ROW=$ROW; . $HERE/tests/ingame/take-preflight.sh
[ "$MODE" = noresult ] || pf_begin "$ROW"
pf_outdir "$OUT"; cd "$OUT" || exit 2
if [ "$MODE" = dialog ]; then
  # fixture dialog (5090 20-rg04 M08): no load here (row.sh loaded the save; run-batch.sh / row.sh run the dialog guard
  # around the row). A row that only polls KenshiFP: an open conversation keeps ui_open=1 (every click refused); a streak
  # of 6 s or more = the row would have stalled
  A select $SH >/dev/null; st=0; mx=0
  for _ in $(seq 1 60); do sleep 1
    if A fp_state | grep -q '\bui_open=1\b'; then st=$((st + 1)); [ $st -gt $mx ] && mx=$st; else st=0; fi; done
  if [ $mx -ge 6 ]; then pf_result FAIL "stalled: ui_open=1 for ${mx}s ($(A dialog | tr -d '\r' | head -1)), every click refused"
  else pf_result PASS "longest ui_open=1 streak ${mx}s (dialog guard closed the conversations)"; fi
  exit 0
fi
if [ "$MODE" = actor ] || [ "$MODE" = actor-bare ]; then
  # fixture raider-on-mate (5090 33-rg04 M08-ACTOR 2026-10-11): control handed to a squad member a raider is fighting;
  # the global ai_refused then counts HER refused AI swings. actor = pf_calm first (clears the raider), actor-bare = none
  A select Malzin >/dev/null; A fp_control take >/dev/null; A fp_combat on >/dev/null; sleep 1
  A select $SH >/dev/null; A fp_control take >/dev/null; sleep 1
  if [ "$MODE" = actor ]; then pf_calm $SH Skaera || pf_fail "$PF_WHY"; fi
  r0=$(A fp_melee state | grep -o 'ai_refused=[0-9]*' | cut -d= -f2); sleep 6; r1=$(A fp_melee state | grep -o 'ai_refused=[0-9]*' | cut -d= -f2)
  o=$(A fp_melee state $SH | grep -o ' active=[^ ]* \| target_h=[^ ]*' | tr -d '\n')
  if [ "$r1" = "$r0" ]; then pf_result PASS "ai_refused $r0->$r1 with $SH controlled ($o)"
  else pf_result FAIL "ai_refused rose $r0->$r1 with $SH controlled: her own fight ($o)"; fi
  exit 0
fi
if [ "$MODE" = rmb-bare ]; then
  # fixture rmb-blocked (5090 31-rg01 K01 2026-10-11): the old K01 order, native RMB control at the unchecked camera yaw
  # with no open-ground check; the crosshair is on the mate there, so the control walks nowhere (fp-controls.sh K01 now
  # finds open ground with fp_keys pick and proves the control moves first: selftest ctl-k01)
  A select $SH >/dev/null; A fp_control take >/dev/null; y=$(A fp_camera state | grep -o '\byaw=[^ ]*' | head -1 | cut -d= -f2)
  A fp_camera look "${y:-0}" 0.5 >/dev/null; p0=$(A where $SH | grep -o 'pos=[^ ]*' | cut -d= -f2)
  A fp_keys swallow off >/dev/null; A fp_keys native rmb 20 >/dev/null; sleep 4; A fp_keys swallow on >/dev/null
  p1=$(A where $SH | grep -o 'pos=[^ ]*' | cut -d= -f2)
  m=$(awk -v a="$p0" -v b="$p1" 'BEGIN{split(a,p,",");split(b,q,",");printf "%.2f", sqrt((q[1]-p[1])^2+(q[3]-p[3])^2)}')
  if awk -v m="$m" 'BEGIN{exit !(m >= 10)}'; then pf_result PASS "control moved=$m"
  else pf_result FAIL "control (swallow off) native RMB did not move $SH (moved=$m, no open-ground check)"; fi
  exit 0
fi
T0=0; lab(){ echo "$(awk -v a="$(date +%s.%N)" -v b="$T0" 'BEGIN{printf "%.2f", a-b}') $*" >> "$N.lab"; }
A load kah-fpxbow >/dev/null; A wait-world >/dev/null
A speed 1 hold >/dev/null; A chatter off >/dev/null; A select $SH >/dev/null; A fp_control take >/dev/null
A teleport $SH $SPOT >/dev/null; A mouse_inject at $(( ${RES_W:-1600} - 5 )) 4 >/dev/null
A fp_combat physical >/dev/null; A fp_combat on >/dev/null; A combatmode $SH ranged off >/dev/null
case $MODE in
  bare) ;;
  popup) pf_open 2 ;;
  *) pf_day; pf_clean ${SPOT%% *} ${SPOT##* } 6000; pf_area $SH "Malzin|Tassilo|Shay" ;;
esac
A unequip Malzin "Chisa Katana" >/dev/null; A transfer Malzin $SH "Chisa Katana" >/dev/null
A equip $SH "Chisa Katana" >/dev/null
if [ "$MODE" = noiso ]; then A key_inject r tap 120 >/dev/null; sleep 1; else pf_ready; fi
case $MODE in bare|noiso) ;; *) pf_open 2;; esac
: > "$N.lab"
# recorder stopped with "q" through a plain pipe at the end label (a native ffmpeg ignores q on an MSYS fifo, 4080)
{ while [ ! -f "$N.stop" ]; do sleep 0.2; done; echo q; } | "$FFX" -hide_banner -loglevel error -y -f gdigrab -draw_mouse 0 -framerate 30 -t 60 -i "$PF_TITLE" -c:v libx264 "$N.mp4" & FP=$!
rm -f "$N.stop"
. $HERE/animlab/take-sample.sh
T0=$(date +%s.%N); take_sample_start "$N.ev.txt" "$T0" $SH "Malzin|Tassilo|Shay"; sleep 1
lab "Ready stance (katana drawn)"; sleep 2
if [ "$MODE" = early ]; then lab "RMB held: block guard"; sleep 1.5; A fp_keys press rmb 2500 >/dev/null; sleep 0.5
else lab "RMB held: block guard"; A fp_keys press rmb 2500 >/dev/null; fi
if [ "$MODE" = lag ]; then sleep 4.5; else sleep 2.0; lab "RMB released: back to ready"; sleep 2.5; fi
lab end; touch "$N.stop"; take_sample_stop; wait $FP; rm -f "$N.stop"
TC=$(python3 $L/takecheck.py --labels "$N.lab" --ev "$N.ev.txt" --rules $HERE/animlab/take-rules.txt --video "$N.mp4" 2>&1 | tail -1)
[ "$MODE" = noresult ] && exit 0
ok=PASS; echo "$TC" | grep -q PASS || ok=FAIL
pf_result $ok "takecheck=[$TC]"
