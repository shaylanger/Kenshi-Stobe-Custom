<?php
declare(strict_types=1);
/**
 * imm26-wpR1: activities (Hunt / Mine / ClearGroup / camp zone) survive a save/load.
 *
 * Why: an activity record is keyed by the native load epoch (world_id). A load builds a NEW epoch, the native Reset cancels the goal
 * ('world_reset') and forgets every grant, and nothing on the server looked at records of an older epoch: the record stayed
 * 'accepted' forever, the NPC just stopped, and a pending offer could not be accepted any more.
 *
 * What this does (server only, kill switch STOBE_ACTIVITY_RESUME_ENABLED, default 1):
 *   - Sweep (activity.php poll, every ~2 s): active records of OLDER epochs are ended cleanly when they can no longer be continued
 *     (deadline passed, loaded an earlier timeline, resume cap, too long since the load, legacy protocol) or marked
 *     resume.state = pending. Nothing is left 'accepted' forever. Several stale records of one actor collapse to the newest.
 *   - Resume (activity chat turn, the only moment the native side hands out fresh candidate ids): a pending record of this
 *     actor/requester is re-grounded against the fresh native facts. A PROPOSED offer keeps its id and moves to the new epoch.
 *     An ACCEPTED job continues as a NEW agreement id with the same terms and the original deadline (the installed DLL revokes every
 *     grant of the old epoch for good, ActivityRuntimeBindings.cpp:57-59,110-113, so the old id can never be granted again);
 *     the old record ends 'superseded' with resume.continuedAs, and the outbox carries a fresh grant that the native side Start()s.
 *     No new consent is asked: the original consent stands.
 *   - Not revived: completed / failed / cancelled / expired / superseded records (they are not 'proposed'/'accepted').
 */
require_once __DIR__ . '/ActivityLifecycle.php';
require_once __DIR__ . '/ActivityAgreementAdapter.php';
require_once __DIR__ . '/ActivityStore.php';
require_once __DIR__ . '/ActivityService.php';

/** Setting lookup: environment, then the STOBE general setting, then the default. */
function stobeActivityResumeSetting(string $id, string $default): string {
    $value = getenv($id);
    if ($value !== false && $value !== '') return strval($value);
    try {
        if (function_exists('getSetting') && isset($GLOBALS['db'])) {
            $stored = getSetting($id, $default);
            if ($stored !== null && $stored !== '') return strval($stored);
        }
    } catch (Throwable $e) { /* fall through to the default */ }
    return $default;
}

function stobeActivityResumeSettings(): array {
    return [
        'enabled'      => in_array(strtolower(trim(stobeActivityResumeSetting('STOBE_ACTIVITY_RESUME_ENABLED', '1'))), ['1','true','yes','on'], true),
        'max_count'    => max(1, min(10, intval(stobeActivityResumeSetting('STOBE_ACTIVITY_RESUME_MAX_COUNT', '3')))),
        'max_age'      => max(60, min(86400, intval(stobeActivityResumeSetting('STOBE_ACTIVITY_RESUME_MAX_AGE_GAMETS', '7200')))),
        'route_radius' => max(50, min(20000, intval(stobeActivityResumeSetting('STOBE_ACTIVITY_RESUME_ROUTE_RADIUS', '1500')))),
    ];
}

function stobeActivityResumeEnabled(): bool { return stobeActivityResumeSettings()['enabled']; }

/**
 * '' when a stale record may still be continued, otherwise [status, reason, why]:
 *   cancelled / '' = a load of an EARLIER timeline (the job was never agreed there): ends quietly, no history row
 *   expired        = the agreed time ran out
 *   failed / interrupted_by_load = cap reached, too long since the load, or a legacy record that cannot be re-grounded
 */
