#!/usr/bin/env bash
# fp-stealth.sh: in-game FP stealth-attack rows (COMBAT_TEST_PLAN.md "Gate 1c"), KenshiFP 7B8175EF+.
# Sneaking + LMB drawn (melee) on a character that does not perceive the attacker = the game's own sneak knockout
# (TaskType STEALTH_KNOCKOUT 228, the vanilla sneak-mode order). Evidence: `fp_keys state` sneak_* fields
# (sneak_path, sneak_aware, sneak_chance, sneak_result, sneak_attacks), `fp_keys sneak` (crosshair probe: target_aware),
# `senses <target> <player>` (the game's own awareness, independent of the DLL), `detecttime` (sighting reset),
# `where` (KO), `fp_melee state` (native fight), KenshiFP.log `[controls] LMB sneak=1 ...` / `[controls] sneak result=...`.
# Run in WSL with Kenshi in the world on a kah-fpxbow copy (Axima = player, Malzin = mate). Speed 1, FP on, Axima controlled.
# Each row spawns its own target (Hungry Bandit, Tech Hunters, relation NEUTRAL_REL) pinned 1.5 m in front of the player,
# retired after (KO + unload). Player stealth/assassination set to SKILL (default 100) for the row, restored on exit.
# Rows (one `RESULT <row> PASS|FAIL <evidence>` each, log path on FAILs):
#  ST01  sneak + LMB drawn on an unaware target (back turned, sighting reset, DLL probe target_aware=0 before the click):
#        sneak_attacks+1, sneak_path=vanilla_sneak, last_task=228, `[controls] LMB sneak=1 ... target_aware=0 path=vanilla_sneak`
#        in KenshiFP.log, then sneak_result=ko and the target KO (`where`) within ST_WAIT s
#  ST02  sneak + LMB drawn on an aware target (facing the player, probe target_aware=1): no sneak order (sneak_attacks same),
#        sneak_path=engage_aware, last_task=61 (unprovoked engage), native fight on him
#  ST03  not sneaking + LMB drawn on the same kind of unaware target: plain engage (sneak_clicks same, last_task=61), no KO order
# Usage: fp-stealth.sh [player] [mate] [outdir]. Env: SKILL (100), NEUTRAL_REL (20), ST_WAIT (30 s), ROWS (default "ST01 ST02 ST03"),
# KFPLOG (/mnt/d/Steam/steamapps/common/Kenshi/KenshiFP.log). Leaves the fixture changed (spawned NPCs KO/unloaded): reload it after.
SH=${1:-Axima}; MT=${2:-Malzin}; OUT=${3:-/tmp/fp-stealth}
SKILL=${SKILL:-100}; NEUTRAL_REL=${NEUTRAL_REL:-20}; ST_WAIT=${ST_WAIT:-30}; ROWS=${ROWS:-"ST01 ST02 ST03"}
KFPLOG=${KFPLOG:-/mnt/d/Steam/steamapps/common/Kenshi/KenshiFP.log}
mkdir -p "$OUT"; LOG="$OUT/log.txt"; : > "$LOG"
A() { local r; r=$(stobe-auto "$@" 2>&1); echo "> $* | $r" >> "$LOG"; echo "$r"; }
fld() { grep -o "\b$1=[^ ]*" | head -1 | cut -d= -f2; }
fps() { A fp_state | fld "$1"; }
ks() { A fp_keys state | fld "$1"; }
ctl() { A fp_control state | fld "$1"; }
id_of() { A where "$1" | grep -o '#[0-9]*' | head -1 | tr -d '#'; }
pos() { A where "$1" | grep -o 'pos=[^ ]*' | cut -d= -f2 | tr ',' ' '; }
isko() { A where "$1" | grep -qE ' (KO|DEAD)( |$)'; }
ge() { awk -v a="$1" -v b="$2" 'BEGIN{exit !(a!="" && a+0>=b+0)}'; }
want() { case " $ROWS " in *" $1 "*) return 0;; esac; return 1; }
RESULTS=()
row() { RESULTS+=("RESULT $1 $2 $3"); echo "RESULT $1 $2 $3" >> "$LOG"; }
judge() { if [ "$2" = 1 ]; then row "$1" PASS "$3"; else row "$1" FAIL "$3"; fi; }
setup_fail() { for r in "${RESULTS[@]}"; do case "$r" in *FAIL*) echo "$r log=$LOG";; *) echo "$r";; esac; done
  echo "RESULT SETUP FAIL $1 log=$LOG"; exit 1; }
