# STOBE test plan: what's left

Last updated 2026-10-01 (after run 8 and round 19h; Stobe.dll `261C7AF3…`, KenshiFP `0193CD57…`, server round 19g). This list holds **only** tests not yet run, tests that couldn't be triggered, and things known not to work; rows that passed are removed (they stay in the run logs). Bugs 1–93 and their fixes: `STOBE_bug_history.md`. Run logs: `archive/`, `test-run-2026-10-01-r8.md` (run 8).

**How to report a test:** tell me roughly when (your clock) and which NPC, e.g. "Malzin around 11:02, she didn't take the vest off". Send it **before relaunching Kenshi** (logs reset on launch).

## Before you start
- Goal/round 18 rows: the save at Shay's outpost **Home** (wheat farms S + XL, grain silo, well, bread oven, stone mine, manual stone processor, 4 General Camp Storage Chests, generators; Malzin in the squad, faction "Nameless"). Bread needs the well powered and the farm watered (it ran dry in run 4). Negotiation rows: the clean save (Malzin, Outlaw Tavern, The Hub). Test one step at a time; if something goes wrong, stop and tell me.
- Say the NPC's name in your first line to them.
- **Malzin's relationship to Shay is currently +60 Fond** (set for the bug 41 test). Run `stobe-reset-npc Malzin` first unless a test needs trust (test 28).
- **Fights only with the fight setup:** Shay on pause duty, a watcher armed in the background **before** the attack, fight started with `stobe-force-attack Malzin [help]` (voice alone can't start one). Watchers: `DELAY=2 stobe-fight-watch "<pay line>"` pays by itself; `stobe-fight-offer "<offer line>"` only sends an offer (then Claude checks the ledger and pays). Her gang stands down when she stops (DLL round 15).
- **Pause behaviour:** while paused, STOBE holds speech and actions (`ACTION_QUEUE: paused`) and runs them in order on unpause. Lines can still be sent while paused (payment + her stop then fire together on unpause). **Reloading a save drops the DLL's queued actions.** Deal clocks only tick when a chat line or game event reaches the server.
- **Setting trust for a test** (test data only; `stobe-reset-npc` clears it):
  `sudo -u postgres psql -d stobe -c "UPDATE core_npc_master SET extended_data = jsonb_set(extended_data, '{relationships,Shay}', jsonb_build_object('aff',60,'tier','Fond','type','friend','note','test','updated_at',extract(epoch from now())::int)) WHERE lower(name)='malzin'"` (tiers: 56 Fond, 31 Friendly, −56 Resentful). Low trust: she refuses credit; Fond: she accepts pay-later.
- **Safety:** if any NPC is harmed or knocked out by an action, or Shay goes down, stop immediately.
- Deal ledger: `cd /tmp && sudo -u www-data php /var/www/html/StobeServer/tools/negotiation_admin.php deals 3` (`deal <id>` for evidence, `directives` for queued NPC actions). KenshiFP results: `Kenshi\KenshiFP.log` (lines starting `[stobe]`).

---

## 1. Fixed but not yet seen in game
| # | Say / do | Expect |
|---|---|---|
| 1 (bug 42) | Fight setup. She agrees to stop for pay-later ("…I pay you right after. Deal?"; she needs trust for this, so Fond works). **Don't pay** and don't pause for over 1 minute of game time. | After the window: BREACHED_PLAYER, an angry line **that matches her attack** (no "cats received"), and she attacks again. Log: `Negotiation directive queued … breach_react`. Pause at once when she attacks. |
| 2 (bug 43) | Fight setup with `help`; she stops for pay | Her words don't claim her gang "isn't hers to call off"; the gang stands down (`PERSONAL_TRUCE: stood down faction-mate`). |
| 3 (bug 35) | While a deal is underway, make a **new** offer with a different amount ("…and 300 cats to take off your hat?") | Her reply is kept; she may repeat your 300. Only a sentence with a truly wrong amount is dropped. |
| 4 (bug 37) | Watch for a COUNTER with no terms (log `Negotiation rejected by deterministic validation … invalid_terms_json`) | Next negotiation turn she's reminded and restates it as COUNTER with terms. |
| 5 (bug 38) | Any chat with Malzin | Her prompt shows "Shay \| player's squad", not "squadmate" (`context_sent_to_llm.log`). |
| 6 | Only if she ever agrees to sell or stow her katana without Fond trust | Line replaced with "Not my Chisa Katana…", log `Negotiation rejected: NPC would give up her weapon`. (She has refused on her own every time so far.) |

## 2. Couldn't be triggered so far
| # | Say / do | Expect | Why not yet |
|---|---|---|---|
| 7 (bug 30) | If she says "Fine…" but the ledger shows nothing, send the next line | Log `NPC agreed in words but recorded no deal`; the next line records ACCEPT | Every clear offer got a proper decision |
| 8 (bug 31) | "N cats and you take off your X. Deal?" (no "hand it to me") | Recorded as UNEQUIP_ITEM; log `take-off request recorded as UNEQUIP_ITEM` | She refused all take-off deals in run 3 (hat, sandals, shirt). Try with trust (Fond). |
| 9 | Pay for something she can't do, and she agrees | Deal fails and **your Cats come back** | She always says she can't. (The refund itself works: seen in run 2.) |
| 10 | Item for item: "I'll give you <valuable item> for your pants." Then "Here's your <item>." | Both items change hands, deal COMPLETE, no refund, no second deal | She refused every item-only offer as not worth it |
| 11 | "Here's 500 cats, now <something she won't do>" | The 500 moves at once (by design); she refuses → the 500 is refunded | Not tried yet |
| 12 | Hand over a **stack** (e.g. 5 bread) into a nearly full pack | `dropped_at_feet=5` | Nobody had a stack (we don't spawn items) |
| 13 | One-on-one fight (no `help`) where a faction-mate joins uninvited | `PERSONAL_FIGHT: stood down joiner=…` within ~0.25 s | In every one-on-one fight nobody joined |
| 14 | Counter-offers where she might misquote ("300 now, 200 after?") | Misquoted amounts rewritten; log `Negotiation speech amounts differ` | She never misquoted |

## 3. Not run yet
**Clothing**
| # | Say / do | Expect |
|---|---|---|
| 15 | Ask her to put on a hat while already wearing one | Log `no free equipment section … occupied=head`; she doesn't claim success |
| 16 | Ask her to put on something she's **already wearing** ("put your vest back on" with the Black Rag Shirt on) | She says it's already on, and doesn't try to equip it (in run 1 she tried to equip it) |

**Combat and NPC-initiated** (fight setup)
| # | Scenario | Expect |
|---|---|---|
| 17 | Refuse to pay after she's handed something over | She may threaten or attack; paying then stops it and the stop holds |
| 18 | Two or more enemies: bargain with one, no names in follow-ups | Your lines stay with the NPC you're bargaining with |
| 19 | After the truce, call your squad off within ~10 s | Not counted as you breaking the deal |
| 20 | After the truce, attack her again (after 10 s) | BREACHED_PLAYER, your fault |
| 21 | Haggle back and forth more than 6 times | She ends the talks |
| 22 | Beat an enemy to low health (don't kill) | They beg or offer terms; "<Name>, deal." → accepted |
| 23 | Stand near a neutral NPC losing a fight | They ask for help, maybe with a reward, paid after |
| 24 | Trigger test 22 again right away | No second offer from the same NPC within 10 minutes |
| 25 | Break 2+ deals, then talk to a new NPC | "Word gets around": your reputation is mentioned |
| 26 | Betrayal (rare: dishonest NPC who dislikes you) | They attack after you pay; BREACHED_NPC, marked intentional |

**Needs Shay's hands** (heal, hand items, two NPCs)
| # | Say / do | Expect |
|---|---|---|
| 27 | Deal talk with NPC A while NPC B stands nearby; then talk to B | B doesn't act as if you'd asked him; may mention he overheard |
| 28 | Ask for something free from someone Fond+ (56+) or a squadmate (Malzin is Fond right now) | They may give it freely |
| 29 | Mid-fight, heal someone (or hand them an item), then talk without mentioning it | They already know ("thanks for patching me up") |
| 30 | "Senlin, what if I bandage you up and you give me your rags?" Heal her and say nothing | She hands the rags over on her own; deal completes |
| 31 | Same, but after she hands over first, "I'm not going to heal you" | You broke the deal; she doesn't say "we're square" |
| 32 | After a long fight, ask about something from earlier in it | She still remembers it |
| 33 (bug 23) | "Here, take this bread" while carrying Poppyseed Bread | You hand it over (distinctive-word match, round 9d) |

**Work and task goals** (passed rows are in `archive/test-run-2026-09-30-r4.md` and later run logs). Automated with `stobe-say` (+ `speed`) unless marked Shay.

What rounds 17–18 added (what these rows check):
- **Planner (KenshiFP):** walks back to the selected player when a goal ends; hauls inputs only from storage/mines/machine outputs; clears old orders when switching machines; power gate ("X has no power" after 30 s, only once she operates a machine with inputs loaded); "Waiting for <farm> to grow"; dry farm blocks after 60 s; goal machines mirrored as real Kenshi jobs (`GOAL_JOB added/removed`, switched off on an unexpected removal); label "StobeGoalLabel" (top centre) for the selected squad member.
- **Goal reports:** KenshiFP writes `stobe_goal_report.request` + `lifelike_initiative.flag` when she's back within 70; Stobe.dll consumes the flag; server `bored.php` queues a `goal_report` directive (no director mode).
- **Server:** store-not-give for "put back in storage"; "resume/try again" resumes the existing goal; "keep N stocked" → STOCK goal; item lists read from the player's line; PATROL → managed patrol goal; LOOT_TARGET with a category or an unreachable body → LOOT_AREA; stored-serial fallback outside the people list; `<player_base>` for faction members.
- **18c:** non-faction NPCs refuse work orders; follow/guard/wait/come/go only at trust ≥ `MINOR_ORDER_TRUST_MIN` (56) or an open deal. **18a/b:** TTS at 1x at any game speed; Volume 0–200 %, Fade 25–400 %.
| # | Say / do | Expect |
|---|---|---|
| 34 | "Make 2 bread" with the well powered and the farm watered (run at 50x, auto-pause on combat) | Water→farm only from the well (never out of the oven), wheat→silo, flour→oven; COMPLETE 2/2; status "Waiting for Wheat Farm … to grow" while growing (bugs 47, 58, 61, 69, 70) |
| 35 | Same with a machine really unpowered while she works it | After ~30 s: BLOCKED "… has no power"; she walks back and says why (bugs 59, 61) |
| 36 | Something needing a crafted ingredient at a bench | Bench queue grows only by what's missing |
| 37 (Shay) | Save and reload mid-goal | Continues with progress intact |
| 38 (Shay looks) | "Fetch the mead" with her starting **far** from the chest | Step "Walking to …"; she walks to the chest instead of fetching from afar (bug 51) |
| 39 | "Give Wendy 3 medkits" (needs a 2nd squad member) | 3 move between squad members |
| 40 | "Buy 3 bread from the trader" (needs a trader) | Walks there and really buys them |
| 41 | A goal needing something only a trader has | WAITING_APPROVAL; approve → buys; decline → cancelled |
| 42 | "Wait here for Wendy" (needs a 2nd squad member) | Holds until Wendy is near |

**Round 19 retest** (round 19h fixes installed after run 8). At Home with Malzin in the squad, **Shay selected** (the test inbox speaks as the selected character); automate unless marked.
| # | Say / do | Expect |
|---|---|---|
| 43 | "Make 1 building material" at 50x | COMPLETE 1/1; no BLOCKED "made no progress" while she works the Manual Stone Processor (bugs 80, 93) |
| 44 | "Loot everything from Sorth's body" (or any corpse) | KenshiFP `loot scan body name=Sorth … match=1`; walks to the body; items in her pack (bug 71) |
| 45 | "Loot the weapons from these bandits" (a body with a weapon) | Only weapons moved (bug 71) |
| 46 | Talk to Malzin near a corpse / a knocked-out NPC | Roster in stobe.log shows `(dead)` / `(unconscious)`; she never treats the corpse as alive (bug 73) |
| 47 (Shay looks) | "Make 2 building materials" with Malzin **selected** | Job list panel switches Stone Mine ↔ Manual Stone Processor by itself; KenshiFP `GOAL_JOB ui refresh replayed selection`, no `faulted` (bug 74, failed run 8, refix 19h) |
| 48 (Shay) | FP mode: look at Malzin and left-click; then click her portrait | Click: you stay Shay, KenshiFP `[fp] look-at click … kept control (bug 79)`. Portrait: switches to her as before. (Her details panel on click: not built yet) |
| 49 | 50x goal: compare to run 5 (`[202 s]` to the bread block) | Steps follow each other without long idles; pauses freeze the goal (bug 78) |
| 50 | Long goal at 50x with food in a chest, Malzin's food low | `GOAL_MEAL hungry` → `ate from …` → `done`; goal resumes (round 19 meals) |
| 51 | Same with no food anywhere | `GOAL_MEAL no food anywhere`; she says she's hungry and there's no food (server `Hunger report queued`); keeps working; afterwards **no** `GOAL_MEAL hungry` flood (one line, then quiet ~10 game min) (bug 92) |
| 52 | Save, give "Patrol the base", quit (or load the save) without saving | KenshiFP `GOAL_LOAD world time …`, then `GOAL_LOAD dropped id=… given_at=… world_now=…`; she isn't patrolling, no walk-back/report. A goal given **before** the save keeps running (bug 83) |
| 53 | "Malzin, guard me." then walk 50 m; "Malzin, follow me." | KenshiFP `ACTION_BRIDGE … squad->squad: using FOLLOW_PLAYER_ORDER`; she keeps up (dist stays small). If she only talks: server `Follow inferred from a direct request (bug 87)` (bugs 86, 87) |
| 54 | Bandit fight: accept an NPC surrender ("Deal…") | Deal dispatches STOP_ATTACK + payment; he stops for good (bug 88) |
| 55 | Offer a bandit cats to stop, pay; stay on block + passive | Gang stands down and stays down for 2 min; your hits on attackers log as "Defending against"; "we had a deal" → `Ceasefire honoured from a completed deal` (bugs 89, 90) |
| 56 | Let a common bandit get badly hurt | Surrender offer ≤ 300 cats and ≤ 35 % of what he carries; server `NPC offer capped (bug 91)` if the model asked for more; only one offer per NPC per fight (bug 91) |
Watch script for fast runs: pause on `[EVENT] knockout: Shay|Malzin` as well as combat.

**Round 18 features** (all automatable unless marked; check logs, state and goal status)
| # | Say / do | Expect |
|---|---|---|
| 57 | Ask a **non-faction** NPC (Malzin out of the squad, or any stranger) at low trust: "loot that corpse", "make 5 bread", "repair the gate", "patrol here" | Refuses in character; server log `Order refused: NPC is not in the player faction`; no goal/action queued (feature 1) |
| 58 | Same NPC at low trust: "follow me" / "guard me" / "wait here" | Refuses or names a price; nothing executed |
| 59 | Same NPC with trust ≥ 56 (set by hand) or after agreeing a paid deal ("follow me for 200 cats. Deal?" → pay) | Follow/guard/wait **does** run |
| 60 | Non-faction NPC in a fight or deal: help/attack, give items, take cats, surrender | Unaffected by the order gate |
| 61 | STOBE Settings window: TTS Volume row now has two boxes | Volume 0–200, Fade 25–400; values save to `StobeCustom.ini` (`TTSVolume`, `TTSFadePercent`) and survive a relaunch (feature 2) |
| 62 | TTS Volume 150–200 | Log `TTS_PLAYBACK … volume_pct=150+`; louder (Shay listens; clipping on loud lines is expected) |
| 63 (Shay listens) | Fade 50 vs 200, with the NPC ~30–60 m away | 50: fades/mutes sooner (`camera_out_of_range` skips at shorter range); 200: carries further |
| 64 | Game speed 3x (and 10x), NPC says a long line (Shay selected) | TTS at normal pitch/speed; log `TTS_PLAYBACK … speed` not scaled; next line doesn't start before the audio ends (feature 3). `Speed Dialogue` toggle in STOBE settings is off |
| 65 (optional) | Turn `Speed Dialogue` back on | Old behaviour returns (faster TTS at 2–3x) |
| 66 (Shay) | Give her a job of your own first, then a goal | Your job stays; only the goal's job comes and goes. Any `GOAL_JOB unexpected removal … disabled` = removal API is type-based → report |
| 67 (Shay looks) | Select Malzin during a goal | Top-centre label: "Malzin - Make 2 Building Material (1/2)" + current step; "+N more queued" when queued |
| 68 (Shay looks) | Goal blocked / done / cancelled | Label shows BLOCKED + reason / DONE / CANCELLED for 60 s, then hides |
| 69 (Shay looks) | Select Shay (no goal), first-person and third-person view | Label hidden for Shay; shows in both camera modes for Malzin. Log `GOAL_LABEL widget created`; no `GOAL_LABEL faulted` |

## 4. Known not working / open issues
- **Bugs 94–100 (run 8 fight, not fixed yet):** old goal report repeated (94); player-directed lines aimed at a nearby NPC (95); "we're done here" accepted an assist deal (96); Malzin called "him" (97); no surrender offers (98); NPC-to-NPC fight chatter flood (99); **FP: a picked-up NPC can't be put down (100)**.
- **Bug 79, second half:** FP look-at click on a squad member should open her details (like a normal NPC). 19h only keeps control on Shay (retest: test 48).
- **Hand-overs land on the floor.** Her GIVE_ITEM to Shay often logs `dropped_at_feet=1` (tobacco, twice in run 3), even when Shay's pack may have room. Check Shay's free space; if it has room, it's a DLL bug.
- **Refund queued outside a chat turn** waits for her next reply (4 min once in a fight). Round 15 only fixed this for settles after a voice payment.
- **Money sentence delay:** holding back a money sentence costs about 6 s of silence.
- **Player name lowercase** ("shay") in prompt lines (Money line, "known to honor deals", breach instruction).
- **`stobe-reset-npc` isn't a neutral start:** the relationship eval re-runs after her first line (run 3: back to "Resentful (rival)" at once).
- **A named price with conditions comes back as REJECT, not COUNTER**, so it isn't recorded (runs 2 and 3: "2000 for the hat", "3000 and a helmet swap"). The player has to restate it as an offer.
- **Her words don't know about drops:** when a taken-off item is dropped at her feet (full pack), she still says it "goes in the pack" (run 2).
- **Open question:** after she's disarmed (katana in her pack or on the floor), does Kenshi's AI re-equip or pick it up in a fight? Not observed yet.
- **Her "cats first" is a COUNTER with identical terms.** The ledger can't express "pay first"; harmless so far.
- **PocketTTS port 8024 unreachable** every line (falls back to 8086). Runtime, not code.
- `stobe-session` sometimes misses NPC lines (use `stobe-say`'s output instead).
- `stobe-tests` flakes intermittently (51/1, also with Kenshi closed); reruns are clean.
- **Goals for the same item count the stockpile:** a resumed or second goal can complete from another goal's output (bug 54, by design).
- **Planner assumes 1 input per output** (e.g. 1 raw stone per building material); she goes back to the mine if a recipe needs more.

## 5. Design work (Shay's notes, not started)
- **Relationship should shape everything she does:** deal pricing and willingness by tier; hard rules like no pay-after deals and no favours below some tier. (Already seen: at Resentful she refused credit; at Fond she accepted it.)
## Automated runs (stobe-say)
Claude can run every row **not** marked Shay, once Shay has loaded the save near the NPC and unpaused (fight rows: Shay on pause duty). Rows marked Shay need his eyes/ears/hands. Use `stobe-say speed` (≤50) for slow goals and pause on any combat toward Shay/Malzin.

## Switches
If a phase misbehaves: `… phase <2-8> off`. Voice payment: `NEGOTIATION_VOICE_PAYMENT`. Trust for free gifts: `GIFT_TRUST_THRESHOLD` (default 56 = Fond). Trust to give up her own weapon: `NEG_WEAPON_TRUST_MIN` (default 56). Trust for minor orders from non-faction NPCs: `MINOR_ORDER_TRUST_MIN` (default = `GIFT_TRUST_THRESHOLD`). STOBE ini: `Speed Dialogue` (0 = TTS at 1x), `TTSVolume` (0–200), `TTSFadePercent` (25–400).
