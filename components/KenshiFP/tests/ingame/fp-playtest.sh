#!/usr/bin/env bash
# fp-playtest.sh: KenshiFP Gate 6 rows (Shay's 2026-10-07 playtest, COMBAT_TEST_PLAN.md "Gate 6", PT01-PT22) as ONE
# compound in-game run: the rows chain the way Shay broke them (FP off/on toggles, weapon swaps, control switches
# between them). Fixes: /root/KenshiFP 74a58ab..74b3408.
# Input goes through the PHYSICAL paths (harness input isolation: `mouse_inject` / `key_inject` = DirectInput/OIS +
# GetAsyncKeyState, what a real mouse/keyboard feeds), so the native select/command queue and the combat adapter's
# physical input are what's tested; `fp_combat input` (injection) only for PT15's shots.
# Evidence: `fp_keys state` (mouse_keys_swallowed ctx_hold_opens ctx_tap_opens lmb_why lmb_*_refused r_path mmb_objects
# mmb_self hud_* carried down speed_*), `fp_keys ctl` (Control button), `fp_combat state` (why wih draws sheathes
# reload_starts spread_*), `fp_control state` (controlled/inspected), `where`/`hp`/`runspeed`/`walktime`, `ui`, and
# KenshiFP.log lines written since the test started.
# Run in WSL with Kenshi in the world on a kah-fpxbow copy (Axima = crossbow player, Malzin = mate, Skaera = hostile).
# Rows (one `RESULT PTxx PASS|FAIL <evidence>` each, log path on FAILs):
#  PT25      (runs first: LOADS the save) load with FP on, no toggle: RMB tap+hold on the ground with the mate selected =
#            mate (unpinned, standing still first) does not move and a swallow counter rises; drawn at load: once as
#            loaded (RMB = aim), then holstered by a physical R; MMB on the mate selects; same after a Left Alt free
#            cursor; no "FP mode toggled" line
#  PT22+PT07 holstered physical LMB on the mate: selection/inspected unchanged, mouse_keys_swallowed rises, no stats
#            window (`ui lbSkills`), no "opened the clicked member's details" log line
#  PT06      holstered physical RMB HOLD on the mate: ctx_hold_opens+1, ctx_freed=1, menu still open after the release
#  PT20      in that menu: `fp_keys ctl` shows Control for the mate; PHYSICAL click on the game's own 'Control' option
#            (`ui control`, not KFPControlBtn) -> switches+1 via=menu, controlled = mate; back again the same way (RMB tap
#            from the mate's body on the player, physical click)
#  PT24      holstered RMB tap on the mate: Control is a native option (`fp_keys ctl` native=1 native_hooks=7 shown=1
#            native_target=mate; `ui control` = a 'Control' widget in the column (same x, width) of the other options;
#            no visible KFPControlBtn); physical click -> Control -> mate via=menu, menu closed (menu_vis=0)
#  PT21      mate selected (physical MMB), RMB tap + hold on the ground: mate (unpinned) does not move, swallowed rises
#  PT19      mate selected, physical MMB on the sky: mmb_self+1, last_select = player, inspected = controlled
#  PT08      next to a building: physical MMB on it -> mmb_objects+1; holstered RMB tap on it -> ctx menu on it
#  PT09      after 3 more FP off/on cycles + a control switch: hook=1 fault=0 swallow=1; MMB still selects the mate,
#            RMB tap still opens the menu, LMB still doesn't select
#  PT04      FP walk/run speed = vanilla: same char, spot and axis; vanilla run order -> physical W held in FP
#            (gait=run), vanilla walk order -> W in FP (gait=walk); steady `where` rate FP vs vanilla within PT04_TOL
#            (5%), the char's order handed back after each hold (fp_move state mv_so/gait_restores); game speed 1
#  PT05      evidence: physical LMB click on TimeSpeedButton2 (x1 while at x1), RTS and FP free cursor: speed_clicks rise,
#            speed_peak_click / long frames / [speed] log lines; FAIL only if the spike shows (peak > SPIKE_MAX)
#  PT23      Shay's speed steps x0.5 -> 1x -> speed up, physical clicks on TimeSpeedButton3/2/4 then keys 2/1/3, RTS and FP:
#            game-time rate per real second around every input <= SPIKE_MAX x the speed, speed up after 1x = x2, speed_guard=1
#  PT11      bow only, holstered, manual combat physical: RMB hold -> nothing drawn (drawn=0 wih=0), combat draws and
#            reload_starts unchanged, fp_combat why=ranged_holstered
#  PT18      bow drawn by physical R: no reload without aim; aim (RMB held) + R = holster only (reload_starts, ammo same)
#  PT15      3 manual shots (injected aim/fire): spread_n +3, spread_cone = formula from spread_skill/spread_per,
#            spread_off <= cone, "[combat] spread" log lines
#  PT02      sword only (bow unequipped), physical R: drawn=1 wih!=0 r_path!=unarmed, log "R draw ... path="
#  PT01+PT03 R draw: label "ready" shown <1.5 s then hidden; RMB block / LMB swing: hud_shown=0, hud_silent rises
#  PT10      sword drawn: physical LMB on the mate in reach -> lmb_why=squad, no engage/fight, mate hp same; on a far NPC
#            (pinned 8 m) -> lmb_why=far, no engage, no fight
#  PT12      sword + bow equipped, sword drawn: RMB hold = melee block (ranged=0, why=melee_in_hands), combat sheathes /
#            reload_starts / wih unchanged; LMB = free swing, no shot
#  PT16      KO'd player lifted by the mate (LIFT_PERSON_PLAYER_ORDER): fp_keys carried=1 down=1, log "[down] carried=1"
# Not here: PT13/PT14/PT17 (viewmodel: coordinator), PT15 head-hit rate vs vanilla (needs a target series: visual/
# balance call), PT16 camera look (screenshot).
# Usage: fp-playtest.sh [player] [mate] [hostile] [outdir] (defaults: $PLAYER/$MATE or Axima/Malzin, Skaera,
# /tmp/fp-playtest). Env: ROWS (space/comma list), KFPLOG, STILL_MAX (3), SPIKE_MAX (1.5), PT04_TOL (0.05), FAR_NPC, SAVE (PT25: save to
# load, default the current one from `status`).
# Leaves the fixture changed (player KO'd/carried, Skaera KO'd, items moved): reload it after.
SH=${1:-${PLAYER:-Axima}}; MT=${2:-${MATE:-Malzin}}; TG=${3:-${HOSTILE:-Skaera}}; OUT=${4:-/tmp/fp-playtest}
KDIR=/mnt/d/Steam/steamapps/common/Kenshi; KFPLOG=${KFPLOG:-$KDIR/KenshiFP.log}
STILL_MAX=${STILL_MAX:-3}; SPIKE_MAX=${SPIKE_MAX:-1.5}; FAR_NPC=${FAR_NPC:-}
ROWS=${ROWS:-"PT25 PT22 PT07 PT06 PT20 PT24 PT21 PT19 PT08 PT09 PT04 PT05 PT23 PT11 PT18 PT15 PT02 PT01 PT03 PT10 PT12 PT16"}; ROWS=${ROWS//,/ }
mkdir -p "$OUT"; LOG="$OUT/log.txt"; : > "$LOG"
A() { local r; r=$(stobe-auto "$@" 2>&1); echo "> $* | $r" >> "$LOG"; echo "$r"; }
note() { echo "$*" >> "$LOG"; }
fld() { grep -o "\b$1=[^ ]*" | head -1 | cut -d= -f2; }
cam() { A fp_camera state | fld "$1"; }
ctl() { A fp_control state | fld "$1"; }
fps() { A fp_state | fld "$1"; }
ks() { A fp_keys state | fld "$1"; }
cs() { A fp_combat state | fld "$1"; }
id_of() { A where "$1" | grep -o '#[0-9]*' | head -1 | tr -d '#'; }
pos() { A where "$1" | grep -o 'pos=[^ ]*' | cut -d= -f2 | tr ',' ' '; }
isko() { A where "$1" | grep -qE ' (KO|DEAD)( |$)'; }
notko() { ! isko "$1"; }
d2() { awk -v a="$1" -v b="$2" 'BEGIN{split(a,p," ");split(b,q," ");printf "%.2f", sqrt((q[1]-p[1])^2+(q[3]-p[3])^2)}'; }
lt() { awk -v a="$1" -v b="$2" 'BEGIN{exit !(a!="" && a+0<b+0)}'; }
ge() { awk -v a="$1" -v b="$2" 'BEGIN{exit !(a!="" && a+0>=b+0)}'; }
inc() { awk -v a="$1" -v b="$2" 'BEGIN{exit !(a!="" && b!="" && b+0>a+0)}'; }     # inc <before> <after>: rose
want() { case " $ROWS " in *" $1 "*) return 0;; esac; return 1; }
waitf() { local end=$((SECONDS+$1)); shift; while [ $SECONDS -lt $end ]; do "$@" && return 0; sleep 0.2; done; return 1; }
uname_() { tr ' =' '__' <<<"$1"; }
kfplines() { tail -n +"$((LN0+1))" "$KFPLOG" 2>/dev/null | tr -d '\r'; }       # KenshiFP.log since the test start
RESULTS=()
# ---- world raids (m53: a Dust Bandits squad attacked Axima/Malzin mid-run: stagger flips in PT01/PT03, PT10 fight=1,
# PT15/PT18 native ranged combat). Raiders within 1500 are knocked out at setup and every 10 s (as stobe-fight-lib.sh
# calm_raiders; the fixture hostile $TG and the PT10 far NPC are kept), and a row during which a non-squad character
# attacked the squad (stobe.log `[EVENT] combat: X -> <squad>`) is `FAIL setup: hostile ... attacking`, never judged.
SLOG=${SLOG:-$KDIR/RE_Kenshi/mods/Stobe/stobe.log}; STOBELIB=${STOBELIB:-/mnt/c/KenshiModding/tests/ingame/stobe/stobe-fight-lib.sh}
[ -r "$STOBELIB" ] && eval "$(grep -E '^RAID_(RE|FILTER)=' "$STOBELIB")"
RAID_RE=${RAID_RE:-Band of Bones|Kral.s Chosen|Dust Bandits|Hungry Bandits|Starving Bandits|Hill Marauders|Black Dragon Ninjas|Berserkers|Cannibals|Fogmen}
RAID_FILTER=${RAID_FILTER:-[band of bones]|[kral|[dust bandits]|[hungry bandits]|[starving bandits]|[hill marauders]|[black dragon ninjas]|[berserkers]|[cannibals]|[fogmen]}
KEEP=""; KEEPN=(); RAIDG=""; SL0=0; SHN=""; MTN=""   # KEEPN: grep -e args for kept attackers ($TG, PT10 far NPC)
sweep() { local lines h n=0
  lines=$(stobe-auto chars 1500 "$RAID_FILTER" 2>/dev/null | sed 's/^[0-9]* within [0-9.]*: //' | tr '|' '\n' | sed 's/^ *//' \
    | grep -E "\[(${RAID_RE})\]" | grep -v -E ' (KO|DEAD)( |$)' | grep -v -E "^(${SH}|${MT}) #")
  for h in $(grep -oE '#[0-9]+/[0-9]+' <<<"$lines"); do case " $KEEP " in *" $h "*) continue;; esac
    stobe-auto ko "$h" 21600 >/dev/null 2>&1 && n=$((n+1)); done; echo "$n"; }
slog_n() { [ -r "$SLOG" ] && wc -l < "$SLOG" || echo 0; }
# hostile_hit: the last `combat: X -> <player|mate>` since the previous row by anyone outside the squad / KEEP names
hostile_hit() { [ -r "$SLOG" ] && [ -n "$SHN" ] || return 0
  tail -n +"$((SL0+1))" "$SLOG" 2>/dev/null | tr -d '\r' | grep -a -F -e "-> $SHN (" -e "-> $MTN (" | grep -a 'EVENT\] combat: ' \
    | grep -a -v -F -e "combat: $SHN (" -e "combat: $MTN (" "${KEEPN[@]}" | tail -1 | sed 's/.*combat: //' | cut -c1-110; }