waitf() { local end=$((SECONDS+$1)); shift; while [ $SECONDS -lt $end ]; do "$@" && return 0; sleep 0.2; done; return 1; }
fp_is() { [ "$(fps fp_mode)" = "$1" ]; }
cursor_ok() { [ "$(fps cursor_hidden)" = 1 ]; }
ctl_is() { local ids id; ids=$(ctl control_ids); id=$(id_of "$1"); [ -n "$id" ] && grep -qE "(^|/)$id(/|$)" <<<"$ids"; }
take() { A select "$1" >/dev/null; A fp_control take >/dev/null; A fp_mode on >/dev/null; waitf 4 fp_is 1; A fp_control take >/dev/null; ctl_is "$1"; }
kge() { ge "$(ks "$1")" "$2"; }
kis() { [ "$(ks "$1")" = "$2" ]; }
uname_() { tr ' =' '__' <<<"$1"; }
# urx_: uname_ quoted for grep regexes (live names carry [ ], e.g. Ivor_2_[Hungry_Bandit])
urx_() { uname_ "$1" | sed 's/[][\.*^$]/\\&/g'; }
in_fight() { local s; s=$(A fp_melee state); grep -q 'active=1' <<<"$s" || return 1
  [ -z "$1" ] && { ! grep -q 'target_h=#0/' <<<"$s"; return; }; grep -q "target_h=#$1/" <<<"$s"; }
not_fight() { ! in_fight; }
aim_at() { local sx sy sz tx ty tz c e YP; read -r sx sy sz <<<"$(pos "$SH")"; read -r tx ty tz <<<"$(pos "$1")"
  c=$(A fp_camera state); e=$(fld camera_y <<<"$c"); [ -n "$(fld camera_x <<<"$c")" ] && { sx=$(fld camera_x <<<"$c"); sz=$(fld camera_z <<<"$c"); }
  [ -n "$e" ] || e=$(awk -v y="$sy" 'BEGIN{print y+19}')
  YP=$(awk -v a="$sx" -v b="$sz" -v c="$tx" -v d="$tz" -v ey="$e" -v py="$ty" -v h="$2" \
     'BEGIN{L=sqrt((c-a)^2+(d-b)^2); printf "%.4f %.4f", atan2(c-a, d-b), atan2(ey-(py+h), L)}')
  A fp_camera look $YP >/dev/null; sleep 0.4; }
# weapons (fp-controls.sh): the fixture's player may carry only a crossbow; take the mate's melee weapon then
weapons() { A inv "$SH" | sed 's/},{/}\n{/g' | grep '"weapon_model"' | sed 's/.*"name":"\([^"]*\)".*/\1/' | grep -v -i -x -F "${BOWN:-@@}"; }
arm_melee() { local w r; while IFS= read -r w; do [ -n "$w" ] || continue; r=$(A equip "$SH" "$w")
  case "$r" in equipped*) WEP=$w; return 0;; esac; done <<<"$(weapons)"; return 1; }
bow_now() { A rangedinfo "$SH" | fld bow; }
give_melee() { local w r; [ -n "$(weapons)" ] && return 0
  w=$(A inv "$MT" | sed 's/},{/}\n{/g' | grep '"weapon_model"' | head -1 | sed 's/.*"name":"\([^"]*\)".*/\1/')
  [ -n "$w" ] || return 1
  r=$(A transfer "$MT" "$SH" "$w")
  case "$r" in transferred*) ;; *) r=$(A unequip "$MT" "$w")
    case "$r" in *ground*) r=$(A pickup "$SH" "$w" now);; *) r=$(A transfer "$MT" "$SH" "$w");; esac;; esac
  echo "SETUP give_melee $w from $MT: $(cut -c1-120 <<<"$r")" >> "$LOG"; [ -n "$(weapons)" ]; }
