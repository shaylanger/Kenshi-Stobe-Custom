#!/usr/bin/env python3
"""Round 13: DeepInfra prompt caching (Shay's finding, 2026-09-30).

Real play had 0 cached tokens across DeepInfra chat calls. The system prompt is one
~7k-token message, but consecutive Malzin turns only shared the first 200-600 tokens:
<character_state> (action, equipment) and <relationships> sat inside <character>, right
after the roleplay rules, and changed every turn. The ~1.8k-token Available Actions list
(2 variants: StopAttack only in fights) came after them, so it was never reused.

1. Chat prompt order (buildSystemPrompt, event 'chat' only) is now stable-first:
     roleplay rules, character (bio, personality, appearance, occupation, skills, speech,
     goals), general instructions, Available Actions
   then the live part:
     <current_situation> (Character State + Relationships, same content, same "##" level),
     player base / goals / funds, knowledge, nearby actors, combat priority, negotiation,
     removed clothing, lifelike continuity; chat.php then adds game time, party,
     short-term memory and conversation history as before.
   Nothing is removed or reworded. Setting PROMPT_CACHE_STABLE_FIRST (default on) turns
   it off.

2. DeepInfra requests for chat/rechat get prompt_cache_key "stobe:<npc>:chat" (both the
   streaming and non-streaming payload builders). Other hosts are untouched.

Usage: patch_round13_prompt_cache.py <StobeServer root>
"""
import sys, pathlib

root = pathlib.Path(sys.argv[1])


def patch(rel, old, new, count=1):
    p = root / rel
    t = p.read_text(encoding="utf-8")
    assert t.count(old) == count, f"{rel}: anchor found {t.count(old)}x, want {count}: {old[:70]!r}"
    p.write_text(t.replace(old, new), encoding="utf-8")


H = "lib/chat_helper_functions.php"
patch(H,
      """    $worldStateBlock = buildWorldStateBlock($npcData);
    if (strpos($prompt, '#NPC_CHARACTER_STATE#') !== false) {""",
      """    $worldStateBlock = buildWorldStateBlock($npcData);
    // Round 13: stable-first chat prompt so DeepInfra's prefix cache can reuse the head.
    // Character State and Relationships change every turn; they move (unchanged) into
    // <current_situation> after Available Actions instead of sitting inside <character>.
    $stableFirst = strtolower($eventType) === 'chat'
        && (!function_exists('getSettingBool') || getSettingBool('PROMPT_CACHE_STABLE_FIRST', true));
    if ($stableFirst) {
        $prompt = str_replace('#NPC_CHARACTER_STATE#', '', $prompt);
        $liveRelationships = '';
        if (preg_match('/<relationships>.*?<\\/relationships>/s', $prompt, $relMatch, PREG_OFFSET_CAPTURE) === 1) {
            $liveRelationships = $relMatch[0][0];
            $prompt = substr_replace($prompt, '', $relMatch[0][1], strlen($liveRelationships));
        }
        if ($includeActionGuidance) {
            $prompt = appendActionGuidanceToPrompt($prompt, $eventType, $npcData);
        }
        $liveBlock = trim(trim($worldStateBlock) . "\\n" . $liveRelationships);
        if ($liveBlock !== '') {
            $prompt .= "\\n\\n<current_situation>\\n" . $liveBlock . "\\n</current_situation>";
        }
    } elseif (strpos($prompt, '#NPC_CHARACTER_STATE#') !== false) {""")
patch(H,
      """    if ($includeActionGuidance) {
        $prompt = appendActionGuidanceToPrompt($prompt, $eventType, $npcData);
    }

    $scenePromptBlock""",
      """    if ($includeActionGuidance && !$stableFirst) {
        $prompt = appendActionGuidanceToPrompt($prompt, $eventType, $npcData);
    }

    $scenePromptBlock""")

C = "connector/openaijson.php"
patch(C,
      """function stobeApplyOpenRouterProviderPin(array &$payload, string $connectorType, string $model): void {""",
      """/**
 * Round 13: DeepInfra prefix caching. One stable key per NPC chat stream keeps her
 * consecutive turns on the same cache. Only sent to DeepInfra.
 */
function stobeApplyPromptCacheKey(array &$payload, string $url, array $meta): void {
    if (isset($payload['prompt_cache_key']) || stripos($url, 'deepinfra.com') === false) {
        return;
    }
    $eventType = strtolower(trim(strval($meta['event_type'] ?? '')));
    if (!in_array($eventType, ['chat', 'rechat'], true)) {
        return;
    }
    $npc = strtolower(trim(preg_replace('/[^A-Za-z0-9]+/', '_', strval($meta['npc_name'] ?? '')) ?? '', '_'));
    if ($npc !== '') {
        $payload['prompt_cache_key'] = 'stobe:' . $npc . ':chat';
    }
}

function stobeApplyOpenRouterProviderPin(array &$payload, string $connectorType, string $model): void {""")
patch(C,
      """    stobeApplyOpenRouterProviderPin($payload, strval($connectorType), strval($model));
""",
      """    stobeApplyOpenRouterProviderPin($payload, strval($connectorType), strval($model));
    stobeApplyPromptCacheKey($payload, strval($url), is_array($meta) ? $meta : []);
""", count=2)
print("round 13 applied to", root)
