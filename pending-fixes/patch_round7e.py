#!/usr/bin/env python3
"""Round 7e: I4 "shirt and shorts" -> only the shorts came off, yet the deal went COMPLETE.

  1. unequip_item.request and stobe_action.request are one-slot mailboxes (KenshiFP reads
     one line every 50 ms and deletes the file). The writers renamed straight over a
     pending request, so the second of two back-to-back actions replaced the first.
     They now wait for the slot (up to 2 s), like stobeNegQueueBridgeBySerial does.
  2. UNEQUIP_ITEM verification ignored the item: any successful unequip by that NPC
     verified every UNEQUIP term. It now has to match the term's item.

Usage: patch_round7e.py <StobeServer root>
"""
import sys, pathlib

root = pathlib.Path(sys.argv[1])


def patch(rel, old, new):
    p = root / rel
    text = p.read_text(encoding="utf-8")
    assert text.count(old) == 1, f"{rel}: anchor not found exactly once: {old[:70]!r}"
    p.write_text(text.replace(old, new), encoding="utf-8")


WAIT = """    // One-slot mailbox (KenshiFP takes one request every 50 ms): never overwrite a pending one.
    for ($slotWait = 0; $slotWait < 40 && file_exists($requestPath); $slotWait++) usleep(50000);
"""

for name in ("unequip_item.request", "stobe_action.request"):
    anchor = ("    $requestPath = '/mnt/d/Steam/steamapps/common/Kenshi/RE_Kenshi/mods/Stobe/" + name + "';\n"
              "    $tempPath = $requestPath . '.tmp.' . strval(getmypid());\n")
    patch("lib/chat_helper_functions.php", anchor, anchor + WAIT)

patch("lib/negotiation_engine.php",
      """function stobeNegBridgeResult(string $command, int $serial, int $sinceUnix): string {
    $result = '';
    foreach (stobeNegBridgeRecords($sinceUnix) as $r) {
        $body = $r['body'];
        if ($command === 'UNEQUIP_ITEM') {
            if (preg_match('/^UNEQUIP_ITEM serial=(\\d+) .*result=(\\w+)/', $body, $m) && intval($m[1]) === $serial) $result = $m[2];
            continue;
        }""",
      """function stobeNegBridgeResult(string $command, int $serial, int $sinceUnix, string $item = ''): string {
    $result = '';
    $base = static fn(string $n): string => strtolower(trim(preg_replace('/\\s*\\[[^\\]]*\\]|\\s+(shoddy|standard|high quality|specialist|masterwork|mk ?[ivx]+)$/i', '', $n) ?? $n));
    $wanted = $base($item);
    foreach (stobeNegBridgeRecords($sinceUnix) as $r) {
        $body = $r['body'];
        if ($command === 'UNEQUIP_ITEM') {
            if (preg_match('/^UNEQUIP_ITEM serial=(\\d+) query=(.*?) matched=(.*?) result=(\\w+)/', $body, $m) && intval($m[1]) === $serial) {
                // Each term is verified by its own item's result, not by any unequip.
                if ($wanted !== '') {
                    $got = $base($m[3]) !== '' ? $base($m[3]) : $base($m[2]);
                    if ($got === '' || (!str_contains($wanted, $got) && !str_contains($got, $wanted))) continue;
                }
                $result = $m[4];
            } elseif ($wanted === '' && preg_match('/^UNEQUIP_ITEM serial=(\\d+) .*result=(\\w+)/', $body, $m) && intval($m[1]) === $serial) {
                $result = $m[2];
            }
            continue;
        }""")

patch("lib/negotiation_engine.php",
      """            $result = $serial > 0 ? stobeNegBridgeResult($bridge[$kind], $serial, $since) : '';""",
      """            $result = $serial > 0 ? stobeNegBridgeResult($bridge[$kind], $serial, $since, $kind === 'UNEQUIP_ITEM' ? strval($term['item'] ?? '') : '') : '';""")

print("patch_round7e: applied")
