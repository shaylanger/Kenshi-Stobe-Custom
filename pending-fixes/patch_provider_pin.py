import sys

# Pins OpenRouter chat models to the providers measured fastest (tools/stobe-provider-bench.php).
root = sys.argv[1].rstrip('/')
path = root + '/connector/openaijson.php'
s = open(path).read()

blocks = [
    """    // NPC dialogue is latency-sensitive. Keep the model/context unchanged, but
    // prefer a stable low-latency provider so GLM's repeated prompt prefix can hit its cache.
    if (
        $connectorType === 'openrouterjson'
        && strtolower(trim(strval($model))) === 'z-ai/glm-5.2'
        && !isset($payload['provider'])
    ) {
        $payload['provider'] = ['order' => ['deepinfra'], 'allow_fallbacks' => true];
    }
""",
    """    // See non-streaming path above. Keeping the provider stable also improves prompt-cache reuse.
    if (
        $connectorType === 'openrouterjson'
        && strtolower(trim(strval($model))) === 'z-ai/glm-5.2'
        && !isset($payload['provider'])
    ) {
        $payload['provider'] = ['order' => ['deepinfra'], 'allow_fallbacks' => true];
    }
""",
]
for b in blocks:
    assert s.count(b) == 1, b[:80]
    s = s.replace(b, "    stobeApplyOpenRouterProviderPin($payload, strval($connectorType), strval($model));\n")

anchor = "/**\n * Hidden reasoning shares max_tokens with the visible reply."
assert s.count(anchor) == 1
s = s.replace(anchor, """/**
 * NPC dialogue is latency-sensitive: route OpenRouter to the providers measured fastest for the
 * model (a stable provider also keeps its prompt cache warm). Fallbacks stay allowed.
 * DeepSeek V4 Flash, 2026-09-29 benchmark: Alibaba 1.8-4 s per reply, Mancer/StreamLake 2-7 s,
 * the rest 7-25 s or unable to serve the JSON-schema request.
 */
function stobeApplyOpenRouterProviderPin(array &$payload, string $connectorType, string $model): void {
    if ($connectorType !== 'openrouterjson' || isset($payload['provider'])) {
        return;
    }
    $pins = [
        'z-ai/glm-5.2' => ['deepinfra'],
        'deepseek/deepseek-v4-flash' => ['alibaba/fp8', 'mancer/fp8', 'streamlake/fp8'],
    ];
    $key = preg_replace('/:(nitro|floor)$/', '', strtolower(trim($model)));
    if (isset($pins[$key])) {
        $payload['provider'] = ['order' => $pins[$key], 'allow_fallbacks' => true];
    }
}

""" + anchor)
open(path, 'w').write(s)
print('patched connector/openaijson.php')