draw_to() { kis drawn "$1" && return 0; A fp_keys press r 120 >/dev/null; waitf 4 kis drawn "$1"; }
stealth_to() { A stealth "$SH" "$([ "$1" = 1 ] && echo on || echo off)" >/dev/null; waitf 3 kis sneak "$1"; }
# probe <field>: fresh DLL crosshair probe (fp_keys sneak), the field of the reply
probe() { A fp_keys sneak >/dev/null; sleep 0.3; A fp_keys sneak show; }

FP0=$(fps fp_mode); PASSIVE0=""; PINNED=""; WEP=""; BOWN=""; BOW_DROPPED=0; ST0=""; AS0=""; SPAWNED=""
cleanup() { A fp_keys reset >/dev/null; A fp_keys focus off >/dev/null; A stealth "$SH" off >/dev/null
            for c in $PINNED; do A pin "$c" off >/dev/null; done
            for c in $SPAWNED; do A ko "$c" 3600 >/dev/null; A unload "$c" >/dev/null; done
            [ -n "$PASSIVE0" ] && A combatmode "$SH" passive "$([ "$PASSIVE0" = 1 ] && echo on || echo off)" >/dev/null
            [ -n "$ST0" ] && A setstat "$SH" stealth "$ST0" >/dev/null; [ -n "$AS0" ] && A setstat "$SH" assassination "$AS0" >/dev/null
            [ -n "$WEP" ] && A unequip "$SH" "$WEP" >/dev/null
            [ "$BOW_DROPPED" = 1 ] && A pickup "$SH" "$BOWN" now >/dev/null; [ -n "$BOWN" ] && A equip "$SH" "$BOWN" >/dev/null
            for c in "$SH" "$MT"; do A protect "$c" off >/dev/null; done
            A speed 1 >/dev/null; A fp_mode "$([ "$FP0" = 1 ] && echo on || echo off)" >/dev/null; }
trap cleanup EXIT

# ---- setup ----
A status | grep -q phase=world || setup_fail "not in world"
for c in "$SH" "$MT"; do A where "$c" | grep -q 'pos=' || setup_fail "$c not found"; done
A fp_keys state | grep -q 'sneak_path=' || setup_fail "KenshiFP has no fp_keys sneak fields (needs 7B8175EF+): $(A fp_keys state | cut -c1-80)"
A fp_keys state | grep -q '\bhook=1\b' || setup_fail "fp_keys hook=0 (playerControl hook not installed)"
# pointers print without 0x on this toolchain; every symbol must be non-zero
grep -aqE 'stealth: sensory=(0x)?[0-9a-fA-F]*[1-9a-fA-F][0-9a-fA-F]* aware=(0x)?[0-9a-fA-F]*[1-9a-fA-F][0-9a-fA-F]* kochance=(0x)?[0-9a-fA-F]*[1-9a-fA-F][0-9a-fA-F]* uncon=(0x)?[0-9a-fA-F]*[1-9a-fA-F][0-9a-fA-F]* dead=(0x)?[0-9a-fA-F]*[1-9a-fA-F][0-9a-fA-F]*' "$KFPLOG" 2>/dev/null \
  || setup_fail "KenshiFP.log has no resolved '[controls] stealth:' symbols line ($(grep -a 'stealth: sensory' "$KFPLOG" 2>/dev/null | tail -1 | cut -c1-140))"