function stobeActivityResumeVerdict(array $record, int $now, array $settings): array {
    $agreement = $record['agreement'] ?? [];
    $status = strval($record['status'] ?? '');
    if ($now < intval($record['lastNow'] ?? 0)) return ['cancelled', '', 'timeline_rollback'];
    if ($status === 'proposed') {
        if ($now >= intval($record['proposalExpiresAt'] ?? 0)) return ['expired', '', 'proposal_expired'];
        if (($record['protocol'] ?? '') !== 'stobe.activity.v2' || !isset($record['routeRef'])) return ['superseded', '', 'legacy_protocol'];
        return ['', '', ''];
    }
    if ($now >= intval($agreement['expiresAt'] ?? 0)) return ['expired', 'expired', 'expired'];
    if (($record['protocol'] ?? '') !== 'stobe.activity.v2' || !isset($record['routeRef'])) return ['failed', 'interrupted_by_load', 'legacy_protocol'];
    $resume = is_array($record['resume'] ?? null) ? $record['resume'] : [];
    if (intval($resume['count'] ?? 0) >= $settings['max_count']) return ['failed', 'interrupted_by_load', 'resume_count'];
    $since = intval($resume['interruptedAt'] ?? $now);
    if ($now - $since > $settings['max_age']) return ['failed', 'interrupted_by_load', 'too_old'];
    return ['', '', ''];
}

/** The record as it is stored when it ends without a native report. */
function stobeActivityResumeEnd(array $record, string $status, string $reason, string $why, int $now): array {
    $record['status'] = $status;
    $record['revision'] = intval($record['revision']) + 1;
    $record['lastNow'] = max(intval($record['lastNow'] ?? 0), $now);
    if ($reason !== '') $record['failureReason'] = $reason;
    $resume = is_array($record['resume'] ?? null) ? $record['resume'] : [];
    $resume['state'] = 'ended';
    $resume['why'] = $why;
    $record['resume'] = $resume;
    return $record;
}

function stobeActivityResumePending(array $record, string $world, int $now): array {
    $resume = is_array($record['resume'] ?? null) ? $record['resume'] : [];
    $resume += ['count' => 0, 'interruptedAt' => $now, 'fromWorld' => strval($record['agreement']['worldId'] ?? $world)];
    $resume['state'] = 'pending';
    $resume['note'] = 'A save/load interrupted this agreed job; it restarts as soon as the target is observed again.';
    $record['resume'] = $resume;
    return $record;
}

/**
 * Pick the fresh native candidate and route point that stand for the agreed scope, or null (transient: not observed now).
 * Hunt/Mine: same kind + source + resource; the same target serial is preferred, another target of the same source is allowed.
 * ClearGroup: the fixed target set (and camp zone) must match exactly.
 * Route: an exact label/kind/coordinate match, else the nearest fresh route point to the old one (or to the fresh source) within $radius.
 */
function stobeActivityResumeSelect(array $facts, array $record, array $routeCandidates, int $radius): ?array {
    $a = $record['agreement'];
    $oldRef = $record['discoveryRef'] ?? [];
    $best = null; $bestScore = -1;
    foreach (($facts['candidates'] ?? []) as $c) {
        if (!is_array($c) || ($c['kind'] ?? '') !== $a['kind'] || ($c['sourceId'] ?? null) !== $a['sourceId']
            || strval($c['resourceId'] ?? '') !== strval($a['resourceId'] ?? '')) continue;
        if (!is_int($c['targetSerial'] ?? null) || strval($c['candidateId'] ?? '') === '') continue;
        if (($c['pathReachable'] ?? false) !== true || ($c['observedNow'] ?? false) !== true || ($c['suitable'] ?? false) !== true
            || ($c['activityPermitted'] ?? false) !== true || ($c['protectedTarget'] ?? true) !== false
            || ($c['conflictingOrder'] ?? true) !== false) continue;
        if ($a['kind'] === 'ClearGroup' && ($c['agreedTargets'] ?? []) !== $a['agreedTargets']) continue;
        if (isset($a['campZone']) && ($c['campZone'] ?? null) !== $a['campZone']) continue;
        $score = (($c['targetSerial'] ?? 0) === ($oldRef['targetSerial'] ?? -1)) ? 2 : 1;
        if ($score > $bestScore) { $best = $c; $bestScore = $score; }
    }
    if ($best === null) return null;
    $old = $record['routeRef'];
    $route = stobeActivityResumeNearestRoute($routeCandidates, $old, $radius, true);
    if ($route === null && is_numeric($best['x'] ?? null) && is_numeric($best['y'] ?? null) && is_numeric($best['z'] ?? null)) {
        // The old waypoint is gone: the approach point nearest the (fresh) source stands in for it.
        $route = stobeActivityResumeNearestRoute($routeCandidates, $best, $radius, false);
    }
    if ($route === null) return null;
    return ['reference' => ['candidateId' => strval($best['candidateId']), 'targetSerial' => $best['targetSerial']],
            'routeSelector' => ['candidateId' => strval($route['id'])]];
}

