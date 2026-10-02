#!/usr/bin/env python3
"""Bug 126: a deal accepted while the NPC is down never pays.

Run 9 (tests 20/22): Trax [Dust Bandit Bowman] was knocked out when Shay
said "Trax, deal."; Stobe skipped GIVE_CATS ("unavailable actor"), left no
execution record, and 45 s later the term (and the deal) went IMPOSSIBLE.
Stral's deal earlier went the same way. Now a payment (GIVE_CATS /
GIVE_ITEM / RETURN_ITEM) with no execution record is re-sent up to twice
via a 'reissue_payment' directive that waits up to 10 minutes for her next
line (as refunds do), so she pays once she's back on her feet.

Usage: patch_r21_bug126_payment_reissue.py <StobeServer tree root>  (idempotent)
"""
import sys
from pathlib import Path

path = Path(sys.argv[1]) / 'lib' / 'negotiation_engine.php'
text = path.read_text(encoding='utf-8')
if 'bug 126' in text:
    print('already patched')
    sys.exit(0)

edits = [
    # 1. payment terms: reissue instead of IMPOSSIBLE when nothing ran
    ("""            } elseif ($age >= STOBE_NEG_EXECUTION_TIMEOUT_SECONDS) {
                $term['status'] = 'IMPOSSIBLE';
                $note($term, 'no_execution_record');
            }
            return $term;
        }
        if (in_array($kind, ['GIVE_ITEM','RETURN_ITEM','LOAN_ITEM'], true)) {""",
     """            } elseif ($age >= STOBE_NEG_EXECUTION_TIMEOUT_SECONDS) {
                $term = stobeNegReissuePayment($term, $deal, $player, $now); // bug 126
            }
            return $term;
        }
        if (in_array($kind, ['GIVE_ITEM','RETURN_ITEM','LOAN_ITEM'], true)) {""", 1),
    ("""            } elseif ($exec['blocked'] !== '' || $age >= STOBE_NEG_EXECUTION_TIMEOUT_SECONDS) {
                $term['status'] = 'IMPOSSIBLE';
                $note($term, $exec['blocked'] !== '' ? 'game_blocked_item_transfer' : 'no_execution_record', ['reason'=>$exec['blocked']]);
            }""",
     """            } elseif ($exec['blocked'] !== '') {
                $term['status'] = 'IMPOSSIBLE';
                $note($term, 'game_blocked_item_transfer', ['reason'=>$exec['blocked']]);
            } elseif ($age >= STOBE_NEG_EXECUTION_TIMEOUT_SECONDS) {
                $term = stobeNegReissuePayment($term, $deal, $player, $now); // bug 126
            }""", 1),
    # 2. the helper, before the verifier
    ("""function stobeNegEvaluateTerm(array $term, array $deal, string $player, int $now): array {""",
     """/**
 * Bug 126: a payment that left no execution record (she was knocked out, out of
 * reach) is sent again when she next speaks, up to twice, before IMPOSSIBLE.
 */
function stobeNegReissuePayment(array $term, array $deal, string $player, int $now): array {
    $token = stobeNegTermActionToken($term, $player);
    if ($token === '' || intval($term['payment_reissues'] ?? 0) >= 2 || !stobeNegPhaseEnabled(2)) {
        $term['status'] = 'IMPOSSIBLE';
        $term['evidence'][] = ['at'=>$now, 'note'=>'no_execution_record'];
        return $term;
    }
    $term['payment_reissues'] = intval($term['payment_reissues'] ?? 0) + 1;
    $term['status'] = 'REISSUE_QUEUED';
    $term['evidence'][] = ['at'=>$now, 'note'=>'payment_reissue_queued', 'attempt'=>$term['payment_reissues']];
    stobeNegQueueDirective(strval($deal['npc_name']), 'reissue_payment', strval($deal['contract_id']), [
        'actions'=>[$token],
        'term_indexes'=>[intval($term['i'])],
        'instruction'=>'You agreed to hand this over to ' . $player . ' and have not yet. Do it now, in one short line.',
    ], true);
    return $term;
}

function stobeNegEvaluateTerm(array $term, array $deal, string $player, int $now): array {""", 1),
    # 3. pending check: reissued payments wait as long as refunds
    ("""        "SELECT payload FROM stobe_negotiation_directive WHERE contract_id=$1 AND consumed_unix=0 AND created_unix >= $2",
        [$contractId, time() - STOBE_NEG_DIRECTIVE_TTL_SECONDS]""",
     """        "SELECT payload FROM stobe_negotiation_directive WHERE contract_id=$1 AND consumed_unix=0
            AND created_unix >= (CASE kind WHEN 'reissue_payment' THEN $3::bigint ELSE $2::bigint END)",
        [$contractId, time() - STOBE_NEG_DIRECTIVE_TTL_SECONDS, time() - 600]""", 1),
    # 4. delivery windows and kinds
    ("(CASE kind WHEN 'refund' THEN 600 ELSE 45 END)",
     "(CASE WHEN kind IN ('refund','reissue_payment') THEN 600 ELSE 45 END)", 3),
    ("'{settle,reissue_truce,betray,breach_react,refund}'",
     "'{settle,reissue_truce,reissue_payment,betray,breach_react,refund}'", 1),
    ("$dispatchKinds = ['settle','reissue_truce','betray','breach_react','refund'];",
     "$dispatchKinds = ['settle','reissue_truce','reissue_payment','betray','breach_react','refund'];", 1),
    ("""        if (in_array(strval($directive['kind']), ['settle','reissue_truce'], true)) {
            stobeNegMarkDirectiveDispatched($directive, $responseActions);""",
     """        if (in_array(strval($directive['kind']), ['settle','reissue_truce','reissue_payment'], true)) {
            stobeNegMarkDirectiveDispatched($directive, $responseActions);""", 1),
    ("""        if (in_array($kind, ['settle','reissue_truce','betray','breach_react','refund'], true)) {
            foreach ($directive['payload']['actions'] ?? [] as $action) {
                if (!in_array($action, $actions, true)) $actions[] = strval($action);
            }
            if (in_array($kind, ['settle','reissue_truce'], true)) stobeNegMarkDirectiveDispatched($directive, $actions);""",
     """        if (in_array($kind, ['settle','reissue_truce','reissue_payment','betray','breach_react','refund'], true)) {
            foreach ($directive['payload']['actions'] ?? [] as $action) {
                if (!in_array($action, $actions, true)) $actions[] = strval($action);
            }
            if (in_array($kind, ['settle','reissue_truce','reissue_payment'], true)) stobeNegMarkDirectiveDispatched($directive, $actions);""", 1),
    # 5. a reissued payment that was never delivered says so
    ("""                $state[$idx]['evidence'][] = ['at'=>$now, 'note'=>'truce_reissue_never_delivered'];""",
     """                $state[$idx]['evidence'][] = ['at'=>$now, 'note'=>isset($term['payment_reissues']) ? 'payment_reissue_never_delivered' : 'truce_reissue_never_delivered'];""", 1),
]
for old, new, count in edits:
    assert text.count(old) == count, 'expected %d of: %s' % (count, old[:70])
    text = text.replace(old, new)
path.write_text(text, encoding='utf-8', newline='')
print('patched', path)
