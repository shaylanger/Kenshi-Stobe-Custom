# KAH-CHAT-003-FOLLOWUP — direct yes/no Heft invitation (4080 i3)

**State:** prepared for independent exact-hash review and a fresh row-specific Agent Validator review. Not queued, not dispatched, and not authorization to contact the rig.

## Scope and prior evidence

This is one direct conversation turn to determine whether Apothecary Matsuyo is willing to travel to Heft after the previous Heft invitation received an unrelated supply/duty answer. The prior turn is terminal and must not be repeated: request `k1791936847351_692_1`, receipt `pending-fixes/rig4080-validation/chat-003-voluntary-travel-proposal-4080i3-20261014.md` (SHA-256 `6BF22333992557C55840E72AA2AE6A82F9F4A1306D239870AFE3EC9332AE3DA1`). This packet uses the next direct invitation already recorded as Validator-cleared in `testing/live-stobe-queue/queue-4080.md`.

## Immutable runtime pins

- Host/route: `DESKTOP-NQQPA73`, isolated Kenshi instance 3 only.
- Stobe DLL: `AEF84C0A682DF036EB2CD0DC30A809E52E19956933F142C3A1D5877C4EB1907C`.
- Harness DLL: `974DBA03F136D6CB08153F29ACC497C485C39BAECEB8BF50C8B5291661D3025D`.
- Private backend: `127.0.0.1:18084`, bound to this same isolated world/session.
- Intended actor: `Apothecary Matsuyo`, handle `#816894528/1`, only if fresh exact-name and exact-handle reads still identify the same living actor.
- Intended destination: `Heft`, only if it is currently listed/valid in this world.

Every pin is a fresh pre-send gate; old PID/save/session/position/health evidence is not reusable. Require a fresh generation/session-ready receipt bound to the current world/save and exact active PHP manifest plus full prompt/history capture. Earlier notes explicitly leave the generation join unconfirmed; if it cannot now be proven, stop before sending.

## Fresh preflight and stop conditions

1. Verify protected host identity, isolated i3 paths (`KAH_INSTANCE=3`, `KENSHI_DIR=/c/KenshiInst/3`, `KAH_DIR=C:/KenshiInst/3/mods/AutomationHarness`), one current game PID, unpaused world, current save/world/player, exact loaded Stobe/Harness paths and hashes, input isolation ON, and private backend health/schema/session readiness. Do not change focus or use keyboard, mouse, UI, save, config, or service controls.
2. Require a fresh session-generation identity joined to the same current save/world and backend. Capture active PHP source manifest and full prompt/history bytes before dispatch. Missing/stale/ambiguous evidence is `FAIL setup`; no send.
3. Confirm Heft is a valid destination now. Refresh target by exact name and `#816894528/1`; both reads must identify the same living Matsuyo, and a fresh state read must provide the before snapshot for that actor (trip/agreement, goal, orders, player orders, destination, movement/dispatch). If actor identity differs, is dead, or state cannot be captured, stop. Do not substitute a different NPC or stale target.
4. Confirm no unresolved/active trip or pending agreement makes a new consent outcome ambiguous. Capture a backend correlation cursor. Before sending, require the inbox and inbox-lock to be absent; never inspect, clear, or consume them if present.
5. Obtain a fresh row-specific Agent Validator CLEAR for this exact immutable packet and verify the independent exact-hash review. Then use the guarded PowerShell 5 → Git Bash stdin route documented in `testing/live-stobe-queue/4080-i3-command-route.md` exactly once.

## Exact one-turn body (`body.sh`)

```bash
export RIG=4080 KAH_INSTANCE=3
export KENSHI_DIR=/c/KenshiInst/3 KDIR=/c/KenshiInst/3
export KAH_DIR='C:\KenshiInst\3\mods\AutomationHarness'
. /c/KenshiModding/tools/automation/rig-env.sh
rig4080_i3_preflight || exit $?
stobe-auto stobe_say "Apothecary Matsuyo" "I mean the trip itself: would you want to travel with me to Heft, yes or no? It is completely fine to say no."
```

The byte-pinned body file is `body.sh` in this directory. Invoke only via the guarded `remote-bash-stdin-4080.ps1 -BodyPath ...` route in `4080-i3-command-route.md`; its fresh output is setup evidence, not a substitute for the gates above.

No `ui` suffix, nearest-target lookup, movement/order command, additional player acceptance, clarification, retry, or second turn is allowed in this row.

## Evidence and verdict

Capture the exact request ID and timestamp; native full-text `TEST_INBOX` and player echo; exact target handle; correlated backend and model decision/output; every native NPC speech segment; and a same-actor post-state compared with the captured baseline. Keep full reply text and artifacts in the durable receipt.

- If the NPC clearly says yes, verify that any agreement/goal/order/dispatch matches the explicit Heft offer and occurs at most once; record the exact lifecycle stages observed. Do not issue a follow-up command to make it happen.
- If the NPC clearly says no, require no agreement, trip start, or movement dispatch.
- If the reply is conditional, equivocal, off-topic, missing, or conflicts with the structured decision, record a dialogue/product or evidence failure as appropriate; do not infer consent or send again.
- Any missing correlation or post-state after a send is `FAIL evidence`, not setup failure and not grounds for a retry.

Suggested single result line:
`RESULT KAH-CHAT-003-FOLLOWUP PASS|FAIL <consent classification>; request=<id> target=Apothecary-Matsuyo#816894528/1 backend=<event> reply=<native lines> state_before_after=<receipt> lifecycle=<observed>`

No rig operation, KAH command, backend call, game launch, save/config mutation, queue mutation, or gameplay occurred while preparing this packet.
