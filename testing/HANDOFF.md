# Current state (m51, 2026-10-07)
This file + CLAUDE.md are the whole state: there are no separate handoff files any more (deleted 2026-10-06). Any agent
starting here needs nothing else. Keep it current: update this section at every milestone, before a session ends.
Run logs: `archive/test-run-2026-10-06-m49.md` (m49), `archive/test-run-2026-10-06-m50.md` (m50, 4080 FP batches b27+). Open rows: `MASTER_TEST_PLAN.md`.

## Right now (2026-10-07 m51, coordinator; Shay: don't stop till done, wakers 2 min, log Shay-needs here and skip)
- m51 work: KenshiFP manual combat ON by default + F10 "Manual combat" toggle + 5 rebindable keys + bound-key leak fixes,
  committed 7b85f67 (KenshiFP 9017FAA0). Stobe NPC biography card committed 8c45a9f/37fb725 (Stobe 3EF4CCEE, server 7ea8347).
- 5090: batch I `C:\KenshiTestRuns\m51-5090-i` (run-batch.sh, --stop): CS01-CS08 (all PASS), K rows, NP5/NP11/NP12 (needs
  DeepInfra credit; Shay is topping up). Run log `archive/test-run-2026-10-07-m51.md`.
- 4080: runners bm51e (60F81473) then bm51f (9017FAA0), `C:\KAH\fp\bm51e.sh|bm51f.sh`, lock `C:\KenshiTestRuns\fp-runner.lock`,
  out `C:\KenshiTestRuns\fp-4080-m51e|m51f` (SUMMARY.txt + DONE): K rows + fp-control COMBAT=on.
- m51 B died 12:02 (5090 clock): WSL had shut down entirely (no crash dump); restart the stack with /etc/start_env, and
  Steam (`D:\Steam\steam.exe -silent`) after a PC restart.
- DeepInfra returned HTTP 402 on chat from 11:38 (5090 clock): check live chat before LLM rows.
- Gotcha: never `unload` a char that is still someone's fight/order target (game crash, exe+268A68); tests KO and leave them.
- Gotcha: start detached WSL batches with `wsl.exe ... bash -s` + heredoc (`setsid nohup ... > log 2>&1 < /dev/null &`) and
  check the out dir appears; the one-line `bash -c '... &'` form silently never ran (m50 G and U).
- 4080 desktop is locked (LogonUI): KenshiFP test switch `fp_keys focus on` (fp-controls.sh uses it). Defender-probe each new DLL
  on the 4080 (copy to C:\KAH, Get-FileHash, wait 20 s, Test-Path + newest Get-MpThreatDetection).
- Waiting on Shay: FP visual/feel checks and whether manual combat goes ON by default (MASTER section 2).

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
- 5090: Stobe 3EF4CCEE (NPC biography card), KenshiFP 9017FAA0 (manual combat default ON + binds, 7b85f67), PG BAFB8C31 (Normal), harness 24BE3AEC; server live `stobe` 055e0c5.
- 4080: KenshiFP 9017FAA0 (m51, from bm51f; FD7A9A27/60F81473 before), PG BAFB8C31, harness 24BE3AEC (no Stobe there). Rig notes: local `handoff/4080-test-rig.md`.

## Status per mod
- **STOBE / REL:** all automated rows PASS; open items only in `STOBE_full_test_plan.md` (D: fixed, awaiting in-game
  confirmation; E/F: design + next big feature, item 63 = pick the next big feature with Shay).
- **KenshiFP decoupling:** done m49 (Stobe 9d99f36, KenshiFP f94b1d5); DC1-DC7, 89, 14-A3, generic-fb, 16-fb 55/55, A8 PASS.
- **FP combat:** all automated rows PASS (m50, KenshiFP 8469D760; Gate 3 tolerances decided 2026-10-06). Left for Shay:
  visual/feel checks and the manual-combat default (OFF now). Details: `components/KenshiFP/docs/COMBAT_TEST_PLAN.md`.
- **PG:** all automated rows PASS; D1-D3, D5-D8 done; open D4 athletics feel + tooltip/feel rows (Shay, MASTER section 2).
  `TEST_PLAN.md` there is the regression spec (scenarios cite its row IDs: never delete rows); status lives in `INGAME_STATUS.md`.

## Next work (in order)
1. Shay: FP visual/feel checks + manual-combat default; PG D4 + tooltip/feel rows (MASTER section 2).
2. Item 63 (next big feature) with Shay (STOBE section D is empty since m50).

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
