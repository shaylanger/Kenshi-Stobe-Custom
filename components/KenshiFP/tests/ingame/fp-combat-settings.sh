#!/usr/bin/env bash
# fp-combat-settings.sh: F10 combat settings (Shay 2026-10-07): manual combat ON by default with an in-game toggle, and
# rebindable attack / block-aim / select / interact / draw keys. Settings change through KenshiFP.ini (the F10 panel
# writes the same ini, hot-reloaded ~0.5 s); the key rows press keys through the device
# paths (harness key_inject while input isolation is on, else REAL keys via kenshi-key.ps1), so the GetAsyncKeyState/OIS
# paths the physical buttons use are what's tested. Evidence: `fp_keys binds`, `fp_keys state` counters,
# KenshiFP.log ([combat] manual combat, [settings] built/saved).
# Run in WSL with Kenshi in the world on a kah-fpxbow copy right after load (Axima = crossbow player, Malzin = mate),
# WITHOUT any `fp_combat on` before it (CS01 checks the default). Rows (one `RESULT <row> PASS|FAIL <evidence>` each):
#  CS01 DEFAULT   fresh launch: manual_combat=1 enabled=1, binds 0x01/0x02/0x04/0x02/0x52, "[combat] manual combat on (setting)"
#  CS02 TOGGLE    ini manual_combat=0 -> enabled=0; =1 -> enabled=1
#  CS03 DRAW      key_draw=']' (0xDD): pressing ']' toggles draw/holster (r_draws+r_holsters rises)
#  CS04 ATTACK    key_attack='[' (0xDB), drawn, aimed at the sky: pressing '[' = an attack click (lmb_clicks+1)
#  CS05 INTERACT  key_interact=';' (0xBA, own key), aimed at the sky: pressing ';' runs the interact pick (ctx_none+1)
#  (CS05 also: FP stays active, game freecam 0, cursor hidden: ';' is vanilla toggle_fps_camera)
#  CS06 SELECT    key_select=''' (0xDE), aimed at the sky: pressing ''' runs the select pick (mmb_none+1)
#  CS07 WINDOW    F10 opens the panel (log "+ 5 binds"), F10 closes it -> "[settings] saved", ini has manual_combat + key_attack=219
#  CS08 RESTORE   original ini written back: binds back to the defaults
# Visual parts (Shay): the panel layout, the "Press a key..." capture by click.
# Usage: fp-combat-settings.sh [player] [mate] [outdir]. Env: KFPLOG, INI.
SH=${1:-Axima}; MT=${2:-Malzin}; OUT=${3:-/tmp/fp-combat-settings}
KDIR=/mnt/d/Steam/steamapps/common/Kenshi
KFPLOG=${KFPLOG:-$KDIR/KenshiFP.log}; INI=${INI:-$KDIR/mods/KenshiFP/KenshiFP.ini}
KEY='C:\KenshiModding\tools\automation\kenshi-key.ps1'
mkdir -p "$OUT"; LOG="$OUT/log.txt"; : > "$LOG"
A() { local r; r=$(stobe-auto "$@" 2>&1); echo "> $* | $r" >> "$LOG"; echo "$r"; }
fld() { grep -o "\b$1=[^ ]*" | head -1 | cut -d= -f2; }
ks() { A fp_keys state | fld "$1"; }
bd() { A fp_keys binds | fld "$1"; }
fps() { A fp_state | fld "$1"; }
waitf() { local end=$((SECONDS+$1)); shift; while [ $SECONDS -lt $end ]; do "$@" && return 0; sleep 0.2; done; return 1; }
# kpress <vk> <ms>: harness input isolation on (kenshi-ctl launch default) -> `key_inject` (DirectInput/OIS +
# GetAsyncKeyState, the paths a physical key feeds, no focus needed); else a real key via kenshi-key.ps1 (focuses Kenshi)
ISO_MARK=${ISO_MARK:-$KDIR/mods/AutomationHarness/input_isolation.on}
kpress() { if [ -f "$ISO_MARK" ]; then local r; r=$(stobe-auto key_inject "$1" tap "$2" 2>&1)
    case "$r" in *keyboards=*) sleep "$(awk -v m="$2" 'BEGIN{printf "%.2f", (m+100)/1000}')"; echo "KEY OK injected: $r";; *) echo "KEY FAIL injected: $r";; esac
  else powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$KEY" "$1" "$2" </dev/null 2>&1 | tr -d '\r'; fi; }
