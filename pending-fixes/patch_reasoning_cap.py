import sys

# Caps the model's hidden reasoning for NPC chat outside fights (fights already turn it off).
root = sys.argv[1].rstrip('/')
path = root + '/connector/openaijson.php'
s = open(path).read()

old = """        $payload['reasoning'] = !empty($GLOBALS['STOBE_REASONING_OFF'])
            ? ['enabled' => false, 'exclude' => true]
            : ['exclude' => true];
"""
assert s.count(old) == 2, s.count(old)
s = s.replace(old, "        $payload['reasoning'] = stobeReasoningPayload($meta);\n")

anchor = "/**\n * Hidden reasoning shares max_tokens with the visible reply."
assert s.count(anchor) == 1
s = s.replace(anchor, """/**
 * Mid-fight chat skips reasoning (COMBAT_FAST_REPLIES). Other NPC chat gets a reasoning budget
 * (CHAT_REASONING_MAX_TOKENS, default 300, 0 = no cap): DeepSeek ignores "effort", and uncapped
 * it sometimes thinks 1,000+ tokens (13 s) on one line. Background calls keep full reasoning.
 */
function stobeReasoningPayload(array $meta): array {
    if (!empty($GLOBALS['STOBE_REASONING_OFF'])) {
        return ['enabled' => false, 'exclude' => true];
    }
    $cap = 0;
    if (strval($meta['event_type'] ?? '') === 'chat') {
        $cap = function_exists('getSetting') ? intval(getSetting('CHAT_REASONING_MAX_TOKENS', '300')) : 300;
    }
    return $cap > 0 ? ['max_tokens' => $cap, 'exclude' => true] : ['exclude' => true];
}

""" + anchor)
open(path, 'w').write(s)
print('patched connector/openaijson.php (reasoning cap)')
