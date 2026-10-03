-- Item 101: repair core_npc_master rows whose extended_data / metadata are JSON arrays ('[]', '[{}]').
-- Backup first (table item101_npc_json_backup keeps id, name and both old values), then turn every non-object
-- value into an object: objects inside a list are merged, anything else becomes '{}'.
-- Run: sudo -u postgres psql -d stobe -v ON_ERROR_STOP=1 -f item101_repair_npc_json.sql
BEGIN;
CREATE TABLE IF NOT EXISTS item101_npc_json_backup AS
  SELECT id, name, extended_data, metadata, NOW() AS saved_at FROM core_npc_master WHERE false;
INSERT INTO item101_npc_json_backup
  SELECT id, name, extended_data, metadata, NOW() FROM core_npc_master
   WHERE jsonb_typeof(extended_data) = 'array' OR jsonb_typeof(metadata) = 'array';
UPDATE core_npc_master m SET extended_data = COALESCE(
    (SELECT jsonb_object_agg(k, v) FROM jsonb_array_elements(m.extended_data) e(el), jsonb_each(CASE WHEN jsonb_typeof(el) = 'object' THEN el ELSE '{}'::jsonb END) kv(k, v)),
    '{}'::jsonb)
 WHERE jsonb_typeof(m.extended_data) = 'array';
UPDATE core_npc_master m SET metadata = COALESCE(
    (SELECT jsonb_object_agg(k, v) FROM jsonb_array_elements(m.metadata) e(el), jsonb_each(CASE WHEN jsonb_typeof(el) = 'object' THEN el ELSE '{}'::jsonb END) kv(k, v)),
    '{}'::jsonb)
 WHERE jsonb_typeof(m.metadata) = 'array';
SELECT (SELECT count(*) FROM item101_npc_json_backup) AS backed_up,
       (SELECT count(*) FROM core_npc_master WHERE jsonb_typeof(extended_data) <> 'object') AS ext_left,
       (SELECT count(*) FROM core_npc_master WHERE jsonb_typeof(metadata) <> 'object') AS meta_left;
COMMIT;
