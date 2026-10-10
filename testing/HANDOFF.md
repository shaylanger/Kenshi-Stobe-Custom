# Current state (m90, 2026-10-10)
This file + CLAUDE.md are the whole state: there are no separate handoff files any more (deleted 2026-10-06). Any agent
starting here needs nothing else. Keep it current: update this section at every milestone, before a session ends.
Run logs: `archive/test-run-2026-10-08-m59-m60.md` (newest), `...-m57-m58.md`, `...-m56.md`, `...-m55.md`, `...-m54.md`. Open rows: `MASTER_TEST_PLAN.md`.
- **Animation lab (offline KenshiFP viewmodel replay/metrics/render, 2026-10-09):** state and resume pointer in `Kenshi-Automation-Harness/docs/animlab/STATUS.md`; KenshiFP adapter in `components/KenshiFP/animlab/`.

## Right now (2026-10-10 ~11:45, m90 coordinator handed off at context limit): many agents stopped, read their handoffs
- Start with `tools/automation/session-start.ps1` (agent status/handoff files in `C:\KenshiTestRuns\agents\`, queues in
  `queue\5090.next` / `4080.next`, inflight markers). Respawn each agent not DONE as a FRESH agent from its handoff file.
- Agents and state:
  - `kfp-fixer` (5090, holds game lock `kfp-fixer`, marker inflight\kfp-fixer -> its batch out dir; installed KenshiFP
    E816CBB1 = F0595751 + ticket B allow-list + (inactive) stroke1 refit4): asked to stop at the handoff; read
    kfp-fixer.status/.handoff.md. Queue: ticket B allow-list is WRONG ('block left upper' hangs) -> name survey + fix;
    E6 refit4 pool-climbed patch pending-fixes/kfp-e6-strokes12-refit4.py (pool stroke1 0.95 marginal) -> inline/churn;
    ONE batched build (ticket B + E6 if gates pass + `# src` rec header + pending-fixes/kfp-test-swing-end-line.py
    (committed 8a47297?) + kfp-pt30-flip.py vmcheck patch) -> animlab gate -> VMQUICK -> 4080 numeric rows -> takes.
  - `pt30-flip` STOPPED-CONTEXT: frame 158 = vmcheck hitch bug (patch pending-fixes/kfp-pt30-flip.py); corrected check
    finds a REAL follow-through edge roll snap at frame 284 (E1 lead in vm_swing_atl, u .58-.98). Decision: ship vmcheck
    patch with the solver fix (coordinator default), not alone.
  - `animlab-loop` DONE (m91): extended take-preflight installed (8352239, 19d4b25; pf_rig -> rig_preflight), backfill n/a
    filter (e42aca6), ledger table in STATUS (harness 8f900db: 46 flaws, lab-first 2%), gate baseline PASS
    (corpus\gate-baseline.tsv, mutations 10/13). Left: take-script wiring uncommitted in kfp-fixer's files (told fixer);
    backfill finds (cursor at 1280,720, guard vs pool, sword-pool manifest rows) + re-baseline -> animlab-maintainer.
  - `animlab-maintainer`: was RUNNING (class audit; UNCOMMITTED per-swing moves/arc/inline change FAILS Shay-accepted
    f28/f23 per taste set -> recalibrate before commit; label-leads-screen + NPC-speech overlay misses from T6 review).
  - `4080-filming` STOPPED-CONTEXT: rig layer done (6ffe60b, eeab981). Proof take not rerun. Take bugs: s3prep2 drew the
    crossbow not the katana (require melee=1), s3render3 end+1.3 s (use +0.5); capture preflight (quser Active +
    non-black grab) not written. 4080 kenshi.cfg left in test mode (restore `kcfg.ps1 play` when done).
  - `4080-display` (virtual display driver + keep-display-on.bat for Shay): read its status/handoff; when READY tell
    Shay to double-click keep-display-on.bat in RDP instead of closing RDP. Shay's RDP session 2 is Active.
  - DONE: `kfp-regress` (no product regression; PT26/28 specs predate accepted poses; side-by-sides
    C:\KenshiTestRuns\spec-compare\*.jpg reviewed + shown to Shay), `animlab-spec` (taste set 71 rows, 0 misses, 6 false
    alarms -> Misses; spec.py; unarmed spec), `fists` (4 candidates C:\KenshiTestRuns\fists-cand\ +
    /root/animlab-work/fists/cand; lab PASS; unarmed spec PASS except shoteiL inferred U6 wind-up 0.05 dm above eye;
    NOT yet coordinator-reviewed; unarmed body game rec spec agents\fists.need-rec.md -> 4080 queue).
