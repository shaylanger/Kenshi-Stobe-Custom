#!/usr/bin/env python3
"""Feature (Shay, 2026-10-02): the relationship shapes how she talks to the person in front of her.

Before: the chat prompt only listed "## Relationships / - Shay - Neutral (neutral)" in the
cached character section plus one generic rule, so a hated or a beloved player got the
same "Hey, how are you?" answer.
Now every chat turn gets a <how_you_feel_about_them> block late in the prompt, built from
her stored entry for the speaker (aff -> tier, plus the relationship type):
  - tier sets the tone, with concrete behaviour (Hostile ... Bonded);
  - type adds the flavour (romantic, crush, ex, familial, rival, nemesis, fearful, ...);
  - outsiders at Hateful/Hostile may threaten or start a fight (Attack); squadmates never
    attack, but may say they want to leave.
Switch: RELATIONSHIP_STANCE (default on). Log-free; unit tests in
tests/relationship_stance_regression.php.

Usage: patch_r25_relationship_stance.py <StobeServer tree>  (idempotent)
"""
import sys
from pathlib import Path

root = Path(sys.argv[1])
f = root / 'lib/chat_helper_functions.php'
s = f.read_text(encoding='utf-8')

FUNCS = r'''// ---- Relationship stance (Shay, 2026-10-02): how she feels about the person talking to her ----

/** Tone for a relationship score: [tier label, behaviour]. */
function stobeRelationshipStanceTier(int $aff): array {
    if ($aff <= -91) return ['Hostile', 'You want this person dead. No courtesy at all: answer with open threats. If you are not in their squad and are able to fight, you may decide to attack them (Attack) instead of talking.'];
    if ($aff <= -76) return ['Hateful', 'You hate this person. Be openly hostile: insults, "get out of my sight", threats. If they keep pushing and you are not in their squad, you may start a fight (Attack).'];
    if ($aff <= -56) return ['Resentful', 'You carry a bitter grudge. Be curt and hostile, throw what they did back at them, tell them to leave you alone. No favours.'];
    if ($aff <= -31) return ['Cold', 'You dislike this person. Short, unfriendly answers ("What do you want?"), no small talk, no warmth, no favours unless they make it worth your while.'];
    if ($aff <= -6)  return ['Wary', 'You distrust this person. Guarded, suspicious, minimal answers; you keep them at arm\'s length.'];
    if ($aff <= 5)   return ['Neutral', 'A stranger to you. Polite but reserved; you neither like nor dislike them yet.'];
    if ($aff <= 30)  return ['Acquaintance', 'You know them a little. Civil and mildly friendly.'];
    if ($aff <= 55)  return ['Friendly', 'You like this person. Warm and easygoing; you are glad to see them and happy to chat.'];
    if ($aff <= 75)  return ['Fond', 'You are genuinely fond of this person. Let it show from the first words: you are glad they are here, you missed them, you joke with them and look out for them.'];
    if ($aff <= 90)  return ['Devoted', 'You are devoted to this person. Openly caring and protective; tell them they matter to you and that you are happy to be with them.'];
    return ['Bonded', 'This person is everything to you. Speak with complete openness and tenderness; you would die for them and they know it.'];
}

/** Extra flavour for a relationship type (empty when the type adds nothing). */
function stobeRelationshipStanceType(string $type): string {
    $map = [
        'romantic'   => 'You are in love with them / in a relationship with them: be affectionate and tender, flirt, tell them you care for them or love them when it fits.',
        'lover'      => 'You are in love with them / in a relationship with them: be affectionate and tender, flirt, tell them you care for them or love them when it fits.',
        'crush'      => 'You are attracted to them but have not said so: a little flustered, shy compliments, you want their attention.',
        'ex'         => 'They are your former lover: it is complicated, wistful or sore; old feelings show through.',
        'familial'   => 'They are family to you: familiar, protective, free to tease or nag them.',
        'platonic'   => 'This is friendship: easy, loyal, honest.',
        'ally'       => 'You see them as an ally you can count on.',
        'protective' => 'You feel protective of them and worry about their safety.',
        'grateful'   => 'You are grateful to them and it shows.',
        'indebted'   => 'You feel you owe them.',
        'admirer'    => 'You admire them and are eager for their approval.',
        'awed'       => 'You are in awe of them.',
        'mentor'     => 'You see yourself as their mentor: guiding, a little demanding.',
        'student'    => 'You look up to them as a teacher.',
        'professional' => 'Your relationship is business: practical and to the point.',
        'transactional' => 'Your relationship is business: practical and to the point.',
        'rival'      => 'They are your rival: competitive, needling, you will not let them get the upper hand.',
        'enemy'      => 'They are your enemy.',
        'nemesis'    => 'They are your nemesis: you loathe them personally.',
        'betrayed'   => 'They betrayed you and you have not forgotten it.',
        'suspicious' => 'You suspect them of something.',
        'distrust'   => 'You do not trust them.',
        'fearful'    => 'You are afraid of them: nervous, placating, careful what you say.',
        'contempt'   => 'You look down on them: condescending and dismissive.',
        'dismissive' => 'You do not take them seriously.',
        'jealous'    => 'You are jealous of them.',
        'obsessed'   => 'You are obsessed with them.',
        'estranged'  => 'You have drifted apart; there is distance and some hurt.',
        'pitying'    => 'You pity them.',
        'servant'    => 'You serve them.',
        'patron'     => 'You are their patron.',
        'client'     => 'They are your client.',
    ];
    return $map[strtolower(trim($type))] ?? '';
}

/** The block for a known relationship; '' for none. */
function stobeRelationshipStanceText(string $target, int $aff, string $type, bool $sameSquad, string $note = ''): string {
    $aff = max(-100, min(100, $aff));
    [$tier, $behaviour] = stobeRelationshipStanceTier($aff);
    $flavour = stobeRelationshipStanceType($type);
    $lines = [];
    $lines[] = '<how_you_feel_about_them>';
    $lines[] = '  <person>' . stobePromptXmlEscape($target) . '</person>';
    $lines[] = '  <feeling>' . $tier . ($type !== '' && strtolower($type) !== 'neutral' ? ' (' . stobePromptXmlEscape(strtolower($type)) . ')' : '') . ', ' . $aff . ' of -100..100</feeling>';
    $lines[] = '  <tone>' . stobePromptXmlEscape($behaviour) . '</tone>';
    if ($flavour !== '') $lines[] = '  <relationship>' . stobePromptXmlEscape($flavour) . '</relationship>';
    if (trim($note) !== '') $lines[] = '  <last_reason>' . stobePromptXmlEscape(trim($note)) . '</last_reason>';
    if ($sameSquad && $aff <= -76) {
        $lines[] = '  <limit>You travel in their squad: you do not attack them, but you may tell them you want to leave.</limit>';
    }
    $lines[] = '  <rule>This feeling decides the tone of this whole reply, more than your general manners. Even a plain greeting ("Hey, how are you?") is answered the way you feel about them. Rules for fights, orders and deals still apply.</rule>';
    $lines[] = '</how_you_feel_about_them>';
    return implode("\n", $lines);
}

/** Her stored entry for $target (case-insensitive), or null. */
function stobeRelationshipEntryFor(array|false $npcData, string $target): ?array {
    if (!is_array($npcData) || trim($target) === '') return null;
    $ext = function_exists('normalizeNpcExtendedDataPayload') ? normalizeNpcExtendedDataPayload($npcData['extended_data'] ?? []) : (is_array($npcData['extended_data'] ?? null) ? $npcData['extended_data'] : []);
    $rels = $ext['relationships'] ?? [];
    if (is_string($rels)) { $d = json_decode($rels, true); $rels = is_array($d) ? $d : []; }
    if (!is_array($rels)) return null;
    $want = function_exists('normalizeParticipantNameToken') ? normalizeParticipantNameToken($target) : trim($target);
    foreach ($rels as $k => $v) {
        $kk = function_exists('normalizeParticipantNameToken') ? normalizeParticipantNameToken(strval($k)) : trim(strval($k));
        if (is_array($v) && strcasecmp($kk, $want) === 0) return $v;
    }
    return null;
}

/** Chat turn block: how she feels about the person talking to her. */
function stobeBuildRelationshipStanceBlock(string $npcName, array|false $npcData, string $speaker, bool $sameSquad): string {
    if (function_exists('getSettingBool') && !getSettingBool('RELATIONSHIP_STANCE', true)) return '';
    if (trim($speaker) === '' || strcasecmp(trim($speaker), trim($npcName)) === 0) return '';
    $entry = stobeRelationshipEntryFor($npcData, $speaker);
    if ($entry === null) return '';
    $aff = intval($entry['aff'] ?? ($entry['affinity'] ?? 0));
    return stobeRelationshipStanceText($speaker, $aff, strval($entry['type'] ?? ''), $sameSquad, strval($entry['note'] ?? ''));
}

'''
anchor = "function buildSystemPrompt("
if 'function stobeBuildRelationshipStanceBlock(' not in s:
    assert s.count(anchor) == 1, 'buildSystemPrompt anchor'
    s = s.replace(anchor, FUNCS + anchor)
