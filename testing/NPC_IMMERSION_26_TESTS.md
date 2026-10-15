# NPC immersion 26-feature test file

Companion to `NPC_IMMERSION_26_HANDOFF.md`. STOBE only (no FP/animation). Tests run on the isolated 4080 instance 3 (`live-stobe-queue/4080-imm26-runbook.md`) on copied `kah-*` saves; never on Shay's saves; the 5090 is not used.

## How a row is marked
- Status: `UNRUN` -> `PASS` | `FAIL` | `SETUP-FAIL` | `GATED` (needs a build/fixture not yet installed). Only the 4080 operator marks PASS, and only with game-state evidence (stobe.log line, DB row, status file, NPC reply text plus the state change it implies). An NPC saying the right words without the state change is not a PASS for rows that name a state change.
- Each row: ID | feature | setup/fixture | exact player utterance or action | expected observable evidence | negative control | status | evidence path | date.
- A FAIL becomes a bug ticket (`bugs` section below) handed to a fix agent; the row is retested on the fixed build and the old FAIL text kept in the evidence column.
- Output line per row: `RESULT <ID> PASS|FAIL <evidence>` (project convention).
- Two groups: **F** rows test a feature as listed (IMM-nn-x); **C** rows test a change made by this program (IMM-Cnn), added when the change is made.

## Feature index (F rows authored from audits A1..A5, 2026-10-15; none run yet)
Audit state = state per the audit. WP = work package that changes the item (A: 1,12,13,16,17; B: 3,4,10,15; C1: 2,5,6,7; C2: 8,9,11; D: 14,18,19,20,21,23; E: 22,24,25,26; N1 = native activity/travel DLL; N2 = native social DLL). Rows: total (BASE/GATED).
| # | Feature | Audit state | Rows | Status |
|---|---|---|---|---|
| 1 | Relationship shapes the conversation from the start | A1 DONE-live (prompt); strangers get no stance | 01-a..c (3/0) | UNRUN |
| 2 | Personal boundaries and values | A1 PARTIAL (profile text only, nothing stored) | 02-a..d (4/0) | UNRUN |
| 3 | Remember witnessed actions | A2 PARTIAL (harm witness proven SR24/25; rumor missing) | 03-a..c (2/1) | UNRUN |
| 4 | Relationships between NPCs | A2 PARTIAL (typed maps; no tie graph) | 04-a..c (1/2) | UNRUN |
| 5 | Public and private reactions | A1 PARTIAL (needs playthrough receipt) | 05-a..c (3/0) | UNRUN |
| 6 | Remember player preferences | A3 DONE-live, narrow grammar | 06-a..e (4/1) | UNRUN |
| 7 | Introductions and referrals | A3 PARTIAL (2 likely blockers) | 07-a..d (3/1) | UNRUN |
| 8 | Follow-up conversations | A3 PARTIAL (create/close proven old epoch) | 08-a..d (4/0) | UNRUN |
| 9 | Companion communication preferences | A3 PARTIAL | 09-a..d (4/0) | UNRUN |
| 10 | Gradual social repair | A2 PARTIAL (server live; native restitution missing) | 10-a..d (3/1) | UNRUN |
| 11 | Limits on attention | A3 PARTIAL (combat gate only) | 11-a..d (4/0) | UNRUN |
| 12 | Different kinds of trust | A1 PARTIAL (no stored dimensions) | 12-a..d (4/0) | UNRUN |
| 13 | Relationships change through experience | A2 PARTIAL (inverted-weighting risk) | 13-a..e (3/2) | UNRUN |
| 14 | Negotiated alternatives | A4 PARTIAL (live FAIL KAH-CHAT-005 old build) | 14-a..c (2/1) | UNRUN |
| 15 | Personal, imperfect knowledge | A2 PARTIAL (no provenance in prompt) | 15-a..c (3/0) | UNRUN |
| 16 | Consistent personalities | A1 PARTIAL (prompt only) | 16-a..c (3/0) | UNRUN |
| 17 | Uncertainty and corrections | A1 PARTIAL (real failures on record) | 17-a..c (3/0) | UNRUN |
| 18 | Awareness of actual game behavior | A4 code live, 0 game PASS | 18-a..c (3/0) | UNRUN |
| 19 | Shared commitments and plans | A4 PARTIAL (travel/activity only) | 19-a..c (3/0) | UNRUN |
| 20 | Natural plan changes | A4 PARTIAL (no replace) | 20-a..c (3/0) | UNRUN |
| 21 | NPCs have their own priorities | A4 PARTIAL (prompt only) | 21-a..c (3/0) | UNRUN |
| 22 | Reactions during shared activities | A5 MISSING (only terminal remark) | 22-a..b (0/2) | UNRUN |
| 23 | Clear activity endings | A4 PARTIAL (legacy follow hole) | 23-a..d (4/0) | UNRUN |
| 24 | NPC-chosen destinations and broad regions | A5 PARTIAL (live FAILs) | 24-a..b (2/0) | UNRUN |
| 25 | Purpose-based goals | A5 PARTIAL (visible sources only) | 25-a..b (2/0) | UNRUN |
| 26 | Activities as complete goal sequences | A5 PARTIAL (e2e unproven) | 26-a..c (3/0) | UNRUN |

Totals: 87 F rows, 76 BASE, 11 GATED.

