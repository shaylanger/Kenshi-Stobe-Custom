#!/usr/bin/env python3
"""Server round 17 (bug 45): work/task goals no longer fail with actor_serial_unavailable
when the NPC is outside the DLL's people list (e.g. working at a far machine at the base).

stobeResolveLiveParticipantSerial() gets an opt-in fallback: the stored storage_id
(hand_<serial>) from core_npc_master, only when exactly one NPC has that name.
Only the work-goal and task-goal queues opt in.

Usage: patch_round17.py <StobeServer root>
"""
import sys, pathlib

root = pathlib.Path(sys.argv[1])

def patch(rel, pairs):
    f = root / rel
    s = f.read_text()
    for old, new in pairs:
        n = s.count(old)
        assert n == 1, f"{rel}: anchor count {n}: {old[:70]!r}"
        s = s.replace(old, new)
    f.write_text(s)
    print("patched", f)

patch("lib/chat_helper_functions.php", [
    ("function stobeResolveLiveParticipantSerial(string $name): int {",
     "function stobeResolveLiveParticipantSerial(string $name, bool $allowStoredFallback = false): int {"),
    ("""            return $serial;
        }
    }
    return 0;
}

function stobeQueueKenshiFpActionRequest(""",
     """            return $serial;
        }
    }
    if ($allowStoredFallback && isset($GLOBALS['db'])) {
        // Not in this request's people list (e.g. working far off at the base):
        // use the stored serial, but only when the name is unambiguous.
        $rows = $GLOBALS['db']->fetchAll(
            "SELECT metadata->>'storage_id' AS sid FROM core_npc_master WHERE LOWER(name)=LOWER($1) AND metadata ? 'storage_id' LIMIT 2",
            [$safeName]
        );
        if (is_array($rows) && count($rows) === 1) {
            $serial = stobeParseLiveStorageSerial(strval($rows[0]['sid'] ?? ''));
            if ($serial > 0) {
                return $serial;
            }
        }
    }
    return 0;
}

function stobeQueueKenshiFpActionRequest("""),
])
patch("lib/work_goal_functions.php", [
    ("? stobeResolveLiveParticipantSerial($safeActor)",
     "? stobeResolveLiveParticipantSerial($safeActor, true)"),
])
patch("lib/task_goal_functions.php", [
    ("stobeResolveLiveParticipantSerial($actor) : 0;",
     "stobeResolveLiveParticipantSerial($actor, true) : 0;"),
])