hook_anchor = """    if (strtolower($eventType) === 'chat' && function_exists('stobeRemovedClothingPromptBlock') && is_array($npcData)) {"""
hook = """    if (strtolower($eventType) === 'chat' && function_exists('stobeBuildRelationshipStanceBlock')) {
        // Shay 2026-10-02: the relationship decides how she talks to the person in front of her.
        $stanceBlock = stobeBuildRelationshipStanceBlock($npcName, $npcData, $playerName, (bool)$inPlayerFaction);
        if ($stanceBlock !== '') {
            $prompt .= "\\n\\n" . $stanceBlock;
        }
    }
"""
if 'stobeBuildRelationshipStanceBlock($npcName, $npcData, $playerName' not in s:
    assert s.count(hook_anchor) == 1, 'hook anchor'
    s = s.replace(hook_anchor, hook + hook_anchor)
f.write_text(s, encoding='utf-8')
print('patched', f)

t = root / 'tests/relationship_stance_regression.php'
if not t.exists():
    t.write_text(r'''<?php
// Relationship stance (Shay, 2026-10-02): the relationship shapes how she talks to the speaker.
require __DIR__ . '/../lib/bootstrap.php';
$pass = 0; $fail = 0;
function check(string $name, bool $ok, $detail = null): void {
    global $pass, $fail;
    if ($ok) { $pass++; echo "PASS $name\n"; } else { $fail++; echo "FAIL $name" . ($detail !== null ? ' :: ' . json_encode($detail) : '') . "\n"; }
}
$hate = stobeRelationshipStanceText('Shay', -80, 'enemy', false);
check('hateful: hostile tone and may start a fight', str_contains($hate, 'Hateful') && str_contains($hate, 'Attack'), $hate);
$hateSquad = stobeRelationshipStanceText('Shay', -95, 'nemesis', true);
check('hostile squadmate: no attack, may leave', str_contains($hateSquad, 'you do not attack them') && str_contains($hateSquad, 'nemesis'), $hateSquad);
$cold = stobeRelationshipStanceText('Shay', -40, 'neutral', false);
check('cold: unfriendly, no type line for neutral', str_contains($cold, 'Cold') && !str_contains($cold, '<relationship>'), $cold);
$neutral = stobeRelationshipStanceText('Shay', 0, 'neutral', false);
check('neutral: reserved', str_contains($neutral, 'Neutral') && str_contains($neutral, 'reserved'), $neutral);
$fond = stobeRelationshipStanceText('Shay', 60, 'platonic', true);
check('fond: warm, missed them', str_contains($fond, 'Fond') && str_contains($fond, 'missed them'), $fond);
$love = stobeRelationshipStanceText('Shay', 96, 'romantic', true);
check('bonded + romantic: love', str_contains($love, 'Bonded') && str_contains($love, 'love'), $love);
check('every reply, even a greeting', str_contains($love, 'Hey, how are you?'));
$npc = ['extended_data' => json_encode(['relationships' => ['Shay' => ['aff' => -60, 'type' => 'rival', 'note' => 'stole her bread']]])];
$block = stobeBuildRelationshipStanceBlock('Malzin', $npc, 'shay', false);
check('stored entry found case-insensitively, note included', str_contains($block, 'Resentful') && str_contains($block, 'stole her bread') && str_contains($block, 'rival'), $block);
check('no entry: no block', stobeBuildRelationshipStanceBlock('Malzin', ['extended_data' => '{}'], 'Shay', false) === '');
check('tier edges', stobeRelationshipStanceTier(-91)[0] === 'Hostile' && stobeRelationshipStanceTier(-90)[0] === 'Hateful'
    && stobeRelationshipStanceTier(5)[0] === 'Neutral' && stobeRelationshipStanceTier(6)[0] === 'Acquaintance'
    && stobeRelationshipStanceTier(91)[0] === 'Bonded' && stobeRelationshipStanceTier(90)[0] === 'Devoted');
echo "\n$pass passed, $fail failed\n";
exit($fail > 0 ? 1 : 0);
''', encoding='utf-8')
    print('created', t)
