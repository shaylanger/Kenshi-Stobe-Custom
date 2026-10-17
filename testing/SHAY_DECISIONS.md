# Open decisions for Shay (live file: keep current)

RULE (Shay 2026-10-16): every item that needs a Shay decision is recorded HERE with: what the problem is, the options, what each option does IN GAME (NPC-visible behaviour) and what it changes in the code/tests, and the default in use. HANDOFF "Right now" only points here. Asking Shay in a summary uses this text; a decision made is moved to the Decided section with date and answer. A coordinator ending without this file current is a handoff defect (process-ideas review checks it).

## Open

### RESOLVED 2026-10-16 22:08 (Shay topped up; llm-health OK) - was BLOCKER (2026-10-16 22:15): LLM provider balance is empty (HTTP 402)
- `bash tools/automation/llm-health.sh` -> `LLM-HEALTH FAIL http=402 {"error":{"message":"You need positive balance to do inference. Please add balance manually or setup top-up"`. Reported by imm26-4080-i4op24 (preflight + llm-health both FAIL), so EVERY in-game row that needs the chat LLM is blocked on every lane until the balance is topped up (the provider is the one in the lane's server config; CLAUDE.md says chat = DeepInfra, relationship eval = OpenRouter: top up whichever the health check reads).
- In game: NPCs cannot answer (no replies), so no row can pass; nothing is wrong with the mod. In code: nothing to change.
- What waits: 01-cx x3 and 02-dx x3 (4080-i4, `hxrun_v3cx.sh 01-cx 4080-i4 --save kah-imm26-4080-i4 ...`, `hxrun_02bd3.sh 02-dx 4080-i4 --save kah-imm26-4080-i4 ...`), 02-bx and 16-bx on 4080-i3 (op32), the 23-a/14-d/19-e reruns after their fixers, 26-a. The replay2 experiment uses the Anthropic API via `claude -p` and is NOT affected.
- Default in use: operators stop on LLM-HEALTH FAIL; I respawn them after Shay says the balance is topped up.


1) HUNT ROUTE GOAL (a/b/c)  - default (a)
   Problem: a Hunt offer's route goal is a landmark ("outside Outlaw Watch to the west"), but the agreed animal is bound by exact serial and never swapped (ActivityRuntimeBindings.cpp:384-394). In the real world the animal is NOT at the landmark (test: ~1260 u away; the 26-a recipe fakes it by teleporting the goat to the goal). So in real play the NPC walks to the landmark, scans, finds no agreed animal, and gives up ("no_observed_suitable_reachable_target").
   (a) Route to the animal's own position / an approach point near it: NPC walks straight to where the animal actually is, then hunts it. Code: route kind observed_source instead of landmark in the Hunt offer + resolveRoute; the 26-a recipe then no longer needs to pin the goat at the goal. Most faithful to "go hunt that animal"; costs a server+recipe change.
   (b) Accept a nearby same-source substitute after arrival: NPC goes to the landmark, and if the agreed animal isn't there, hunts another animal of the same kind that is nearby. Code: loosen the exact-serial binding after arrival; risk: NPC kills a different animal than was agreed (breaks the agreed-target rule).
   (c) Refuse Hunt offers whose route goal is > ~300 u from the animal: NPC says no / proposes nothing when the landmark is far from the animal. Code: one distance check at propose time; safe but Hunt offers become rarer (most landmarks are far from animals).
   Does not block the NC30 test (recipe still pins the goat). Default (a).

2) MINE: fix26froute rebind  - default NO
   Problem found on 26-f: the native side re-issues every route row with a NEW counter id (and 0.002 y drift) whenever the context snapshot is > 30 s old or the NPC moved > 30 u. The server's ACCEPT re-check requires the EXACT stored id/coords, so a "Yes" that comes > ~30 s after the offer fails ("No currently grounded route candidate"). Hunt is already fixed by imm26-u4b (re-bind to a current row near the stored point). The staged patch (pending-fixes/imm26-fix26froute) extends that re-bind to ClearGroup (27/27 offline checks, mutations killed). The decision: ALSO extend it to Mine?
   In game: yes = a miner who is offered a mining route and told "yes" late (after walking/talking > 30 s) still starts mining; no = that late "yes" is rejected and the NPC says no suitable route / you must re-ask. Code: add Mine to stobeActivityKindRouteRebinds() (1 line) + the u4b test that currently asserts Mine stays EXACT (E2) must be changed. Default no: leave Mine exact, apply only the ClearGroup patch. (Late-yes failures then remain for Mine.)