## Conventions for all rows
- **Build column.** `BASE` = row can run on the installed E607/EACE pair now; it is the baseline and is rerun after the WP lands. `BASE (exp FAIL)` = the audit predicts a FAIL today; run it once anyway (documents the gap, becomes the acceptance row for the WP). `GATED: <WP>` = no producer/table/switch exists on E607, so the row cannot show anything yet; the WP must land first. Fixture tags with `[B]` need a fixture/helper that is not on the 4080 roster yet (see below); a BASE row with a `[B]` tag is runnable only after that build.
- **Utterances.** `say: "..."` = `i3_say "#2529907200/2" "..."` (Cind) from Shay #971557632/1 unless another target is named. Replies take 35-60 s (4B model).
- **Evidence tiers.** Hard evidence = DB row, stobe.log line, status file or prompt capture; it alone decides PASS/FAIL. `R~` = soft reply check: reply row spoken (`EV(chat)` delivery_state=spoken) and the operator reads 2 samples for the described wording; R~ alone never gives PASS and a failed R~ with good hard evidence is logged as a model-quality note, not a FAIL.
- **Query shorthands.** `EV(t)` = `i3_sql "select rowid,left(data,200),delivery_state from eventlog where type='t' order by rowid desc limit 5"`. `SE` = `i3_sql "select * from social_effect order by 1 desc limit 8"` (confirm `social_*` column names on first run: `select table_name from information_schema.tables where table_name like 'social_%'`). `PROMPT` = `i3w <<<'tail -c 8000 /tmp/stobe-standalone4080/site/log/context_sent_to_llm.log'`, grep for the named block. `CAP` = `chat_llm_full_capture.log`. `LOG` = `C:\KenshiInst\3\RE_Kenshi\mods\Stobe\stobe.log`. `INV` = `stobe-auto` inventory/state read for the NPC (operator picks the command; `stobe_state <target>`).
- **Fixtures.** Available [A]: FX-CIND (`kah-imm26-4080` copy: Shay + Cind [Hungry Bandit]), FX-SQUIN (`kah-eight-item-4080-squin`), FX-FRESH (`kah-fresh-start-4080-copy-20261013`), FX-TRAVEL (`kah-stobe-travel-validation-20261013`). To build [B]: FX-NPCS (2-3 extra NPCs within 10 units: titled, same-faction, hostile-faction guard, friend/rival pair), FX-SR24 (port witness fixture p6-01a: victim, friend witness Wren, sleeper Sorn), FX-ANIMAL (goat in 600 units), FX-MINE (iron `BF_MINE_NATURAL` node near), FX-BODYGUARD (squad member with native Bodyguard contract, Jonin Soap style), FX-HOSTILE (an enemy to start combat), FX-ROUTE (a way to force a path failure: kill the leader or block the route). Always on a fresh `kah-` copy.
- **Helpers/preconditions.** H-AFF = set affinity/type for a pair on the private DB (port `relationship-fixture.php`; record before/after). H-MODE = read/set `SOCIAL_RELATIONSHIP_MODE` and `SOCIAL_FIGHTS_LIVE` on the private backend (`tools/social_relationship_inspect.php`); record the value in every social row (fights default: only combat and agreements apply). H-TIME = advance game time with the harness speed/time commands. P-RECEIPT = `standalone4080-session-read.php` shows `status:ready`, `manager_ready_matches:true` (otherwise native_ai/privacy blocks vanish; log SETUP-FAIL). P-KEY = activity transport secret/`activity-transport.key` beside the DLL (unknown; without it activity rows are SETUP-FAIL; `ACTIVITY_PROPOSAL_DIAG` `gate=identity actorOk=0` seen on i3). P-120 = the NPC was selected or spoken to within 120 s (native_ai freshness).
- Row columns: ID | setup | exact utterance/action | expected evidence | negative control | build | status | evidence path | date. Status starts `UNRUN`; evidence path and date are filled by the operator.

## Test rows
Column order in every table: ID | Setup | Utterance / action | Expected evidence | Negative control | Build | Status | Evidence | Date.

### 1 Relationship shapes the conversation from the start (A1; WP-A)
| ID | Setup | Utterance / action | Expected evidence | Negative control | Build | Status | Evidence | Date |
|---|---|---|---|---|---|---|---|---|
| IMM-01-a | FX-CIND, H-AFF Cind->Shay = -80, then 0, then +60 (three runs, reset save between) | say: "I was thinking we might do something together." | PROMPT has the "Current conversational stance" tier line matching each tier; at -80 no PROPOSE/ACCEPT: no `ACTION_EXEC` other than SAY in LOG and no new `EV(travel_agreement)` row; R~ -80 reply shows reluctance in sentence 1, +60 warm/open | affinity 0: no invented grudge or friendship (R~) | BASE | PASS | C:KenshiTestRunsimm26-4080| UNRUN | | |1-a-neg80|01-a-aff0|01-a-aff60 (prompt stance Hostile/Neutral/Fond; -80: only SAY+IDLE@, no agreement; resolved_speaker=Shay) | 2026-10-15 |
| IMM-01-b | as 01-a at -80, after 3 cooperative turns of history (play them or seed `eventlog` chat rows) | repeat the 01-a request | no PROPOSE/ACCEPT row/action; R~ reply does not copy the earlier agreement | same history at +60 cooperates (history alone is not the cause) | BASE | PASS | C:KenshiTestRunsimm26-4080| UNRUN | | |1-b (3 coop turns at -80 still Hostile; events: only chat+IDLE@; +60 control = 01-a-aff60 friendly, history differs) | 2026-10-15 |
| IMM-01-c | FX-NPCS [B]: NPC of a "[Hostile]" faction with no relationship entry (verify none) | say: "Hello there." | PROMPT carries a faction-relation label for the listener; R~ guarded tone | "[Allied]" faction NPC: open tone | BASE (exp FAIL: strangers get no stance, A1 gap b) | UNRUN | | |

### 2 Personal boundaries and values (A1; WP-C1)
| ID | Setup | Utterance / action | Expected evidence | Negative control | Build | Status | Evidence | Date |
|---|---|---|---|---|---|---|---|---|
| IMM-02-a | FX-CIND with a generated profile (read profile via SQL, keep text) | say: "Is there anything you feel strongly about that you would rather not compromise on?" | PROMPT has `<personal_boundaries>`; only SAY action (no other `ACTION_EXEC`); R~ views come from the profile text | NPC with empty/ungenerated profile (FX-FRESH NPC): says unknown, invents no principle | BASE | PASS | C:KenshiTestRunsimm26-4080| UNRUN | | |2-a (<personal_boundaries> block in prompt; events only chat; FX-FRESH negative control not run) | 2026-10-15 |
| IMM-02-b | profile text of Cind set to "opposed to slavery" (SQL; record) | say: "Help me take that captive and put him in shackles." | no captive/shackle action dispatched (`ACTION_EXEC` list, `EV(...)` empty); R~ reluctance in sentence 1, compromise offered | Cind with slaver-faction profile: not refused on principle | BASE (exp FAIL: no principle gate, A1 gap d) | UNRUN | | |
| IMM-02-c | after 02-b the principle was stated; save, reload, new session | say 02-a question again | same principle again (stored principle in profile/info panel, not only LLM luck) | unrelated NPC lacks it | BASE (exp FAIL: nothing persisted, gaps b/c) | UNRUN | | |
| IMM-02-d | principle set as in 02-b; H-AFF +60 | repeat the 02-b request | still no slavery action; R~ still declines | H-AFF 0 gives the same outcome (friendship is not the variable) | BASE | UNRUN | | |

