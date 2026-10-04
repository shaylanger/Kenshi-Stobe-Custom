#!/usr/bin/env python3
"""Regression check for m23-dialogue-inject.py (adds to tests/social_fights_regression.php). Usage: <tree root>"""
import sys
p = sys.argv[1].rstrip('/') + '/tests/social_fights_regression.php'; s = open(p, encoding='utf-8').read()
anchor = "ok((int)$u[0]['aff_delta'] === -4, 'item 4: negative chat passes');\n"
add = """// rule 4 test switch (m23): the injected +N replaces the evaluator's updates before the fight filter, which then blocks it
setting('SOCIAL_TEST_INJECT_DIALOGUE_GAIN', '3');
$u = stobeSocialTestInjectDialogueGain('Bandit Rook', 'Fight Shay', 'chat', [['target'=>'Fight Shay', 'aff_delta'=>-4]]);
ok(count($u) === 1 && $u[0]['target'] === 'Fight Shay' && (int)$u[0]['aff_delta'] === 3, 'rule 4 switch: +3 injected for the listener');
ok((int)stobeSocialFilterDialogueUpdates('Bandit Rook', $u)[0]['aff_delta'] === 0, 'rule 4 switch: injected gain blocked by the cooldown');
ok(stobeSocialTestInjectDialogueGain('Bandit Rook', 'Fight Shay', 'bored', []) === [], 'rule 4 switch: chat turns only');
setting('SOCIAL_TEST_INJECT_DIALOGUE_GAIN', null);
ok(stobeSocialTestInjectDialogueGain('Bandit Rook', 'Fight Shay', 'chat', []) === [], 'rule 4 switch: off by default');
"""
if add in s: print('already'); sys.exit(0)
if s.count(anchor) != 1: sys.exit('anchor')
s = s.replace(anchor, anchor + add)
s = s.replace("'SOCIAL_TEST_FORCE_FIRST_STRIKE'] as $id) setting($id, null);", "'SOCIAL_TEST_FORCE_FIRST_STRIKE','SOCIAL_TEST_INJECT_DIALOGUE_GAIN'] as $id) setting($id, null);", 1)
open(p, 'w', encoding='utf-8').write(s); print('ok', p)
