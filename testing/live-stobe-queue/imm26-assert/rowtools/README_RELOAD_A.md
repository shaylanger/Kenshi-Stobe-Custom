# Save+load resume rows, set A (imm26-reloadrows-A / A2)

Shipped offline-tested only (`bash rowtools/reload-selftest.sh` -> `SELFTEST RELOAD ALL PASS 60/60`); no lane or Kenshi was touched. First live run: `--dry` first, then one row. Set B (reloaddefs_b.sh, reloadrun-b.sh) is a different agent's and has its own files.

## Use
```
bash testing/live-stobe-queue/imm26-assert/rowtools/reload-run.sh <ROW> <lane> [--save S] [--no-reload] [--dry] [--allow-retry "why"]
        [--complete] [--spawn "<harness body>"] [--offer T] [--accept T] [--kind Hunt|ClearGroup] [--alt P] [--dest/--gate/--trap trip knobs]
bash testing/live-stobe-queue/imm26-assert/rowtools/reload-cycle.sh <lane> [save-name] [near|far]   # the bare save + load + wait-world verb
```
ROW = 26-d 26-dx 26-e 26-f 24-c 23-e 27-a 08-e 20-d. Output: `RECORDS <row> <file> ...` lines (first non-empty activity/agreement dump), then ONE `RESULT <row> PASS|FAIL|SETUP-FAIL|GATED ...` line; exit 0/1/2/3/4 as go-row.sh. `reload-run.sh` first reloads the lane's ready save (5090-i3 `kah-imm26-5090-ready`, 5090-i4 `kah-imm26-i4-trip2`, any other lane needs `--save`), then preflight, the row, `reloadcheck_a.py`.

No edits to `rowdefs.sh` / `tripdefs.sh` / `rowcheck.py`: `reload-run.sh` sources `reloaddefs_a.sh` after `go-row.sh` and sets `PY=reload-py.sh`, which redirects `rowcheck.py <set-A row>` to `reloadcheck_a.py` (everything else passes through). To load the rows through `go-row.sh` / `go-batch.sh` directly the owner of rowdefs.sh would add one source line for `reloaddefs_a.sh` and a try-import hook in rowcheck.py (not applied).

## Rows
| Row | What it does | Verdict checks (reloadcheck_a.py) |
|---|---|---|
| 26-d | spawn goats, offer + accept a Hunt, save+load (`rw_save_load`), re-spawn goats, "Are we still on that job?" (`--complete`: wait for the hand-over) | old record `superseded` + `resume.continuedAs`; NEW id chained via `resume.of`; new world epoch; accepted; resume.state resumed, count 1; same kind/resource/qty; one active record; grant re-emitted in the outbox; no `start rejected`; with `--complete` completed |
| 26-dx | as 26-d plus "Cancel that." before the save | cancelled stays cancelled, no continuation, no active record, no new grant |
| 26-e | offer only (proposed), save+load, offer again, "Yes" | proposal survives, re-bound to the new world (same id), no orphan in the old world, "Yes" after the re-propose accepts |
| 26-f | as 26-d with ClearGroup (bandit group fixture; camp via `--offer/--spawn`) | as 26-d + agreedTargets / campZone identical |
| 24-c | region plan -> area trip ACCEPTED (needs 24-b state), save+load, "Where were we going?", "I'm right behind you." | resume chain, `regional_goal` kept, one post-load OWNED_TRAVEL, MOVE_CUS_ORDERED, destination within 0.5 |
| 23-e | "Follow me." (legacy FOLLOW), Shay teleported 80 u away, speed 3 before and after the load | FOLLOW_TICK after load, no FOLLOW_EXPIRED / stale hand, follower closes the distance |
| 27-a | `contract-bodyguard <npc> Shay hours 24 own`, chase before and after the load | BODYGUARD present after load, follower closes the distance |
| 08-e | open follow-up topic, save+load, natural bored ticks (needs BORED_EVENT_CHANCE=100 on the backend) | topic survives, exactly one `followup:<id>:1` claim, none `:2`, ask_count 1 |
| 20-d | accepted trip, change offered, save+load, bare "Yes." | pending_change names the old agreement before and after; "Yes" ends/replaces the old row; pending_change cleared |

