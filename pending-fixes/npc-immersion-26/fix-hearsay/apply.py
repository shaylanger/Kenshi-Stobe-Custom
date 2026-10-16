#!/usr/bin/env python3
"""imm26 fix-hearsay (row 03-b): a holder with many first-hand rows (Hub guard, 75 rows) never showed a heard_from row in the prompt.
Usage: python3 apply.py <tree-root> [--test-only|--no-test]   (idempotent; asserts every anchor exactly once)
1. lib/imm26_knowledge.php stobeKnowledgeConversationContext: append the holder's newest 2 active heard_from rows (same guards as
   stobeKnowledgeClaimsFor) that are not already in $claims; if one is 'about' the listener and none is already picked, the pick is
   up to 2 first-hand about rows + 1 hearsay about row.
2. stobeKnowledgeShareFromSpeech: speaker LIMIT 8 -> 40 (the mention check + max 2 shares per line still bound the work).
3. tests/imm26_wpB_knowledge_regression.php: regression case (fails before, passes after)."""
import sys, os
root = sys.argv[1]; opt = sys.argv[2] if len(sys.argv) > 2 else ''
def rw(rel, edits):
    p = os.path.join(root, rel)
    s = open(p, encoding='utf-8', newline='').read()
    for a, b in edits:
        if b in s: continue          # already applied
        assert s.count(a) == 1, (rel, a[:70])
        s = s.replace(a, b)
    open(p, 'w', encoding='utf-8', newline='').write(s)
    print('ok', rel)

if opt != '--test-only':
    rw('lib/imm26_knowledge.php', [
("        $claims = stobeKnowledgeClaimsFor($scope, $holderKey, $gamets);\n        $suspicions = stobeKnowledgeSuspicions($scope, $actor, $gamets);\n        $asks = stobeKnowledgeAsksAboutEvents($message);",
 "        $claims = stobeKnowledgeClaimsFor($scope, $holderKey, $gamets);\n"
 "        // A holder with many first-hand rows never ranks a heard_from row into the top 12: always add the newest 2 (row 03-b).\n"
 "        $have = array_flip(array_map(fn($c) => (int)$c['id'], $claims));\n"
 "        foreach (stobeKnowledgeHearsayFor($scope, $holderKey, $gamets, 2) as $hr) if (!isset($have[(int)$hr['id']])) $claims[] = $hr;\n"
 "        $suspicions = stobeKnowledgeSuspicions($scope, $actor, $gamets);\n        $asks = stobeKnowledgeAsksAboutEvents($message);"),
("        $pick = array_slice($about, 0, 3);\n        // Something to bring up",
 "        $pick = array_slice($about, 0, 3);\n"
 "        if (!array_filter($pick, fn($c) => $c['basis'] === 'heard_from')) {\n"
 "            $hearAbout = array_values(array_filter($about, fn($c) => $c['basis'] === 'heard_from'));\n"
 "            if ($hearAbout) $pick = array_merge(array_slice(array_values(array_filter($about, fn($c) => $c['basis'] !== 'heard_from')), 0, 2), [$hearAbout[0]]);\n"
 "        }\n        // Something to bring up"),
("function stobeKnowledgeLine(array $c, int $gamets): string\n",
 "/** @return list<array> the holder's newest active hearsay rows (same time guards as stobeKnowledgeClaimsFor). */\n"
 "function stobeKnowledgeHearsayFor(array $scope, string $holderKey, int $gamets, int $limit = 2): array\n{\n"
 "    if (!stobeKnowledgeEnsureSchema()) return [];\n"
 "    return $GLOBALS['db']->fetchAll(\"SELECT * FROM social_rumor WHERE campaign_id=$1 AND holder_key=$2 AND status='active' AND basis='heard_from'\n"
 "        AND learned_ts<=$3 AND game_ts<=$3 AND ttl_ts>$3 ORDER BY learned_ts DESC, game_ts DESC LIMIT \" . max(1, min(8, $limit)),\n"
 "        [$scope['campaign_id'], $holderKey, $gamets]) ?: [];\n}\n\nfunction stobeKnowledgeLine(array $c, int $gamets): string\n"),
("ORDER BY severity DESC, game_ts DESC LIMIT 8\",\n            [$scope['campaign_id'], 'npc:' . $speakerId, $gamets])",
 "ORDER BY severity DESC, game_ts DESC LIMIT 40\",\n            [$scope['campaign_id'], 'npc:' . $speakerId, $gamets])"),
])

TEST = r'''// ---- row 03-b: a holder with many first-hand rows still shows one hearsay line, and a busy witness can still pass on an older subject ----
$TG = $T0 + 3 * $DAY; $guard = $npc('WpB Guard'); $gk = 'npc:' . (int)$guard['id'];
$sc = ['campaign_id'=>CAMP, 'timeline_epoch'=>'3'];
$rec = fn(string $inc, string $subj, string $basis, int $sev, int $gts, array $x = []) => stobeKnowledgeRecord($sc, $x + ['holder_key'=>$gk, 'holder_name'=>'WpB Guard',
    'subject_key'=>"name:$subj", 'subject_name'=>$subj, 'victim_key'=>'name:WpB Victim', 'victim_name'=>'WpB Victim', 'incident_id'=>$inc, 'component'=>'attack',
    'claim_kind'=>'attack', 'claim_text'=>"$subj attacked WpB Victim ($inc)", 'severity'=>$sev, 'basis'=>$basis, 'game_ts'=>$gts, 'learned_ts'=>$gts + 10, 'ttl_ts'=>$TG + 30 * $DAY]);
$rec('hs-old', 'WpB Attacker', 'heard_from', 1, $T0 + 100, ['source_name'=>'WpB Zero', 'hops'=>1, 'confidence'=>'hearsay', 'claim_text'=>'WpB Attacker hurt WpB Victim (hearsay row)']);
for ($i = 1; $i <= 15; ++$i) $rec("hs-fh$i", 'WpB Attacker', 'saw', 2, $T0 + $DAY + $i * 60);
$rec('hs-pal', 'WpB Pal', 'saw', 1, $T0 + 200);
$ctx = stobeKnowledgeConversationContext('WpB Guard', $guard, 'WpB Attacker', [], ['gamets'=>$TG, 'player_message'=>'Have you heard anything about me?']);
ok(str_contains($ctx, 'hearsay from WpB Zero'), 'holder with 15 newer first-hand rows still shows one attributed hearsay line');
ok(substr_count($ctx, "\n- [") <= 4 && substr_count($ctx, 'you saw it yourself') === 2, 'hearsay slot replaces the third first-hand line only (2 first-hand + 1 hearsay)');
$sh = stobeKnowledgeShareFromSpeech('WpB Guard', $guard, 'WpB Friend', 'I saw WpB Pal hit someone.', $TG);
ok(count($sh) === 1 && $sh[0]['about'] === 'WpB Pal', 'busy witness (16 higher-ranked rows) can still pass on an older row whose subject was spoken');

'''
if opt != '--no-test':
    rw('tests/imm26_wpB_knowledge_regression.php', [
("'WpB Pal'=>[7140,'Hub',false],", "'WpB Pal'=>[7140,'Hub',false], 'WpB Guard'=>[7150,'Hub',false],"),
("// ---- item 4: ties ----\n", TEST + "// ---- item 4: ties ----\n"),
])
