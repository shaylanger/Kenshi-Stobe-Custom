#!/usr/bin/env python3
"""Bug 115 follow-up: log "hungry" / "food in her pack" once per hungry spell.

With the game feeding her from her pack, KenshiFP re-checks every game
minute; between the game's own eating and the 150 start level that logged
two lines a minute. Remember that the pack note was given (packnote) and
stay quiet until she is fed (level >= SGM_STOP_LEVEL).

Usage: patch_r21_bug115b_meal_quiet.py <KenshiFP root>   (idempotent)
"""
import sys
from pathlib import Path

path = Path(sys.argv[1]) / 'client' / 'stobe_task_goals.inc'
text = path.read_text(encoding='utf-8')
if 'packnote' in text:
    print('already patched')
    sys.exit(0)
edits = [
    ("typedef struct { uint32_t serial; int eating; int eaten; int warned; float last_d; int still; DWORD next_ms; DWORD retry_ms; } SgmMeal;\n",
     "typedef struct { uint32_t serial; int eating; int eaten; int warned; float last_d; int still; DWORD next_ms; DWORD retry_ms; int packnote; } SgmMeal;\n"),
    ("        if(lvl>=SGM_START_LEVEL){if(lvl>=SGM_STOP_LEVEL)m->warned=0;m->retry_ms=0;return 0;}\n",
     "        if(lvl>=SGM_START_LEVEL){if(lvl>=SGM_STOP_LEVEL){m->warned=0;m->packnote=0;}m->retry_ms=0;return 0;}\n"),
    ("        logline(\"[stobe] GOAL_MEAL hungry actor=%s level=%.0f\",name,lvl);\n    }\n",
     "        if(!m->packnote)logline(\"[stobe] GOAL_MEAL hungry actor=%s level=%.0f\",name,lvl);\n    }\n"),
    ("        logline(\"[stobe] GOAL_MEAL food in her pack; the game feeds her actor=%s level=%.0f\",name,lvl);\n",
     "        if(!m->packnote){m->packnote=1;logline(\"[stobe] GOAL_MEAL food in her pack; the game feeds her actor=%s level=%.0f\",name,lvl);}\n"),
]
for old, new in edits:
    assert text.count(old) == 1, 'anchor not found exactly once: %r' % old[:70]
    text = text.replace(old, new)
path.write_text(text, encoding='utf-8', newline='')
print('patched', path)