row() { local res=$2 ev=$3 hh; hh=$(hostile_hit)
  case "$ev" in setup:*) ;; *) [ -n "$hh" ] && { res=FAIL; ev="setup: hostile attacking the squad during the row ($hh) | $ev"; };; esac
  RESULTS+=("RESULT $1 $res $ev"); echo "RESULT $1 $res $ev" >> "$LOG"; SL0=$(slog_n); }
judge() { if [ "$2" = 1 ]; then row "$1" PASS "$3"; else row "$1" FAIL "$3"; fi; }
finish() { for r in "${RESULTS[@]}"; do case "$r" in *FAIL*) echo "$r log=$LOG";; *) echo "$r";; esac; done; }
# setup_fail <reason>: every wanted row not yet reported gets `FAIL setup: <reason>`
setup_fail() { local r; for r in $ROWS; do printf '%s\n' "${RESULTS[@]}" | grep -q "^RESULT $r " || row "$r" FAIL "setup: $1"; done; finish; exit 1; }
# rows_fail <reason> <rows...>: the listed wanted rows fail on a setup reason
rows_fail() { local why=$1 r; shift; for r in "$@"; do want "$r" && row "$r" FAIL "setup: $why"; done; }

# ---- physical input (input isolation) ----
mclick() { A mouse_inject "$1" click "${2:-80}" >/dev/null; sleep "$(awk -v m="${2:-80}" 'BEGIN{printf "%.2f", (m+250)/1000}')"; }
mdown() { A mouse_inject "$1" down >/dev/null; }
mup() { A mouse_inject "$1" up >/dev/null; }
rkey() { A key_inject r tap 120 >/dev/null; sleep 0.35; }
altkey() { A key_inject 0xa4 tap 120 >/dev/null; sleep 0.4; }      # Left Alt = KenshiFP free-cursor toggle

# ---- view / control ----
fp_is() { [ "$(fps fp_mode)" = "$1" ]; }
mode() { A fp_mode "$1" >/dev/null; waitf 4 fp_is "$([ "$1" = on ] && echo 1 || echo 0)"; }
ctl_is() { local ids id; ids=$(ctl control_ids); id=$(id_of "$1"); [ -n "$id" ] && grep -qE "(^|/)$id(/|$)" <<<"$ids"; }
take() { A select "$1" >/dev/null; A fp_control take >/dev/null; mode on; A fp_control take >/dev/null; waitf 4 ctl_is "$1"; }
cursor_ok() { [ "$(fps cursor_hidden)" = 1 ]; }
look() { A fp_camera look "$1" "${2:-0}" >/dev/null; sleep 0.3; }
SKY=-0.9
sky() { look "$(cam yaw)" "$SKY"; }
# aim_pt <viewer> <x y z> <height dm>: FP camera from the eye at a world point + height; aim_at <viewer> <npc> <height>
aim_pt() { local V=$1 sx sy sz tx ty tz c e YP; read -r sx sy sz <<<"$(pos "$V")"; read -r tx ty tz <<<"$2"
  c=$(A fp_camera state); e=$(fld camera_y <<<"$c"); [ -n "$(fld camera_x <<<"$c")" ] && { sx=$(fld camera_x <<<"$c"); sz=$(fld camera_z <<<"$c"); }
  [ -n "$e" ] || e=$(awk -v y="$sy" 'BEGIN{print y+19}')
  YP=$(awk -v a="$sx" -v b="$sz" -v c="$tx" -v d="$tz" -v ey="$e" -v py="$ty" -v h="$3" \
     'BEGIN{L=sqrt((c-a)^2+(d-b)^2); printf "%.4f %.4f", atan2(c-a, d-b), atan2(ey-(py+h), L)}')
  A fp_camera look $YP >/dev/null; sleep 0.4; }
aim_at() { aim_pt "$1" "$(pos "$2")" "$3"; }
# pick_on <viewer> <npc>: aim until the crosshair pick reports the npc (bounded: heights 13 10 7, 2 tries each)
pick_on() { local H; for H in 13 10 7; do for _ in 1 2; do aim_at "$1" "$2" "$H"; A fp_keys pick >/dev/null; sleep 0.3
  PK=$(A fp_keys pick show); [ "$(fld result <<<"$PK")" = "$(uname_ "$(live_name "$2")")" ] && return 0; done; done; return 1; }
live_name() { local n; n=$(A where "$1" | sed -n 's/^\(.*\) #[0-9][0-9]*\/[0-9][0-9]* .*/\1/p' | head -1); echo "${n:-$1}"; }
menu_close() { [ "$(fps free)" = 1 ] && A fp_state free off >/dev/null; sleep 0.3; }
toggles() { local i; for i in $(seq 1 "$1"); do mode off; sleep 0.5; mode on; sleep 0.5; done; }
in_fight() { A fp_melee state | grep -q 'active=1' && ! A fp_melee state | grep -q 'target_h=#0/'; }
not_fight() { ! in_fight; }
kis() { [ "$(ks "$1")" = "$2" ]; }
kge() { ge "$(ks "$1")" "$2"; }
csis() { [ "$(cs "$1")" = "$2" ]; }
csge() { ge "$(cs "$1")" "$2"; }

# ---- equipment (as fp-controls.sh: the fixture player carries a crossbow only; melee comes from the mate) ----
weapons() { A inv "$SH" | sed 's/},{/}\n{/g' | grep '"weapon_model"' | sed 's/.*"name":"\([^"]*\)".*/\1/' | grep -v -i -x -F "${BOWN:-@@}"; }
# bow_now: the full bow name (`rangedinfo` prints `bow=<name with spaces> has_ammo=...`; m53: `fld bow` cut it to
# "Oldworld" and every later unequip/pickup/equip by name missed)
bow_now() { local r; r=$(A rangedinfo "$SH"); case "$r" in *" bow=none"*) echo none;; *" bow="*) sed -n 's/.* bow=\(.*\) has_ammo=.*/\1/p' <<<"$r" | head -1;; *) echo none;; esac; }
# href <unequip reply>: the item's `#serial/index` (pickup by handle: exact, any distance)
href() { local i s; i=$(grep -o 'h\.index=[0-9]*' <<<"$1" | head -1 | cut -d= -f2); s=$(grep -o 'h\.serial=[0-9]*' <<<"$1" | head -1 | cut -d= -f2)
  [ -n "$i" ] && [ -n "$s" ] && echo "#$s/$i"; }
arm_melee() { local w r; while IFS= read -r w; do [ -n "$w" ] || continue; r=$(A equip "$SH" "$w")
  case "$r" in equipped*) WEP=$w; return 0;; esac; done <<<"$(weapons)"; return 1; }
GIVEN=""
give_melee() { local w r; [ -n "$(weapons)" ] && return 0
  w=$(A inv "$MT" | sed 's/},{/}\n{/g' | grep '"weapon_model"' | head -1 | sed 's/.*"name":"\([^"]*\)".*/\1/')
  [ -n "$w" ] || { note "SETUP give_melee: $MT has no melee weapon either"; return 1; }
  r=$(A transfer "$MT" "$SH" "$w")
  case "$r" in transferred*) ;; *) r=$(A unequip "$MT" "$w")
    case "$r" in *ground*) r=$(A pickup "$SH" "$w" now);; *) r=$(A transfer "$MT" "$SH" "$w");; esac;; esac
  note "SETUP give_melee $w from $MT: $(cut -c1-120 <<<"$r")"; [ -n "$(weapons)" ] && GIVEN=$w; }
# bow_off: unequip the bow. The fixture player's main inventory holds no long weapon (m53: bow and katana both went
# "-> ground"), and the mate's back slot has her own bow, so a dropped bow stays on the ground next to the player
# (BOW_DROPPED=1, handle BOWREF; harness f4ab9f6+ remembers unequip drops and scans CROSSBOW items for pickup)
BOW_DROPPED=0; BOWREF=""
bow_off() { local r; [ "$(bow_now)" = none ] && return 0; r=$(A unequip "$SH" "$BOWN")
  case "$r" in *"-> ground"*) BOW_DROPPED=1; BOWREF=$(href "$r"); note "SETUP bow on the ground next to $SH ($BOWREF)";; esac
  [ "$(bow_now)" = none ]; }
bow_back() { [ "$(bow_now)" != none ]; }
# bow_on: pickup by handle (`now` = giveItem: the game puts it on the free back slot = equipped), else equip by name
bow_on() { bow_back && return 0; [ -n "$BOWN" ] || return 1
  if [ "$BOW_DROPPED" = 1 ]; then note "SETUP bow pickup: $(A pickup "$SH" "${BOWREF:-$BOWN}" now | cut -c1-140)"
    waitf 15 bow_back && { BOW_DROPPED=0; return 0; }; fi
  A equip "$SH" "$BOWN" | grep -q '^equipped' && BOW_DROPPED=0; bow_back; }
draw_to() { kis drawn "$1" && return 0; rkey; waitf 4 kis drawn "$1"; }

# ---- restore on exit ----
FP0=""; DIST0=""; AR0=""; PASSIVE0=""; RANGED0=""; PINNED=""; WEP=""; BOWN=""; ISO_SET=0; LN0=0
cleanup() { A mouse_inject right up >/dev/null; A mouse_inject left up >/dev/null; A fp_move none >/dev/null
  A fp_keys reset >/dev/null; A fp_keys swallow on >/dev/null
  A fp_combat input 0 0 0 >/dev/null; A fp_combat physical >/dev/null; [ -n "$AR0" ] && A fp_combat autoreload "$AR0" >/dev/null
  [ "$(fps free)" = 1 ] && A fp_state free off >/dev/null
  for c in $PINNED; do A pin "$c" off >/dev/null; done
  [ -n "$PASSIVE0" ] && A combatmode "$SH" passive "$([ "$PASSIVE0" = 1 ] && echo on || echo off)" >/dev/null
  [ -n "$RANGED0" ] && A combatmode "$SH" ranged "$([ "$RANGED0" = 1 ] && echo on || echo off)" >/dev/null
  [ -n "$RAIDG" ] && kill "$RAIDG" 2>/dev/null
  # the melee weapon goes back to the mate (an unequip with no room drops it: she picks it up by handle)
  local wr=""; [ -n "$WEP" ] && wr=$(A unequip "$SH" "$WEP"); [ -n "$BOWN" ] && bow_on >/dev/null
  if [ -n "$GIVEN" ]; then case "$wr" in *"-> ground"*) A pickup "$MT" "$(href "$wr")" now >/dev/null;; *) A transfer "$SH" "$MT" "$GIVEN" >/dev/null;; esac; fi
  for c in "$SH" "$MT"; do A protect "$c" off >/dev/null; done
  A select "$SH" >/dev/null; A fp_control take >/dev/null
  A fp_camera distance "${DIST0:-0}" >/dev/null; A speed 1 >/dev/null
  [ -n "$FP0" ] && A fp_mode "$([ "$FP0" = 1 ] && echo on || echo off)" >/dev/null
  [ "$ISO_SET" = 1 ] && A input_isolation off >/dev/null; }
trap cleanup EXIT

