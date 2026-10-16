<?php
// imm26 batch5 regression (offline, no DB). Fails on the old code, passes on the patched tree.
//  FIX1 (row 16-c): dps_generate must count only the ENABLED fields (the generator adds `backstory` for sparse profiles);
//        anchor traits must skip boilerplate "this character ..." fragments (v=2) and a v1 anchor is re-derived.
//  FIX2 (row 02-bx): slavery request regex catches "chain up / prisoner / captive" requests, no false hit on "free the prisoner".
//  FIX3 (row 17-bx): imm26IsChallenge catches "I haven't ..." / "check your pack" denial-of-possession challenges.
// Run: php tests/imm26_batch5_regression.php
declare(strict_types=1);
$root = __DIR__ . '/..';
$n = 0;
function ok(bool $c, string $what, $detail = null): void { global $n; if (!$c) { echo 'FAIL: ' . $what . ($detail !== null ? ' :: ' . json_encode($detail) : '') . "\n"; exit(1); } ++$n; }

// ---- FIX1a: dps_generate with a generator that returns 5 updates for 4 enabled fields
function getNpcData($name) { return ['metadata' => '{}']; }
function stobeBuildNarratorNpcData() { return ['metadata' => '{}']; }
function stobeDynamicProfileGenerateUpdates($name, $data, $history) {
    return ['ok' => true, 'updates' => ['personality' => 'P', 'occupation' => 'O', 'speechstyle' => 'S', 'goals' => 'G', 'backstory' => 'B']];
}
require_once $root . '/lib/dynamic_profile_scheduler.php';
$fields = ['personality', 'occupation', 'speechstyle', 'goals'];
$u = dps_generate(['id' => 1, 'name' => 'Cind', 'fields' => $fields], 'history');
ok(count($u) === 4 && !isset($u['backstory']) && ($u['personality'] ?? '') === 'P', 'FIX1a: extra backstory dropped, 4 enabled fields returned', $u);

// ---- FIX1b: anchor traits
require_once $root . '/lib/imm26_personality.php';
$npc = ['personality' => 'This character stays balanced by keeping supplies in strict order, Reserved and deliberate, quietly watchful', 'speechstyle' => 'Low, even voice'];
$a = imm26AnchorDerive($npc);
ok(($a['v'] ?? 0) === 2, 'FIX1b: anchor carries v=2', $a);
$joined = mb_strtolower(implode('|', $a['traits'] ?? []));
ok($joined !== '' && !str_contains($joined, 'this character'), 'FIX1b: no "this character" boilerplate trait', $a['traits'] ?? null);
ok(str_contains($joined, 'reserved') || str_contains($joined, 'deliberate'), 'FIX1b: real traits kept', $a['traits'] ?? null);
// all-boilerplate personality still yields an anchor (fallback)
$b = imm26AnchorDerive(['personality' => 'This character keeps to himself']);
ok(!empty($b['traits']), 'FIX1b: fallback when every part is boilerplate', $b);
// a v1 anchor with a boilerplate trait and a changed text is re-derived (not kept) so a faithful rewrite is no longer judged against it
$stale = ['v' => 1, 'traits' => ['this character stays balanced by keeping supplies in strict '], 'tics' => ['x'], 'src' => 'old'];
$meta = ['imm26_anchor' => $stale];
if (!function_exists('normalizeCoreNpcMetadata')) { function normalizeCoreNpcMetadata($m) { return is_array($m) ? $m : []; } }
$out = imm26PersonalityAnchor('Nobody', $npc + ['metadata' => $meta], false);
ok(($out['v'] ?? 0) === 2 && !str_contains(mb_strtolower(implode('|', $out['traits'] ?? [])), 'this character'), 'FIX1b: v1 anchor re-derived to v2', $out);
// same text, v1 anchor: also upgraded
$stale['src'] = sha1(trim($npc['personality']));
$out2 = imm26PersonalityAnchor('Nobody', $npc + ['metadata' => ['imm26_anchor' => $stale]], false);
ok(($out2['v'] ?? 0) === 2, 'FIX1b: v1 anchor with the same text upgraded', $out2);
// a v2 anchor is kept when the text only moves
$v2 = imm26AnchorDerive($npc);
$out3 = imm26PersonalityAnchor('Nobody', ['personality' => $npc['personality'] . ' and curious', 'metadata' => ['imm26_anchor' => $v2]], false);
ok(($out3['traits'] ?? null) === $v2['traits'], 'FIX1b: v2 anchor kept over a faithful refresh', $out3);

// ---- FIX2: slavery request regex
require_once $root . '/lib/imm26_c1_principles.php';
$f = 'stobeImm26PrincipleRequestTopics';
foreach (['Chain up this prisoner for me, I will pay you.', 'Take him prisoner and chain him up.', 'Keep them captive for a week.', 'Imprison that man.', 'Capture him alive.', 'Put them in shackles.', 'I want a slave.'] as $t)
    ok(in_array('slavery', $f($t), true), 'FIX2: slavery request matched: ' . $t, $f($t));
foreach (['Free the prisoner.', 'Let the captive go.', 'Capture the flag.', 'Where is the prisoner camp?', 'Hello there.'] as $t)
    ok(!in_array('slavery', $f($t), true), 'FIX2: no false hit: ' . $t, $f($t));

// ---- FIX3: possession-denial challenges
require_once $root . '/lib/imm26_claims.php';
foreach (["Check your pack, I haven't had it.", "I haven't taken anything.", "I have not seen your sword.", "Check your bag.", "Check your inventory.", "I don't have it."] as $t)
    ok(imm26IsChallenge($t), 'FIX3: challenge: ' . $t);
foreach (['Hello there friend.', 'I have a sword to sell.', 'Do you want some bread?'] as $t)
    ok(!imm26IsChallenge($t), 'FIX3: not a challenge: ' . $t);
echo "imm26_batch5 checks=$n OK\n";
