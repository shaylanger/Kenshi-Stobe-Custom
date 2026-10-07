#!/usr/bin/env bash
# fp-manual-ranged.sh: in-game rows R01-R06 + R12 (subset) of the draft manual ranged adapter (COMBAT_TEST_PLAN.md).
# Run in WSL with Kenshi in the world on kah-fpxbow (Axima = squad crossbow user, Skaera = hostile Hungry Bandit).
# Input comes from `fp_combat input <aim> <fire> <reload>` (same controller/native gates as physical input).
# Evidence per shot: the adapter's actual_shots, the gun's loaded count (rangedinfo shots=<n>/<max>) and the harness
# GunClass::shoot counter (`rangedtest <npc> last` shots=), which also sees autonomous AI shots.
# Usage: fp-manual-ranged.sh [shooter] [target] [outdir]. Ends with one `RESULT <row> PASS|FAIL <evidence>` per row.
# Restores: fp_combat off + physical input, FP mode as found, shooter's pin/protect left for the fixture reload.
SH=${1:-Axima}; TG=${2:-Skaera}; OUT=${3:-/tmp/fp-manual-ranged}
mkdir -p "$OUT"; LOG="$OUT/log.txt"; : > "$LOG"
A() { local r; r=$(stobe-auto "$@" 2>&1); echo "> $* | $r" >> "$LOG"; echo "$r"; }
fld() { grep -o "\b$1=[^ ]*" | head -1 | cut -d= -f2; }           # fld <name> < reply
cs() { A fp_combat state | fld "$1"; }                               # adapter state field
loaded() { A rangedinfo "$SH" | grep -o 'shots=[0-9]*' | head -1 | cut -d= -f2; }
hshots() { A rangedtest "$SH" last | grep -o 'shots=[0-9]*' | head -1 | cut -d= -f2; }
bolts() { A inv "$SH" | grep -o '"name":"Bolts[^"]*","count":[0-9]*' | head -1 | sed 's/"name":"//; s/","count":/ x/'; }
inp() { A fp_combat input "$1" "$2" "$3" >/dev/null; }
# waitfor <seconds> <field> <value>: poll the adapter state until field==value
waitfor() { local end=$((SECONDS+$1)); while [ $SECONDS -lt $end ]; do [ "$(cs "$2")" = "$3" ] && return 0; sleep 0.2; done; return 1; }
RESULTS=()
row() { RESULTS+=("RESULT $1 $2 $3"); echo "RESULT $1 $2 $3" >> "$LOG"; }

setup_fail() { echo "RESULT SETUP FAIL $1 log=$LOG"; cleanup; exit 1; }
FP0=$(A fp_state | fld fp_mode)
cleanup() { A fp_combat input 0 0 0 >/dev/null; A fp_combat off >/dev/null; A fp_combat physical >/dev/null
            A fp_mode "$([ "$FP0" = 1 ] && echo on || echo off)" >/dev/null; }
trap cleanup EXIT

# ---- setup checks (no retry loops: a failed setup stops with a reason) ----
A status | grep -q phase=world || setup_fail "not in world"
A where "$SH" | grep -q 'pos=' || setup_fail "shooter $SH not found"
A where "$TG" | grep -q 'pos=' || setup_fail "target $TG not found"
[ "$(A rangedinfo "$SH" | fld bow)" != none ] || setup_fail "$SH has no ranged weapon"
A protect "$SH" on >/dev/null
A pin "$TG" at "$SH" dist 25 face "$SH" >/dev/null
A protect "$TG" on >/dev/null
A select "$SH" >/dev/null; A fp_mode on >/dev/null; sleep 1
A fp_control take >/dev/null
A fp_control state | grep -q "control_ids=.*/$(A where "$SH" | grep -o '#[0-9]*' | tr -d '#')" || setup_fail "fp_control did not take $SH"
# aim the camera at the target: forward = (sin yaw, cos yaw) in x/z, pitch>0 looks down
read -r sx sz <<<"$(A where "$SH" | grep -o 'pos=[^ ]*' | cut -d= -f2 | awk -F, '{print $1, $3}')"
read -r tx tz <<<"$(A where "$TG" | grep -o 'pos=[^ ]*' | cut -d= -f2 | awk -F, '{print $1, $3}')"
YAW=$(awk -v a="$sx" -v b="$sz" -v c="$tx" -v d="$tz" 'BEGIN{printf "%.4f", atan2(c-a, d-b)}')
A fp_camera look "$YAW" 0.02 >/dev/null
A fp_combat on | grep -q requested || setup_fail "fp_combat on refused"
inp 0 0 0; waitfor 3 armed 1 || setup_fail "adapter never armed (enabled=$(cs enabled) fault=$(cs fault))"
[ "$(cs actor)" != 0 ] || setup_fail "adapter has no actor"

