#!/usr/bin/env python3
"""Item 86: deal-5f062ad7 (Skarven, surrender, he paid 100) went BREACHED_PLAYER 10 s after the
payment: while the personal truce held (re-applied every second) the game kept re-reporting
"Shay: Initiated attack (talking to: Skarven)" every 4 s with no hit landing; the server read that as
the player resuming the fight. (a) A player-side "Initiated attack" breaks a truce / SPARE only if
real harm to the NPC follows (a major hit from the player side, a knockout by the player side, or
his death) within 8 s. (b) A load of an older save cancels in-flight deals created after the loaded
game time (status CANCELLED, note rolled_back_by_load, no consequences, no reputation change).
Usage: item86_false_breach_and_rollback.py <tree root>"""
import sys, pathlib

root = pathlib.Path(sys.argv[1])

def patch(rel, old, new):
    p = root / rel
    s = p.read_text(encoding='utf-8')
    if new in s:
        print(f'{rel}: already patched'); return
    n = s.count(old)
    assert n == 1, f'{rel}: anchor found {n} times'
    p.write_text(s.replace(old, new), encoding='utf-8')
    print(f'{rel}: patched')

E = 'lib/negotiation_engine.php'
patch(E,
r'''function stobeNegNpcDied(string $npc, int $sinceUnix): bool {''',
r'''/**
 * Item 86: did the player side really hurt $npc between $fromUnix and $toUnix? A major hit from the
 * player side, a knockout by the player side, or his death. "Initiated attack" alone is not harm:
 * the game re-reports it while a personal truce holds.
 */
function stobeNegPlayerHarmedNpc(string $npc, string $player, int $fromUnix, int $toUnix): bool {
    try {
        $rows = $GLOBALS['db']->fetchAll(
            "SELECT type, data FROM eventlog WHERE type IN ('major_damage','knockout','death')
               AND localts >= $1 AND localts <= $2 AND data LIKE $3 ORDER BY localts LIMIT 40",
            [$fromUnix, $toUnix, '%' . $npc . '%']);
    } catch (Throwable $e) {
        return true; // can't tell: keep the old behaviour
    }
    foreach (is_array($rows) ? $rows : [] as $row) {
        $data = trim(strval($row['data'] ?? ''));
        if (!str_starts_with(strtolower($data), strtolower($npc) . ':')) continue;
        if ($row['type'] === 'death') return true;
        if (preg_match('/took a major hit from\s+(.+?)(?:\s+using\s+.+)?$/', $data, $m) && stobeNegIsPlayerSide(trim($m[1]), $player)) return true;
        if (preg_match('/Knocked out by .+? from\s+(.+?)\s*$/i', $data, $m) && stobeNegIsPlayerSide(trim($m[1]), $player)) return true;
    }
    return false;
}

/** Item 86: a load of an older save cancels in-flight deals created after the loaded game time. */
function stobeNegCancelDealsAfterRollback(int $cutoffGamets): int {
    if ($cutoffGamets <= 0) return 0;
    try {
        stobeNegEnsureSchema();
        $rows = $GLOBALS['db']->fetchAll(
            "UPDATE stobe_social_contract SET status='CANCELLED', consequences_applied=TRUE, resolved_at=NOW(), updated_at=NOW(),
                    evidence=(CASE WHEN jsonb_typeof(evidence)='object' THEN evidence ELSE '{}'::jsonb END) || jsonb_build_object('note','rolled_back_by_load','cutoff_gamets',$1::bigint)
              WHERE status IN ('PROPOSED','COUNTERED','ACCEPTED','AWAITING_PERFORMANCE')
                AND COALESCE(NULLIF(baseline->>'gamets','')::bigint, 0) > $1
            RETURNING contract_id", [$cutoffGamets]);
        $ids = array_map(static fn($r) => strval($r['contract_id']), is_array($rows) ? $rows : []);
        if (count($ids) > 0) {
            $GLOBALS['db']->exec("DELETE FROM stobe_negotiation_directive WHERE contract_id = ANY($1::text[])", ['{' . implode(',', $ids) . '}']);
            stobeLogInfo('Deals from after the loaded save cancelled (item 86)', ['cutoff_gamets'=>$cutoffGamets, 'deals'=>$ids]);
        }
        return count($ids);
    } catch (Throwable $e) {
        stobeLogWarn('Deal rollback failed (item 86)', ['error'=>$e->getMessage()]);
        return 0;
    }
}

function stobeNegNpcDied(string $npc, int $sinceUnix): bool {''')

