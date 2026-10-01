#!/usr/bin/env python3
"""Bug 90: a paid ceasefire (Murk, 500 cats) held only until the deal
completed (30 s quiet window); the hostile gang re-engaged and Murk's reply to
"we had a deal" was overwritten with "Let's get the terms straight first."
- Watch the ceasefire for 120 s (was 30), re-apply it up to 4 times (was 2).
- A combat/surrender deal with this NPC that completed in the last 10 min is
  honoured: if the reply claims a ceasefire / agreement, keep the words and
  re-issue STOP_ATTACK@player instead of the "terms" rewrite.
Usage: patch_r19_bug90_ceasefire.py <StobeServer tree root>"""
import sys, pathlib
root = pathlib.Path(sys.argv[1])

def patch(rel, pairs):
    p = root / rel; s = p.read_text()
    for a, b in pairs:
        if b in s: continue
        assert s.count(a) == 1, f"{rel}: anchor not found: {a[:70]!r}"
        s = s.replace(a, b)
    p.write_text(s); print("patched", p)

patch("tests/negotiation_engine_regression.php", [
    ("backdate($id, 31);", "backdate($id, STOBE_NEG_TRUCE_OBSERVE_SECONDS + 1);"),
    ("for ($attempt = 0; $attempt < 2; $attempt++) {", "for ($attempt = 0; $attempt < STOBE_NEG_TRUCE_MAX_REISSUE; $attempt++) {"),
])

patch("lib/negotiation_engine.php", [
    ("const STOBE_NEG_TRUCE_OBSERVE_SECONDS = 30;",
     "const STOBE_NEG_TRUCE_OBSERVE_SECONDS = 120;     // a paid ceasefire must outlast the gang's re-aggro (bug 90)"),
    ("const STOBE_NEG_TRUCE_MAX_REISSUE = 2;", "const STOBE_NEG_TRUCE_MAX_REISSUE = 4;"),
])

HELPER = r'''/**
 * Bug 90: a ceasefire deal with this NPC that completed recently (default 10 min).
 * Returns the contract row or null.
 */
function stobeDealRecentCompletedCeasefire(string $npc, int $seconds = 600): ?array {
    try {
        $row = $GLOBALS['db']->fetchOne(
            "SELECT contract_id, kind FROM stobe_social_contract
              WHERE LOWER(npc_name)=LOWER($1) AND kind IN ('combat','surrender') AND status='COMPLETE'
                AND updated_at > NOW() - ($2 || ' seconds')::interval
              ORDER BY updated_at DESC LIMIT 1",
            [$npc, strval(max(1, $seconds))]
        );
        return is_array($row) ? $row : null;
    } catch (Throwable $e) {
        return null;
    }
}

function stobeDealCaptureResponse('''
patch("lib/negotiation_phase1.php", [("function stobeDealCaptureResponse(", HELPER)])

patch("processor/chat.php", [
    ("""                } elseif (stobeDealSpeechClaimsCeasefire($responseText)
                    || preg_match("/\\\\b(deal|agreed|you'?ve got it|you got it)\\\\b/i", $responseText)) {
                    $responseText = "Let's get the terms straight first.";
                }
                $responseActions = array_values(array_filter($responseActions, static fn($a) =>
                    !preg_match('/^(STOP_ATTACK|GIVE_CATS|GIVE_ITEM|TAKE_CATS|TAKE_ITEM)@/i', strval($a))));""",
     """                } elseif ((stobeDealSpeechClaimsCeasefire($responseText)
                    || preg_match("/\\\\b(deal|agreed|you'?ve got it|you got it)\\\\b/i", $responseText))
                    && function_exists('stobeDealRecentCompletedCeasefire')
                    && ($honoured = stobeDealRecentCompletedCeasefire($targetNpc)) !== null) {
                    // Bug 90: the paid ceasefire still stands; keep her words and stop again.
                    $honourCeasefire = 'STOP_ATTACK@' . $playerName;
                    stobeLogInfo('Ceasefire honoured from a completed deal (bug 90)', ['npc'=>$targetNpc, 'contract_id'=>$honoured['contract_id'] ?? '']);
                } elseif (stobeDealSpeechClaimsCeasefire($responseText)
                    || preg_match("/\\\\b(deal|agreed|you'?ve got it|you got it)\\\\b/i", $responseText)) {
                    $responseText = "Let's get the terms straight first.";
                }
                $responseActions = array_values(array_filter($responseActions, static fn($a) =>
                    !preg_match('/^(STOP_ATTACK|GIVE_CATS|GIVE_ITEM|TAKE_CATS|TAKE_ITEM)@/i', strval($a))));
                if (!empty($honourCeasefire)) {
                    $responseActions[] = $honourCeasefire;
                    $actionConfig['deal_sanctioned_give'] = true; // let the STOP_ATTACK through (bug 88)
                }"""),
])