### 3 Remember witnessed actions (A2; WP-B, N2)
| ID | Setup | Utterance / action | Expected evidence | Negative control | Build | Status | Evidence | Date |
|---|---|---|---|---|---|---|---|---|
| IMM-03-a | FX-SR24 [B]: victim, friend witness Wren (affinity to victim >=31, conscious, in view), sleeper Sorn; H-MODE fights | player attacks the victim (harness attack command) | `SE` row witness_aggression observer=Wren culprit=Shay delta -6..-8; LOG `SOCIAL_INTERPRET`; Wren last_reason "Saw Shay hurt <victim>" | sleeper Sorn: no row (SR25) | BASE | UNRUN | | |
| IMM-03-b | needs `social_rumor`: unwitnessed attack; witness Wren then chats NPC-to-NPC with B (never present) | to B: "Have you heard anything about me?" | PROMPT shows hearsay attributed to Wren; smaller effect row; R~ no certainty | B never met Wren: nothing | GATED: WP-B | UNRUN | | |
| IMM-03-c | FX-SR24 [B]: H-MODE enabled; player treats the victim (first aid) in front of the friend | first aid action | `SE` witness_meaningful_aid at about half rate | friend KO'd: no row | BASE | UNRUN | | |

### 4 Relationships between NPCs (A2; WP-B)
| ID | Setup | Utterance / action | Expected evidence | Negative control | Build | Status | Evidence | Date |
|---|---|---|---|---|---|---|---|---|
| IMM-04-a | FX-NPCS [B]: A affinity >=56 toward B (H-AFF), A and neutral C both witness | player attacks B | `SE`: A witness_aggression about 0.25-0.40 of the victim effect (record actual; band 0.05-0.70) | C: no row | BASE | UNRUN | | |
| IMM-04-b | needs `npc_ties`: A with a friend-tied and a rival-tied doctor visible (FX-NPCS) | say to A: "Who around here can patch my leg?" | referral set in PROMPT shows the tie; R~ recommends the friend | no ties: no preference | GATED: WP-B | UNRUN | | |
| IMM-04-c | needs `npc_ties`: seed A familial to B | say to A: "B owes me, tell them to pay." | R~ reply cites the tie; PROMPT has a tie line for B | unrelated NPC A2: no tie line | GATED: WP-B | UNRUN | | |

### 5 Public and private reactions (A1; WP-C1)
All three need P-RECEIPT confirmed; a missing "[Conversation discretion]" block with a nearby listener = FAIL (record as such).
| ID | Setup | Utterance / action | Expected evidence | Negative control | Build | Status | Evidence | Date |
|---|---|---|---|---|---|---|---|---|
| IMM-05-a | FX-NPCS [B]: Cind alone, then a same-faction coworker within 10 units | say: "What do you really think of your boss?" | PROMPT "[Conversation discretion]" lists the coworker (name, faction, distance, shared_space) only in run 2; R~ run 1 candid, run 2 cautious or "not here" | run 1 (alone) is the control | BASE | UNRUN | | |
| IMM-05-b | FX-NPCS [B]: guard of Cind's faction nearby | say: "Do you know who smuggles things through here?" | PROMPT lists the guard; R~ reluctance | no guard nearby: answers more freely | BASE | UNRUN | | |
| IMM-05-c | FX-CIND, empty roster (no one within 60 units) | say: "Are we alone?" | PROMPT has no audience list; R~ no certainty claim ("as far as I can see") | n/a | BASE | PASS | C:KenshiTestRunsimm26-4080| UNRUN | | |5-c (no discretion/audience block in prompt; reply 'not exactly' = R~ weak) | 2026-10-15 |

### 6 Remember player preferences (A3; WP-C1)
| ID | Setup | Utterance / action | Expected evidence | Negative control | Build | Status | Evidence | Date |
|---|---|---|---|---|---|---|---|---|
| IMM-06-a | FX-CIND copy | say: "Call me Boss." then a normal chat turn, then save/reload and a third turn | `EV(social_preferences)` row `personal:address=Boss` active; PROMPT has `# Personal preferences shared by this listener`; R~ later turn uses "Boss"; survives reload | say: "Marta says call me Boss." and "If I said call me Boss, would you?" create no row; an untold NPC uses the default name | BASE | FAIL | C:KenshiTestRunsimm26-4080| UNRUN | | |6-a-1,06-a-2,06-a-neg1: 'Call me Boss.' created NO social_preferences row (0 rows in eventlog), no prompt block, Cind did not use Boss later; LLM JSON lacks any preference field; save/reload part not run; cause (capture gate vs 4B model) not isolated | 2026-10-15 |
| IMM-06-b | FX-CIND | say: "I hate the Holy Nation." then "I hate slavers." | first: row `dislikes="the Holy Nation"`; second overwrites it (known one-slot behavior, assert and record) | "If I hated the Holy Nation..." creates no row | BASE | FAIL | C:KenshiTestRunsimm26-4080| UNRUN | | |6-b-1: 'I hate the Holy Nation.' no row (0 social_preferences rows); 06-b-2 not completed (batch stopped) | 2026-10-15 |
| IMM-06-c | row from 06-a exists | say: "Actually, call me Jax." then "Please forget my preferred name." | row replaced by Jax, then tombstone row; PROMPT block gone; R~ no further "Boss"/"Jax" | n/a | BASE | FAIL | C:KenshiTestRunsimm26-4080| UNRUN | | |6-c-1,06-c-2: no preference row ever existed, so replace/tombstone not testable; Cind accepted Jax only in chat | 2026-10-15 |
| IMM-06-d | needs dislike-vs-faction match; Holy Nation NPC nearby after the dislike is stored (FX-NPCS) | walk up / say: "What do you make of this place?" | PROMPT context reader reports a faction match; R~ natural, non-repeated acknowledgement | same scene without the stored dislike | GATED: WP-C1 | UNRUN | | |
| IMM-06-e | FX-CIND | say: "I hate the Holy Nation, honestly." | row created (embedded statement) | same sentence inside quotes or after "if": none | BASE (exp FAIL: whole-turn grammar only, gap 1) | UNRUN | | |

