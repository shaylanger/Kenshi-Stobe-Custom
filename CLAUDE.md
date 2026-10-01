# Kenshi modding workspace (Shay)

Home folder for STOBE / KenshiFP work. The code lives elsewhere; this folder holds the notes, the test plan, pending fixes and tools.

## Machine setup (decided 2026-09-30)
- **This PC** (`DESKTOP-JFLPK99`, RTX 5090, `172.16.1.147`) runs Kenshi and the `DwemerAI4Skyrim3` distro: STOBE, Postgres, STT, Python PocketTTS and the background processor.
- **Server PC** (`DESKTOP-NQQPA73`, RTX 4080, `172.16.1.100`) will run a local LLM only, for background jobs (diary, relationships and the like). The model isn't chosen yet. Reach it with `ssh 4080` (key login).
- Dialogue (chat) runs on DeepInfra directly (connector 19, `deepseek-ai/DeepSeek-V4.1-Flash`), seen in the 2026-09-30 logs. Relationship eval still goes through OpenRouter (DeepSeek V4 Flash, pinned to Alibaba).
- Shay is setting up the environment and starting or stopping services. Don't change the runtime unless asked.
- History: on 2026-09-29 the stack briefly moved to the 4080. That was reverted (VRAM). Notes are in `two-pc-setup.md` (historical).

## Where things are
- **StobeServer (PHP):** WSL distro `DwemerAI4Skyrim3`, `/var/www/html/StobeServer` (live). The 1.3.1 merge copy is `/root/stobe-work/ss-merge`; server patches go to **both**. Run commands with `wsl.exe -d DwemerAI4Skyrim3 -u root --cd / -- bash -s` and a heredoc. Files are owned `dwemer:www-data`; don't chown.
- **Stobe.dll source:** `/root/STOBE-src` (branch `local/event-priority-debounce`). Build copy: `C:\StobeBuild\src` (copy changed files over, then build). **KenshiFP:** `/root/KenshiFP` (build `re_plugin/build.sh`, mingw in WSL).
- **Game:** `D:\Steam\steamapps\common\Kenshi`. The game loads **`Kenshi\mods\Stobe\Stobe.dll`** (a plain file since 2026-09-30, replacing a Vortex link to 1.2.3). `RE_Kenshi\mods\Stobe` holds only logs, config and test-inbox files, so a DLL copied there does nothing. KenshiFP is `Kenshi\mods\KenshiFP\KenshiFP.dll`, a Vortex symlink: install by copying over its link target. After an install, check the loaded modules on the running `kenshi_x64` (`(Get-Process kenshi_x64).Modules`). Logs: `RE_Kenshi\mods\Stobe\stobe.log`, `Kenshi\KenshiFP.log`; both reset on each launch.
- **Build Stobe.dll:** `C:\StobeBuild\build_portable.bat` (VS2010 x64 from `C:\StobeBuildTools`, cl 16.00.30319). It **must** use `/GL` + `/LTCG` (already in the script); without them KenshiLib asserts "Incorrect address in GetRealAddress" at startup. Only replace DLLs while Kenshi is closed; verify with SHA256.
- **Test plan:** `STOBE_full_test_plan.md` (only open tests and known issues). **Bug list 1–43 with fix and status:** `STOBE_bug_history.md`. Old run logs: `archive/test-run-2026-09-30*.md`.

