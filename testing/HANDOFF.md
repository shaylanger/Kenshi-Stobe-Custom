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
- **Shay's decisions (typed by Shay, 2026-10-03), build + test them:** item 104 sell-side max drop = **90 %** (a hater
  only buys if they rip you off hugely); item 100 = **option (b)**: reputation and relationship history follow the
  squad character who is speaking, not the persona "Shay"; **B 55 decided**: retire R4, use the REL combat rules plus
  the 6 additions in `STOBE_full_test_plan.md` section E (REL builder; forgiveness threshold is a setting, default
  "up to -28 fades over ~14 game days", Shay may still adjust it); F 62 deferred; F 63 deferred until this master
  plan is done and all bugs are fixed/validated; STOBE A9 (TTS volume/fade) PASS (Shay tested). PG 256 stays deferred.
- Confirmed by Shay directly (2026-10-03 ~18:00): this goal and the to-do list below are Shay's orders, also written
  into CLAUDE.md "Current state" and `MASTER_TEST_PLAN.md`.

## Read first
`CLAUDE.md`, `testing/README.md`, `MASTER_TEST_PLAN.md`, run log `archive/test-run-2026-10-03-m18.md` (+ m17),
`C:\KenshiTestFixtures\FIXTURES.md`, harness `docs/COMMANDS.md`, local `handoff/4080-test-rig.md`, `testing/AGENT_PROMPTS.md`.

## State now (2026-10-03 ~19:30, coordinator context full: new session takes over here)
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
- Subagents still running: REL builder (SR09/13/14, SR07, SR30/SR06 forcing, B 55 fight rules: spec = STOBE plan section E as of d6abec1, event-based forgiveness), item 100 (b) fixer,
  4080 rig operator (PG rows). They die with this session: check git logs + their repos.
- **Item 104 sell side -90 %: START NOW (Shay, 2026-10-03, direct order).** Not delegated yet because the permission
  checker blocked the hand-off message. Scope: C++ ShopPricing + tests, server deal price + relationship_pricing
  endpoint, wrapper python copy; build, install, test in game. If the hand-off is blocked again, the coordinator builds it itself.

## Next steps
1. When m18 batch + followup end: stop Kenshi, install the builds above, relaunch.
2. Run: item 107/18/109/16 Full-Base reruns (followup.sh if not done), Squin 14/A3 + 15 approve/decline (items 111-113),
   `STOBE-102-104-relationship-trading.sh shop-prices|shop-floor|shop-block` (+ `REAL_TRADER=1`), section C wrappers
   `STOBE-C*.sh` + `STOBE-20-refuse-after-handover.sh` + `STOBE-A11-A12-heal-deal.sh a12` (auto-home, `scenarios.sh fresh`
   first), `C:\KenshiTestRuns\scenarios\kah-2-3-msg-trade.txt` (kah-trader copy), PG launch 5 balance files + pg-56 (PG 89)
   on Full-Base (`RUN_ORDER.md`), PG 151-152 (pg-15 on/off, steps in PG RUN_ORDER), KAH 5, REL SR18/19 Full-Base.
3. PG fit finding (pg-14): +25 % Labouring gear beats the whole skill range (x1.26): design principle 4 -> Shay decision.

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
17. End: prune `STOBE_full_test_plan.md` (header + section D still list confirmed items 65-89 and old DLL hashes).
10. End: Capture=0, REL mode off, PG `set_test_mode.ps1 -Mode Normal -Rules Normal`, close Kenshi, one final summary
    (with the Shay decisions above).

## Gotchas
- Full-Base world raids: `fullbase-guard.sh` after each Full-Base load; it protects both squad members, so wrappers that
  KO the mate must turn protect off first (park_malzin does since m18).
- `stobe-fight-lib.sh` is sourced by every wrapper: `bash -n` it after any edit (run via WSL with `MSYS_NO_PATHCONV=1`).
- Long WSL batches: start detached (`setsid nohup bash … &` inside WSL); Bash `run_in_background` dies at 10 min.
- Don't run Windows `python3` in Git Bash for repo scripts that need WSL paths; use WSL python3.
- **Needs Shay (blocked for agents):** item 100 (b) reputation migration (moves today's 2 Beaks BREACHED_NPC counts off
  the "shay" row, backup first): `tr -d '\r' < /mnt/c/KenshiModding/pending-fixes/item100b_reputation_migration.sh | bash`
  in WSL. Optional; nothing is lost if it stays unrun.
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
- Unanalysed results (logged in the m18 run log): rel-enslaved p7-04 15/2, p7-05 21/1; rel-theft p3-05b 31/2,
  probe-theft-seen 19/3.
