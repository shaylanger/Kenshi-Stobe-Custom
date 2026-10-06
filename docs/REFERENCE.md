# Reference: commands, test bed, gotchas

Long reference text kept out of CLAUDE.md. Current state: `testing/HANDOFF.md`; open rows: `MASTER_TEST_PLAN.md`.
(This was `archive/CLAUDE_background.md`; its old round-26 status notes were removed 2026-10-06, see git history.)

## In-game commands (full reference: `Kenshi-Automation-Harness/docs/COMMANDS.md`)
`stobe-auto <cmd>` (WSL harness client; the harness must be on (`stobe-say on`) before launch; `stobe-auto help` lists
everything incl. mod commands; agent guide `Kenshi-Automation-Harness/AGENTS.md`). Groups:
- game: `status` (shows `save=` and `last_saved=`), `load`, `save`, `speed`, `time`, `wait-world`, `wait-game <min>`;
- characters: `chars`, `traders`, `where`, `hp`, `inv`, `sections`, `spawn`, `teleport` (`<npc> <npc2|x y z|building
  <name>> [dist m]`), `ko`, `health`, `damage`, `blood`, `kill`, `hunger <npc> [0..300]` (no value = read), `eat`,
  `stat`/`setstat`, `setname`, `faction`, `sleep`/`wake`, `shackle`, `cage`, `select`, `recruit`, `relation`;
- orders: `order <npc> <task> [target|building]` (291 tasks, `tasks`), `attack`, `fight <a> <b>` (NPC vs NPC),
  `job <npc> <building> [task <t>] [radius <m>]`, `jobs`, `clearjobs`;
- items/money: `give`, `money`, `buy`, `trade` (real purchase), `shopstock`, `stash`, `transfer`, `packput`/`packweight`,
  `iteminfo`/`equip`/`unequip`, `weight`, `find`;
- buildings: `buildings [radius] [filter] [near <npc>]` (`pos=x,y,z`), `building <name> [radius]`, `power`/`fill …
  [radius <m>]`, `benches [radius] [crafts]` (search radius default 300, max 5000), `craft`, `craftfinish`, `research`,
  `blueprint`;