## Tools (WSL `/usr/local/bin`; sources in `tools/`)
- `stobe-say on|off|ping|mode <m>|state <npc>|give_cats <n>|say <npc> <text…> [--wait S]`: drives the running game through Stobe.dll's test inbox (see Automated testing).
- `stobe-reset-npc <npc> [since]`: clears one NPC's server-side test state (deals, directives, memories and events since the date, and her relationship to the player). No backup: Shay OK'd this for test data.
- `stobe-session HH:MM[:SS] HH:MM|now [npc]`: summary of a play-test window (local game clock). Its conversation section sometimes misses NPC lines; `stobe-say` prints them from stobe.log.
- `stobe-tests [tree] [pattern]`: test runner on the `stobe_test` DB. Run **once, after all requested work is done**. Baseline: 52 pass, 7 known pre-existing failures.
- `stobe-rotate-logs`: run after every server deploy.
- `stobe-force-attack <npc> [help]` (TEST ONLY): queues `ATTACK@<player>` (or `@help`) for the NPC's next chat reply. Voice alone can't start a fight.
- `DELAY=2 stobe-fight-watch "<pay line>" [timeout]`: on the first attack on Shay, sends the pay line after DELAY seconds, then logs 20 s of fight lines to /tmp/fight-watch.log. Run it in the background before any fight line.
- `stobe-fight-offer "<offer line>" [npc] [timeout]`: like fight-watch, but only sends an offer (no payment) 2 s after the first attack; Claude then checks the ledger and pays. Run it in the background before `stobe-force-attack`.
- `cd /tmp && sudo -u www-data php /var/www/html/StobeServer/tools/negotiation_admin.php deals N | deal <id> | directives`: deal ledger.
- `php /root/stobe-provider-bench.php …`: replays a logged chat request against OpenRouter providers (see the script header).

