#!/usr/bin/env python3
"""Item 48 (Stobe.dll): a line whose speaker is dead or unconscious is not spoken.

Run 12: a raider's COUNTER arrived 2 s after he died (the LLM call started while he was
dying). The server drops deal replies from NPCs it knows are out, but its knockout/death
events can lag; the game's own state decides here. Dying but conscious still speaks.

Usage: patch_stobe_r26_48_no_say_when_out.py <STOBE-src root>  (idempotent)
"""
import sys
from pathlib import Path

f = Path(sys.argv[1]) / 'src/main.cpp'
s = f.read_text(encoding='utf-8')
marker = 'NPC_SAY dropped: speaker is dead or unconscious (item 48)'
if marker in s:
    print('already patched', f)
    sys.exit(0)
old = '''        if (bubbleContent.empty() && !utteranceId.empty()) {
          PostSpeechDeliveryState(utteranceId, "cancelled");
        }
'''
new = '''        if (!bubbleContent.empty() && isNPCSay) {
          // Item 48: a reply that arrives after its speaker died or was knocked out isn't spoken.
          Character *sayer = ResolveCharacterFromHandSafe(thisptr, targetHand);
          if (sayer && (uintptr_t)sayer > 0x1000 && !sayer->isPlayerCharacter() &&
              (sayer->isDead() || sayer->isUnconcious())) {
            Log("HOOK_MSG_PROC: NPC_SAY dropped: speaker is dead or unconscious (item 48): " +
                sayer->getName() + ": " + bubbleContent);
            bubbleContent = "";
          }
        }
''' + old
assert s.count(old) == 1, 'anchor'
s = s.replace(old, new)
f.write_text(s, encoding='utf-8')
print('patched', f)