# ---- setup (bounded checks) ----
A status | grep -q phase=world || setup_fail "not in world"
for c in "$SH" "$MT"; do A where "$c" | grep -q 'pos=' || setup_fail "$c not found"; done
[ -r "$KFPLOG" ] || setup_fail "KenshiFP.log not readable at $KFPLOG (set KFPLOG=)"
LN0=$(wc -l < "$KFPLOG")
K=$(A fp_keys state)
grep -q 'speed_now=' <<<"$K" && grep -q 'mmb_self=' <<<"$K" || setup_fail "KenshiFP fp_keys state has no Gate 6 fields (needs 74b3408+): $(cut -c1-80 <<<"$K")"
grep -q '\bhook=1\b' <<<"$K" || setup_fail "fp_keys hook=0 (playerControl hook not installed)"
A fp_keys ctl | grep -q '^ctl shown=' || setup_fail "fp_keys ctl missing (needs 968a5f6+)"
A fp_combat state | grep -q 'spread_n=' || setup_fail "fp_combat state has no spread_n (needs 095837f+)"
if ! A input_isolation status | grep -q 'isolation=on'; then A input_isolation on >/dev/null; ISO_SET=1
  A input_isolation status | grep -q 'isolation=on' || setup_fail "input isolation would not turn on (mouse_inject/key_inject need it)"; fi
# ---- PT25: Shay's steps: load the save while FP is on (direct_control_default: the loaded squad starts in FP), NO FP
# toggle, then the mouse: RMB tap + hold on the ground with the mate selected (mate must not move), MMB on the mate
# (must select). Then the same after a Left Alt tap (free cursor, what the 2026-10-08 log showed 7 s after his load):
# RMB on the ground under the free cursor = no walk order, Left Alt again, MMB selects. No "FP mode toggled" line.
if want PT25; then SAVE=${SAVE:-$(A status | fld save)}; OK=1; EV="save=$SAVE"
  RES=$(sed -n 's/^Video Mode=\([0-9]*\) x \([0-9]*\).*/\1 \2/p' "$KDIR/kenshi.cfg" | head -1); read -r SW SHH <<<"${RES:-1920 1080}"
  A fp_mode on >/dev/null; sleep 0.5; L25=$(wc -l < "$KFPLOG"); A load "$SAVE" >/dev/null; sleep 5; stobe-auto wait-world 240 >/dev/null 2>&1; sleep 3
  if ! A status | grep -q phase=world || ! waitf 20 fp_is 1; then row PT25 FAIL "setup: after load $SAVE: $(A status | cut -c1-80) fp_mode=$(fps fp_mode) (direct_control_default=1 should start FP)"
  else waitf 6 cursor_ok; HC=$(ctl controlled); MTN25=$(live_name "$MT"); SMT=$(id_of "$MT")
    TOG=$(tail -n +"$((L25+1))" "$KFPLOG" | tr -d '\r' | grep -c 'FP mode toggled')
    EV+=" fp_mode=1 controlled=$HC cursor_hidden=$(fps cursor_hidden) free=$(ks free) load_resets=$(ks free_load_resets) toggles_since_load=$TOG"
    [ "$TOG" = 0 ] || OK=0
    ctl_is "$MT" && { OK=0; EV+=" setup: $MT is the controlled char"; }
    # m63: the save loads with the crossbow DRAWN (RMB = aim, not a ground click) and Malzin still walking after the load
    # (where samples moved ~45 u before any input): both phases ran on an invalid setup. Now: drawn at load -> one
    # phase as loaded (look_drawn), then holster with a physical R (no FP toggle) for the ground RMB (look); the mate is
    # pinned next to the player, unpinned and must stand still (2 samples 1 s apart < 1 u, max 8 s) before the RMB.
    DRAWN25=$(ks drawn); EV+=" drawn_at_load=$DRAWN25"; PH25="look free"; [ "$DRAWN25" = 1 ] && PH25="look_drawn look free"
    for ph in $PH25; do
      [ $ph = look ] && [ "$(ks drawn)" = 1 ] && { draw_to 0 || { OK=0; EV+=" | look: physical R did not holster (drawn=$(ks drawn))"; continue; }; }
      [ $ph = free ] && { altkey; waitf 3 kis free 1 || { OK=0; EV+=" | free: Left Alt did not free the cursor (free=$(ks free))"; continue; }
                          A mouse_inject at $((SW/2)) $((SHH*7/10)) >/dev/null; sleep 0.3; }
      A pin "$MT" at "$SH" dist 25 face "$SH" >/dev/null; sleep 1; A pin "$MT" off >/dev/null; PINNED=${PINNED/ $MT/}; A select "$MT" >/dev/null
      ST=0; for _ in 1 2 3 4 5 6 7 8; do Q0=$(pos "$MT"); sleep 1; lt "$(d2 "$Q0" "$(pos "$MT")")" 1 && { ST=1; break; }; done
      # m64: right after the load (crossbow drawn) her AI kept wandering (8.46 u/s): settle her with a real HOLD_POSITION
      # AI order (a player RMB move order would replace it, so the no-walk assertion stays the same), bounded 12 s more
      SET="unpin"; if [ $ST = 0 ]; then SET="hold($(A order "$MT" HOLD_POSITION | cut -c1-40))"
        for _ in $(seq 12); do Q0=$(pos "$MT"); sleep 1; lt "$(d2 "$Q0" "$(pos "$MT")")" 1 && { ST=1; break; }; done; fi
      if [ $ST = 0 ]; then OK=0; EV+=" | $ph: setup: $MT never stood still after unpin + HOLD_POSITION ($(d2 "$Q0" "$(pos "$MT")") u/s)"; continue; fi
      EV+=" | $ph: settled_by=$SET"
      [ $ph != free ] && look "$(cam yaw)" 0.45
      # m65: the weapon drawn in the save was sheathed by the char's AI while the mate settled (drawn=0 at the RMB):
      # look_drawn redraws it with a physical R and must have drawn=1 at the RMB, else it is the 'look' phase again
      if [ $ph = look_drawn ] && ! kis drawn 1; then draw_to 1 || { OK=0; EV+=" $ph: setup: physical R did not draw (drawn=$(ks drawn))"; continue; }; EV+=" redrawn_by_R=1"; fi
      P0=$(pos "$MT"); K0=$(A fp_keys state); mclick right 150; sleep 0.4; mdown right; sleep 1.2; mup right; sleep 3
      K=$(A fp_keys state); DM=$(d2 "$P0" "$(pos "$MT")")
      SW0=$(( $(fld rmb_swallowed <<<"$K0") + $(fld mouse_keys_swallowed <<<"$K0") )); SW1=$(( $(fld rmb_swallowed <<<"$K") + $(fld mouse_keys_swallowed <<<"$K") ))
      EV+=" $MT still, selected, RMB tap+hold on the ground (drawn=$(fld drawn <<<"$K0")): moved=$DM rmb_swallowed $(fld rmb_swallowed <<<"$K0")->$(fld rmb_swallowed <<<"$K") mouse_keys_swallowed $(fld mouse_keys_swallowed <<<"$K0")->$(fld mouse_keys_swallowed <<<"$K") rmb_free_swallowed $(fld rmb_free_swallowed <<<"$K0")->$(fld rmb_free_swallowed <<<"$K") ctx_why=$(fld ctx_why <<<"$K")"
      lt "$DM" "$STILL_MAX" && [ "$SW1" -gt "$SW0" ] || OK=0   # the RMB arrived (a swallow counter rose) and gave no walk order
      [ $ph = look_drawn ] && [ "$(fld drawn <<<"$K0")" != 1 ] && { OK=0; EV+=" look_drawn: weapon not drawn at the RMB"; }
      [ $ph = look_drawn ] && continue
      [ $ph = free ] && { altkey; waitf 3 kis free 0 || { OK=0; EV+=" free stuck on"; A fp_state free off >/dev/null; }; waitf 4 cursor_ok; }
      menu_close
      A pin "$MT" at "$SH" dist 25 face "$SH" | grep -q '^pinned' && PINNED+=" $MT"; sleep 1
      if pick_on "$SH" "$MT"; then M0=$(ks mmb_selects); mclick middle 80; waitf 3 kge mmb_selects $((M0+1)); SEL=$(ks last_select)
        EV+=" MMB on $MT: mmb_selects $M0->$(ks mmb_selects) last_select=$SEL"; [ "$SEL" = "$(uname_ "$MTN25")" ] || OK=0
      else OK=0; EV+=" MMB: crosshair pick never on $MT"; fi
      A select "$SH" >/dev/null; done
    tail -n +"$((L25+1))" "$KFPLOG" | tr -d '\r' | grep -E '\[control|\[controls\]|\[input\]|\[ui\]' | head -60 > "$OUT/pt25-load.txt"
    judge PT25 $OK "$EV log=$OUT/pt25-load.txt"; fi; fi
FP0=$(fps fp_mode); DIST0=$(cam target); AR0=$(cs auto_reload)
BOWN=$(A rangedinfo "$SH" | grep -o 'bow=.* has_ammo' | sed 's/^bow=//; s/ has_ammo$//'); [ "$BOWN" = none ] && BOWN=""
A speed 1 hold >/dev/null; A fp_move none >/dev/null; A fp_keys reset >/dev/null; A fp_keys swallow on >/dev/null
for c in "$SH" "$MT"; do A protect "$c" on >/dev/null; done
PASSIVE0=$(A combatmode "$SH" | fld passive); A combatmode "$SH" passive on >/dev/null
TGH=""; if A where "$TG" | grep -q 'pos='; then TGH=$(A where "$TG" | grep -oE '#[0-9]+/[0-9]+' | head -1)
  A pin "$TGH" at "$SH" dist 600 >/dev/null && PINNED+=" $TGH"; KEEP+=" $TGH"; KEEPN+=(-e "combat: $(live_name "$TGH") ("); fi
RK=$(sweep); note "SETUP raid sweep: knocked out $RK raiders within 1500 (kept:$KEEP)"; [ "$RK" -gt 0 ] 2>/dev/null && sleep 3
take "$SH" || setup_fail "could not take $SH ($(A fp_control state | cut -c1-160))"
A fp_camera distance 0 >/dev/null
waitf 4 cursor_ok || setup_fail "FP cursor not hidden ($(A fp_state | cut -c1-120)): look mode needed for the mouse rows"
H0=$(ctl controlled); HOME=$(pos "$SH"); MTN=$(live_name "$MT"); SHN=$(live_name "$SH")
A pin "$MT" at "$SH" dist 25 face "$SH" | grep -q '^pinned' && PINNED+=" $MT" || setup_fail "could not pin $MT in front of $SH"
sleep 1; draw_to 0 || setup_fail "$SH weapon would not holster"
note "SETUP sh=$SH($SHN) mt=$MT($MTN) tg=$TG$TGH bow='$BOWN' auto_reload=$AR0 home=$HOME controlled=$H0 iso_set=$ISO_SET kfplog_from=$LN0"
( while sleep 10; do kill -0 $$ 2>/dev/null || exit 0; n=$(sweep); [ "$n" = 0 ] || echo "RAID sweep $(date +%H:%M:%S): knocked out $n" >> "$LOG"; done ) </dev/null >/dev/null 2>&1 &
RAIDG=$!; SL0=$(slog_n)

# chain step: FP off/on twice before the first rows (Shay: controls broke after a toggle)
toggles 2; take "$SH" >/dev/null

# ---- PT22 + PT07: holstered physical LMB on the mate: no select, no stats window ----
if want PT22 || want PT07; then menu_close; A select "$SH" >/dev/null; sleep 0.3
  if ! pick_on "$SH" "$MT"; then rows_fail "crosshair pick never on $MT ($(cut -c1-120 <<<"$PK"))" PT22 PT07
  else I0=$(ctl inspected); K0=$(A fp_keys state); mclick left 80; sleep 0.6; K=$(A fp_keys state); I1=$(ctl inspected)
    UIS=$(A ui lbskills | grep -c 'lbSkills'); OPN=$(kfplines | grep -c "opened the clicked member's details")
    ev="inspected $I0->$I1 last_select $(fld last_select <<<"$K0")->$(fld last_select <<<"$K") mouse_keys_swallowed $(fld mouse_keys_swallowed <<<"$K0")->$(fld mouse_keys_swallowed <<<"$K") lmb_swallowed $(fld lmb_swallowed <<<"$K0")->$(fld lmb_swallowed <<<"$K") drawn=$(fld drawn <<<"$K") stats_widgets=$UIS details_log=$OPN"
    ok=1; [ "$I1" = "$I0" ] && [ "$(fld last_select <<<"$K")" = "$(fld last_select <<<"$K0")" ] || ok=0
    { inc "$(fld mouse_keys_swallowed <<<"$K0")" "$(fld mouse_keys_swallowed <<<"$K")" || inc "$(fld lmb_swallowed <<<"$K0")" "$(fld lmb_swallowed <<<"$K")"; } || ok=0
    want PT07 && judge PT07 $ok "$ev"
    ok2=1; [ "$UIS" = 0 ] && [ "$OPN" = 0 ] && [ "$I1" = "$I0" ] || ok2=0; want PT22 && judge PT22 $ok2 "$ev"; fi; fi