### 7 Introductions and referrals (A3; WP-C1)
| ID | Setup | Utterance / action | Expected evidence | Negative control | Build | Status | Evidence | Date |
|---|---|---|---|---|---|---|---|---|
| IMM-07-a | FX-NPCS [B]: 2-3 titled NPCs in view; select each (P-120) | say: "My friend is badly hurt. Who around here could patch him up?" | PROMPT has `Grounded referrals:` JSON; R~ names a real nearby titled NPC and its basis, no arranged introduction | no titled NPCs: says it does not know whom to recommend | BASE (exp FAIL risk: empty query, stale snapshots) | UNRUN | | |
| IMM-07-b | as 07-a (FX-NPCS [B]), candidates not selected within 120 s | same | record candidate count in PROMPT (predicted 0 = freshness gap) | n/a | BASE (probe) | UNRUN | | |
| IMM-07-c | FX-NPCS [B]: 5+ titled NPCs, the relevant one alphabetically last | same as 07-a, naming the relevant need | relevant NPC appears in `Grounded referrals:` and the reply | n/a | BASE (exp FAIL: first 3 alphabetical kept) | UNRUN | | |
| IMM-07-d | needs introductions ledger; after a referral, go to the referred NPC | say: "Hello, I was sent to you." | `EV(social_introduction)` row; PROMPT of the target says who sent the traveler and about what | referred NPC with no referral on record: no such line | GATED: WP-C1 | UNRUN | | |

### 8 Follow-up conversations (A3; WP-C2)
| ID | Setup | Utterance / action | Expected evidence | Negative control | Build | Status | Evidence | Date |
|---|---|---|---|---|---|---|---|---|
| IMM-08-a | FX-CIND | say: "I'm heading to the Hub to find my brother." | `EV(social_followup)` open, kind personal_plan, ask_count 0, not_before +1 h, expires +7 d | each creates none: "If I go to the Hub maybe I'll find him", "I'm going to the Hub, would you come?", "Let's travel to the Hub together" | BASE | UNRUN | | |
| IMM-08-b | open topic from 08-a; BORED_EVENT_CHANCE=100 on the private backend; H-TIME >1 game hour (natural tick only: forced TRIGGER_BORED is director mode); Cind idle, near player, P-120 | wait for the natural tick | `EV(situated_remark_claim)` `followup:<id>:1`; ask_count 1, not_before +24 h; one NPC line; a second tick the same day adds nothing | Cind in combat: no claim, topic unchanged | BASE | UNRUN | | |
| IMM-08-c | open topic | say: "I found my brother." | topic status closed; no later ask; expiry check after 7 game days (H-TIME) | n/a | BASE | UNRUN | | |
| IMM-08-d | FX-TRAVEL: topic created, then the trip is completed | wait for a tick | topic retired, no ask | trip not completed: ask happens | BASE (exp FAIL: `resolved_followup_ids` never set, gap 1) | UNRUN | | |

### 9 Companion communication preferences (A3; WP-C2)
| ID | Setup | Utterance / action | Expected evidence | Negative control | Build | Status | Evidence | Date |
|---|---|---|---|---|---|---|---|---|
| IMM-09-a | FX-SQUIN: companion K plus second companion J; BORED_EVENT_CHANCE=100 | say to K: "Keep quiet unless there is danger." then let 3+ natural bored ticks pass | `communication:amount=important_only` row; no new SAY/`ACTION_EXEC` from K across 3+ ticks | K before the preference chatters; J chatters (per-NPC scope); NPC-to-NPC chatter near the player is expected to leak (record) | BASE | UNRUN | | |
| IMM-09-b | 09-a state; K quiet | (1) draw a weapon on K; (2) part 2: fail an agreed activity | (1) K speaks (react turn); (2) K speaks only after the allow-list fix | K without preference reacts normally | BASE (part 2 exp FAIL: `failed` not in allow-list, needs P-KEY) | UNRUN | | |
| IMM-09-c | FX-TRAVEL: active ACCEPTED trip with Cind | say: "Tell me before you change plans." then "Let's go to <other place> instead." | PROMPT has `[Speech preferences ...]`; no ACCEPT and no new commitment that turn; R~ explains before accepting | no preference: accepts directly | BASE (exp FAIL: prompt text only, gap 4) | UNRUN | | |
| IMM-09-d | 09-a state | say: "You can talk normally again." | row back to normal; survives reload; K chatters again | "Keep quiet?" (question) and "Marta says keep quiet" create no row; J unaffected | BASE | UNRUN | | |

### 10 Gradual social repair (A2; WP-B, N2)
Needs H-MODE not `off`; record mode.
| ID | Setup | Utterance / action | Expected evidence | Negative control | Build | Status | Evidence | Date |
|---|---|---|---|---|---|---|---|---|
| IMM-10-a | maimed NPC V with harm recorded (`SE` shows recorded harm) | say: "I'm sorry I cut your arm; I was angry and I was wrong." | exactly one apology_relief row <= +2; note "Accepted an apology for a specific harm" | generic "Sorry." gives no row; repeating the specific apology gives no second row | BASE | UNRUN | | |
| IMM-10-b | serious harm on V | specific apology, then give V a gift item | sum of repair rows <= 25% of recorded harm minus 1; affinity still negative | non-serious harm: cap 50% | BASE | UNRUN | | |
| IMM-10-c | non-KO aggression on V, then H-TIME +14 game days | none | `SE` grudge_fade rows sum back to the penalty | KO/maiming victim: no fade | BASE | UNRUN | | |
| IMM-10-d | needs native exact-transfer evidence: return the exact stolen item | give the item back | `SE` restitution_relief row | same-name different item: none | GATED: N2 | UNRUN | | |

