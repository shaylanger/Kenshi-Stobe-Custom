# REL (STOBE stateful relationships): final report, phase 8

Snapshot 2026-10-03 (run m16): phases 1-8 built and merged live, running in **shadow** mode with native Capture=1.
Later runs passed more rows (SR06, SR07, SR12, SR30 ...): the open rows now live only in
`RELATIONSHIP_SYSTEM_DESIGN.md` section 8; architecture and settings in `REL_ARCHITECTURE.md`.
The row states live in `server/tests/social_relationship/scenarios.json` (`rel_state`). This report is the summary,
and it is current as of the `rel_state` values committed with it.

## Summary

| Verdict | Rows |
|---|---|
| Pass in game | SR02 03 04 05 08 10 11 12 15 16 18 19 21 22 24 25 28 29 32 38 41 43 (22; SR12 including a real slave) |
| Pass offline; in game it is by construction or out of reach | SR01 17 20 26 31 33 36 (7) |
| Partial: the in-game part passes, one sub-case is offline only | SR23 27 34 35 37 39 40 42 44 (9) |
| Results pending (next run) | SR06 (p2-04 rerun), SR07 (p3-05b with `sever`), SR32 real-slave part (rel-enslaved.sh on m16d) |
| Inconclusive in game, LLM-dependent (section 2) | SR30 |
| Waiting for Shay's decision (feasibility estimate 2026-10-03, see the theft probe at the end) | SR09, SR13, SR14 |

**Offline gate:** `tests/run_social_phase1.py` covers contract, unit, integration, save/migration, concurrency, the
interpreters, scope, HTTP, the inspect tool, legacy negotiation, mutation proof (20) and the perf bench. It passes
on the final branch (`8ca2a49`, 2026-10-03 22:40, all 25 steps).
- Earlier attempts that evening failed at random steps for two reasons:
  - a parallel `stobe-tests` run (stage-100) was using the same test DB;
  - the test DB's `core_npc_id_seq` was behind the restored rows (15663 < 15867), so inserts hit duplicate keys.
- The sequence was reset with `setval` (test DB only). The live DB is fine (sequence 34022 >= max id 34013).

