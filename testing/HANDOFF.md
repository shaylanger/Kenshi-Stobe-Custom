# Current checkpoint: m40 (2026-10-05, before Shay's PC reboot)
Coordinator handoff: temp folder coordinator-handoff-m40.md (copy in handoff/). Run log: archive/test-run-2026-10-03-m22.md.
- **State:** all automated rows done (PG 250 PASS-live in m39). Kenshi closed, nothing running, game lock released, PG config Normal/Normal, 4080 idle, no subagents.
- **Open = Shay decisions D1-D8** in MASTER_TEST_PLAN.md section 2 ("Open Shay decisions"): farming gear too strong, medic saturation, perception flat, athletics short runs, crossbow outlier + lab50 controls, turret targeting, import crash (vanilla), pg-84 file drift (our to-do).
- **Graphics mods still OFF:** `bash C:/KenshiModding/tools/automation/gfx-mods.sh on` before playing.

# Previous checkpoint: m31 (2026-10-04 evening, after RAM upgrade to 48 GB)
Coordinator handoff: temp folder coordinator-handoff-m31.md (m26 has Shay decisions). Run log: archive/test-run-2026-10-03-m22.md.
- **5090:** PG operator subagent runs the 5090 PG queue (pgop HANDOFF-5090-operator-m32.md) and the 4080 queue; coordinator borrows the 5090 game for REL batch Q (list-q, after fixer m31: p7-04, p7-05, SR19 cage sub-check).
- **5090 after its own work (Shay, 2026-10-04):** don't stop; use it for PG testing too, alongside the 4080; the coordinator decides the split.
- **PG (m29):** BLOCKER: harness protect/health -> wounds factor 0.25, all PG balance data invalid. 5090 runner = 5090 PG operator subagent (game lock owner 5090-pg-operator): harness fix + live check, then gate 85-89/92(+fs), pg-89, pg-55; progress pgop/HANDOFF-5090-operator-m29.md. 4080: previous operator out of context (handoff pgop/HANDOFF-4080-operator-m29.md); a new one gets gate 52-54/80-84/90 + pg-51 once the harness fix is on the rig.
- **Memory:** mem-ab gfx A/B done (MEMORY_BASELINE_2026-10-04.md): HD textures off saves 2.6 GB, Dust/ReShade 0.6 GB.

## Test efficiency rules (Shay, 2026-10-04; full text in CLAUDE.md "Test efficiency")
- Mechanical rows = deterministic: inject the model reply (NEG_TEST_INJECT ...) before the logic under test; prove the injection fired + real game/server change; switches restored on exit. Live-model rows = a small separate batch (prompt -> intended reply).
- Setup checks before long tests (shared helpers): out dir, fixture, selected chars, live NPC names/handles, inventory, worker/bench/materials/research/power/job, game time advancing, raid protection. Bounded polls, specific SETUP FAIL reason, repair then rerun.
- PG: per-point provenance (build/config/fixture/skill/gear/setup/evidence); no stale captures; reuse only compatible points; block reruns when points aren't independently resettable; investigate flat data even with 0 script failures.
- After each batch: reconcile (passes out of the plans, evidence in run log), classify every non-pass, map bugs to confirmations, rerun only invalidated passes; report requirement IDs and scenarios separately.

