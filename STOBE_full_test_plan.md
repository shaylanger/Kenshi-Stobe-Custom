# STOBE: open issues and tests left

Last updated 2026-10-02 (round 26: D 41/43/48/53 fixed, cap tiers built). Installed: Stobe.dll `FF633947` (items 48 + cap tiers + harness bridge), KenshiFP `4D04FC9C` (goal panel). Server: round 26 (`5f71138`, live + ss-merge). `NEG_CATS_PURSE_MODES` is on.
This list holds **only** open items. Everything fixed and confirmed is gone (history: `archive/STOBE_bug_history_old_numbers.md`, run logs `archive/test-run-*.md`).

**Numbering restarted on 2026-10-02:** items are numbered 1, 2, 3… here. "was N" is the old bug number (still used in commit messages and code comments). The next new item is **67**.

**How to report:** tell me roughly when (your clock) and which NPC, e.g. "Malzin around 11:02, she didn't take the vest off". Send it **before relaunching Kenshi** (logs reset on launch).

## A. Needs Shay (eyes, hands or first-person mode)

| # | What to do | Expect |
|---|---|---|
| 1 (was 79) | FP mode: look at Malzin and left-click; then click her portrait | You stay Shay and **her** details open; log `[fp] look-at click … kept control (bug 79)`. Portrait still switches to her. Code is in the installed KenshiFP |
| 2 (was 100) | FP mode: pick up an NPC, press G | The NPC is put down; log `put down: dropCarriedObject called`. Code is in the installed KenshiFP |
| 3 (was 103) | Talk to Malzin, then buy food from a **friendly** trader | The purchase event names the trader as seller, never Malzin. Code is in the installed Stobe.dll |
| 4 (was 51) | "Malzin, fetch the mead" with her far from the chest | She walks to the chest (step "Walking to …") instead of taking it from afar |
| 5 (was 74) | "Make 2 building materials" with Malzin **selected** | The job list switches Stone Mine ↔ Manual Stone Processor by itself; log `GOAL_JOB ui refresh replayed selection`, no `faulted` |
| 6 | Goal panel: give Malzin a goal ("make 2 building materials"), select her; then select Shay; open the inventory/map | A small framed panel right **above the job list**, as wide as it: "Malzin - Make 2 Building Material  1/2" + the current step (+N more queued); BLOCKED/DONE for 60 s; hidden for Shay and when the HUD job list is hidden. Log `GOAL_PANEL created at x,y wxh (jobs widget)` (not `layout fallback`), no `faulted`. KenshiFP `4D04FC9C` |
| 7 | Fill your pack, then "Malzin, give me one of your bread" | On-screen message "No room in Shay's pack: dropped at their feet." (run 11: the drop and its event are verified; the message itself only shows on screen) |
| 8 (was 69, 70) | Power the Grain Silo (it has no power in the test save), water the farm, then "Malzin, make 2 bread" at 50x | Water only from the well (never out of the oven), wheat → silo, flour → oven, COMPLETE 2/2; "Waiting for Wheat Farm … to grow" while growing; a dry farm blocks after ~60 s |
| 9 | STOBE Settings window: TTS Volume row | Two boxes: Volume 0–200, Fade 25–400; saved to `StobeCustom.ini` (`TTSVolume`, `TTSFadePercent`) and kept after a relaunch |
| 10 | Mid-fight, heal someone (or hand them an item), then talk without mentioning it | They already know ("thanks for patching me up") |
| 11 | "Senlin, what if I bandage you up and you give me your rags?" Heal her, say nothing | She hands the rags over on her own; deal completes |
| 12 | Same, but after she hands over first: "I'm not going to heal you" | You broke the deal; she doesn't say "we're square" |
| 13 | After a long fight, ask about something from earlier in it | She still remembers it |

## B. Needs a specific game state or situation (automatable once it exists)

