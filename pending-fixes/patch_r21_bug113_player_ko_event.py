#!/usr/bin/env python3
"""Bug 113: the player's own knockout/recovery/death is never an event.

The NPC event sweep skips knockout, recovered and death events for the
controlled character (`if (!isPlayerActor)`), so when Shay went down in a
raid nobody knew (NPCs can't react) and the safety watch that pauses on
"[EVENT] knockout: Shay" never fired. Emit those three for the player too;
slavery/carry events stay NPC-only.

Usage: patch_r21_bug113_player_ko_event.py <STOBE tree root>   (idempotent)
"""
import sys
from pathlib import Path

path = Path(sys.argv[1]) / 'src' / 'main.cpp'
text = path.read_text(encoding='utf-8')
old = """    if (!isPlayerActor) {
      if (!state.unconscious && unconsciousNow) {
        EmitKnockoutEvent(npc);
      } else if (state.unconscious && !unconsciousNow && !deadNow) {
        EmitRecoveredEvent(npc);
      }
      if (!state.dead && deadNow) {
        EmitDeathEvent(npc);
      }
      if (!state.enslaved && enslavedNow) {"""
new = """    // Bug 113: the player's own knockout/recovery/death are events too.
    if (!state.unconscious && unconsciousNow) {
      EmitKnockoutEvent(npc);
    } else if (state.unconscious && !unconsciousNow && !deadNow) {
      EmitRecoveredEvent(npc);
    }
    if (!state.dead && deadNow) {
      EmitDeathEvent(npc);
    }
    if (!isPlayerActor) {
      if (!state.enslaved && enslavedNow) {"""
if 'Bug 113' in text:
    print('already patched')
    sys.exit(0)
assert text.count(old) == 1, 'anchor not found exactly once'
path.write_text(text.replace(old, new), encoding='utf-8', newline='')
print('patched', path)
