<?php
declare(strict_types=1);
/**
 * imm26-sfTrav: TEST-ONLY seam that makes a travel PROPOSE deterministic on an isolated lane (sibling of imm26-sfO, which does Hunt/ClearGroup).
 *
 * Rows 20-d, 08-d, 19-e need a stored PROPOSED travel_agreement before the player's "Yes"; the model often gives no travel_decision=PROPOSE.
 * When the lane is ARMED (marker <lane>/test-inject-travel.json), the armed NPC's next travel-consent chat turn is read as if the model had answered
 * travel_decision=PROPOSE (kind/leader/destination from the marker). That synthetic reply goes through the UNCHANGED stobeTravelCapture(): the same
 * policy refusal, availability gate, destination grounding (local candidates / known places), plan hash, commitment prepare and stobeTravelWrite
 * that an LLM PROPOSE takes. Nothing is inserted by hand, nothing is granted: the player's own "Yes" still needs the model's ACCEPT with an exact
 * quote, or the normal path refuses it. If the product would refuse the offer, the product's own refusal text is what the player gets.
 *
 * GATE (all must hold, else this file does nothing and the model's reply is used as is):
 *   1. the site root is /tmp/stobe-<lane>/site (an isolated lane tree; the live tree /var/www/html/StobeServer can never match),
 *   2. the process uses a PRIVATE database socket inside that lane root (STOBE_DB_HOST under <lane>/),
 *   3. the marker exists, is valid, not expired, names this NPC (or "any") and is unused. One-shot: renamed to test-inject-travel.fired-<ts>.json.
 * Written by testing/live-stobe-queue/imm26-assert/rowtools/inject-travel.sh.
 */

function stobeTravelTestInjectLaneRoot(): ?string {
    $site = realpath(dirname(__DIR__));
    if ($site === false || basename($site) !== 'site' || !str_starts_with($site, '/tmp/stobe-')) return null;
    $lane = dirname($site);
    $db = realpath(strval(getenv('STOBE_DB_HOST') ?: ''));
    if ($db === false || !str_starts_with($db . '/', $lane . '/')) return null;
    return $lane;
}

function stobeTravelTestInjectMarker(): string {
    $site = realpath(dirname(__DIR__)) ?: dirname(__DIR__);
    return dirname($site) . '/test-inject-travel.json';
}

/** "Cind" matches "Cind" and "cind [Traders Guild]"; "any" matches every NPC. */
function stobeTravelTestInjectNameMatches(string $want, string $actor): bool {
    $want = strtolower(trim($want)); $actor = strtolower(trim($actor));
    if ($want === 'any') return true;
    if ($want === '' || $actor === '') return false;
    if ($want === $actor) return true;
    return str_starts_with($actor, $want) && in_array($actor[strlen($want)], [' ', '[', '|'], true);
}

/**
 * Called by processor/chat.php just before stobeTravelCapture(), only when the marker file exists. Returns the raw model JSON the ordinary
 * capture should now see: unchanged when nothing fires, '{"travel_decision":"NONE"}' after the injected PROPOSE already went through
 * stobeTravelCapture() here (so the ordinary capture does not record it twice). Never throws.
 * The outcome of the last call is left in $GLOBALS['STOBE_TRAVEL_TEST_INJECT_RESULT']
 * (fired | refused | trip_active | no_candidate | other_actor | gate_closed | marker_* | claim_failed | error).
 */
