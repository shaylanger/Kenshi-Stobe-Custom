#!/usr/bin/env python3
"""Item 108: template names never seen as "X [Template]" (e.g. "Berserker") count as generic names.

stobeIsGenericNpcName() learned templates only from bracketed DB names, so an unnamed raid fighter
"Berserker" got relationship entries (m18 Full-Base: Shek Warrior Anscara <-> Berserker). It now also
checks data/npc_generic_templates.json (non-unique character templates of this load order, made by
pending-fixes/gen_npc_generic_templates.py; recruitables and unique NPCs are not in it).

Usage: item108_generic_template_names.py <tree root>   (run gen_npc_generic_templates.py <tree> first)
"""
import sys, pathlib

root = pathlib.Path(sys.argv[1])
assert (root / 'data' / 'npc_generic_templates.json').exists(), 'run gen_npc_generic_templates.py first'

def patch(rel, old, new):
    p = root / rel
    s = p.read_text()
    if new in s:
        print(f"{rel}: already patched"); return
    assert s.count(old) == 1, f"{rel}: anchor found {s.count(old)}x"
    p.write_text(s.replace(old, new))
    print(f"{rel}: patched")

patch("lib/chat_helper_functions.php",
"""    $k = strtolower($name);
    if (array_key_exists($k, $cache)) return $cache[$k];
    try {
        $row = $GLOBALS['db']->fetchOne("SELECT 1 AS x FROM core_npc_master WHERE LOWER(name) LIKE $1 LIMIT 1", ['% [' . $k . ']']);""",
"""    $k = strtolower($name);
    if (array_key_exists($k, $cache)) return $cache[$k];
    // Item 108: non-unique character templates of the load order, also when never seen named.
    static $templates = null;
    if ($templates === null) {
        $raw = @file_get_contents(dirname(__DIR__) . '/data/npc_generic_templates.json');
        $list = is_string($raw) ? json_decode($raw, true) : null;
        $templates = is_array($list) ? array_flip(array_map('strval', $list)) : [];
    }
    if (isset($templates[preg_replace('/\\s+/', ' ', $k)])) return $cache[$k] = true;
    try {
        $row = $GLOBALS['db']->fetchOne("SELECT 1 AS x FROM core_npc_master WHERE LOWER(name) LIKE $1 LIMIT 1", ['% [' . $k . ']']);""")

patch("tests/negotiation_engine_regression.php",
"""// ---------------------------------------------------------------- Item 107:""",
"""// Item 108: a template never seen named is generic; recruitables, uniques and players are not.
check('item 108: "Berserker" (template, never seen named) is generic', stobeIsGenericNpcName('Berserker') === true);
check('item 108: "Kral\\'s Chosen" is generic', stobeIsGenericNpcName("Kral's Chosen") === true);
check('item 108: unique "Dust King" and recruitable "Ruka" are not generic', stobeIsGenericNpcName('Dust King') === false && stobeIsGenericNpcName('Ruka') === false);
check('item 108: the player is not generic', stobeIsGenericNpcName($player) === false);

// ---------------------------------------------------------------- Item 107:""")
