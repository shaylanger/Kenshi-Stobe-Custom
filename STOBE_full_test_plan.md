# STOBE: open issues and tests left

Last updated 2026-10-02 (run 11). Installed: Stobe.dll `D7DA294A`, KenshiFP `F7935763`; server through round 23.
This list holds **only** open items. Everything fixed and confirmed is gone (history: `archive/STOBE_bug_history_old_numbers.md`, run logs `archive/test-run-*.md`).

**Numbering restarted on 2026-10-02:** items are numbered 1, 2, 3… here. "was N" is the old bug number (still used in commit messages and code comments). The next new item is **41**.

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
| 17 | Break 2+ deals so broken > kept (now 39 kept / 10 broken), then talk to a new NPC | She mentions your reputation ("word gets around") |
| 18 | Betrayal: a dishonest NPC who dislikes you, a deal with payment first | They attack after you pay; BREACHED_NPC, marked intentional (rare by design) |
| 19 | Deal talk with NPC A while NPC B stands nearby; then talk to B | B doesn't act as if you'd asked him; may mention he overheard |
| 20 | Refuse to pay after she's handed something over (fight setup) | She may threaten or attack; paying then stops it and the stop holds |
| 21 (was 42) | Fight setup, Fond trust, she stops for pay-later; don't pay for 1+ game minute | BREACHED_PLAYER, an angry line that matches her attack (no "cats received"), log `breach_react` |
| 22 (was 43) | Fight setup with `help`; she stops for pay | Her words don't say her gang "isn't hers to call off"; the gang stands down |
| 23 (was 78) | A long goal at 50x | No long idles between steps (partly seen in run 6) |
| 24 (was 131) | An NPC who agreed to pay while knocked out wakes up | Payment re-sent and VERIFIED, never IMPOSSIBLE while his line is being written (unit-tested; seen once in run 10) |

## C. Can't reproduce so far (fixed or built, never triggered in game)

| # | What would show it | Expect | Tried |
|---|---|---|---|
| 25 (was 128) | A surrender offer from a raider who gets **named** mid-fight | Server log `Directive follows the NPC's new name`; offer arrives | Spawned raiders are named before any offer (run 10) |
| 26 (was 30) | She says "Fine…" but the ledger shows nothing | Log `NPC agreed in words but recorded no deal`; the next line records ACCEPT | Every clear offer got a proper decision |
| 27 (was 37) | A COUNTER with no terms (log `invalid_terms_json`) | Next turn she's reminded and restates it with terms | Never happened |
| 28 (was 31) | "Take off X" during a deal | Recorded as UNEQUIP, not a hand-over | Never happened |
| 29 (was 35) | She misquotes an amount in a longer reply | Only the wrong sentence is rewritten, not the whole reply | Never happened |
| 30 (was 38) | A non-member's prompt | No "Shay \| squadmate" line | Never seen |
| 31 | Counter-offers like "300 now, 200 after?" where she misquotes | Amounts rewritten; log `Negotiation speech amounts differ` | She never misquoted |
| 32 | A REJECT that names her own price ("2000 for the hat") | Recorded as COUNTER (fixed run 11, unit-tested) | The model chose COUNTER by itself in run 11 |
| 33 | Pay for something she can't do, and she agrees | Deal fails and your Cats come back | She always says she can't (refund itself works) |
| 34 | One-on-one fight where a faction-mate joins uninvited | `PERSONAL_FIGHT: stood down joiner=…` within ~0.25 s | Nobody joined so far |
| 35 | She agrees to sell/stow her weapon without Fond trust | "Not my Chisa Katana…", log `NPC would give up her weapon` | She refuses on her own |
| 36 | Haggle back and forth more than 6 times | She ends the talks | Run 10: accepted at round 2 (unit-tested) |
| 37 | A neutral NPC losing a fight near Shay | They ask for help, maybe with a reward | Run 10: spawned victim wandered off |

## D. Open bugs (known broken, not fixed)

| # | Bug | Notes |
|---|---|---|
| 38 | The work planner assumes 1 input per output | A recipe needing 2 raw stone per building material sends her back to the mine for the rest; she still finishes. Fix: read the recipe's input amounts from Kenshi's production data (KenshiFP `stobe_work_planner.inc`, `wgp_ensure_item` gets `need` = outputs) |
| 39 | She claims an order is done when it isn't | Run 11: "Already done." to "stow your katana" while it was still equipped, no action sent. Needs a guard: a done-claim without a matching action/state |
| 40 | Her inventory knowledge lags | Run 11: holding 4 Dried Meat she said she had 1 (the items came from the test helper, outside a chat). Check whether `INV_SYNC` reaches the prompt before her reply |

## E. Design questions and features

- **Stowed weapons (answered in run 11):** with her katana in her pack or on the floor she fought ~50 s bare-handed; Kenshi's AI never re-equips or picks it up. Should she draw a stowed weapon when a fight starts?
- **Goal panel (Shay, 2026-10-02):** when Malzin has a goal ("make bread"), show a small UI element above the jobs area with the goal's info, instead of the current top-centre label.
- **Relationship shapes everything:** deal pricing and willingness by tier; hard rules like no pay-after deals and no favours below some tier.

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
