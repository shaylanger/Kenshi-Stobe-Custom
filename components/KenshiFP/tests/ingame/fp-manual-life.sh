#!/usr/bin/env bash
# fp-manual-life.sh: in-game R12 lifecycle rows of the manual ranged adapter that fp-manual-ranged.sh's subset
# (pause/FP-off/actor swap) leaves open: UI, KO, weapon swap, game speed, save/load (COMBAT_TEST_PLAN.md R12).
# Run with Kenshi in the world on kah-fpxbow right after load (Axima = squad crossbow user in ranged combat with
# Skaera = hostile Hungry Bandit). Input: `fp_combat input <aim> <fire> <reload>`.
# Evidence: harness GunClass::shoot counter (`rangedtest <npc> last` shots=, sees every real shot incl. AI ones),
# the adapter's actual_shots/why/aimed/armed, the KO/UI state from `fp_combat state`.
# Rule under test: an interruption yields to native and a trigger held through it never fires on return (no
# inherited fire); a fresh trigger after return fires exactly once.
# Usage: fp-manual-life.sh [shooter] [target] [outdir]. Ends with one `RESULT <row> PASS|FAIL <evidence>` per row.
SH=${1:-Axima}; TG=${2:-Skaera}; OUT=${3:-/tmp/fp-manual-life}
mkdir -p "$OUT"; LOG="$OUT/log.txt"; : > "$LOG"
A() { local r; r=$(stobe-auto "$@" 2>&1); echo "> $* | $r" >> "$LOG"; echo "$r"; }
fld() { grep -o "\b$1=[^ ]*" | head -1 | cut -d= -f2; }
cs() { A fp_combat state | fld "$1"; }
# mshots: the adapter's own (manual) shots. While the adapter yields (UI/KO) the native AI may shoot: allowed, so
# "no shot while interrupted" counts manual shots only (4080 batch 3: an AI shot during the UI failed R12-UI)
mshots() { cs actual_shots; }
hshots() { A rangedtest "$SH" last | grep -o 'shots=[0-9]*' | head -1 | cut -d= -f2; }
inp() { A fp_combat input "$1" "$2" "$3" >/dev/null; }
waitfor() { local end=$((SECONDS+$1)); while [ $SECONDS -lt $end ]; do [ "$(cs "$2")" = "$3" ] && return 0; sleep 0.2; done; return 1; }
RESULTS=()
row() { RESULTS+=("RESULT $1 $2 $3"); echo "RESULT $1 $2 $3" >> "$LOG"; }
setup_fail() { echo "RESULT SETUP FAIL $1 log=$LOG"; exit 1; }
FP0=$(A fp_state | fld fp_mode)
cleanup() { A fp_combat input 0 0 0 >/dev/null; A fp_combat off >/dev/null; A fp_combat physical >/dev/null; A speed 1 >/dev/null
            A fp_mode "$([ "$FP0" = 1 ] && echo on || echo off)" >/dev/null; }
trap cleanup EXIT
# take: select + FP + take control of the shooter, camera at the target
take() { A select "$SH" >/dev/null; A fp_mode on >/dev/null; sleep 1; A fp_control take >/dev/null
  read -r sx sz <<<"$(A where "$SH" | grep -o 'pos=[^ ]*' | cut -d= -f2 | awk -F, '{print $1, $3}')"
  read -r tx tz <<<"$(A where "$TG" | grep -o 'pos=[^ ]*' | cut -d= -f2 | awk -F, '{print $1, $3}')"
  A fp_camera look "$(awk -v a="$sx" -v b="$sz" -v c="$tx" -v d="$tz" 'BEGIN{printf "%.4f", atan2(c-a, d-b)}')" 0.02 >/dev/null; }
