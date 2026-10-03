#!/usr/bin/env python3
"""Item 78: "go buy a Standard First Aid Kit from Apothecary Abia" -> "that's not the one working the
counter here" (twice): Abia (a loaded trader ~285 away) wasn't in her prompt (nearby list stops at
250), so she doubted her and took no action. When the player's line names a known NPC seen in the
last 30 min who isn't in the prompt's people list, a short fact block tells her who that is and that
she can walk there (trader -> BuyItems finds them). Usage: item78_named_people_not_in_sight.py <tree>"""
import sys, pathlib

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

H = 'lib/chat_helper_functions.php'
patch(H,
r'''/**
 * Item 77: the closing tone directive (the very end of the system message) for a known, clearly''',
r'''/** Item 78: a name that marks a trader ("Apothecary Abia", "Barman Hobbs"), or stored trader data. */
function stobeNpcLooksLikeTrader(string $name, array $row = []): bool {
    $meta = $row['metadata'] ?? [];
    if (is_string($meta)) $meta = json_decode($meta, true);
    if (is_array($meta) && (!empty($meta['is_trader']) || !empty($meta['trader_inventory_items']))) return true;
    return preg_match('/^(?:apothecary|trader|barman|bartender|shopkeeper|merchant|smith|weapon\s?smith|armou?r\s?smith|robotics\s+trader|doctor|bar\s?keeper|innkeeper)\b|\b(?:trader|merchant|shopkeeper|smith)\b/i', trim($name)) === 1;
}

/**
 * Item 78: people the player's line names who are known and seen in the last 30 min but are not in
 * this prompt (out of sight): a short fact block so she can act on the errand. $rows (tests) =
 * [['name'=>..,'faction'=>..,'metadata'=>..], ...]; else core_npc_master.
 */
function stobeNamedPeopleNotInSightBlock(string $message, string $systemPrompt, string $npcName, ?array $rows = null): string {
    $message = trim($message);
    if ($message === '' || mb_strlen($message) > 600) return '';
    if ($rows === null) {
        try {
            $rows = $GLOBALS['db']->fetchAll(
                "SELECT name, faction, metadata FROM core_npc_master
                  WHERE length(name) >= 5 AND position(lower(name) in lower($1)) > 0
                    AND updated_at > NOW() - INTERVAL '30 minutes'
                  ORDER BY length(name) DESC LIMIT 4", [$message]);
        } catch (Throwable $e) {
            return '';
        }
    }
    $lines = [];
    foreach (is_array($rows) ? $rows : [] as $row) {
        $name = trim(strval($row['name'] ?? ''));
        if ($name === '' || strcasecmp($name, trim($npcName)) === 0 || stripos($message, $name) === false) continue;
        // already in her people lists ("- Name (" / "- Name\n" / "- Name - ")
        if (preg_match('/^- ' . preg_quote($name, '/') . '(?:\s*\(|\s*$|\s+-\s)/mi', $systemPrompt)) continue;
        $faction = trim(preg_replace('/\s*\[[^\]]*\]\s*$/', '', strval($row['faction'] ?? '')) ?? '');
        $isTrader = stobeNpcLooksLikeTrader($name, $row);
        $lines[] = '  <person name="' . stobePromptXmlEscape($name) . '">'
            . ($isTrader ? 'A trader' : 'Someone') . ($faction !== '' ? ' (' . stobePromptXmlEscape($faction) . ')' : '')
            . ' who is around but out of your sight right now. You can walk over to them'
            . ($isTrader ? '; a BuyItems/SellItems goal with them as target finds and walks to them.' : '.')
            . '</person>';
    }
    if (count($lines) === 0) return '';
    return "<people_named_not_in_sight>\n" . implode("\n", $lines) . "\n</people_named_not_in_sight>";
}

/**
 * Item 77: the closing tone directive (the very end of the system message) for a known, clearly''')

C = 'processor/chat.php'
patch(C,
r'''// Item 77: the relationship sets the tone; its directive closes the system message (after history and memory).''',
r'''// Item 78: people the player names who are around but not in her people list.
if (!$narratorMode && $dialogueMode !== 'cheat' && function_exists('stobeNamedPeopleNotInSightBlock')) {
    $namedNotInSight = stobeNamedPeopleNotInSightBlock(strval($message ?? ''), $systemPrompt, $targetNpc);
    if ($namedNotInSight !== '') {
        $systemPrompt .= "\n\n" . $namedNotInSight;
        stobeLogInfo('Named people not in sight added to the prompt (item 78)', ['npc'=>$targetNpc, 'block'=>$namedNotInSight]);
    }
}
// Item 77: the relationship sets the tone; its directive closes the system message (after history and memory).''')

T = 'tests/goal_destination_regression.php'
patch(T,
r'''check('item 73: a non-faction NPC -> nothing', ''',
r'''// 78: a named trader out of sight gets a fact line (run m3, Crafting base)
$rows78 = [['name'=>'Apothecary Abia', 'faction'=>'Holy Nation Outlaws [42022-rebirth.mod]', 'metadata'=>'{}']];
$line78 = 'Malzin, go buy a Standard First Aid Kit from Apothecary Abia.';
$b78 = stobeNamedPeopleNotInSightBlock($line78, "# Nearby\n- Apothecary Death (Male Hive)\n", 'Malzin', $rows78);
check('item 78: Apothecary Abia (not in the people list) -> trader fact line',
    str_contains($b78, 'Apothecary Abia') && str_contains($b78, 'A trader (Holy Nation Outlaws)') && str_contains($b78, 'BuyItems'), $b78);
check('item 78: already in the nearby list -> nothing',
    stobeNamedPeopleNotInSightBlock($line78, "- Apothecary Abia (Female Greenlander): Action: idle\n", 'Malzin', $rows78) === '');
check('item 78: a name not in the line -> nothing',
    stobeNamedPeopleNotInSightBlock('Malzin, how are you?', '', 'Malzin', $rows78) === '');
check('item 78: a non-trader is "Someone"',
    str_contains(stobeNamedPeopleNotInSightBlock('Go find Hobbs Smitty.', '', 'Malzin', [['name'=>'Hobbs Smitty','faction'=>'','metadata'=>'{}']]), 'Someone who is around'));
check('item 73: a non-faction NPC -> nothing', ''')
