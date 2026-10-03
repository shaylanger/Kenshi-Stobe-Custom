# Master test plan (all features, one game)

Started 2026-10-02 (late). One coordinator session runs Kenshi and tests every feature in the same
launch; feature agents write scenarios and fix their own bugs. Roles, loop and scenario format:
`testing/README.md`. This file is the index: details stay in each feature's own plan.

| Feature | Owner | Detail plan (source of truth for rows) | Scenarios |
|---|---|---|---|
| STOBE (Stobe.dll + server) | coordinator | `STOBE_full_test_plan.md` (items numbered from 1, next 64) | `tests/ingame/stobe/` |
| KenshiFP (KFP) | coordinator | rows live in the STOBE plan (goal panel, FP mode) | `tests/ingame/stobe/` |
| Profession Gear (PG) | PG agent | `Kenshi-Profession-Gear-Progression/TEST_PLAN.md` (rows 1–320), status `INGAME_STATUS.md` | PG repo `tests/ingame/` |
| Relationship system (REL) | REL builder | `STOBE_relationship_system_audit_and_implementation_plan.md` (SR01–SR44), deliveries `isolated/relationships-phase1/DELIVERY.md` | `/root/stobe-work/social-phase1/server/tests/social_relationship/ingame/` |
| Automation harness (KAH) | coordinator (+ helper agents) | this file, section 5 | `C:\KenshiTestRuns\scenarios\` |

IDs: `<feature> <row>` (e.g. STOBE 41, PG 306, REL SR02, KAH 3). Run logs: `archive/test-run-<date>-m<n>.md`.

## 0. Builds under test

| Component | Installed | Pending install |
|---|---|---|
| Stobe.dll | `FF633947` | - |
| KenshiFP.dll | `5A2E2085` (goal panel + fp_* commands) | - |
| ProfessionGearProgression.dll | `D667F5EE` (pg_* commands) | - |
| AutomationHarness.dll | `527113C2` | - |
| Server (live) | `5f71138` (branch `stobe`) | REL phase 1 (`feature/social-phase1`, inert by default) once delivered |

## 1. Automated: runnable now

Status: `todo` / `PASS <run>` / `FAIL <run> -> bug` / `blocked: <why>`.

### 1a. Fixture `auto-home` (Shay + Malzin at Home)

| ID | What | How (short) | Status |
|---|---|---|---|
| STOBE 41 | No false "you have my katana" claim | re-equip katana, gear exchange, "What have I taken from you?" | todo |
| STOBE 43 | Two-part hand-over gives both items | give bread + dried meat, "give me all your bread and all your dried meat" | todo |
| STOBE 54 | Relationship talk by tier | `scenarios.sh trust` -80 / 60 / 96, prompt `<how_you_feel_about_them>` + words | todo |
| STOBE 55 | R4 fights count (superseded once REL is enabled) | `scenarios.sh duel`, server log `a fight counts (R4)` | todo |
| STOBE 56 | Relationship types from the list only | chats, check entries | todo |
| STOBE 57 | No entries for generic names | talk/fight an unnamed Hungry Bandit | todo |
| STOBE 58 | `stobe-reset-npc` save + `--restore` | WSL only, no game action needed | todo |
| STOBE 59 | Relationships follow the save | real insult/fight at T, reload fixture, `PLAYTHROUGH: restored` | todo |
| STOBE 48 | KO/death during a deal | `scenarios.sh surrender` + `ko` / `kill` | todo |
| STOBE 53 | Cap without a lie | surrender, "Make it 350" | todo |
| STOBE 60 | Cap tiers 0–2 | surrender with Dust Bandit and Hungry Bandit | todo |
| STOBE 61 | Cap tiers 3–5 (top-up) | spawn Samurai Sergeant / Dust King, beat, accept, 2nd deal | todo |
| STOBE 20 | Refuse to pay after hand-over | fight setup | todo |
| STOBE 21 | Pay-later breach | Fond trust, stop for pay-later, don't pay 1+ game min | todo |
| STOBE 22 | Gang stands down on paid deal | `gang 3` + pay | todo |
| STOBE 17 | Reputation voiced | set counts broken > kept, talk to a new NPC | todo |
| STOBE 14 | Buy from a trader | spawn Skeleton Traders near Home, "buy 3 bread from the trader" | todo |
| STOBE 15 | Goal needing trader stock -> approval | same traders | todo |
| STOBE A3 | Purchase event names the trader | talk to Malzin, then `trade Shay <trader> <food>` | todo |
| STOBE A4 | Fetch from a far chest walks there | goal status step "Walking to" | todo |
| STOBE A5 | Job list switches by itself (Malzin selected) | log `GOAL_JOB ui refresh replayed selection`, harness `screenshot` | todo |
| STOBE A6 / KFP | Goal panel above the job list | log `GOAL_PANEL created … (jobs widget)` + harness `screenshot` + `ui` | FAIL m1 -> STOBE 65 (rest OK: created at jobs widget, text, hidden for Shay) |
| STOBE A7 | "No room in pack" on-screen message | fill pack, ask for bread, harness `messages` | PASS m1 |
| STOBE A8 | Bread chain: well -> farm -> silo -> oven | `power` the silo, water, "make 2 bread" at 50x | todo |
| STOBE A10 | Mid-fight heal is known without saying | `order Shay FIRST_AID_ORDER target <npc>`, then talk | todo |
| STOBE A11 / A12 | Heal-for-item deal kept / broken | first aid via `order`, deal state | todo |
| STOBE A13 | Remembers earlier fight events | long fight, then ask | todo |
| STOBE A1 / A2 | FP mode: look-at click keeps control; put down with G | `fp_mode`, `fp_click`, `fp_putdown`, `fp_state` + KenshiFP.log | todo |

### 1b. Fixture `Crafting base` (benches, Malzin, apothecaries in town)

| ID | What | How | Status |
|---|---|---|---|
| STOBE 16 | Goal with a crafted ingredient: bench queue grows only by what's missing | goal at a bench | todo |
| PG crafting group | PG 85–92, 306 (+ weapons) | PG scenarios (pending from PG agent) | todo |

### 1c. Fixture `Trader` (Shay alone next to 5 real traders)

| ID | What | How | Status |
|---|---|---|---|
| PG trader group | PG 219, 237 | PG scenarios (pending from PG agent) | todo |

### 1d. Relationship system

| ID | What | How | Status |
|---|---|---|---|
| REL P1 smoke | Phase 1 merged inert (capture off), then shadow: raw events, identity, no affinity change, stale events rejected | REL scenarios (pending delivery) | blocked: delivery |

## 2. Requires specific game setup (no fixture/command for it yet)

| ID | What it needs |
|---|---|
| STOBE 18 | A dishonest NPC who dislikes Shay betraying a paid deal: rare by design; needs many tries or a forced-betrayal test switch |
| STOBE 25–37, 44, 45, 47, 49, 51 (section C) | LLM behaviours that haven't happened in game; checked passively: after every run grep the server/stobe logs for their log lines |
| KAH power charge | A battery building in a fixture (none has one) |
| PG rows | filled from the PG agent's `INGAME_STATUS.md` (NEEDS-SETUP) |

## 3. Requires Shay

| ID | What |
|---|---|
| STOBE A9 | TTS volume/fade: the setting and ini are checked automatically; how it sounds is Shay's |
| Voice / feel | Voice quality, overall play feel, relationship balance feel (REL §9) |
| PG rows | filled from the PG agent's `INGAME_STATUS.md` (NEEDS-SHAY), e.g. tooltip readability |

## 4. Bugs found (open)

Owner fixes; the coordinator reruns. Fixed + confirmed bugs leave this table (line in the run log).

| Bug | Owner | Found | What | Status |
|---|---|---|---|---|
| STOBE 64 | STOBE | stobe-tests | `negotiation_engine` regression: "unpaid -> BREACHED_PLAYER" backdates wall time but hostile deals expire on game time (stale test); "breach reaction queued" depends on it | open |
| STOBE 65 | KFP | m1 | Goal panel overlaps the Money/Day/speed box | open |
| STOBE 66 | STOBE | m1 | Work goal to "Home": destination_not_known (base registry pruned by cross-fixture loads, not re-detected) | open |

## 5. Harness (KAH) known limits / open items

| # | Item | Status |
|---|---|---|
| KAH 1 | `damage` wounds don't bleed (use `blood`) | limit, documented |
| KAH 2 | `messages`: no vanilla game message seen yet (Stobe's are captured) | open, watch |
| KAH 3 | `shopstock`/`trade` from a shop barrel: the game's trade event names "Old Wooden Barrel" as seller and the trader's cats don't change (affects STOBE A3) | open, check in STOBE A3 |
| KAH 4 | `faction` gives the NPC a new #serial | limit, documented |
| KAH 5 | `power charge` untested (no battery in fixtures) | needs setup |
| KAH 6 | Hover tooltips can't be read (PG 135–141) | open: try `ui` while hovering |