| # | Situation | Expect |
|---|---|---|
| 14 | A friendly trader nearby: "Buy 3 bread from the trader" | She walks there and really buys them |
| 15 | A goal needing something only a trader has | WAITING_APPROVAL; approve → buys; decline → cancelled |
| 16 | A goal needing a crafted ingredient at a bench | The bench queue grows only by what's missing |
| 17 | Break 2+ deals so broken > kept (now 45 kept / 10 broken), then talk to a new NPC | She mentions your reputation ("word gets around"). Tried run 12 (counts set to 1/5): the prompt had "Word gets around: Shay has a reputation for breaking deals." every time, but 3 NPCs never voiced it |
| 18 | Betrayal: a dishonest NPC who dislikes you, a deal with payment first | They attack after you pay; BREACHED_NPC, marked intentional (rare by design) |
| 20 | Refuse to pay after she's handed something over (fight setup) | She may threaten or attack; paying then stops it and the stop holds. Tried run 12: spawned raiders always want Cats first ("You pay first, then we talk about the bow"), 2 tries; needs Malzin's force-attack setup or a trader |
| 21 (was 42) | Fight setup, Fond trust, she stops for pay-later; don't pay for 1+ game minute | BREACHED_PLAYER, an angry line that matches her attack (no "cats received"), log `breach_react`. Tried run 12: a raider at Fond 60 refused pay-later 3 times ("After is where men die"). The unit check "unpaid -> BREACHED_PLAYER" is stale: hostile deals expire on game time, the test only backdates wall time |
| 22 (was 43) | Fight setup with `help`; she stops for pay | Her words don't say her gang "isn't hers to call off"; the gang stands down. Run 12 (gang of 3 raiders, paid 1000): words fine ("You're paying the whole gang"), deal COMPLETE, no fighting after; but the gang stood down only because gang-mate Yarel's own surrender offer sent a faction STOP_ATTACK. The paid deal itself sends only an individual STOP_FIGHT for the payee |
| 54 | Relationship talk (StobeServer f83a3fb): `scenarios.sh trust Malzin -80 Hateful enemy`, "Malzin, hey, how are you?"; then 60 Fond; then `scenarios.sh trust Malzin 96 Bonded romantic` | Prompt has `<how_you_feel_about_them>` with the tier/type each time; hated: rude/"leave me alone"/a threat (an outsider at Hateful/Hostile may even attack; a squadmate never does); Fond: warm, glad to see you; romantic: loving words. Unit-tested (tests/relationship_stance_regression.php) |
| 55 | Fights count (R4): duel a named raider (`scenarios.sh duel`) | Server log `Relationship: a fight counts (R4)`; the raider's entry for Shay drops by 10 (her entry for him by 4 if she attacked); only once per pair per 15 min |
| 56 | Relationship types (R1): a few chats that change a relationship | New entries only use list types (no "annoyed"/"ally"); an odd type never turns "romantic" into "neutral" |
| 57 | Generic names (R3): talk to / fight an unnamed "Hungry Bandit" | No relationship entry keyed "Hungry Bandit"; named ones ("Ket [Hungry Bandit]") still get entries |
| 58 | `stobe-reset-npc Malzin`, then `stobe-reset-npc --restore Malzin` | First reset prints `saved Malzin -> Shay: …`; restore puts the same entry back (one "Shay" key, no "shay" duplicate) |
| 59 | Relationships follow the save: in a test save, make Malzin hate Shay (`scenarios.sh trust Malzin -80 Hateful enemy` writes no snapshot, so use a real fight or a few insults at game time T), save nothing, then load a save from before T | Server log `PLAYTHROUGH: restored relationship timeline state` with `restored` ≥ 1; Malzin → Shay back to the value at that save (96 Bonded on the auto-home fixture); NPCs first met after that save have no entry. Unit-tested (tests/relationship_rollback_regression.php) |
| 41 | False gear claim (StobeServer 51bc0cb): Malzin re-equips her katana ("put your katana back on"), then a gear exchange ("give me all your dried meat"), then "What have I taken from you?" | She never says Shay has her katana while it's in her Equipment. If the model writes it: server log `False gear claim not spoken (item 41)` and the sentence is missing from her bubble (stobe.log NPC_SAY) |
| 43 | Two-part hand-over (StobeServer c87e552): give Malzin bread and dried meat (`stobe-auto give Malzin Bread 2`, `… "Dried Meat" 5`), then "Malzin, give me all your bread and all your dried meat." Then again with "…but keep the meat" style refusal from her side | Both arrive (`stobe-auto inv Shay`; KenshiFP/stobe.log GIVE_ITEM ×2). When her reply carried one, server log `Two-part hand-over: missing GIVE_ITEM added (item 43)`. An item her reply keeps ("the meat stays") is not handed over |
| 48 | KO / death during a deal (StobeServer 5aaba07; Stobe `FF633947`): (a) `scenarios.sh surrender`, let the raider propose, then `stobe-auto ko <raider>` before answering; wait until he wakes. (b) Talk deal with a raider, `stobe-auto kill` him right after your line | (a) No deal line or COUNTER while he's KO (a late one: stobe.log `NPC_SAY dropped: speaker is dead or unconscious (item 48)`); the offer stays PROPOSED/COUNTERED (`negotiation_admin.php deals 3`); on waking server log `Deal resumes after a knockout (item 48)` and he brings the offer up again. (b) No line or recorded deal after his `[EVENT] death` (server log `Deal reply from a knocked-out or dead NPC dropped (item 48)` if the reply came back late). Dying but conscious may still talk |
| 53 | Cap without a lie (StobeServer 5f71138): `scenarios.sh surrender` (Dust Bandit), ask for more than he offers ("Make it 350") | He refuses or counters at his limit, never "I don't have 350"/"never did" when he has money. His prompt line: "the most you will pay in a deal is N" |
| 60 | Cap tiers 0–2 (StobeServer 5f71138; Stobe `FF633947`, `NEG_CATS_PURSE_MODES` on): `scenarios.sh surrender` with a Dust Bandit (tier 1) and a Hungry Bandit (tier 0) | Offers ≤ min(300 / 100, carried); carried ≤ template max (Dust Bandit 200) even with a big squad purse; terms have `"purse":"exact"`; payment dispatched as `GIVE_CATS@Shay@N@exact`. If he can't pay all: stobe.log `GIVE_CATS … skipped reason=insufficient`, term IMPOSSIBLE (no part payment) |
| 61 | Cap tiers 3–5 (same builds): spawn a Samurai Sergeant (tier 3) or Dust King (tier 4) with few Cats, beat him until he offers; accept; then a second deal with him | First offer can go up to 10,000 / 50,000 (above what he carries), term `"purse":"topup"`; on payment stobe.log `GIVE_CATS topup … added=` and Shay gets the full amount. Second deal within 3 game days: he offers only what he carries (no top-up) |