# a stray free-cursor toggle (shared desktop Alt) makes FP drop the key: clear it before every press (logged)
key() { local r; [ "$(fps free)" = 1 ] && echo "FREE was on before $1: $(A fp_state free off)" >> "$LOG"; echo "PRE $1 $(A fp_state | grep -o "cursor_hidden=[0-9] ui_open=[0-9] ui_why=[^ ]*" ) free=$(A fp_state | fld free)" >> "$LOG"; r=$(kpress "$1" "${2:-200}")
  echo "KEY $1 $r | post: $(A fp_state | grep -o "cursor_hidden=[0-9] ui_open=[0-9] ui_why=[^ ]*")" >> "$LOG"; case "$r" in *FAIL*) return 1;; esac; return 0; }
RESULTS=()
row() { RESULTS+=("RESULT $1 $2 $3"); echo "RESULT $1 $2 $3" >> "$LOG"; }
judge() { if [ "$2" = 1 ]; then row "$1" PASS "$3"; else row "$1" FAIL "$3"; fi; }
finish() { for r in "${RESULTS[@]}"; do case "$r" in *FAIL*) echo "$r log=$LOG";; *) echo "$r";; esac; done; }
setup_fail() { finish; echo "RESULT SETUP FAIL $1 log=$LOG"; restore; exit 1; }
# setini <key> <value>: replace/append one ini line in place (truncating write keeps Vortex's hardlink), then wait
# until `fp_keys binds` shows it (hot reload polls every 500 ms)
setini() { local t; t=$(grep -v -E "^$1=" "$INI"; echo "$1=$2"); printf '%s\n' "$t" > "$INI"; sleep 1.2; }
bis() { [ "$(bd "$1")" = "$2" ]; }
cnt_up() { local v; v=$(ks "$1"); [ -n "$v" ] && [ "$v" -gt "$2" ] 2>/dev/null; }
# restore: a reload only sets the keys present, so first apply the defaults explicitly, then the original file
restore() { [ -f "$OUT/ini.bak" ] || return 0
  { grep -v -E '^(manual_combat|key_attack|key_block|key_select|key_interact|key_draw)=' "$OUT/ini.bak"
    printf 'manual_combat=1\nkey_attack=1\nkey_block=2\nkey_select=4\nkey_interact=2\nkey_draw=82\n'; } > "$INI.tmp"
  cat "$INI.tmp" > "$INI"; rm -f "$INI.tmp"; sleep 1.2; cat "$OUT/ini.bak" > "$INI"; }
[ -f "$INI" ] || setup_fail "no ini at $INI"
cp "$INI" "$OUT/ini.bak"
trap restore EXIT
logn() { wc -l < "$KFPLOG" 2>/dev/null || echo 0; }
logsince() { tail -n +"$(( $1 + 1 ))" "$KFPLOG" 2>/dev/null | tr -d '\r'; }

# ---- CS01: defaults on a fresh launch (no fp_combat on sent) ----
b=$(A fp_keys binds)
grep -a -q "\[combat\] manual combat on (setting)" "$KFPLOG"; L=$?
ok=0; grep -q "manual_combat=1 enabled=1 attack=0x01 block=0x02 select=0x04 interact=0x02 draw=0x52" <<<"$b" && [ $L = 0 ] && ok=1
judge CS01 $ok "$b log_line=$([ $L = 0 ] && echo yes || echo no)"

# ---- CS02: toggle through the ini ----
setini manual_combat 0; waitf 4 bis enabled 0; e0=$(bd enabled)
setini manual_combat 1; waitf 4 bis enabled 1; e1=$(bd enabled)
judge CS02 $([ "$e0" = 0 ] && [ "$e1" = 1 ] && echo 1 || echo 0) "off->enabled=$e0 on->enabled=$e1"

# ---- FP setup: Axima controlled, FP on, looking at the sky ----
A select "$SH" >/dev/null; A fp_control take >/dev/null; A fp_mode on >/dev/null
fpon() { [ "$(fps fp_mode)" = 1 ]; }
waitf 6 fpon || setup_fail "fp_mode did not turn on"
A fp_control take >/dev/null; A fp_keys focus on >/dev/null
yaw=$(A fp_camera state | fld yaw); A fp_camera look "${yaw:-0}" -0.9 >/dev/null; sleep 0.4

# ---- CS03: draw/holster on ']' (m51 A: kah-fpxbow's crossbow is drawn at load and the AI re-draws it after a holster,
# so the row counts the toggle: r_draws + r_holsters rises) ----
setini key_draw 221; waitf 4 bis draw 0xDD
tog() { local s; s=$(A fp_keys state); echo $(( $(fld r_draws <<<"$s") + $(fld r_holsters <<<"$s") )); }
tog_up() { [ "$(tog)" -gt "$1" ]; }
drawn_is() { [ "$(ks drawn)" = "$1" ]; }
t0=$(tog)
key 0xDD 150 || setup_fail "kenshi-key could not focus Kenshi"
waitf 4 tog_up "$t0"; t1=$(tog)
judge CS03 $([ "${t1:-0}" -gt "${t0:-0}" ] && echo 1 || echo 0) "draw=$(bd draw) draws+holsters $t0->$t1 drawn=$(ks drawn)"
drawn_is 1 || { key 0xDD 150; waitf 4 drawn_is 1; }
drawn_is 1 || setup_fail "weapon not drawn for CS04"