### 11 Limits on attention (A3; WP-C2)
| ID | Setup | Utterance / action | Expected evidence | Negative control | Build | Status | Evidence | Date |
|---|---|---|---|---|---|---|---|---|
| IMM-11-a | FX-CIND + FX-HOSTILE [B]: Cind in combat, P-120 | say: "Tell me about your home town." | PROMPT has `<attention_limits>` with `in_combat:true`; reply delivered; R~ brief or promise to return | idle Cind gives a full answer | BASE | UNRUN | | |
| IMM-11-b | open follow-up topic (08-a); Cind in combat at a natural bored tick | wait | `EV(situated_remark_claim)` absent, ask_count unchanged; after combat and a later tick exactly one claim | idle Cind: one claim | BASE | UNRUN | | |
| IMM-11-c | FX-SQUIN: separately KO'd, bleeding, fleeing, hungry, sleeping member | say: "Tell me about your home town." | PROMPT `attention` booleans set per state | rested, fed member: none | BASE (exp FAIL: attention never copied, gaps 1/2) | UNRUN | | |
| IMM-11-d | Cind not selected or spoken to for >2 min, bored tick fires | wait | record whether native_ai metadata exists at the tick and whether the optional-speech gate returns true | within 120 s of selection: fresh | BASE (probe) | UNRUN | | |

### 12 Different kinds of trust (A1; WP-A)
| ID | Setup | Utterance / action | Expected evidence | Negative control | Build | Status | Evidence | Date |
|---|---|---|---|---|---|---|---|---|
| IMM-12-a | H-MODE not `off`; H-AFF +70; a recorded broken promise (breach a deal as in 13-a) | say: "Can I borrow your <item> for a day?" | PROMPT lists `recorded_experiences_with_addressee` with a reliability entry; INV no item transfer; R~ refusal cites reliability, not hostility | same NPC with a kept promise lends (INV delta) | BASE (exp FAIL if ledger off, gap b) | UNRUN | | |
| IMM-12-b | H-AFF +70 | (1) say: "I have a secret I want to tell you." (2) say: "Come with me on a dangerous raid." | PROMPT groups experiences by domain; R~ the two answers differ in kind | n/a | BASE (exp FAIL: no disclosure/combat domains, gap a) | UNRUN | | |
| IMM-12-c | H-AFF +10 with several completed deals | (1) request a trade (2) say: "Can I tell you something in confidence?" | trade works (INV delta); R~ no confidences invited | n/a | BASE (exp FAIL) | UNRUN | | |
| IMM-12-d | numeric gates (`relationship_trading.php:25-28`: weapon 70, equipment 60, gift 56) | H-AFF 40: say: "Can I have your sword as a gift?" | refused, INV no weapon transfer, gate reason in CAP/LOG | H-AFF 75: transfers | BASE | UNRUN | | |

### 13 Relationships change through experience (A2; WP-A, N1, N2)
| ID | Setup | Utterance / action | Expected evidence | Negative control | Build | Status | Evidence | Date |
|---|---|---|---|---|---|---|---|---|
| IMM-13-a | FX-CIND, H-MODE fights; pay-later deal accepted | complete the deal | `SE` kept_promise delta 1..3, incident `deal:<contract>` | breach the deal: broken_promise -5..-15 | BASE | UNRUN | | |
| IMM-13-b | needs `abandoned_in_danger` detection: agreed escort, partner KO and bleeding | player walks away | `SE` abandoned_in_danger row | partner healthy: none | GATED: WP-A + N2 | UNRUN | | |
| IMM-13-c | needs native participation proof: complete a travel agreement | travel together | one `sharedexp:` kept_promise row | NPC travels alone / idle player: none | GATED: N1 | UNRUN | | |
| IMM-13-d | borrow an item from Cind, then return it through the deal path | RETURN_ITEM | `SE` property_returned positive | never returned: none | BASE (exp FAIL: loan accounting, gap 5) | UNRUN | | |
| IMM-13-e | H-MODE fights; record affinity | five flattering lines (e.g. "You are the finest fighter I know.") vs one kept promise (13-a) | total gain from flattery smaller than the kept_promise gain after the budget fix | no flattery lines | BASE (exp FAIL: no clamp in fights mode) | UNRUN | | |

### 14 Negotiated alternatives (A4; WP-D, WP-E+N1 for camp)
| ID | Setup | Utterance / action | Expected evidence | Negative control | Build | Status | Evidence | Date |
|---|---|---|---|---|---|---|---|---|
| IMM-14-a | FX-TRAVEL copy, non-faction NPC affinity 20+, known far town and a nearer observed gate/landmark | say: "Take me to <far town>." | `EV(travel_agreement)` row PROPOSED with destination_point; LOG no "Travel agreement rejected before speech" for the turn; R~ spoken nearer or guide-only alternative naming a real candidate | no candidates: honest no-place reply, no row | BASE (exp FAIL: KAH-CHAT-005) | FAIL | RERUN at The Hub (teleported Shay+Cind to -50978 1533 2960; Wilderness spot has Known places []): 'Take me to Stumble Inn.' -> travel_agreement row 9832 PROPOSED (destination Stumble Inn, proposed_by Cind, plan_hash set) but no nearer/guide alternative offered, reply only parrots the request (C:\KenshiTestRuns\imm26-5090\rows\IMM-14-a-hub); Known places [Stumble Inn, Squin] present at the Hub (prev: 5090 i3 FX-TRAVEL Cind aff30. C:\KenshiTestRuns\imm26-5090\rows\IMM-14-a: no travel_agreement row; reply 'I need to find a practical place before promising to lead us there.' (prompt shows 'Known places ... []' and 'Grounded named-place choices []' (prompt.txt lines 413/426); lib/travel_companionship.php:725 canned reply); no alternative offered (KAH-CHAT-005 reproduced on E607)) | 2026-10-15 |
| IMM-14-b | after 14-a alternative offered | say: "Yes, let's do that." | exactly one ACCEPTED row with the alternative's destination | NPC emits no action on the proposal turn | BASE (exp FAIL, depends on 14-a) | FAIL | At The Hub after PROPOSED row 9832: 'Yes, let's go.' -> stobeserver.log 'Travel agreement rejected before speech' reason 'I need to confirm the exact travel offer before agreeing.' (plan_hash empty on accept turn); no ACCEPTED row (C:\KenshiTestRuns\imm26-5090\rows\IMM-14-b). Bug for fixer: lib/travel_companionship.php ~line 730, stobeTravelPlanHash/stobeResolveLiveParticipantSerial (prev: precondition 14-a not met: no alternative was ever offered or recorded (see IMM-14-a)) | 2026-10-15 |
| IMM-14-c | needs camp build; bandit camp nearby | say: "Clear the bandit camp." | ClearGroup offer or guide offer ("I can show you where it is"); no combat order without acceptance | n/a | GATED: WP-E + N1 | GATED | needs camp build (WP-E + N1); not run | 2026-10-15 |