## C. Can't reproduce so far (fixed or built, never triggered in game)

| # | What would show it | Expect | Tried |
|---|---|---|---|
| 25 (was 128) | A surrender offer from a raider who gets **named** mid-fight | Server log `Directive follows the NPC's new name`; offer arrives | Spawned raiders are named before any offer (run 10). Run 12: no `Directive follows` line in ~10 fights |
| 26 (was 30) | She says "Fine…" but the ledger shows nothing | Log `NPC agreed in words but recorded no deal`; the next line records ACCEPT | Every clear offer got a proper decision (run 12 too) |
| 27 (was 37) | A COUNTER with no terms (log `invalid_terms_json`) | Next turn she's reminded and restates it with terms | Never happened (run 12: none in ~40 deal turns) |
| 28 (was 31) | "Take off X" during a deal | Recorded as UNEQUIP, not a hand-over | Tried run 12: Malzin refused both (iron hat for 50, sandals for 200), no terms |
| 29 (was 35) | She misquotes an amount in a longer reply | Only the wrong sentence is rewritten, not the whole reply | Run 12: 8 rewrites, all from the first number on (held-back streaming); 4 were false alarms, now item 51 |
| 30 (was 38) | A non-member's prompt | No "Shay \| squadmate" line | Never seen (run 12: 0 in all of today's prompts) |
| 31 | Counter-offers like "300 now, 200 after?" where she misquotes | Amounts rewritten; log `Negotiation speech amounts differ` | She never misquoted (run 12: "300 now, 200 after" countered with the same numbers) |
| 32 | A REJECT that names her own price ("2000 for the hat") | Recorded as COUNTER (fixed run 11, unit-tested) | The model chose COUNTER by itself in run 11; run 12 "5 cats" got a plain REJECT |
| 33 | Pay for something she can't do, and she agrees | Deal fails and your Cats come back | She always says she can't (refund itself works); run 12: "carry me to the Hub", "build a house now" both refused |
| 34 | One-on-one fight where a faction-mate joins uninvited | `PERSONAL_FIGHT: stood down joiner=…` within ~0.25 s | Nobody joined so far |
| 35 | She agrees to sell/stow her weapon without Fond trust | "Not my Chisa Katana…", log `NPC would give up her weapon` | She refuses on her own (run 12: 3000 and 5000 Cats, refused) |
| 36 | Haggle back and forth more than 6 times | She ends the talks | Run 10: accepted at round 2 (unit-tested). Run 12: 8 rounds with a raider, but every ACCEPT starts a new deal, so rounds never passed 2 |
| 37 | A neutral NPC losing a fight near Shay | They ask for help, maybe with a reward | Run 10: spawned victim wandered off |