- Waiting on Shay: (1) PT26/PT28 specs follow accepted poses or not (stills confused Shay: agent spec-videos builds side-by-side
  videos C:\KenshiTestRuns\spec-videos\ to show him instead); 4080 virtual display LIVE (Shay ran keep-display-on.bat 2026-10-10, session 2 on console, gdigrab LIVE); he must rerun it each time he leaves RDP; 4080-filming told to start the proof take. Shay decided: half-open hand OK; palm strikes -> straight-wrist punches. Shay decided 2026-10-10 (m91): native animation frames are EXEMPT from the wrist-bend limit (PT29 + lab wrist checks; told kfp-fixer + animlab-maintainer). Shay 2026-10-10: unarmed inferred rules (U1/U2/U4/U6/U10/U11/U14/U16) + R17 are NOT his to judge: the native in-game animations decide (agent animlab-spec resolves each against native measurements).
- T6 turret-fp.mp4: coordinator review FAIL (labels lead the screen 0.4-0.5 s; NPC speech text overlays; possible 1-frame
  barrel sliver at 59.125); fixer has the list. Review pack C:\KenshiTestRuns\review\t6 (built with --offset 0.8).
- Nothing is ready for Shay as a video.

## Earlier (2026-10-10 m87): FP viewmodel/turret work DONE, nothing running, waiting on Shay
- Kenshi closed, lock free, no inflight, 5090 idle recorded ("awaiting Shay's decisions"). Fixers #1-#44 (lock owner fixer-pt30) finished; their log `%TEMP%\claude\C--KenshiModding\wr\HANDOFF-sword-wrist.md`.
- Videos, all coordinator-reviewed, in `C:\KenshiTestRuns\vm-rework\`: anim-sword-e6, sword-z25-block, turret-fp (T6, 86fa1ca), zoom-sweep (Z1, 276e1fc). Scripts to re-render them: `C:\KenshiTestRuns\vidscripts\` (f24/f26/f36/f38 helpers).
- Waiting on Shay (COMBAT_TEST_PLAN rows): Z1 zoommode switch (default) or fade; E6 default stroke mask (now 0x1 = diagonal only; stroke 3 stays off); T6 turret look/feel.
- Harness bugs seen (not fixed): give+pickup leaves a ghost crossbow mesh; `teleport "#handle"` ignores the handle and moves the selected char; `chars` centres on the player. No `unpin` command (pins drop on relaunch).
- Gotchas: the display sleeps after 60 min without input -> gdigrab records black; run a SetThreadExecutionState(ES_DISPLAY_REQUIRED|ES_CONTINUOUS) keeper while filming. Files written from WSL show skewed mtimes in Git Bash: check freshness from inside WSL. `setsid nohup ... &` inside a one-shot `wsl.exe bash -c` died with the call here; run long WSL jobs as a background Bash-tool call instead.

## Earlier (2026-10-09 m78): sword wrist fold FIXED, fixer #6 on PT30-FLIP / PT32 / blade look
- **Wrist fix** KenshiFP C7586828 (/root/KenshiFP ad419c0, local only) on both rigs; snapshots 51d9720, 27ab2ed, 2773fd3; VMQUICK row c49adda/62f0917; plan 306390a.
  Sword wrist bend 108.7 -> <=24 deg (limit 30); zoom 25 no longer glues hands to the head. VMQUICK PASS (5090); 4080 final rows PT13/14/26-30 PASS; 5090 all PASS except PT30.
- **Open (fixer #6, lock owner fixer-pt30, state in `%TEMP%\claude\C--KenshiModding\wr\HANDOFF-sword-wrist.md`):** PT30-FLIP (1 blade-roll jump at first wind-up after draw, ~2/5 runs);
  PT32 native free swing ends after ~2 frames (no visible attack at zoom 25); blade foreshortened into the screen at strike/follow-through vs the old sweep (coordinator review);
  5090 window renders 938x475 instead of 1600x900. PT33 open palm at wind-up (native finger pose) = Shay-look row. Sheets `C:\KenshiTestRuns\vm-rework\`.
- 4080 Defender exclusions done (Shay). RAM rules stay as they are (Shay 2026-10-09: WSL 8 GB cap is enough, measured 1.1 GB used / 6.8 GB available; voice services stay off).

## Dual wield research checkpoint (2026-10-09; documentation only)
- Updated `DUAL_WIELDING_MOD_IMPLEMENTATION_BRIEF.md` with static follow-up: candidate source/reuse status, pinned Blender 4.2 exporter and official rig templates, back/hip/main inventory distinction, public KEP source hook audit, and existing VMQUICK/PT29/PT30 recorder/checker gaps for two blades.
- Inactive references under `tools/research/dual-wield-reference/`: animation-toolchain archives and KEP source at `08bb145c9b360bbfd2117c57b9104c5d2c18624e`; excluded from source control.
- User explicitly authorized research only, stopping before building/testing. No mod enabled, game driven, harness changed or lock acquired. `fixer-pt30` ownership and ongoing FP work were left intact.
- Next dual wield phase: candidate fixture evaluation and animation exporter round trip, when authorized; read the brief for exact gates. Existing body checks must cover both weapon hands before accepting dual poses.

## Earlier (2026-10-08 m77): PT17 viewmodel rework DONE, nothing running
- **PT17 final KenshiFP 0750f26a** (/root/KenshiFP 04bf8c2, local, unpushed like the 60 before it; snapshot 25748e5):
  sword + crossbow near-plane cuts 423/247 -> 0. 5090 run on 0750f26a: PT13/14/26/27/29/30 PASS (PT30 cut=0 both).
  PT28 PASS on a rerun with the desktop unattended (two earlier FAILs = why=no_focus while the 5090 was in use).
- Installed: 5090 KenshiFP **0750F26A**, Stobe 85A731C7, harness FA9C3EFB; 4080 KenshiFP BDE84F7F, harness 24BE3AEC.
  **4080 Windows Defender quarantines 0750f26a** (ML false positive, ThreatID 2147731849): needs Shay's exclusion
  decision (C:\KAH + Kenshi mods folder); the permission checker blocks agents from Defender work.
- Rigs: both Kenshi closed, locks free; 5090 gfx mods on + full screen restored. Sheets `C:\KenshiTestRuns\vm-rework\pt17-*.jpg`.

## Earlier (2026-10-08 ~23:40, m76 successor): FP viewmodel deferred sweep DONE
- **Shay (m75): run every 4080 + 5090 step truly in parallel** (two background jobs at once; memory `parallel-rigs`).
- **Sweep on final DLL KenshiFP C2692485: every row PASS** (PT11/13/14/18/25/26/27/28/29/30/31 + sword/crossbow
  holds, fire, zoom-out, draw/holster). All FAILs were test bugs, fixed in `fp-viewmodel.sh`: vm_on = great-circle angle
  (az meaningless at aim elev -87), live shots wait `loaded=1`, reload captured before the slow screenshot, vmcheck skips
  the 0.4 s aim-hold blend, PT28 enables + arms fp_combat itself (run without PT13 it stayed `why=off`). Walk "FAIL" =
  measurement artifact (raw rec lags one frame of root motion; walkana p95 0.13-0.25 dm), no product change; test build
  61DDB46C discarded. Evidence sheets: `C:\KenshiTestRuns\vm-rework\`.
- Rigs: 5090 Kenshi closed, lock free, gfx mods on + full screen restored, `idle "Shay playing"`; 4080 closed, lock free.
  Installed: both KenshiFP C2692485; 5090 Stobe 85A731C7, harness FA9C3EFB; 4080 harness 24BE3AEC.
- Test data cleaned (Shay 2026-10-08, rule in CLAUDE.md "Clean up test data"): 5090 `C:\KenshiTestRuns` 30 GB -> 7 MB,
  4080 14.8 GB -> 0.45 GB, harness screenshots emptied on both.
- Open for Shay (feel): crossbow reload hold 70 deg roll. Worth a look: harness call ~1.3 s each on the 5090; a launch
  with DISPLAY2 on can grab the foreground.

## Before (2026-10-08 ~21:30, coordinator session m74 successor, deferred sweep running)
- **Task:** Shay's FP viewmodel order (every-frame review of all FP combat animations, sword + crossbow, vs Chivalry 2;
  verbatim + Amendments 1/2 in `C:\Users\Shay\AppData\Local\Temp\claude\C--KenshiModding\vm-shared.md`). Method = Amendment
  2: fast path per weapon (both DONE), then ONE deferred sweep on the final merged DLL (RUNNING NOW). Previous checkpoint:
  `handoff-m74.md` in that temp dir (full DONE/IN FLIGHT/gotchas of the crossbow session).
- **Status:** SWORD fast path DONE (PT14/PT26/PT27 PASS on BA4025B2, merged 5e7f4de). CROSSBOW fast path DONE: PT28 failed
  on 30B2D5EF (ready bmin under the HUD line, reload uz +0.28 from an anti-parallel pose u) -> pose fixes only (ready/block
  grip y -1.5 -> -0.8; reload f(-0.40,-0.30,0.87) u(-0.915,0.19,-0.356): hold rolled ~70 deg left, limbs vertical = the only
  orientation meeting uz<=-0.3 nose-down; LOOK is Shay's feel call), live-tuned PASS, merged 3-way onto main as
  /root/KenshiFP **5bab271**. FINAL DLL **KenshiFP C2692485** (copy `C:\KenshiTestRuns\vm-rework\dll\KenshiFP-C2692485.dll`;
  builds are not byte-identical: copy, never rebuild) installed on BOTH rigs. On it (4080): PT28 PASS, PT29 PASS, sheets
  xr2 (reload entry/hold/exit), xt2-649-672 (aim->ready), xt3-aim.jpg (ready->aim); recordings x15/x16/x17 (x17 = 827 fr,
  FLAGS 0). Commits in C:\KenshiModding main: 66ff880 (snapshot kfp_viewmodel.inc), 8e5c701 (fp-viewmodel PT28 limits),
  505e5df (COMBAT_TEST_PLAN PT28 fast path done). Progress files `vm-progress-sword.md` / `vm-progress-xbow.md` (temp dir).
- **Running right now:** 5090 Kenshi RUNNING windowed background on kah-fpxbow (DISPLAY3 = the only monitor on; DISPLAY2 is
  off), lock owner vm-sword, KenshiFP C2692485: SWORD SWEEP in progress per `vm-handoff-sword-3.md` "Sword sweep recipe"
  (swpass f3 -> swframes -> shots/sheets holds+draw/holster+walk -> `swrows.sh` PT13,PT14,PT26,PT27,PT29,PT30 -> LAST
  `m73fg.sh` PT18/PT31/PT11/PT25). Log `C:\KenshiTestRuns\vm-rework\swpass-f3.log`. 4080: Kenshi RUNNING (kah-fpxbow,
  C2692485, harness 52C24941), lock rig4080; crossbow sweep items left: zoom-out spot frames per state (fp_camera distance
  25 + shotset replay of x17), hold sheets ready/aim in+out vs `reference photos/crossbow aiming.PNG`, draw/holster sheets
  from x17, `xwalk x18` walk sheet (tools ps4080.sh srec.sh shotset.sh xsheets.sh xrec.sh in the temp dir). Inflight markers
  `C:\KenshiTestRuns\inflight\4080-xbow-sweep`, `5090-sword-sweep`; waker `sleep 120; rig-health.sh` (RIG STALL for the
  4080 marker while the 5090 game is down is expected: the script only sees the local game).
- **Installed:** 5090 Stobe 85A731C7, KenshiFP C2692485, harness FA9C3EFB, server 4722ddd. 4080 KenshiFP C2692485, harness
  52C24941 (restore 24BE3AEC at the end). gfx-mods OFF; kenshi.cfg TEST mode (windowed, VSync=No; Shay's values in
  C:\KenshiTestRuns\kenshi.cfg.play).
- **Uncommitted/unpushed:** C:\KenshiModding main == origin (505e5df) except `components/KenshiFP/tests/ingame/
  fp-viewmodel.sh` (PT13 ready tilt band -27..-6, follows the PT28 low-carry spec; bash -n OK; commit with the sweep
  results) and the usual not-mine files. /root/KenshiFP main 5bab271 clean (local only, never pushed); /root/KenshiFP-vm
  (viewmodel) = 5bab271; /root/KenshiFP-sw = 5e7f4de stale. Server/ss-merge/STOBE-src untouched.
- **Open bugs/tickets:** none for the fixer. Sweep watch list: PT26 on the 4080 (30B2D5EF, 40 fps) had swing ratio up to
  2.9/3.0 -> confirm on the 5090; black-plane artefact once on the 4080 (not reproduced); near clip caps the aim limb span
  ~65 % (accepted); reload hold look (70 deg roll) = Shay's feel call. Permission checker denied editing rig-health.sh
  (hook script, don't retry) and once a plain waker command (retry worked): tell Shay in the summary.
- **End of task:** 4080 restore (ctl.ps1 stop, delete kah-fpxbow, harness 24BE3AEC back, ctl.ps1 release, delete inflight
  marker), 5090 stop + release + `gfx-mods.sh on`, ONE summary to Shay (commits, DLL sha8 + path, sheet paths per animation,
  numeric tables, issues fixed, unfixable + why, Chivalry refs). **Decisions waiting on Shay:** none.
- **Gotchas:** run4080.sh runs all 7 rows unless `ROWS=` is set; never tail wrap-out/log.txt (grep ^RESULT); vmcommit.sh
  drops other-weapon hunks (merge by hand); python heredocs via wsl.exe: no "\U" in normal strings; a `setsid nohup` job
  inside a wsl.exe call dies with the call: run long WSL jobs as a background Git Bash command that keeps wsl.exe open;
  DISPLAY2 drops out of the monitor list (launcher uses the first screen that is on, Shay: windowed + background is what
  matters); fp_vm replay recordings live in memory (lost on relaunch; a new recording replaces them); harness screenshot
  never overwrites an existing file.
## Earlier today (2026-10-08 ~17:15 after m72, coordinator)
- **Launch rule (Shay, 2026-10-08, CLAUDE.md "Test launches on the 5090"):** test launches are windowed 1600x900, background,
  isolation on, DISPLAY2 preferred (m72 ran exclusive-fullscreen and interrupted Shay; killed). `kenshi-ctl.ps1 cfg status`
  shows the mode; `gfx-mods.sh on` / `-Play` restore Shay's full screen 2560x1440 (saved in C:\KenshiTestRuns\kenshi.cfg.play).
- **18:30 status:** first fable agents hit their context limit after ~20 min (~200k tokens each); successors #2 started
  18:25 from vm-handoff-sword-2.md / vm-handoff-xbow-2.md (builds ready, not installed: sword BA4025B2 = face-guard block,
  cocked wind-up, deeper draw pose; crossbow 30B2D5EF = aim grip at the eye plane, low ready carry, reload rolled, near-plane
  routing xwp, corrected limb model). m73 playtest inside the sword session (2546C194): PT25 PASS, PT11 PASS, PT18/PT31 FAIL
  = setup (aim refused `no_focus`: the background window is never foreground) -> fp-playtest.sh now sets the `fp_keys
  focus on` test switch like fp-controls.sh (18b57a9); rerun in the final sweep. Launch focus leak (game took the
  foreground when launched while Shay was idle) -> harness `background` command + Demote fallback (harness bc53d38).
- **Running (fable agents, started ~17:10):** sword viewmodel agent on the 5090 (lock owner `vm-sword`, clone
  /root/KenshiFP-sw, handoff vm-handoff-sword.md) and crossbow viewmodel agent on the 4080 (lock `rig4080`, clone
  /root/KenshiFP-vm, handoff vm-handoff-xbow.md); shared rules + Chivalry 2 reference (Shay's photo
  `reference photos/crossbow aiming.PNG`) in vm-handoff-review.md / vm-shared.md (temp dir). Coordinator batches take
  turns with the sword agent via the game lock.
- **Shay's process changes (17:30, "do all of these"):** (1) the sword agent runs PT18/PT31/PT11/PT25 (fp-playtest) inside
  its own session, m73 = viewmodel rows only; (2) agents batch all fixes per weapon -> one build -> one full every-frame
  pass (second pass only on a finding); (3) sheets reviewed by the coordinator as they appear via vm-progress-sword.md /
  vm-progress-xbow.md (temp dir), PT26/PT28 accepted from numeric tables + sheets; (4) 40 fps pass only, fpscap 20 only
  for borderline frames; (5) agents take each other's unclaimed items when a rig frees up (CLAIM lines in the progress files).
- **Amendment 2 (Shay, 18:00, full text vm-shared.md, replaces the above where different):** FAST PATH per weapon = one
  offline review -> all fixes -> one build -> ONE zoomed-in every-frame pass of the MOVING states only (swing, reload,
  fire/kick) with numeric tables; static holds (ready/aim/block) accepted from numeric checks; skip zoom-out passes,
  draw/holster cycles, walk frames, PT29-at-25, PT30/regression rows on iteration builds, fpscap-20. `FASTPATH DONE
  <weapon> <sha8>` in the progress file when merged. DEFERRED FINAL SWEEP once on the final merged DLL after BOTH weapons
  are done (first free rig starts, split if both free): zoom-out spot frame per state + PT29 at 25, hold sheets in+out vs
  Chivalry 2, draw/holster cycles, walk sheets, PT30 + regression rows, PT18/PT31/PT11/PT25 last on the 5090; logged as
  `SWEEP <item> PASS|FAIL`; findings batched -> one fix/build -> targeted pass -> affected sweep items only.
- **Next coordinator batch m73 (5090, when the lock is free):** viewmodel rows PT13,PT14,PT26-PT30 after the agents merge
  (KenshiFP main 614adb0+ rebuilt/installed by the sword agent; record its sha8 here).
  m72 dir C:\KenshiTestRuns\m72 (killed early; rerun as m73 with fresh frozen scripts). Run log m67-m71 in
  `archive/test-run-2026-10-08-m61.md`. m71: PASS PT25 PT11 PT31 PT15 PT02 PT01 PT13 PT14 PT27 PT26 PT30; FAIL PT18
  (measurement, fixed 9da5bf9, unconfirmed), PT28/PT29 (viewmodel agents).
- Final step of this round: close Kenshi, `gfx-mods.sh on` (restores full screen too), ONE summary to Shay.
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
- 5090 (2026-10-10): KenshiFP 3A059220 (3b65503), harness FF567966, PG BAFB8C31, Stobe RE_Kenshi 85A731C7 (mods\Stobe copy B45194AD); server live `stobe` last recorded 9c0fc10.
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
