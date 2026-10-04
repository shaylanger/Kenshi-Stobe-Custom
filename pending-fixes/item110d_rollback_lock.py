#!/usr/bin/env python3
"""Item 110 (d) / HANDOFF to-do 20: playthrough rollback never runs without its lock.

Cause: the rollback's advisory lock key 937463 was the same key the regular
memory-summary and auto-diary cycles hold while they wait for an LLM reply, so a
save load that arrived during such a cycle logged "rollback lock busy, continuing
without lock" and pruned/restored unlocked, also concurrently with the other
load-time requests (init, player_base_state, npc_snapshot, ...).

Fix:
- the rollback gets its own key (937464);
- a busy lock is waited for (PLAYTHROUGH_ROLLBACK_LOCK_WAIT_MS, default 15000);
  the request that gets it next re-reads the clock and sees the rollback done;
- if it is still busy after the wait the request skips the rollback cleanly
  (reason rollback_lock_busy, clock untouched so the next load event retries).

Usage: python3 item110d_rollback_lock.py <tree root>
"""
import sys, pathlib

root = pathlib.Path(sys.argv[1])
p = root / "lib/playthrough_rollback.php"
s = p.read_text()

pairs = [
    (
        """function stobePlaythroughRollbackLockKey(): int
{
    return 937463;
}

function stobePlaythroughAcquireRollbackLock(): bool
{
    $db = $GLOBALS['db'] ?? null;
    if (!$db) {
        return false;
    }

    $row = $db->fetchOne(
        'SELECT pg_try_advisory_lock($1) AS locked',
        [stobePlaythroughRollbackLockKey()]
    );
    if (!$row) {
        return false;
    }

    return stobePlaythroughToBool($row['locked'] ?? false);
}
""",
        """// Item 110: own key. 937463 is the memory-summary / auto-diary lock, held during LLM calls.
function stobePlaythroughRollbackLockKey(): int
{
    return 937464;
}

/** How long a request waits for another request's rollback before it skips its own (ms). */
function stobePlaythroughRollbackLockWaitMs(): int
{
    return max(0, min(60000, getSettingInt('PLAYTHROUGH_ROLLBACK_LOCK_WAIT_MS', 15000)));
}

function stobePlaythroughAcquireRollbackLock(int $waitMs = 0): bool
{
    $db = $GLOBALS['db'] ?? null;
    if (!$db) {
        return false;
    }

    $deadline = microtime(true) + max(0, $waitMs) / 1000.0;
    while (true) {
        $row = $db->fetchOne(
            'SELECT pg_try_advisory_lock($1) AS locked',
            [stobePlaythroughRollbackLockKey()]
        );
        if ($row && stobePlaythroughToBool($row['locked'] ?? false)) {
            return true;
        }
        if (!$row || microtime(true) >= $deadline) {
            return false;
        }
        usleep(100000);
    }
}
""",
    ),
    (
        """    $lockAcquired = stobePlaythroughAcquireRollbackLock();
    if (!$lockAcquired) {
        stobeLogWarn('PLAYTHROUGH: rollback lock busy, continuing without lock', [
            'incoming_gamets' => $incoming,
            'last_seen_gamets' => $lastSeen,
            'event_type' => $event,
        ]);
    }
""",
        """    // Item 110: never roll back unlocked. The load sends several authoritative requests at
    // once; one rolls back, the others wait and then see the new clock (forward_or_same_after_lock).
    $lockWaitStarted = microtime(true);
    $lockAcquired = stobePlaythroughAcquireRollbackLock(stobePlaythroughRollbackLockWaitMs());
    $lockWaitedMs = intval(round((microtime(true) - $lockWaitStarted) * 1000));
    if (!$lockAcquired) {
        stobeLogWarn('PLAYTHROUGH: rollback lock busy, rollback skipped', [
            'incoming_gamets' => $incoming,
            'last_seen_gamets' => $lastSeen,
            'event_type' => $event,
            'waited_ms' => $lockWaitedMs,
        ]);
        if (!empty($GLOBALS['pgr_operation']) && function_exists('pgr_fail')) {
            pgr_fail('Another request held the rollback lock.');
        }
        return ['triggered' => false, 'reason' => 'rollback_lock_busy'];
    }
    if ($lockWaitedMs >= 200) {
        stobeLogInfo('PLAYTHROUGH: waited for rollback lock', [
            'incoming_gamets' => $incoming,
            'event_type' => $event,
            'waited_ms' => $lockWaitedMs,
        ]);
    }
""",
    ),
]

for old, new in pairs:
    if new in s:
        print("already applied:", new.splitlines()[0][:60])
        continue
    assert s.count(old) == 1, f"anchor not found once: {old[:70]!r}"
    s = s.replace(old, new)
p.write_text(s)
print("ok", p)