## New standing rules (Shay, 2026-10-04; full text in CLAUDE.md "PG validation gate" and "RAM budget")
- PG: 3-point validation gate (low skill/no gear, high skill/no gear, low skill/gear) before any full matrix; mechanical pass and balance acceptance tracked separately; one gate line per profession; one runner per machine, recorded here.
- RAM: parakeet STT off unless a test needs voice; PocketTTS off unless a batch tests audio (after checking replies still work without it); WSL cap 8 GB; graphics-only mods (Dust, ReShade, HD textures if worth it) off for automated runs, with a restore command for Shay.
- Both rules applied (m29, commits 2574235, cbc7148, 558154d). Per-profession gate results go below this line when the operator reports.
- **PG gate lines (m35, 4080 matrix m35 + 5090 batch T; throughput per profession, gear = s50 +50% unless noted; mechanical = gear moves the stat; balance = Shay/balance pass):**
  - armour smithing: s10 0.024 / s90 0.054 / +50% gain +27.7% -> mechanical PASS, balance open
  - weapon smithing: s10 0.034 / s90 0.077 / +25.6% -> mechanical PASS, balance open
  - crossbow smithing: s10 0.0064 / s90 0.0147 / +99.6% (lab50 ctl 1.60 off) -> mechanical PASS, balance suspicious (gear far above others; recheck)
  - cooking: s10 0.127 / s90 0.287 / +23.6% -> mechanical PASS, balance open
  - farming: s10 0.364 / s90 0.728 / s25+50% 0.888 > s75, +108.7% -> mechanical PASS, balance FAIL row 206 (gear too strong)
  - robotics: s10 0.021 / s90 0.048 / +22.0% (lab50 ctl 0.84) -> mechanical PASS, balance open
  - science: s10 21.5 / s90 47.7 / +23.1% (lab50 ctl 0.75) -> mechanical PASS, balance open
  - engineering: s10 2.90 / s90 8.39 / +25.3% -> mechanical PASS, balance open
  - medic: s10 6.37 / s90 18.3 / +0.1% (Standard kit saturates by Medic 50) -> mechanical flat, Shay decision "medic curve saturation"
  - assassination: s10 43.8 / s90 180 / s25+50% 92.7 / +36.7% -> mechanical PASS, balance open
  - lockpicking: s10 0.117 / s90 0.90 / s25+50% 0.483 / +70.0% -> mechanical PASS, balance open (lock level <= skill reads flat 0.9)
  - thievery: s10 0.11 / s90 0.99 / s25+50% 0.41 / +50.0% -> mechanical PASS, balance open
  - stealth: s10 0.70 / s90 1.30 / +16.7% -> mechanical PASS, balance open
  - swimming: s10 2.38 / s90 30.9 / +24.8% -> mechanical PASS, balance open
  - athletics (5090 batch T pg-85, swim 300 m s, lower = faster): s10 4.3 / s90 3.0 / own50 ~2.8 / lab50 ctl 3.5 -> mechanical PASS, balance open
  - turrets (pg-55, batch W, needs harness `turret ... aim`: the turret never targets a dummy by itself): skill01 0.10 / 0.90 / 0.15, dummy worst 5% / -27% KO / -58% KO -> mechanical PASS, balance open (n=1)
  - perception: not run (pending decision "perception ignored by 1.0.65 detection")
---
# Handoff: multi-feature test loop (coordinator) — state 2026-10-03 ~17:55 (run m18 running)

## Goal (Shay, 2026-10-03, firm): build, test, validate, fix EVERYTHING; only stop for decisions or when done
- **Standing rule (Shay, direct):** if testing or validating ANY row needs a handler, harness command, test switch,
  hook, log line, driver or other code that doesn't exist yet, BUILD IT (yourself or via a subagent), then run the
  test. Never report a row as blocked / "needs setup" / "missing code". Don't stop to ask; start the to-do list below now.
- "Missing code / needs a driver / needs a handler / needs setup" is never a blocker: **build it** (harness commands,
  test switches, drivers, mod logic), using subagents in parallel (PG agent, STOBE fixer, REL builder, harness helper,
  4080 rig operator). Memory `coordinator-builds-everything`.
- Loop: test -> log bugs -> fix -> build -> install -> retest until every testable row passes, then close Kenshi and
  give Shay ONE final summary.
- **How (Shay, 2026-10-03):** batch the game runs: as many tests as possible per launch, fix + build all bugs found
  together, restart once to install and retest; start batches detached and check in every 5 min with
  `batch-health.sh <out>` (one line: OK = keep waiting, STALL = act now, DONE = read SUMMARY.txt).
  At most 2 standing subagents: 1 fixer + 1 4080 rig operator; a third only for a big build, stopped when done.
- **Token-light tests (Shay, 2026-10-03):** tokens are the priority, so make the tests report compactly instead of
  reading logs: every wrapper/scenario prints one `RESULT <row> PASS|FAIL <key evidence>` line per row (+ log path on
  FAIL); read only `grep ^RESULT` output, open logs only for FAILs. Retrofit the line into each wrapper as you next touch
  it (shared helper in `stobe-fight-lib.sh`). Group rows by save so each launch covers as many as possible; batch fixes.
