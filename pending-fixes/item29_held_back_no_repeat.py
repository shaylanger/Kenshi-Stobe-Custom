#!/usr/bin/env python3
"""Item 29: a corrected held-back reply doesn't say the already-spoken sentences again.

During an underway deal the stream speaks a reply until its first money sentence and holds the rest. When the
held part misquotes an amount, stobeDealProgressAmountCheck returns the WHOLE reply minus the wrong sentence
("Sure thing. The road north is quiet tonight. Then we're done."), and chat.php spoke that as the held part,
so the start was said twice (and stored twice in the reply text). Now only the sentences not spoken yet are
the held part (stobeDealDropSpokenSentences).

Usage: item29_held_back_no_repeat.py <tree root>
"""
import sys, pathlib

root = pathlib.Path(sys.argv[1])

def patch(rel, old, new):
    p = root / rel
    s = p.read_text()
    if new in s:
        print(f"{rel}: already patched"); return
    assert s.count(old) == 1, f"{rel}: anchor found {s.count(old)}x"
    p.write_text(s.replace(old, new))
    print(f"{rel}: patched")

patch("lib/negotiation_phase1.php",
"""function stobeDealSpeechAmountCheck(string $text, string $npc, array $dealResult, string $playerMessage = ''): ?array {""",
"""/** Item 29: the held-back part of a corrected line: sentences already spoken before the hold are not said again. */
function stobeDealDropSpokenSentences(string $line, string $spoken): string {
    $norm = static fn(string $s): string => strtolower(trim(preg_replace('/\\s+/', ' ', $s) ?? $s));
    $done = [];
    foreach (preg_split('/(?<=[.!?])\\s+/', trim($spoken)) ?: [] as $s) {
        if (trim($s) !== '') $done[$norm($s)] = true;
    }
    $kept = [];
    foreach (preg_split('/(?<=[.!?])\\s+/', trim($line)) ?: [] as $s) {
        if (trim($s) === '' || isset($done[$norm($s)])) continue;
        $kept[] = trim($s);
    }
    return implode(' ', $kept);
}

function stobeDealSpeechAmountCheck(string $text, string $npc, array $dealResult, string $playerMessage = ''): ?array {""")

patch("processor/chat.php",
"""                    if (!$alreadyStreamed) {
                        $responseText = trim($streamSpokenPrefix . ' ' . $amountCheck['line']);
                        if ($streamSpokenPrefix !== '') $streamSpeakOverride = $amountCheck['line'];
                    }""",
"""                    if (!$alreadyStreamed) {
                        // Item 29: what was spoken before the hold is not said again.
                        $heldLine = $streamSpokenPrefix !== '' && function_exists('stobeDealDropSpokenSentences')
                            ? stobeDealDropSpokenSentences(strval($amountCheck['line']), $streamSpokenPrefix) : strval($amountCheck['line']);
                        $responseText = trim($streamSpokenPrefix . ' ' . $heldLine);
                        if ($streamSpokenPrefix !== '') $streamSpeakOverride = $heldLine;
                    }""")

patch("tests/negotiation_engine_regression.php",
"""// ---------------------------------------------------------------- cleanup
""",
"""// ---------------------------------------------------------------- item 29: a corrected held-back line doesn't repeat the spoken start
check('item 29: spoken sentences are not said again', function_exists('stobeDealDropSpokenSentences')
    && stobeDealDropSpokenSentences("Sure thing. The road north is quiet tonight. Then we're done.", 'Sure thing.  The road north is quiet tonight.') === "Then we're done.");
check('item 29: nothing spoken yet -> the whole line', function_exists('stobeDealDropSpokenSentences')
    && stobeDealDropSpokenSentences('You still owe me 100 Cats.', '') === 'You still owe me 100 Cats.');
check('item 29: chat.php speaks only the unspoken part', str_contains(file_get_contents(dirname(__DIR__) . '/processor/chat.php'), 'stobeDealDropSpokenSentences('));

// ---------------------------------------------------------------- cleanup
""")