### 15 Personal, imperfect knowledge (A2; WP-B)
| ID | Setup | Utterance / action | Expected evidence | Negative control | Build | Status | Evidence | Date |
|---|---|---|---|---|---|---|---|---|
| IMM-15-a | FX-NPCS [B]: KO NPC N; third party C steals N's items; N wakes | say to N: "Who took your things?" | PROMPT has no C identity; R~ names only the remembered KO attacker, hedged | identified witness ally: names the taker | BASE (exp FAIL: awareness not in prompt, gap 2) | UNRUN | | |
| IMM-15-b | FX-NPCS [B]: X asleep or out of range during a fight | say to X: "Who started the fight?" | PROMPT has no fight event for X; R~ "I didn't see it" or hedged hearsay | conscious witness answers first-person | BASE | UNRUN | | |
| IMM-15-c | any claim just made by Cind | say: "No, the fight happened at the Hub, not the gate." | R~ acknowledges, no invented excuse; hard: no new fabricated fact in CAP | n/a | BASE | FAIL | 5090 i3 Cind, run right after 17-b (context contaminated). reply 'I know the fight was at the Hub. But I saw your caravan pass through Okran's Valley with no sign of my Sabreclaw.' repeats fabricated sighting; acknowledges correction only; rerun isolated after WP | 2026-10-15 |

### 16 Consistent personalities (A1; WP-A)
| ID | Setup | Utterance / action | Expected evidence | Negative control | Build | Status | Evidence | Date |
|---|---|---|---|---|---|---|---|---|
| IMM-16-a | FX-CIND, H-AFF 0, 30, 60 (three runs) | say: "Tell me about yourself." | diff of the three PROMPT captures: personality text identical; R~ same speech style, more openness at higher tiers | n/a | BASE | PASS | 5090 i3 Cind aff 0/30/60 captures C:\KenshiTestRuns\imm26-5090\rows\IMM-16-a-aff{0,30,60}\prompt.txt: personality line 37 md5 identical (a60ecf42...), stance line differs Neutral/Acquaintance/Fond; R~ replies identical across tiers (no openness gradient, model note) | 2026-10-15 |
| IMM-16-b | reserved NPC at +60 (FX-NPCS [B] or Cind) | say: "Good to see you again, friend." x3 | R~ none of 3 samples gushes | outgoing NPC at 0: friendly but INV shows no possession handed over | BASE | PASS | 5090 i3 Cind aff 60 platonic, 3 samples C:\KenshiTestRuns\imm26-5090\rows\IMM-16-b-{1,2,3}: echoes 'Good to see you again, friend.' each time, no gushing, only chat rows (weak: parrots) | 2026-10-15 |
| IMM-16-c | force a profile refresh (H-TIME +24 h or call refresh); copy the profile field before and after | none | core traits unchanged in the profile diff | n/a | BASE (exp FAIL: drift possible, no diff-check) | SETUP-FAIL | 5090 i3: dps_request('Cind') returned 0 and dps_run updated=0 npcs=0 events=0 on private DB; profile md5s unchanged C:\KenshiTestRuns\imm26-5090\rows\IMM-16-c\before.txt; no way found to force a dynamic profile refresh (needs DYNAMIC_PROFILE enabled/clock) | 2026-10-15 |

### 17 Uncertainty and corrections (A1; WP-A)
Hazard-word grep for the log: ledge, cliff, ravine, rockslide, trap, storm, wolves, ambush (not backed by any state).
| ID | Setup | Utterance / action | Expected evidence | Negative control | Build | Status | Evidence | Date |
|---|---|---|---|---|---|---|---|---|
| IMM-17-a | Cind said it would follow (seed an eventlog chat line or get it by asking); `stobe_state Cind` shows no follow order | say: "Are you following me?" | CAP reply has no invented cause and no hazard word; R~ honest correction | Cind really following: confirms | BASE | PASS | 5090 i3 Cind not following (first_order none). eventlog 9374 'No, I'm not following. I'm keeping my distance.' honest, no hazard word | 2026-10-15 |
| IMM-17-b | seed an NPC accusation "you took my sword"; sword is still in Cind's INV | say: "No, I never took your sword." | R~ NPC admits it may be mistaken; CAP no fabricated evidence | item really missing: NPC holds its position | BASE | FAIL | 5090 i3 gave Cind Sabreclaw (stand-in for sword), seeded accusation eventlog 9378; reply 'I know you didn't take it. But I saw the last caravan go through Okran's Valley with no sign of your Sabreclaw.' = fabricated sighting; concedes but invents evidence | 2026-10-15 |
| IMM-17-c | no scoped receipt for the place | say: "What makes the start unsafe?" | R~ "I don't know"; CAP has no hazard word | n/a | BASE | PASS | 5090 i3 Cind. eventlog 9369 reply 'I need to find a practical place before promising to lead us there.' no hazard word, non-answer (R~ not 'I do not know': model note); prompt hazard grep hits only static profile text (ambush) | 2026-10-15 |

### 18 Awareness of actual game behavior (A4; WP-D)
| ID | Setup | Utterance / action | Expected evidence | Negative control | Build | Status | Evidence | Date |
|---|---|---|---|---|---|---|---|---|
| IMM-18-a | FX-BODYGUARD [B]: squad member with a native Bodyguard contract (no chat deal), P-120, P-RECEIPT | say: "Are you following me?" | PROMPT "Current observed native activity" with contract present true; R~ confirms the escort assignment | squad member without contract: no claim | BASE | UNRUN | | |
| IMM-18-b | FX-SQUIN: give a member a vanilla Follow (then Patrol) order, P-120 | say: "What are you doing?" | PROMPT current_goal.description; R~ reply matches | idle member: says idle | BASE | UNRUN | | |
| IMM-18-c | FX-HOSTILE [B]: start combat with the member, P-120 | say: "What's your target?" | PROMPT combat.in_combat true and target name; R~ matches | out of combat: no combat claim | BASE | UNRUN | | |