# ---- CS04: attack on '[' (drawn, sky) ----
setini key_attack 219; waitf 4 bis attack 0xDB
yaw=$(A fp_camera state | fld yaw); A fp_camera look "${yaw:-0}" -0.9 >/dev/null; sleep 0.3
# m51 L: the game re-holstered the crossbow (drawn 1->0) between the look and the press: re-draw right before it
drawn_is 1 || { key 0xDD 150; waitf 4 drawn_is 1; }
drawn_is 1 || setup_fail "weapon holstered again before the CS04 press"
c0=$(ks lmb_clicks); key 0xDB 120; waitf 3 cnt_up lmb_clicks "$c0"; c1=$(ks lmb_clicks)
judge CS04 $([ "${c1:-0}" -gt "${c0:-0}" ] && echo 1 || echo 0) "attack=$(bd attack) lmb_clicks $c0->$c1 drawn=$(ks drawn)"

# ---- CS05: interact on its own key ';' ----
setini key_interact 186; waitf 4 bis interact 0xBA
rv0=$(fps bound_toggle_reverts); n0=$(ks ctx_none); o0=$(ks ctx_opens); key 0xBA 120; waitf 3 cnt_up ctx_none "$n0"; n1=$(ks ctx_none); o1=$(ks ctx_opens)
[ "$(fps free)" = 1 ] && A fp_state free off >/dev/null
# ';' is also Kenshi's own toggle_fps_camera: FP must swallow its bound keys (m51: the game camera took over, FP dropped)
st=$(A fp_state); act=$(fld active <<<"$st"); fc=$(fld freecam <<<"$st"); ch=$(fld cursor_hidden <<<"$st"); sw=$(fld last_swallow_dik <<<"$st")
# path 2 (RE_Kenshi's own key listener runs toggle_fps_camera): the FP front listener must eat it, so the revert backstop never fires
klf=$(fld kl_front <<<"$st"); rv1=$(fld bound_toggle_reverts <<<"$st")
judge CS05 $( { [ "${n1:-0}" -gt "${n0:-0}" ] || [ "${o1:-0}" -gt "${o0:-0}" ]; } && [ "$act" = 1 ] && [ "$fc" = 0 ] && [ "$ch" = 1 ] && [ "$klf" = 1 ] && [ "${rv1:-x}" = "${rv0:-y}" ] && echo 1 || echo 0) "interact=$(bd interact) ctx_none $n0->$n1 ctx_opens $o0->$o1 active=$act freecam=$fc cursor_hidden=$ch last_swallow_dik=$sw kl_front=$klf kl_eaten=$(fld kl_eaten <<<"$st") reverts $rv0->$rv1"

# ---- CS06: select on ''' ----
setini key_select 222; waitf 4 bis select 0xDE
m0=$(ks mmb_none); s0=$(ks mmb_selects); key 0xDE 120; waitf 3 cnt_up mmb_none "$m0"; m1=$(ks mmb_none); s1=$(ks mmb_selects)
judge CS06 $([ "${m1:-0}" -gt "${m0:-0}" ] || [ "${s1:-0}" -gt "${s0:-0}" ] && echo 1 || echo 0) "select=$(bd select) mmb_none $m0->$m1 mmb_selects $s0->$s1"

# ---- CS07: the F10 panel builds with the bind rows and saves on close ----
n=$(logn); key 0x79 150; sleep 1.5
built=$(logsince "$n" | grep -a -o "\[settings\] built [^;]*" | tail -1)
key 0x79 150; sleep 1.5
saved=$(logsince "$n" | grep -a -c "\[settings\] saved")
inil=$(grep -E "^(manual_combat|key_attack)=" "$INI" | tr -d '\r' | tr '\n' ' ')
ok=0; grep -q "+ 5 binds" <<<"$built" && [ "$saved" -ge 1 ] && grep -q "manual_combat=1" <<<"$inil" && grep -q "key_attack=219" <<<"$inil" && ok=1
judge CS07 $ok "built=\"$built\" saved=$saved ini: $inil"

# ---- CS08: restore ----
restore
waitf 4 bis attack 0x01; b=$(A fp_keys binds)
judge CS08 $(grep -q "attack=0x01 block=0x02 select=0x04 interact=0x02 draw=0x52" <<<"$b" && echo 1 || echo 0) "$b"
A fp_keys focus off >/dev/null
finish
