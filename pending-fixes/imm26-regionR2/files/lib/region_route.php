<?php
/**
 * imm26 24-b (Shay 2026-10-16): region routing for a broad "consider <region>" agreement.
 *
 * Grounded destination = a native candidate id when one is in range (area_goal.php), else the NEAREST KNOWN TOWN IN THE REGION. This module owns the
 * second half. It is pure data + arithmetic: no movement, no consent, no trip state. The town -> region table is the ONLY data source and it sits behind
 * stobeRegionRouteTownRegions(); when the native world_towns snapshot carries a `region` field, only that one function changes.
 *
 * Undiscovered (rumoured) towns in stobe_world_town MAY be used (Shay 2026-10-16); the caller words the offer as "I'd lead us to <Town> first".
 */

/** Region names compare case-insensitively without a leading "the " or punctuation ("The Swamp" == "Swamp", "Okran's Pride" == "okrans pride"). */
function stobeRegionRouteKey(string $region): string {
    $k = mb_strtolower(trim($region));
    $k = preg_replace('/^the\s+/u', '', $k) ?? $k;
    return preg_replace('/[^\p{L}\p{N}]+/u', '', $k) ?? '';
}

/**
 * THE data-source seam. Returns lower(town name) => ['name'=>string,'region'=>string,'source'=>string].
 * Today: data/kenshi_town_regions.json (static, provenance per town). Tomorrow: a native `region` per world town replaces the body.
 * Tests may set $GLOBALS['STOBE_REGION_ROUTE_TOWN_REGIONS'] (same shape as the file's "towns" object) to bypass the file.
 */
function stobeRegionRouteTownRegions(): array {
    static $cache = null;
    $override = $GLOBALS['STOBE_REGION_ROUTE_TOWN_REGIONS'] ?? null;
    $towns = [];
    if (is_array($override)) {
        $towns = $override;
    } else {
        if ($cache !== null) return $cache;
        $raw = @file_get_contents(__DIR__ . '/../data/kenshi_town_regions.json');
        $decoded = is_string($raw) ? json_decode($raw, true) : null;
        $towns = is_array($decoded) && is_array($decoded['towns'] ?? null) ? $decoded['towns'] : [];
    }
    $out = [];
    foreach ($towns as $name => $entry) {
        $name = trim(strval($name));
        $region = is_array($entry) ? trim(strval($entry['region'] ?? '')) : trim(strval($entry));
        if ($name === '' || $region === '') continue;
        $out[mb_strtolower($name)] = ['name'=>$name, 'region'=>$region,
            'source'=>is_array($entry) ? strval($entry['source'] ?? '') : ''];
    }
    if (!is_array($override)) $cache = $out;
    return $out;
}

/** Towns the server knows with coordinates (location_zones + stobe_world_town, discovered or rumoured), each with a `discovered` flag when known. */
function stobeRegionRouteWorldTowns(): array {
    if (!function_exists('stobeTravelZoneRows')) return [];
    $zones = stobeTravelZoneRows();
    $discovered = [];
    $db = $GLOBALS['db'] ?? null;
    if ($db && function_exists('stobeEnsureWorldTownTable') && stobeEnsureWorldTownTable()) {
        try {
            foreach ((array)$db->fetchAll("SELECT name, discovered FROM stobe_world_town LIMIT 1000") as $row) {
                $discovered[mb_strtolower(trim(strval($row['name'] ?? '')))] = in_array($row['discovered'] ?? false, [true, 't', 'true', 1, '1'], true);
            }
        } catch (Throwable $e) { /* flag unknown */ }
    }
    foreach ($zones as &$zone) $zone['discovered'] = $discovered[mb_strtolower($zone['name'])] ?? null;
    unset($zone);
    return $zones;
}

/**
 * Pure pick: the nearest tagged town of $region. $zones rows = ['name','x','y','z','discovered'?]; $pos = NPC position or null;
 * the town the NPC stands in is never chosen. Order: horizontal distance (x/z, the stobeTravelWhere metric), discovered first, name.
 * Without a position the order is discovered first, then name. Returns the row + 'distance' and 'region_source', or null.
 */
function stobeRegionRoutePick(string $region, array $zones, ?array $pos, string $currentTown, array $townRegions): ?array {
    $want = stobeRegionRouteKey($region);
    if ($want === '') return null;
    $here = mb_strtolower(trim($currentTown));
    $best = [];
    foreach ($zones as $zone) {
        if (!is_array($zone)) continue;
        $name = trim(strval($zone['name'] ?? ''));
        $tag = $townRegions[mb_strtolower($name)] ?? null;
        if ($name === '' || !is_array($tag) || stobeRegionRouteKey(strval($tag['region'])) !== $want) continue;
        if ($here !== '' && mb_strtolower($name) === $here) continue;
        foreach (['x','y','z'] as $axis) if (!is_numeric($zone[$axis] ?? null) || !is_finite(floatval($zone[$axis]))) continue 2;
        $dist = $pos ? hypot(floatval($zone['x']) - floatval($pos['x']), floatval($zone['z']) - floatval($pos['z'])) : null;
        $best[] = ['name'=>$name, 'x'=>floatval($zone['x']), 'y'=>floatval($zone['y']), 'z'=>floatval($zone['z']),
            'discovered'=>$zone['discovered'] ?? null, 'distance'=>$dist, 'region_source'=>strval($tag['source'] ?? '')];
    }
    if (!$best) return null;
    usort($best, static fn($a, $b) => [$a['distance'] ?? INF, ($a['discovered'] === true) ? 0 : 1, $a['name']]
        <=> [$b['distance'] ?? INF, ($b['discovered'] === true) ? 0 : 1, $b['name']]);
    return $best[0];
}

/**
 * The single entry point for the integration: nearest known town in $region for this NPC.
 * @return array{status:string,region:string,town?:array}  status route_ready | cannot_route_yet
 */
function stobeRegionRouteResolve(string $region, array|false $npc, string $speaker, string $currentTown): array {
    $region = trim($region);
    $none = ['status'=>'cannot_route_yet', 'region'=>$region];
    if ($region === '') return $none;
    try {
        $townRegions = stobeRegionRouteTownRegions();
        if (!$townRegions) return $none;
        $zones = stobeRegionRouteWorldTowns();
        if (!$zones) return $none;
        $pos = function_exists('stobeTravelNpcPosition') ? stobeTravelNpcPosition($npc, $speaker, $zones) : null;
        $town = stobeRegionRoutePick($region, $zones, $pos, $currentTown, $townRegions);
    } catch (Throwable $e) { return $none; }
    return $town ? ['status'=>'route_ready', 'region'=>$region, 'town'=>$town] : $none;
}
