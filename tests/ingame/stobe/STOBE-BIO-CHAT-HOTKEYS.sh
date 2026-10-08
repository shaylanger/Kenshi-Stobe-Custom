#!/usr/bin/env bash
# id: STOBE-BIO-CHAT-HOTKEYS
# covers: items 146 (bio hotkey '\' shows the SELECTED character's card) and 147 ('/' chat with a squad mate
#         selected: the FP-controlled character speaks). Shay's exact steps (2026-10-08): FP on his own character,
#         selection with the physical middle mouse button (crosshair on the mate / on the sky = own character),
#         then the physical '\' or '/' key. No harness select/open shortcuts in the rows (memory repro-shays-exact-steps).
#         Needs Stobe 496FA3EA+ (NpcPanelOpenForSelected, '/' FP speaker, `CreateChatUI done ... speaker=`).
# fixture: kah-npcpanel (Shay + Malzin, Apothecary Abia in town).
# usage: PLAYER=Shay MATE=Malzin bash STOBE-BIO-CHAT-HOTKEYS.sh [rows]   rows = 146a 146b 147 (comma or space)
# verify: 146a  own char selected (MMB on the sky) + '\' -> `NPC_PANEL: request why=hotkey_selected target=<player>`
#         146b  mate selected (MMB with the crosshair on her) + '\' -> target=<mate> speaker=<player> (FP observer)
#         147   mate selected (MMB) + '/' -> `UI: CreateChatUI done target=<mate> speaker=<player>`
set -u
. "$(dirname "$0")/stobe-fight-lib.sh"
ROWS="${*:-146a 146b 147}"; ROWS=${ROWS//,/ }
want() { case " $ROWS " in *" $1 "*) return 0 ;; esac; return 1; }

A() { stobe-auto "$@" 2>&1; }
fld() { grep -o "\b$1=[^ ]*" | head -1 | cut -d= -f2; }
id_of() { A where "$1" | grep -o '#[0-9]*' | head -1 | tr -d '#'; }
pos() { A where "$1" | grep -o 'pos=[^ ]*' | cut -d= -f2 | tr ',' ' '; }
uname_() { tr ' =' '__' <<<"$1"; }
fp_is() { [ "$(A fp_state | fld fp_mode)" = "$1" ]; }
ctl_is() { local ids id; ids=$(A fp_control state | fld control_ids); id=$(id_of "$1"); [ -n "$id" ] && grep -qE "(^|/)$id(/|$)" <<<"$ids"; }
fp_take() { A select "$1" >/dev/null; wait_for 6 selected_is "$1"; A fp_control take >/dev/null; wait_for 6 ctl_is "$1"; }
lines() { grep -a -c "" "$L" 2>/dev/null || echo 0; }
wait_log() {
  local t=$(( $(date +%s) + $2 )) r
  while :; do
    r=$(tail -n +"$(( $1 + 1 ))" "$L" | grep -a -F "$3" | head -1)
    [ -n "$r" ] && { echo "$r"; return 0; }
    [ "$(date +%s)" -ge "$t" ] && return 1; sleep 1
  done
}
mmb() { A mouse_inject middle click 80 >/dev/null; sleep 0.4; }
key() { A key_inject "$1" tap 120 >/dev/null; }
# crosshair onto <npc> (same aim as fp-playtest pick_on: heights 13 10 7, 2 tries each)
aim_at() { local sx sy sz tx ty tz c e YP; read -r sx sy sz <<<"$(pos "$PLAYER")"; read -r tx ty tz <<<"$(pos "$1")"
  c=$(A fp_camera state); e=$(fld camera_y <<<"$c"); [ -n "$(fld camera_x <<<"$c")" ] && { sx=$(fld camera_x <<<"$c"); sz=$(fld camera_z <<<"$c"); }
  [ -n "$e" ] || e=$(awk -v y="$sy" 'BEGIN{print y+19}')
  YP=$(awk -v a="$sx" -v b="$sz" -v c="$tx" -v d="$tz" -v ey="$e" -v py="$ty" -v h="$2" \
     'BEGIN{L=sqrt((c-a)^2+(d-b)^2); printf "%.4f %.4f", atan2(c-a, d-b), atan2(ey-(py+h), L)}')
  A fp_camera look $YP >/dev/null; sleep 0.4; }
pick_on() { local H; for H in 13 10 7; do for _ in 1 2; do aim_at "$1" "$H"; A fp_keys pick >/dev/null; sleep 0.3
  [ "$(A fp_keys pick show | fld result)" = "$(uname_ "$1")" ] && return 0; done; done; return 1; }
