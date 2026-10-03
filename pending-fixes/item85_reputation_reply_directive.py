#!/usr/bin/env python3
"""Item 85 (plan row 17): with shay kept=2 broken=10, a stranger offered "a job, I'll pay 200 cats
afterwards" answered "Two hundred, you say? What's the job?": the reputation line ("Word gets
around: Shay has a reputation for breaking deals.") sat inside the deal block. Like item 77, a short
closing <reply_reputation> directive now ends the system message for a non-squad NPC when the
player's line is about a deal/job/payment and the player's broken deals outnumber kept ones:
distrust, mention the reputation, payment up front or no deal, no pay-later.
Usage: item85_reputation_reply_directive.py <tree root>"""
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
r'''// ------------------------------------------------------------------ Phase 8: betrayal''',
r'''/**
 * Item 85: the closing reputation directive for a non-squad NPC when the player's line is about a
 * deal, job or payment and the player breaks more deals than they keep ('' otherwise).
 * $counts = [kept, broken] for tests; else stobe_negotiation_reputation.
 */
function stobeNegReputationReplyDirective(string $npcName, array|false $npcData, string $player, string $message, ?bool $squadMember = null, ?array $counts = null): string {
    if (trim($player) === '' || trim($message) === '') return '';
    if (!preg_match('/\b(deal|job|work\s+for|pay|paid|payment|cats?|reward|offer|trade|afterwards|later|owe|promise|hire|contract|split|share|bounty)\b/i', $message)) return '';
    if ($squadMember === null) $squadMember = is_array($npcData) && function_exists('npcIsInPlayerFaction') && npcIsInPlayerFaction($npcData);
    if ($squadMember) return '';
    if ($counts === null) {
        try {
            stobeNegEnsureSchema();
            $row = $GLOBALS['db']->fetchOne("SELECT player_kept, player_broken FROM stobe_negotiation_reputation WHERE LOWER(player_name)=LOWER($1)", [$player]);
            $counts = [intval($row['player_kept'] ?? 0), intval($row['player_broken'] ?? 0)];
        } catch (Throwable $e) {
            return '';
        }
    }
    [$kept, $broken] = [intval($counts[0] ?? 0), intval($counts[1] ?? 0)];
    if (!($broken >= 2 && $broken > $kept)) return '';
    $who = function_exists('stobePromptXmlEscape') ? stobePromptXmlEscape($player) : $player;
    return "<reply_reputation>\n"
        . '  <heard>Word gets around: ' . $who . ' has broken ' . $broken . ' deals and kept only ' . $kept . '. You have heard this and you believe it.</heard>' . "\n"
        . '  <how>Be openly distrustful about any deal, job or payment ' . $who . ' brings up: let them know you have heard they do not pay or keep their word. '
        . 'Payment later, "afterwards" or promises are worthless from them: demand the Cats up front (all of it, or a large part before you lift a finger), or refuse.</how>' . "\n"
        . '  <rule>Show this in your first words. Do not accept a pay-later offer from ' . $who . ' (no deal_decision ACCEPT unless the payment comes first).</rule>' . "\n"
        . '</reply_reputation>';
}

// ------------------------------------------------------------------ Phase 8: betrayal''')

C = 'processor/chat.php'
patch(C,
r'''// Item 77: the relationship sets the tone; its directive closes the system message (after history and memory).''',
r'''// Item 85: a deal/job/payment line from a player known to break deals (non-squad NPCs).
if (!$narratorMode && $dialogueMode !== 'cheat' && function_exists('stobeNegReputationReplyDirective')
    && (!function_exists('stobeNegPhaseEnabled') || stobeNegPhaseEnabled(7))) {
    $reputationDirective = stobeNegReputationReplyDirective($targetNpc, is_array($npcData) ? $npcData : false, strval($speaker), strval($message ?? ''));
    if ($reputationDirective !== '') {
        $systemPrompt .= "\n\n" . $reputationDirective;
        stobeLogInfo('Reputation directive added (item 85)', ['npc'=>$targetNpc]);
    }
}
// Item 77: the relationship sets the tone; its directive closes the system message (after history and memory).''')

T = 'tests/negotiation_engine_regression.php'
patch(T,
r'''// ---------------------------------------------------------------- 12h5. deal-offer cap tiers''',
r'''// ---------------------------------------------------------------- 12h4d. item 85: reputation shapes a stranger's reply
$line85 = "Hey you. I've got a job for you, I'll pay 200 cats afterwards. Interested?";
$d85 = stobeNegReputationReplyDirective('Maeza [Hungry Bandit]', [], 'Shay', $line85, false, [2, 10]);
check('item 85: broken 10 / kept 2, a pay-later job offer -> distrust directive (up front or no deal)',
    str_contains($d85, '<reply_reputation>') && str_contains($d85, 'broken 10 deals') && str_contains($d85, 'up front'), $d85);
check('item 85: a good reputation -> nothing', stobeNegReputationReplyDirective('X', [], 'Shay', $line85, false, [46, 12]) === '');
check('item 85: a squad member -> nothing', stobeNegReputationReplyDirective('Malzin', [], 'Shay', $line85, true, [2, 10]) === '');
check('item 85: small talk -> nothing', stobeNegReputationReplyDirective('X', [], 'Shay', 'Nice weather today.', false, [2, 10]) === '');
$chat85 = file_get_contents(__DIR__ . '/../processor/chat.php');
check('item 85: the directive is added at the end of the system message, before item 77\'s',
    ($p85 = strpos($chat85, 'stobeNegReputationReplyDirective(')) !== false && $p85 < strpos($chat85, 'stobeRelationshipReplyToneDirective(')
    && $p85 > strpos($chat85, 'stobeApplyCompactChatHistory('));

// ---------------------------------------------------------------- 12h5. deal-offer cap tiers''')
