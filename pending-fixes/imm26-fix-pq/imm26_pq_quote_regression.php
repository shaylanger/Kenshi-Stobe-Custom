<?php
// imm26 fix-pq (row 10-a): social repair capture must accept a player_quote that echoes the prompt's context decorations
// ("Speaker: " prefix, "(talking to: X)" / "[Player tone: ...]" suffix) without loosening the comparison otherwise.
// Fails on the old code (no stobeSocialRepairQuoteMatches; capture used strict !==). Pure-function test, no DB.
// Run: php tests/imm26_pq_quote_regression.php
$root = __DIR__ . '/..';
require_once $root . '/lib/social_repair_dialogue.php';
$checks = 0;
function check(string $name, bool $ok): void { global $checks; $checks++; if (!$ok) { echo "FAIL $name\n"; exit(1); } }
check('Q0: helper exists', function_exists('stobeSocialRepairQuoteMatches'));
$msg = "Malzin, I'm sorry I hurt you. I was angry and I was wrong.";
$m = 'stobeSocialRepairQuoteMatches';
check('Q1: exact quote matches', $m($msg, $msg, 'Shay'));
check('Q2: quote with (talking to: X) suffix matches', $m($msg . ' (talking to: Malzin)', $msg, 'Shay'));
check('Q3: quote with "Shay: " prefix and suffix matches', $m('Shay: ' . $msg . ' (talking to: Malzin)', $msg, 'Shay'));
check('Q4: message itself carrying the suffix matches the bare quote', $m($msg, $msg . ' (talking to: Malzin)', 'Shay'));
check('Q5: [Player tone] + talking-to suffixes stripped', $m($msg . ' [Player tone: calm] (talking to: Malzin)', $msg, 'Shay'));
check('Q6: different words still rejected', !$m("Malzin, I'm sorry I hurt you. (talking to: Malzin)", $msg, 'Shay'));
check('Q7: extra trailing words still rejected', !$m($msg . ' You deserved it. (talking to: Malzin)', $msg, 'Shay'));
check('Q8: other speaker prefix not stripped', !$m('Cind: ' . $msg, $msg, 'Shay'));
check('Q9: mid-text talking-to not stripped', !$m('I (talking to: Malzin) am sorry', 'I am sorry', 'Shay'));
check('Q10: empty core rejected', !$m('(talking to: Malzin)', '(talking to: Malzin)', 'Shay'));
$src = file_get_contents($root . '/lib/social_repair_dialogue.php');
check('Q11: capture uses the helper, no raw strict compare', strpos($src, "stobeSocialRepairQuoteMatches(\$update['player_quote']") !== false
    && strpos($src, "\$update['player_quote']!==\$message") === false);
echo "imm26_pq_quote checks=$checks OK\n";
