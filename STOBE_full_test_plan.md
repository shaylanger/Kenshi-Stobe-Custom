# STOBE: open issues and tests left

Last updated 2026-10-02 (run 12). Installed: Stobe.dll `526D69F1`, KenshiFP `D3C78B3D`; server through round 24 (`b375e2b`).
This list holds **only** open items. Everything fixed and confirmed is gone (history: `archive/STOBE_bug_history_old_numbers.md`, run logs `archive/test-run-*.md`).

**Numbering restarted on 2026-10-02:** items are numbered 1, 2, 3… here. "was N" is the old bug number (still used in commit messages and code comments). The next new item is **54**.

**How to report:** tell me roughly when (your clock) and which NPC, e.g. "Malzin around 11:02, she didn't take the vest off". Send it **before relaunching Kenshi** (logs reset on launch).

## A. Needs Shay (eyes, hands or first-person mode)

| # | What to do | Expect |
|---|---|---|
| 1 (was 79) | FP mode: look at Malzin and left-click; then click her portrait | You stay Shay and **her** details open; log `[fp] look-at click … kept control (bug 79)`. Portrait still switches to her. Code is in the installed KenshiFP |
| 2 (was 100) | FP mode: pick up an NPC, press G | The NPC is put down; log `put down: dropCarriedObject called`. Code is in the installed KenshiFP |
| 3 (was 103) | Talk to Malzin, then buy food from a **friendly** trader | The purchase event names the trader as seller, never Malzin. Code is in the installed Stobe.dll |
| 4 (was 51) | "Malzin, fetch the mead" with her far from the chest | She walks to the chest (step "Walking to …") instead of taking it from afar |
| 5 (was 74) | "Make 2 building materials" with Malzin **selected** | The job list switches Stone Mine ↔ Manual Stone Processor by itself; log `GOAL_JOB ui refresh replayed selection`, no `faulted` |
| 6 | Goal label: give her a job of your own, then a goal; select her; let a goal block/finish; select Shay; FP and 3rd person | Your job stays; label "Malzin - Make 2 Building Material (1/2)" + step; BLOCKED/DONE for 60 s; hidden for Shay; `GOAL_LABEL widget created`, no `faulted` |
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

| # | Bug | Notes |
|---|---|---|
| 41 | She claims something false about her gear | Run 12: right after re-equipping her katana: "You've got my larder and my blade both" (the prompt listed the katana under Equipment) |
| 43 | A two-part order does only one part | `max_actions = 1`: "give me all your bread and all your dried meat" gave only the bread, while she said "You took my food". Fix or design call: allow 2 hand-overs, or make her say she does one |
| 48 | A dying or dead NPC negotiates | Run 12: a raider hit by `stobe-auto kill` (dying) proposed a deal 19 s later, died, and his COUNTER came 2 s after death. Needs a rule: no deal talk once dying/dead |
| 53 | The Cats cap comes out as a lie | Run 12: a raider with 10,000 Cats, capped at 300 (design), said "I don't have 350 cats. Never did." The prompt should let her refuse without claiming to be broke |

## E. Design questions and features

- **Stowed weapons (Shay, 2026-10-02):** an NPC must not stow or drop her weapon unless she really trusts Shay, is in Shay's faction, or is surrendering. (Re-drawing in a fight is not needed.) To build: guard on UNEQUIP/DROP_WEAPON/SHEATHE-to-pack for outsiders.
- **Goal panel (Shay, 2026-10-02): BUILD IT.** when Malzin has a goal ("make bread"), show a small UI element above the jobs area with the goal's info, instead of the current top-centre label.
- **Relationship shapes everything (Shay, 2026-10-02: wanted):** deal pricing and willingness by tier; hard rules like no pay-after deals and no favours below some tier. **And how they talk to Shay**, as a heavy weight on every reply, using the tier *and* the type (the STOBE UI has many types: romantic, crush, ex, familial, rival, nemesis, fearful, admirer, …):
  - hates Shay ("Hey, how are you?") → "Leave me alone" / "Go away"; hated enough: threats, maybe picks a fight;
  - likes Shay → warm, shows it ("Hey, I've missed you. I'm doing great now that you're here");
  - loves / in a relationship → more inclined to say romantic things, that she cares, that she loves Shay.
  (Examples only.) Today the chat prompt just lists `## Relationships` as "Shay - Neutral (neutral)" plus one generic rule ("Let established relationships affect warmth, teasing, trust…"), so the effect is weak.
