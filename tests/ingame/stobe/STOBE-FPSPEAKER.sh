#!/usr/bin/env bash
# id: STOBE-FPSPEAKER
# covers: item 136 (a chat typed while KenshiFP controls a squad member speaks as the FP-controlled character, not
#         the selected one) and item 135 (NPC info panel on a squad member: the observer is the FP-controlled
#         character). Needs Stobe 454c257+ (`stobe_say ... ui`, `stobe_npcinfo chatwith/chatclose`) and KenshiFP
#         e9d3954d+ (exports KenshiFP_ControlledCharacter).
# fixture: kah-npcpanel (Shay + Malzin, Apothecary Abia in town). Leaves a recruited "Hungry Bandit" in the squad
#          (run-batch reloads the save per row).
# usage: PLAYER=Shay MATE=Malzin bash STOBE-FPSPEAKER.sh [rows]   rows = 136 135 (default both)
# verify: 136 = stobe.log `CHAT_SEND_STAGE: resolved_speaker=<mate>` after `stobe_say <trader> <text> ui` (the chat
#         window's Send path, no speaker override) with FP on the mate and the player selected.
#         135 = `NPC_PANEL: request why=hotkey_chat|chat_info_button target=<mate> ... speaker=<player>` with FP on
#         the player, the mate selected and the chat window open on the mate with a THIRD squad member as the chat
#         speaker: without the FP observer the pair falls back to that third member, so the row discriminates.
set -u
. "$(dirname "$0")/stobe-fight-lib.sh"
ROWS="${*:-136 135}"
want() { case " $ROWS " in *" $1 "*) return 0 ;; esac; return 1; }
TRADER="${TRADER:-Apothecary Abia}"

A() { stobe-auto "$@" 2>&1; }
fld() { grep -o "\b$1=[^ ]*" | head -1 | cut -d= -f2; }
id_of() { A where "$1" | grep -o '#[0-9]*' | head -1 | tr -d '#'; }
fp_is() { [ "$(A fp_state | fld fp_mode)" = "$1" ]; }
ctl_is() { local ids id; ids=$(A fp_control state | fld control_ids); id=$(id_of "$1"); [ -n "$id" ] && grep -qE "(^|/)$id(/|$)" <<<"$ids"; }
fp_take() { A select "$1" >/dev/null; wait_for 6 selected_is "$1"; A fp_control take >/dev/null; wait_for 6 ctl_is "$1"; }
lines() { grep -a -c "" "$L" 2>/dev/null || echo 0; }
# wait_log <mark> <secs> <fixed-string>: first matching stobe.log line written after <mark>
wait_log() {
  local t=$(( $(date +%s) + $2 )) r
  while :; do
    r=$(tail -n +"$(( $1 + 1 ))" "$L" | grep -a -F "$3" | head -1)
    [ -n "$r" ] && { echo "$r"; return 0; }
    [ "$(date +%s)" -ge "$t" ] && return 1; sleep 1
  done
}

FP0=$(A fp_state | fld fp_mode); ISO_SET=0
cleanup() {
  A stobe_npcinfo close >/dev/null; A stobe_npcinfo chatclose >/dev/null
  fp_take "$PLAYER" >/dev/null 2>&1
  [ -n "$FP0" ] && A fp_mode "$([ "$FP0" = 1 ] && echo on || echo off)" >/dev/null
  [ "$ISO_SET" = 1 ] && A input_isolation off >/dev/null
  A select "$PLAYER" >/dev/null
}
trap cleanup EXIT

preflight FPSPEAKER "$TRADER"
A fp_state | grep -q "fp_mode=" || setup_fail FPSPEAKER "KenshiFP fp_state not answering: $(A fp_state | cut -c1-120)"
A fp_mode on >/dev/null; wait_for 6 fp_is 1 || setup_fail FPSPEAKER "fp_mode on did not stick: $(A fp_state | cut -c1-120)"