sky() { A fp_camera look "$(A fp_camera state | fld yaw)" -0.9 >/dev/null; sleep 0.3; }
# physical MMB selection: crosshair on <who>, or on the sky for the controlled character
mmb_select() { if [ "$1" = "$PLAYER" ]; then sky; else pick_on "$1" || return 1; fi; mmb; wait_for 4 selected_is "$1"; }
panel_line() { tail -n +"$(( $1 + 1 ))" "$L" | grep -a -F "NPC_PANEL: request why=" | head -1; }

FP0=$(A fp_state | fld fp_mode); ISO_SET=0
cleanup() {
  A stobe_npcinfo close >/dev/null; A stobe_npcinfo chatclose >/dev/null
  [ -n "$FP0" ] && A fp_mode "$([ "$FP0" = 1 ] && echo on || echo off)" >/dev/null
  [ "$ISO_SET" = 1 ] && A input_isolation off >/dev/null
  A select "$PLAYER" >/dev/null
}
trap cleanup EXIT

preflight BIOHOTKEYS
A fp_state | grep -q "fp_mode=" || setup_fail BIOHOTKEYS "KenshiFP fp_state not answering: $(A fp_state | cut -c1-120)"
A stobe_npcinfo close >/dev/null; A stobe_npcinfo chatclose >/dev/null
A input_isolation status | grep -q "isolation=on" || { A input_isolation on >/dev/null; ISO_SET=1; sleep 1; }
A input_isolation status | grep -q "isolation=on" || setup_fail BIOHOTKEYS "input isolation would not turn on"
A fp_mode on >/dev/null; wait_for 6 fp_is 1 || setup_fail BIOHOTKEYS "fp_mode on did not stick: $(A fp_state | cut -c1-120)"
fp_take "$PLAYER" || setup_fail BIOHOTKEYS "could not take FP control of $PLAYER ($(A fp_control state | cut -c1-160))"
[ "$(A fp_state | fld cursor_hidden)" = 1 ] || setup_fail BIOHOTKEYS "FP cursor not hidden (look mode needed for MMB pick)"

# hotkey_row <row> <who to select> <want target> <want speaker>
hotkey_row() {
  RESULT_LOG="$L"
  mmb_select "$2" || { verdict "$1" "SETUP FAIL physical MMB did not select $2 (selected: $(A where @selected | head -1 | cut -c1-60))"; return; }
  ctl_is "$PLAYER" || { verdict "$1" "SETUP FAIL selecting $2 moved FP control off $PLAYER"; return; }
  local m ln tg sp; m=$(lines); key backslash
  if ! wait_log "$m" 5 "NPC_PANEL: request why=" >/dev/null; then
    verdict "$1" "FAIL '\\' opened no panel ($(tail -n +"$(( m + 1 ))" "$L" | grep -a 'NPC_PANEL' | tail -1 | cut -c1-120))"
  else
    ln=$(panel_line "$m"); tg=$(echo "$ln" | sed -E 's/.* target=(.*) serial=.*/\1/'); sp=$(echo "$ln" | sed -E 's/.* speaker=(.*) visible=.*/\1/')
    if [ "$tg" = "$3" ] && [ "$sp" = "$4" ]; then verdict "$1" "PASS $(echo "$ln" | grep -oE 'why=[^ ]*') target=$tg speaker=$sp (FP=$PLAYER, MMB-selected $2, key '\\')"
    else verdict "$1" "FAIL target=$tg speaker=$sp, want target=$3 speaker=$4 (FP=$PLAYER, MMB-selected $2; $(echo "$ln" | cut -c1-140))"; fi
  fi
  key backslash; sleep 1; A stobe_npcinfo close >/dev/null
}

want 146a && hotkey_row 146a "$PLAYER" "$PLAYER" "$MATE"
want 146b && hotkey_row 146b "$MATE" "$MATE" "$PLAYER"

if want 147; then
  RESULT_LOG="$L"
  if ! mmb_select "$MATE"; then verdict 147 "SETUP FAIL physical MMB did not select $MATE"
  else
    m=$(lines); key /
    if ln=$(wait_log "$m" 6 "UI: CreateChatUI done target="); then
      tg=$(echo "$ln" | sed -E 's/.*target=(.*) speaker=.*/\1/'); sp=$(echo "$ln" | sed -E 's/.* speaker=//' | tr -d '\r')
      if [ "$tg" = "$MATE" ] && [ "$sp" = "$PLAYER" ]; then verdict 147 "PASS chat target=$tg speaker=$sp (FP=$PLAYER, MMB-selected $MATE, key '/')"
      else verdict 147 "FAIL chat target=$tg speaker=$sp, want target=$MATE speaker=$PLAYER (FP-controlled)"; fi
    else
      verdict 147 "FAIL '/' opened no chat ($(tail -n +"$(( m + 1 ))" "$L" | grep -a -E 'UI: chat hotkey|CHAT_OPEN' | tail -1 | cut -c1-120))"
    fi
    A stobe_npcinfo chatclose >/dev/null
  fi
fi
