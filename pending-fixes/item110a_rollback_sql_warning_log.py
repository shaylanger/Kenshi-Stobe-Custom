#!/usr/bin/env python3
"""Item 110 (a): playthrough rollback failure diagnostics.

- The guard's error handlers log the SQL warning text (message, file, line) when
  they mark the rollback as failed (also for warnings suppressed with @).
- The failure flag only covers the rollback's own writes: it is reset right
  before the prune/restore starts, so a warning from normal request
  processing before the rollback no longer fails it.
- "Playthrough rollback could not finish" names the reason (restore error
  counts / first SQL warning).

Usage: python3 item110a_rollback_sql_warning_log.py <tree root>
"""
import sys, pathlib

root = pathlib.Path(sys.argv[1])


def patch(rel, pairs):
    p = root / rel
    s = p.read_text()
    for old, new in pairs:
        if new in s:
            print(f"{rel}: already applied")
            continue
        assert s.count(old) == 1, f"{rel}: anchor not found once: {old[:70]!r}"
        s = s.replace(old, new)
    p.write_text(s)


patch("lib/playthrough_guard.php", [
    ("            if (!empty($GLOBALS['pgr_operation']) && str_contains($message,'pg_')) $GLOBALS['pgr_sql_failed'] = true;\n",
     "            pgr_note_sql_warning((string)$message,(string)$file,(int)$line);\n"),
    ("// Keep the recovery copy pinned after incomplete pruning, without stopping normal processing.\n",
     "// Item 110: record which SQL warning marks the rollback as failed (also when suppressed with @).\n"
     "function pgr_note_sql_warning(string $message, string $file, int $line): void {\n"
     "    if (empty($GLOBALS['pgr_operation']) || !str_contains($message,'pg_')) return;\n"
     "    $GLOBALS['pgr_sql_failed'] = true;\n"
     "    $GLOBALS['pgr_sql_warnings'][] = trim($message) . ' @ ' . basename($file) . ':' . $line;\n"
     "    error_log('Playthrough rollback SQL warning: ' . trim($message) . ' in ' . $file . ':' . $line);\n"
     "}\n\n"
     "// Item 110: only the rollback's own writes count, not warnings from the request before it.\n"
     "function pgr_begin_writes(): void {\n"
     "    if (empty($GLOBALS['pgr_operation'])) return;\n"
     "    $GLOBALS['pgr_sql_failed'] = false;\n"
     "    $GLOBALS['pgr_sql_warnings'] = [];\n"
     "}\n\n"
     "// Keep the recovery copy pinned after incomplete pruning, without stopping normal processing.\n"),
    ("function pgr_complete(bool $success = true): bool {\n",
     "function pgr_complete(bool $success = true, string $detail = ''): bool {\n"),
    ("        pgr_fail('A rollback write failed.');\n",
     "        $warnings = $GLOBALS['pgr_sql_warnings'] ?? [];\n"
     "        $why = trim($detail . (empty($warnings) ? '' : ' ' . count($warnings) . ' SQL warning(s), first: ' . str_replace([\"\\r\", \"\\n\"], ' ', (string)$warnings[0])));\n"
     "        pgr_fail('A rollback write failed.' . ($why === '' ? '' : ' ' . $why));\n"),
])

patch("lib/server_logger.php", [
    ("        if (!empty($GLOBALS['pgr_operation']) && str_contains($message, 'pg_')) $GLOBALS['pgr_sql_failed'] = true;\n",
     "        if (!empty($GLOBALS['pgr_operation']) && str_contains($message, 'pg_')) {\n"
     "            if (function_exists('pgr_note_sql_warning')) pgr_note_sql_warning($message, $file, $line);\n"
     "            else $GLOBALS['pgr_sql_failed'] = true;\n"
     "        }\n"),
])

patch("lib/playthrough_rollback.php", [
    ("        if ($playthroughId < 0) return ['triggered'=>false,'reason'=>'snapshot_failed'];\n"
     "        $pruneEnabled = stobePlaythroughPruneOnRollbackEnabled();\n",
     "        if ($playthroughId < 0) return ['triggered'=>false,'reason'=>'snapshot_failed'];\n"
     "        if (function_exists('pgr_begin_writes')) pgr_begin_writes(); // item 110\n"
     "        $pruneEnabled = stobePlaythroughPruneOnRollbackEnabled();\n"),
    ("        if (!pgr_complete(empty($restoreCounts['errors']) && empty($volatileStateCounts['errors']))) return ['triggered'=>false,'reason'=>'rollback_failed'];\n",
     "        $failDetail = (empty($restoreCounts['errors']) ? '' : 'NPC/relationship restore errors=' . intval($restoreCounts['errors']) . '.')\n"
     "            . (empty($volatileStateCounts['errors']) ? '' : ' Volatile state errors=' . intval($volatileStateCounts['errors']) . '.');\n"
     "        if (!pgr_complete(empty($restoreCounts['errors']) && empty($volatileStateCounts['errors']), trim($failDetail))) return ['triggered'=>false,'reason'=>'rollback_failed'];\n"),
])
print("ok")
