#!/usr/bin/env python3
"""NPC info panel (player view) server patch. Usage: patch_server.py <tree root>
Copies lib/npc_player_view.php + tests/npc_player_view_regression.php and patches by anchors:
ai_npcs.php (player_view action), chat_helper_functions.php (evaluator returns disclosed facts,
first-person background lines trigger the evaluation), playthrough_rollback.php (prune facts
learned in an abandoned timeline). Idempotent; fails if an anchor is missing."""
import os, shutil, sys

root = sys.argv[1]
here = os.path.dirname(os.path.abspath(__file__))
MARK = 'NPC info panel'

def patch(rel, edits):
    p = os.path.join(root, rel)
    s = open(p, encoding='utf-8').read()
    if MARK in s:
        print('skip (already patched)', rel); return
    for old, new in edits:
        if s.count(old) != 1:
            sys.exit('anchor not unique/missing in %s: %r' % (rel, old[:80]))
        s = s.replace(old, new)
    open(p, 'w', encoding='utf-8').write(s)
    print('patched', rel)

for rel in ('lib/npc_player_view.php', 'tests/npc_player_view_regression.php'):
    src = os.path.join(here, rel)
    if os.path.exists(src):
        shutil.copyfile(src, os.path.join(root, rel)); print('copied', rel)

patch('ai_npcs.php', [
    (' *   {"action":"detail","sid":"<storage_id|id:123|name>"}\n',
     ' *   {"action":"detail","sid":"<storage_id|id:123|name>"}\n'
     ' *   {"action":"player_view","storage_id":"hand_<serial>","serial":1,"name":"","speaker":"","gamets":0,\n'
     ' *    "live_activity":"","live_faction":"","trader":false,"key":""}  (NPC info panel: read-only, no LLM call)\n'),
    ("http_response_code(400);\necho json_encode(['ok' => false, 'error' => 'Unknown action']);",
     "if ($action === 'player_view') {\n"
     "    require_once $path . 'lib/npc_player_view.php';\n"
     "    try {\n"
     "        $view = stobeNpcPlayerViewText($payload);\n"
     "    } catch (Throwable $e) {\n"
     "        stobeLogWarn('NPC info panel: player_view failed', ['error' => $e->getMessage()]);\n"
     "        echo json_encode(['ok' => false, 'error' => 'player_view failed', 'key' => strval($payload['key'] ?? '')], $jsonFlags);\n"
     "        return;\n"
     "    }\n"
     "    echo json_encode(['ok' => true, 'text' => $view['text'], 'key' => strval($payload['key'] ?? ''), 'storage_id' => $view['storage_id']], $jsonFlags);\n"
     "    return;\n"
     "}\n\n"
     "http_response_code(400);\necho json_encode(['ok' => false, 'error' => 'Unknown action']);"),
])

patch('lib/chat_helper_functions.php', [
    # gate: an NPC talking about their own past is worth one evaluation (facts piggyback on it)
    ("    $backgroundChance = max(1, intval(round($chance / 4)));\n    return stobeShouldRunAutomaticRelationshipEvaluation($backgroundChance);",
     "    // NPC info panel: the NPC talking about their own past/work is worth one evaluation (disclosed facts ride on it).\n"
     "    if (trim($responseText) !== '' && preg_match(\n"
     "        '/\\b(i was born|i grew up|i used to|i come from|i came from|years ago|back when i|before i (?:came|joined|was)|my (?:father|mother|family|brother|sister|parents|village|home ?town)|i once|i\\'ve been an?|i was an?|i work(?:ed)? as)\\b/i',\n"
     "        $responseText\n"
     "    ) === 1) {\n"
     "        return true;\n"
     "    }\n"
     "    $backgroundChance = max(1, intval(round($chance / 4)));\n    return stobeShouldRunAutomaticRelationshipEvaluation($backgroundChance);"),
    ("            . \"  <rule>Use at most 3 updates.</rule>\\n\"\n",
     "            . \"  <rule>Use at most 3 updates.</rule>\\n\"\n"
     "            . \"  <rule>Also return \\\"disclosed\\\": facts the speaker states about THEMSELVES in speaker_response (origin, past, family, occupation, interests), e.g. \\\"disclosed\\\":[{\\\"fact\\\":\\\"grew up in Stack\\\",\\\"category\\\":\\\"background\\\"}]. category is one of background, interest, occupation, history. At most 2, short, third person without the name, only what is literally said in this turn: no guesses, no facts about others, nothing from incoming_line. Use [] if none.</rule>\\n\"\n"),
    ("            . \"  <rule>If nothing changed, return {\\\"updates\\\":[]}.</rule>\\n\"",
     "            . \"  <rule>If nothing changed, return {\\\"updates\\\":[],\\\"disclosed\\\":[]}.</rule>\\n\""),
    ("            'response_format' => ['type' => 'json_object'],\n        ]);\n        if ($rawEval !== false && trim(strval($rawEval)) !== '') {\n",
     "            'response_format' => ['type' => 'json_object'],\n        ]);\n"
     "        if ($rawEval !== false && trim(strval($rawEval)) !== '' && strcasecmp($listener, $speaker) !== 0) {\n"
     "            // NPC info panel: facts the NPC disclosed to the listener, from the same evaluator reply (no extra LLM call).\n"
     "            try {\n"
     "                require_once __DIR__ . '/npc_player_view.php';\n"
     "                stobeNpcFactRecordDisclosed($speakerNpcData, $speaker, $listener, stobeNpcFactParseDisclosed(strval($rawEval)), $result['clean_response'], stobeNpcFactCurrentGamets());\n"
     "            } catch (Throwable $e) {\n"
     "                stobeLogWarn('NPC_FACTS: record failed', ['npc' => $speaker, 'error' => $e->getMessage()]);\n"
     "            }\n"
     "        }\n"
     "        if ($rawEval !== false && trim(strval($rawEval)) !== '') {\n"),
])

patch('lib/playthrough_rollback.php', [
    ("        'task_goals' => 0,\n        'work_goals' => 0,\n    ];\n",
     "        'task_goals' => 0,\n        'work_goals' => 0,\n        'npc_facts' => 0,\n    ];\n\n"
     "    // NPC info panel: facts learned in the abandoned timeline go too; unstamped (game_ts 0) rows stay.\n"
     "    if (stobePlaythroughTableExists('stobe_npc_learned_fact')) {\n"
     "        $counts['npc_facts'] = stobePlaythroughDeleteCount(\n"
     "            'WITH deleted AS (DELETE FROM stobe_npc_learned_fact WHERE game_ts > $1 RETURNING 1) SELECT COUNT(*)::int AS c FROM deleted',\n"
     "            [$cutoff]\n"
     "        );\n"
     "    }\n"),
    ("        'player_base_presence_cleared' => 0,\n    ];\n}\n\nfunction stobePlaythroughZeroRestoreCounts",
     "        'player_base_presence_cleared' => 0,\n        'npc_facts' => 0,\n    ];\n}\n\nfunction stobePlaythroughZeroRestoreCounts"),
])