- UI: `ui`, `click`, `messages`, `screenshot` (game frame with HUD, `mods\AutomationHarness\shots\`);
- mods: `stobe_*` (Stobe, incl. goals and `stobe_npcinfo`), `fp_mode`/`fp_click`/`fp_putdown`/`fp_state`/`fp_camera`
  (KenshiFP), `pg_info`/`pg_force_affix`/`pg_clear`/`pg_roll`/`pg_bonus` (ProfessionGear);
- whole tests: scenario files + `stobe-auto run <file> --csv out.csv` (format: `stobe-auto run --help`).

Names: exact match nearest the player, `#serial`, `@player`, `@selected`. New general commands go into the harness repo,
Stobe-only ones into `StobeHarnessBridge.cpp`, other mods register theirs via `include/KenshiAutomationHarness.h`.

Command facts learned the hard way:
- Weapons can't be created directly (the item factory refuses them): `research` to unlock, then `craft <npc> <weapon> at
  weapon` with the materials given to the worker. `give` can't create weapons.
- Wounds from `damage` don't bleed (use `blood`); first aid needs a kit on the medic.
- A given backpack goes on the back if that slot is free, else into the main inventory; `unequip` moves the item to the
  main inventory (dropped if no room); `sections <npc>` shows where everything is.
- `@player` = first squad member (can be the mate): name the player explicitly. `recruit` changes the selection:
  `stobe-auto select <player>` after it, or `stobe-say` speaks as someone else.
- Spawned "Hungry Bandit" + faction `Drifters` = neutral test dummy. Real traders anywhere:
  `spawn "Skeleton Traders Animals" "Traders Guild" near <player> dist 140`.
- NPCs teleported within ~7 m of the squad get attacked (even Drifters at +30); for a neutral second NPC recruit a
  spawned bandit. Never kill members of a spawned neutral squad near the squad (survivors turn hostile): teleport them away.
- Raiders must be teleported inside outpost walls (else `path_failed`); the player attacking first reliably starts a fight.
  `attack` is a real order (breaks truces like a player click).
- Wait ~8 s after `wait-world` before the first `say`. `stobe_say` needs an exact name ("Vorl [Dust Bandit Bowman]").

## Scenario helpers (`tools/automation/scenarios.sh`, WSL)
`fresh` (reload the fixture, feed, reset the mate), `bodies <n>`, `duel`, `gang <n>`, `surrender` (prints
`serial|name|deal`; sends the mate away, waits for `combat_start` before dropping the target's health, refuses if the
player is KO; retry if the deal is empty), `trust "<npc>" 60 Fond`. A faction truce comes from a raid where the bandits
attack first (`gang 2`, then a deal); `surrender` (player attacks first) only makes a personal stop.
Fight watchers: `DELAY=2 stobe-fight-watch "<pay line>"` pays by itself; `stobe-fight-offer "<offer line>"` only sends
an offer; `stobe-force-attack <mate> [help]` starts a fight. `stobe-reset-npc <npc>` clears trust (saves the player
relationship first; `--restore` puts it back). `stobe-say give_cats <n>` is a test helper, not a payment.
Deal ledger: `cd /tmp && sudo -u www-data php /var/www/html/StobeServer/tools/negotiation_admin.php deals 3`
(`deal <id>`, `directives`).

## Launch (`tools/automation/kenshi-ctl.ps1`)
Wrapper around the harness repo's `tools/kenshi-ctl.ps1` with this PC's paths; allowed without asking.
`launch [-Save x]` archives the logs to `C:\KenshiTestRuns\logs\` (harness.log, outbox.txt, RE_Kenshi log, stobe.log,
stobe_goals.log, KenshiFP.log), starts `kenshi_x64.exe` (RE_Kenshi restarts it with `--norestart`), presses the
launcher OK (button 1003), waits for `KAH: frame listener running` and the autoload. Also `stop`, `restart`, `status`,
`health` (ok/crashed/hung), `screenshot` (window grab without HUD; use the harness `screenshot` for the HUD).
Stobe's MOTD dialog is off (`EnableMOTD=0` in `StobeCustom.ini` and `Stobe.ini`) so it doesn't cover screenshots.

## Gotchas
- **Goals live outside the save** (`RE_Kenshi\mods\Stobe\stobe_work_goals.tsv`, `stobe_task_goals.tsv` + server DB),
  stamped with game time and dropped when an older save is loaded. Clear leftovers: `<id>\tCANCEL` lines in
  `stobe_work_goal.control` / `stobe_task_goal.control`. Since the m49 decoupling all goal logic is in Stobe.dll
  (log `stobe_goals.log`, was KenshiFP.log).
- **Goals run on game time:** nothing advances while paused; at 50x stall/give-up timers are 50x faster too.
- **Hunger:** `MedicalSystem::hunger` is fullness 0–3; the UI shows x100 (max 300, KO ~76–87). Long 50x runs starve
  NPCs: keep food in a chest; the watch script pauses on `[EVENT] knockout` toward the squad as well as combat.
- Walk-back/report target is the selected squad member unless that's the worker, then the nearest other member.
- Squad members can't use Stobe's FOLLOW (blocked for player faction); follow/guard go through BODYGUARD →
  FOLLOW_PLAYER_ORDER.
- While paused STOBE holds speech and actions and runs them on unpause; reloading drops queued actions. Deal clocks
  tick only when a chat line or game event reaches the server.
- Logs: prompts `log/context_sent_to_llm.log`, outputs `log/output_from_llm.log` (server; `stobe-rotate-logs` archives
  them). Game logs reset on launch: save them before relaunching.
- Crash dumps: `D:\…\Kenshi\crashDump1.0.65_x64.zip`; parse the .dmp exception + stack, map RVAs with
  `x86_64-w64-mingw32-nm -n` (ImageBase from `objdump -p`).
- WSL files can be read/edited with Read/Edit via `//wsl.localhost/DwemerAI4Skyrim3/...`.
- Fact-check NPC claims against `[EVENT]` lines: a wrong statement is a bug.

## Relationships (legacy map, still the storage REL writes to)
- Per NPC in `core_npc_master.extended_data->relationships` (copy in the `relationships` column):
  `{target: {aff -100..100, tier, type, note, updated_at}}`, one-directional.
- After each chat turn the relationship evaluator (separate OpenRouter call) may return up to 3 updates for people
  present (`allowed_targets`); normal chat stays within −8..+8. Fights are scored by the B 55 rules
  (`STOBE_full_test_plan.md` section E) and REL (`docs/REL_ARCHITECTURE.md`).
- Tier from aff: Hostile ≤−91, Hateful ≤−76, Resentful ≤−56, Cold ≤−31, Wary ≤−6, Neutral −5..+5, Acquaintance ≥+6,
  Friendly ≥+31, Fond ≥+56, Devoted ≥+76, Bonded ≥+91. Type = evaluator's word, else inferred from aff while neutral.
- No entries for unnamed template names (`data/npc_generic_templates.json`). Relationships follow the loaded save
  (`NEVER_CLEAR_RELATIONSHIP_DATA=false`, baseline snapshots at game time 0).
- NPC wealth / cap tiers research: `archive/npc-wealth-survey.tsv`, `tools/research/` (FCS reader for this load order:
  `fcs_parse.py`, `fcs_merge.py`, `npc_wealth.py`; WSL `python3`, cache `/tmp/kenshi_merged.pkl`); template money
  table `data/npc_wealth_templates.json` on the server.
