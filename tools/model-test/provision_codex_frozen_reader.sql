-- STAGED ONLY. Review before an administrator runs this against stobe_frozen.
-- Never run against live database `stobe`. This intentionally changes only
-- frozen DB role metadata and can be applied once when provisioning the isolated
-- investigation environment; no agent should run it during benchmark cells.
\set ON_ERROR_STOP on
\getenv reader_password CODEX_FROZEN_READER_PASSWORD
\if :{?reader_password}
\else
  \echo 'CODEX_FROZEN_READER_PASSWORD must be set in the administrator environment'
  \quit 2
\endif

BEGIN;
DO $target_check$
BEGIN
  IF current_database() <> 'stobe_frozen' THEN
    RAISE EXCEPTION 'refusing to provision outside stobe_frozen';
  END IF;
END
$target_check$;
DO $no_foreign_tables$
BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_foreign_table
  ) THEN
    RAISE EXCEPTION 'foreign tables are not permitted in the frozen read schemas';
  END IF;
END
$no_foreign_tables$;
CREATE ROLE codex_frozen_reader LOGIN PASSWORD :'reader_password'
  NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS NOINHERIT;
ALTER ROLE codex_frozen_reader
  SET default_transaction_read_only = on;
ALTER ROLE codex_frozen_reader
  SET statement_timeout = '5s';
ALTER ROLE codex_frozen_reader
  SET search_path = pg_catalog, public;
GRANT CONNECT ON DATABASE stobe_frozen TO codex_frozen_reader;
REVOKE ALL ON SCHEMA public FROM codex_frozen_reader;
GRANT USAGE ON SCHEMA public TO codex_frozen_reader;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO codex_frozen_reader;
GRANT USAGE ON SCHEMA stobe_meta TO codex_frozen_reader;
GRANT SELECT ON ALL TABLES IN SCHEMA stobe_meta TO codex_frozen_reader;

DO $read_only_check$
BEGIN
  IF has_database_privilege('codex_frozen_reader', 'stobe_frozen', 'CREATE')
     OR has_database_privilege('codex_frozen_reader', 'stobe_frozen', 'TEMP')
     OR has_schema_privilege('codex_frozen_reader', 'public', 'CREATE')
     OR has_schema_privilege('codex_frozen_reader', 'stobe_meta', 'CREATE')
     OR EXISTS (
       SELECT 1
       FROM pg_class c
       JOIN pg_namespace n ON n.oid = c.relnamespace
       WHERE n.nspname IN ('public', 'stobe_meta')
         AND c.relkind IN ('r', 'p', 'v', 'm', 'f')
         AND (
           has_table_privilege('codex_frozen_reader', format('%I.%I', n.nspname, c.relname), 'INSERT')
           OR has_table_privilege('codex_frozen_reader', format('%I.%I', n.nspname, c.relname), 'UPDATE')
           OR has_table_privilege('codex_frozen_reader', format('%I.%I', n.nspname, c.relname), 'DELETE')
           OR has_table_privilege('codex_frozen_reader', format('%I.%I', n.nspname, c.relname), 'TRUNCATE')
           OR has_table_privilege('codex_frozen_reader', format('%I.%I', n.nspname, c.relname), 'REFERENCES')
           OR has_table_privilege('codex_frozen_reader', format('%I.%I', n.nspname, c.relname), 'TRIGGER')
         )
     ) THEN
    RAISE EXCEPTION 'reader inherited write-capable database, schema, or relation privileges';
  END IF;
END
$read_only_check$;

COMMIT;