# ---- PT06: holstered RMB HOLD on the mate opens the menu; its own release keeps it open ----
MENU_ON_MT=0
if want PT06 || want PT20; then menu_close; draw_to 0
  if ! pick_on "$SH" "$MT"; then rows_fail "crosshair pick never on $MT" PT06
  else K0=$(A fp_keys state); mdown right; sleep 0.9; K1=$(A fp_keys state); mup right; sleep 0.8; K2=$(A fp_keys state); FR=$(fps free)
    # the GAME's menu must still be open after the release (m53: ctx_freed/free stayed 1 but no Control offer came:
    # KenshiFP flags alone don't show the menu); `fp_keys ctl` menu_vis = the game's ContextMenu visible byte,
    # menu_widgets = the menu widgets' own visible flags (KenshiFP PT06 diag build+)
    CT=$(A fp_keys ctl); MV=$(fld menu_vis <<<"$CT"); MW=$(fld menu_widgets <<<"$CT")
    MOPEN=1; if [ -n "$MV" ]; then { [ "$MV" = 1 ] || { [ -n "$MW" ] && [ "$MW" != 0 ] && [ "$MW" != -1 ]; }; } || MOPEN=0; fi
    ev="menu_open_after_release=$MOPEN (menu_vis=${MV:-n/a} menu_widgets=${MW:-n/a} ctl_offers=$(fld offers <<<"$CT")) ctx_hold_opens $(fld ctx_hold_opens <<<"$K0")->$(fld ctx_hold_opens <<<"$K1") tap_opens $(fld ctx_tap_opens <<<"$K0")->$(fld ctx_tap_opens <<<"$K2") ctx_freed held=$(fld ctx_freed <<<"$K1") released=$(fld ctx_freed <<<"$K2") free=$FR last_target=$(fld last_target <<<"$K1") log_hold=$(kfplines | grep -c 'RMB context menu .* via=hold')"
    K3=$(A fp_keys state); ev="$ev diag[ctx_hook=$(fld ctx_hook <<<"$K3") keep=$(fld ctx_keep <<<"$K2")->$(fld ctx_keep <<<"$K3") closes=$(fld ctx_closes <<<"$K1")->$(fld ctx_closes <<<"$K3") where=$(fld ctx_close_where <<<"$K3") reshow_blocked=$(fld ctx_reshow_blocked <<<"$K3") game_shows=$(fld ctx_game_shows <<<"$K3") hides=$(fld ctx_game_hides <<<"$K3") hide_rva=$(fld ctx_hide_rva <<<"$K3") reshow_rva=$(fld ctx_reshow_rva <<<"$K3") upd_hook=$(fld ctx_upd_hook <<<"$K3") upd_calls=$(fld ctx_upd_calls <<<"$K3") upd_fed=$(fld ctx_upd_fed <<<"$K1")->$(fld ctx_upd_fed <<<"$K3") upd_req=$(fld ctx_upd_req <<<"$K3")]"   # KenshiFP 21532ae closer diag (m55: menu closed ~2 frames after open)
    ok=1; [ "$(fld ctx_hold_opens <<<"$K1")" = $(( $(fld ctx_hold_opens <<<"$K0") + 1 )) ] && [ "$(fld ctx_freed <<<"$K1")" = 1 ] && [ "$(fld ctx_freed <<<"$K2")" = 1 ] && [ "$FR" = 1 ] && [ $MOPEN = 1 ] || ok=0
    [ "$(fld last_target <<<"$K1")" = "$(uname_ "$MTN")" ] || ok=0
    [ $ok = 1 ] && MENU_ON_MT=1; want PT06 && judge PT06 $ok "$ev"; fi; fi

# ---- PT20: Control button in the menu on a squad mate; switch there and back ----
# ctl_menu <viewer> <target>: holstered RMB tap on the target from the viewer's body; 0 = Control offered for it
ctl_menu() { menu_close; draw_to 0; pick_on "$1" "$2" || return 1; CTL_DRAWN=$(ks drawn); mclick right 150; waitf 3 bash -c "stobe-auto fp_keys ctl | grep -q 'shown=1'"; }
# ctl_opt: the game's own menu option captioned exactly 'Control' (KenshiFP PT24 native option, never the KFPControlBtn
# fallback widget) -> "x y w h name" of the first visible one, empty if none
ctl_opt() { A ui control | tr -d '\r' | tr '|' '\n' | grep -E "^ *[^ ]+ 'Control' -?[0-9]+,-?[0-9]+ [0-9]+x[0-9]+ *$" | grep -v '^ *KFPControlBtn ' | head -1 |
  sed -E "s/^ *([^ ]+) 'Control' (-?[0-9]+),(-?[0-9]+) ([0-9]+)x([0-9]+).*/\2 \3 \4 \5 \1/"; }
# opt_col <x> <w>: other visible captioned widgets in that column (the game's other options of the same menu)
# (harness `ui tree`, KAH e520c10+; m65: the options are unnamed '-' widgets, `ui <filter>` never listed them)
opt_col() { { A ui tree Control up 2; A ui tree Control up 3; } | tr -d '\r' | tr '|' '\n' | grep -E "'[^']+' $1,-?[0-9]+ ${2}x[0-9]+ *$" | grep -v "'Control' " | sort -u | wc -l; }
# ctl_opt_click: PHYSICAL left click (virtual cursor + DirectInput button) on the centre of the 'Control' option
ctl_opt_click() { local o x y w h; o=$(ctl_opt); [ -n "$o" ] || return 1; read -r x y w h _ <<<"$o"
  A mouse_inject at $((x + w/2)) $((y + h/2)) >/dev/null; sleep 0.3; mclick left 80; }
if want PT20; then
  # the hold menu from PT06 if it really offers Control (bounded wait), else a fresh tap menu (PT06 judges the hold)
  if [ $MENU_ON_MT = 1 ] && ! waitf 3 bash -c "stobe-auto fp_keys ctl | grep -q 'shown=1'"; then
    note "PT20: no Control offer on the PT06 hold menu ($(A fp_keys ctl)): tap menu instead"; MENU_ON_MT=0; fi
  [ $MENU_ON_MT = 1 ] || ctl_menu "$SH" "$MT"
  C1=$(A fp_keys ctl); S0=$(fld switches <<<"$C1")
  if [ "$(fld shown <<<"$C1")" != 1 ]; then row PT20 FAIL "Control button not shown with the menu on $MT open: [$C1] free=$(fps free) ctx_freed=$(ks ctx_freed)"
  else O1=$(ctl_opt); ctl_opt_click; waitf 3 ctl_is "$MT"; C2=$(A fp_keys ctl); T1=$(ctl controlled); TO=$(ctl_is "$MT" && echo 1 || echo 0); FR1=$(fps free)
    # chain: FP off/on while controlling the mate, then back to the player from her body (physical click again)
    toggles 1; AT=$(ctl_is "$MT" && echo 1 || echo 0); ctl_menu "$MT" "$SH"; C3=$(A fp_keys ctl); W3=$(ks ctx_why); KL3=$(kfplines | grep -aE "RMB .* opened no menu|RMB press ignored|RMB context menu" | tail -1 | cut -c1-170); O3=$(ctl_opt); ctl_opt_click; waitf 3 ctl_is "$SH"; C4=$(A fp_keys ctl); BACK=$(ctl_is "$SH" && echo 1 || echo 0)
    ev="to_mate: [target=$(fld target <<<"$C1") shown=1 option='${O1:-none}'] switches $S0->$(fld switches <<<"$C2") via=$(fld via <<<"$C2") last=$(fld last <<<"$C2") controlled=$T1 is_mate=$TO free_after=$FR1 still_mate_after_fp_toggle=$AT | back: shown=$(fld shown <<<"$C3") target=$(fld target <<<"$C3") option='${O3:-none}' switches->$(fld switches <<<"$C4") via=$(fld via <<<"$C4") is_player=$BACK log=$(kfplines | grep -c '\[controls\] Control -> .* via=menu') drawn_at_tap=${CTL_DRAWN:-n/a} ctx_why=${W3:-n/a} tap_log='${KL3:-none}'"
    ok=1; [ -n "$O1" ] && [ "$(fld target <<<"$C1")" = "$(uname_ "$MTN")" ] && [ "$(fld switches <<<"$C2")" = $((S0+1)) ] && [ "$(fld via <<<"$C2")" = menu ] && [ "$TO" = 1 ] && [ "$FR1" = 0 ] || ok=0
    [ -n "$O3" ] && [ "$(fld switches <<<"$C4")" = $((S0+2)) ] && [ "$(fld via <<<"$C4")" = menu ] && [ "$BACK" = 1 ] || ok=0; judge PT20 $ok "$ev"; fi
  menu_close; ctl_is "$SH" || take "$SH" >/dev/null; fi
menu_close

# ---- PT24: Control is an entry of the game's own RMB menu (not a separate button); physical click switches ----
if want PT24; then ctl_is "$SH" || take "$SH" >/dev/null
  if ! ctl_menu "$SH" "$MT"; then rows_fail "no menu with Control on $MT after a holstered RMB tap: $(A fp_keys ctl)" PT24
  else C1=$(A fp_keys ctl); S0=$(fld switches <<<"$C1"); O=$(ctl_opt); NC=0; OX=""; OW=""
    [ -n "$O" ] && { read -r OX _ OW _ _ <<<"$O"; NC=$(opt_col "$OX" "$OW"); }
    A screenshot pt24-menu >/dev/null; OPTS=$(A ui tree Control up 2 | tr -d '\r' | grep -oE "'[^']+'" | tr '\n' ',' | cut -c1-200)
    KB=$(A ui kfpcontrolbtn all | tr -d '\r' | tr '|' '\n' | grep -E "^ *KFPControlBtn " | grep -vc " hidden *$")
    ctl_opt_click; waitf 3 ctl_is "$MT"; C2=$(A fp_keys ctl); TO=$(ctl_is "$MT" && echo 1 || echo 0)
    ev="[native=$(fld native <<<"$C1") hooks=$(fld native_hooks <<<"$C1") shown=$(fld shown <<<"$C1") native_target=$(fld native_target <<<"$C1") injected=$(fld native_injected <<<"$C1") captions=$(fld native_captions <<<"$C1")] option='${O:-none}' same_column_options=$NC menu_entries=[$OPTS] shot=<harness mod folder>/shots/pt24-menu.png kfpbtn_visible=$KB | click: switches $S0->$(fld switches <<<"$C2") via=$(fld via <<<"$C2") native_clicks $(fld native_clicks <<<"$C1")->$(fld native_clicks <<<"$C2") is_mate=$TO menu_vis_after=$(fld menu_vis <<<"$C2") log=$(kfplines | grep -c 'Control option added to the game.s context menu')"
    ok=1; [ "$(fld native <<<"$C1")" = 1 ] && [ "$(fld native_hooks <<<"$C1")" = 7 ] && [ "$(fld shown <<<"$C1")" = 1 ] && [ "$(fld native_target <<<"$C1")" = "$(uname_ "$MTN")" ] || ok=0
    [ -n "$O" ] && [ "$NC" -ge 1 ] && [ "$KB" = 0 ] || ok=0
    [ "$(fld switches <<<"$C2")" = $((S0+1)) ] && [ "$(fld via <<<"$C2")" = menu ] && [ "$TO" = 1 ] && [ "$(fld menu_vis <<<"$C2")" = 0 ] || ok=0
    judge PT24 $ok "$ev"; fi
  menu_close; ctl_is "$SH" || take "$SH" >/dev/null; fi