function stobeTravelTestInjectApply(string $raw, string $actor, array|false $npc, string $speaker, string $playerLine, int $gamets,
        string &$text, array &$actions, bool $alreadyStreamed = false): string {
    $GLOBALS['STOBE_TRAVEL_TEST_INJECT_RESULT'] = 'unset';
    $set = static function (string $r): void { $GLOBALS['STOBE_TRAVEL_TEST_INJECT_RESULT'] = $r; };
    try {
        $lane = stobeTravelTestInjectLaneRoot();
        if ($lane === null) { $set('gate_closed'); return $raw; }
        $marker = stobeTravelTestInjectMarker();
        $json = @file_get_contents($marker, false, null, 0, 8192);
        $spec = is_string($json) ? json_decode($json, true) : null;
        if (!is_array($spec) || ($spec['schema'] ?? '') !== 'STOBE_TEST_TRAVEL_INJECT_V1') { $set('marker_invalid'); return $raw; }
        if (!is_int($spec['expires_at'] ?? null) || $spec['expires_at'] < time()) { $set('marker_expired'); return $raw; }
        if (!stobeTravelTestInjectNameMatches(strval($spec['npc'] ?? ''), $actor)) { $set('other_actor'); return $raw; }
        $kind = strval($spec['kind'] ?? 'same_route'); $leader = strval($spec['leader'] ?? 'npc');
        if (!in_array($kind, ['same_route', 'detour', 'guide'], true) || !in_array($leader, ['npc', 'player'], true)) { $set('marker_terms'); return $raw; }
        $old = stobeTravelRead($actor, $speaker, $gamets);
        // The product never overwrites an accepted trip with a PROPOSE, so there is nothing to inject (marker kept).
        if (is_array($old) && ($old['status'] ?? '') === 'ACCEPTED') { $set('trip_active'); return $raw; }
        // Destination: the marker's, else the first local candidate / known place that grounds. Grounded here with the resolver the capture uses.
        $want = trim(strval($spec['destination'] ?? ''));
        $cands = $want !== '' ? [$want]
            : array_merge(array_map('strval', array_keys(stobeTravelLocalCandidates($actor, $npc))), stobeTravelKnownPlaceNames($actor, $npc, 12));
        $dest = '';
        foreach ($cands as $c) { if (stobeTravelResolvePlan($actor, $npc, $c, null)) { $dest = $c; break; } }
        if ($dest === '') {
            if (function_exists('stobeLogWarn')) stobeLogWarn('STOBE_TEST_TRAVEL_INJECT: destination does not ground for this NPC; model reply used (marker kept)',
                ['row'=>strval($spec['row'] ?? ''), 'npc'=>$actor, 'destination'=>$want]);
            $set('no_candidate'); return $raw;
        }
        $fired = $lane . '/test-inject-travel.fired-' . date('YmdHis') . '-' . bin2hex(random_bytes(3)) . '.json';
        if (!@rename($marker, $fired)) { $set('claim_failed'); return $raw; }   // one-shot: a concurrent request lost the rename
        $synthetic = ['travel_decision'=>'PROPOSE', 'travel_kind'=>$kind, 'travel_leader'=>$leader, 'travel_destination'=>$dest,
            'travel_reason'=>'Test seam offer (imm26-sfTrav)', 'travel_player_quote'=>''];
        stobeTravelCapture(json_encode($synthetic, JSON_UNESCAPED_UNICODE), $actor, $npc, $speaker, $playerLine, $gamets, $text, $actions);
        $state = stobeTravelRead($actor, $speaker, $gamets);
        $written = is_array($state) && ($state['status'] ?? '') === 'PROPOSED' && intval($state['created_gamets'] ?? -1) === $gamets;
        // The player sees an offer that matches the stored one (the model's own words may be a refusal or small talk). Product refusals stay as they are.
        if ($written && empty($spec['keep_text']) && !$alreadyStreamed) {
            $text = ($leader === 'player' ? 'I can come with you to ' : 'I can lead us to ') . strval($state['destination'] ?? $dest) . '. Shall we go?';
        }
        @file_put_contents($fired, json_encode($spec + ['fired_at'=>time(), 'synthetic'=>$synthetic, 'result'=>$written ? 'proposed' : 'refused',
            'agreement_id'=>$state['agreement_id'] ?? null, 'text'=>$text], JSON_UNESCAPED_SLASHES));
        if (function_exists('stobeLogWarn')) stobeLogWarn('STOBE_TEST_TRAVEL_INJECT fired (test seam, isolated lane only)',
            ['row'=>strval($spec['row'] ?? ''), 'npc'=>$actor, 'destination'=>$dest, 'written'=>$written]);
        $set($written ? 'fired' : 'refused');
        return '{"travel_decision":"NONE"}';
    } catch (Throwable $e) {
        $set('error');
        return $raw;
    }
}
