# STOBE test plan: what's left

Last updated 2026-10-01 (after run 4 and round 18; Stobe.dll `3F967C4E…`, KenshiFP `1C768AB1…`, server round 18c). This list holds **only** tests not yet run, tests that couldn't be triggered, and things known not to work. Bugs 1–70 and their fixes: `STOBE_bug_history.md`. Run logs: `archive/` and `archive/test-run-2026-09-30-r4.md`.

**How to report a test:** tell me roughly when (your clock) and which NPC, e.g. "Malzin around 11:02, she didn't take the vest off". Send it **before relaunching Kenshi** (logs reset on launch).

## Before you start
- Goal/round 18 rows: the save at Shay's outpost **Home** (wheat farms S + XL, grain silo, well, bread oven, stone mine, manual stone processor, 4 General Camp Storage Chests, generators; Malzin in the squad, faction "Nameless"). Bread needs the well powered and the farm watered (it ran dry in run 4). Negotiation rows: the clean save (Malzin, Outlaw Tavern, The Hub). Test one step at a time; if something goes wrong, stop and tell me.
- Say the NPC's name in your first line to them.
- **Malzin's relationship to Shay is currently +60 Fond** (set for the bug 41 test). Run `stobe-reset-npc Malzin` first unless a test needs trust (I13).
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
| F2 + bug 42 | Fight setup. She agrees to stop for pay-later ("…I pay you right after. Deal?"; she needs trust for this, so Fond works). **Don't pay** and don't pause for over 1 minute of game time. | After the window: BREACHED_PLAYER, an angry line **that matches her attack** (no "cats received"), and she attacks again. Log: `Negotiation directive queued … breach_react`. Pause at once when she attacks. |
| bug 43 | Fight setup with `help`; she stops for pay | Her words don't claim her gang "isn't hers to call off"; the gang stands down (`PERSONAL_TRUCE: stood down faction-mate`). |
| bug 35 | While a deal is underway, make a **new** offer with a different amount ("…and 300 cats to take off your hat?") | Her reply is kept; she may repeat your 300. Only a sentence with a truly wrong amount is dropped. |
| bug 37 | Watch for a COUNTER with no terms (log `Negotiation rejected by deterministic validation … invalid_terms_json`) | Next negotiation turn she's reminded and restates it as COUNTER with terms. |
| bug 38 | Any chat with Malzin | Her prompt shows "Shay \| player's squad", not "squadmate" (`context_sent_to_llm.log`). |
| L6 backstop | Only if she ever agrees to sell or stow her katana without Fond trust | Line replaced with "Not my Chisa Katana…", log `Negotiation rejected: NPC would give up her weapon`. (She has refused on her own every time so far.) |