patch(E,
r'''                if (stobeNegCharMatches($ev['target'], $npc) && stobeNegIsPlayerSide($ev['attacker'], $player)) {
                    $term['status'] = 'VOID';''',
r'''                if (stobeNegCharMatches($ev['target'], $npc) && stobeNegIsPlayerSide($ev['attacker'], $player)
                    && stobeNegPlayerHarmedNpc($npc, $player, intval($ev['ts']) - 2, intval($ev['ts']) + 8)) { // item 86
                    $term['status'] = 'VOID';''')

patch(E,
r'''            if (stobeNegCharMatches($ev['target'], $npc) && stobeNegIsPlayerSide($ev['attacker'], $player)) {
                $term['status'] = 'UNMET';
                $note($term, 'player_side_attacked_after_sparing', ['attacker'=>$ev['attacker']]);''',
r'''            if (stobeNegCharMatches($ev['target'], $npc) && stobeNegIsPlayerSide($ev['attacker'], $player)
                && stobeNegPlayerHarmedNpc($npc, $player, intval($ev['ts'] ?? 0) - 2, intval($ev['ts'] ?? 0) + 8)) { // item 86
                $term['status'] = 'UNMET';
                $note($term, 'player_side_attacked_after_sparing', ['attacker'=>$ev['attacker']]);''')

T = 'tests/negotiation_engine_regression.php'
patch(T,
r'''backdate($id, 7);
storeEvent('combat', time(), 1000, "$player: Initiated attack (talking to: NegTestBandit)");
stobeNegTick();
check('bug 127: an attack 12 s after sparing is', termStatus($id, 0) === 'UNMET', [status($id), termStatus($id, 0)]);''',
r'''backdate($id, 7);
storeEvent('combat', time(), 1000, "$player: Initiated attack (talking to: NegTestBandit)");
stobeNegTick();
// Item 86 (run m8): the game re-reports "Initiated attack" while a personal truce holds; no hit, no breach.
check('item 86: an "Initiated attack" 12 s after sparing with no hit is not a breach', termStatus($id, 0) !== 'UNMET', [status($id), termStatus($id, 0)]);
storeEvent('major_damage', time(), 1000, "NegTestBandit: took a major hit from $player using Machete");
stobeNegTick();
check('bug 127: an attack 12 s after sparing is (with a real hit, item 86)', termStatus($id, 0) === 'UNMET', [status($id), termStatus($id, 0)]);
// Item 86 (b): a load of an older save cancels in-flight deals created after it, no consequences.
$id86 = makeDeal('NegTestBandit', [['kind'=>'SPARE','by'=>'player','target'=>'npc']], 'surrender');
$db->exec("UPDATE stobe_social_contract SET baseline = jsonb_set(COALESCE(baseline,'{}'::jsonb), '{gamets}', '900000') WHERE contract_id=$1", [$id86]);
$rep86 = $db->fetchOne("SELECT player_kept, player_broken FROM stobe_negotiation_reputation WHERE player_name=$1", [strtolower($player)]);
$n86 = stobeNegCancelDealsAfterRollback(800000);
$row86 = stobeNegFetchDeal($id86);
check('item 86: a deal from after the loaded save is cancelled (rolled_back_by_load)',
    $n86 >= 1 && $row86['status'] === 'CANCELLED' && str_contains(strval($row86['evidence']), 'rolled_back_by_load'), [$n86, $row86['status'] ?? null]);
check('item 86: reputation unchanged by the rollback',
    $db->fetchOne("SELECT player_kept, player_broken FROM stobe_negotiation_reputation WHERE player_name=$1", [strtolower($player)]) == $rep86);
$id86b = makeDeal('NegTestBandit', [['kind'=>'SPARE','by'=>'player','target'=>'npc']], 'surrender');
$db->exec("UPDATE stobe_social_contract SET baseline = jsonb_set(COALESCE(baseline,'{}'::jsonb), '{gamets}', '700000') WHERE contract_id=$1", [$id86b]);
stobeNegCancelDealsAfterRollback(800000);
check('item 86: a deal from before the loaded save stays', stobeNegFetchDeal($id86b)['status'] !== 'CANCELLED');
$db->exec("UPDATE stobe_social_contract SET status='CANCELLED' WHERE contract_id=$1", [$id86b]);''')

R = 'lib/playthrough_rollback.php'
patch(R,
r'''        $queueCounts = stobePlaythroughClearRelationshipQueues();''',
r'''        $queueCounts = stobePlaythroughClearRelationshipQueues();
        if (function_exists('stobeNegCancelDealsAfterRollback')) {
            $restoreCounts['deals_cancelled'] = stobeNegCancelDealsAfterRollback($incoming); // item 86
        }''')
