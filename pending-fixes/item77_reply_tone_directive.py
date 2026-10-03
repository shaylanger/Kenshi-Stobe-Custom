#!/usr/bin/env python3
"""Item 77: the relationship stance block (item 54) was in the prompt but replies to "Hey Malzin, how
are you?" came out the same flat tone at -80 Hateful, 60 Fond and 96 Bonded romantic: her wound
state and pacing notes came later and set the tone. A short tone directive now closes the system
message (after history/memory), with per-band directions and "lead with this feeling".
Staged replay of the m3 prompts (DeepSeek V4.1 Flash): hateful -> "get out of my sight", romantic ->
"Hey, love", fond -> warmer. Usage: item77_reply_tone_directive.py <tree root>"""
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
r'''/** Chat turn block: how she feels about the person talking to her. */''',
r'''/**
 * Item 77: the closing tone directive (the very end of the system message) for a known, clearly
 * felt relationship; '' for none or a neutral one (-5..30).
 */
function stobeRelationshipReplyToneDirective(string $npcName, array|false $npcData, string $speaker): string {
    if (function_exists('getSettingBool') && !getSettingBool('RELATIONSHIP_STANCE', true)) return '';
    if (trim($speaker) === '' || strcasecmp(trim($speaker), trim($npcName)) === 0) return '';
    $entry = stobeRelationshipEntryFor($npcData, $speaker);
    if ($entry === null) return '';
    $aff = max(-100, min(100, intval($entry['aff'] ?? ($entry['affinity'] ?? 0))));
    $type = strtolower(trim(strval($entry['type'] ?? '')));
    [$tier] = stobeRelationshipStanceTier($aff);
    $romantic = in_array($type, ['romantic', 'lover', 'crush'], true);
    if ($aff <= -56) {
        $how = 'Hostile: curt, cold, resentful. No pleasantries and no "and you?"; tell them what you think of them or to leave you alone.';
    } elseif ($aff <= -6) {
        $how = 'Guarded: short, unfriendly or suspicious; no small talk, no warmth.';
    } elseif ($aff <= 30) {
        return '';
    } elseif ($romantic && $aff >= 56) {
        $how = 'Loving: you are in love with them. Open with affection (glad they are here, you missed them or thought of them, a soft word or pet name); tender and personal; ask about them because you care.';
    } elseif ($aff >= 56) {
        $how = 'Warm: you are fond of them. Your first words show you are glad to see them (greet them by name, say it is good to see them, a smile in your voice); friendly, personal, a little teasing.';
    } else {
        $how = 'Friendly: warm and easygoing, glad to talk to them.';
    }
    $who = function_exists('normalizeParticipantNameToken') ? normalizeParticipantNameToken($speaker) : trim($speaker);
    return "<reply_tone>\n"
        . '  <feeling>You feel ' . $tier . ($type !== '' && $type !== 'neutral' ? ' (' . stobePromptXmlEscape($type) . ')' : '')
        . ', ' . $aff . ' of -100..100, about ' . stobePromptXmlEscape($who) . '.</feeling>' . "\n"
        . '  <how>' . stobePromptXmlEscape($how) . "</how>\n"
        . '  <rule>Lead with this feeling in your first words, even to a plain greeting. Your wounds, hunger or surroundings come second, at most a short aside; they never set the tone. Rules for fights, orders and deals still apply.</rule>' . "\n"
        . '</reply_tone>';
}

/** Chat turn block: how she feels about the person talking to her. */''')

C = 'processor/chat.php'
patch(C,
r'''$stobeMessageAssemblyStageStartedAt = microtime(true);
$messages = [''',
r'''// Item 77: the relationship sets the tone; its directive closes the system message (after history and memory).
if (!$narratorMode && $dialogueMode !== 'cheat' && function_exists('stobeRelationshipReplyToneDirective')) {
    $replyToneDirective = stobeRelationshipReplyToneDirective($targetNpc, is_array($npcData) ? $npcData : false, strval($speaker));
    if ($replyToneDirective !== '') {
        $systemPrompt .= "\n\n" . $replyToneDirective;
    }
}
$stobeMessageAssemblyStageStartedAt = microtime(true);
$messages = [''')

T = 'tests/relationship_stance_regression.php'
patch(T,
r'''// R1: types onto the list''',
r'''// Item 77: the closing tone directive
$npc77 = static fn(int $aff, string $type) => ['extended_data' => json_encode(['relationships' => ['Shay' => ['aff' => $aff, 'type' => $type]]])];
$t77h = stobeRelationshipReplyToneDirective('Malzin', $npc77(-80, 'enemy'), 'Shay');
check('item 77: -80 Hateful -> hostile directive', str_contains($t77h, '<reply_tone>') && str_contains($t77h, 'Hostile') && str_contains($t77h, 'Hateful'), $t77h);
$t77f = stobeRelationshipReplyToneDirective('Malzin', $npc77(60, 'platonic'), 'Shay');
check('item 77: 60 Fond -> warm directive', str_contains($t77f, 'Warm') && str_contains($t77f, 'glad to see them'), $t77f);
$t77r = stobeRelationshipReplyToneDirective('Malzin', $npc77(96, 'romantic'), 'Shay');
check('item 77: 96 Bonded romantic -> loving directive, feeling first', str_contains($t77r, 'Loving') && str_contains($t77r, 'Lead with this feeling'), $t77r);
check('item 77: neutral (0) -> no directive', stobeRelationshipReplyToneDirective('Malzin', $npc77(0, 'neutral'), 'Shay') === '');
check('item 77: no entry -> no directive', stobeRelationshipReplyToneDirective('Malzin', ['extended_data' => '{}'], 'Shay') === '');
$chat77 = file_get_contents(__DIR__ . '/../processor/chat.php');
$pos77 = strpos($chat77, 'stobeRelationshipReplyToneDirective(');
check('item 77: the directive is added after history/memory, right before the messages are assembled',
    $pos77 !== false && $pos77 > strpos($chat77, 'stobeApplyCompactChatHistory(') && $pos77 < strpos($chat77, '$stobeMessageAssemblyStageStartedAt = microtime(true);'));

// R1: types onto the list''')