## Automated testing (Claude runs tests itself)
Shay launches Kenshi, loads the clean save next to the test NPC (Malzin, Outlaw Tavern, The Hub), leaves it unpaused, and says "go". Then:
1. **Check** that both DLLs loaded (hashes below), then `stobe-say on`, `stobe-say ping`, and that Cats sync works (`CATS_SYNC … reason=update_tick` in stobe.log equals conf_opts `PLAYER_CATS`).
2. **Reset:** `stobe-reset-npc Malzin` (Shay said he doesn't care about the test data). Top up Cats with `stobe-say give_cats N`. Check both inventories with `stobe-say state Shay` / `state Malzin`. The player auto-eats food, so re-check before item deals.
3. **Run tests** one line at a time with `stobe-say say Malzin "…"`. After each line, check the reply, the deal ledger (`negotiation_admin.php deals 1`) and `state`. A pass means the game state changed correctly, not just the words.
4. **Log** every result and bug in a new dated run file (e.g. `test-run-2026-10-01.md`). At the end, remove passed items from `STOBE_full_test_plan.md`, add new bugs to `STOBE_bug_history.md` (next number: 44), then archive the run file.

How it works: the DLL polls `RE_Kenshi\mods\Stobe\test_inbox.txt` every 500 ms while `test_inbox.flag` exists. Lines go through `SubmitVoiceChatText`, the same path as push-to-talk after STT. Replies go to `test_outbox.txt`. Source patches: `pending-fixes/patch_test_inbox.py` and `patch_test_inbox_give.py` (the DLL's `give_item` exists but is unused: Shay chose not to spawn items).

**Safety (hard rules):**
- After any line that can anger the NPC (refusals, breaches, insults), grep stobe.log for `[EVENT] combat: .* -> Shay` **before the next line**. `state` isn't enough.
- If anyone attacks the player, or the player shows `flags=unconscious`, stop and tell Shay at once.
- **Fight tests need a new setup.** Claude's reaction time (checks plus 5–10 s replies) lost two fights: katana plus faction-mates knock Shay out in under 30 s. Agree the setup with Shay first (Shay on pause duty, and/or a pre-armed script that pays the moment the first attack event appears).
- Keep deal offers phrased as offers ("…Deal?"). Pay with an explicit "Here's …".
- Things that can't be triggered by voice so far: K4 (she acts in the same reply that takes the payment), K9 ("attack me": she refuses).

## Pending fixes
`pending-fixes/` holds patch scripts. Each takes a tree root and asserts its anchor, so a script that has already been applied fails. Applied so far:
- **Server** (live + ss-merge): `patch_round6`, `patch_provider_pin`, `patch_reasoning_cap`, `patch_round7`, `7b`–`7h`, `patch_round8`, `8b`, `patch_round9`, `9b`–`9e`.
- **Server** round 10 (bug 26 speech/terms amounts, bug 27 `@help`) and `10b` (money talk held back during an underway deal), `10c` (fight deals right after an attack), `11` (an NPC's own weapon: only when surrendering or trust >= `NEG_WEAPON_TRUST_MIN`, default 56), `patch_round12.py` (bugs 28–31; deployed 17:08, backup `/root/stobe-backups/round12-20260930-170841`), live + ss-merge, 2026-09-30.
- **Server** round 12 (latency, `patch_round12_latency.py`; not the same as `patch_round12.py`): one MiniMe topic call instead of two (only `topics[0]` was used); trader-inventory polling (8×100 ms) only for real traders, so "cats"-type lines to non-traders no longer wait ~806 ms. Live + ss-merge, 2026-09-30. Backup `/root/stobe-backups/round12_20260930_170142`.
- **Server** round 13 (`patch_round13_rel_player`): the NPC Relationship Affinities editor shows and edits the player's row (the old filter hid it, and saving a profile deleted it). The editor's `$data` was renamed `$relPayload`, because it clobbered the page's NPC list and caused HTTP 500 whenever a row rendered. Live + ss-merge, 2026-09-30. Backup `/root/stobe-backups/round13_20260930_170917`.
- **Server** round 13 (`patch_round13_prompt_cache`, DeepInfra caching): the chat system prompt is stable-first (roleplay, character bio, general instructions, Available Actions, then `# Current Situation` = Character State + Relationships, then knowledge, scene, negotiation, lifelike, history). Content unchanged. Setting `PROMPT_CACHE_STABLE_FIRST` (default on) switches it off. DeepInfra chat/rechat requests send `prompt_cache_key` `stobe:<npc>:chat` (probe: 200 OK, 1152/1210 cached on repeat). Live + ss-merge, 2026-09-30 17:12. Backup `/root/stobe-backups/round13_20260930_170801`. To validate: 10–20 Malzin turns, then check `cached_tokens` in `output_from_llm.log`.
- **Server** round 14 (`patch_round14_attack_help.py`, bug 39): `ATTACK@<target>@help` survives the action normalizer (the sanitizer stripped '@'). Live + ss-merge, 2026-09-30 17:40. Backup `/root/stobe-backups/round14_20260930_173954`. Verified in game (gang joined).
- **Server** round 14 (`patch_round14_audit_cache.py`, audit only): `audit_request.log` usage now has `cached_tokens`, `prompt_cache_key` and `service_tier`. The DB `audit_request.request` JSON puts small fields before `messages` (the 24,000-char cut used to drop the key), and `result` gets `cached_tokens`. Earlier the audit showed 0 cached and no key, while DeepInfra's real usage (`output_from_llm.log`) showed 16/18 Malzin turns reusing 1.4–2.6k tokens after round 13. Live + ss-merge, 2026-09-30 17:52. Backup `/root/stobe-backups/round14_20260930_175150`.
- **Server** round 15 (`patch_round15.py`, bugs 34–38, 41, 42): after a voice hand-over the chat request ticks the deal (≤4 s) so her side goes out the same turn (34); the progress amount check allows amounts the player just said and drops only wrong sentences (35); "<number> … deal" / "<number> then" is an offer (36); COUNTER/PROPOSE/ACCEPT with unreadable terms gets a next-turn reminder (37); "squadmate" only from a squad member's view (38); combat pay windows need game time too (`STOBE_NEG_PAY_WINDOW_GAMETS` 1950 ≈ 60 s at 1x; 30 min real-time cap) (41); pending directive instructions go into the chat prompt (42). Unit tests `pending-fixes/r15_unit*.php` (18 pass). Live + ss-merge, 2026-09-30 17:54. Backup `/root/stobe-backups/round15_20260930_175412`.
- **Server** round 16 (`patch_round16.py`, bug 43): combat-deal prompt rules say her faction-mates stand down with her (she can call them off). Live + ss-merge, 2026-09-30 18:23. Backup `/root/stobe-backups/round16_20260930_182346`.
- **DLL** (`/root/STOBE-src`): `patch_test_inbox`, `patch_test_inbox_give`, `patch_dll_round7`, `patch_dll_round8`, `patch_dll_round9`, `patch_dll_round9b`, `patch_dll_round15` (bug 40: the personal truce guard also stands down her faction-mates targeting the player; **installed** `236C3F2C…` 2026-09-30 (previous DLL saved as `C:\StobeBuild\out\Stobe.dll.prev_7EF3EEFD`); backup `/root/stobe-backups/dll_round15_20260930_175435`).
- **KenshiFP** (`/root/KenshiFP`): `patch_kfp_round8`, `patch_kfp_round17` (bug 44), `patch_kfp_round17b` (return to player), `17c` (bug 47 input hauling), `17d` (bug 48 machine switch). Backup `/root/stobe-backups/kfp_round17_20260930_185628`.
- **Server** round 17 (`patch_round17.py`, bug 45: stored-serial fallback for goal queues), `17b` (bug 46: faction members get `<player_base>` from server presence), `17c` (RESUME restarts BLOCKED work goals). Live + ss-merge, 2026-09-30 19:00–19:13. Backups `/root/stobe-backups/round17*_20260930_*`.
- **DLL** `patch_dll_round17` (test inbox `speed`), `17b` (bug 49 inbox speaker), installed `81964C7C…`. Backup `/root/stobe-backups/dll_round17_20260930_191158`.

Backups are in `/root/stobe-backups/` (no DB backups: Shay doesn't want them).

## Current state (2026-09-30, run 4 in progress: work/task goals at Home)
- **Installed:** Stobe.dll `81964C7C…` (round 17 `speed` + 17b inbox speaker fix; previous copies `Stobe.dll.prev_*` in `C:\StobeBuild\out`), KenshiFP.dll `D565F854…` (round 17 stall fix, 17b walk back to player, 17c input hauling, 17d machine switch; previous copies `.prev_*` next to the Vortex target). NOTE: KenshiFP compiles `client/stobe_task_goals.inc`; `stobe_task_goals_stage.inc` is an unused copy. The server has everything up to round 17c (live + ss-merge). Run log: `test-run-2026-09-30-r4.md`.
- `stobe-say speed <x>` sets game speed (0 = pause, 0.5–10). Use 5x for slow goals; drop to 1x (or pause) before anything risky.
- **Malzin's relationship to Shay is +60 Fond/friend** (set by hand for the bug 41 test). Run `stobe-reset-npc Malzin` before tests that need her neutral.
- **Next:** work from `STOBE_full_test_plan.md` (only open items): section 1 first (42 needs a real breach, 43, 35/37/38), then section 2. Then Shay's design notes below.
- Three automated runs on 2026-09-30 found bugs 1–43; status of each is in `STOBE_bug_history.md` (full run logs in `archive/`).

### To look into later (Shay's design notes, 2026-09-30; not started)
- **Relationship should shape everything she does.** First check whether the player→NPC relationship (affinity, tier, type) reaches the LLM prompt at all, and how prominently. Example: Malzin is at −64 "Resentful", type "rival", yet she took 39,000 Cats of deals, disarmed for 10,000 and was happy to bargain. At that level she shouldn't trust the player, shouldn't follow any of his commands, should be suspicious of every deal, and should charge more or just refuse. Idea: deal pricing and willingness scale with the tier, plus hard server rules like round 11's weapon rule (e.g. no pay-after-delivery deals and no favours below some tier).
- **Tasks and goals only for the player's own faction.** A random NPC shouldn't take orders like "make me 5 bread" or "loot that corpse". Minor requests like "follow me" might work for a non-member who trusts the player enough, or who is paid an amount they think is fair (i.e. through a deal). Check where task and goal actions are allowed today, and gate them on `npcIsInPlayerFaction` plus trust/deal for the minor ones.

### Other open items
- Pick the 4080 background LLM and point the diary, relationship, dynamic and middle-term connectors at it.
- The 4080's StobeServer copy may differ from this PC's (latency logging, game state from 09-29). Check with Shay before relying on it.
- Minor: some GIVE_ITEM hand-overs are logged as "transferred" but dropped (round 9 now logs `dropped_at_feet` and tells the player). The model sometimes writes deal_terms as text or prose (now parsed strictly).

## Working rules
- Keep reads and outputs small (grep/tail, never whole logs). Batch commands. If the permission check fails twice, stop and tell Shay; it's a transient checker error, so say that, and retry when he says continue.
- Back up code (not the DB) before changing anything, stage, `php -l`, test the logic standalone, deploy to live and ss-merge, run `stobe-tests` once at the end, rotate logs.
- Replace DLLs only while Kenshi is closed; verify with SHA256 and the loaded-module check.
- **Test reports from Shay:** he gives the time and NPC name. Use `stobe-session`, not diagnostics files.