# ---- R01 hold aim / release lower ----
inp 1 0 0
if waitfor 5 aimed 1 && waitfor 5 anim_ready 1; then r1a="aimed=1 anim_ready=1"; else r1a="aimed=$(cs aimed) anim_ready=$(cs anim_ready)"; fi
A fp_combat aim > "$OUT/aim.txt"
inp 0 0 0; sleep 1.5
r1b="after_release aimed=$(cs aimed) reloading=$(cs reloading)"
if [[ $r1a == "aimed=1 anim_ready=1" ]] && [ "$(cs aimed)" = 0 ]; then row R01 PASS "$r1a; $r1b"; else row R01 FAIL "$r1a; $r1b"; fi

# shoot: wait until shot-ready, pull the trigger, wait for the adapter's shot counter; prints nothing, sets SHOT=1|0
shoot() { local s0; s0=$(cs actual_shots); SHOT=0; inp 1 0 0; waitfor 8 shot_ready 1 || return 1
          inp 1 1 0; local end=$((SECONDS+3)); while [ $SECONDS -lt $end ]; do [ "$(cs actual_shots)" != "$s0" ] && { SHOT=1; break; }; sleep 0.1; done
          inp "${1:-1}" 0 0; return 0; }
# reload_watch <seconds>: wait while reloading; print the native reload timer the adapter read the frame the reload
# started (last_reload_timer) and the wall seconds waited
reload_watch() { local end=$((SECONDS+$1)) t0=$SECONDS; while [ $SECONDS -lt $end ]; do
          [ "$(cs reloading)" = 0 ] && break; sleep 0.2; done
          echo "$(cs last_reload_timer) $((SECONDS-t0))"; }

# ---- R02 one trigger = one shot (auto reload on: the reload after it is R04) ----
A fp_combat autoreload 1 >/dev/null
L0=$(loaded); H0=$(hshots); S0=$(cs actual_shots); RS0=$(cs reload_starts); B0=$(bolts)
shoot 1; sleep 0.3
H1=$(hshots); S1=$(cs actual_shots); B1=$(bolts)
ev="actual_shots $S0->$S1 harness_shots $H0->$H1 loaded_before=$L0 bolts '$B0'->'$B1'"
if [ "$SHOT" = 1 ] && [ $((S1-S0)) = 1 ] && [ $((H1-H0)) = 1 ] && [ "$L0" = 1 ]; then row R02 PASS "$ev"; else row R02 FAIL "$ev"; fi

# ---- R04 reload: auto reload while aiming the empty weapon, shot refused during it, native duration ----
# The trigger must land inside the reload: R02's evidence reads take several wall seconds, so if its reload has under
# 3 s left, let it finish and fire one fresh shot (re-baselined) whose reload is then tested.
st=$(A fp_combat state); RLX=$(echo "$st" | fld reloading); RLL=$(echo "$st" | fld reload_left); R04_BASE="r02_shot"
if [ "$RLX" != 1 ] || awk -v l="$RLL" 'BEGIN{exit !(l<3)}'; then
  reload_watch 12 >/dev/null
  RS0=$(cs reload_starts); Hb=$(hshots); Sb=$(cs actual_shots)
  shoot 1
  S1=$((Sb+1)); H1=$((Hb+1)); R04_BASE="fresh_shot shot=$SHOT left_before=$RLL"
  [ "$SHOT" = 1 ] || { S1=$Sb; H1=$Hb; }
fi
waitfor 4 reloading 1; RLT=$(cs reload_left)
inp 1 1 0; sleep 0.5; inp 1 0 0                                      # trigger during reload
S3=$(cs actual_shots); H3=$(hshots)
read -r MX DUR <<<"$(reload_watch 30)"
RS1=$(cs reload_starts); L4=$(loaded); R4=$(cs reloading)
ev="base=$R04_BASE reload_starts $RS0->$RS1 reload_left_at_trigger=$RLT native_timer_max=${MX}s wall~${DUR}s fire_during_reload shots $S1->$S3 harness $H1->$H3 loaded_after=$L4 reloading_after=$R4"
if [ $((RS1-RS0)) = 1 ] && [ "$S3" = "$S1" ] && [ "$H3" = "$H1" ] && [ "$L4" = 1 ] && [ "$R4" = 0 ] && awk -v m="$MX" -v t="$RLT" 'BEGIN{exit !(m>=1 && t>=0.5)}'; then row R04 PASS "$ev"; else row R04 FAIL "$ev"; fi
AUTO_MX=$MX

# ---- R03 no duplicate/AI firing: loaded + aimed at an in-range hostile, no trigger, 10 s ----
inp 1 0 0; waitfor 6 shot_ready 1; H5=$(hshots); S5=$(cs actual_shots)
sleep 10
H6=$(hshots); S6=$(cs actual_shots); SUP=$(cs suppressed)
ev="aimed_no_fire_10s harness_shots $H5->$H6 actual $S5->$S6 suppressed=$SUP ($TG hostile at 25 m)"
if [ "$H6" = "$H5" ] && [ "$S6" = "$S5" ]; then row R03 PASS "$ev"; else row R03 FAIL "$ev"; fi

