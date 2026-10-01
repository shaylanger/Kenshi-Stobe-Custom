<?php
// Replays one logged chat request against every OpenRouter provider of the model.
// Usage: php stobe-provider-bench.php <context_sent_to_llm.log> <start line> <end line> [runs] [provider,...|all] [mode,...]
// Modes: on, off, low, medium, high (reasoning effort), max200, max400 (reasoning token cap). Default: on,off.
// Prints one CSV row per call: provider,reasoning,run,ttft_ms,first_text_ms,total_ms,out_tok,reason_tok,cached_tok,served_by,error
[$_, $logFile, $from, $to] = $argv;
$runs = intval($argv[4] ?? 3);
$only = isset($argv[5]) && $argv[5] !== 'all' ? explode(',', $argv[5]) : null;
$modes = isset($argv[6]) ? explode(',', $argv[6]) : ['on', 'off'];

// The logged record is a var_export() array; take its payload.
$lines = array_slice(file($logFile), intval($from) - 1, intval($to) - intval($from) + 1);
$start = 0;
foreach ($lines as $i => $l) { if (str_starts_with($l, 'array (')) { $start = $i; break; } }
$record = eval('return ' . rtrim(implode('', array_slice($lines, $start)), "\n;") . ';');
$base = $record['payload'];
$model = preg_replace('/:nitro$/', '', $base['model']);

// Key comes from the live connector row (or its API badge); it is never printed.
$key = trim(strval(shell_exec("su postgres -c \"psql -d stobe -Atc \\\"select coalesce(nullif(c.api_key,''), b.api_key) from core_llm_connector c left join core_api_badge b on b.id = c.api_badge_id where c.model ilike '%deepseek-v4-flash%' limit 1\\\"\"")));
if ($key === '') { fwrite(STDERR, "no OpenRouter key found\n"); exit(1); }

$ep = json_decode(file_get_contents("https://openrouter.ai/api/v1/models/$model/endpoints"), true);
$providers = [];
foreach ($ep['data']['endpoints'] ?? [] as $e) {
    $tag = strval($e['tag'] ?? $e['provider_name']);
    if ($only === null || in_array($tag, $only, true) || in_array($e['provider_name'], $only, true)) $providers[$tag] = $e['provider_name'];
}
fwrite(STDERR, "model $model, providers: " . implode(', ', array_keys($providers)) . "\n");

echo "provider,reasoning,run,ttft_ms,first_text_ms,total_ms,out_tok,reason_tok,cached_tok,served_by,error,json_ok,deal_decision\n";
foreach ($providers as $tag => $name) {
    foreach ($modes as $reason) {
        for ($r = 1; $r <= $runs; $r++) {
            $p = $base;
            $p['model'] = $model;
            $p['stream'] = true;
            $p['usage'] = ['include' => true];
            $p['provider'] = ['order' => [$tag], 'allow_fallbacks' => false];
            $p['reasoning'] = match ($reason) {
                'on' => ['enabled' => true],
                'off' => ['enabled' => false],
                'max200', 'max300', 'max400' => ['max_tokens' => intval(substr($reason, 3))],
                default => ['effort' => $reason],
            };
            $t0 = microtime(true); $ttft = $firstText = null; $buf = ''; $text = ''; $usage = []; $served = ''; $err = '';
            $ch = curl_init('https://openrouter.ai/api/v1/chat/completions');
            curl_setopt_array($ch, [
                CURLOPT_POST => true, CURLOPT_TIMEOUT => 90,
                CURLOPT_HTTPHEADER => ['Content-Type: application/json', "Authorization: Bearer $key"],
                CURLOPT_POSTFIELDS => json_encode($p, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES),
                CURLOPT_WRITEFUNCTION => function ($ch, $chunk) use (&$buf, &$text, &$ttft, &$firstText, &$usage, &$served, &$err, $t0) {
                    $buf .= $chunk;
                    while (($nl = strpos($buf, "\n")) !== false) {
                        $line = trim(substr($buf, 0, $nl)); $buf = substr($buf, $nl + 1);
                        if (!str_starts_with($line, 'data: ') || $line === 'data: [DONE]') continue;
                        $j = json_decode(substr($line, 6), true);
                        if (!is_array($j)) continue;
                        if (isset($j['error'])) $err = substr(strval($j['error']['message'] ?? 'error'), 0, 60);
                        $served = strval($j['provider'] ?? $served);
                        $d = $j['choices'][0]['delta'] ?? [];
                        $ms = (microtime(true) - $t0) * 1000;
                        if ($ttft === null && (($d['content'] ?? '') !== '' || ($d['reasoning'] ?? '') !== '')) $ttft = $ms;
                        if ($firstText === null && ($d['content'] ?? '') !== '') $firstText = $ms;
                        $text .= strval($d['content'] ?? '');
                        if (!empty($j['usage'])) $usage = $j['usage'];
                    }
                    return strlen($chunk);
                },
            ]);
            curl_exec($ch);
            if (curl_errno($ch)) $err = curl_error($ch);
            $code = curl_getinfo($ch, CURLINFO_HTTP_CODE);
            if ($code !== 200 && $err === '') $err = "http $code " . substr(trim($buf), 0, 60);
            curl_close($ch);
            $total = (microtime(true) - $t0) * 1000;
            $reply = json_decode($text, true);
            printf("%s,%s,%d,%d,%d,%d,%d,%d,%d,%s,%s,%s,%s\n", $tag, $reason, $r, $ttft ?? -1, $firstText ?? -1, $total,
                $usage['completion_tokens'] ?? 0, $usage['completion_tokens_details']['reasoning_tokens'] ?? 0,
                $usage['prompt_tokens_details']['cached_tokens'] ?? 0, $served, str_replace(',', ';', $err),
                is_array($reply) ? 'yes' : 'no', is_array($reply) ? strval($reply['deal_decision'] ?? '-') : '-');
            flush();
        }
    }
}