A senses "$MT" "$SH" | grep -q 'aware=' || setup_fail "harness has no senses command"
BOWN=$(A rangedinfo "$SH" | grep -o 'bow=.* has_ammo' | sed 's/^bow=//; s/ has_ammo$//'); [ "$BOWN" = none ] && BOWN=""
. "$(dirname "$0")/fp-ui-guard.sh" 2>/dev/null || { ui_guard_setup() { :; }; ui_clear() { return 0; }; ui_summary() { echo "ui_guard=missing"; }; raid_guard_start() { :; }; }
A speed 1 hold >/dev/null; A fp_move none >/dev/null; A fp_keys reset >/dev/null
for c in "$SH" "$MT"; do A protect "$c" on >/dev/null; done
ui_guard_setup; ui_clear
take "$SH" || setup_fail "could not take $SH ($(A fp_control state | cut -c1-160))"
A fp_camera distance 0 >/dev/null
[ "$(fps cursor_hidden)" = 1 ] || { A fp_keys focus on | grep -q test_focus=1 && echo "SETUP test_focus=1" >> "$LOG"; waitf 3 cursor_ok; }
[ "$(fps cursor_hidden)" = 1 ] || setup_fail "FP cursor not hidden ($(A fp_state | cut -c1-120))"
ST0=$(A stat "$SH" stealth | grep -oE 'base=[0-9.]+' | cut -d= -f2); AS0=$(A stat "$SH" assassination | grep -oE 'base=[0-9.]+' | cut -d= -f2)
A setstat "$SH" stealth "$SKILL" >/dev/null; A setstat "$SH" assassination "$SKILL" >/dev/null
give_melee || echo "SETUP: could not give $SH a melee weapon" >> "$LOG"
if [ "$(bow_now)" != none ]; then r=$(A unequip "$SH" "$(bow_now)"); case "$r" in *ground*) BOW_DROPPED=1;; esac; fi
arm_melee || setup_fail "no melee weapon equips (inv weapons: $(weapons | tr '\n' ';'))"
PASSIVE0=$(A combatmode "$SH" | fld passive); A combatmode "$SH" passive on >/dev/null
# the mate stands 30 m ahead: an unaware target is pinned facing him (back to the player)
A pin "$MT" at "$SH" dist 300 | grep -q '^pinned' && PINNED+=" $MT" || setup_fail "could not pin $MT 30 m ahead of $SH"
echo "SETUP sh=$SH mt=$MT stealth=$ST0 assassination=$AS0 -> $SKILL weapon=$WEP bow='$BOWN' passive0=$PASSIVE0" >> "$LOG"

# spawn_target <row>: TH (ref) / TN (name) of a fresh neutral Hungry Bandit (Tech Hunters), or return 1
spawn_target() { local SP; SP=$(A spawn "Hungry Bandit" "Tech Hunters" near "$SH" dist 40 count 1 2>&1); echo "$1 spawn: $SP" >> "$LOG"
  TH=$(grep -oE '#[0-9]+/[0-9]+' <<<"$SP" | head -1); TN=$(sed 's/^spawned [^:]*: //; s/ #[0-9].*//' <<<"$SP")
  [ -n "$TH" ] || return 1; SPAWNED+=" $TH"; A relation "$TH" "$NEUTRAL_REL" >/dev/null; A hunger "$TH" 300 >/dev/null; }
# place <face npc>: target pinned 1.5 m in front of the player, facing <face>
place() { A pin "$TH" at "$SH" dist 15 face "$1" | grep -q '^pinned' && PINNED+=" $TH"; }
retire() { A ko "$TH" 3600 >/dev/null; A pin "$TH" off >/dev/null; waitf 10 isko "$TH"; A unload "$TH" >/dev/null
  SPAWNED=${SPAWNED/ $TH/}; PINNED=${PINNED/ $TH/}; }
# live_tn: TN = the target's live name. Stobe renames spawned generics ("Ivor 2 [Hungry Bandit]"),
# so the spawn-time name never matched the pick/probe target (m50 5090 K ST01 false setup FAIL).
live_tn() { local W; W=$(A where "$TH" | sed -n 's/^\(.*\) #[0-9][0-9]*\/[0-9][0-9]* .*/\1/p'); [ -n "$W" ] && TN=$W; }
# pick_on: the crosshair pick reports the target (bounded)
pick_on() { local PK; for _ in 1 2 3 4 5 6; do live_tn; A fp_keys pick >/dev/null; sleep 0.3; PK=$(A fp_keys pick show)
  [ "$(fld result <<<"$PK")" = "$(uname_ "$TN")" ] && return 0; done; return 1; }
# unaware_ready: sighting reset (detecttime, 3 s) not seen, game senses aware=0, DLL probe target_aware=0 (bounded, 3 tries)
unaware_ready() { local d s p; for _ in 1 2 3; do live_tn; d=$(A detecttime "$SH" "$TH" timeout 3); s=$(A senses "$TH" "$SH"); p=$(probe)
  UR="detect: seen=$(fld seen <<<"$d") los=$(fld los <<<"$d") | senses: sees=$(fld sees <<<"$s") hears=$(fld hears <<<"$s") aware=$(fld aware <<<"$s") | probe: $(cut -d' ' -f2- <<<"$p")"
  [ "$(fld target <<<"$p")" = "$(uname_ "$TN")" ] && [ "$(fld target_aware <<<"$p")" = 0 ] && [ "$(fld aware <<<"$s")" = 0 ] && return 0; sleep 1; done; return 1; }

