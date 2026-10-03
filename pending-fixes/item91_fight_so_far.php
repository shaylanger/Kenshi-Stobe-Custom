<?php
// Item 91 (A13, run m16): a long fight pushes its early events (who started it, the first knockouts) out of
// the prompt: every hit is a stored `combat` row, the history keeps the last CONTEXT_HISTORY (50) rows and the
// combat block the last 5 notable rows. Fix: a compact <this_fight_so_far> block built from the DB for the
// current (or just-ended) fight: the opening attack plus every knockout/death/limb loss of the fight's
// participants, which per-hit rows can't push out.
// Usage: php item91_fight_so_far.php <tree root>   (asserts every anchor; idempotent refusal if already applied)
$root = rtrim($argv[1] ?? '', '/');
if ($root === '' || !is_dir($root)) { fwrite(STDERR, "usage: php item91_fight_so_far.php <tree root>\n"); exit(2); }

function patchFile(string $path, array $edits): void {
    $src = file_get_contents($path);
    if ($src === false) { fwrite(STDERR, "cannot read $path\n"); exit(1); }
    if (str_contains($src, 'Item 91')) { fwrite(STDERR, "$path already has item 91\n"); exit(1); }
    foreach ($edits as [$anchor, $replacement]) {
        if (substr_count($src, $anchor) !== 1) { fwrite(STDERR, "anchor not unique/missing in $path: " . substr($anchor, 0, 80) . "\n"); exit(1); }
        $src = str_replace($anchor, $replacement, $src);
    }
    file_put_contents($path, $src);
    echo "patched $path\n";
}

$helpers = <<<'PHP'
/**
 * Item 91: the current (or just-ended) fight's notable events, oldest first, from rows newest first
 * (each ['type','data','gamets']). Pure (no DB) so the regression test can feed rows.
 * A fight = the run of fight rows the NPC witnessed with no gap above $gap game seconds; it counts when its
 * last row is within $recent of now. Participants grow from the NPC through every "A: Initiated attack
 * (talking to: B)" row that touches one of them, so a town brawl next door stays out.
 */
