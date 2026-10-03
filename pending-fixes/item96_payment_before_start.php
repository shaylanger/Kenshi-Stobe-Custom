<?php
// Item 96 (REL surrender diagnosis, run m16): Rel Krag paid at once on accept (stobe.log GIVE_CATS at 17:42:43.66),
// but "Deal performance started" was only logged at 17:42:47 (after the reply was built). The NPC payment check
// looks from dispatched_unix - 3, missed the payment, re-queued it after 45 s (REISSUE_QUEUED), and the deal sat in
// AWAITING_PERFORMANCE. Fix: an NPC hand-over term dispatched with the accepting reply is searched from up to 30 s
// before the performance start (never past the previous deal with this NPC: same bound as the player-side lookback),
// kept in a separate field so the 45 s execution timeout still counts from the dispatch.
// Usage: php item96_payment_before_start.php <tree root>   (asserts anchors; refuses a second run)
$root = rtrim($argv[1] ?? '', '/');
function patch96(string $path, array $edits): void {
    $src = file_get_contents($path);
    if ($src === false) { fwrite(STDERR, "cannot read $path\n"); exit(1); }
    if (str_contains($src, 'Item 96')) { fwrite(STDERR, "$path already has item 96\n"); exit(1); }
    foreach ($edits as [$a, $b]) {
        if (substr_count($src, $a) !== 1) { fwrite(STDERR, "anchor missing in $path: " . substr($a, 0, 90) . "\n"); exit(1); }
        $src = str_replace($a, $b, $src);
    }
    file_put_contents($path, $src); echo "patched $path\n";
}
patch96("$root/lib/negotiation_engine.php", [
[<<<'A'
        foreach ($state as $idx => $t) {
            if (($t['by'] ?? '') === 'player' && in_array($t['kind'] ?? '', ['GIVE_CATS','GIVE_ITEM','RETURN_ITEM'], true)) {
                $state[$idx]['dispatched_unix'] = $now - $lookback;
            }
        }
A, <<<'B'
        foreach ($state as $idx => $t) {
            if (($t['by'] ?? '') === 'player' && in_array($t['kind'] ?? '', ['GIVE_CATS','GIVE_ITEM','RETURN_ITEM'], true)) {
                $state[$idx]['dispatched_unix'] = $now - $lookback;
            }
            // Item 96: her hand-over went out with the accepting reply and can land before this start.
            if (($t['by'] ?? '') === 'npc' && ($t['status'] ?? '') === 'DISPATCHED'
                && in_array($t['kind'] ?? '', ['GIVE_CATS','GIVE_ITEM','RETURN_ITEM'], true)) {
                $state[$idx]['evidence_since_unix'] = $now - min(30, $lookback);
            }
        }
B],
[<<<'A'
    $since = max(0, intval($term['dispatched_unix'] ?? 0) - 3);
    $baseline = stobeNegDecode($deal['baseline'] ?? []);
A, <<<'B'
    $since = max(0, intval($term['dispatched_unix'] ?? 0) - 3);
    if (isset($term['evidence_since_unix'])) $since = min($since, max(0, intval($term['evidence_since_unix']) - 3)); // Item 96
    $baseline = stobeNegDecode($deal['baseline'] ?? []);
B],
]);
// regression: inserted after the bug 126 block (section 6b) of tests/negotiation_engine_regression.php
patch96("$root/tests/negotiation_engine_regression.php", [
[<<<'A'
check('bug 126: never executed after 2 reissues -> IMPOSSIBLE', status($id) === 'IMPOSSIBLE', [status($id), termStatus($id, 0)]);
A, <<<'B'
check('bug 126: never executed after 2 reissues -> IMPOSSIBLE', status($id) === 'IMPOSSIBLE', [status($id), termStatus($id, 0)]);
// Item 96 (m16 Rel Krag): she paid with the accepting reply, 4 s before the performance start was recorded.
file_put_contents($stobeLog, ''); stobeNegResetLogCache();
$db->exec("DELETE FROM stobe_social_contract WHERE npc_name='NegTestTrader' AND player_name=$1", [$player]);
$id = makeDeal('NegTestTrader', [['kind'=>'GIVE_CATS','by'=>'npc','to'=>'player','amount'=>33]], 'social');
stobeLine("ACTION_EXEC: GIVE_CATS actor=NegTestTrader recipient=$player amount=33", time() - 5);
stobeNegBeginPerformance($id, ['GIVE_CATS@' . $player . '@33'], $player, 1000, '');
stobeNegTick();
check('item 96: payment made just before the performance start is verified', status($id) === 'COMPLETE' && termStatus($id, 0) === 'VERIFIED', [status($id), termStatus($id, 0)]);
B],
]);
