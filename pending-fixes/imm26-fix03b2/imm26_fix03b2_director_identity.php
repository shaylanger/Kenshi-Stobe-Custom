<?php
// imm26 fix03b2 (row 03-b / 22-b): the Director cast must accept `Name|hand_<serial>` (what main.php's CACHE_PEOPLE carries) as well as
// `Name|<digits>`. Fails on a tree without stobeDirectorPeopleSerials. Pure: no database needed.
declare(strict_types=1);
set_exception_handler(function (Throwable $e) { echo get_class($e), ': ', $e->getMessage(), ' @', basename($e->getFile()), ':', $e->getLine(), "\n"; exit(1); });
require_once __DIR__ . '/../lib/director_scene.php';
$n = 0;
function ok(bool $c, string $what): void { global $n; if (!$c) throw new RuntimeException('FAIL: ' . $what); ++$n; }
ok(function_exists('stobeDirectorPeopleSerials'), 'identity helper exists');
$j = fn(array $a) => json_encode($a);

// the real shape: annotated CACHE_PEOPLE, raw client list numeric
$annot = $j(['Cind [Hungry Bandit]|hand_2529907200', 'Shay|hand_971557632', 'Ghetts|hand_3864624128']);
$raw = $j(['Cind [Hungry Bandit]|2529907200', 'Shay|971557632', 'Ghetts|3864624128']);
$r = stobeDirectorPeopleSerials($annot, $raw);
ok($r === ['Cind [Hungry Bandit]' => '2529907200', 'Shay' => '971557632', 'Ghetts' => '3864624128'], 'hand_ ids accepted, digits-only actor_id handed on');
ok(ctype_digit($r['Cind [Hungry Bandit]']) && $r['Cind [Hungry Bandit]'] === '2529907200', 'DLL-facing id equals the raw client serial');
ok(stobeDirectorPeopleSerials($annot) === $r, 'works without the raw list');
// plain digits (old shape) still fine
ok(stobeDirectorPeopleSerials($j(['A|123', 'B|456']), $j(['A|123', 'B|456'])) === ['A' => '123', 'B' => '456'], 'plain digit ids still accepted');
ok(stobeDirectorPeopleSerials($j(['A|HAND_77'])) === ['A' => '77'], 'prefix is case-insensitive');
// still rejected
ok(stobeDirectorPeopleSerials($j(['A|abc', 'B|hand_', 'C|hand_x1', 'D|12x', 'E|', 'F', 'G|-5', 'H|hand_-5'])) === [], 'non-digit ids rejected');
ok(stobeDirectorPeopleSerials($j(['A|1', 5, null, ['x']])) === ['A' => '1'], 'non-string entries ignored');
ok(stobeDirectorPeopleSerials('not json') === [] && stobeDirectorPeopleSerials('') === [], 'bad json -> empty');
// negative signed raw serial: normalizeStorageIdToken made it hand_<unsigned>, the DLL cannot deliver it -> skipped
$r = stobeDirectorPeopleSerials($j(['Malzin|hand_2740478464', 'Shay|hand_971557632']), $j(['Malzin|-1554488832', 'Shay|971557632']));
ok($r === ['Shay' => '971557632'], 'negative raw serial skipped, others kept');
ok(stobeDirectorPeopleSerials($j(['Malzin|hand_2740478464'])) === ['Malzin' => '2740478464'], 'without a raw list the unsigned id is kept');
// a raw entry for another name does not suppress this one; bad raw json is ignored
ok(stobeDirectorPeopleSerials($j(['A|hand_5']), $j(['B|-1'])) === ['A' => '5'], 'raw list matched by name only');
ok(stobeDirectorPeopleSerials($j(['A|hand_5']), 'garbage') === ['A' => '5'], 'bad raw json ignored');
// source guard: the generator uses the helper, not the old ctype_digit test
$src = file_get_contents(__DIR__ . '/../lib/director_scene.php');
ok(strpos($src, 'stobeDirectorPeopleSerials(strval($GLOBALS') !== false && strpos($src, 'ctype_digit($parts[1])') === false, 'stobeGenerateDirectorScene uses the helper');
echo "PASS imm26_fix03b2_director_identity ($n checks)\n";
