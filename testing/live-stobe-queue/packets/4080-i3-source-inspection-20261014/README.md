# 4080 i3 isolated session/marker source inspection packet

Status: **prepared only; not executed**. This is a gated, metadata-only inspection packet. It makes no game, save, queue, service, schema, or source changes. It must not be sent until a fresh exact-packet review and a row-specific Agent Validator CLEAR authorize this exact packet.

## Why it stops before source today

The current checkpoint says there has been no runtime contact since 05:52Z. The latest historical i3 notes name `127.0.0.1:18084` and `/tmp/stobe-standalone4080/site`, but the last captured process listing showed five same-argument PHP rows. That is not proof of one unique listener or of a test-only database binding. This packet requires fresh proof and aborts before opening any PHP source unless every gate passes.

## Exact approved transport shape

Use only `tools/automation/remote-bash-stdin-4080.ps1 -BodyPath <absolute body path>`. The body pins `RIG=4080`, `KAH_INSTANCE=3`, `KENSHI_DIR=/c/KenshiInst/3`, and the i3 harness. It must be reviewed byte-for-byte with this packet. Do not run the body's contents through SSH/WSL/KAH another way.

## Stage 0 gates (must all pass before PHP source is opened)

1. Confirm host `DESKTOP-NQQPA73` and the explicit i3 route variables. Canonicalize `/c/KenshiInst/3` and the exact INI path; require each resolved path to equal its expected literal path, preventing symlink/junction ancestors from redirecting the read to another install.
2. Read only `ServerHost` and `ServerPort` from `/c/KenshiInst/3/RE_Kenshi/mods/Stobe/StobeCustom.ini`; count every active assignment and require exactly one well-formed assignment each with values `127.0.0.1` / `18084`. Malformed or annotated assignments abort.
3. Require exactly one socket listener PID on loopback port 18084. Require that PID's argument vector to be exactly the expected `php -S 127.0.0.1:18084 -t /tmp/stobe-standalone4080/site`, with no duplicate same-argument PHP process. Canonicalize the document root and require exactly `/tmp/stobe-standalone4080/site`.
4. Read only allowlisted process metadata (`STOBE_DB_HOST`, `STOBE_DB_NAME`, and `PGDATA`) and require socket `/tmp/stobe-standalone4080/socket`, database `stobe_standalone4080_test`, and data directory `/tmp/stobe-standalone4080/pgdata`. This proves only that the listener process carries expected test-lane metadata; it does **not** prove its code uses that DSN or that its live connection points to that database. No full process-environment dump, `.env` read, credentials, tokens, DB query, or DB contents.
5. Any absent, duplicate, malformed, non-loopback, shared, redirected, or non-test-only evidence emits only `RESULT 4080-I3-SOURCE-INSPECT ABORT <fixed reason>` and exits before any PHP file is opened.

The DB names and roots above come from the historical isolated backend receipt; they are expected values, not current proof. If the exact allowlisted metadata is not present in the PHP process environment, the packet aborts. Do not broaden the variables read or infer values from a health response.

## Stage 1 source whitelist

Only after Stage 0 passes, require every path component to be non-symlinked under the already-canonical document root, hash the bytes, and inspect these files only:

- `lib/playthrough_preferences.php` — historical `ptp_connect()` definition.
- `lib/playthrough_retention.php` — historical `ptr_read()` definition and the session-store query.
- `playthrough_session.php` — session endpoint/writer candidate.

If any path is missing, stop with `ABORT fixed_file_missing_or_redirected`. Do not recursively search, read includes, inspect logs, or expand the whitelist in the same execution.

Output only SHA-256 per whitelisted file, exact basename, byte length, line numbers, allowlisted schema field names (`campaign_id`, `client_id`, `character_id`, `load_id`, `timeline_epoch`, `native_session_id`, `gamets`, `status`, `player_name`), and fixed lexical-presence booleans for expected symbol names, DB-setting names, table name, generation/manager marker names, lock terms, atomic-rename terms, and transaction terms. These booleans are **not semantic proof**: comments, unrelated code, or delegated includes can create false positives. Do not print function names, source lines, SQL text, arbitrary string literals, raw session IDs, tokens, credentials, logs, or database records. Run a secret-pattern scan over all three source buffers before emitting any Stage 1 result; if it flags a possible secret, emit only `ABORT possible-secret-detected`.

No result may label the backend private/isolated based only on process environment or directory names. The packet always ends `INCOMPLETE semantics=not-proven`; it cannot prove DB connection binding, marker read/write behavior, include dependencies, or shared-lease atomicity. It is only a safe source inventory. A later packet would need an exact allowlist and stronger analysis before those semantic claims can be made.

## Local synthetic tests

`gate_selftest.py` is a pure local test of the Stage 0 decision model, not the shell body or transport wrapper. It uses synthetic values only and has no subprocess, filesystem, network, SSH, WSL, KAH, database, or rig access. Required cases: all-exact model pass; wrong host/route; non-loopback or duplicate INI; zero/multiple listener PIDs; extra PHP process; document-root redirection; wrong DB name; shared PG root; missing metadata; and explicit assertion that a rejected model case has `source_opened=false`.
