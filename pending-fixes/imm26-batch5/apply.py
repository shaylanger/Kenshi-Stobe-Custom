#!/usr/bin/env python3
"""imm26-batch5: three small server fixes (rows 16-c, 02-bx, 17-bx).
FIX1 (16-c): lib/dynamic_profile_scheduler.php dps_generate counted the generator's updates against the 4 enabled fields, but
  stobeDynamicProfileGenerateUpdates adds `backstory` for sparse profiles (5 != 4 -> generation_failed_or_empty). Filter the updates to
  the enabled fields first. lib/imm26_personality.php: anchor traits were 60-char fragments like "this character stays balanced by
  keeping supplies in strict " that no faithful rewrite keeps; skip "this character/person ..." parts, mark the anchor v=2 and
  re-derive any v1 anchor.
FIX2 (02-bx): slavery request regex (prompt line + action gate) missed "chain up", "prisoner", "captive" phrasings.
FIX3 (17-bx): imm26IsChallenge missed "I haven't ..." / "check your pack" denials of possession.
Usage (WSL): python3 apply.py <tree-root>    (idempotent; asserts anchors; installs tests/imm26_batch5_regression.php)"""
import sys, os, shutil
root = sys.argv[1]
here = os.path.dirname(os.path.abspath(__file__))


def edit(rel, pairs, marker):
    p = os.path.join(root, rel)
    s = open(p, encoding='utf-8').read()
    if marker in s:
        print('already applied:', rel)
        return
    for a, b in pairs:
        assert s.count(a) == 1, 'anchor missing/ambiguous in %s: %r' % (rel, a[:70])
        s = s.replace(a, b)
    open(p, 'w', encoding='utf-8').write(s)
    print('applied:', rel)


# FIX1a
edit('lib/dynamic_profile_scheduler.php', [(
    r'''        return !empty($generated['ok']) && count($generated['updates'] ?? [])===count($npc['fields']) ? $generated['updates'] : [];
''',
    r'''        // The generator may add fields that are not enabled (backstory for sparse profiles): count only the enabled ones.
        $enabled = array_intersect_key((array)($generated['updates'] ?? []), array_flip($npc['fields']));
        return !empty($generated['ok']) && count($enabled)===count($npc['fields']) ? $enabled : [];
''')], 'array_intersect_key((array)')

# FIX1b
edit('lib/imm26_personality.php', [
    (r'''function imm26PhraseSplit(string $text, int $max, int $maxLen = 60): array
{''',
     r'''function imm26PhraseSplit(string $text, int $max, int $maxLen = 60, bool $skipBoilerplate = false): array
{'''),
    (r'''        if (mb_strlen($part) < 4) continue;
        $part = mb_substr($part, 0, $maxLen);''',
     r'''        if (mb_strlen($part) < 4) continue;
        // imm26-batch5: generated profiles open with "this character ..."; a cut-off fragment of that never survives a rewrite.
        if ($skipBoilerplate && preg_match('/\b(?:this character|this person)\b/iu', $part) === 1) continue;
        $part = mb_substr($part, 0, $maxLen);'''),
    (r'''    $traits = imm26PhraseSplit($personality, 3);
    if (!$traits) return [];''',
     r'''    $traits = imm26PhraseSplit($personality, 3, 60, true) ?: imm26PhraseSplit($personality, 3);
    if (!$traits) return [];'''),
    (r'''    return ['v'=>1, 'traits'=>$traits,''', r'''    return ['v'=>2, 'traits'=>$traits,'''),
    (r'''    if ($stored && ($stored['src'] ?? '') === $hash) return $stored;
    if ($stored) {''',
     r'''    if ($stored && (int)($stored['v'] ?? 1) < 2) $stored = []; // v1 traits were boilerplate fragments: derive again
    if ($stored && ($stored['src'] ?? '') === $hash) return $stored;
    if ($stored) {'''),
], 'skipBoilerplate')

# FIX2
edit('lib/imm26_c1_principles.php', [(
    r'''            'request' => '/\b(?:enslav\w*|slaves?|slavery|shackl\w*|kidnap\w*|in chains)\b/iu',''',
    r'''            'request' => '/\b(?:enslav\w*|slaves?|slavery|shackl\w*|kidnap\w*|in chains|chain\w*\s+(?:up|him|her|them|this|that|the)|imprison\w*|captur\w*\s+(?:him|her|them)|(?:take|make|hold|keep)\s+\w+(?:\s+\w+)?\s+(?:prisoner|captive)s?)\b/iu',''')],
    r'imprison\w*|captur')

# FIX3
edit('lib/imm26_claims.php', [(
    r'''|you said|that is not what)\\b/iu"''',
    r'''|you said|that is not what|i (?:haven'?t|have not|hadn'?t)|i don'?t have (?:it|that|one)|check your (?:pack|bag|inventory))\\b/iu"''')],
    'check your (?:pack')

os.makedirs(os.path.join(root, 'tests'), exist_ok=True)
shutil.copy(os.path.join(here, 'imm26_batch5_regression.php'), os.path.join(root, 'tests', 'imm26_batch5_regression.php'))
print('tests installed')