| 44 | A Cats term recorded the wrong way round (her words/action say she pays) | Turned round: her GiveCats action, "you give me N", or the deal on the table (log `Negotiation term fixed`) | Run 12: the first two rules fixed it in game; the third ("350 and you go free") unit-tested only; the model keeps finding new wordings |
| 45 | An extra 0-Cats term in her terms | Dropped (log `0 Cats (item 45)`); deal recorded | Unit-tested |
| 47 | An action target by a shared name with a corpse of that name nearby | The living NPC is chosen (Stobe `526D69F1`) | Built; scenarios no longer leave corpses, so not re-seen |
| 49 | Pay an NPC who was named after the deal | Payment VERIFIED, and only for that NPC's deal (serial-pinned) | Part 1 seen in game (1000 Cats verified); part 2 (serial pin) unit-tested |
| 51 | She repeats your offer, then names hers | Her reply is kept, no "My terms:" rewrite | Unit-tested |
## D. Open bugs (known broken, not fixed)

None open. 41, 43, 48, 53 fixed 2026-10-02 (round 26): test rows in B.

| # | Bug | Notes |
|---|---|---|
| 64 | `stobe-tests` negotiation_engine fails 2 checks: "unpaid -> BREACHED_PLAYER" backdates wall time, but hostile deals expire on game time (stale test); "breach reaction queued" depends on it | Fix the test (backdate game time), not the engine |
| 65 | Goal panel covers the Money/Day/speed box when a goal NPC is selected (2560x1440, run m1): panel at 2086,1127 466x62 overlaps `TimeMoneyPanel` 2185,1096 268x88 | KenshiFP `stobe_task_goals.inc` `goal_panel_rect`: place it above the TimeMoneyPanel (or left of it) |
| 66 | "Malzin, make 2 building materials" -> "I do not know how to reach Home" (run m1): `player_bases`/`player_base_locations` empty; a load of an older-game-time save (other fixtures) prunes bases with `first_game_ts > cutoff`, and Stobe doesn't re-detect Home (`ResolvePlayerOwnedTown` finds no player town at the auto-home position) | server `work_goal_functions.php` resolver + `playthrough_rollback.php`; Stobe `PlayerBaseState.cpp` |

## E. Design questions and features

- **Stowed weapons (Shay, 2026-10-02):** an NPC must not stow or drop her weapon unless she really trusts Shay, is in Shay's faction, or is surrendering. (Re-drawing in a fight is not needed.) To build: guard on UNEQUIP/DROP_WEAPON/SHEATHE-to-pack for outsiders.
- **Relationship shapes everything (rest):** deal pricing and willingness by tier; hard rules like no pay-after deals and no favours below some tier. (How she *talks* by relationship is built, see B 54.)
- **How are relationships created and typed? (Shay, 2026-10-02, design question)** Findings (run 12):
  - **Storage:** per NPC in `core_npc_master.extended_data->relationships` (a second copy in the `relationships` column): `{target: {aff -100..100, tier, type, note, updated_at}}`. One-directional: Malzin→Shay and Shay→Malzin are separate entries.
  - **When an entry is made/changed:** after each chat turn and game event the server runs a separate "relationship evaluator" call (OpenRouter `deepseek-v4-flash`, after she has spoken since 5f138be): it sees the speaker, listener, the line, her reply and her current map, and may return up to 3 updates (`aff_delta`, optional `type`, short `note`) for people present (`allowed_targets`). Normal chat is told to stay within −8..+8. An entry appears the first time anyone gets a non-empty update, starting from 0. NPC↔NPC entries come from the same call on bored/combat chatter (that's where Malzin's bandit entries come from). There is also a one-off "Build with AI" analysis (NPC Master page).
  - **Tier** = fixed scale from aff: Hostile ≤−91, Hateful ≤−76, Resentful ≤−56, Cold ≤−31, Wary ≤−6, Neutral −5..+5, Acquaintance ≥+6, Friendly ≥+31, Fond ≥+56, Devoted ≥+76, Bonded ≥+91.
  - **Type** = what the evaluator says, else inferred from aff only while still "neutral" (≥+6 platonic, ≤−6 wary, ≤−30 rival, ≤−55 enemy); type changes are meant for defining moments only (romance, betrayal, violence, marriage, family).
  - **Malzin now:** → Shay 0..−2 "Neutral (neutral)", note "refused to sell katana"; Shay → Malzin +3 Neutral. → bandits: Boss Madoc −6 Wary (rival) "threatens Boss Madoc after a hit", Ulan [Dust Bandit] −11 Wary (rival) "taunted about crew's defeat", Vren [Dust Bandit] +6 Acquaintance (neutral) "No hard feelings after the fight", Dust Bandit Bowman +2 Neutral (acquaintance) "Considered execution", Hesk +0 "Accepted payment and issued warning", … (14 entries, all from run 11/12 test fights).
  - **Why Vren became an Acquaintance after a fight:** the evaluator only ran when someone spoke and saw one line; combat events never counted. After the fight Vren said something friendly → +6 "No hard feelings after the fight". Fixed (R4, below).
  - **Why she was only Neutral with Shay:** the test runs reset her with `stobe-reset-npc` (live DB). Loading an older save did not bring relationships back then (`NEVER_CLEAR_RELATIONSHIP_DATA` = true). **Since 2026-10-02 relationships follow the loaded save** (StobeServer 78243b0, 28dff99; baseline snapshots at game time 0 for 61 NPCs; test B 59). Restored by hand to 96 Bonded (platonic) on 2026-10-02; `stobe-reset-npc` now saves the entry first and `--restore` puts it back.
  - **Fixed 2026-10-02 (StobeServer 956000f, e714b66, 43a5516, 9839389):** R1 types mapped onto the official list (unknown type keeps the old one); R2 Kenshi examples in the analysis prompt fallback; R3 no entries for unnamed template names (5 existing ones removed, backup `/root/stobe-backups/relationships_pre_r25_cleanup.tsv`); R4 a fight lowers both sides (victim −10, attacker −4, once per pair per 15 min). Tests: B 55–57. R4 (the fight rule) is up for a deep analysis: `handoff/relationship-fights-context.md`.

