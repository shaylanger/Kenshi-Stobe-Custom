# Handoff: multi-feature test loop (coordinator) — state 2026-10-03 ~09:30

You are taking over as the **coordinator** from the previous session (context grew too big). Goal from Shay:
run every automatable test of STOBE, KenshiFP, Profession Gear (PG), the relationship system (REL) and the
automation harness (KAH) in combined Kenshi launches, log bugs, fix them via owner agents, rebuild,
reinstall, relaunch, retest — **don't stop until everything automatable passes**. Shay-only checks go to
`MASTER_TEST_PLAN.md` section 3, things needing a missing game setup to section 2. Commit + push often in
all repos (workspace, StobeServer, harness, PG; REL branch). Shay wants concise answers.

## Read first (in this order)
1. `CLAUDE.md` (workspace rules, test bed, tools, git identity rules).
2. `testing/README.md` (roles, loop, scenario file format).
3. `MASTER_TEST_PLAN.md` (index, status of every row, open bugs) + newest run logs `archive/test-run-2026-10-03-m13.md` … `m15.md`.
4. `C:\KenshiTestFixtures\FIXTURES.md`, `Kenshi-Automation-Harness/docs/COMMANDS.md`.

## Subagents: start them again (they died with the old session)
Use the Agent tool, `subagent_type: general-purpose`, `run_in_background: true`. Prompt templates:
`testing/AGENT_PROMPTS.md`. Four roles, each owns its code; only the coordinator runs Kenshi/installs:
- **STOBE fixer**: STOBE server + Stobe.dll + KenshiFP bugs (plan `STOBE_full_test_plan.md` section D, next item **91**).
- **PG agent**: `Kenshi-Profession-Gear-Progression` (status `INGAME_STATUS.md`, `ACTIVE_CONTEXT.md`, scenarios `tests/ingame/`, `RUN_ORDER.md`).
- **REL builder**: `/root/stobe-work/social-phase1/{server,native-workspace}` branch `feature/social-phase1`; resume file `isolated/relationships-phase1/REL_ACTIVE_CONTEXT.md`, deliveries `DELIVERY.md`. Rule: **never purge the social tables unless the coordinator says so.**
- **Harness helper**: `Kenshi-Automation-Harness` (build `cmd /d /c "call C:\KenshiModding\Kenshi-Automation-Harness\build.bat"`, tests the same way with `tests\run_tests.bat`).
Send each agent results with exact file paths; they reply with commits/hashes; you integrate + install.

## Installed right now (game may still be running the perf runner, see below)
| Component | Installed | Built, not installed |
|---|---|---|
| Stobe.dll | `49AFB0A7` (REL 1–7 + m8/m9/m11/m13 native + STOBE items to 88, debug removed) | - |
| KenshiFP.dll | `7043126D` (items to 90) | - |
| ProfessionGearProgression.dll | `10C19BAB` | **`7D80DBB3`** (job scaling on by default; then run `set_test_mode.ps1 -Mode Forced -Rules InGameTest` again) |
| AutomationHarness.dll | `7E711945` | **`F946C881`** (`#serial/index` handles, fps, produced, trade fixes, build/unbuild) |
| Server live | `/var/www/html/StobeServer` branch `stobe` = REL `50ec073` + STOBE fixes (SOCIAL_RELATIONSHIP_MODE=off) | - |
| StobeCustom.ini | `[SocialRelationships] Capture=` toggled by the perf runner (B=1, A=0); **set back as needed** | - |
| PG config | Forced + InGameTest (test mode) | after all PG testing: `set_test_mode.ps1 -Mode Normal -Rules Normal` |

