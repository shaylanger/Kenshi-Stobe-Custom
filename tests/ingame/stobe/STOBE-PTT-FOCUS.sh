#!/usr/bin/env bash
# id: STOBE-PTT-FOCUS
# covers: item 145 (the push-to-talk key typed into the chat box is a letter, not push-to-talk: Shay's 2026-10-07
#         session had 100+ `STT_RESULT: rejected reason=Hold push-to-talk longer` from ~70 ms taps while typing).
#         Needs Stobe 9d19bfc+ (focus guard) and 454c257+ (`stobe_npcinfo chatwith/chatclose`).
# fixture: kah-npcpanel (Shay + Malzin, Apothecary Abia in town).
# usage: PLAYER=Shay MATE=Malzin bash STOBE-PTT-FOCUS.sh
# verify: chat window open on the trader (its text field has key focus), the PTT key held 400 ms ->
#         `STT_CAPTURE: push-to-talk key ignored while a text field has focus` and no other STT_CAPTURE/STT_RESULT line;
#         control: chat closed, the same hold -> some other STT_CAPTURE/STT_RESULT line (capture started or was
#         blocked), so the key really reached Stobe's PTT path. The "ignored" line is logged at most once a minute:
#         the focused half runs first.
set -u
. "$(dirname "$0")/stobe-fight-lib.sh"
TRADER="${TRADER:-Apothecary Abia}"
INI="/mnt/d/Steam/steamapps/common/Kenshi/RE_Kenshi/mods/Stobe/StobeCustom.ini"
A() { stobe-auto "$@" 2>&1; }
lines() { grep -a -c "" "$L" 2>/dev/null || echo 0; }
since() { tail -n +"$(( $1 + 1 ))" "$L"; }
other_stt() { since "$1" | grep -a -E "STT_CAPTURE:|STT_RESULT:" | grep -a -v -c "ignored while a text field"; }

KEY=$(grep -a -i '^PushToTalkHotkey=' "$INI" 2>/dev/null | head -1 | cut -d= -f2 | tr -d '\r' | tr 'A-Z' 'a-z')
[ -n "$KEY" ] || KEY=$(grep -a -i -h '^PushToTalkHotkey=' /mnt/d/Steam/steamapps/common/Kenshi/RE_Kenshi/mods/Stobe/*.ini 2>/dev/null | head -1 | cut -d= -f2 | tr -d '\r' | tr 'A-Z' 'a-z')
ISO_SET=0
cleanup() { A key_inject "${KEY:-u}" up >/dev/null; A stobe_npcinfo chatclose >/dev/null
  [ "$ISO_SET" = 1 ] && A input_isolation off >/dev/null; }
trap cleanup EXIT

[ -n "$KEY" ] || setup_fail 145 "PushToTalkHotkey not found in the Stobe ini"
if ! A input_isolation status | grep -q 'isolation=on'; then A input_isolation on >/dev/null; ISO_SET=1
  A input_isolation status | grep -q 'isolation=on' || setup_fail 145 "input isolation would not turn on (key_inject needs it)"; fi
A select "$PLAYER" >/dev/null

# focused: chat window open on the trader, PTT key held like a slow typist
A stobe_npcinfo chatwith "$TRADER" >/dev/null; sleep 2
m=$(lines)
A key_inject "$KEY" tap 400 >/dev/null; sleep 3
ign=$(since "$m" | grep -a -c "ignored while a text field")
oth=$(other_stt "$m")
A stobe_npcinfo chatclose >/dev/null; sleep 2

# control: chat closed, same hold
m2=$(lines)
A key_inject "$KEY" tap 400 >/dev/null; sleep 4
ctl=$(other_stt "$m2")
ctl_line=$(since "$m2" | grep -a -E "STT_CAPTURE:|STT_RESULT:" | head -1 | cut -c1-140)

ev="key=$KEY focused: ignored=$ign other_stt=$oth | closed: stt_lines=$ctl ('$ctl_line')"
if [ "$ctl" -lt 1 ]; then verdict 145 "SETUP FAIL the PTT key never reached Stobe with the chat closed ($ev)"
elif [ "$ign" -ge 1 ] && [ "$oth" = 0 ]; then verdict 145 "PASS $ev"
else verdict 145 "FAIL $ev"; fi