3) OWN-PRESENCE PROMPT RULE  - default OFF
   Problem (15-bx): asked "who started the fight?", a far NPC who saw nothing invents that she was there ("I came in after it was done", "I saw her open on Fenn"). No fight data was in her prompt (the DLL correctly sent none): the model confabulates her own presence.
   Proposed fix: one sentence added to every NPC's situated-knowledge prompt: "Your own presence needs evidence too: unless a supplied event of yours puts you at the scene, never say or imply you arrived at / came in on / caught any part of an incident; say you did not see it."
   In game ON: NPCs stop claiming to have arrived at fights they weren't at; they say "I didn't see it". Risk: it touches EVERY NPC prompt, and the live test on 15-bx still FAILED with the sentence present (X1 passed; X2/X3 still said "I came in after it was done" - X3 also cites X1 since all three share one chat thread), so effect is unproven.
   Default OFF (do not ship an unproven change to every prompt). If you want it tried: rerun 15-bx with independent threads (different far NPCs); if the sentence still doesn't stop it, the stronger fix is an explicit "Incidents you witnessed: none" field in the prompt facts instead.
   Related sub-question: does a pure clarifying reply ("Over where?") count as satisfying the hedge requirement? Recommendation: NO, keep strict.

4) 15-bx SPLIT  - default YES
   CAVEAT: label only; my reading from the reports. 15-bx currently bundles two different things: (i) DELIVERY - does the DLL send fight events to NPCs far away / asleep? (checks show no fight lines in the far NPC's prompt at 326 u > the 200 u shout radius = delivery is correct) and (ii) HONESTY - does the model refuse to claim it saw the fight (the confabulation in item 3), plus the sleeping/KO NPC S1 measurement. One row can't pass/fail both cleanly.
   Split YES: 15-bx-a (events reach only NPCs within max(ShoutRadius 200, TalkRadius 80); asleep/KO S1 handling) = code-logic test, expected to PASS; 15-bx-b (no invented eyewitness claim) = model-behaviour test, stays open/FAIL until item 3 is decided. No game change; rows and checker get separated so a real delivery PASS isn't hidden behind a model-wording FAIL. Split NO: one row keeps failing until the model stops confabulating.

5) 01-cx: judge the WHOLE REPLY vs the STRICT FIRST SENTENCE  - no default recorded (v3cx currently gates on the whole reply)
   Row: a hostile-faction stranger should be guarded/unfriendly; an allied stranger should not be.
   Strict first sentence (row text as written): only the NPC's first sentence counts. Old checker used this and failed correct behaviour: replies that open with a fragment or a polite word then say the unfriendly thing in sentence 2 ("People who work. Slave Hunters ... I've got neither" read as not guarded; 4080 stored runs v2 FAIL 4/6). In game it matches "the very first words out of her mouth show wariness".
   Whole reply (v3cx, committed 42c5fe08): any part of the reply with guarded markers ("keep your distance", "state your business", "you're bait") counts. Same stored runs PASS 6/6, and mutations (open/friendly/warm hostile reply, guarded allied reply) still FAIL. In game it matches "she comes across as guarded in what she says", not necessarily in the first sentence. Opening-sentence-only reading was 3,2,1,2,0,2 out of 3 across the six sets, so a strict first-sentence rule would fail honest-looking NPCs.
   My recommendation: whole reply (v3cx); the opening sentence is often a short fragment. If Shay wants the first sentence to carry it, the NPC prompt (not the checker) must be changed to force an unfriendly opener.

6) PI-66 raise CLAUDE_CODE_MAX_CONCURRENT_SUBAGENTS (settings env) - Shay applies (edit by Claude denied as self-modification). Effect: more than 20 subagents at once (replay waves, lane operators + fixers); only from the next session start. Default: not set.
7) PI-51 / PI-62 hook swaps - PI-51 APPLIED 2026-10-16 20:3x (persistent waker via Monitor, backup C:\KenshiTestRuns\backup\kenshi-waker-guard.ps1.pre-pi51). PI-62 swap pending: cd /c/KenshiModding/pending-fixes/pi62-sweep-auto && powershell -NoProfile -ExecutionPolicy Bypass -File swap.ps1 (Shay runs it; Git Bash needs forward slashes or a cd).

## Decided
- PI-62 (auto-sweep) and its extra delete patterns (selftest-all*, scratch-*, coordinator.heartbeat.*.tmp, dur_run*.sh): YES, Shay 2026-10-16.
- PI-66 / PI-51 confirmed by Shay 2026-10-16 (PI-51 applied).

- 2026-10-16 (Shay, "3: a"): 16-bx word cap = option a: add a trait brevity line so reserved/terse NPCs answer in <= 40 words; fixer imm26-fix16bxbrevity.
