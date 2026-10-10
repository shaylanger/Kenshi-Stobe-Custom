#!/bin/bash
# fp-studio-fixture.sh <out dir> [save name kah-fpstudio]   (WSL on the 5090; Kenshi running, harness up; ~3 min)
# Builds the FP "studio" fixture (Speed plan 6, Shay 2026-10-10) from the kah-fpxbow fixture copy (never Shay's saves):
#   open ground  Axima on the VMQUICK open-ground spot (-54100 669 7300, the spot of the lab's body recordings), the
#                spot judged by the lab (pf_open: frames.py openground + cursor + overlay + luma) before saving
#   day          saved at 10:00-10:59 game time, so every take that loads it starts in daylight with >2 h of the
#                10-13 h window left (pf_day stays in the takes as the guard)
#   no raiders   every non-squad NPC within 9000 (90 m: also covers the block-guard spot -54190,4380) of the spot killed (not KO: KO'd raiders wake up), checked by
#                pf_area (3 sampler rounds near=0 down=0 msgs=0) before saving
#   squad        Malzin / Shay / Tassilo parked 4.5 m behind the spot (out of the zoom-0 frame), Axima holding the
#                Chisa Katana and the Oldworld Bow MkI (crossbow) with the crossbow loaded; weapons holstered in the save
#   chatter/name tags  runtime only (not in a save): takes keep `chatter off` + cursor park (pf_open)
# Saves as <save name> (default kah-fpstudio), then copies %LOCALAPPDATA%\kenshi\save\<save name> to
# C:\KenshiTestFixtures\FP-studio (FIXTURES.md "FP-studio"). Last line: RESULT STUDIO-FIXTURE PASS|FAIL <evidence>
# Batch row:  studio | - | Axima | Malzin | 900 | /mnt/c/KenshiModding/components/KenshiFP/tests/ingame/fp-studio-fixture.sh {OUT}/studio
OUT=$1; SAVE=${2:-kah-fpstudio}
[ -n "$OUT" ] || { echo "RESULT STUDIO-FIXTURE FAIL setup: usage fp-studio-fixture.sh <out dir> [save name]"; exit 2; }
export KAH_OWNER=${KAH_OWNER:-take-dryrun}
SH=Axima; SPOT="-54100 669.2 7300"; X=-54100; Z=7300
HERE=/mnt/c/KenshiModding/components/KenshiFP
SAVES=/mnt/c/Users/Shay/AppData/Local/kenshi/save; FIX=/mnt/c/KenshiTestFixtures/FP-studio
A(){ stobe-auto "$@" </dev/null 2>&1; }
restore(){ A chatter on >/dev/null; A fp_keys release rmb >/dev/null; }
PF_ROW=STUDIO-FIXTURE; PF_ON_FAIL=restore; . $HERE/tests/ingame/take-preflight.sh
pf_begin "$PF_ROW"
pf_outdir "$OUT"; cd "$OUT" || pf_fail "cd $OUT"
[ -d "$SAVES/kah-fpxbow" ] || pf_fail "base save kah-fpxbow missing in $SAVES (copy C:\\KenshiTestFixtures\\FP-crossbow there)"
case "$SAVE" in kah-*) ;; *) pf_fail "save name $SAVE must start with kah- (test copies only)";; esac
# ---- base fixture
A load kah-fpxbow | cut -c1-80; sleep 8
for i in $(seq 1 60); do sleep 3; A wait-world | grep -qE "phase=world|ready" && break; done
A status | grep -q phase=world || pf_fail "kah-fpxbow did not reach the world"
A speed 1 hold >/dev/null; A chatter off >/dev/null
A select $SH >/dev/null; A fp_control take >/dev/null
pf_rig; pf_display
# ---- time: 10:xx (50x until 10 h, then 1x); pf_hour = whole hours
h=$(pf_hour)
if [ "$h" -ne 10 ]; then
  A speed 50 hold >/dev/null
  for i in $(seq 1 300); do sleep 1; h=$(pf_hour); [ "$h" = 10 ] && break; done
  A speed 1 hold >/dev/null
