#!/usr/bin/env python3
"""Generates imm26_durable_item_id_native_regression.php = option B test harness header (adapted: DurA names, ids in evidence) + native_test_body.php.part."""
import io, os
here = os.path.dirname(os.path.abspath(__file__))
src = io.open(os.path.join(here, '..', 'imm26-durable-item-id', 'imm26_durable_item_id_regression.php'), encoding='utf-8', newline='').read().replace('\r\n', '\n')
head = src.split('$T = 100000;')[0]
head = head.replace("campDur%", "campDurA%").replace("'Dur %'", "'DurA %'").replace("'Dur ", "'DurA ")
head = head.replace("// imm26 durable item id: restitution after a save/load, matched by a strict server-side fingerprint (no native change).",
                    "// imm26 10-f OPTION A: restitution after a save/load, matched by the NATIVE durable item id (sdi1-...), option B fingerprint as fallback.")
head = head.replace("tests/imm26_durable_item_id_regression.php", "tests/imm26_durable_item_id_native_regression.php")
head = head.replace("Touches only campaigns 'campDur*' and NPCs named 'Dur *'", "Touches only campaigns 'campDurA*' and NPCs named 'DurA *'")
a1 = "$savedFp = one("
assert head.count(a1) == 1
head = head.replace(a1, "$savedId = one('SELECT value FROM general_settings WHERE id=$1', ['STOBE_REPAIR_DURABLE_ID_ENABLED']); $savedId = $savedId ? $savedId['value'] : null;\n" + a1)
a2 = "setting('STOBE_REPAIR_FINGERPRINT_ENABLED', null);\nconst P"
assert head.count(a2) == 1
head = head.replace(a2, "setting('STOBE_REPAIR_FINGERPRINT_ENABLED', null); setting('STOBE_REPAIR_DURABLE_ID_ENABLED', null);\nconst P")
s0 = head.index("// $stacks: list of"); s1 = head.index("function totals")
head = head[:s0] + '''// $stacks: list of [item_key, prototype_id, type_key, quantity, ?durable_item_id]
function evidence(array $stacks, string $from, string $to): array {
    $items = [];
    foreach ($stacks as $s) {
        $row = ['item_key'=>$s[0], 'prototype_id'=>$s[1], 'type_key'=>$s[2], 'quantity'=>$s[3], 'from_storage_id'=>$from, 'to_storage_id'=>$to];
        if (isset($s[4])) $row['durable_item_id'] = $s[4];
        $items[] = $row;
    }
    return ['verified'=>true, 'method'=>'same_live_item_whole_stack', 'items'=>$items];
}
''' + head[s1:]
t = "function totals(array $stacks): array { $t = []; foreach ($stacks as [, , $type, $qty]) $t[$type] = ($t[$type] ?? 0) + $qty; return $t; }"
assert head.count(t) == 1
head = head.replace(t, "function totals(array $stacks): array { $t = []; foreach ($stacks as $s) $t[$s[2]] = ($t[$s[2]] ?? 0) + $s[3]; return $t; }")
body = io.open(os.path.join(here, 'native_test_body.php.part'), encoding='utf-8', newline='').read().replace('\r\n', '\n')
io.open(os.path.join(here, 'imm26_durable_item_id_native_regression.php'), 'w', encoding='utf-8', newline='').write(head + body)
print('ok')