if want 136; then
  RESULT_LOG="$L"
  fp_take "$MATE" || setup_fail 136 "could not take FP control of $MATE ($(A fp_control state | cut -c1-160))"
  A select "$PLAYER" >/dev/null; wait_for 6 selected_is "$PLAYER" || setup_fail 136 "cannot reselect $PLAYER"
  ctl_is "$MATE" || setup_fail 136 "selecting $PLAYER moved FP control off $MATE ($(A fp_control state | cut -c1-160))"
  m=$(lines)
  r=$(A stobe_say "$TRADER" "Hello there, how is business" ui)
  case "$r" in *"ui=1"*) ;; *) verdict 136 "FAIL stobe_say ui rejected: $(echo "$r" | tail -1 | cut -c1-140)"; r="" ;; esac
  if [ -n "$r" ]; then
    if ln=$(wait_log "$m" 15 "CHAT_SEND_STAGE: resolved_speaker="); then
      sp=$(echo "$ln" | sed -E 's/.*resolved_speaker=(.*) dist_to_target=.*/\1/')
      if [ "$sp" = "$MATE" ]; then verdict 136 "PASS resolved_speaker=$sp (FP=$MATE, selected=$PLAYER, ui send to $TRADER)"
      else verdict 136 "FAIL resolved_speaker=$sp, want FP-controlled $MATE (selected=$PLAYER)"; fi
    else
      verdict 136 "FAIL no CHAT_SEND_STAGE resolved_speaker line in 15 s after say ui ($(tail -n +"$(( m + 1 ))" "$L" | grep -a -E 'TEST_INBOX: say_ui|CHAT_GATE|CHAT_SEND_STAGE' | tail -1 | cut -c1-120))"
    fi
  fi
  sleep 3   # let the reply start before the next row reselects
fi

if want 135; then
  RESULT_LOG="$L"
  # a third squad member as the chat window's speaker: without the FP observer the pair would fall back to it
  so=$(A spawn "Hungry Bandit" "Tech Hunters" near "$PLAYER" dist 30 count 1)
  h=$(echo "$so" | grep -oE '#[0-9]+/[0-9]+' | head -1)
  [ -n "$h" ] || setup_fail 135 "third member spawn failed: $(echo "$so" | tail -1 | cut -c1-120)"
  A recruit "$h" >/dev/null
  T3=$(A where "$h" | sed -E 's/ #[0-9].*//')
  fp_take "$PLAYER" || setup_fail 135 "could not take FP control of $PLAYER ($(A fp_control state | cut -c1-160))"
  A select "$MATE" >/dev/null; wait_for 6 selected_is "$MATE" || setup_fail 135 "cannot select $MATE"
  ctl_is "$PLAYER" || setup_fail 135 "selecting $MATE moved FP control off $PLAYER ($(A fp_control state | cut -c1-160))"
  r=$(A stobe_npcinfo chatwith "$MATE" "$T3")
  case "$r" in *"chat open"*"speaker=$T3"*) ;; *) setup_fail 135 "chatwith $MATE as $T3 failed: $(echo "$r" | tail -1 | cut -c1-140)" ;; esac
  sleep 1
  A input_isolation status | grep -q "isolation=on" || { A input_isolation on >/dev/null; ISO_SET=1; sleep 1; }
  m=$(lines); path=hotkey
  A key_inject backslash tap 120 >/dev/null
  if ! ln=$(wait_log "$m" 4 "NPC_PANEL: request why="); then
    # the hotkey is ignored while a MyGUI edit box has key focus (the chat input): use the Info button path
    path="info_button (hotkey blocked by chat focus)"; m=$(lines)
    A stobe_npcinfo chat >/dev/null
    ln=$(wait_log "$m" 6 "NPC_PANEL: request why=") || ln=""
  fi
  if [ -z "$ln" ]; then
    verdict 135 "FAIL no NPC_PANEL request line (hotkey nor Info) ($(tail -n +"$(( m + 1 ))" "$L" | grep -a 'NPC_PANEL' | tail -1 | cut -c1-120))"
  else
    tg=$(echo "$ln" | sed -E 's/.* target=(.*) serial=.*/\1/'); sp=$(echo "$ln" | sed -E 's/.* speaker=(.*) visible=.*/\1/')
    why=$(echo "$ln" | grep -oE 'why=[^ ]*')
    if [ "$tg" = "$MATE" ] && [ "$sp" = "$PLAYER" ]; then
      verdict 135 "PASS $why target=$tg speaker=$sp (FP=$PLAYER, selected=$MATE, chat speaker=$T3; path=$path)"
    else
      verdict 135 "FAIL $why target=$tg speaker=$sp, want target=$MATE speaker=$PLAYER (FP observer; chat speaker=$T3; path=$path)"
    fi
  fi
fi