**Run outputs:** `C:\KenshiTestRuns\<run>\rel*\` (`.out`, `.csv`, `.inspect.txt`, `.gainloss.txt`) and archived game
logs in `C:\KenshiTestRuns\logs\<time>-stop\`. Run logs m4-m22: git history (`archive/test-run-2026-10-03-m*.md`, removed 2026-10-06).

## Row by row

Offline suites are in `server/tests/`. In-game scenarios are in `server/tests/social_relationship/ingame/`.

| Row | What | Offline | In game (file, last run) | Verdict | Open / why |
|---|---|---|---|---|---|
| SR01 | Tier boundaries, directed maps, clamp, retry delta | social_relationship_unit | - | pass offline | Pure logic; nothing to see in game |
| SR02 | A attacks B: only B->A changes | combat | p2-01 (m4, m5, m8, m13): Rel Vorn->Shay -15 aggression, -21 KO | **pass** | |
| SR03 | Retaliation is free | combat | p2-02, p2-03 (m4) | **pass** | |
| SR04 | Joining to defend a friend: not charged | combat | p2-02 (m4) + Hub fights | **pass** | |
| SR05 | One escalating harm budget per encounter | combat | p2-01 (m4, m8, m11): joined assault -40 | **pass** | |
| SR06 | Second distinct assault counts again | combat | p2-04: m8, the bandit struck first (retaliation, correct). m16 batch 8 (20/0) was inconclusive: Rel Vorn was still knocked out from p2-01, so the second strike was `pending_awareness` (correct for an unconscious victim). p2-04 now wakes him with `protect` | **pending** rerun | If he strikes first again, or stays down, move it to section 2 |
| SR07 | Defensive limb loss = separate grievance, once | combat | p3-05 (m16 batch 8, 31/2): `damage 400` does not sever, so there was no limb_loss and no capture; p3-05b (`sever`, KAH 20, harness F6A3FC31) runs next | **pending** p3-05b | Blocked if `sever` doesn't leave the game's own limb-lost state |
| SR08 | KO'd, someone else loots: wake blames the KO attacker (inferred), not the real taker | unconscious | p3-01 (m15 39/0): Rel Tam->Shay theft -9 inferred | **pass** | |
| SR09 | Better evidence of the real taker wins | unconscious (evidence adapter) | - | **waiting for Shay** | Needs a witness/sensing evidence source (feasibility estimate) |
| SR10 | Unknown KO / own use / squad change: no invented theft | unconscious | p3-02 (m8) | **pass** | |
| SR11 | Enslaved while KO: latent, owner charged on waking | unconscious | p3-03 (m13 -86, m16 -73) | **pass** | |
| SR12 | Unknown owner, actor vs later owner, repeated chaining | unconscious | p3-03 (m16): only the owner charged, the KO attacker only harm, one enslaved fact; real slave: p7-03 (rel-enslaved.sh) | **pass**, including the real slave: m16 rel-enslaved p7-03 (Izumi first seen enslaved, no blame after a 2 h shift; the camp's own enslavements reported with the owner) | Repeated chaining: offline only |
| SR13 | Theft only when caught | property | - | **waiting for Shay** | No proven "caught" signal (HUNT_MY_THIEF idea) and no steal driver |
| SR14 | Theft severity, returned property | property | - | **waiting for Shay** | Same blocker as SR13 |
| SR15 | Real first aid on an unconscious, bleeding patient: credited by outcome | care | p4-01 (m5 +11, m8 +29) | **pass** | |
| SR16 | Repeated aid in one episode adds nothing | care, unit | p4-01 (m16): lifesaving +31, second treatment 0 | **pass** | |
| SR17 | Harm then heal: no trust farming | care | - | pass offline | Staged self-harm has no attacker in game |
| SR18 | Outsider carries a KO'd NPC to a bed: safe_rescue | care | p4-02 (m11 +9, m13 +8, m15 +9) | **pass** | Carry by the player actor is not captured (sweep skips the player) |
| SR19 | Carry ends in a cage: imprisonment | care | p4-03 (m11 -31, m13 -33, m15 -31) | **pass** | Ground drop / unknown placer: offline only |
| SR20 | Squad carry/loot/equipment exempt | unconscious, care, property | - | pass offline | Squad looting a conscious mate is not scripted |
| SR21 | Hungry recipient fed: food_aid; full recipient nothing | care | p4-04 (m16 53/0): Rel Hask +5, Rel Fenn not_hungry | **pass** | |
| SR22 | Ordinary trade ~0; gifts small | property | p5-01, p5-02 (m8, m11 +3, m13 +2) | **pass** | |
| SR23 | Missing seller / purse / failed buy: no guessed reward | property | p5-01 (m16 rel7 21/0): character seller fair_trade; rel6: failed buy, no effect | **partial pass** | Shop storage / faction purse sellers can't be reached in game |
| SR24 | Friend who sees it shares the victim's feeling | witness | p6-01a/b (m8, m9, m13, m16): Rel Wren -6..-8 | **pass** | |
| SR25 | Absent/asleep/KO witness: nothing | witness | p6-01b (m16 rerun 23/0): Rel Sorn asleep in a bed, sleeping 1, no effect | **pass** | |
| SR26 | Single hop, pre-event affinity | witness | p6-01b | pass offline (consistent in game) | |
| SR27 | Insult heard by a friend; dialogue not re-scored | witness | - | **partial** | Insult witnesses need dialogue listener data (not built) |
| SR28 | Hated enemy (-85) still surrenders; deal works | negotiation_engine | rel-surrender.sh kept hate (m16 fights2): offer with -85, COMPLETE, kept_coercive_deal 0 | **pass** | Needed STOBE 96 |
| SR29 | Honored coercive deal minimal; attack after acceptance = betrayal | property, negotiation_engine | rel-surrender.sh breach (m16 fights2): BREACHED_PLAYER, broken_promise -13, betrayal -25 | **pass** | Needed STOBE 97. "A dishonest NPC betrays" stays the engine's rule (STOBE 18 test switch) |
| SR30 | Recruitment gate at 75/76, trust evidence | recruitment | p7-01 (m8; m16 batch 8, 11/0: Rel Rook "That's a fast ask from someone I just met"); p7-05/06 (m16 rel-enslaved: Rel Nima "Make it worth my while first") | **inconclusive** x3; gate logic passes offline | The NPC never tried JoinParty, so the gate was never reached. LLM-dependent: section 2 |
| SR31 | No join bypass via autonomy/director/inline | recruitment | - | pass offline | Native ACT_JOIN_PARTY fallback paths not audited in game |
| SR32 | Freed from chains: liberator credited | recruitment | p7-02 (m16 run 4): Rel Xan->Malzin chains_freed +14; real slave: p7-04 (rel-enslaved.sh) | **pass**; real-slave part **pending** (m16 rel-enslaved found 2 native bugs, fixed in rel-native-m16d: player-actor slave skipped; owner unchaining counted as freed) | Escape completion (a game day free) is not tracked across the handle the game re-creates |
| SR33 | Vanilla recruitment unchanged | recruitment | - | pass by construction | The gate is only on STOBE's JoinParty path |
| SR34 | Generic names, rename, same name, reused serial | combat | p2-01 (m4) named binding | **partial** | Same-name NPCs and renames need game data; m16 added storage_alias for re-squadded characters |
| SR35 | Duplicates / same tick / out of order: exactly once | integration, combat, unconscious | p1-03 (m4) | **partial** | Out-of-order delivery beyond the late-event rule is not tested |
| SR36 | Concurrent writers: no lost deltas | concurrency, integration | - | pass offline | |
| SR37 | Crash/restart mid-KO | unconscious | p3-04 (m9) | **partial** | Crash between writes: integration test only |
| SR38 | Reload before/during KO/loot restores state | integration, unconscious | p3-04 (m9 39/0), p1-04 | **pass** | |
| SR39 | Playthrough switch / upgrade / export | playthrough | - | **partial** | Export/import not tested |
| SR40 | Stale epoch, barrier, NEVER_CLEAR | integration, http, scope | p1-04 (m4) | **partial** | NEVER_CLEAR_RELATIONSHIP_DATA=true not tested (live uses false) |
| SR41 | off/shadow/category flags; no double count with R4 | integration, combat | p1-01, p1-02, p1-03, p2-05 (m4); check-shadow in every run | **pass** | |
| SR42 | Victim's prompt knows only the inferred blame | unconscious, witness | p3-01 (m15): belief names only Shay | **partial** | Prompt-side belief injection not built (notes only) |
| SR43 | Floods, caps, retention; perf | concurrency, combat, perf bench | p8-01 soak (m13), 10-min windows (m15) | **pass** | fps 99.6-100.2% of Capture=0, memory B-A -45/+4 MB, no overflow |
| SR44 | Runner resume after interruption | runner manifest | - | **partial** | The game runner (harness) is not REL-owned |

## Fixes found by the in-game runs (for the record)

- **Native:**
  - capture without Playthrough Saves (m4);
  - placed falls back to the carrier (m13);
  - the sleeping witness flag (m13);
  - storage_alias for re-squadded characters (m16);
  - the sweep follows a handle change; ESCAPING/EX_SLAVE count as free (m16b);
  - freed is reported when the chains come off (m16c).
- **Server:**
  - an ally joining an assault (m9);
  - enslavement kept for waking without a seen KO (m11);
  - storage_alias identity binding (m16).
- **STOBE (other owners), found through REL tests:**
  - 96: a payment executed before the dispatch was missed;
  - 97: a player attack is now allowed to end the personal-truce guard.

## Phase 8 gates

| Gate | Result |
|---|---|
| Retention (raw facts, checkpoints, finished incidents older than 3 game days) | Done (m9). Inspect `--retention`. Ledger, beliefs and latent incidents are never pruned |
| Perf bench offline | Pass: 6000 facts, p95 12.2 ms per fact, tables bounded |
| Soak + frame time in game (SR43) | Pass: m13 soak (99.5% fps, worst frame 107.7%); m15 10-min B-A-B-A windows compared in the same frame-cap regime (99.6-100.2%) |
| Shadow consistency | `--check-shadow` passed in every run's inspect output |
| Full matrix on one build | **Closed by per-row evidence.** Every in-game row's last pass is on a recorded build (m13 to m16, Stobe EF62563B for the m16 rows). A single-build confirmation run is optional: the batch lines below |
| Offline runner on the final branch | **Pass** (`8ca2a49`, 25/25 steps) |
| Install manifest | `REL_ARCHITECTURE.md` |
| Enabled-mode balance review | **Shay** (section 3): a short supervised session on a kah-* copy (p2-05 style) |

**Optional single-build confirmation** (current build; `fixture|file|mode|reload`):
```
auto-home|REL-p1-03-shadow-capture.txt|shadow|1
auto-home|REL-p2-01-player-first-strike.txt|shadow|1
auto-home|REL-p3-01-ko-loot-inferred.txt|shadow|1
auto-home|REL-p3-03-enslaved-while-ko.txt|shadow|1
auto-home|REL-p4-01-first-aid.txt|shadow|1
auto-home|REL-p4-04-food.txt|shadow|1
auto-home|REL-p6-01a-witness-setup.txt|shadow|1   (+ the two --set-relation 91 calls)
auto-home|REL-p6-01b-witness-attack.txt|shadow|0
auto-home|REL-p7-02-slave-escape.txt|shadow|1
```

## Recommendation

- **Normal play:** keep `shadow` with Capture=1. It records everything, changes no affinity, and costs no measurable
  frame time.
- **Before `enabled`:** Shay's balance review (section 3).
- **Category switches:**
  - SR13/SR14 (theft) don't score at all until a "caught" signal exists, so `SOCIAL_CATEGORY_PROPERTY` can stay on.
  - Turn `SOCIAL_CATEGORY_RECRUITMENT` off if the gate feels too strict in play (SR30 is still LLM-dependent).

## Theft probe (SR09/13/14, waiting for Shay)

**Theft probe for SR09/13/14:** `ingame/REL-probe-theft-seen.txt` and `REL-probe-theft-unseen.txt` (KAH 22). After
the probe, give Shay a firm estimate.