## 2. Couldn't be triggered so far
| # | Say / do | Expect | Why not yet |
|---|---|---|---|
| L9 (bug 30) | If she says "Fine…" but the ledger shows nothing, send the next line | Log `NPC agreed in words but recorded no deal`; the next line records ACCEPT | Every clear offer got a proper decision |
| L10 (bug 31) | "N cats and you take off your X. Deal?" (no "hand it to me") | Recorded as UNEQUIP_ITEM; log `take-off request recorded as UNEQUIP_ITEM` | She refused all take-off deals in run 3 (hat, sandals, shirt). Try with trust (Fond). |
| E5 | Pay for something she can't do, and she agrees | Deal fails and **your Cats come back** | She always says she can't. (The refund itself works: seen in run 2.) |
| E8 | Item for item: "I'll give you <valuable item> for your pants." Then "Here's your <item>." | Both items change hands, deal COMPLETE, no refund, no second deal | She refused every item-only offer as not worth it |
| Pay-first refused | "Here's 500 cats, now <something she won't do>" | The 500 moves at once (by design); she refuses → the 500 is refunded | Not tried yet |
| L1b | Hand over a **stack** (e.g. 5 bread) into a nearly full pack | `dropped_at_feet=5` | Nobody had a stack (we don't spawn items) |
| L4a | One-on-one fight (no `help`) where a faction-mate joins uninvited | `PERSONAL_FIGHT: stood down joiner=…` within ~0.25 s | In every one-on-one fight nobody joined |
| L3 | Counter-offers where she might misquote ("300 now, 200 after?") | Misquoted amounts rewritten; log `Negotiation speech amounts differ` | She never misquoted |

## 3. Not run yet
**Clothing**
| # | Say / do | Expect |
|---|---|---|
| A6 | Ask her to put on a hat while already wearing one | Log `no free equipment section … occupied=head`; she doesn't claim success |
| A7 | Ask her to put on something she's **already wearing** ("put your vest back on" with the Black Rag Shirt on) | She says it's already on, and doesn't try to equip it (run 1 I5: she tried to equip it) |

**Combat and NPC-initiated** (fight setup)
| # | Scenario | Expect |
|---|---|---|
| K11 | Refuse to pay after she's handed something over (like I10) | She may threaten or attack; paying then stops it and the stop holds |
| F4 | Two or more enemies: bargain with one, no names in follow-ups | Your lines stay with the NPC you're bargaining with |
| F5 | After the truce, call your squad off within ~10 s | Not counted as you breaking the deal |
| F6 | After the truce, attack her again (after 10 s) | BREACHED_PLAYER, your fault |
| F8 | Haggle back and forth more than 6 times | She ends the talks |
| G1 | Beat an enemy to low health (don't kill) | They beg or offer terms; "<Name>, deal." → accepted |
| G2 | Stand near a neutral NPC losing a fight | They ask for help, maybe with a reward, paid after |
| G3 | Trigger G1 again right away | No second offer from the same NPC within 10 minutes |
| H3 | Break 2+ deals, then talk to a new NPC | "Word gets around": your reputation is mentioned |
| H4 | Betrayal (rare: dishonest NPC who dislikes you) | They attack after you pay; BREACHED_NPC, marked intentional |

**Needs Shay's hands** (heal, hand items, two NPCs)
| # | Say / do | Expect |
|---|---|---|
| I7 | Deal talk with NPC A while NPC B stands nearby; then talk to B | B doesn't act as if you'd asked him; may mention he overheard |
| I13 | Ask for something free from someone Fond+ (56+) or a squadmate (Malzin is Fond right now) | They may give it freely |
| I15 | Mid-fight, heal someone (or hand them an item), then talk without mentioning it | They already know ("thanks for patching me up") |
| I16 | "Senlin, what if I bandage you up and you give me your rags?" Heal her and say nothing | She hands the rags over on her own; deal completes |
| I17 | Same, but after she hands over first, "I'm not going to heal you" | You broke the deal; she doesn't say "we're square" |
| I18 | After a long fight, ask about something from earlier in it | She still remembers it |
| D7b (bug 23) | "Here, take this bread" while carrying Poppyseed Bread | You hand it over (distinctive-word match, round 9d) |

**Work and task goals** (run 4 at Home passed B4, B5, B6, C3, C4, C6, C7, C8, walk-back; see `archive/test-run-2026-09-30-r4.md`). Automated with `stobe-say` (+ `speed`) unless marked Shay.

What rounds 17–18 added (what these rows check):
- **Planner (KenshiFP):** walks back to the selected player when a goal ends; hauls inputs only from storage/mines/machine outputs; clears old orders when switching machines; power gate ("X has no power" after 30 s, only once she operates a machine with inputs loaded); "Waiting for <farm> to grow"; dry farm blocks after 60 s; goal machines mirrored as real Kenshi jobs (`GOAL_JOB added/removed`, switched off on an unexpected removal); label "StobeGoalLabel" (top centre) for the selected squad member.
- **Goal reports:** KenshiFP writes `stobe_goal_report.request` + `lifelike_initiative.flag` when she's back within 70; Stobe.dll consumes the flag; server `bored.php` queues a `goal_report` directive (no director mode).
- **Server:** store-not-give for "put back in storage"; "resume/try again" resumes the existing goal; "keep N stocked" → STOCK goal; item lists read from the player's line; PATROL → managed patrol goal; LOOT_TARGET with a category or an unreachable body → LOOT_AREA; stored-serial fallback outside the people list; `<player_base>` for faction members.
- **18c:** non-faction NPCs refuse work orders; follow/guard/wait/come/go only at trust ≥ `MINOR_ORDER_TRUST_MIN` (56) or an open deal. **18a/b:** TTS at 1x at any game speed; Volume 0–200 %, Fade 25–400 %.
| # | Say / do | Expect |
|---|---|---|
| B1 | "Make 2 bread" with the well powered and the farm watered (run at 50x, auto-pause on combat) | Water→farm only from the well (never out of the oven), wheat→silo, flour→oven; COMPLETE 2/2; status "Waiting for Wheat Farm … to grow" while growing (bugs 47, 58, 61, 69, 70) |
| B1c | "Make 2 bread" with the farm dry and no water to bring | After ~60 s: BLOCKED "Wheat Farm … has no Water and none is available to carry"; she says so (bug 70) |
| B1b | Same with a machine really unpowered while she works it | After ~30 s: BLOCKED "… has no power"; she walks back and says why (bugs 59, 61) |
| B3 | Something needing a crafted ingredient at a bench | Bench queue grows only by what's missing |
| B7 (Shay) | Save and reload mid-goal | Continues with progress intact |
| R1 | "Make 1 building material", Malzin the only NPC near Shay | Walks back (`GOAL_RETURN arrived`) **and reports** the result; log `LIFELIKE_INITIATIVE: flag consumed`, `BORED_EVENT: initiative turn addresses the player`, server `Goal report queued` and no "Director scene failed" (bugs 59, 65, 66) |
| R2 | A goal that gets BLOCKED (e.g. "make 3 steel bars") | She comes back and says **why** it is blocked (bugs 59, 65, 66) |
| F1 | "Fetch the vodka and the mead" / "put them back in the chest" | **Both** items (server log: two FETCH goals); then both stored (bug 60). Walking to the chest is only judgeable when she starts far from it (step "Walking to …") (bug 51) |
| P1 | "Patrol the base" | PATROL goal; her position changes; step "Patrolling (n/N waypoints)" advances; no lasting `path_failed` (bugs 62, 67) |
| P1b | Then "wait here" | Patrol CANCELLED "replaced by a new order"; she stops (bug 63, passed once in run 4) |
| G1 (Shay watches) | "Guard me" | Stays close to Shay (stood ~29 m off in run 4) |
| C1 | After a fight: "loot the weapons from these bandits" | LOOT_AREA weapons; walks to each body; only weapons in her pack. If nothing: KenshiFP log `TASK_GOAL loot scan … dead=N valid=N` tells why (bug 68) |
| C2 | "Loot the food off that dead bonedog" / "loot everything from <name>'s body" | LOOT_AREA food/all on that body; walks to it (bugs 64, 68) |
| C5 | "Give Wendy 3 medkits" (needs a 2nd squad member) | 3 move between squad members |
| C9 | "Buy 3 bread from the trader" (needs a trader) | Walks there and really buys them |
| C10 | A goal needing something only a trader has | WAITING_APPROVAL; approve → buys; decline → cancelled |
| C11b | "Wait here for Wendy" (needs a 2nd squad member) | Holds until Wendy is near |

**Round 18 features** (all automatable unless marked; check logs, state and goal status)
| # | Say / do | Expect |
|---|---|---|
| N1 | Ask a **non-faction** NPC (Malzin out of the squad, or any stranger) at low trust: "loot that corpse", "make 5 bread", "repair the gate", "patrol here" | Refuses in character; server log `Order refused: NPC is not in the player faction`; no goal/action queued (feature 1) |
| N2 | Same NPC at low trust: "follow me" / "guard me" / "wait here" | Refuses or names a price; nothing executed |
| N3 | Same NPC with trust ≥ 56 (set by hand) or after agreeing a paid deal ("follow me for 200 cats. Deal?" → pay) | Follow/guard/wait **does** run |
| N4 | Faction member (Malzin in the squad): all the work orders above | Still work exactly as before (no refusal) |
| N5 | Non-faction NPC in a fight or deal: help/attack, give items, take cats, surrender | Unaffected by the order gate |
| V1 | STOBE Settings window: TTS Volume row now has two boxes | Volume 0–200, Fade 25–400; values save to `StobeCustom.ini` (`TTSVolume`, `TTSFadePercent`) and survive a relaunch (feature 2) |
| V2 | TTS Volume 150–200 | Log `TTS_PLAYBACK … volume_pct=150+`; louder (Shay listens; clipping on loud lines is expected) |
| V3 (Shay listens) | Fade 50 vs 200, with the NPC ~30–60 m away | 50: fades/mutes sooner (`camera_out_of_range` skips at shorter range); 200: carries further |
| S1 | Game speed 3x (and 10x), NPC says a long line | TTS at normal pitch/speed; log `TTS_PLAYBACK … speed` not scaled; next line doesn't start before the audio ends (feature 3). `Speed Dialogue` toggle in STOBE settings is off |
| S2 (optional) | Turn `Speed Dialogue` back on | Old behaviour returns (faster TTS at 2–3x) |
| J1 | "Make 2 building materials" | `GOAL_JOB added … job=Stone Mine`, then `GOAL_JOB removed` + `added … Manual Stone Processor`; at the end `GOAL_JOB removed`; her job list (`stobe-say state` `permajobs=`) shows the machine during the goal and is empty after (feature 4) |
| J2 | Pause the goal, then resume | Job removed on pause, re-added on resume |
| J3 (Shay) | Give her a job of your own first, then a goal | Your job stays; only the goal's job comes and goes. Any `GOAL_JOB unexpected removal … disabled` = removal API is type-based → report |
| L1 (Shay looks) | Select Malzin during a goal | Top-centre label: "Malzin - Make 2 Building Material (1/2)" + current step; "+N more queued" when queued |
| L2 (Shay looks) | Goal blocked / done / cancelled | Label shows BLOCKED + reason / DONE / CANCELLED for 60 s, then hides |
| L3 (Shay looks) | Select Shay (no goal), first-person and third-person view | Label hidden for Shay; shows in both camera modes for Malzin. Log `GOAL_LABEL widget created`; no `GOAL_LABEL faulted` |

## 4. Known not working / open issues
- **Hand-overs land on the floor.** Her GIVE_ITEM to Shay often logs `dropped_at_feet=1` (tobacco, twice in run 3), even when Shay's pack may have room. Check Shay's free space; if it has room, it's a DLL bug.
- **Refund queued outside a chat turn** waits for her next reply (4 min once in a fight). Round 15 only fixed this for settles after a voice payment.
- **L2b:** holding back a money sentence costs about 6 s of silence.
- **Player name lowercase** ("shay") in prompt lines (Money line, "known to honor deals", breach instruction).
- **`stobe-reset-npc` isn't a neutral start:** the relationship eval re-runs after her first line (run 3: back to "Resentful (rival)" at once).
- **A named price with conditions comes back as REJECT, not COUNTER**, so it isn't recorded (runs 2 and 3: "2000 for the hat", "3000 and a helmet swap"). The player has to restate it as an offer.
- **Her words don't know about drops:** when a taken-off item is dropped at her feet (full pack), she still says it "goes in the pack" (run 2, K6).
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
Claude can run alone, once Shay has loaded the save near the NPC and unpaused: section 1 (fight rows with Shay on pause), section 2 rows L9, L10, E5, E8, pay-first refused, L3, and A6, A7, K11, F8, I13, D7b; goal rows R1, R2, B1, B1c, F1, P1, P1b, C1, C2; round 18 rows N1–N5, V1, V2, S1, J1, J2. Rows marked Shay need his eyes/ears/hands. Use `stobe-say speed` (≤50) for slow goals and pause on any combat toward Shay/Malzin.

## Switches
If a phase misbehaves: `… phase <2-8> off`. Voice payment: `NEGOTIATION_VOICE_PAYMENT`. Trust for free gifts: `GIFT_TRUST_THRESHOLD` (default 56 = Fond). Trust to give up her own weapon: `NEG_WEAPON_TRUST_MIN` (default 56). Trust for minor orders from non-faction NPCs: `MINOR_ORDER_TRUST_MIN` (default = `GIFT_TRUST_THRESHOLD`). STOBE ini: `Speed Dialogue` (0 = TTS at 1x), `TTSVolume` (0–200), `TTSFadePercent` (25–400).