# ---- ST01: sneak + LMB on an unaware target = vanilla sneak knockout ----
if want ST01; then ui_clear
  if ! spawn_target ST01; then row ST01 FAIL "setup spawn failed"
  elif ! place "$MT"; then row ST01 FAIL "setup could not pin $TN in front of $SH"; retire
  else sleep 1; draw_to 1; stealth_to 1; aim_at "$TH" 13; waitf 8 not_fight
    if ! pick_on; then row ST01 FAIL "setup crosshair pick never on $TN ($(A fp_keys pick show | cut -c1-120))"
    elif ! unaware_ready; then row ST01 FAIL "setup $TN never unaware of $SH: $UR"
    else KS0=$(A fp_keys state); A0=$(fld sneak_attacks <<<"$KS0"); C0=$(fld sneak_clicks <<<"$KS0")
      A fp_keys press lmb 100 >/dev/null; waitf 3 kge sneak_clicks $((C0+1)); K1=$(A fp_keys state)
      waitf "$ST_WAIT" bash -c "stobe-auto fp_keys state | grep -q 'sneak_result=\(ko\|dead\|failed\|timeout\|lost\)\b'"
      sleep 0.5; K2=$(A fp_keys state); KO=0; isko "$TH" && KO=1
      LL=$(grep -a "\[controls\] LMB sneak=1 target=$(urx_ "$TN") " "$KFPLOG" 2>/dev/null | tail -1 | sed 's/.*LMB sneak=/sneak=/')
      LR=$(grep -a "\[controls\] sneak result=.* target=$(urx_ "$TN") " "$KFPLOG" 2>/dev/null | tail -1 | sed 's/.*sneak result=/result=/')
      ev="pre: $UR | click: sneak_clicks $C0->$(fld sneak_clicks <<<"$K1") sneak_attacks $A0->$(fld sneak_attacks <<<"$K1") path=$(fld sneak_path <<<"$K1") last_task=$(fld last_task <<<"$K1") sneak=$(fld sneak <<<"$K1") drawn=$(fld drawn <<<"$K1") chance=$(fld sneak_chance <<<"$K1") | result=$(fld sneak_result <<<"$K2") elapsed_ms=$(fld sneak_elapsed_ms <<<"$K2") ${TN}_KO=$KO | log: [$LL] [$LR]"
      ok=1; [ "$(fld sneak_attacks <<<"$K1")" = $((A0+1)) ] && [ "$(fld sneak_path <<<"$K1")" = vanilla_sneak ] && [ "$(fld last_task <<<"$K1")" = 228 ] || ok=0
      grep -q 'target_aware=0 .*path=vanilla_sneak task=228' <<<"$LL" || ok=0
      [ "$(fld sneak_result <<<"$K2")" = ko ] && [ $KO = 1 ] && grep -q '^result=ko ' <<<"$LR" || ok=0
      judge ST01 $ok "$ev"; fi
    stealth_to 0; retire; fi; waitf 15 not_fight; fi