function stobeSelectFightSoFarEvents(array $rowsDesc, string $npcName, int $now, int $gap = 3000, int $recent = 6000, int $max = 12): array {
    $npc = strtolower(trim($npcName));
    if ($npc === '' || $now <= 0 || count($rowsDesc) === 0) return [];
    $latest = intval($rowsDesc[0]['gamets'] ?? 0);
    if ($latest <= 0 || $latest > $now || $now - $latest > $recent) return [];
    $episode = [];
    $prev = $latest;
    foreach ($rowsDesc as $row) {
        $g = intval($row['gamets'] ?? 0);
        if ($g <= 0 || $g > $now) continue;
        if ($prev - $g > $gap) break;
        $episode[] = $row;
        $prev = $g;
    }
    $episode = array_reverse($episode);
    $pairs = [];
    foreach ($episode as $row) {
        if (strtolower(strval($row['type'] ?? '')) !== 'combat') continue;
        if (preg_match('/^(.+?):\s*(?:Initiated attack|Defending against)\b.*?\(talking to:\s*(.+?)\)\s*$/i', trim(strval($row['data'] ?? '')), $m)) {
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
    $out = []; $seen = []; $opening = false;
    foreach ($episode as $row) {
        $type = strtolower(trim(strval($row['type'] ?? '')));
        $data = trim(strval($row['data'] ?? ''));
        if ($data === '') continue;
        $keep = false;
        if ($type === 'combat') {
            if (!$opening && preg_match('/^(.+?):\s*(?:Initiated attack|Defending against)\b.*?\(talking to:\s*(.+?)\)/i', $data, $m)
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

/** Item 91: load the NPC's fight rows from the DB and attach the selection as metadata 'fight_so_far'. */
function stobeAttachFightSoFarEvents(array $npcData, string $npcName, int $currentGamets, array $aliases = []): array {
    if ($currentGamets <= 0 || normalizeParticipantNameToken($npcName) === '') return $npcData;
    try {
        $db = $GLOBALS['db'] ?? null;
        if (!$db) return $npcData;
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
        $rows = $db->fetchAll($query, $params);
        $events = stobeSelectFightSoFarEvents(is_array($rows) ? $rows : [], $npcName, $currentGamets);
    } catch (Throwable $e) {
        if (function_exists('stobeLogWarn')) stobeLogWarn('Fight so far (item 91) skipped', ['error' => $e->getMessage()]);
        return $npcData;
    }
    if (count($events) === 0) return $npcData;
    $metadata = normalizeNpcMetadataPayload($npcData['metadata'] ?? []);
    $metadata['fight_so_far'] = $events;
    $npcData['metadata'] = $metadata;
    return $npcData;
}

/** Item 91: the prompt block. */
function stobeBuildFightSoFarPromptBlock(array $npcData): string {
    $metadata = normalizeNpcMetadataPayload($npcData['metadata'] ?? []);
    $events = $metadata['fight_so_far'] ?? [];
    if (!is_array($events) || count($events) === 0) return '';
    $lines = ['<this_fight_so_far>',
        '  <note>What happened in this fight from its start (oldest first). You saw it; you remember it even if the latest blows are all you hear about.</note>'];
    foreach ($events as $event) {
        if (!is_array($event)) continue;
        $line = trim(strval($event['line'] ?? ''));
        if ($line === '') continue;
        $lines[] = '  <event type="' . stobePromptXmlEscape(strval($event['type'] ?? 'event')) . '">'
            . stobePromptXmlEscape(truncatePromptValue($line, 200)) . '</event>';
    }
    $lines[] = '</this_fight_so_far>';
    return implode("\n", $lines);
}

function getCurrentPlayerFactionIdentity(): array {
PHP;

patchFile("$root/lib/chat_helper_functions.php", [
    ["function getCurrentPlayerFactionIdentity(): array {", $helpers],
    ["    \$combatPriorityBlock = stobeBuildCombatPriorityPromptBlock(\$npcData, \$npcName);\n    if (\$combatPriorityBlock !== '') {\n        \$prompt .= \"\\n\\n\" . \$combatPriorityBlock;\n    }\n",
     "    \$combatPriorityBlock = stobeBuildCombatPriorityPromptBlock(\$npcData, \$npcName);\n    if (\$combatPriorityBlock !== '') {\n        \$prompt .= \"\\n\\n\" . \$combatPriorityBlock;\n    }\n    \$fightSoFarBlock = stobeBuildFightSoFarPromptBlock(\$npcData); // Item 91\n    if (\$fightSoFarBlock !== '') {\n        \$prompt .= \"\\n\\n\" . \$fightSoFarBlock;\n    }\n"],
]);
patchFile("$root/processor/chat.php", [
    ["if (!\$narratorMode && is_array(\$npcData)) {\n    \$npcData = stobeAttachRecentCombatPromptEvents(\$npcData, \$eventHistory, intval(\$gamets));\n}\n",
     "if (!\$narratorMode && is_array(\$npcData)) {\n    \$npcData = stobeAttachRecentCombatPromptEvents(\$npcData, \$eventHistory, intval(\$gamets));\n    \$npcData = stobeAttachFightSoFarEvents(\$npcData, \$targetNpc, intval(\$gamets), \$historyAliases); // Item 91\n}\n"],
]);
patchFile("$root/processor/rechat.php", [
    ["if (is_array(\$npcData)) {\n    \$npcData = stobeAttachRecentCombatPromptEvents(\$npcData, \$eventHistory, intval(\$gamets));\n}\n",
     "if (is_array(\$npcData)) {\n    \$npcData = stobeAttachRecentCombatPromptEvents(\$npcData, \$eventHistory, intval(\$gamets));\n    \$npcData = stobeAttachFightSoFarEvents(\$npcData, \$respondingNpc, intval(\$gamets), \$historyAliases); // Item 91\n}\n"],
]);