Server behaviour (wpR1/wpR3 deploy notes): the continuation gets a NEW agreement id (DLL revokes ids on load), chained via `resume.of`; a resumed proposal is re-bound in place and needs a re-PROPOSE; resume fires on a chat turn with that actor while the target is observed (so the fixtures are re-spawned right before the post-load say); caps 3 resumes / 7200 game s. Work goals after an OLDER save are dropped by design (bug 83): no row loads an older save; no work-goal row exists (no harness verb creates a work goal). 23-e / 27-a FAIL = the feature is lost on load (native fix plan: `agents/out/imm26-wpR3/latest.md` section 3).

## Known live blockers
26-d / 26-dx / 26-f (and the last leg of 26-e): the 26-a accept dies on `ACTIVITY start rejected: requester_now_hostile` -> SETUP-FAIL "known blocker 26-a". 26-f: no ClearGroup/camp offer recipe (14-c/14-d). 24-c: SETUP-FAIL until a `route_ready` region trip exists (24-b). 08-e: SETUP-FAIL when BORED_EVENT_CHANCE is not 100 (the checker never sets it) or no tick claims within RW_TICK_CHUNKS.

## Env knobs
`RW_KIND RW_OFFER RW_ACCEPT RW_RESUME_SAY RW_SPAWN_CMD RW_COMPLETE RW_HUNT_WAIT(180) RW_AWAY(80) RW_CHASE_S(30) RW_BG_ARGS("hours 24 own") RW_FU_SAY RW_ADV(120) RW_TICK_CHUNKS(4) RW_ALT RW_20D_RESUME_FIRST RW_SAY_WAIT(8) RW_SAVE_NAME`. Gotcha fixed in A2: the default offer/accept wording lives in `RW_OFFER_DEF` / `RW_ACCEPT_DEF` because bash 5.2 reads an apostrophe inside `"${VAR:-...}"` as a quote.

## Offline self-test
`reload-selftest.sh` = reloadfake.py (-> tripfake.py -> fakelane.py) + reloadscen.py (30 scenarios). Every defect scenario asserts the EXACT set of failing checks (each assertion fails alone), plus recipe statements (activity tables cleaned, fixtures spawned, save before load, env overrides) and CLI runs of `reload-run.sh` / `reload-cycle.sh`.

## 27-a status form and 08-e recipe (imm26-rowfix-reload 2026-10-15)
- 27-a: the harness parses `contract-bodyguard` modes from field 3, so the status query is `contract-bodyguard <npc> Shay status` (`<npc> status` made "status" the HIRER: `ERROR: no character named: status`); an `@player` retry follows when it still errors. `bg_set.txt` `has_contract=1` counts as pre-load proof; when the status query is unavailable after the load, `order_present_after_load` falls back to the post-load chase (the check detail says so). Scenarios `27a-statuserr` / `27a-statuserr-lost`.
- 08-e: quiet scene (`rw_prep` tr_quiet) + the NPC sheathed; after the load re-quiet, sheathe, ONE chat line to the NPC (`RW_08E_POST_SAY`), then `RW_TICK_CHUNKS` (default 8) chunks of `RW_ADV` (default 60) s. Evidence `cind_ticks.txt` / `cind_ticks_log.txt` / `srvlog_n0.txt` = NPC-speaker ticks in the lane server log since the load. SETUP-FAIL wording separates "no NPC-speaker tick (speaker lottery)" from "N NPC-speaker ticks, none claimed (server claim gate; Fix B, Shay decides)". BORED_EVENT_CHANCE is not the cause.
