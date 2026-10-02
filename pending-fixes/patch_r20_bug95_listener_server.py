#!/usr/bin/env python3
"""Bug 95 (server part): NPC lines were stored with the wrong addressee. Only
rechat passed 'stream_listener' to stobeStreamDialogueViaLlm(); chat and bored
replies were stored without one and stobeInferDialogueTargetForLog() guessed,
skipping the player on purpose. Malzin's reply to Shay's order ("Give me a
bit.") was stored "(talking to: Dezerka)", and nearby NPCs then treated such
lines as said to them.
Fix: chat replies are addressed to the player who spoke; bored/initiative
replies to the turn's chosen listener (the player for goal reports and offers).
Usage: patch_r20_bug95_listener_server.py <StobeServer tree root>"""
import sys, pathlib
root = pathlib.Path(sys.argv[1])

def patch(rel, pairs):
    p = root / rel; s = p.read_text()
    for a, b in pairs:
        if b in s: continue
        assert s.count(a) == 1, f"{rel}: anchor not found: {a[:70]!r}"
        s = s.replace(a, b)
    p.write_text(s); print("patched", p)

patch("processor/chat.php", [
    ("""            'stream_event_type' => 'chat',
            'stream_gamets' => $gamets,
            'defer_structured_stream' => $negotiationDefer,""",
     """            'stream_event_type' => 'chat',
            'stream_listener' => $speaker, // bug 95: replies go to whoever spoke
            'stream_gamets' => $gamets,
            'defer_structured_stream' => $negotiationDefer,"""),
])
patch("processor/bored.php", [
    ("""        'stream_event_type' => 'bored',
        'stream_gamets' => $gamets,
        'defer_structured_stream' => is_array($negDirective),""",
     """        'stream_event_type' => 'bored',
        'stream_listener' => $listener, // bug 95: the turn's real addressee
        'stream_gamets' => $gamets,
        'defer_structured_stream' => is_array($negDirective),"""),
])
