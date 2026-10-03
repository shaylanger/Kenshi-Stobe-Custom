#!/usr/bin/env python3
"""Item 77, ss-merge variant of the chat.php + test parts (its chat.php has no latency stages and no
$narratorMode). Run after item77_reply_tone_directive.py patched lib/chat_helper_functions.php.
Usage: item77_ssmerge_chat.py <ss-merge root>"""
import sys, pathlib, re

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

patch('processor/chat.php',
r'''$historyMessages = is_array($compactHistory['history_messages'] ?? null)
    ? $compactHistory['history_messages']
    : $historyMessages;
$messages = [''',
r'''$historyMessages = is_array($compactHistory['history_messages'] ?? null)
    ? $compactHistory['history_messages']
    : $historyMessages;
// Item 77: the relationship sets the tone; its directive closes the system message (after history and memory).
if ($dialogueMode !== 'narrator' && $dialogueMode !== 'cheat' && function_exists('stobeRelationshipReplyToneDirective')) {
    $replyToneDirective = stobeRelationshipReplyToneDirective($targetNpc, is_array($npcData) ? $npcData : false, strval($speaker));
    if ($replyToneDirective !== '') {
        $systemPrompt .= "\n\n" . $replyToneDirective;
    }
}
$messages = [''')

# the test from the main script, with the placement check anchored on "$messages = ["
main = (pathlib.Path(__file__).parent / 'item77_reply_tone_directive.py').read_text(encoding='utf-8')
block = main[main.index("// Item 77: the closing tone directive"):main.index("// R1: types onto the list''')")]
block = block.replace("$stobeMessageAssemblyStageStartedAt = microtime(true);", "$messages = [")
patch('tests/relationship_stance_regression.php', "// R1: types onto the list", block + "// R1: types onto the list")
