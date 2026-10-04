#!/usr/bin/env python3
"""m23 B55 rule 4 test switch (fixer 9): general_settings SOCIAL_TEST_INJECT_DIALOGUE_GAIN=<int 1..20>, off by default.
On a chat turn the relationship evaluator's updates for the listener are replaced by one aff_delta=<N> update BEFORE
stobeSocialFilterDialogueUpdates, so the real fight filter (cooldown / half rate) runs on a positive gain the live model
may never propose. Logged as 'SOCIAL_TEST_INJECT_DIALOGUE_GAIN'. Usage: m23-dialogue-inject.py <tree root>
"""
import sys
root = sys.argv[1].rstrip('/')
def patch(rel, old, new):
    p = f'{root}/{rel}'; s = open(p, encoding='utf-8').read()
    if new in s: print('already', rel); return
    if s.count(old) != 1: sys.exit(f'anchor count {s.count(old)} in {rel}: {old[:60]!r}')
    open(p, 'w', encoding='utf-8').write(s.replace(old, new)); print('ok', rel)

patch('lib/social_dialogue.php', "function stobeSocialFilterDialogueUpdates(string $speaker, array $updates): array\n",
"""/**
 * B 55 rule 4 test switch (general_settings SOCIAL_TEST_INJECT_DIALOGUE_GAIN = 1..20, off by default): on a chat turn the
 * evaluator's updates are replaced by one +N update for the listener, before the fight filter, so the cooldown can be
 * tested in game without depending on the model proposing a gain. Turn it off after the test.
 */
function stobeSocialTestInjectDialogueGain(string $speaker, string $listener, string $eventType, array $updates): array
{
    try { $n = (int)getSetting('SOCIAL_TEST_INJECT_DIALOGUE_GAIN', '0'); } catch (Throwable $e) { $n = 0; }
    if ($n < 1 || $n > 20 || strtolower($eventType) !== 'chat' || trim($listener) === '' || strcasecmp(trim($speaker), trim($listener)) === 0) return $updates;
    $out = [['target'=>trim($listener), 'aff_delta'=>$n, 'note'=>'test injection']];
    $log = function_exists('stobeLogRelationshipInfo') ? 'stobeLogRelationshipInfo' : (function_exists('stobeLogWarn') ? 'stobeLogWarn' : null);
    if ($log) $log('REL test switch SOCIAL_TEST_INJECT_DIALOGUE_GAIN: evaluator gain injected (turn it off after the test)',
        ['speaker'=>$speaker, 'target'=>trim($listener), 'aff_delta'=>$n, 'replaced'=>count($updates)]);
    return $out;
}

function stobeSocialFilterDialogueUpdates(string $speaker, array $updates): array
""")
patch('lib/chat_helper_functions.php', """    if (count($updates) === 0) {
        if ($method === '') {
            $method = 'none';
        }
        $result['method'] = $method;
        stobeLogRelationshipDebug('Relationship evaluation skipped/no changes', [""",
"""    require_once __DIR__ . '/social_dialogue.php';
    $injected = stobeSocialTestInjectDialogueGain($speaker, $listener, $eventType, $updates); // B 55 rule 4 test switch, off by default
    if ($injected !== $updates) { $updates = $injected; $method = 'test_inject'; }

    if (count($updates) === 0) {
        if ($method === '') {
            $method = 'none';
        }
        $result['method'] = $method;
        stobeLogRelationshipDebug('Relationship evaluation skipped/no changes', [""")
patch('tools/social_relationship_inspect.php', "'SOCIAL_FIGHT_RULES', 'SOCIAL_GRUDGE_FADE_DAYS'], true) || $value === '')",
      "'SOCIAL_FIGHT_RULES', 'SOCIAL_GRUDGE_FADE_DAYS', 'SOCIAL_TEST_INJECT_DIALOGUE_GAIN'], true) || $value === '')")
