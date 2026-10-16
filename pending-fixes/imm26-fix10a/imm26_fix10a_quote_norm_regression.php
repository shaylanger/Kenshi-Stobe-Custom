<?php
// imm26 fix10a (row 10-a): npc_quote / player_quote comparisons in lib/social_repair_dialogue.php must normalise BOTH sides
// the same way. The reply (meta response_message) is sanitizeForKenshi()-normalised (em dash -> '-'), the model's npc_quote keeps
// the raw em dash, so strpos() failed and no apology was captured. Fails on the unpatched tree (no helper). Pure, no DB.
// Run: php tests/imm26_fix10a_quote_norm_regression.php
$root = __DIR__ . '/..';
require_once $root . '/lib/social_repair_dialogue.php';
$checks = 0;
function check(string $name, bool $ok): void { global $checks; $checks++; if (!$ok) { echo "FAIL $name\n"; exit(1); } }
check('N0: helpers exist', function_exists('stobeSocialRepairNpcQuoteInReply') && function_exists('stobeSocialRepairQuoteNormalize'));
$in = 'stobeSocialRepairNpcQuoteInReply';
$pq = 'stobeSocialRepairQuoteMatches';
$raw = "I hear you, Shay. I don\u{2019}t want to stay angry with you \u{2014} that\u{2019}s not who I am\u{2026} Thank you.";
$reply = "I hear you, Shay. I don't want to stay angry with you - that's not who I am... Thank you.";
$phase = 'fallback';
for ($round = 0; $round < 2; $round++) {
    if ($round === 1) {
        // Round 2: the real production sanitiser loaded (extracted verbatim from the tree, never re-written here).
        $src = file_get_contents($root . '/lib/data_functions.php');
        check('N20: sanitizer found in tree', preg_match('/^function sanitizeForKenshi\(.*?^}\r?\n/ms', $src, $mm) === 1);
        eval($mm[0]);
        $phase = 'prod';
        $reply = sanitizeForKenshi($raw);
        check('N21: reply really lost the em dash', strpos($reply, "\u{2014}") === false);
    }
    check("N1[$phase]: npc_quote with em dash/curly/ellipsis matches the sanitised reply", $in("with you \u{2014} that\u{2019}s not who I am\u{2026}", $reply));
    check("N2[$phase]: whole raw reply as quote matches", $in($raw, $reply));
    check("N3[$phase]: ASCII quote still matches", $in("that's not who I am", $reply));
    check("N4[$phase]: spaced/cased variation matches", $in("  WITH YOU \u{2013}   that's NOT who I am ", $reply));
    check("N5[$phase]: different words rejected", !$in("I forgive you completely", $reply));
    check("N6[$phase]: reordered words rejected", !$in("that's not who I am - with you", $reply));
    check("N7[$phase]: empty / whitespace quote rejected", !$in('', $reply) && !$in(" \u{00a0} ", $reply));
    check("N8[$phase]: dropped word rejected", !$in("with you - that's who I am", $reply));
    $msg = "Malzin, I'm sorry I hurt you \u{2014} I was angry and I was wrong\u{2026}";
    check("N9[$phase]: player_quote em dash/ellipsis vs same text ASCII", $pq("Malzin, I'm sorry I hurt you - I was angry and I was wrong...", $msg, 'Shay'));
    check("N10[$phase]: player_quote curly apostrophe echo", $pq("Malzin, I\u{2019}m sorry I hurt you \u{2014} I was angry and I was wrong\u{2026} (talking to: Malzin)", $msg, 'Shay'));
    check("N11[$phase]: player_quote different words rejected", !$pq("Malzin, I'm sorry I hurt you - I was right", $msg, 'Shay'));
    check("N12[$phase]: empty core rejected", !$pq('(talking to: Malzin)', '(talking to: Malzin)', 'Shay'));
}
$src = file_get_contents($root . '/lib/social_repair_dialogue.php');
check('N30: capture uses the normalised npc_quote helper, no raw strpos', strpos($src, "stobeSocialRepairNpcQuoteInReply(\$update['npc_quote']") !== false
    && strpos($src, "strpos(strval(\$meta['response_message'] ?? ''),\$update['npc_quote'])") === false);
echo "imm26_fix10a_quote_norm checks=$checks OK\n";
