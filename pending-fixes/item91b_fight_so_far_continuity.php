<?php
// Item 91b (A13 v3, run m16): the <this_fight_so_far> block was never built for the real question. The fight
// rows were loaded with the audience filter, which drops every row while Malzin is knocked out (she was KO'd
// twice in the waves), so her rows had gaps > 3000 game s and the "fight" was only its last few seconds,
// without the opening or Kor Gast's knockout. Now: load the fight rows of the window without the audience
// filter; participants grow from the NPC through attack pairs; the fight's continuity uses every
// participant's rows (the fight goes on while she is down); only rows she saw (her people token present and
// not unconscious/sleeping) become lines; the opening attack must be one she saw too.
// Usage: php item91b_fight_so_far_continuity.php <tree root>   (needs item 91; asserts the anchors)
$root = rtrim($argv[1] ?? '', '/');
$path = "$root/lib/chat_helper_functions.php";
$src = @file_get_contents($path);
if ($src === false) { fwrite(STDERR, "cannot read $path\n"); exit(2); }
if (str_contains($src, 'Item 91b')) { fwrite(STDERR, "already applied\n"); exit(1); }
$start = strpos($src, "/**\n * Item 91: the current (or just-ended) fight's notable events");
$end = strpos($src, "/** Item 91: load the NPC's fight rows from the DB");
if ($start === false || $end === false || $end < $start) { fwrite(STDERR, "item 91 anchors missing\n"); exit(1); }

$newSelect = <<<'PHP'
/**
 * Item 91 + 91b: the current (or just-ended) fight's notable events, oldest first, from rows newest first
 * (each ['type','data','gamets', optional 'people']). Pure (no DB) so the regression test can feed rows.
 * Participants grow from the NPC through every "A: Initiated attack (talking to: B)" row that touches one of
 * them, so a brawl next door stays out. A fight = the participants' rows with no gap above $gap game s, and
 * it counts when its last row is within $recent of now. Item 91b: continuity uses every participant's rows
 * (the fight goes on while the NPC is knocked out); a line is kept only if the NPC saw it ('people' lists
 * her, not unconscious/sleeping; rows without 'people' count as seen).
 */
function stobeFightRowSeenBy(array $row, string $npcLower): bool {
    if (!array_key_exists('people', $row)) return true; // Item 91b
    $people = json_decode(strval($row['people'] ?? ''), true);
    if (!is_array($people)) return false;
    foreach ($people as $token) {
        $name = strtolower(trim(explode('|', strval($token))[0]));
        if ($name === $npcLower) return true;
        if (str_starts_with($name, $npcLower . ' (')) {
            return preg_match('/\((unconscious|sleeping|knocked[ _]out|dead)\)/', $name) !== 1;
        }
    }
    return false;
}

