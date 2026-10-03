<?php
// Item 91c: log what the fight-so-far lookup found (rows, lines), so a run shows whether the block was built.
$root = rtrim($argv[1] ?? '', '/'); $path = "$root/lib/chat_helper_functions.php";
$src = file_get_contents($path);
if ($src === false || str_contains($src, 'Item 91c')) { fwrite(STDERR, "missing or already applied\n"); exit(1); }
$a = "        \$events = stobeSelectFightSoFarEvents(is_array(\$rows) ? \$rows : [], \$npcName, \$currentGamets);\n";
if (substr_count($src, $a) !== 1) { fwrite(STDERR, "anchor missing\n"); exit(1); }
$src = str_replace($a, $a . "        if (function_exists('stobeLogInfo')) stobeLogInfo('Fight so far (item 91c)', ['npc' => \$npcName, 'gamets' => \$currentGamets, 'rows' => is_array(\$rows) ? count(\$rows) : 0, 'lines' => count(\$events), 'first' => \$events[0]['line'] ?? '']);\n", $src);
file_put_contents($path, $src); echo "patched $path\n";
