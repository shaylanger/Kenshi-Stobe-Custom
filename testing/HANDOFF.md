# Current state (m50, 2026-10-06)
This file + CLAUDE.md are the whole state: there are no separate handoff files any more (deleted 2026-10-06). Any agent
starting here needs nothing else. Keep it current: update this section at every milestone, before a session ends.
Run logs: `archive/test-run-2026-10-06-m49.md` (m49), `archive/test-run-2026-10-06-m50.md` (m50, 4080 FP batches b27+). Open rows: `MASTER_TEST_PLAN.md`.

## Right now
- 5090: batch C running (`C:\KenshiTestRuns\m50-5090-c`, run-batch.sh; rows DRAWN = DW1-DW10 on Stobe 95B9D33A, mlife = M08 on
  KenshiFP ABEB8BF6). Health: `batch-health.sh /mnt/c/KenshiTestRuns/m50-5090-c/out`. Runner = coordinator.
- 4080: batch 36b (KenshiFP FC5041E8: life PASS 5/5, control rows running), then batch 37 on ABEB8BF6 (staged C:\KAH\fp\b4080-37.sh,
  start `C:\KAH\sb37.ps1` after `C:\KAH\inst.ps1 -Hash ABEB8BF6` with Kenshi stopped): controls rows (all incl. DOWN01) + mlife.
  Check `ssh 4080 powershell -File C:/KAH/w36b.ps1` / `w37.ps1`. Runner = coordinator, lock owner rig4080.
- 4080 desktop is locked (LogonUI): no window can be foreground, so KenshiFP frees the cursor. Test switch `fp_keys focus on|off`
  (fp-controls.sh uses it). 4080 Defender ML flagged KenshiFP 47D56C70 as Trojan:Win32/Bearfoos.B!ml (false positive, quarantined);
  probe every new DLL there first (copy to C:\KAH, Get-FileHash, wait 20 s, Test-Path).
- Gate 3 decided (Shay 2026-10-06): manual aim may beat the dice for now; R15/R16 stay. Nothing waiting on Shay.

## The mods and what each one owns (after the m49 decoupling)
- **Stobe.dll** (`/root/STOBE-src`, snapshot `components/STOBE`): chat/LLM bridge to the Stobe server, negotiation/deals,
  relationships (REL), NPC info panel, and since m49 ALL goal/action logic: work planner (production at benches), task goals
  (fetch, buy, guard, stock, repair, give item, bodyguard...), goal lifecycle + status/control files, goal panel UI, native
  actions (lookup, orders, movement, equip). Log `stobe_goals.log`. Works with KenshiFP absent (DC1-DC5).
- **KenshiFP.dll** (`/root/KenshiFP`, snapshot `components/KenshiFP`): first-person mode only: camera/head/eye, mouse and
  cursor, FP targeting, manual FP combat (ranged + melee adapters, OFF by default), FP harness commands.
- **Profession Gear (PG)** (own repo `Kenshi-Profession-Gear-Progression`): per-item affixes and profession gear bonuses.
- **Automation Harness** (own repo `Kenshi-Automation-Harness`): in-game test commands (`stobe-auto`).
- **Stobe server** (WSL `/var/www/html/StobeServer`, branch `stobe`): LLM prompts, deal engine, relationship evaluation.

## Builds installed
- 5090: Stobe 95B9D33A (drawn-weapon reactions), KenshiFP ABEB8BF6, PG BAFB8C31 (Normal), harness C6969009; server live `stobe` 055e0c5.
- 4080: KenshiFP FC5041E8 (ABEB8BF6 next), PG BAFB8C31, harness C6969009 (no Stobe there). Rig notes: local `handoff/4080-test-rig.md`.

## Status per mod
- **STOBE / REL:** all automated rows PASS; open items only in `STOBE_full_test_plan.md` (D: fixed, awaiting in-game
  confirmation; E/F: design + next big feature, item 63 = pick the next big feature with Shay).
- **KenshiFP decoupling:** done m49 (Stobe 9d99f36, KenshiFP f94b1d5); DC1-DC7, 89, 14-A3, generic-fb, 16-fb 55/55, A8 PASS.
- **FP combat:** on FE26573F R07, R08 (8/9), R09, R11, R13, FP-EYE PASS both rigs, S01 (= DC1-DC5). Passed on older builds,
  to reconfirm in one batch per rig: R10, R12 (UI/KO/SWAP/SPEED/LOAD), R14-R16, M08, S03. Never passed: M09, S05, C01-C05,
  Gate 3 balance acceptance. Manual combat stays OFF by default. Details: `components/KenshiFP/docs/COMBAT_TEST_PLAN.md`.
- **PG:** all automated rows PASS; D1-D3, D5-D8 done; open D4 athletics feel + tooltip/feel rows (Shay, MASTER section 2).
  `TEST_PLAN.md` there is the regression spec (scenarios cite its row IDs: never delete rows); status lives in `INGAME_STATUS.md`.