## Frame-time windows (finished; not yet sent to the REL builder)
`C:\KenshiTestRuns\m15el\windows.txt` (10 min each after 60 s warm-up, kah-crafting, order B-A-B-A, relaunch between):
- B1 Capture=1: avg 57.1 fps, worst 348.7 ms, mem 5069 -> 4981 MB
- A1 Capture=0: avg 57.2 fps, worst 1983.7 ms, mem 4886 -> 4843 MB
- B2 Capture=1: avg 80.1 fps, worst 773.2 ms, mem 4878 -> 4866 MB
- A2 Capture=0: avg 106.6 fps, worst 402.8 ms, mem 4918 -> 4902 MB
Launch-to-launch variance is large (camera/scene), so pairwise B1/A1 ≈ equal, B2/A2 = 75 %. **First task: send these to the
REL builder** (ask for a verdict; maybe more pairs or a fixed camera position: the harness has no camera command yet).
Kenshi is left running on kah-crafting with Capture=0 (A2 was last) and REL mode off.

## Next steps (in order)
1. Send the frame windows above to the REL builder.
2. Install PG `7D80DBB3` + harness `F946C881` (Kenshi closed), `set_test_mode.ps1 -Mode Forced -Rules InGameTest`,
   Capture=1, fresh fixtures. Run PG `auto-home/pg-12-job-throughput.txt` (v5: expect B ≈ 1.5× A, C ≈ A on
   output_progress) → PG agent (rows 177, 331).
3. REL reruns with the new harness (scenarios use `#serial/index` now): p4-04, p6-01a + set-relation hook + p6-01b (keep),
   p7-02 (use `C:\KenshiTestRuns\m15\rel-batch.sh` as template: `fixture|file|mode|reload`), then send outputs to the REL builder.
4. Quick regression pass of the green PG files with the new harness (pg-01…08, pg-10/11, pg-21) since handles changed.
5. Remaining STOBE automatable rows: A13 (memory after a long fight), 56 (types), 16; everything else is in sections 2/3.
6. When all automatable rows are green: Capture=0, REL mode off, PG Normal mode, close Kenshi, final summary
   in `MASTER_TEST_PLAN.md` + a short report to Shay (what passed, what's in sections 2/3, balance note below).

## Runners and gotchas (learned the hard way)
- PG files: `OUT=/mnt/c/KenshiTestRuns/<run> bash /mnt/c/KenshiTestRuns/m2/run-pg.sh <fixture-save> <file>…` (reloads the fixture before each).
- REL batches: copy `C:\KenshiTestRuns\m15\rel-batch.sh`, edit the heredoc list (`fixture|file|mode|reload`); it sets the mode, runs, dumps inspect, handles p6-01a set-relation; ends with mode off.
- Run long WSL jobs with the Bash tool `run_in_background: true` + a `wsl.exe … bash -s <<'EOF' … EOF` heredoc. **Never** start jobs with `&` inside WSL (they die when wsl.exe exits). Add `< /dev/null` to every script call inside the heredoc (powershell.exe otherwise eats the rest of the heredoc).
- Git Bash mangles `/mnt/...` paths in `wsl.exe … bash /mnt/...` → always use the heredoc form.
- Use Monitor (until-loops) to watch outputs; foreground `sleep` > a few s is blocked.
- Native changes: REL delivers incremental patches against `/root/STOBE-src` (`git apply --check` then apply), STOBE fixer edits `/root/STOBE-src` directly; build with `tools/automation/build-stobe.ps1`; then snapshot changed `src/*` into `components/STOBE` with a heredoc loop and commit.
- REL server: `git fetch origin feature/social-phase1; git merge --ff-only …; git push origin HEAD:stobe` in the live tree; ss-merge sync = fixer task.
- Bug numbers: STOBE plan section D (fixer adds rows; next 91). Master plan section 4 mirrors them.
- Fixture reloads prune social rows newer than the save (by design): take REL inspect snapshots right after each scenario.
- GPU driver hang (TDR) once killed Kenshi (m3): not our mods.

## Balance / decisions for Shay (put in the final report)
- PG: job scaling now makes profession gear speed up real work (up to +25 % per affix) → balance rows 161–199 matter.
- REL: recommendation = shadow mode for normal play until SR25/SR32 and the perf windows close; enabled mode only for a supervised balance session on a fixture copy.
- Crash m3 = NVIDIA TDR (driver/TdrDelay is Shay's call).
