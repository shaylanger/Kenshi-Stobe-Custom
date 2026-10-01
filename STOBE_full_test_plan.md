# STOBE test plan: what's left

Last updated 2026-09-30 (after run 3; Stobe.dll `236C3F2C…` round 15, server round 16). This list holds **only** tests not yet run, tests that couldn't be triggered, and things known not to work. Everything that passed was removed. Bugs 1–43 and their fixes: `STOBE_bug_history.md`. Full run logs: `archive/test-run-2026-09-30*.md` (test IDs here still match them).

**How to report a test:** tell me roughly when (your clock) and which NPC, e.g. "Malzin around 11:02, she didn't take the vest off". Send it **before relaunching Kenshi** (logs reset on launch).

## Before you start
- Use the **clean save** (Malzin, Outlaw Tavern, The Hub). Test one step at a time; if something goes wrong, stop and tell me.
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
| # | Say / do | Expect |
|---|---|---|
| B1 | "Make 2 bread" with silo/oven powered and the farm growing (run at 50x) | Water→farm, wheat→silo, flour→oven; COMPLETE 2/2; "Waiting for Wheat Farm S to grow" while growing (bugs 47, 58, 61) |
| B1b | Same with a machine really unpowered while she works it | After ~30 s: BLOCKED "… has no power"; she walks back and says why (bugs 59, 61) |
| B3 | Something needing a crafted ingredient at a bench | Bench queue grows only by what's missing |
| B7 (Shay) | Save and reload mid-goal | Continues with progress intact |
| R1 | Any goal finishing near Shay | She walks back **and reports** the result (bug 59) |
| F1 (Shay watches) | "Fetch the vodka and the mead" / "put them back in the chest" | Both items; she **walks to the chest** first (bugs 51, 60) |
| P1 (Shay watches) | "Patrol the base", then "wait here" | Loops between Home's buildings; "wait here" ends the patrol (bugs 62, 63) |
| G1 (Shay watches) | "Guard me" | Stays close to Shay (stood ~29 m off in run 4) |
| C1 | After a fight: "loot the weapons from these bandits" | Only weapons; walks to each body |
| C2 | "Loot the food off that dead bonedog" | LOOT_AREA food; walks to the body (bug 64) |
| C5 | "Give Wendy 3 medkits" (needs a 2nd squad member) | 3 move between squad members |
| C9 | "Buy 3 bread from the trader" (needs a trader) | Walks there and really buys them |
| C10 | A goal needing something only a trader has | WAITING_APPROVAL; approve → buys; decline → cancelled |
| C11b | "Wait here for Wendy" (needs a 2nd squad member) | Holds until Wendy is near |

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
- `stobe-tests` flaked once (51/1) with the game running; reruns were clean.

## 5. Design work (Shay's notes, not started)
- **Relationship should shape everything she does:** deal pricing and willingness by tier; hard rules like no pay-after deals and no favours below some tier. (Already seen: at Resentful she refused credit; at Fond she accepted it.)
- **Tasks and goals only for the player's faction:** random NPCs shouldn't take "make 5 bread" or "loot that corpse"; minor requests ("follow me") only with trust or a fair deal. Gate on `npcIsInPlayerFaction` plus trust/deal.
- **Volume control in kenshi esttings for TTS**: right now the tts is not piped into kenshi and thus the sound effect is played at a static volume (possibly based on proximity) and we should be able to adjust that so it can be louder or quieter in the games settings if possible
- **TSS speed should not be effected by game speed setting**:right now if you speed up the game speed the tss gets played at a accelerated rate. I think it would be better if we didnt adjust the tts speed if the game speed changes
- **Can we route the task/goals system into the inbuild kenshi jobs**: Ideally when a NPC is given a goal the goals and what they are working shows up in the existing jobs queue. Not sure the best way to make this happen it would just be nice to see if they have a goal/task and where they are on it via the ingame jobs. (just a suggestion but maybe the gaodl could be a custom job, and then all the tasks that are real kenshi jobs queue in order and with any custom tasks like move to or sush showing as well).

## Automated runs (stobe-say)
Claude can run alone, once Shay has loaded the save near the NPC and unpaused: section 1 (fight rows with Shay on pause), section 2 rows L9, L10, E5, E8, pay-first refused, L3, and A6, A7, K11, F8, I13, D7b. The rest of section 3 needs Shay.

## Switches
If a phase misbehaves: `… phase <2-8> off`. Voice payment: `NEGOTIATION_VOICE_PAYMENT`. Trust for free gifts: `GIFT_TRUST_THRESHOLD` (default 56 = Fond). Trust to give up her own weapon: `NEG_WEAPON_TRUST_MIN` (default 56).