# fresh_shot [ready_s]: release, aim, wait shot-ready (default 10 s), one trigger; echoes the harness shot delta (expect 1)
fresh_shot() { local h0; inp 0 0 0; sleep 0.5; inp 1 0 0; waitfor "${1:-10}" shot_ready 1 || { echo "not_ready/anim=$(cs anim_ready)/ammo=$(cs ammo)/reloading=$(cs reloading)/why=$(cs why)"; return; }
  h0=$(hshots); inp 1 1 0; sleep 1.5; inp 1 0 0; local d=$(( $(hshots) - h0 ))
  [ "$d" = 0 ] && { echo "0/rej=$(cs last_reject)/rej_why=$(cs last_reject_why)/anim_sup=$(cs anim_suppressed)"; return; }; echo "$d"; }
ready_held() { inp 0 0 0; sleep 0.5; inp 1 0 0; waitfor 10 shot_ready 1 || return 1; return 0; }

# ---- setup ----
A status | grep -q phase=world || setup_fail "not in world"
for c in "$SH" "$TG"; do A where "$c" | grep -q 'pos=' || setup_fail "$c not found"; done
BOW=$(A rangedinfo "$SH" | grep -o 'bow=.* has_ammo' | sed 's/^bow=//; s/ has_ammo$//')
[ -n "$BOW" ] && [ "$BOW" != none ] || setup_fail "$SH has no ranged weapon"
A protect "$SH" on >/dev/null; A protect "$TG" on >/dev/null
A pin "$TG" at "$SH" dist 25 face "$SH" >/dev/null
take
A fp_control state | grep -q "control_ids=.*/$(A where "$SH" | grep -o '#[0-9]*' | tr -d '#')" || setup_fail "fp_control did not take $SH"
A fp_combat autoreload 1 >/dev/null
A fp_combat on | grep -q requested || setup_fail "fp_combat on refused"
inp 0 0 0; waitfor 3 armed 1 || setup_fail "adapter never armed (why=$(cs why))"
ready_held || setup_fail "never shot-ready (why=$(cs why))"

# ---- R12-UI: inventory open while aiming, then trigger pressed + held -> no shot, why=ui_open; close with the trigger
#      still held -> none (pressing first would fire legally before the UI opens: 4080 batch 2) ----
H0=$(mshots); A click INV >/dev/null; waitfor 3 why ui_open; inp 1 1 0; sleep 1.5; W=$(cs why); HU=$(mshots)
A click INV >/dev/null; sleep 2; HC=$(mshots); W2=$(cs why); FS=$(fresh_shot)
ev="ui: why=$W shots_during=$((HU-H0)) after_close_held=$((HC-HU)) why_after=$W2 fresh_trigger_shots=$FS"
if [ "$W" = ui_open ] && [ "$HU" = "$H0" ] && [ "$HC" = "$HU" ] && [ "$FS" = 1 ]; then row R12-UI PASS "$ev"; else row R12-UI FAIL "$ev"; fi

# ---- R12-KO: knocked out while aiming, trigger pressed + held while down -> no shot, none inherited on waking; fresh
#      fires. protect clears a KO at once, so it is off while down. ----
#      knockoutForceTimer only sets the medical KO timer; the game's medical update turns it into the KO later (>3 s on
#      the 4080 batch 14: the trigger then went into a still-conscious shooter = a legal shot). So wait until the adapter
#      reports why=down (KO 10 s, wait <=15 s) BEFORE pressing; never down -> the row fails as setup, no press.
ready_held; H0=$(mshots); A protect "$SH" off >/dev/null; A ko "$SH" 10 >/dev/null; KOW=0
if waitfor 15 why down; then inp 1 1 0; sleep 1; W=$(cs why); HK=$(mshots); else
  KOW="never_down/why=$(cs why)/unconscious=$(cs unconscious)/ko_timer=$(cs ko_timer)"; W=$(cs why); HK=$(mshots); fi