menu_close

# ---- PT21: a selected squad mate gets no move order from RMB ----
if want PT21 || want PT19; then ctl_is "$SH" || take "$SH" >/dev/null
  if ! pick_on "$SH" "$MT"; then rows_fail "crosshair pick never on $MT for the MMB select" PT21 PT19
  else M0=$(ks mmb_selects); mclick middle 80; waitf 3 kge mmb_selects $((M0+1)); INS=$(ctl inspected); SEL=$(ks last_select)
    if [ "$SEL" != "$(uname_ "$MTN")" ]; then rows_fail "physical MMB did not select $MT (last_select=$SEL mmb_selects $M0->$(ks mmb_selects))" PT21 PT19
    else
      if want PT21; then A pin "$MT" off >/dev/null; PINNED=${PINNED/ $MT/}; sleep 1
        P0=$(pos "$MT"); YW=$(cam yaw); look "$(awk -v y="$YW" 'BEGIN{printf "%.4f", y+1.2}')" 0.45
        K0=$(A fp_keys state); mclick right 150; sleep 0.5; menu_close; mdown right; sleep 1.2; mup right; sleep 0.5; menu_close; sleep 2.5
        K=$(A fp_keys state); DM=$(d2 "$P0" "$(pos "$MT")")
        ev="$MT selected (inspected=$INS) RMB tap+hold on the ground: $MT moved=$DM mouse_keys_swallowed $(fld mouse_keys_swallowed <<<"$K0")->$(fld mouse_keys_swallowed <<<"$K") rmb_swallowed $(fld rmb_swallowed <<<"$K0")->$(fld rmb_swallowed <<<"$K") ctx_opens $(fld ctx_opens <<<"$K0")->$(fld ctx_opens <<<"$K")"
        ok=1; lt "$DM" "$STILL_MAX" || ok=0; judge PT21 $ok "$ev"
        A pin "$MT" at "$SH" dist 25 face "$SH" | grep -q '^pinned' && PINNED+=" $MT"; sleep 1
        A select "$MT" >/dev/null; sleep 0.3; fi   # PT19 needs the mate selected again
      # ---- PT19: MMB on the sky = selection back to the controlled char ----
      if want PT19; then sky; K0=$(A fp_keys state); mclick middle 80; waitf 3 kge mmb_self $(( $(fld mmb_self <<<"$K0") + 1 )); sleep 0.3
        K=$(A fp_keys state); I1=$(ctl inspected); HC=$(ctl controlled)
        ev="before: inspected=$INS | mmb_self $(fld mmb_self <<<"$K0")->$(fld mmb_self <<<"$K") last_select=$(fld last_select <<<"$K") inspected=$I1 controlled=$HC"
        ok=1; [ "$(fld mmb_self <<<"$K")" = $(( $(fld mmb_self <<<"$K0") + 1 )) ] && [ "$(fld last_select <<<"$K")" = "$(uname_ "$SHN")" ] && [ "$I1" = "$HC" ] || ok=0
        judge PT19 $ok "$ev"; fi; fi; fi; fi
menu_close

# ---- PT08: MMB / RMB menu on a building ----
if want PT08; then BL=""; for f in house shack bar shop hut tower home wall gate; do BL=$(A buildings 1500 "$f" | grep -m1 'pos='); [ -n "$BL" ] && break; done
  BP=$(grep -o 'pos=[^ ]*' <<<"$BL" | head -1 | cut -d= -f2 | tr ',' ' ')
  if [ -z "$BP" ]; then row PT08 FAIL "setup: no building within 1500"
  else read -r bx by bz <<<"$BP"; GOT=0
    for off in 250 350 180; do A teleport "$SH" "$(awk -v x="$bx" -v o="$off" 'BEGIN{print x+o}')" "$by" "$bz" >/dev/null; sleep 1.5; take "$SH" >/dev/null
      for h in 20 35 10; do aim_pt "$SH" "$BP" "$h"; K0=$(A fp_keys state); mclick middle 80; sleep 0.5; K=$(A fp_keys state)
        [ "$(fld mmb_objects <<<"$K")" = $(( $(fld mmb_objects <<<"$K0") + 1 )) ] && { GOT=1; break 2; }; done; done
    ev1="building='$(cut -c1-50 <<<"$BL")' MMB: mmb_objects $(fld mmb_objects <<<"$K0")->$(fld mmb_objects <<<"$K") mmb_self->$(fld mmb_self <<<"$K") last_select=$(fld last_select <<<"$K")"
    if [ $GOT = 0 ]; then row PT08 FAIL "no object select on 9 aims at the building (pick: $(A fp_keys pick show | cut -c1-120)): $ev1"
    else BN=$(fld last_select <<<"$K"); draw_to 0; O0=$(ks ctx_opens); mclick right 150; waitf 3 kge ctx_opens $((O0+1)); K2=$(A fp_keys state)
      ev="$ev1 | RMB tap: ctx_opens $O0->$(fld ctx_opens <<<"$K2") last_target=$(fld last_target <<<"$K2") ctx_freed=$(fld ctx_freed <<<"$K2") log=$(kfplines | grep -c 'MMB select object')"
      ok=1; [ "$(fld ctx_opens <<<"$K2")" = $((O0+1)) ] && [ "$(fld last_target <<<"$K2")" = "$BN" ] && [ "$BN" != "$(uname_ "$SHN")" ] || ok=0
      judge PT08 $ok "$ev"; menu_close; fi
    A teleport "$SH" $HOME >/dev/null; sleep 1.5; take "$SH" >/dev/null; fi; fi

# ---- PT09: controls survive FP toggles (+ a control switch) ----
if want PT09; then toggles 3; take "$MT" >/dev/null; mode off; take "$SH" >/dev/null; A select "$SH" >/dev/null; sleep 0.5
  K0=$(A fp_keys state); OK0=1; [ "$(fld hook <<<"$K0")" = 1 ] && [ "$(fld fault <<<"$K0")" = 0 ] && [ "$(fld swallow <<<"$K0")" = 1 ] && [ "$(fld fp <<<"$K0")" = 1 ] || OK0=0
  if ! pick_on "$SH" "$MT"; then row PT09 FAIL "setup: crosshair pick never on $MT after the toggles ($(cut -c1-100 <<<"$PK"))"
  else I0=$(ctl inspected); mclick left 80; sleep 0.4; IL=$(ctl inspected)
    M0=$(ks mmb_selects); mclick middle 80; waitf 3 kge mmb_selects $((M0+1)); SEL=$(ks last_select); A select "$SH" >/dev/null
    O0=$(ks ctx_tap_opens); mclick right 150; waitf 3 kge ctx_tap_opens $((O0+1)); K=$(A fp_keys state); menu_close
    ev="after 3 FP toggles + control switch: hook=$(fld hook <<<"$K0") fault=$(fld fault <<<"$K0") swallow=$(fld swallow <<<"$K0") | LMB inspected $I0->$IL | MMB last_select=$SEL | RMB tap ctx_tap_opens $O0->$(fld ctx_tap_opens <<<"$K") last_target=$(fld last_target <<<"$K")"
    ok=$OK0; [ "$IL" = "$I0" ] && [ "$SEL" = "$(uname_ "$MTN")" ] && [ "$(fld ctx_tap_opens <<<"$K")" = $((O0+1)) ] || ok=0; judge PT09 $ok "$ev"; fi; fi
menu_close

# vwalk <dist> <walk|run>: a native timed walk from home along the first axis that walks: sets VW="axis=.. speed=.. top_speed=.." (empty: no axis walked, VWERR = last error)
VWERR=""; MVS=""
vwalk() { local ax r; VW=""; for ax in -x +x -z +z; do A teleport "$SH" $HOME >/dev/null; sleep 1.5; r=$(A walktime "$SH" "$1" "$ax" "$2")
    case "$r" in *" walked "*) VW="axis=$ax $(grep -o 'speed=[^ ]*\|top_speed=[^ ]*' <<<"$r" | tr '\n' ' ')"; return 0;; esac
    VWERR="$2 $ax: $(cut -c1-90 <<<"$r")"; done; return 1; }
# ---- PT04: FP walk/run speed = the vanilla speed of the same char/state (within PT04_TOL, 5%) ----
# Shay's steps: in FP, hold W (physical key) and walk/run; outside FP the same char gets a move order. One method on
# both sides: `where` samples during steady motion (after the start-up), each stamped at the middle of its call,
# least-squares slope of distance vs time; same char, same start spot, same axis (the first axis a vanilla run walks).
# State: vanilla run order (walktime run) -> FP W must drive gait=run; vanilla walk order (walktime walk) -> FP W must
# drive gait=walk; the char's order is handed back after each hold (gait_restores rises, mv_so = the vanilla order).
PT04_TOL=${PT04_TOL:-0.05}
# psamp <n> <dist cap> <start pos>: n where samples of $SH, prints "t d" rows (t = mid-call seconds, d = XZ from start)
psamp() { local i a b P; for i in $(seq 1 "$1"); do a=$(date +%s.%N); P=$(pos "$SH"); b=$(date +%s.%N)
    awk -v a="$a" -v b="$b" -v d="$(d2 "$3" "$P")" -v cap="$2" 'BEGIN{if (d+0 < cap+0) printf "%.4f %.2f\n", (a+b)/2, d}'; done; }
# slope: least squares over "t d" rows (needs >=3 rows spanning >=1 s), "" if not enough
slope() { awk '{t[NR]=$1; d[NR]=$2} END{if (NR<3 || t[NR]-t[1]<1) exit; for(i=1;i<=NR;i++){st+=t[i];sd+=d[i]} mt=st/NR; md=sd/NR
    for(i=1;i<=NR;i++){n+=(t[i]-mt)*(d[i]-md); q+=(t[i]-mt)^2} if (q>0) printf "%.2f", n/q}'; }
axis_yaw() { case "$1" in +x) echo 1.5708;; -x) echo 4.7124;; +z) echo 0;; -z) echo 3.1416;; esac; }
# van_rate <walk|run> <dist> <lead s>: vanilla move order along $AX from home, steady rate -> VR
van_rate() { local P0 bg; mode off; A teleport "$SH" $HOME >/dev/null; sleep 1.5; P0=$(pos "$SH")
  ( A walktime "$SH" "$2" "$AX" "$1" > "$OUT/pt04-walk-$1.txt" ) & bg=$!
  sleep "$3"; VR=$(psamp 6 "$(awk -v d="$2" 'BEGIN{print d-40}')" "$P0" | slope); wait "$bg"; VRW=$(cut -c1-120 "$OUT/pt04-walk-$1.txt")
  VLAT=$(lat "$P0" "$(pos "$SH")"); VDONE=$(grep -oE 'walked [0-9.]+' <<<"$VRW" | cut -d' ' -f2); }
# lat <start> <end>: sideways offset from the axis $AX (a path that left the straight line = an obstacle on it)
lat() { awk -v a="$1" -v b="$2" -v ax="$AX" 'BEGIN{split(a,p," ");split(b,q," "); d=(ax ~ /x/)?q[3]-p[3]:q[1]-p[1]; printf "%.1f", d<0?-d:d}'; }
# fp_rate <lead s>: FP on, physical W held along $AX from home, steady rate -> FR, KenshiFP meter -> FM
fp_rate() { local P0; A teleport "$SH" $HOME >/dev/null; sleep 1.5; take "$SH" >/dev/null; look "$(axis_yaw "$AX")" 0
  P0=$(pos "$SH"); A key_inject w down >/dev/null; sleep "$1"; FR=$(psamp 6 "${2:-100000}" "$P0" | slope); FLAT=$(lat "$P0" "$(pos "$SH")")
  A key_inject w up >/dev/null; sleep 1.2; FM=$(A fp_move state); }