function stobeSelectFightSoFarEvents(array $rowsDesc, string $npcName, int $now, int $gap = 3000, int $recent = 6000, int $max = 12): array {
    $npc = strtolower(trim($npcName));
    if ($npc === '' || $now <= 0 || count($rowsDesc) === 0) return [];
    $pairRe = '/^(.+?):\s*(?:Initiated attack|Defending against)\b.*?\(talking to:\s*(.+?)\)\s*$/i';
    $pairs = [];
    foreach ($rowsDesc as $row) {
        if (strtolower(strval($row['type'] ?? '')) !== 'combat') continue;
        if (preg_match($pairRe, trim(strval($row['data'] ?? '')), $m)) {
            $pairs[] = [strtolower(trim($m[1])), strtolower(trim($m[2]))];
        }
    }
    $part = [$npc => true];
    for ($pass = 0; $pass < 4; $pass++) {
        $grew = false;
        foreach ($pairs as [$a, $b]) {
            if (isset($part[$a]) !== isset($part[$b])) { $part[$a] = true; $part[$b] = true; $grew = true; }
        }
        if (!$grew) break;
    }
    $subject = static function (string $data): string {
        $d = trim($data);
        $c = strpos($d, ':');
        if ($c !== false) return strtolower(trim(substr($d, 0, $c)));
        $w = stripos($d, ' was ');
        return $w !== false ? strtolower(trim(substr($d, 0, $w))) : '';
    };
    $involves = static function (array $row) use ($part, $subject, $pairRe, $npc): bool {
        $data = trim(strval($row['data'] ?? ''));
        if (preg_match($pairRe, $data, $m)) return isset($part[strtolower(trim($m[1]))]) || isset($part[strtolower(trim($m[2]))]);
        $s = $subject($data);
        return ($s !== '' && isset($part[$s])) || str_contains(strtolower($data), $npc);
    };
    $episode = [];
    $prev = null;
    foreach ($rowsDesc as $row) {
        $g = intval($row['gamets'] ?? 0);
        if ($g <= 0 || $g > $now || !$involves($row)) continue;
        if ($prev === null) {
            if ($now - $g > $recent) return [];
        } elseif ($prev - $g > $gap) {
            break;
        }
        $episode[] = $row;
        $prev = $g;
    }
    $episode = array_reverse($episode);
    $out = []; $seen = []; $opening = false;
    foreach ($episode as $row) {
        $type = strtolower(trim(strval($row['type'] ?? '')));
        $data = trim(strval($row['data'] ?? ''));
        if ($data === '' || !stobeFightRowSeenBy($row, $npc)) continue;
        $keep = false;
        if ($type === 'combat') {
            if (!$opening && preg_match($pairRe, $data, $m)
                && isset($part[strtolower(trim($m[1]))]) && isset($part[strtolower(trim($m[2]))])) {
                $keep = true; $opening = true;
            }
        } elseif (in_array($type, ['knockout', 'death', 'limb_loss'], true)) {
            $s = $subject($data);
            $keep = ($s !== '' && isset($part[$s])) || str_contains(strtolower($data), $npc);
        }
        if (!$keep) continue;
        $key = $type . '|' . strtolower($data);
        if (isset($seen[$key])) continue;
        $seen[$key] = true;
        $out[] = ['type' => $type === 'combat' ? 'opening' : $type, 'line' => $data, 'gamets' => intval($row['gamets'] ?? 0)];
    }
    if (count($out) <= 1 && (($out[0]['type'] ?? '') === 'opening')) return []; // nothing notable beyond the start
    if (count($out) > $max) {
        $head = array_slice($out, 0, 5);
        $tail = array_slice($out, -($max - 5));
        $out = array_merge($head, [['type' => 'gap', 'line' => (count($out) - $max) . ' more in between', 'gamets' => 0]], $tail);
    }
    return $out;
}

PHP;
$src = substr($src, 0, $start) . $newSelect . substr($src, $end);

$oldQ = <<<'PHP'
        // the audience SQL numbers its own placeholders from $1, so it goes first
        $params = [];
        $audienceSql = stobeEventAudienceSql($npcName, $params, $aliases);
        $params[] = $currentGamets - 40000; $lo = '$' . count($params);
        $params[] = $currentGamets; $hi = '$' . count($params);
        $query = "SELECT type, data, gamets FROM eventlog
                  WHERE type IN ('combat','combat_start','combat_end','knockout','death','limb_loss')
                    AND gamets BETWEEN {$lo} AND {$hi}
                    AND " . stobeBuildEventlogDeliveryVisibilitySql('eventlog') . "
                    AND {$audienceSql}
                  ORDER BY gamets DESC, rowid DESC LIMIT 4000";
PHP;
$newQ = <<<'PHP'
        // Item 91b: no audience filter (it drops every row while she is knocked out and breaks the fight
        // apart); who saw what is decided per row from 'people' in stobeSelectFightSoFarEvents.
        $params = [$currentGamets - 40000, $currentGamets];
        $query = "SELECT type, data, gamets, people FROM eventlog
                  WHERE type IN ('combat','knockout','death','limb_loss')
                    AND gamets BETWEEN $1 AND $2
                    AND " . stobeBuildEventlogDeliveryVisibilitySql('eventlog') . "
                  ORDER BY gamets DESC, rowid DESC LIMIT 6000";
PHP;
if (substr_count($src, $oldQ) !== 1) { fwrite(STDERR, "query anchor missing\n"); exit(1); }
$src = str_replace($oldQ, $newQ, $src);
file_put_contents($path, $src);
echo "patched $path\n";
