<?php
// Item 91b: add the A13 v3 case to tests/fight_so_far_regression.php (anchored insert).
$root = rtrim($argv[1] ?? '', '/');
$path = "$root/tests/fight_so_far_regression.php";
$src = file_get_contents($path);
if ($src === false || str_contains($src, 'Item 91b')) { fwrite(STDERR, "missing or already applied\n"); exit(1); }
$anchor = "\$chatSrc = file_get_contents(__DIR__ . '/../processor/chat.php');";
if (substr_count($src, $anchor) !== 1) { fwrite(STDERR, "anchor missing\n"); exit(1); }
$add = <<<'PHP'
// Item 91b (A13 v3): Malzin is knocked out for ~3500 game s mid-fight (absent from 'people'); the fight goes
// on around her. The opening and Kor Gast's knockout she saw must survive; what happened while she was out
// must not become a line; a town brawl in the same rows stays out.
$pp = static fn(array $names): string => json_encode(array_map(fn($n) => $n . '|hand_1', $names));
$v3 = [];
$v3[] = ['type' => 'combat', 'data' => 'Malzin: Initiated attack (talking to: Kor Gast)', 'gamets' => 516100, 'people' => $pp(['Malzin', 'Shay', 'Kor Gast'])];
$v3[] = ['type' => 'knockout', 'data' => 'Kor Gast was Knocked Out.', 'gamets' => 516271, 'people' => $pp(['Kor Gast', 'Malzin', 'Shay'])];
$v3[] = ['type' => 'combat', 'data' => 'Kolven [Hungry Bandit]: Initiated attack (talking to: Malzin)', 'gamets' => 516862, 'people' => $pp(['Kolven [Hungry Bandit]', 'Malzin', 'Shay'])];
$v3[] = ['type' => 'combat', 'data' => 'Kolven [Hungry Bandit]: Initiated attack (talking to: Shay)', 'gamets' => 516900, 'people' => $pp(['Kolven [Hungry Bandit]', 'Malzin', 'Shay'])];
$v3[] = ['type' => 'combat', 'data' => 'Shay: Initiated attack (talking to: Marr [Hungry Bandit])', 'gamets' => 516950, 'people' => $pp(['Shay', 'Marr [Hungry Bandit]', 'Malzin'])];
$v3[] = ['type' => 'knockout', 'data' => 'Malzin: Knocked out by an Iron Stick from Kolven [Hungry Bandit]', 'gamets' => 517156, 'people' => $pp(['Malzin', 'Shay'])];
for ($g = 517300; $g <= 520700; $g += 400) { // she is out: rows without her
    $v3[] = ['type' => 'combat', 'data' => 'Marr [Hungry Bandit]: Initiated attack (talking to: Shay)', 'gamets' => $g, 'people' => $pp(['Marr [Hungry Bandit]', 'Shay'])];
}
$v3[] = ['type' => 'knockout', 'data' => 'Marr [Hungry Bandit] was Knocked Out.', 'gamets' => 518144, 'people' => $pp(['Marr [Hungry Bandit]', 'Shay'])];
$v3[] = ['type' => 'knockout', 'data' => 'Dust Bandit: Knocked out by an Iron Stick from Captain Ophir', 'gamets' => 520491, 'people' => $pp(['Dust Bandit', 'Captain Ophir', 'Malzin (unconscious)'])];
$v3[] = ['type' => 'combat', 'data' => 'Captain Ophir: Initiated attack (talking to: Dust Bandit)', 'gamets' => 520400, 'people' => $pp(['Captain Ophir', 'Dust Bandit'])];
$v3[] = ['type' => 'combat', 'data' => 'Threkk [Hungry Bandit]: Initiated attack (talking to: Malzin)', 'gamets' => 520803, 'people' => $pp(['Threkk [Hungry Bandit]', 'Malzin', 'Shay'])];
$v3[] = ['type' => 'knockout', 'data' => 'Threkk [Hungry Bandit] was Knocked Out.', 'gamets' => 522129, 'people' => $pp(['Threkk [Hungry Bandit]', 'Malzin', 'Shay'])];
usort($v3, fn($a, $b) => $b['gamets'] <=> $a['gamets']);
$v3l = array_column(stobeSelectFightSoFarEvents($v3, 'Malzin', 522435), 'line');
check('91b: opening + Kor Gast KO survive her own knockout gap', in_array('Malzin: Initiated attack (talking to: Kor Gast)', $v3l, true) && in_array('Kor Gast was Knocked Out.', $v3l, true), $v3l);
check('91b: her own knockout is kept', in_array('Malzin: Knocked out by an Iron Stick from Kolven [Hungry Bandit]', $v3l, true), $v3l);
check('91b: unseen while she was out (Marr KO) left out', !in_array('Marr [Hungry Bandit] was Knocked Out.', $v3l, true), $v3l);
check('91b: town brawl left out', !in_array('Dust Bandit: Knocked out by an Iron Stick from Captain Ophir', $v3l, true), $v3l);
check('91b: latest knockout kept', in_array('Threkk [Hungry Bandit] was Knocked Out.', $v3l, true), $v3l);
check('91b: query has no audience filter', str_contains(file_get_contents(__DIR__ . '/../lib/chat_helper_functions.php'), 'SELECT type, data, gamets, people FROM eventlog'));

PHP;
$src = str_replace($anchor, $add . $anchor, $src);
file_put_contents($path, $src);
echo "patched $path\n";