within() { awk -v a="$1" -v b="$2" -v t="$PT04_TOL" 'BEGIN{exit !(a!="" && b!="" && b+0>0 && (a-b)/b<=t && (b-a)/b<=t)}'; }
if want PT04; then take "$SH" >/dev/null; A teleport "$SH" $HOME >/dev/null; sleep 1.5
  SPN=$(ks speed_now); ATH=$(A stat "$SH" athletics | grep -o 'base=[^ ]*\|effective=[^ ]*' | tr '\n' ' ')
  mode off; AX=""; vwalk 80 run && AX=$(grep -o 'axis=[^ ]*' <<<"$VW" | cut -d= -f2)
  if [ -z "$AX" ]; then A fp_keys movers >/dev/null; sleep 0.3
    MVS=$(A fp_keys movers show | awk -v w="$SHN mode=" 'BEGIN{RS=" [|] "} index($0,w)==1{print; exit}' | cut -c1-160)
    row PT04 FAIL "setup: native run never started on any axis from $HOME: $SH mover [$MVS] ${VWERR:0:160}"
  elif [ "$SPN" != "1.00" ] && [ "$SPN" != "1.0" ] && [ "$SPN" != "1" ]; then row PT04 FAIL "setup: game speed $SPN, not 1 (rates are real time)"
  else
    # m64/m65: on -x a wall stands ~205 u from home: vanilla `walktime run 500` never started (no path) and FP run hit
    # it after ~2 s (x stuck, sliding sideways, rate 11.8 u/s while the meter peaked at 112 = vanilla top speed). The
    # run axis must carry a full vanilla run of 500 u in a straight line (walked >= 450, sideways < 25), and the FP run
    # samples stop at 420 u from the start (inside the proven clear stretch).
    AXT=""; VRUN=""; G0=$(fld gait_restores <<<"$(A fp_move state)")
    for AX in -x +x -z +z; do van_rate run 500 1.0; AXT+=" $AX:rate=${VR:-none},walked=${VDONE:-0},side=$VLAT"
      if [ -n "$VR" ] && awk -v w="${VDONE:-0}" -v l="$VLAT" 'BEGIN{exit !(w+0>=450 && l+0<25)}'; then VRUN=$VR; VRUNW=$VRW; break; fi; done
    [ -n "$VRUN" ] || { AX=""; VRUNW="no clear 500 u run axis:$AXT"; }
    [ -n "$AX" ] && { fp_rate 1.0 420; FRUN=$FR; FMRUN=$FM; FLATRUN=$FLAT; }
    [ -n "$AX" ] && { van_rate walk 150 1.5; VWALK=$VR; VWALKW=$VRW; }
    [ -n "$AX" ] && { fp_rate 2.0 420; FWALK=$FR; FMWALK=$FM; }
    mode off; vwalk 20 run >/dev/null; take "$SH" >/dev/null       # hand the char its run order back
    g() { fld "$1" <<<"$2"; }
    ev="axis $AX | run: vanilla $VRUN u/s FP $FRUN u/s (FP gait=$(g gait "$FMRUN") vanilla_order=$(g vanilla_order "$FMRUN") meter rate_avg=$(g rate_avg "$FMRUN") rate_peak=$(g rate_peak "$FMRUN") sideways=$FLATRUN mv_max=$(g mv_max "$FMRUN") after release mv_so=$(g mv_so "$FMRUN"))"
    ev="$ev | walk: vanilla $VWALK u/s FP $FWALK u/s (FP gait=$(g gait "$FMWALK") meter rate_avg=$(g rate_avg "$FMWALK") mv_walk=$(g mv_walk "$FMWALK") after release mv_so=$(g mv_so "$FMWALK"))"
    ev="$ev | gait_restores $G0->$(g gait_restores "$FMWALK") | tol $PT04_TOL | athletics $ATH | axes$AXT | walktime run [$VRUNW] walk [$VWALKW]"
    if [ -z "$VRUN" ] || [ -z "$VWALK" ] || [ -z "$FRUN" ] || [ -z "$FWALK" ]; then row PT04 FAIL "setup: too few steady samples: $ev"
    else ok=1; within "$FRUN" "$VRUN" && within "$FWALK" "$VWALK" || ok=0
      [ "$(g gait "$FMRUN")" = run ] && [ "$(g gait "$FMWALK")" = walk ] && [ "$(g mv_so "$FMRUN")" = run ] && [ "$(g mv_so "$FMWALK")" = walk ] || ok=0
      [ "$(g holding "$FMWALK")" = 0 ] && inc "$G0" "$(g gait_restores "$FMWALK")" || ok=0
      judge PT04 $ok "$ev"; fi; fi
  A teleport "$SH" $HOME >/dev/null; sleep 1.5; take "$SH" >/dev/null; fi

# ---- PT05: time-scale button click evidence (RTS, then FP free cursor) ----
spd_click() { local u x y w h; u=$(A ui timespeedbutton2 | grep -oE "TimeSpeedButton2( '[^']*')? -?[0-9]+,-?[0-9]+ [0-9]+x[0-9]+" | grep -oE -- '-?[0-9]+,-?[0-9]+ [0-9]+x[0-9]+$' | head -1)
  [ -n "$u" ] || return 1; read -r x y w h <<<"$(tr ',x' '  ' <<<"$u")"
  A mouse_inject at $((x + w/2)) $((y + h/2)) >/dev/null; sleep 0.3; mclick left 80; sleep 3.3; }
if want PT05; then A speed 1 >/dev/null; sleep 0.5; EV=""; OK=1; N=0
  for where_ in rts fp; do
    if [ $where_ = rts ]; then mode off; else take "$SH" >/dev/null; altkey; waitf 3 bash -c "stobe-auto fp_state | grep -q 'free=1'"; fi
    L0=$(wc -l < "$KFPLOG"); K0=$(A fp_keys state)
    if spd_click; then N=$((N+1)); K=$(A fp_keys state); SL=$(tail -n +"$((L0+1))" "$KFPLOG" | tr -d '\r' | grep -c '^.*\[speed\]')
      PEAK=$(fld speed_peak_click <<<"$K")
      EV+="$where_: speed_clicks $(fld speed_clicks <<<"$K0")->$(fld speed_clicks <<<"$K") peak_click=$PEAK changes $(fld speed_changes <<<"$K0")->$(fld speed_changes <<<"$K") long_frames $(fld speed_long_frames <<<"$K0")->$(fld speed_long_frames <<<"$K") now=$(fld speed_now <<<"$K") speed_log_lines=$SL | "
      inc "$(fld speed_clicks <<<"$K0")" "$(fld speed_clicks <<<"$K")" || OK=0; lt "$PEAK" "$SPIKE_MAX" || OK=0
      tail -n +"$((L0+1))" "$KFPLOG" | tr -d '\r' | grep '\[speed\]' | head -20 > "$OUT/pt05-$where_-speed.txt"
    else EV+="$where_: TimeSpeedButton2 not visible ($(A ui timespeed | cut -c1-120)) | "; fi
    [ $where_ = fp ] && menu_close; done
  if [ $N = 0 ]; then row PT05 FAIL "setup: TimeSpeedButton2 never found: $EV"
  else judge PT05 $OK "evidence ($N clicks, spike if peak_click>=$SPIKE_MAX): ${EV% | } logs=$OUT/pt05-*-speed.txt"; fi
  A speed 1 >/dev/null; take "$SH" >/dev/null; fi

# ---- PT23: Shay's speed sequence: x0.5 -> 1x button -> speed up (physical clicks on the speed buttons, then the same
# with the speed keys), RTS and FP free cursor / FP look. After every step the game-time rate (harness `time`
# game_hours per real second, back-to-back samples for 2 s, first sample taken right BEFORE the input) is compared
# with the 1x base rate: no sample above SPIKE_MAX x the higher of the speeds before/after the step. Speed up after
# 1x must land on x2 (RE_Kenshi custom speeds; KenshiFP speed guard armed: speed_guard=1).
gh() { local a b r; a=$(date +%s.%N); r=$(stobe-auto time 2>&1); b=$(date +%s.%N)
  echo "$(awk -v a="$a" -v b="$b" 'BEGIN{printf "%.4f",(a+b)/2}') $(fld game_hours <<<"$r") $(fld speed <<<"$r")"; }
feq() { awk -v a="$1" -v b="$2" 'BEGIN{exit !(a!="" && a-b<0.01 && b-a<0.01)}'; }
spd_now() { A time | fld speed; }
spd_btn() { local n=$1 u x y w h; u=$(A ui "timespeedbutton$n" | grep -oE "TimeSpeedButton$n( '[^']*')? -?[0-9]+,-?[0-9]+ [0-9]+x[0-9]+" | grep -oE -- '-?[0-9]+,-?[0-9]+ [0-9]+x[0-9]+$' | head -1)
  [ -n "$u" ] || return 1; read -r x y w h <<<"$(tr ',x' '  ' <<<"$u")"; BTN_XY="$((x + w/2)) $((y + h/2))"; }
# pt23_step <click|key> <down|one|up>: one physical input, samples around it; sets ST_EV (evidence) and ST_BAD (1 = burst)
pt23_step() { local how=$1 what=$2 n k s0 S=() i r
  case $what in down) n=3; k=2;; one) n=2; k=1;; up) n=4; k=3;; esac
  if [ "$how" = click ]; then spd_btn "$n" || { ST_EV="TimeSpeedButton$n not visible"; ST_BAD=1; return 1; }
    A mouse_inject at $BTN_XY >/dev/null; sleep 0.25; fi
  s0=$(spd_now); S+=("$(gh)")
  if [ "$how" = click ]; then stobe-auto mouse_inject left click 80 >/dev/null 2>&1; else stobe-auto key_inject "$k" tap 150 >/dev/null 2>&1; fi
  for i in $(seq 1 14); do S+=("$(gh)"); done
  r=$(printf '%s\n' "${S[@]}" | awk -v base="$BASE" -v s0="$s0" -v lim="$SPIKE_MAX" '
      { t[NR]=$1; h[NR]=$2; s[NR]=$3 } END { s1=s[NR]; ref=(s0+0>s1+0)?s0:s1; if (ref<=0) ref=1; mx=0
        for (i=2;i<=NR;i++) { dt=t[i]-t[i-1]; if (dt<=0) continue; q=(h[i]-h[i-1])/dt/base/ref; if (q>mx) mx=q }
        printf "%s %.2f %d", s1, mx, (mx>lim) }')
  read -r ST_S1 ST_MAX ST_BAD <<<"$r"; ST_EV="$what($how) x$s0->x$ST_S1 max_rate=${ST_MAX}x"; }