/** Nearest native_local route point within $radius of $anchor (an exact label/kind/coordinate match wins when $exactFirst). */
function stobeActivityResumeNearestRoute(array $routeCandidates, array $anchor, int $radius, bool $exactFirst): ?array {
    $nearest = null; $nearestDistance = INF;
    foreach ($routeCandidates as $p) {
        if (!is_array($p) || ($p['source'] ?? '') !== 'native_local' || strval($p['id'] ?? '') === '') continue;
        foreach (['x','y','z'] as $axis) if (!is_numeric($p[$axis] ?? null)) continue 2;
        $distance = stobeActivityResumeDistance($p, $anchor);
        if ($exactFirst && ($p['label'] ?? null) === ($anchor['label'] ?? '') && ($p['kind'] ?? null) === ($anchor['kind'] ?? '') && $distance < 1.0) return $p;
        if ($distance < $nearestDistance) { $nearest = $p; $nearestDistance = $distance; }
    }
    return $nearest !== null && $nearestDistance <= $radius ? $nearest : null;
}

function stobeActivityResumeDistance(array $a, array $b): float {
    $d = 0.0;
    foreach (['x','y','z'] as $axis) $d += (floatval($a[$axis] ?? 0) - floatval($b[$axis] ?? 0)) ** 2;
    return sqrt($d);
}

/**
 * Shared step for one actor's stale records: collapse duplicates, honour an active record of this epoch, end what cannot continue.
 * Returns the single record that may still continue (already marked pending), or null.
 */
function stobeActivityResumeTriage(\Stobe\Activity\ActivityStore $store, string $world, int $now, array $stale, array $settings, array &$ended): ?array {
    usort($stale, static fn(array $x, array $y): int => intval($y['lastNow'] ?? 0) <=> intval($x['lastNow'] ?? 0));
    $keep = array_shift($stale);
    foreach ($stale as $duplicate) {
        $store->endStale(stobeActivityResumeEnd($duplicate, 'superseded', '', 'newer_record_exists', $now), intval($duplicate['revision']));
    }
    if ($store->activeForActor($world, intval($keep['agreement']['actor'])) !== null) {
        $store->endStale(stobeActivityResumeEnd($keep, 'superseded', '', 'new_activity_started', $now), intval($keep['revision']));
        return null;
    }
    [$status, $reason, $why] = stobeActivityResumeVerdict($keep, $now, $settings);
    if ($status !== '') {
        $record = stobeActivityResumeEnd($keep, $status, $reason, $why, $now);
        $store->endStale($record, intval($keep['revision']));
        // Only a job the player really agreed to gets a history row (a rolled-back timeline or an unanswered offer leaves none).
        if (strval($keep['status']) === 'accepted' && $status !== 'cancelled' && $status !== 'superseded') $ended[] = $record;
        return null;
    }
    if (($keep['resume']['state'] ?? '') !== 'pending') {
        $revision = intval($keep['revision']);
        $keep = stobeActivityResumePending($keep, $world, $now);
        $store->endStale($keep, $revision);
    }
    return $keep;
}

