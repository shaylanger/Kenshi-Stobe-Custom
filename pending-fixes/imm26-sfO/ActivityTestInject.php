<?php
declare(strict_types=1);
/**
 * imm26-sfO: TEST-ONLY seam that makes a Hunt / ClearGroup PROPOSE deterministic on an isolated lane.
 *
 * Rows 26-a..26-f, 22-a, 26-b, 26-c and the offer step of 14-d need the model to choose a PROPOSE; it often does not. When a lane
 * is ARMED (marker file below), the next chat turn of the armed NPC is read as a model PROPOSE whose activity_intent is built from
 * THAT turn's own native facts and route candidates (the lists the model is shown). Everything after that is the unchanged product
 * path in stobeActivityChatFinish(): the real adapter propose() grounding, the willingness/availability gates, the proposed record
 * in stobe_activity_record, the offer text that the native side binds to the offer it displayed, then the player's own "Yes".
 * Nothing is granted, nothing is weakened: no consent is faked.
 *
 * GATE (all must hold, otherwise this file does nothing and the model's reply is used as is):
 *   1. the site root is /tmp/stobe-<lane>/site (an isolated lane tree; the live tree /var/www/html/StobeServer can never match),
 *   2. the process uses a PRIVATE database socket inside that lane root (STOBE_DB_HOST under <lane>/),
 *   3. the marker <lane>/test-inject-activity.json exists, is valid, not expired, names this actor (or 0 = any) and is unused.
 * The marker is one-shot (renamed to test-inject-activity.fired-<ts>.json on use). Written by
 * testing/live-stobe-queue/imm26-assert/rowtools/inject-propose.sh.
 */

function stobeActivityTestInjectLaneRoot(): ?string {
    $site = realpath(dirname(__DIR__, 2));
    if ($site === false || basename($site) !== 'site' || !str_starts_with($site, '/tmp/stobe-')) return null;
    $lane = dirname($site);
    $db = realpath(strval(getenv('STOBE_DB_HOST') ?: ''));
    if ($db === false || !str_starts_with($db . '/', $lane . '/')) return null;
    return $lane;
}

function stobeActivityTestInjectMarker(): string {
    $site = realpath(dirname(__DIR__, 2)) ?: dirname(__DIR__, 2);
    return dirname($site) . '/test-inject-activity.json';
}

/**
 * Build the intent for $spec from the turn's own facts. Every candidate/route pair is run through the real adapter propose() (pure,
 * no database), the first that grounds wins. Returns the intent array, or null when nothing in this turn's facts can ground.
 */
function stobeActivityTestInjectBuildIntent(array $turn, array $spec): ?array {
    $request = $turn['request']; $context = $request['context'];
    $request['nativeFacts']['npcWilling'] = true;
    $facts = stobeActivityEnrichFacts($request['nativeFacts'] ?? []);
    $adapter = stobeActivityAdapter($request);
    $kind = strval($spec['kind']); $want = strtolower(trim(strval($spec['target'] ?? '')));
    $routes = [];
    foreach ((array)($request['routeCandidates'] ?? []) as $p) {
        if (is_array($p) && ($p['source'] ?? '') === 'native_local' && ($p['actor_serial'] ?? null) === $context['actor'] && is_string($p['id'] ?? null)) $routes[] = $p;
    }
    foreach (($facts['candidates'] ?? []) as $c) {
        if (!is_array($c) || ($c['kind'] ?? '') !== $kind || !is_string($c['candidateId'] ?? null) || !is_int($c['targetSerial'] ?? null)) continue;
        if ($want !== '') {
            $hay = strtolower(implode('|', [strval($c['sourceId'] ?? ''), strval($c['candidateId']), strval($c['targetSerial']), strval($c['resourceName'] ?? ''),
                strval($c['label'] ?? ''), implode(',', array_map('strval', (array)($c['agreedTargets'] ?? [])))]));
            if (!str_contains($hay, $want)) continue;
        }
        foreach ($routes as $route) {
            $intent = ['kind'=>$kind, 'sourceId'=>strval($c['sourceId'] ?? ''), 'resourceId'=>$kind === 'ClearGroup' ? '' : strval($c['resourceId'] ?? ''),
                'quantity'=>$kind === 'ClearGroup' ? 0 : max(1, intval($spec['quantity'] ?? 1)),
                'discoveryRef'=>['candidateId'=>$c['candidateId'], 'targetSerial'=>$c['targetSerial']],
                'agreedTargets'=>$kind === 'ClearGroup' ? array_values((array)($c['agreedTargets'] ?? [])) : [],
                'routeRef'=>['candidateId'=>$route['id']]];
            if ($kind === 'ClearGroup' && is_array($c['campZone'] ?? null)) $intent['campZoneRef'] = $c['campZone'];
            try { $adapter->propose($context, $intent); return $intent; } catch (Throwable $e) { /* next pair */ }
        }
    }
    return null;
}

