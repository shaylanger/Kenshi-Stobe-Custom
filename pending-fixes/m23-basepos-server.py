#!/usr/bin/env python3
"""m23 16-fullbase: remember the player base at its real town position (Stobe sends town_x/y/z).

stobeWorkGoalRememberBaseLocation stored the newest location_zones row (any zone, any character) as
the base position, and base ids repeat across saves (66--INGAME:-1:-1), so "Your Outpost" on Full-Base
resolved to Squin coords left from another save: Avarek walked off to Squin (16-fullbase, m22).
Usage: m23-basepos-server.py <StobeServer tree root>
"""
import sys, pathlib
root = pathlib.Path(sys.argv[1])

def patch(rel, pairs):
    p = root / rel
    s = p.read_text()
    for old, new in pairs:
        if new in s:
            continue
        assert s.count(old) == 1, (rel, old[:70], s.count(old))
        s = s.replace(old, new)
    p.write_text(s)

patch("lib/player_base_functions.php", [
    ("""    if ($normalized['name'] === '') {
        $normalized['name'] = 'Player Base';
    }
    return $normalized;
}
""", """    if ($normalized['name'] === '') {
        $normalized['name'] = 'Player Base';
    }
    // m23: the base's real town position (Stobe 'town_x/y/z'); base ids repeat across saves.
    $tx = $value['town_x'] ?? null; $ty = $value['town_y'] ?? null; $tz = $value['town_z'] ?? null;
    if (is_numeric($tx) && is_numeric($ty) && is_numeric($tz)) {
        $tx = floatval($tx); $ty = floatval($ty); $tz = floatval($tz);
        if (is_finite($tx) && is_finite($ty) && is_finite($tz) &&
            abs($tx) < 10000000.0 && abs($ty) < 10000000.0 && abs($tz) < 10000000.0) {
            $normalized['town_x'] = $tx; $normalized['town_y'] = $ty; $normalized['town_z'] = $tz;
        }
    }
    return $normalized;
}
"""),
    ("""            stobeWorkGoalRememberBaseLocation(
                strval($base['base_id'] ?? ''),
                strval($base['name'] ?? 'Player Base'),
                $gameTs
            );""", """            stobeWorkGoalRememberBaseLocation(
                strval($base['base_id'] ?? ''),
                strval($base['name'] ?? 'Player Base'),
                $gameTs,
                isset($base['town_x'], $base['town_y'], $base['town_z'])
                    ? ['x' => $base['town_x'], 'y' => $base['town_y'], 'z' => $base['town_z']]
                    : null
            );"""),
])

patch("lib/work_goal_functions.php", [
    ("""function stobeWorkGoalRememberBaseLocation(string $baseId, string $baseName, int $gameTs): void
{
    $baseId = trim($baseId);
    $baseName = trim($baseName);
    if ($baseId === '') {
        return;
    }
    stobeWorkGoalEnsureSchema();
    $db = $GLOBALS['db'];

    $location = $db->fetchOne(""", """function stobeWorkGoalRememberBaseLocation(string $baseId, string $baseName, int $gameTs, ?array $townPos = null): void
{
    $baseId = trim($baseId);
    $baseName = trim($baseName);
    if ($baseId === '') {
        return;
    }
    stobeWorkGoalEnsureSchema();
    $db = $GLOBALS['db'];

    // m23: Stobe sends the base's own town position: use it. The fallback below (newest zone seen by
    // anyone) can be another town, or a same-named base from another save (ids repeat across saves).
    $location = (is_array($townPos) && is_numeric($townPos['x'] ?? null) &&
                 is_numeric($townPos['y'] ?? null) && is_numeric($townPos['z'] ?? null))
        ? ['x' => floatval($townPos['x']), 'y' => floatval($townPos['y']), 'z' => floatval($townPos['z']),
           'zone_name' => $baseName, 'city_name' => $baseName]
        : $db->fetchOne("""),
])

patch("tests/goal_destination_regression.php", [
    ("""$db->exec("DELETE FROM player_base_locations WHERE base_name='GdTest Fortress'");
""", """$db->exec("DELETE FROM player_base_locations WHERE base_name='GdTest Fortress'");
// m23 (16-fullbase): the base is remembered at the town position Stobe sends, not the newest zone seen
$db->exec("INSERT INTO player_base_locations (base_id, base_name, x, y, z) VALUES ('gdtest-fortress', 'GdTest Fortress', -62461, 324, 16346)");
stobeWorkGoalRememberBaseLocation('gdtest-fortress', 'GdTest Fortress', 5, ['x' => -76592.5, 'y' => 332.0, 'z' => 33017.0]);
$f = stobeWorkGoalResolveDestination('GdTest Fortress');
check('m23: a base snapshot with town_x/y/z moves a stale base row to the town', is_array($f) && floatval($f['x']) === -76592.5 && floatval($f['z']) === 33017.0, $f);
$n = stobeNormalizePlayerBaseSnapshot(['inside' => true, 'base_id' => 'gdtest-fortress', 'name' => 'GdTest Fortress', 'town_x' => -76592.5, 'town_y' => 332, 'town_z' => '33017']);
check('m23: the base snapshot keeps negative town coords', ($n['town_x'] ?? null) === -76592.5 && ($n['town_z'] ?? null) === 33017.0, $n);
$db->exec("DELETE FROM player_base_locations WHERE base_name='GdTest Fortress'");
"""),
])
print("ok")