- **Batch tooling (Shay, 2026-10-03, items 2/4/5/7 of the token plan):** batches run with
  `tools/automation/run-batch.sh [--launch <save>] [--stop] <list> <out>` (WSL, detached; list = `name | save |
  player | mate | timeout | command`, header has examples; `home` and `kah-fullbase` setup built in). Every 5 min a
  background `sleep 300; bash tools/automation/batch-health.sh <out>`; on DONE read `<out>/SUMMARY.txt` only. Each FAIL carries `excerpt=` (from `batch-excerpts.sh`); open that,
  full logs only if needed. Fixer gets a ticket (template in `testing/AGENT_PROMPTS.md`). After every server fix,
  `stobe-tests` must pass before the next game batch. The runner was tested offline with stubs only; its first real
  batch is the live check (if it misbehaves, fix the runner, don't fall back to hand-written batch scripts).
- **Shay's decisions (typed by Shay, 2026-10-03), build + test them:** item 104 sell-side max drop = **90 %** (a hater
  only buys if they rip you off hugely); item 100 = **option (b)**: reputation and relationship history follow the
  squad character who is speaking, not the persona "Shay"; **B 55 decided** (final spec = `STOBE_full_test_plan.md`
  section E items 1-8, commit 6391c32): retire R4, use the REL combat rules with: event-based forgiveness (each fight
  its own grudge; up to -28 fades over ~14 game days, KO or worse never fades by itself; no relationship-value cutoff;
  a setting), kept deal wins back variable 0..1/3, consensual sparring free, no chat gains for 1 game day, only fights
  that matter count, first fight leaves a permanent mark, **harsher penalties by her state when she wakes x closeness
  multiplier** (Friendly 1.3, Fond 2.0, Devoted 2.5, Bonded 3.0; floor -100), **treating her afterwards takes off a
  variable 15-30 %** (never positive); F 62 deferred; F 63 deferred until this master plan is done and all bugs are
  fixed/validated; STOBE A9 (TTS volume/fade) PASS (Shay tested). PG 256 stays deferred.
- **Git commits/pushes are allowed** (Shay added allow rules in `.claude/settings.local.json`): commit + push after every step.
- Confirmed by Shay directly (2026-10-03 ~18:00): this goal and the to-do list below are Shay's orders, also written
  into CLAUDE.md "Current state" and `MASTER_TEST_PLAN.md`.

## Read first
`CLAUDE.md`, `testing/README.md`, `MASTER_TEST_PLAN.md`, run log `archive/test-run-2026-10-03-m18.md` (+ m17),
`C:\KenshiTestFixtures\FIXTURES.md`, harness `docs/COMMANDS.md`, local `handoff/4080-test-rig.md`, `testing/AGENT_PROMPTS.md`.