/**
 * Called by stobeActivityChatFinish() only when the marker file exists. On success $reply is replaced by a PROPOSE reply and the
 * marker is consumed. Returns a short status string (never throws).
 */
function stobeActivityTestInjectApply(array $turn, &$reply): string {
    try {
        $lane = stobeActivityTestInjectLaneRoot();
        if ($lane === null) return 'gate_closed';
        $marker = stobeActivityTestInjectMarker();
        $raw = @file_get_contents($marker, false, null, 0, 8192);
        $spec = is_string($raw) ? json_decode($raw, true) : null;
        if (!is_array($spec) || ($spec['schema'] ?? '') !== 'STOBE_TEST_ACTIVITY_INJECT_V1') return 'marker_invalid';
        if (!in_array($spec['kind'] ?? '', ['Hunt', 'ClearGroup'], true)) return 'marker_kind';
        if (!is_int($spec['expires_at'] ?? null) || $spec['expires_at'] < time()) return 'marker_expired';
        $actor = intval($spec['actor'] ?? 0);
        $npc = trim(strval($spec['npc'] ?? ''));
        // actor 0 + npc name: resolve the name the way stobeActivityChatBegin() resolves the speaker (live people list, stored serial as fallback).
        if ($actor === 0 && $npc !== '') {
            $actor = function_exists('stobeResolveLiveParticipantSerial') ? stobeResolveLiveParticipantSerial($npc, true) : 0;
            if ($actor === 0) return 'npc_unresolved';
        }
        if ($actor !== 0 && $actor !== ($turn['request']['context']['actor'] ?? null)) return 'other_actor';
        $intent = stobeActivityTestInjectBuildIntent($turn, $spec);
        if ($intent === null) {
            if (function_exists('stobeLogWarn')) stobeLogWarn('STOBE_TEST_ACTIVITY_INJECT: no groundable candidate in this turn; model reply used (marker kept)',
                ['row'=>strval($spec['row'] ?? ''), 'kind'=>$spec['kind'], 'target'=>strval($spec['target'] ?? '')]);
            return 'no_candidate';
        }
        $fired = $lane . '/test-inject-activity.fired-' . date('YmdHis') . '-' . bin2hex(random_bytes(3)) . '.json';
        if (!@rename($marker, $fired)) return 'claim_failed';   // one-shot: a concurrent request lost the rename
        @file_put_contents($fired, json_encode($spec + ['fired_at'=>time(), 'intent'=>$intent], JSON_UNESCAPED_SLASHES));
        $reply = array_merge(is_array($reply) ? $reply : [], ['action'=>'Talk', 'activity_decision'=>'PROPOSE',
            'activity_intent'=>json_encode($intent, JSON_UNESCAPED_SLASHES), 'travel_decision'=>'NONE', 'deal_decision'=>'NONE', 'deal_terms'=>'']);
        if (function_exists('stobeLogWarn')) stobeLogWarn('STOBE_TEST_ACTIVITY_INJECT fired (test seam, isolated lane only)',
            ['row'=>strval($spec['row'] ?? ''), 'kind'=>$spec['kind'], 'actor'=>$turn['request']['context']['actor'] ?? null, 'intent'=>$intent]);
        return 'fired';
    } catch (Throwable $e) {
        return 'error';
    }
}
