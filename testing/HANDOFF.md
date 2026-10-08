# Current state (m66, 2026-10-08, Shay playtest round 2)
This file + CLAUDE.md are the whole state: there are no separate handoff files any more (deleted 2026-10-06). Any agent
starting here needs nothing else. Keep it current: update this section at every milestone, before a session ends.
Run logs: `archive/test-run-2026-10-08-m59-m60.md` (newest), `...-m57-m58.md`, `...-m56.md`, `...-m55.md`, `...-m54.md`. Open rows: `MASTER_TEST_PLAN.md`.

## Right now (2026-10-08 m67, coordinator)
- Shay's 2026-10-08 playtest round 2: rows STOBE 146/147 (done), NP1-14, FP PT04, PT17, PT23-PT29. RULE (memory
  repro-shays-exact-steps): a row passes only when the wrapper replays Shay's exact steps; visual rows need screenshots
  of every state zoomed in AND out. Run log `archive/test-run-2026-10-08-m61.md` (m61-m66).
- Confirmed m64-m66: NP1-NP14, PT05, PT06, PT13, PT14, PT19-PT21, PT23 (+ LMB speed bug fixed: KenshiFP 1EACB71D blocks
  MyGUI presses while FP owns the cursor), PT24 (Control inside the native menu), PT27, PT29 (pre-rework).
- Confirmed m66c-m67: PT04, PT20, PT24, PT25 (pre-holster-delay); m67 (KenshiFP 53ED240C, holster lowering window
  6140eca) PASS PT20/23/11/18/15/02/12, FAIL PT25 (R holster with crossbow: sheathed then drawn=1 again) + PT01
  (hud_shown=0 after R draw) -> fixer (fresh agent, ticket in run log m67). Rerun both after the fix.