# ---- R05 manual reload (auto reload off) = same native reload ----
A fp_combat autoreload 0 >/dev/null
shoot 1; sleep 2
L7=$(loaded); R7=$(cs reloading); RS2=$(cs reload_starts)                # empty, aimed, must NOT reload by itself
inp 1 0 1; sleep 0.3; inp 1 0 0
waitfor 4 reloading 1; read -r MX DUR <<<"$(reload_watch 30)"
RS3=$(cs reload_starts); L8=$(loaded)
A fp_combat autoreload 1 >/dev/null
ev="auto_reload=0: empty+aimed 2s loaded=$L7 reloading=$R7; reload key: reload_starts $RS2->$RS3 loaded_after=$L8 native_timer_max=${MX}s (auto ${AUTO_MX}s) wall~${DUR}s"
if [ "$SHOT" = 1 ] && [ "$L7" = 0 ] && [ "$R7" = 0 ] && [ $((RS3-RS2)) = 1 ] && [ "$L8" = 1 ] && awk -v a="$MX" -v b="$AUTO_MX" 'BEGIN{d=a-b; if(d<0)d=-d; exit !(d<=0.5 && a>=1)}'; then row R05 PASS "$ev"; else row R05 FAIL "$ev"; fi

# ---- R06 finite ammo: no bolts in the inventory -> no reload, no shot; bolts never created ----
BN0=$(A inv "$SH" | grep -o '"name":"Bolts[^"]*"' | head -1 | sed 's/"name":"//; s/"$//')
BA=$(bolts)
A drop "$SH" "$BN0" all > "$OUT/drop.txt"; sleep 0.5; BN=$(bolts)
shoot 1; sleep 0.5; SHOT1=$SHOT
RS4=$(cs reload_starts); S9=$(cs actual_shots); H9=$(hshots); sleep 4
RS5=$(cs reload_starts); L10=$(loaded); R10=$(cs reloading)
inp 1 1 1; sleep 1; inp 1 0 0; sleep 0.5; S10=$(cs actual_shots); H10=$(hshots); RS6=$(cs reload_starts)
for _ in $(seq 1 40); do A pickup "$SH" "$BN0" radius 10 now >> "$OUT/pickup.txt"; [ "$(bolts)" = "$BA" ] && break; done; BR=$(bolts)
ev="bolts '$BA' -> dropped '${BN:-none}' -> picked '$BR'; last bolt fired=$SHOT1; no bolts: reload_starts $RS4->$RS5->$RS6 loaded=$L10 reloading=$R10 empty trigger+reload: shots $S9->$S10 harness $H9->$H10"
if [ -z "$BN" ] && [ "$SHOT1" = 1 ] && [ "$RS6" = "$RS4" ] && [ "$L10" = 0 ] && [ "$S10" = "$S9" ] && [ "$H10" = "$H9" ] && [ "$BR" = "$BA" ]; then row R06 PASS "$ev"; else row R06 FAIL "$ev"; fi
inp 1 0 0; waitfor 4 reloading 1; reload_watch 30 >/dev/null; inp 0 0 0

# ---- R12 lifecycle subset: pause, FP off, actor swap -> no manual shot, no inherited fire on return ----
A pin "$TG" off >/dev/null; A teleport "$TG" "$SH" dist 400 >/dev/null; A pin "$TG" >/dev/null   # no native AI target
inp 1 0 0; waitfor 8 shot_ready 1; H11=$(hshots); S11=$(cs actual_shots)
A speed 0 >/dev/null; inp 1 1 0; sleep 1; HP=$(hshots); inp 1 0 0; A speed 1 >/dev/null; sleep 1; HP2=$(hshots)
A fp_mode off >/dev/null; sleep 0.5; inp 1 1 0; sleep 1; HF=$(hshots); EN=$(cs actor); A fp_mode on >/dev/null; sleep 1.5; HF2=$(hshots); inp 0 0 0
A select Shay >/dev/null; A fp_control take >/dev/null; sleep 0.5; inp 1 1 0; sleep 1; HS=$(hshots); inp 0 0 0
A select "$SH" >/dev/null; A fp_control take >/dev/null; sleep 1.5; HB=$(hshots); S12=$(cs actual_shots)
ev="harness_shots start=$H11 paused_trigger=$HP unpaused=$HP2 fp_off_trigger=$HF (adapter actor=$EN) fp_on_held=$HF2 other_actor_trigger=$HS back=$HB adapter_shots $S11->$S12"
if [ "$HP" = "$H11" ] && [ "$HP2" = "$H11" ] && [ "$HF" = "$H11" ] && [ "$EN" = 0 ] && [ "$HF2" = "$H11" ] && [ "$HS" = "$H11" ] && [ "$HB" = "$H11" ] && [ "$S12" = "$S11" ]; then
  row R12 PASS "$ev (subset pause/FP-off/actor-swap; UI/KO/save-load/weapon-swap pending)"; else row R12 FAIL "$ev"; fi

printf '%s\n' "${RESULTS[@]}" | while read -r l; do case "$l" in *FAIL*) echo "$l log=$LOG";; *) echo "$l";; esac; done
