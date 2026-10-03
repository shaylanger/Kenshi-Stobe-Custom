<?php
// Item 101 (REL builder, m16 rel-enslaved): 41 live core_npc_master rows (ids 33330-34058, created since 2026-10-02)
// store extended_data as a JSON array ('[]' x24, '[{}]' x17; metadata '[]' x55). Every relationship write to them fails
// in Postgres: jsonb_set(extended_data, '{relationships}', ...) on an array -> "path element at position 1 is not an
// integer" (15 in the PG log, latest 22:27 for camp NPCs like Arlo/Blacksheep).
// Cause: an empty PHP array json-encodes as '[]' (normalizeJsonString), and the profile/snapshot writers pass an empty
// extended_data/metadata array for new NPCs.
// Fix:
//  - stobeJsonObjectString(): extended_data/metadata/relationships are always written as JSON objects ('{}' when empty;
//    a list of objects is merged; any other list becomes '{}').
//  - the two relationship writers turn a non-object extended_data into '{}' before jsonb_set.
//  - the existing rows are repaired by tools/item101_repair_npc_json.sql (backup table first).
// Usage: php item101_extended_data_object.php <tree root>
$root = rtrim($argv[1] ?? '', '/');
function p101(string $path, array $edits): void {
    $s = file_get_contents($path);
    if ($s === false) { fwrite(STDERR, "cannot read $path\n"); exit(1); }
    if (str_contains($s, 'Item 101')) { fwrite(STDERR, "$path already has item 101\n"); exit(1); }
    foreach ($edits as [$a, $b]) {
        if (substr_count($s, $a) !== 1) { fwrite(STDERR, "anchor missing/not unique in $path: " . substr($a, 0, 90) . "\n"); exit(1); }
        $s = str_replace($a, $b, $s);
    }
    file_put_contents($path, $s); echo "patched $path\n";
}
p101("$root/lib/data_functions.php", [
['function normalizeJsonString(mixed $value): string {', <<<'B'
/** Item 101: a JSON object for columns that must be objects (extended_data, metadata, relationships). */
function stobeJsonObjectString(mixed $value): string {
    if (is_string($value)) {
        $text = trim($value);
        if ($text === '') return '{}';
        $decoded = json_decode($text, true);
        if (!is_array($decoded)) return '{}';
        $value = $decoded;
    }
    if (!is_array($value) || count($value) === 0) return '{}';
    if (array_is_list($value)) {
        $merged = [];
        foreach ($value as $v) {
            if (is_array($v) && !array_is_list($v)) $merged = array_merge($merged, $v);
        }
        if (count($merged) === 0) return '{}';
        $value = $merged;
    }
    $encoded = json_encode((object)$value, JSON_UNESCAPED_UNICODE);
    return is_string($encoded) ? $encoded : '{}';
}

function normalizeJsonString(mixed $value): string {
B],
["    \$metadata = normalizeJsonString(normalizeCoreNpcMetadata(\$row['metadata'] ?? '{}'));\n    \$extendedData = normalizeJsonString(normalizeCoreNpcExtendedData(\$row['extended_data'] ?? '{}'));",
 "    \$metadata = stobeJsonObjectString(normalizeCoreNpcMetadata(\$row['metadata'] ?? '{}')); // Item 101\n    \$extendedData = stobeJsonObjectString(normalizeCoreNpcExtendedData(\$row['extended_data'] ?? '{}'));"],
["    \$metadataJson = normalizeJsonString(\$metadataArray);\n\n    \$profilePersisted = \$db->exec(",
 "    \$metadataJson = stobeJsonObjectString(\$metadataArray); // Item 101\n\n    \$profilePersisted = \$db->exec("],
["    \$extendedDataJson = normalizeJsonString(normalizeCoreNpcExtendedData(\$profile['extended_data'] ?? '{}'));",
 "    \$extendedDataJson = stobeJsonObjectString(normalizeCoreNpcExtendedData(\$profile['extended_data'] ?? '{}')); // Item 101"],
["    \$metadataJson = normalizeJsonString(\$metadataForStorage);\n    \$extendedDataJson = normalizeJsonString(\$snapshotExtendedPayload);",
 "    \$metadataJson = stobeJsonObjectString(\$metadataForStorage); // Item 101\n    \$extendedDataJson = stobeJsonObjectString(\$snapshotExtendedPayload);"],
["            \$params[] = normalizeJsonString(\$fields[\$column]);\n            \$paramIndex++;\n            continue;\n        }\n\n        if (\$type === 'bounty_json') {",
 "            \$params[] = in_array(\$column, ['extended_data', 'metadata'], true) // Item 101: always objects\n                ? stobeJsonObjectString(\$fields[\$column]) : normalizeJsonString(\$fields[\$column]);\n            \$paramIndex++;\n            continue;\n        }\n\n        if (\$type === 'bounty_json') {"],
]);
p101("$root/lib/chat_helper_functions.php", [
["            \"UPDATE core_npc SET extended_data = jsonb_set(COALESCE(extended_data, '{}'::jsonb), '{relationships}', \$2::jsonb, true),",
 "            \"UPDATE core_npc SET extended_data = jsonb_set(CASE WHEN jsonb_typeof(extended_data) = 'object' THEN extended_data ELSE '{}'::jsonb END, '{relationships}', \$2::jsonb, true), /* Item 101 */"],
["                     extended_data = jsonb_set(\n                         COALESCE(extended_data, '{}'::jsonb),\n                         '{relationships}',",
 "                     extended_data = jsonb_set( -- Item 101: an array (bad old row) becomes an object\n                         CASE WHEN jsonb_typeof(extended_data) = 'object' THEN extended_data ELSE '{}'::jsonb END,\n                         '{relationships}',"],
]);
$test = <<<'T'
<?php
// Item 101: extended_data/metadata are written as JSON objects; relationship writes survive an old array row.
require __DIR__ . '/../lib/bootstrap.php';
$pass = 0; $fail = 0;
function check(string $name, bool $ok, $detail = null): void {
    global $pass, $fail;
    if ($ok) { $pass++; echo "PASS $name\n"; } else { $fail++; echo "FAIL $name" . ($detail !== null ? ' :: ' . json_encode($detail) : '') . "\n"; }
}
check('empty array -> {}', stobeJsonObjectString([]) === '{}');
check('"[]" -> {}', stobeJsonObjectString('[]') === '{}');
check('[{}] -> {}', stobeJsonObjectString([[]]) === '{}' && stobeJsonObjectString('[{}]') === '{}');
check('object kept', stobeJsonObjectString(['a' => 1]) === '{"a":1}');
check('list of objects merged', stobeJsonObjectString([['a' => 1], ['b' => 2]]) === '{"a":1,"b":2}');
$db = $GLOBALS['db'];
$name = 'Item101 Camp Npc';
$db->exec("DELETE FROM core_npc_master WHERE name=$1", [$name]);
storeNpcProfile($name, ['name' => $name, 'extended_data' => [], 'metadata' => []], ['history_reason' => 'test']);
$row = $db->fetchOne("SELECT jsonb_typeof(extended_data) AS e, jsonb_typeof(metadata) AS m FROM core_npc_master WHERE name=$1", [$name]);
check('new NPC: extended_data and metadata are objects', is_array($row) && $row['e'] === 'object' && $row['m'] === 'object', $row);
$db->exec("UPDATE core_npc_master SET extended_data='[]'::jsonb WHERE name=$1", [$name]); // an old bad row
$npc = getNpcData($name);
$ok = stobePersistNpcRelationshipMap($name, ['Shay' => ['aff' => 80, 'type' => 'platonic', 'tier' => 'Devoted', 'note' => 'test']], is_array($npc) ? $npc : false);
$row = $db->fetchOne("SELECT jsonb_typeof(extended_data) AS e, extended_data->'relationships'->'Shay'->>'aff' AS aff FROM core_npc_master WHERE name=$1", [$name]);
check('relationship write on an array row succeeds and leaves an object', $ok !== false && is_array($row) && $row['e'] === 'object' && $row['aff'] === '80', [$ok, $row]);
$db->exec("DELETE FROM core_npc_master WHERE name=$1", [$name]);
echo "pass=$pass fail=$fail\n";
exit($fail > 0 ? 1 : 0);
T;
if (!file_exists("$root/tests/npc_json_object_regression.php")) { file_put_contents("$root/tests/npc_json_object_regression.php", $test); echo "added tests/npc_json_object_regression.php\n"; }