## State now (2026-10-03 ~20:00, m18 coordinator closed: new session takes over here)
- 5090: Kenshi running; m18 batch `C:\KenshiTestRuns\m18atch.sh` running detached in WSL (log `batch.log`, outputs `out\`;
  done so far: 21/18/generic/16 Full-Base, Squin 14/15; next: 61, rel-enslaved, rel-theft, trading modes, A8, 18/21/22 home,
  pg.sh). After it: `C:\KenshiTestRuns\m18ollowup.sh` (21/18/generic/16 Full-Base reruns with the fixes). Results so far
  and analysis: `archive/test-run-2026-10-03-m18.md`.
- Installed: Stobe 478D8AA6, KenshiFP 5719BEA5, harness F6A3FC31, PG D7A60E49 (Forced + InGameTest), Capture=1.
- **Built, install at the next restart** (Kenshi closed, `install-dll.ps1`): Stobe E45BFB0E (shop price hook 103/104 incl.
  ShopTrader sellers; still -75 % sell side), KenshiFP 6E0A031E (items 111 + 112), harness 33087EDE (repo main 8116c46:
  KAH 2/3, KAH 22b, KAH 24 balance commands; check KAH 3 commit 7778508 is in it), PG 266C68F5 (only for row 250).
- Server live (all pushed): item 100 (b) (0c6ed3e: deal reputation + relationship outcome on the deal's character; rerun 18/21/17 Full-Base + an auto-home deal), item 110 (e605768), items 107, 18 markers, 108, 109, 111, 113, 90 (e3b9cc3), A12 refusal (01a7c4e), item 29 (cd5a316),
  test switches NEG_TEST_INJECT / NEG_TEST_FORCE_INITIATIVE (2b2b52d).
- **No subagents are running** (the m18 coordinator session was closed by Shay ~20:00; all its subagents ended with it).
- **First jobs for the new coordinator (Shay's direct orders):**
  1. **Item 104 sell side -90 %: START NOW.** Never started (the old session's hand-off was blocked). The built Stobe
     E45BFB0E still has -75 %. Scope: C++ ShopPricing + tests, server deal price + relationship_pricing endpoint,
     wrapper python copy; build, install, test in game.
  2. **B 55 fight rules: build them** (REL builder; it was never built): spec = STOBE plan section E items 1-8 (commit
     6391c32, supersedes d6abec1), continue from local `handoff/rel-b55-fights-build.md` + draft
     `pending-fixes/b55_social_fights.php`. Build + unit tests + in-game rows.
  3. Item 100 (b) is live (server 0c6ed3e): test it (rerun 18/21/17 Full-Base + an auto-home deal).

## Next steps
1. When m18 batch + followup end: stop Kenshi, install the builds above, relaunch.
2. Run: item 107/18/109/16 Full-Base reruns (followup.sh if not done), Squin 14/A3 + 15 approve/decline (items 111-113),
   `STOBE-102-104-relationship-trading.sh shop-prices|shop-floor|shop-block` (+ `REAL_TRADER=1`), section C wrappers
   `STOBE-C*.sh` + `STOBE-20-refuse-after-handover.sh` + `STOBE-A11-A12-heal-deal.sh a12` (auto-home, `scenarios.sh fresh`
   first), `C:\KenshiTestRuns\scenarios\kah-2-3-msg-trade.txt` (kah-trader copy), PG launch 5 balance files + pg-56 (PG 89)
   on Full-Base (`RUN_ORDER.md`), PG 151-152 (pg-15 on/off, steps in PG RUN_ORDER), KAH 5, REL SR18/19 Full-Base.
3. PG fit finding (pg-14): +25 % Labouring gear beats the whole skill range (x1.26): design principle 4 -> **Shay
   decided (2026-10-03): wait.** No change to Labouring (or any profession) until the balance data for every profession
   is in; then present the whole picture to Shay (option discussed: scale the gear bonus by skill).

## To-do (all of it, in parallel where possible)
1. **PG balance driver, all rows 161-199** (PG agent): extend `Kenshi-Profession-Gear-Progression/tools/balance_driver.py`
   to every profession; add the measurement commands the harder rows need (185 engineering build/repair, 191 medic
   healing, 194 water route, 195-199 detection/lock/target) to the harness; run them; then fit rows 200-210
   (`tools/analyze_balance.py`).
2. **Stobe.dll shop-window relationship pricing hook** (items 103/104: shop prices by relationship, buy/sell floor,
   -80 trade block): `pending-fixes/apply_shop_price_hook.py`, interface `pending-fixes/relationship-pricing-interface.md`,
   endpoint `pending-fixes/relationship_pricing_endpoint.php`. Build, install, test in game.
3. **REL SR09/13/14**: steal driver (harness KAH 22) + theft-caught signal; test.
4. **REL SR07** limb loss: harness `sever`/damage; test.
5. **Item 90** (her words don't match her action): fix + test.
6. **PG 250**: make a ruin/loot fixture (harness spawn/stash or a real ruin) and test.
7. **Section C (25-37, 44, 45, 47, 49, 51), STOBE 20, A12**: test switches/forcing like `NEG_TEST_FORCE_BETRAYAL`, then test.
8. **Confirm fixed-but-unconfirmed bugs in game**: 70, 86, 94, 96, 97, 99, 101, 105, 106, 107, STOBE 18 Full-Base.
9. Rest of the m18 batch results -> bugs -> fixes -> retest. 4080 rows.
11. **KAH 5** `power <battery> charge` on a real Battery Bank (Full-Base): coordinator, next Full-Base launch.
12. **PG 89** = `pg-56-critical-craft` (pg.sh runs only pg-50..55): add to the PG run.
13. **PG 151-152** = pg-15 on launch 3 with PG disabled, compared with launch 1 (same machine).
14. **REL SR30** (recruitment join never tried) and **SR06** (victim turns hostile): force them like section C (REL builder).
15. **KAH 2** (no vanilla game message seen by `messages`) and **KAH 3** (shop-barrel trade names "Old Wooden Barrel",
    trader's cats unchanged): fix + verify (harness).
16. **REL SR18/19 on Full-Base** (bed/cage rescue, plan 1f).
19. FIXED (harness 8BF347BF, m19; 4080 reruns by PG agent) **Harness bugs from the 4080 (m18 run log): fix + retest the rows:** `walktime` times out when the character
    stops 4-9 m short (PG 254 FAIL); `newgame` hangs in loading, Kenshi exits ~9 min later (PG 132/133/240 FAIL);
    `pickup` treats No Faction drops as owned (Commands.cpp ~1301); kah.py `@log` path with spaces; `packput` into a
    nested pack (PG 120 nested case).
20. DONE (StobeServer 538bf00, m19) **Server side finding (m18, item 110):** concurrent rollback requests at a load run without the advisory lock
    ("rollback lock busy"): fix + check php_error.log after older-save loads.
21. DONE (ff51538, m19) **Master plan refresh:** sections 2 and 4 of `MASTER_TEST_PLAN.md` are stale (rows built/moved since m16): update them.
17. DONE (83f579c, planning session): prune `STOBE_full_test_plan.md`.
18. (was 10) End: Capture=0, REL mode off, PG `set_test_mode.ps1 -Mode Normal -Rules Normal`, close Kenshi, one final summary
    (with the Shay decisions above).

## Gotchas
- Full-Base world raids: `fullbase-guard.sh` after each Full-Base load; it protects both squad members, so wrappers that
  KO the mate must turn protect off first (park_malzin does since m18).
- `stobe-fight-lib.sh` is sourced by every wrapper: `bash -n` it after any edit (run via WSL with `MSYS_NO_PATHCONV=1`).
- Long WSL batches: start detached (`setsid nohup bash … &` inside WSL); Bash `run_in_background` dies at 10 min.
- Don't run Windows `python3` in Git Bash for repo scripts that need WSL paths; use WSL python3.
- **Item 100 (b) reputation migration: skipped (Shay, 2026-10-03: test data).** The 2 Beaks BREACHED_NPC counts on
  the "shay" row stay; `npc_broken` is only recorded, never read by the server. Don't run
  `pending-fixes/item100b_reputation_migration.sh`.
- **REL builder (finished, m18):** server cb3bc44 + 2fbd947 live (theft_caught SR13/14, SR09 witness, switches
  SOCIAL_TEST_FORCE_FIRST_STRIKE / SOCIAL_TEST_FORCE_JOIN_ATTEMPT); harness e8b4688 (`drop ... owned`, KAH 22b; worktree
  `C:\KenshiModding\kah-rel-wt`, remove after building main). Native patch `pending-fixes/rel_theft_caught_native.py`
  (apply to /root/STOBE-src, build; private build 018496B9 OK). Run after installing: `bash
  /var/www/html/StobeServer/tests/social_relationship/ingame/rel-m18.sh <outdir>` (auto-home, Capture=1).
  **B 55 not built:** continue from local `handoff/rel-b55-fights-build.md` + draft `pending-fixes/b55_social_fights.php`.

## Session end (coordinator m18, ~19:45)
- The m18 batch keeps running detached in WSL (it doesn't need this session): check `C:\KenshiTestRuns\m18\batch.log`
  (finished when its last line is `HH:MM batch done`; rel-theft also prints "batch done, mode off", which is NOT the end), then run `followup.sh` the same way (`setsid nohup bash … &` in WSL). Kenshi stays running on
  the 5090 (lock owner `coordinator`).
- All subagents ended with the session. The 4080 rig operator never reported: check the 4080 (`ctl.ps1 status`, lock
  `rig4080`, results `C:\KenshiTestRuns\m18-4080\` there), stop its game and delete its kah-* copies if left.
- Unanalysed results (logged in the m18 run log): rel-theft p3-05b 31/2,
  probe-theft-seen 19/3.