- **How are relationships created and typed? (Shay, 2026-10-02, design question)** Findings (run 12):
  - **Storage:** per NPC in `core_npc_master.extended_data->relationships` (a second copy in the `relationships` column): `{target: {aff -100..100, tier, type, note, updated_at}}`. One-directional: Malzin→Shay and Shay→Malzin are separate entries.
  - **When an entry is made/changed:** after each chat turn and game event the server runs a separate "relationship evaluator" call (OpenRouter `deepseek-v4-flash`, after she has spoken since 5f138be): it sees the speaker, listener, the line, her reply and her current map, and may return up to 3 updates (`aff_delta`, optional `type`, short `note`) for people present (`allowed_targets`). Normal chat is told to stay within −8..+8. An entry appears the first time anyone gets a non-empty update, starting from 0. NPC↔NPC entries come from the same call on bored/combat chatter (that's where Malzin's bandit entries come from). There is also a one-off "Build with AI" analysis (NPC Master page).
  - **Tier** = fixed scale from aff: Hostile ≤−91, Hateful ≤−76, Resentful ≤−56, Cold ≤−31, Wary ≤−6, Neutral −5..+5, Acquaintance ≥+6, Friendly ≥+31, Fond ≥+56, Devoted ≥+76, Bonded ≥+91.
  - **Type** = what the evaluator says, else inferred from aff only while still "neutral" (≥+6 platonic, ≤−6 wary, ≤−30 rival, ≤−55 enemy); type changes are meant for defining moments only (romance, betrayal, violence, marriage, family).
  - **Malzin now:** → Shay 0..−2 "Neutral (neutral)", note "refused to sell katana"; Shay → Malzin +3 Neutral. → bandits: Boss Madoc −6 Wary (rival) "threatens Boss Madoc after a hit", Ulan [Dust Bandit] −11 Wary (rival) "taunted about crew's defeat", Vren [Dust Bandit] +6 Acquaintance (neutral) "No hard feelings after the fight", Dust Bandit Bowman +2 Neutral (acquaintance) "Considered execution", Hesk +0 "Accepted payment and issued warning", … (14 entries, all from run 11/12 test fights).
  - **Why she's only Neutral with Shay:** the test runs reset her with `stobe-reset-npc` (live DB, no backup, by agreement). Before that she was Fond/Devoted (ally) in run 8 prompts and 96 Bonded in run 11. **Decide:** restore her to Bonded, and should tests use a copy instead of the live relationship?
  - **Problems seen:** types outside the list appear ("annoyed", "ally", "distrust", "acquaintance"); the analysis prompt still has Skyrim examples ("Imperial → Stormcloak"); generic names ("Hungry Bandit", "Dust Bandit Bowman") get entries that later match any NPC of that kind.
- **Deal-offer cap tiers (Shay, 2026-10-02):** replace common 300 / leader 1000 / wealthy with 6 tiers from the game data (`archive/npc-wealth-survey.tsv`, `tools/research/npc_wealth.py`); proposal in the run 12 chat, waiting for Shay's OK.
- **Decided for D 43 / 48 (Shay):** 43: do both hand-overs (fallback: she says she does one). 48: dying but conscious may deal; unconscious or dead may not; a deal interrupted by a KO resumes when they wake.

---

## Before you start
- Goal rows: the save at Shay's outpost **Home** (Malzin in the squad, faction "Nameless"); negotiation rows: any save with Malzin. Say the NPC's name in your first line to them.
- **Fights only with the fight setup:** Shay on pause duty, a watcher armed **before** the attack, fight started with `stobe-force-attack Malzin [help]`. Watchers: `DELAY=2 stobe-fight-watch "<pay line>"` pays by itself; `stobe-fight-offer "<offer line>"` only sends an offer.
- **Pause behaviour:** while paused, STOBE holds speech and actions and runs them on unpause. Reloading a save drops queued actions. Deal clocks tick only when a chat line or game event reaches the server.
- **Trust for a test:** `bash tools/automation/scenarios.sh trust "<npc name>" 60 Fond` (WSL); `stobe-reset-npc <npc>` clears it (tiers: 56 Fond, 31 Friendly, −56 Resentful).
- **Safety:** if any NPC is harmed or knocked out by an action, or Shay goes down, stop.
- Deal ledger: `cd /tmp && sudo -u www-data php /var/www/html/StobeServer/tools/negotiation_admin.php deals 3` (`deal <id>`, `directives`). KenshiFP results: `Kenshi\KenshiFP.log` (`[stobe]` lines).

## Switches
If a phase misbehaves: `… phase <2-8> off`. Voice payment: `NEGOTIATION_VOICE_PAYMENT`. Trust for free gifts: `GIFT_TRUST_THRESHOLD` (56 = Fond). Trust to give up her own weapon: `NEG_WEAPON_TRUST_MIN` (56). Trust for minor orders from non-faction NPCs: `MINOR_ORDER_TRUST_MIN`. STOBE ini: `Speed Dialogue` (0 = TTS at 1x), `TTSVolume` (0–200), `TTSFadePercent` (25–400).