# ---- ST02: sneak + LMB on an aware target = normal engage, no sneak order ----
if want ST02; then ui_clear
  if ! spawn_target ST02; then row ST02 FAIL "setup spawn failed"
  elif ! place "$SH"; then row ST02 FAIL "setup could not pin $TN in front of $SH"; retire
  else sleep 1; draw_to 1; stealth_to 1; aim_at "$TH" 13; waitf 8 not_fight; live_tn; ser=$(id_of "$TH")
    AW=""; for _ in $(seq 1 10); do P=$(probe); S=$(A senses "$TH" "$SH")
      AW="probe: $(cut -d' ' -f2- <<<"$P") | senses: sees=$(fld sees <<<"$S") aware=$(fld aware <<<"$S")"
      [ "$(fld target <<<"$P")" = "$(uname_ "$TN")" ] && [ "$(fld target_aware <<<"$P")" = 1 ] && break; AW="NOTAWARE $AW"; sleep 1; done
    if grep -q '^NOTAWARE' <<<"$AW"; then row ST02 FAIL "setup $TN (facing $SH at 1.5 m) never aware of him in 10 s: $AW"
    else KS0=$(A fp_keys state); A0=$(fld sneak_attacks <<<"$KS0"); C0=$(fld sneak_clicks <<<"$KS0"); G0=$(fld engages <<<"$KS0")
      A fp_keys press lmb 100 >/dev/null; waitf 3 kge sneak_clicks $((C0+1)); waitf 8 in_fight "$ser"; FT=$?; K=$(A fp_keys state)
      LL=$(grep -a "\[controls\] LMB sneak=1 target=$(urx_ "$TN") " "$KFPLOG" 2>/dev/null | tail -1 | sed 's/.*LMB sneak=/sneak=/')
      ev="pre: $AW | sneak_clicks $C0->$(fld sneak_clicks <<<"$K") sneak_attacks $A0->$(fld sneak_attacks <<<"$K") path=$(fld sneak_path <<<"$K") engages $G0->$(fld engages <<<"$K") last_task=$(fld last_task <<<"$K") native_fight_on_$(uname_ "$TN")=$((1-FT)) | log: [$LL]"
      ok=1; [ "$(fld sneak_clicks <<<"$K")" = $((C0+1)) ] && [ "$(fld sneak_attacks <<<"$K")" = "$A0" ] && [ "$(fld sneak_path <<<"$K")" = engage_aware ] || ok=0
      [ "$(fld engages <<<"$K")" = $((G0+1)) ] && [ "$(fld last_task <<<"$K")" = 61 ] && [ $FT = 0 ] || ok=0
      grep -q 'target_aware=1 .*path=engage_aware' <<<"$LL" || ok=0
      judge ST02 $ok "$ev"; fi
    stealth_to 0; retire; fi; waitf 20 not_fight; fi

# ---- ST03: not sneaking + LMB on an unaware target = plain engage (no sneak path) ----
if want ST03; then ui_clear
  if ! spawn_target ST03; then row ST03 FAIL "setup spawn failed"
  elif ! place "$MT"; then row ST03 FAIL "setup could not pin $TN in front of $SH"; retire
  else sleep 1; draw_to 1; stealth_to 0; aim_at "$TH" 13; waitf 8 not_fight; live_tn; ser=$(id_of "$TH")
    if ! pick_on; then row ST03 FAIL "setup crosshair pick never on $TN ($(A fp_keys pick show | cut -c1-120))"
    else S=$(A senses "$TH" "$SH"); KS0=$(A fp_keys state); C0=$(fld sneak_clicks <<<"$KS0"); A0=$(fld sneak_attacks <<<"$KS0"); G0=$(fld engages <<<"$KS0")
      A fp_keys press lmb 100 >/dev/null; waitf 3 kge engages $((G0+1)); waitf 8 in_fight "$ser"; FT=$?; K=$(A fp_keys state)
      ev="sneak=$(fld sneak <<<"$KS0") senses_aware=$(fld aware <<<"$S") | sneak_clicks $C0->$(fld sneak_clicks <<<"$K") sneak_attacks $A0->$(fld sneak_attacks <<<"$K") engages $G0->$(fld engages <<<"$K") last_task=$(fld last_task <<<"$K") native_fight_on_$(uname_ "$TN")=$((1-FT))"
      ok=1; [ "$(fld sneak <<<"$KS0")" = 0 ] && [ "$(fld sneak_clicks <<<"$K")" = "$C0" ] && [ "$(fld sneak_attacks <<<"$K")" = "$A0" ] || ok=0
      [ "$(fld engages <<<"$K")" = $((G0+1)) ] && [ "$(fld last_task <<<"$K")" = 61 ] && [ $FT = 0 ] || ok=0
      judge ST03 $ok "$ev"; fi
    retire; fi; waitf 20 not_fight; fi

echo "$(ui_summary)" >> "$LOG"
for r in "${RESULTS[@]}"; do case "$r" in *FAIL*) echo "$r log=$LOG";; *) echo "$r";; esac; done