for _ in $(seq 1 60); do [ "$(cs why)" != down ] && break; inp 1 1 0; sleep 0.5; done
sleep 2; HW=$(mshots); W2=$(cs why); A protect "$SH" on >/dev/null; take; FS=$(fresh_shot)
ev="ko: setup=$KOW why=$W shots_down=$((HK-H0)) after_wake_held=$((HW-HK)) why_after=$W2 fresh_trigger_shots=$FS"
if [ "$KOW" = 0 ] && [ "$W" = down ] && [ "$HK" = "$H0" ] && [ "$HW" = "$HK" ] && [ "$FS" = 1 ]; then row R12-KO PASS "$ev"; else row R12-KO FAIL "$ev"; fi

# ---- R12-SWAP: crossbow unequipped mid-aim, then trigger held -> adapter leaves ranged (why=melee), no manual shot;
#      re-equipped with the trigger still held -> none; fresh trigger fires. unequip drops the bow when the inventory
#      is full (4080 batch 3): pick it up again ----
ready_held; H0=$(mshots); A unequip "$SH" "$BOW" >/dev/null; waitfor 3 why melee; inp 1 1 0; sleep 1.5; W=$(cs why); HS=$(mshots)
A equip "$SH" "$BOW" | grep -q ERROR && { A pickup "$SH" "$BOW" now >/dev/null; sleep 1; A equip "$SH" "$BOW" >/dev/null; }
inp 1 1 0; sleep 2; HE=$(mshots); W2=$(cs why); take; FS=$(fresh_shot)
ev="swap: unequipped why=$W shots=$((HS-H0)) re-equipped held_shots=$((HE-HS)) why=$W2 fresh_trigger_shots=$FS fault=$(cs fault)"
if [ "$W" = melee ] && [ "$HS" = "$H0" ] && [ "$HE" = "$HS" ] && [ "$FS" = 1 ] && [ "$(cs fault)" = 0 ]; then row R12-SWAP PASS "$ev"; else row R12-SWAP FAIL "$ev"; fi

# ---- R12-SPEED: at speed 3 one trigger = one shot; the native reload runs in game time (shorter real time) ----
A speed 3 >/dev/null; FS=$(fresh_shot); t0=$SECONDS; for _ in $(seq 1 40); do [ "$(cs reloading)" = 0 ] && break; sleep 0.25; done
RT=$((SECONDS-t0)); LT=$(cs last_reload_timer); A speed 1 >/dev/null
ev="speed3: trigger_shots=$FS reload_real_s=$RT native_timer=$LT"
if [ "$FS" = 1 ] && awk -v r="$RT" -v t="$LT" 'BEGIN{exit !(t>0 && r<=t)}'; then row R12-SPEED PASS "$ev"; else row R12-SPEED FAIL "$ev"; fi

# ---- R12-LOAD: save mid-aim, load it with the trigger held -> no inherited shot, adapter re-arms, fresh fires.
#      The loaded crossbow comes back unloaded (4080 batch 6: ammo=0 after load), so the fresh shot needs the draw,
#      the full native reload (~6 s at this skill) and the aim settle: 10 s timed out right as the aim settled ----
ready_held; A save kah-fp-r12 >/dev/null; sleep 2; inp 1 1 0; A load kah-fp-r12 >/dev/null; A wait-world >/dev/null
H0=$(mshots); sleep 3; HL=$(mshots); W=$(cs why); AR=$(cs armed); take; FS=$(fresh_shot 30)
ev="load: held_shots_after_load=$((HL-H0)) why=$W armed=$AR fresh_trigger_shots=$FS reload_starts=$(cs reload_starts) fault=$(cs fault)"
if [ "$HL" = "$H0" ] && [ "$FS" = 1 ] && [ "$(cs fault)" = 0 ]; then row R12-LOAD PASS "$ev"; else row R12-LOAD FAIL "$ev"; fi

for r in "${RESULTS[@]}"; do case "$r" in *FAIL*) echo "$r log=$LOG";; *) echo "$r";; esac; done