if want PT23; then mode off; A speed 1 >/dev/null; sleep 1.5; OK=1; EV=""
  K=$(A fp_keys state); GUARD=$(fld speed_guard <<<"$K")
  b1=$(gh); sleep 3; b2=$(gh)
  BASE=$(awk -v a="$b1" -v b="$b2" 'BEGIN{split(a,p," ");split(b,q," "); d=q[1]-p[1]; if (d>0 && q[2]>p[2]) printf "%.8f", (q[2]-p[2])/d; else print 0}')
  if [ "$GUARD" != 1 ] || [ "$BASE" = 0 ]; then row PT23 FAIL "setup/product: speed_guard=$GUARD (RE_Kenshi index or custom speeds not found: grep '[speed] RE_Kenshi' KenshiFP.log) base_rate=$BASE h/s [$b1 | $b2]"
  else for v in rts:click rts:key fp:click fp:key; do where_=${v%%:*}; how=${v##*:}
      if [ $where_ = rts ]; then mode off; else take "$SH" >/dev/null; [ $how = click ] && { altkey; waitf 3 bash -c "stobe-auto fp_state | grep -q 'free=1'"; }; fi
      A speed 1 >/dev/null; sleep 1; K0=$(A fp_keys state); L0=$(wc -l < "$KFPLOG"); SEQ=""; j=0
      # to x0.5 the way Shay does (speed down), then 1x, then speed up
      while ! feq "$(spd_now)" 0.5 && [ $j -lt 4 ]; do pt23_step "$how" down; SEQ+="$ST_EV; "; [ "$ST_BAD" = 1 ] && OK=0; j=$((j+1)); done
      feq "$(spd_now)" 0.5 || { OK=0; SEQ+="never reached x0.5; "; }
      pt23_step "$how" one; SEQ+="$ST_EV; "; [ "$ST_BAD" = 1 ] && OK=0; feq "$ST_S1" 1 || { OK=0; SEQ+="1x gave x$ST_S1; "; }
      pt23_step "$how" up; SEQ+="$ST_EV; "; [ "$ST_BAD" = 1 ] && OK=0; feq "$ST_S1" 2 || { OK=0; SEQ+="speed up after 1x gave x$ST_S1 (want x2); "; }
      K=$(A fp_keys state)
      EV+="$v: ${SEQ}fixed $(fld speed_fixed <<<"$K0")->$(fld speed_fixed <<<"$K") synced $(fld speed_synced <<<"$K0")->$(fld speed_synced <<<"$K") fix_run=$(fld speed_fix_run <<<"$K") | "
      tail -n +"$((L0+1))" "$KFPLOG" | tr -d '\r' | grep '\[speed\]' | head -40 > "$OUT/pt23-$where_-$how-speed.txt"
      menu_close; done
    judge PT23 $OK "base=${BASE}h/s spike_max=$SPIKE_MAX ${EV% | } logs=$OUT/pt23-*-speed.txt"; fi
  A speed 1 >/dev/null; take "$SH" >/dev/null; fi

# ---- weapon rows: mate behind the shooter, manual combat on (physical input) ----
take "$SH" >/dev/null
note "SETUP weapons: $MT behind $SH: $(A pin "$MT" at "$SH" dist -25 face "$SH" | cut -c1-100)"
A fp_combat on >/dev/null; A fp_combat physical >/dev/null; A fp_combat autoreload 1 >/dev/null
BOWOK=0; [ -n "$BOWN" ] && bow_on && BOWOK=1

# ---- PT11: holstered crossbow, RMB does nothing combat-related ----
if want PT11; then if [ $BOWOK = 0 ]; then row PT11 FAIL "setup: no crossbow on $SH ('$BOWN')"; else
  menu_close; draw_to 0; sky; C0=$(A fp_combat state); mdown right; sleep 1.5; K1=$(A fp_keys state); C1=$(A fp_combat state); mup right; sleep 0.8; menu_close
  K2=$(A fp_keys state); C2=$(A fp_combat state)
  ev="RMB held 1.5 s: drawn=$(fld drawn <<<"$K1")/$(fld drawn <<<"$K2") wih=$(fld wih <<<"$K1")/$(fld wih <<<"$K2") ranged=$(fld ranged <<<"$K1") why=$(fld why <<<"$C1") combat draws $(fld draws <<<"$C0")->$(fld draws <<<"$C2") reload_starts $(fld reload_starts <<<"$C0")->$(fld reload_starts <<<"$C2") enabled=$(fld enabled <<<"$C1") injected=$(fld injected <<<"$C1")"
  ok=1; [ "$(fld drawn <<<"$K1")" = 0 ] && [ "$(fld drawn <<<"$K2")" = 0 ] && [ "$(fld wih <<<"$K2")" = 0 ] && [ "$(fld why <<<"$C1")" = ranged_holstered ] || ok=0
  [ "$(fld draws <<<"$C2")" = "$(fld draws <<<"$C0")" ] && [ "$(fld reload_starts <<<"$C2")" = "$(fld reload_starts <<<"$C0")" ] || ok=0
  judge PT11 $ok "$ev"; fi; fi

# chain: FP off/on + control to the mate and back between the bow rows
toggles 1; take "$MT" >/dev/null; take "$SH" >/dev/null

# ---- PT18: R only draws/holsters the crossbow ----
if want PT18; then if [ $BOWOK = 0 ]; then row PT18 FAIL "setup: no crossbow on $SH"; else
  draw_to 0; sky; C0=$(A fp_combat state); D0=$(ks r_draws); rkey; waitf 4 kis drawn 1; waitf 6 kis ranged 1; sleep 2; C1=$(A fp_combat state); K1=$(A fp_keys state)
  mdown right; sleep 1; waitf 12 csis reloading 0; C2=$(A fp_combat state); H0=$(ks r_holsters); rkey; waitf 4 kis drawn 0; sleep 0.8; C3=$(A fp_combat state); K3=$(A fp_keys state); mup right; sleep 0.5
  ev="R draw: r_draws $D0->$(fld r_draws <<<"$K1") ranged=$(fld ranged <<<"$K1") reload_starts $(fld reload_starts <<<"$C0")->$(fld reload_starts <<<"$C1") (2 s, no aim) | aim+R: drawn=$(fld drawn <<<"$K3") r_holsters $H0->$(fld r_holsters <<<"$K3") reload_starts $(fld reload_starts <<<"$C2")->$(fld reload_starts <<<"$C3") ammo $(fld ammo <<<"$C2")->$(fld ammo <<<"$C3")"
  ok=1; [ "$(fld drawn <<<"$K1")" = 1 ] && [ "$(fld ranged <<<"$K1")" = 1 ] && [ "$(fld reload_starts <<<"$C1")" = "$(fld reload_starts <<<"$C0")" ] || ok=0
  [ "$(fld drawn <<<"$K3")" = 0 ] && [ "$(fld r_holsters <<<"$K3")" = $((H0+1)) ] && [ "$(fld reload_starts <<<"$C3")" = "$(fld reload_starts <<<"$C2")" ] && [ "$(fld ammo <<<"$C3")" = "$(fld ammo <<<"$C2")" ] || ok=0
  judge PT18 $ok "$ev"; fi; fi

# ---- PT15: manual crossbow shots get the skill cone ----
if want PT15; then if [ $BOWOK = 0 ]; then row PT15 FAIL "setup: no crossbow on $SH"; else
  # m53: aiming a HOLSTERED crossbow does nothing by design (PT11, why=holstered), so draw it with R first
  draw_to 1; waitf 6 kis ranged 1
  aim_at "$SH" "$MT" 13; look "$(awk -v y="$(cam yaw)" 'BEGIN{printf "%.4f", y+3.14159}')" 0.05   # away from the mate, at the ground ahead
  # m54: the controller arms only after one idle input frame (a no_focus/UI release resets it; an aim already
  # held never arms: armed=0, shot_ready never 1), so publish idle input first, then aim
  A fp_combat input 0 0 0 >/dev/null; waitf 4 csis armed 1 || note "SETUP PT15 not armed after idle input (why=$(cs why))"
  A fp_combat input 1 0 0 >/dev/null; waitf 8 csis aimed 1; SL0=$(kfplines | grep -c '\[combat\] spread'); C0=$(A fp_combat state); SHOTS=0; WHY=""
  for _ in 1 2 3; do waitf 20 csis shot_ready 1 || { WHY="shot_ready never 1 (ammo=$(cs ammo) has_ammo=$(cs has_ammo) reloading=$(cs reloading) why=$(cs why) drawn=$(ks drawn) ranged=$(ks ranged))"; break; }
    S=$(cs actual_shots); A fp_combat input 1 1 0 >/dev/null; waitf 3 csge actual_shots $((S+1)) && SHOTS=$((SHOTS+1)); A fp_combat input 1 0 0 >/dev/null; sleep 0.4; done
  A fp_combat input 0 0 0 >/dev/null; A fp_combat physical >/dev/null; C1=$(A fp_combat state); SL1=$(kfplines | grep -c '\[combat\] spread')
  N0=$(fld spread_n <<<"$C0"); N1=$(fld spread_n <<<"$C1"); SK=$(fld spread_skill <<<"$C1"); PE=$(fld spread_per <<<"$C1"); CO=$(fld spread_cone <<<"$C1"); OF=$(fld spread_off <<<"$C1"); SC=$(fld spread_scale <<<"$C1")
  EXP=$(awk -v s="$SK" -v p="$PE" -v k="$SC" 'BEGIN{a=(0.75*s+0.25*p)/100; if(a<0)a=0; if(a>1)a=1; printf "%.3f", (0.5+6*(1-a)^1.5)*k}')
  ev="shots=$SHOTS spread_n $N0->$N1 crossbows=$SK perception=$PE cone=$CO expected=$EXP off=$OF scale=$SC spread_log $SL0->$SL1 $WHY"
  if [ $SHOTS = 0 ]; then row PT15 FAIL "setup: no shot fired: $ev"
  else ok=1; [ "$N1" = $((N0+SHOTS)) ] && [ $((SL1-SL0)) -ge $SHOTS ] || ok=0
    awk -v c="$CO" -v e="$EXP" -v o="$OF" 'BEGIN{d=c-e; if(d<0)d=-d; exit !(c!="" && d<0.02 && o+0<=c+0.001 && c+0>0)}' || ok=0
    judge PT15 $ok "$ev"; fi
  draw_to 0; fi; fi

# ---- melee: bow off, sword from the mate ----
MELEE=0; if want PT02 || want PT01 || want PT03 || want PT10 || want PT12; then draw_to 0
  give_melee || note "SETUP: could not give $SH a melee weapon"; bow_off || note "SETUP: bow would not unequip ($(bow_now))"
  arm_melee && MELEE=1; note "SETUP melee=$MELEE wep='$WEP' bow_now=$(bow_now) bow_dropped=$BOW_DROPPED"; fi
mfail() { rows_fail "no melee weapon equips on $SH (inv: $(weapons | tr '\n' ';'))" "$@"; }
toggles 1; take "$SH" >/dev/null

# ---- PT02 (+ PT01): R with a sword only ----
if want PT02 || want PT01; then if [ $MELEE = 0 ]; then mfail PT02 PT01; else draw_to 0; sky; sleep 2; K0=$(A fp_keys state)
  rkey; K1=$(A fp_keys state); waitf 4 kis drawn 1; K2=$(A fp_keys state); sleep 2.6; K3=$(A fp_keys state)
  RL=$(kfplines | grep '\[controls\] R \(draw\|ready\)' | tail -1 | cut -c1-120)
  # m53: the weapon was already out before R (bandit fight: r_draws 1->1, no flash): that is setup, not a verdict
  if [ "$(fld drawn <<<"$K0")" != 0 ]; then rows_fail "weapon not holstered before R (drawn=$(fld drawn <<<"$K0") ui_state=$(fld ui_state <<<"$K0"))" PT02 PT01
  else
  if want PT02; then ev="bow=$(bow_now) wep='$WEP' r_draws $(fld r_draws <<<"$K0")->$(fld r_draws <<<"$K2") drawn=$(fld drawn <<<"$K2") wih=$(fld wih <<<"$K2") r_path=$(fld r_path <<<"$K2") fists=$(fld fists <<<"$K2") log='$RL'"
    ok=1; inc "$(fld r_draws <<<"$K0")" "$(fld r_draws <<<"$K2")" && [ "$(fld drawn <<<"$K2")" = 1 ] && [ "$(fld wih <<<"$K2")" != 0 ] && [ -n "$(fld wih <<<"$K2")" ] && [ "$(fld r_path <<<"$K2")" != unarmed ] && [ "$(fld fists <<<"$K2")" = 0 ] || ok=0
    judge PT02 $ok "$ev"; fi
  if want PT01; then
    # shown within the flash (K1 ~0.4 s / K2 after the draw), hidden 2.6 s later while still ready
    SHOWN=0; for s in "$K1" "$K2"; do [ "$(fld hud_shown <<<"$s")" = 1 ] && [ "$(fld hud_text <<<"$s")" = ready ] && SHOWN=1; done
    ev="before R: ui_state=$(fld ui_state <<<"$K0") | after R: hud_text=$(fld hud_text <<<"$K1")/$(fld hud_text <<<"$K2") hud_shown=$(fld hud_shown <<<"$K1")/$(fld hud_shown <<<"$K2") | +2.6 s: ui_state=$(fld ui_state <<<"$K3") hud_shown=$(fld hud_shown <<<"$K3") hud_flashes $(fld hud_flashes <<<"$K0")->$(fld hud_flashes <<<"$K3") hist=$(fld hud_hist <<<"$K3")"
    ok=1; [ $SHOWN = 1 ] && [ "$(fld ui_state <<<"$K3")" = ready ] && [ "$(fld hud_shown <<<"$K3")" = 0 ] && inc "$(fld hud_flashes <<<"$K0")" "$(fld hud_flashes <<<"$K3")" || ok=0
    judge PT01 $ok "$ev"; fi; fi; fi; fi

# ---- PT03: no text while blocking / swinging ----
if want PT03; then if [ $MELEE = 0 ]; then mfail PT03; else draw_to 1; sky; waitf 10 not_fight; sleep 1.6; K0=$(A fp_keys state)
  mdown right; sleep 0.7; KB1=$(A fp_keys state); sleep 0.6; KB2=$(A fp_keys state); mup right; sleep 1
  mclick left 80; KS1=$(A fp_keys state); waitf 5 kge fs_ends $(( $(fld fs_ends <<<"$K0") + 1 )); K=$(A fp_keys state)
  ev="block: ui_state=$(fld ui_state <<<"$KB1")/$(fld ui_state <<<"$KB2") hud_shown=$(fld hud_shown <<<"$KB1")/$(fld hud_shown <<<"$KB2") | swing: free_swings $(fld free_swings <<<"$K0")->$(fld free_swings <<<"$K") ui=$(fld ui_state <<<"$KS1") hud_shown=$(fld hud_shown <<<"$KS1") | hud_silent $(fld hud_silent <<<"$K0")->$(fld hud_silent <<<"$K") hist=$(fld hud_hist <<<"$K")"
  ok=1; [ "$(fld ui_state <<<"$KB1")" = blocking ] && [ "$(fld hud_shown <<<"$KB1")" = 0 ] && [ "$(fld hud_shown <<<"$KB2")" = 0 ] || ok=0
  [ "$(fld ui_state <<<"$KS1")" != swinging ] || [ "$(fld hud_shown <<<"$KS1")" = 0 ] || ok=0
  ge "$(fld hud_silent <<<"$K")" $(( $(fld hud_silent <<<"$K0") + 2 )) && inc "$(fld free_swings <<<"$K0")" "$(fld free_swings <<<"$K")" || ok=0
  judge PT03 $ok "$ev"; fi; fi

# ---- PT10: LMB never orders an attack on a squad mate or a far NPC ----
if want PT10; then if [ $MELEE = 0 ]; then mfail PT10; else draw_to 1; waitf 10 not_fight
  HP0=$(A hp "$MT" | grep -o 'worst=[0-9-]*%'); EV=""; ok=1
  if pick_on "$SH" "$MT"; then K0=$(A fp_keys state); mclick left 80; sleep 1.5; K=$(A fp_keys state); FI=$(in_fight && echo 1 || echo 0)
    EV="mate: lmb_why=$(fld lmb_why <<<"$K") dist=$(fld lmb_dist <<<"$K") squad_refused $(fld lmb_squad_refused <<<"$K0")->$(fld lmb_squad_refused <<<"$K") engages $(fld engages <<<"$K0")->$(fld engages <<<"$K") fight=$FI hp $HP0->$(A hp "$MT" | grep -o 'worst=[0-9-]*%')"
    [ "$(fld lmb_why <<<"$K")" = squad ] && [ "$(fld lmb_squad_refused <<<"$K")" = $(( $(fld lmb_squad_refused <<<"$K0") + 1 )) ] && [ "$(fld engages <<<"$K")" = "$(fld engages <<<"$K0")" ] && [ $FI = 0 ] || ok=0
  else ok=0; EV="setup: crosshair pick never on $MT"; fi
  # far NPC: FAR_NPC=<name>, else the fixture hostile, else a neutral spawned 10 m away
  FN=""; if [ -n "$FAR_NPC" ]; then FN=$FAR_NPC; elif [ -n "$TGH" ] && notko "$TGH"; then FN=$TGH
  else SP=$(A spawn "Hungry Bandit" "Tech Hunters" near "$SH" dist 100 count 1); FN=$(grep -oE '#[0-9]+/[0-9]+' <<<"$SP" | head -1); note "PT10 spawn: $SP"; fi
  [ -n "$FN" ] && [ "$FN" != "$TGH" ] && KEEPN+=(-e "combat: $(live_name "$FN") (")
  if [ -n "$FN" ] && A pin "$FN" at "$SH" dist 80 | grep -q '^pinned'; then PINNED+=" $FN"; sleep 1; waitf 10 not_fight
    if pick_on "$SH" "$FN"; then K0=$(A fp_keys state); mclick left 80; sleep 2; K=$(A fp_keys state); FI=$(in_fight && echo 1 || echo 0)
      EV+=" | far $(live_name "$FN"): lmb_why=$(fld lmb_why <<<"$K") dist=$(fld lmb_dist <<<"$K") far_refused $(fld lmb_far_refused <<<"$K0")->$(fld lmb_far_refused <<<"$K") engages $(fld engages <<<"$K0")->$(fld engages <<<"$K") free_swings $(fld free_swings <<<"$K0")->$(fld free_swings <<<"$K") fight=$FI"
      [ "$(fld lmb_why <<<"$K")" = far ] && [ "$(fld lmb_far_refused <<<"$K")" = $(( $(fld lmb_far_refused <<<"$K0") + 1 )) ] && [ "$(fld engages <<<"$K")" = "$(fld engages <<<"$K0")" ] && [ $FI = 0 ] || ok=0
    else ok=0; EV+=" | setup: crosshair pick never on the far npc $FN"; fi
    A pin "$FN" at "$SH" dist 600 >/dev/null
  else ok=0; EV+=" | setup: no far NPC to pin (FAR_NPC=, $TG KO/missing, spawn failed)"; fi
  EV+=" log_no_engage=$(kfplines | grep -c 'LMB no engage')"
  case "$EV" in *setup:*) row PT10 FAIL "$EV";; *) judge PT10 $ok "$EV";; esac; fi; fi