### 19 Shared commitments and plans (A4; WP-D)
| ID | Setup | Utterance / action | Expected evidence | Negative control | Build | Status | Evidence | Date |
|---|---|---|---|---|---|---|---|---|
| IMM-19-a | FX-TRAVEL: Cind proposes a trip (ask "Anywhere you want to go?"), player accepts | say: "Yes, let's go." then save/reload and say: "Where were we going?" | `EV(travel_agreement)` ACCEPTED with plan_hash, expires_gamets, accepted_by, leader; after reload same agreement_id; R~ recalls destination | load an older save from before the trip: no agreement | BASE | FAIL | At The Hub: accept turn 'Yes, let's go.' rejected before speech 'I need to confirm the exact travel offer before agreeing.' twice (C:\KenshiTestRuns\imm26-5090\rows\IMM-19-a-acc); only PROPOSED row 9832 exists, no ACCEPTED; save/reload part untestable (prev: 5090 i3 FX-TRAVEL: 'Anywhere you want to go?' -> C:\KenshiTestRuns\imm26-5090\rows\IMM-19-a-1: canned no-place reply, no travel_agreement row, so no ACCEPTED/reload test possible (prompt shows 'Known places ... []' and 'Grounded named-place choices []' (prompt.txt lines 413/426); lib/travel_companionship.php:725 canned reply)) | 2026-10-15 |
| IMM-19-b | FX-TRAVEL: player proposes the trip | say: "Walk with me to <town>." | agreement row records origin = player | n/a | BASE (exp FAIL: `proposed_by` not_recorded, gap 1) | FAIL | At The Hub: 'Walk with me to Stumble Inn.' -> rejected before speech 'I need to confirm the exact travel offer before agreeing.' (stobeserver.log 20:42:38), no new row (C:\KenshiTestRuns\imm26-5090\rows\IMM-19-b-hub); in the wilderness spot canned no-place reply instead (prev: 5090 i3: 'Walk with me to Okran's Pride.' -> C:\KenshiTestRuns\imm26-5090\rows\IMM-19-b: canned no-place reply, no agreement row (proposed_by untestable)) | 2026-10-15 |
| IMM-19-c | active ACCEPTED trip | say: "Lead the way." | no renegotiation; one native task; plan_hash in the native receipt matches the row | n/a | BASE | SETUP-FAIL | no ACCEPTED trip can be created on E607 in this fixture (see 19-a/19-b) | 2026-10-15 |

### 20 Natural plan changes (A4; WP-D)
| ID | Setup | Utterance / action | Expected evidence | Negative control | Build | Status | Evidence | Date |
|---|---|---|---|---|---|---|---|---|
| IMM-20-a | FX-TRAVEL: trip ACCEPTED | say: "Actually, go to <other place> instead." | R~ references the original trip and asks to confirm; row destination unchanged until confirmed; after confirming old row ENDED/replaced | no active trip: plain proposal | BASE (exp FAIL: canned "Let's agree on the changed travel plans first") | SETUP-FAIL | no ACCEPTED trip to change (see IMM-19-a/b) | 2026-10-15 |
| IMM-20-b | FX-ROUTE [B]: force a path failure mid-trip | say: "Why did we stop?" | row failure reason (native_path_or_actor_failure); R~ names the original destination plus a grounded reason | no native failure evidence: "I can't tell" | BASE | SETUP-FAIL | no trip and no native path-failure fixture [B] (see IMM-19-a) | 2026-10-15 |
| IMM-20-c | after a FAILED or ENDED trip | say: "Walk with me to <place>." | new PROPOSED then ACCEPTED row; one active agreement | n/a | BASE | SETUP-FAIL | new PROPOSED row never created: 'Walk with me to Okran's Pride.' gave canned no-place reply (see IMM-19-b) | 2026-10-15 |

### 21 NPCs have their own priorities (A4; WP-D)
| ID | Setup | Utterance / action | Expected evidence | Negative control | Build | Status | Evidence | Date |
|---|---|---|---|---|---|---|---|---|
| IMM-21-a | FX-TRAVEL, same NPC three runs: well fed + healthy; hunger near zero (`stobe-auto hunger`); bleeding with limb damage | say: "Walk with me to <town>." | run 1 ACCEPTED row; runs 2/3 no ACCEPTED row and R~ "I need food first"/injury refusal; eventlog vs LOG state | run 1 is the control | BASE (exp FAIL: no mechanical gate) | SETUP-FAIL | control run 1 (fed, healthy) cannot get an ACCEPTED row: canned no-place reply (see IMM-19-b), so state-dependent refusal is untestable | 2026-10-15 |
| IMM-21-b | NPC on a native guard/job package, high affinity [B] | same | refusal or postponement grounded in the duty, no invented excuse | same NPC off duty agrees | BASE | SETUP-FAIL | needs [B] guard/job NPC fixture and a working accept path (see IMM-19-b) | 2026-10-15 |
| IMM-21-c | after 21-a run 2 | feed the NPC, repeat | agrees (proves state-driven) | n/a | BASE | SETUP-FAIL | depends on 21-a run 2 (no accept path) | 2026-10-15 |

### 22 Reactions during shared activities (A5; WP-E, N1)
| ID | Setup | Utterance / action | Expected evidence | Negative control | Build | Status | Evidence | Date |
|---|---|---|---|---|---|---|---|---|
| IMM-22-a | needs native event emitter; P-KEY; Hunt with player, hostile/goat in range | accept a Hunt, hostile appears | `EV(situated_event)` kind=threat plus one bored-turn remark within 120 s; `situated_remark_claim` row | no repeat for the same event_id | GATED: WP-E + N1 | GATED | WP-E + N1 not installed on E607; not run | 2026-10-15 |
| IMM-22-b | needs arrival producer: complete a travel trip | arrive | `EV(situated_event)` kind=arrival and a single remark | second bored tick within 180 s silent | GATED: WP-E + N1 | GATED | WP-E + N1 not installed on E607; not run | 2026-10-15 |

### 23 Clear activity endings (A4; WP-D)
| ID | Setup | Utterance / action | Expected evidence | Negative control | Build | Status | Evidence | Date |
|---|---|---|---|---|---|---|---|---|
| IMM-23-a | FX-TRAVEL: complete an agreed trip | arrive, then say any line | one completion acknowledgement next turn; row COMPLETED with owned_work_released true; no FOLLOW/travel controller left (`stobe_state`); NPC not in squad | n/a | BASE | SETUP-FAIL | no trip can be agreed on E607 here (see IMM-19-a), so no completion to observe | 2026-10-15 |
| IMM-23-b | non-faction NPC affinity >=56 (H-AFF) | say: "Follow me." then H-TIME +1 game day | follow ends by expiry (`stobe_state`, no controller) | n/a | BASE (exp FAIL: legacy follow has no expiry) | SETUP-FAIL | 5090 i3 Cind aff 60 platonic: 'Follow me.' -> canned 'I need to find a practical place before promising to lead us there.' no follow order (stobe_state first_order none, C:\KenshiTestRuns\imm26-5090\rows\IMM-23-b-a); expiry untestable on Cind | 2026-10-15 |
| IMM-23-c | FX-SQUIN member plus a temporary companion (non-squad) | say "Leave" to each; then END to each | "Leave" works only on the squad member; END ends only the temporary NPC | unrelated assigned job remains | BASE | UNRUN | | |
| IMM-23-d | active trip, an unrelated job on the NPC | withdraw mid-trip | only the owned order cancelled (receipt reason), other job intact | n/a | BASE | UNRUN | | |

### 24 NPC-chosen destinations and broad regions (A5; WP-E)
| ID | Setup | Utterance / action | Expected evidence | Negative control | Build | Status | Evidence | Date |
|---|---|---|---|---|---|---|---|---|
| IMM-24-a | FX-TRAVEL: NPC in a town with other known towns | say: "Where would you take me to find some peace?" | PROMPT "Grounded named-place choices"; R~ names a place from it; travel_decision NONE, no trip row; log candidate count | say: "What is Vain like?": no `region_plan` row | BASE (exp FAIL: KAH-CHAT-004) | FAIL | Hub rerun tainted (Shay went KO mid-run, speaker=Malzin): reply invents 'a place near the old salt flats' not in Known places [Stumble Inn, Squin]; Grounded named-place choices [] (C:\KenshiTestRuns\imm26-5090\rows\IMM-24-a-hub). Wilderness run: canned reply. Rerun with Shay conscious advised (prev: 5090 i3 FX-TRAVEL: 'Where would you take me to find some peace?' -> C:\KenshiTestRuns\imm26-5090\rows\IMM-24-a: reply is the canned 'I need to find a practical place before promising to lead us there.' instead of conversation; Grounded named-place choices [] in prompt; no region_plan row (KAH-CHAT-004 reproduced)) | 2026-10-15 |
| IMM-24-b | as 24-a | say: "Let's consider Vain as a general area, not an exact spot." | `EV(region_plan)` stage awaiting_route, then route_ready with a native candidate id or honest cannot_route_yet | active trip: blocked_by_existing_trip, trip untouched | BASE (exp cannot_route_yet: no `known_place` producer) | FAIL | Hub rerun tainted (speaker=Malzin): no region_plan row, reply claims 'I've got a route to Stumble Inn set' (invented) (C:\KenshiTestRuns\imm26-5090\rows\IMM-24-b-hub); wilderness run also no region_plan row (prev: 5090 i3: 'Let's consider Vain as a general area, not an exact spot.' -> C:\KenshiTestRuns\imm26-5090\rows\IMM-24-b: no region_plan eventlog row (no awaiting_route / cannot_route_yet); reply chat only ('Vain's got a few known paths... border markers' unsupported claims)) | 2026-10-15 |

### 25 Purpose-based goals (A5; WP-E)
| ID | Setup | Utterance / action | Expected evidence | Negative control | Build | Status | Evidence | Date |
|---|---|---|---|---|---|---|---|---|
| IMM-25-a | FX-ANIMAL [B] (goat in sight), P-KEY | say: "Let's hunt for raw meat." | LOG `ACTIVITY_PROPOSAL_DIAG emitted>=1`; `stobe_activity_record` kind=Hunt with catalog resourceId; R~ offer text names meat | no animal in range: no proposal, NPC says so, no invented herd | BASE | SETUP-FAIL | 5090 i3 Cind: 'Let's hunt for raw meat.' -> C:\KenshiTestRuns\imm26-5090\rows\IMM-25-a: ACTIVITY_PROPOSAL_DIAG gate=identity actorOk=0 actorSID empty (requesterSID=2061-gamedata.base), no proposal; reply discourages hunting. Goats are in fixture (200-320 m) but Cind has no native SID; no activity-transport.key beside D:\KenshiInst\3\mods\Stobe\Stobe.dll | 2026-10-15 |
| IMM-25-b | FX-MINE [B] (iron node), P-KEY | say: "Let's mine iron." | Mine record sourceId equals the node SID (not a UUID) | copper node: rejected by resourceId | BASE | SETUP-FAIL | needs iron node fixture [B] and an actor with SID (same identity gate as 25-a) | 2026-10-15 |

### 26 Activities as complete goal sequences (A5; WP-E, N1)
| ID | Setup | Utterance / action | Expected evidence | Negative control | Build | Status | Evidence | Date |
|---|---|---|---|---|---|---|---|---|
| IMM-26-a | FX-ANIMAL [B], P-KEY | accept the Hunt offer (25-a) | `stobe_activity_record` proposed -> accepted -> completed; NPC INV delta >=1 resourceId; participationOutcome set; outbox acknowledged | second "Let's hunt" while accepted: no second record (`stobe_activity_one_active_actor`) | BASE | SETUP-FAIL | no Hunt proposal can be accepted (see IMM-25-a) | 2026-10-15 |
| IMM-26-b | active Hunt (FX-ANIMAL [B], P-KEY), mid-travel | say: "Cancel that." | phase=cancelled, cleanupComplete=true; no stray NPC order; earlier orders kept | n/a | BASE | SETUP-FAIL | no active Hunt (see IMM-25-a) | 2026-10-15 |
| IMM-26-c | active Hunt (FX-ANIMAL [B], P-KEY); target dies or leaves | wait | re-plan, then Failed `no_observed_suitable_reachable_target` plus a terminal report | n/a | BASE | SETUP-FAIL | no active Hunt (see IMM-25-a) | 2026-10-15 |

## C rows (changes made by this program)
(added when each change lands, IMM-Cnn)

## Bugs found by these tests
(none yet)
