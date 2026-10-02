#!/usr/bin/env python3
"""Bug 131: a reissue directive claimed by the bored path was taken for "never delivered".

Run 10 (test 86): Skelden accepted while knocked out; his payment was re-queued
(REISSUE_QUEUED). When he woke, bored.php claimed the directive (consumed_unix set,
outcome still '') and asked the LLM for his line. A deal tick in those 2 s saw no
pending directive and marked the payment IMPOSSIBLE ("payment_reissue_never_delivered");
the dispatch then overwrote it. With nothing else open, the deal would have resolved
IMPOSSIBLE before the dispatch, and the payment he then made would be lost.

A directive claimed in the last 60 s whose outcome is still empty is in flight:
it still counts as pending. (A failed bored stream puts it back; a crashed one
times out after 60 s.)

Usage: patch_r22_bug131_reissue_claim_race.py <StobeServer tree root>  (idempotent)
"""
import sys
from pathlib import Path

root = Path(sys.argv[1])
lib = root / 'lib' / 'negotiation_engine.php'
text = lib.read_text(encoding='utf-8')
if 'bug 131' not in text:
    old = """        "SELECT payload FROM stobe_negotiation_directive WHERE contract_id=$1 AND consumed_unix=0
            AND created_unix >= (CASE kind WHEN 'reissue_payment' THEN $3::bigint ELSE $2::bigint END)",
        [$contractId, time() - STOBE_NEG_DIRECTIVE_TTL_SECONDS, time() - 600]
    );"""
    new = """        "SELECT payload FROM stobe_negotiation_directive WHERE contract_id=$1
            AND (consumed_unix=0 OR (consumed_unix >= $4::bigint AND outcome=''))
            AND created_unix >= (CASE kind WHEN 'reissue_payment' THEN $3::bigint ELSE $2::bigint END)",
        // Claimed by the bored path but not delivered yet: still in flight (bug 131).
        [$contractId, time() - STOBE_NEG_DIRECTIVE_TTL_SECONDS, time() - 600, time() - 60]
    );"""
    assert text.count(old) == 1, 'pending query anchor'
    text = text.replace(old, new)
    lib.write_text(text, encoding='utf-8', newline='')
    print('patched', lib)

test = root / 'tests' / 'negotiation_engine_regression.php'
t = test.read_text(encoding='utf-8')
if 'bug 131' not in t:
    anchor = """check('bug 126: reissue still waits after 5 min', termStatus($id, 0) === 'REISSUE_QUEUED', termStatus($id, 0));
"""
    add = """// Bug 131: the bored path claimed it and is still generating her line: not "never delivered".
$db->exec("UPDATE stobe_negotiation_directive SET consumed_unix=$2 WHERE contract_id=$1 AND consumed_unix=0", [$id, time()]);
stobeNegTick();
check('bug 131: a reissue being delivered stays queued', termStatus($id, 0) === 'REISSUE_QUEUED' && status($id) === 'AWAITING_PERFORMANCE', [status($id), termStatus($id, 0)]);
$db->exec("UPDATE stobe_negotiation_directive SET consumed_unix=0 WHERE contract_id=$1 AND outcome=''", [$id]);
"""
    assert t.count(anchor) == 1, 'test anchor'
    t = t.replace(anchor, anchor + add)
    test.write_text(t, encoding='utf-8', newline='')
    print('patched', test)