fi
TM=$(A time | grep -o 'time=[0-9:]*' | cut -d= -f2)
case "$TM" in 10:[0-5]?) ;; *) pf_fail "game time $TM, wanted 10:00-10:59";; esac
# ---- squad: Axima on the spot, the rest behind it
r=$(A teleport $SH $SPOT); grep -q 'moved=1' <<<"$r" || pf_fail "teleport $SH $SPOT: $(cut -c1-100 <<<"$r")"
for p in "Malzin -53900 633 6850" "Shay -53980 640 6850" "Tassilo -53940 640 6850"; do
  set -- $p; A teleport $1 $2 $3 $4 | grep -q 'moved=1' || pf_fail "teleport $1 $2 $3 $4 failed"; done
sleep 2
# ---- no raiders: kill (not KO) every live non-squad NPC within 9000 of the spot
n=0
{ A chars 9000; for f in "Starving" "Dust Bandits" "Hungry" "Outlaws" "Marauder" "Shinobi"; do A chars 9000 "$f"; done; } 2>/dev/null \
  | sed "s/^[0-9]* within [0-9.]*: //" | sed 's/ | /\n/g' | grep -v "\[Nameless\]\| DEAD" \
  | sed -n 's/.*\(#[0-9]*\/[0-9]*\) .* pos=\([-0-9.]*\),[-0-9.]*,\([-0-9.]*\).*/\1 \2 \3/p' | sort -u > kill.txt
while read -r id x z; do
  d=$(awk -v x=$x -v z=$z -v a=$X -v b=$Z 'BEGIN{printf "%d", sqrt((x-a)^2+(z-b)^2)}'); [ "$d" -lt 9000 ] || continue
  A kill "$id" >/dev/null; n=$((n + 1))
done < kill.txt
echo "killed $n non-squad NPCs within 9000"; sleep 3
pf_area $SH "Malzin|Shay|Tassilo"
# ---- weapons: katana from Malzin to Axima, both equipped, crossbow loaded, then holstered
A unequip Malzin "Chisa Katana" >/dev/null; A inv Malzin | grep -q '"name":"Chisa Katana"' && A transfer Malzin $SH "Chisa Katana" >/dev/null
A inv $SH | grep -q '"name":"Chisa Katana"' || A pickup $SH "Chisa Katana" radius 80 >/dev/null
A equip $SH "Chisa Katana" >/dev/null
A inv $SH | grep -q '"name":"Chisa Katana","count":1,"equipped":true' || pf_fail "Chisa Katana not equipped on $SH: $(A inv $SH | grep -o '"name":"Chisa Katana"[^}]*')"
A inv $SH | grep -q '"name":"Oldworld Bow MkI","count":1,"equipped":true' || pf_fail "crossbow (Oldworld Bow MkI) not equipped on $SH"
A fp_combat physical >/dev/null; A fp_combat on >/dev/null; A combatmode $SH ranged on >/dev/null
pf_weapon crossbow
A key_inject r tap 120 >/dev/null; pf_waitst holstered 6 || pf_fail "weapon would not holster (state=$(pf_st))"
A combatmode $SH ranged off >/dev/null
# ---- open ground on the spot (zoom 0, the take view)
A fp_camera distance 0 >/dev/null; A fp_camera orbit 0 >/dev/null; A fp_camera look 0 0.05 >/dev/null; sleep 1
pf_open 3
# the zoom-25 side view most takes film too (name tags / bark text of the parked squad would show here)
A fp_camera distance 25 >/dev/null; A fp_camera orbit 2.3 >/dev/null; sleep 2; pf_open 2
A fp_camera distance 0 >/dev/null; A fp_camera orbit 0 >/dev/null
pf_area $SH "Malzin|Shay|Tassilo"
# ---- save + copy
TM=$(A time | grep -o 'time=[0-9:]*' | cut -d= -f2)
A save "$SAVE" | cut -c1-80
for i in $(seq 1 40); do sleep 1; A status | grep -q "last_saved=$SAVE\b" && break; done
A status | grep -q "last_saved=$SAVE\b" || pf_fail "save $SAVE not confirmed (status: $(A status | cut -c1-120))"
sleep 5
[ -d "$SAVES/$SAVE" ] || pf_fail "save folder $SAVES/$SAVE missing after save"
restore
pf_game_done   # game part over (save confirmed on disk): run-batch.sh starts the next row while the fixture copy runs
rm -rf "$FIX.new"; cp -r "$SAVES/$SAVE" "$FIX.new" && rm -rf "$FIX" && mv "$FIX.new" "$FIX" || pf_fail "copy to $FIX failed"
pf_result PASS "save=$SAVE time=$TM killed=$n spot=$X,$Z fixture=$FIX files=$(find "$FIX" -type f | wc -l)"