# ---- PT12: sword drawn + crossbow carried: RMB/LMB stay melee ----
if want PT12; then if [ $MELEE = 0 ]; then mfail PT12; elif [ -z "$BOWN" ]; then row PT12 FAIL "setup: no crossbow"; else
  draw_to 0; bow_on || note "SETUP PT12 bow would not re-equip"; A equip "$SH" "$WEP" >/dev/null
  # m54: R draws the game's preferred weapon, which follows the orders-panel ranged toggle (vanilla; ranged=1 drew
  # the bow). The row needs the sword in hands with the bow equipped: ranged off for this row, restored on exit.
  RANGED0=$(A combatmode "$SH" | fld ranged); A combatmode "$SH" ranged off >/dev/null
  toggles 1; take "$SH" >/dev/null; sky; rkey; waitf 4 kis drawn 1; sleep 0.5
  if [ "$(bow_now)" = none ] || [ "$(ks ranged)" != 0 ] || [ "$(ks drawn)" != 1 ]; then row PT12 FAIL "setup: need sword drawn + bow equipped (bow=$(bow_now) drawn=$(ks drawn) ranged=$(ks ranged) r_path=$(ks r_path))"
  else waitf 10 not_fight; W0=$(ks wih); C0=$(A fp_combat state); K0=$(A fp_keys state)
    mdown right; sleep 0.8; K1=$(A fp_keys state); C1=$(A fp_combat state); sleep 0.7; mup right; sleep 1
    mclick left 80; waitf 5 kge fs_ends $(( $(fld fs_ends <<<"$K0") + 1 )); K=$(A fp_keys state); C2=$(A fp_combat state)
    ev="bow=$(bow_now) RMB held: ui_state=$(fld ui_state <<<"$K1") ranged=$(fld ranged <<<"$K1") why=$(fld why <<<"$C1") wih $W0->$(fld wih <<<"$K1")->$(fld wih <<<"$K") sheathes $(fld sheathes <<<"$C0")->$(fld sheathes <<<"$C2") reload_starts $(fld reload_starts <<<"$C0")->$(fld reload_starts <<<"$C2") | LMB: free_swings $(fld free_swings <<<"$K0")->$(fld free_swings <<<"$K") actual_shots $(fld actual_shots <<<"$C0")->$(fld actual_shots <<<"$C2") wrong_weapon_log=$(kfplines | grep -c 'wrong_weapon')"
    ok=1; [ "$(fld ui_state <<<"$K1")" = blocking ] && [ "$(fld ranged <<<"$K1")" = 0 ] && [ "$(fld why <<<"$C1")" = melee_in_hands ] || ok=0
    [ "$(fld wih <<<"$K1")" = "$W0" ] && [ "$(fld wih <<<"$K")" = "$W0" ] && [ "$(fld sheathes <<<"$C2")" = "$(fld sheathes <<<"$C0")" ] && [ "$(fld reload_starts <<<"$C2")" = "$(fld reload_starts <<<"$C0")" ] || ok=0
    inc "$(fld free_swings <<<"$K0")" "$(fld free_swings <<<"$K")" && [ "$(fld actual_shots <<<"$C2")" = "$(fld actual_shots <<<"$C0")" ] || ok=0
    judge PT12 $ok "$ev"; fi; draw_to 0; fi; fi
A fp_combat off >/dev/null; A fp_combat physical >/dev/null

# ---- PT16: KO'd and carried by the mate ----
iscarried() { kis carried 1; }
notcarried() { kis carried 0; }
if want PT16; then draw_to 0; take "$SH" >/dev/null; A pin "$MT" off >/dev/null; PINNED=${PINNED/ $MT/}
  A protect "$SH" off >/dev/null; A ko "$SH" 120 >/dev/null
  if ! waitf 15 isko "$SH"; then row PT16 FAIL "setup: $SH never knocked out"
  else sleep 1; A order "$MT" LIFT_PERSON_PLAYER_ORDER target "$SH" >/dev/null
    if ! waitf 40 iscarried; then row PT16 FAIL "setup: $MT never lifted $SH in 40 s (carried=$(ks carried) down=$(ks down) $MT: $(A where "$MT" | cut -c1-100))"
    else sleep 1; K=$(A fp_keys state); CL=$(kfplines | grep '\[down\] carried=1' | tail -1 | cut -c1-140)
      A screenshot pt16-carried >/dev/null
      ev="carried=$(fld carried <<<"$K") down=$(fld down <<<"$K") ui_state=$(fld ui_state <<<"$K") fp=$(fld fp <<<"$K") log='$CL' screenshot=shots/pt16-carried.png"
      ok=1; [ "$(fld carried <<<"$K")" = 1 ] && [ "$(fld down <<<"$K")" = 1 ] && [ -n "$CL" ] || ok=0; judge PT16 $ok "$ev"
      A order "$MT" PUT_DOWN_OBJECT >/dev/null; waitf 20 notcarried || note "PT16: still carried 20 s after PUT_DOWN_OBJECT"; fi
  fi
  A protect "$SH" on >/dev/null; waitf 20 notko "$SH" || note "PT16: $SH still KO after protect on"; fi

[ -n "$TGH" ] && { A pin "$TGH" off >/dev/null; PINNED=${PINNED/ $TGH/}; isko "$TGH" || A ko "$TGH" 3600 >/dev/null; }
finish