## Next work (in order)
1. FP combat reconfirm batch on FE26573F (both rigs, wrappers in `components/KenshiFP/tests/ingame/`, fixture FP-crossbow).
2. FP combat open rows: M09, S05, C01-C05; define Gate 3 tolerances.
3. STOBE section D in-game confirmations; then item 63 (next big feature) with Shay.

## How to run things (recipes that used to live only in handoffs)
- Detached 5090 batch: `MSYS_NO_PATHCONV=1 wsl.exe -d DwemerAI4Skyrim3 -u root --cd / -- bash -s <<'EOF'` +
  `setsid nohup bash /mnt/c/KenshiModding/tools/automation/run-batch.sh ... >start.log 2>&1 </dev/null &` + `sleep 5; pgrep -f run-batch.sh`
  (the `bash -c '... &'` form died silently). Health: `batch-health.sh <out>` (CLAUDE.md "Batch the game runs").
- 4080: ssh default shell is cmd; bash = `"C:\Program Files\Git\bin\bash.exe" -l`. FP wrappers live in `C:\KAH\fp`, outputs
  `C:\KenshiTestRuns\fp-4080-<N>`. Install KenshiFP: copy the DLL to `C:\KAH\KenshiFP.dll`, run `C:\KAH\inst.ps1` (harness:
  `C:\KAH\insth.ps1`). Subagents can't ssh the 4080: copy logs to `C:\KenshiTestRuns\fp-4080-<N>-logs\` for them.
- Never `mv` a `.new` over a wrapper a running 5090 batch reads straight from /mnt/c (drvfs kills it): run batches from copies.
- KenshiFP free-cursor (Left Alt) blocks `fp_camera look`; `fp-ui-guard.sh` clears it (`stobe-auto fp_state free off`).
- A physical Right Alt toggles FP mode (only with Kenshi focused); don't touch the 5090 keyboard during FP batches.
- Git Bash clock is 1 h behind the WSL/batch clock. Git Bash `/tmp` is not WSL `/tmp`.

Goal, batching, token-light test rules: CLAUDE.md "Start here" (Shay's standing orders, 2026-10-03/04). The m18-m40
checkpoints, to-do list and session notes were removed 2026-10-06 (all items done or tracked in the plans; history in
the run logs and `git log -p testing/HANDOFF.md`).

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
  - crossbow smithing: s10 0.0064 / s90 0.0147 / +99.6% -> rerun m41: +7.1% / +14.1% at +25/+50%, lab50 ctl 1.000 (D5) -> mechanical PASS, balance open
  - cooking: s10 0.127 / s90 0.287 / +23.6% -> mechanical PASS, balance open
  - farming: lowered to ~0.5/pt (D1): +25% gear +16.5%, +50% +29.7% -> row 206 PASS (4080 m41), balance accepted
  - robotics: s10 0.021 / s90 0.048 / +22.0% (lab50 ctl 0.84) -> mechanical PASS, balance open
  - science: s10 21.5 / s90 47.7 / +23.1% (lab50 ctl 0.75) -> mechanical PASS, balance open
  - engineering: s10 2.90 / s90 8.39 / +25.3% -> mechanical PASS, balance open
  - medic: gear raises kit quality (D2): +22.1% / +41.5% heal rate at +25 / +50% gear -> row 191 PASS (4080 m43)
  - assassination: s10 43.8 / s90 180 / s25+50% 92.7 / +36.7% -> mechanical PASS, balance open
  - lockpicking: s10 0.117 / s90 0.90 / s25+50% 0.483 / +70.0% -> mechanical PASS, balance open (lock level <= skill reads flat 0.9)
  - thievery: s10 0.11 / s90 0.99 / s25+50% 0.41 / +50.0% -> mechanical PASS, balance open
  - stealth: s10 0.70 / s90 1.30 / +16.7% -> mechanical PASS, balance open
  - swimming: s10 2.38 / s90 30.9 / +24.8% -> mechanical PASS, balance open
  - athletics (5090 batch T pg-85, swim 300 m s, lower = faster): s10 4.3 / s90 3.0 / own50 ~2.8 / lab50 ctl 3.5 -> mechanical PASS; acceleration hook (PG f212cbc) -> D4 feel row for Shay
  - turrets (pg-55, batch W, needs harness `turret ... aim`: the turret never targets a dummy by itself): skill01 0.10 / 0.90 / 0.15, dummy worst 5% / -27% KO / -58% KO -> mechanical PASS, balance accepted (D6)
  - perception: back on gear (m46 Shay); ranged gate PASS m47 (4080, PG 199a/b/c)

## Gotchas
- Full-Base world raids: `fullbase-guard.sh` after each Full-Base load; it protects both squad members, so wrappers that
  KO the mate must turn protect off first (park_malzin does since m18).
- `stobe-fight-lib.sh` is sourced by every wrapper: `bash -n` it after any edit (run via WSL with `MSYS_NO_PATHCONV=1`).
- Long WSL batches: start detached (`setsid nohup bash … &` inside WSL); Bash `run_in_background` dies at 10 min.
- Don't run Windows `python3` in Git Bash for repo scripts that need WSL paths; use WSL python3.