- Open: PT26/PT28 + Shay's NEW ORDER (2026-10-08): review EVERY frame of every FP combat animation (attack, recover, block,
  aim, fire, reload, ready, draw/holster, transitions; sword + crossbow) vs other FP games (Skyrim/KCD/Chivalry),
  fluid, no frame jumps, readable, correct grip/orientation; fix and redo the full every-frame pass until nothing is
  left. Owner: viewmodel agent on the 4080 (handoff C:\Users\Shay\AppData\Local\Temp\claude\C--KenshiModding\
  vm-handoff-review.md, agent #4 since 14:35; predecessor vm-handoff-pt28b.md); coordinator reviews its montages itself before accepting.
- Installed 5090: Stobe B45194AD, KenshiFP 53ED240C, harness FA9C3EFB, server 4722ddd. gfx-mods OFF (on before Shay plays).
- Shay decisions taken 2026-10-08: PT04 FP speeds = the game's non-FP speeds; R with sword+bow follows the ranged toggle.

## Before m52 (2026-10-07 m51 end, coordinator handing over to a new agent)
- **Shay is playing on the 5090: do not launch, stop or install anything there until Shay says it is free.** Kenshi on
  the 5090 is Shay's (`-Play`), gfx-mods ON. 4080 idle, Kenshi closed, lock released.
- **Nothing automated is left on the 4080.** All FP rows closed (C05-KO 8965bc3, C05-STAIRS a1414c4, C04-TAKE da96d77/
  ffad4e4, C05-INTERIOR 799c3f9: bm51h 30/30, bm51i, bm51j 40/40); FS01/FB01/FF01/HUD01 deleted from COMBAT_TEST_PLAN.
- **Last 5090 round (one launch, when Shay frees it; Kenshi closed, `gfx-mods.sh off --hdtex` first, `on` after):**
  1. install KenshiFP 76CF7E8A (5090 still 07376F24) + Stobe B056BDF0 (`C:\StobeBuild\out\Stobe.dll`, built from e4e4f3a).
  2. KenshiFP confirm: one fp-control ctl-off set (C05-INTERIOR on the 5090).
  3. NPC bio LLM rows: `npc-llm | kah-npcpanel | Shay | Malzin | 1800 | STOBE-NPCPANEL.sh NP5 NP11 NP12 NP13 NP14`
     (NP13/14 = hidden backstory confided at Devoted+, server bf31d12, setting `general_settings.NPC_BIO_BACKSTORY_MIN_TIER`
     default Devoted; NP13/14 set Apothecary Abia's tier with `scenarios.sh trust`, may write a test backstory into the
     shared `stobe` DB, end at Fond 60). Probe DeepInfra first (one chat line; server log must show no `http_code":402`).
  4. STT confirm (e4e4f3a): push-to-talk after a save load gave "Speech transcription failed." every time (voice worker
     thread kept the main-menu playthrough epoch, upload silently dropped). Needs Parakeet (`wsl-voice.sh stt start`):
     after a load, push-to-talk -> stobe.log `STT_UPLOAD: completed`, never `STT_UPLOAD: dropped`. Can't speak into a
     mic from a test: drive it with a WAV/loopback or ask Shay to confirm while playing.
  Then log in `archive/test-run-2026-10-07-m51.md` (or a new m52 log), delete passed rows, update this section.
- **DeepInfra:** returned 402 (out of credit) for all chat from ~19:15 2026-10-07 (Malzin said "..."); Shay fixed the
  billing. If NPCs answer "..." again, grep the server log for `"http_code":402` first.
- **Open for Shay (ask once, don't block):** (a) backstory reveal at Devoted+ (default) or Bonded only (one
  general_settings row, no deploy); (b) untracked `tools/automation/kenshi-click.ps1` (a helper added a key_inject switch):
  commit or leave.
- **Final summary to Shay still owed after the last 5090 round:** F10 manual combat toggle for his feel test, NPC bio via
  `\` (now with confided backstory at Devoted+), input isolation (`kenshi-ctl.ps1 launch` background / `-Play`), STT fix,
  product note: once FP walk is pinned on a rock the order fallback doesn't walk around it either.
- Gotchas: detached WSL batches via `bash -s` heredoc (the `bash -c '... &'` form silently never ran, again m51 L);
  never `unload` a char that is still someone's fight/order target (crash exe+268A68); after a PC restart start the
  WSL stack (/etc/start_env) and Steam (`D:\Steam\steam.exe -silent`); 4080 desktop locked -> `fp_keys focus on`;
  Defender-probe new DLLs on the 4080; don't run Windows `python` from Git Bash (hangs on stdin).

## The mods and what each one owns (after the m49 decoupling)
- **Stobe.dll** (`/root/STOBE-src`, snapshot `components/STOBE`): chat/LLM bridge to the Stobe server, negotiation/deals,
  relationships (REL), NPC info panel, and since m49 ALL goal/action logic: work planner (production at benches), task goals
  (fetch, buy, guard, stock, repair, give item, bodyguard...), goal lifecycle + status/control files, goal panel UI, native
  actions (lookup, orders, movement, equip). Log `stobe_goals.log`. Works with KenshiFP absent (DC1-DC5).
- **KenshiFP.dll** (`/root/KenshiFP`, snapshot `components/KenshiFP`): first-person mode only: camera/head/eye, mouse and
  cursor, FP targeting, manual FP combat (ranged + melee adapters, ON by default since 7b85f67, F10 toggle), FP harness commands.
- **Profession Gear (PG)** (own repo `Kenshi-Profession-Gear-Progression`): per-item affixes and profession gear bonuses.
- **Automation Harness** (own repo `Kenshi-Automation-Harness`): in-game test commands (`stobe-auto`).
- **Stobe server** (WSL `/var/www/html/StobeServer`, branch `stobe`): LLM prompts, deal engine, relationship evaluation.

## Builds installed
- 5090: Stobe C8020701, KenshiFP D7BFCDF4 (252fde6), harness 52C24941, PG BAFB8C31 (Normal); server live `stobe` 9c0fc10.
- 4080: KenshiFP 76CF7E8A (799c3f9 C05-INTERIOR; bm51j 40/40), PG BAFB8C31, harness 24BE3AEC (no Stobe there). Rig notes: local `handoff/4080-test-rig.md`.

## Status per mod
- **STOBE / REL:** all automated rows PASS; open items only in `STOBE_full_test_plan.md` (D: fixed, awaiting in-game
  confirmation; E/F: design + next big feature, item 63 = pick the next big feature with Shay).
- **KenshiFP decoupling:** done m49 (Stobe 9d99f36, KenshiFP f94b1d5); DC1-DC7, 89, 14-A3, generic-fb, 16-fb 55/55, A8 PASS.
- **FP combat:** all automated rows PASS (m50, KenshiFP 8469D760; Gate 3 tolerances decided 2026-10-06). Left for Shay:
  visual/feel checks (manual combat now ON by default, F10 toggle). Details: `components/KenshiFP/docs/COMBAT_TEST_PLAN.md`.
- **PG:** all automated rows PASS; D1-D3, D5-D8 done; open D4 athletics feel + tooltip/feel rows (Shay, MASTER section 2).
  `TEST_PLAN.md` there is the regression spec (scenarios cite its row IDs: never delete rows); status lives in `INGAME_STATUS.md`.

## Next work (in order)
1. Shay: FP visual/feel checks (F10 settings); PG D4 + tooltip/feel rows (MASTER section 2).
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
- Never replace a wrapper a running batch is executing, not even .new + mv: on /mnt/c (drvfs) the running bash loses its file ("error reading input file: No data available", m64 lost NP12). Edit only after its row ended.
- Full-Base world raids: `fullbase-guard.sh` after each Full-Base load; it protects both squad members, so wrappers that
  KO the mate must turn protect off first (park_malzin does since m18).
- `stobe-fight-lib.sh` is sourced by every wrapper: `bash -n` it after any edit (run via WSL with `MSYS_NO_PATHCONV=1`).
- Long WSL batches: start detached (`setsid nohup bash … &` inside WSL); Bash `run_in_background` dies at 10 min.
- Don't run Windows `python3` in Git Bash for repo scripts that need WSL paths; use WSL python3.
