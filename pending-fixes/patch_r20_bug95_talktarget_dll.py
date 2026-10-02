#!/usr/bin/env python3
"""Bug 95 (Stobe.dll part): lines meant for the player were tagged with a
nearby NPC as TALKTARGET. An idle (bored) turn is dispatched for a pair
(22:17:41 Pax -> Maelis); when an initiative is pending the server swaps in a
different speaker who addresses the player (Malzin's goal report, Skovrek's
"Greenlander, I'll pay you 300"). The DLL still tagged every line with the
pair's listener (Maelis), so those lines were recorded as said to Maelis and
she and others answered them.
Fix: the bored task remembers the player; a streamed line whose speaker is
neither the task's speaker nor its listener is addressed to the player.
Usage: patch_r20_bug95_talktarget_dll.py <STOBE-src tree root>"""
import sys, pathlib
root = pathlib.Path(sys.argv[1])

def patch(rel, pairs):
    p = root / rel; s = p.read_text()
    for a, b in pairs:
        if b in s: continue
        assert s.count(a) == 1, f"{rel}: anchor not found: {a[:70]!r}"
        s = s.replace(a, b)
    p.write_text(s); print("patched", p)

patch("src/ChatBox.cpp", [
    ("""  std::string previousSpeaker;
  std::string previousSpeakerHandle;
  std::string initiatorSpeaker;""",
     """  std::string previousSpeaker;
  std::string previousSpeakerHandle;
  std::string playerFallbackName;   // bug 95: who a server-swapped speaker addresses
  std::string playerFallbackHandle;
  std::string initiatorSpeaker;"""),
    ("""  task->previousSpeaker = listener;
  task->previousSpeakerHandle = listenerSerial;
  if (task->previousSpeakerHandle.empty() && listener == playerName &&""",
     """  task->previousSpeaker = listener;
  task->previousSpeakerHandle = listenerSerial;
  task->playerFallbackName = playerName;     // bug 95
  task->playerFallbackHandle = playerSerial;
  if (task->previousSpeakerHandle.empty() && listener == playerName &&"""),
    ("""        if (!listenerName.empty() && !EqualsIgnoreCase(listenerName, actor)) {
          explicitTalkTargetToken =
              BuildTalkTargetMetadataToken(listenerName, listenerHandle);
        }""",
     """        // Bug 95: the server can swap in another speaker (goal report, NPC
        // offer); that speaker addresses the player, not this turn's listener.
        std::string taskSpeaker = TrimChatLine(state->task->npcName);
        std::string fallbackName = TrimChatLine(state->task->playerFallbackName);
        if (!fallbackName.empty() && !taskSpeaker.empty() &&
            !EqualsIgnoreCase(actor, taskSpeaker) &&
            !EqualsIgnoreCase(actor, listenerName) &&
            !EqualsIgnoreCase(actor, fallbackName)) {
          Log("BORED_EVENT: speaker swapped by server (" + taskSpeaker + " -> " +
              actor + "); addressing " + fallbackName + " instead of " + listenerName);
          listenerName = fallbackName;
          listenerHandle = TrimChatLine(state->task->playerFallbackHandle);
        }
        if (!listenerName.empty() && !EqualsIgnoreCase(listenerName, actor)) {
          explicitTalkTargetToken =
              BuildTalkTargetMetadataToken(listenerName, listenerHandle);
        }"""),
])