## F. Next big things

| # | What | Notes |
|---|---|---|
| 62 | Decouple our logic from KenshiFP | We started by tacking our features onto KenshiFP, and a lot now lives there that shouldn't (e.g. work planner `client/stobe_work_planner.inc`, task goals `client/stobe_task_goals.inc` + goal panel, GIVE_ITEM/BODYGUARD handling). Goal: KenshiFP holds only FP-mode logic; the rest moves into Stobe or a new mod, whichever fits each piece |
| 63 | Pick the next big feature | Go through the big features list (`KENSHI_BIG_MOD_IDEAS_CONTEXT.md`, `PROFESSION_GEAR_PROGRESSION_MOD_CONTEXT.md`) and start on the next big item |

---

## Before you start
- Goal rows: the save at Shay's outpost **Home** (Malzin in the squad, faction "Nameless"); negotiation rows: any save with Malzin. Say the NPC's name in your first line to them.
- **Fights only with the fight setup:** Shay on pause duty, a watcher armed **before** the attack, fight started with `stobe-force-attack Malzin [help]`. Watchers: `DELAY=2 stobe-fight-watch "<pay line>"` pays by itself; `stobe-fight-offer "<offer line>"` only sends an offer.
- **Pause behaviour:** while paused, STOBE holds speech and actions and runs them on unpause. Reloading a save drops queued actions. Deal clocks tick only when a chat line or game event reaches the server.
- **Trust for a test:** `bash tools/automation/scenarios.sh trust "<npc name>" 60 Fond` (WSL); `stobe-reset-npc <npc>` clears it (tiers: 56 Fond, 31 Friendly, −56 Resentful).
- **Safety:** if any NPC is harmed or knocked out by an action, or Shay goes down, stop.
- Deal ledger: `cd /tmp && sudo -u www-data php /var/www/html/StobeServer/tools/negotiation_admin.php deals 3` (`deal <id>`, `directives`). KenshiFP results: `Kenshi\KenshiFP.log` (`[stobe]` lines).

## Switches
Relationships: `RELATIONSHIP_STANCE` (how she talks by relationship, on), `RELATIONSHIP_FIGHTS_COUNT` (R4, on), `NEVER_CLEAR_RELATIONSHIP_DATA` (false = relationships follow the loaded save).
Deals: `NEG_CATS_PURSE_MODES` (cap tiers: send GIVE_CATS `@topup`/`@exact` to Stobe.dll; needs Stobe `FF633947`+; on since 2026-10-02).
If a phase misbehaves: `… phase <2-8> off`. Voice payment: `NEGOTIATION_VOICE_PAYMENT`. Trust for free gifts: `GIFT_TRUST_THRESHOLD` (56 = Fond). Trust to give up her own weapon: `NEG_WEAPON_TRUST_MIN` (56). Trust for minor orders from non-faction NPCs: `MINOR_ORDER_TRUST_MIN`. STOBE ini: `Speed Dialogue` (0 = TTS at 1x), `TTSVolume` (0–200), `TTSFadePercent` (25–400).
