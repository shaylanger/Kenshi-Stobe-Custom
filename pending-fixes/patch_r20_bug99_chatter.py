#!/usr/bin/env python3
"""Bug 99: about 35 NPC-to-NPC lines in 10 minutes of fighting (4-6 idle turns
a minute). stobeLifelikeSignalRuntime() writes lifelike_<kind>.flag with a
45 s cooldown measured from the flag file's mtime, but Stobe.dll deletes the
flag as soon as it reads it, so the cooldown never applied: every major hit,
knockout and heal near the player forced another idle turn (~every 15 s).
Fix: the cooldown uses a separate marker file the DLL doesn't touch. Healing
and recovery only raise an initiative when they involve the player by name
(strangers patching each other no longer start conversations).
Usage: patch_r20_bug99_chatter.py <StobeServer tree root>"""
import sys, pathlib
root = pathlib.Path(sys.argv[1])

def patch(rel, pairs):
    p = root / rel; s = p.read_text()
    for a, b in pairs:
        if b in s: continue
        assert s.count(a) == 1, f"{rel}: anchor not found: {a[:70]!r}"
        s = s.replace(a, b)
    p.write_text(s); print("patched", p)

patch("lib/lifelike_npc.php", [
    ("""    $now = time();
    $mtime = @filemtime($path);
    if ($cooldownSeconds > 0 && is_int($mtime) && ($now - $mtime) < $cooldownSeconds) {
        return false;
    }
    $ok = @file_put_contents($path, strtolower(trim($eventType)) . "\\n" . $now . "\\n", LOCK_EX) !== false;""",
     """    $now = time();
    // Bug 99: the DLL deletes the flag when it reads it, so its mtime can't
    // carry the cooldown. Keep the last-signal time in our own marker file.
    $marker = rtrim(sys_get_temp_dir(), '/') . '/stobe_lifelike_' . $kind . '.last';
    $mtime = @filemtime($marker);
    if ($cooldownSeconds > 0 && is_int($mtime) && ($now - $mtime) < $cooldownSeconds) {
        return false;
    }
    @touch($marker, $now);
    $ok = @file_put_contents($path, strtolower(trim($eventType)) . "\\n" . $now . "\\n", LOCK_EX) !== false;"""),
    ("""        'carry', 'trade', 'limb_loss', 'recruit', 'join', 'leave', 'relationship'
    ], true)) {
        stobeLifelikeSignalRuntime('initiative', $type, 45);""",
     """        'carry', 'trade', 'limb_loss', 'recruit', 'join', 'leave', 'relationship'
    ], true)) {
        // Bug 99: strangers healing each other near the player aren't a reason to talk.
        $playerName = normalizeParticipantNameToken(getSetting('PLAYER_NAME', ''));
        if (in_array($type, ['healing', 'recovered'], true)
            && ($playerName === '' || stripos($eventData, $playerName) === false)) {
            return;
        }
        stobeLifelikeSignalRuntime('initiative', $type, 45);"""),
])