/** Poll housekeeping (no fresh native facts): nothing of an older epoch stays 'accepted' or 'proposed' for ever. */
function stobeActivityResumeSweep(\Stobe\Activity\ActivityStore $store, array $context, array &$ended): void {
    $settings = stobeActivityResumeSettings();
    if (!$settings['enabled'] || !is_int($context['now'] ?? null)) return;
    $byActor = [];
    foreach ($store->staleActive($context['worldId']) as $record) $byActor[intval($record['agreement']['actor'])][] = $record;
    foreach ($byActor as $actorId => $stale) {
        // A poisoned stale row must never break polling (a PHP-level error only; an SQL error still aborts the surrounding transaction).
        try { stobeActivityResumeTriage($store, $context['worldId'], $context['now'], $stale, $settings, $ended); }
        catch (\Throwable $e) { if (function_exists('stobeLogWarn')) stobeLogWarn('Activity resume sweep skipped an actor', ['actor' => $actorId, 'error' => $e->getMessage()]); }
    }
}

/**
 * Chat turn: continue this actor's interrupted job/offer from the fresh native facts of the request.
 * $request = the authenticated chat request (context, nativeFacts, routeCandidates). Returns the record now active in this epoch, or null.
 */
function stobeActivityResumeForChat(\Stobe\Activity\ActivityStore $store, array $request, array &$ended): ?array {
    $settings = stobeActivityResumeSettings();
    $c = $request['context'] ?? [];
    if (!$settings['enabled'] || !is_int($c['now'] ?? null) || !is_int($c['actor'] ?? null) || !is_int($c['requester'] ?? null)) return null;
    $stale = $store->staleActive($c['worldId'], $c['actor'], $c['requester']);
    if (!$stale) return null;
    $keep = stobeActivityResumeTriage($store, $c['worldId'], $c['now'], $stale, $settings, $ended);
    if ($keep === null) return null;
    $facts = stobeActivityEnrichFacts($request['nativeFacts'] ?? []);
    $pick = stobeActivityResumeSelect($facts, $keep, is_array($request['routeCandidates'] ?? null) ? $request['routeCandidates'] : [], $settings['route_radius']);
    if ($pick === null) return null;                       // target not observed now: stays pending, tried again on the next turn
    $request['nativeFacts'] = $facts;
    $request['nativeFacts']['npcWilling'] = true;          // the original consent stands; this is not a new agreement
    $accepted = strval($keep['status']) === 'accepted';
    try {
        $made = stobeActivityAdapter($request)->resume($c, $keep, $pick['reference'], $pick['routeSelector'],
            $accepted ? 'activity-' . bin2hex(random_bytes(16)) : strval($keep['agreement']['id']));
    } catch (Throwable $error) {
        if (function_exists('stobeLogDebug')) stobeLogDebug('Activity resume deferred', ['reason' => $error->getMessage()]);
        return null;                                       // grounding refused right now: stays pending
    }
    $resumed = $made['record'];
    $resume = is_array($keep['resume'] ?? null) ? $keep['resume'] : [];
    $resumed['resume'] = ['state' => 'resumed', 'count' => intval($resume['count'] ?? 0) + ($accepted ? 1 : 0),
        'interruptedAt' => intval($resume['interruptedAt'] ?? $c['now']), 'resumedAt' => $c['now'],
        'fromWorld' => strval($resume['fromWorld'] ?? ''), 'of' => strval($resume['of'] ?? $keep['agreement']['id']),
        'note' => 'A save/load interrupted this agreed job and it was picked up again; the same agreement stands, do not ask for consent again.'];
    $previousRevision = intval($keep['revision']);
    if ($accepted) {
        $previous = stobeActivityResumeEnd($keep, 'superseded', '', 'continued', $c['now']);
        $previous['resume']['continuedAs'] = $resumed['agreement']['id'];
        $store->commitResume($previous, $previousRevision, $resumed, $made['envelope'], bin2hex(random_bytes(16)));
    } else {
        $store->commitResume(null, $previousRevision, $resumed, null, bin2hex(random_bytes(16)));
    }
    return $resumed;
}
