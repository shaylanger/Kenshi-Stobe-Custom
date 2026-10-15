# imm26 composed server patch: lane installs (2026-10-15, imm26-install-server)

Patch: `compose.patch` (base `/root/imm26/base` + wpA..E + wpC1/C2 + travel fix; 78 php files linted per site).
Installer: `install-lane-site.sh <lane_root> <pgport> <db> [patch]` (refuses roots outside `/tmp/stobe-*`; env BASE/COMPOSE/COMPOSE_MANIFEST/XTRA for the 4080 where `/root/imm26` does not exist).
Never touched: `/var/www/html/StobeServer`, ss-merge, Shay's live install/DB, ports 80/443/8083/5432. No game was killed, no php backend restarted (php -S re-reads files per request; migrations ran via `php tools/bootstrap-database.php` with the lane env: tables `imm26_npc_principle`, `npc_ties`, `social_rumor`, `stobe_world_town` present in each lane DB, health `database_upgrade_required:false`).
Backups per site (in the lane root): `bak-pre-compose-20261015.tar.gz` (site minus portraits/voices/soundcache/log) and `bak-pre-compose-20261015.sql.gz` (pg_dump). Rollback = untar over `site/` + restore the sql into the lane DB.

| Site | Path | Result |
|---|---|---|
| 5090 i3 (18086, db stobe_imm26_5090) | `/tmp/stobe-imm26-5090/site` (WSL) | was base + travel fix; travel_companionship.php reset to base (the fix is inside compose), patched, lint 78 ok, identical to compose tree, health ok, imm26 libs load |
| 5090 i4 (18087, stobe_imm26_5090_i4) | `/tmp/stobe-imm26-5090-i4/site` | base-identical -> patched, lint 78 ok, identical to compose tree, health ok. (No fixture profile file edit was present on the 5090 i4 site.) |
| 5090 i5 (18088, stobe_imm26_5090_i5) | `/tmp/stobe-imm26-5090-i5/site` | base-identical -> patched, same checks, health ok |
| 4080 i3 (18084, stobe_standalone4080_test) | 4080 WSL `/tmp/stobe-standalone4080/site` | site was an OLDER snapshot of the live tree (14 files behind base: schema.sql, db_updates.php, chat_helper_functions, data_functions, negotiation_phase1, playthrough_switching, travel_companionship, playthrough_session, town_knowledge, 5 tests). Synced those 14 to base (`prep-4080.sh`, base tar copied to `C:\KenshiTestRuns\imm26-install`), then patched; lint 78 ok, sha256 manifest of compose tree matches (voices excluded), health ok |
| 4080 i4 (18085, stobe_standalone4080_i4_test) | 4080 WSL `/tmp/stobe-standalone4080-i4/site` | same as 4080 i3, plus lane-local `lib/test_provider_reply_fixture.php` (4080-i4 profile) preserved untouched; only that file differs from the compose manifest (expected) |

Side effect on the 4080 lane DBs (and all five): `bio_unique` migration deletes the bare-name `Tengu` bio rows, `stobe_world_town` table created (base behaviour, now also on the 4080).
Smoke: HTTP `health.php` (ok, schema ready, no upgrade required) + php CLI load of `imm26_plans/ties/knowledge/npc_availability` with each lane env; no chat/bundle was sent (operators may be mid-row; local model is 40-60 s per reply). 5090 lane `php_error.log` showed no new errors from the install.
Helper copies on the 4080: `C:\KenshiTestRuns\imm26-install\` (compose.patch, base-code.tgz, manifests, scripts); 5090 copy of the same dir exists too (safe to delete after the program).
