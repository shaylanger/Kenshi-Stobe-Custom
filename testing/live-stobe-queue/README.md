# Direct Stobe chat rows (2026-10-13)

These immutable row emitters print an operator command and receipt checklist. They do not execute KAH, contact a rig, query the backend, or manufacture a result. Use them only after an authorized rig operator confirms all row gates.

## Row files

| ID | Purpose | Dependency |
|---|---|---|
| `kah-chat-001-greeting.sh` | Direct greeting/readiness smoke | Fresh host/build/save/NPC/session gate receipt |
| `kah-chat-002-local-knowledge.sh` | Ask the target to name the verified current town | Row 001 PASS; fresh host/build/save/NPC/session gate receipt |
| `kah-chat-003-voluntary-travel-proposal.sh` | Ask whether the target wants to travel voluntarily to Heft | Row 002 PASS; fresh host/build/save/NPC/session gate receipt; no active trip unless its before/after state can be inspected |
| `kah-chat-004-greeting-target-gated.sh` | 4080 replacement greeting with matching target identity across `chars`, `where`, and `stobe_ping` | Fresh unique name + serial/index match, alive and <=80, session/build/save gates; one send only |
| [`kah-chat-005-nearest-multiword-greeting.sh`](kah-chat-005-nearest-multiword-greeting.sh) | Current-world direct multiword greeting through fresh `@nearest` and ACKed native handle | Current isolated world/save/backend identity and installed Stobe SHA; fresh nearest ACK/native handle alive and <=80; reviewed Base64-safe Bash payload; no chars-name/native-alias equality gate |
| [`kah-chat-007-integrated-target-handle-readonly.sh`](kah-chat-007-integrated-target-handle-readonly.sh) | Exact `#serial/index` resolver check on the integrated native build | Exact Stobe SHA `AEF84C0A...1907C`, manifest `AD63A137...7B0445C`, isolated install route and current live actor; read-only only |
| `kah-ui-003-stobe-chat-hotkey-isolated.sh` | Stobe chat hotkey, textbox caret, slash draft, fresh untouched close | Exact loaded Stobe hotkey-candidate hash; isolated injected input + UI/screenshot evidence |
| `kah-ui-004-kenshifp-toggle-key-isolated.sh` | KenshiFP binding capture, persistence, reset and guards | Exact loaded current KenshiFP hash; isolated injected input + UI/INI evidence |

`kah-ui-001-stobe-chat-hotkey.sh` and `kah-ui-002-kenshifp-toggle-key.sh` are preserved but superseded; do not execute because their input method was ambiguous.
For the 4080 greeting, KAH-CHAT-001 is superseded by KAH-CHAT-005; see `CHAT-ROW-STATUS-20261013.md`. KAH-CHAT-004 remains a stricter historical target-name consistency row. KAH-CHAT-002 depends on KAH-CHAT-005 PASS, and KAH-CHAT-003 depends on KAH-CHAT-002 PASS.

`kah-chat-006-target-identity-readonly.sh` is preserved as an unpinned draft; KAH-CHAT-007 replaces it with the exact integrated build pin.

Run a row file only to print its instructions, for example `bash kah-chat-001-greeting.sh`. Copy the printed KAH command only after completing the gates. The command must be issued directly as `stobe-auto stobe_say "<exact verified NPC name>" "<utterance>"`; there is no `ui` suffix, UI command, focus action, or OS input.

For trusted 4080 PowerShell 5 calls, use the [instance-3 Base64 command route](4080-i3-command-route.md). Its read-only preflight proves the isolated paths and stops on a pending or locked inbox without opening or changing it.

## Common preconditions

Record the actual rig, isolated instance, PID, exact copied-save identity, loaded save shown by `stobe-auto status`, target `where` identity (name plus serial/index), and verified current town from the city-start/location receipt. `currentTown` is not a KAH command. Recheck the installed Stobe DLL SHA-256 on the loaded install and confirm the harness endpoint/instance mapping before every row. Expected current baselines from the queue ledger are:

| Rig | Route | Copied save | Expected Stobe SHA-256 | Additional gate |
|---|---|---|---|---|
| 4080 | isolated instance 3 | Current isolated `newgame:Empire Citizen` is validator-cleared and valid; no copied-save-only gate | `40414D8C70E5E377D2FE1EB8C42C167D6B21F3D20CD7077B5ECB8D5661E7101D` (reverified) | Backend 18084 HTTP200; latest `chars`+`where Ulvik` show #520507808/7 at 61.7m but `stobe_ping nearest=none`; no chat sent. Wait for fresh named nearest target <=80. |
| 5090 | isolated instance 1 | `kah-fresh-start-5090-copy-20261013-152239` | `85A731C788AEDE86D76CDF1DFDDBBA448A64697EB262220AFCC24B02D9FCCE0A` | Session POST recovered, but KAH reports loaded campaign identity mismatch; hold chats until identity is resolved |

These are expected queue baselines, not proof of current state. Any mismatch, missing receipt, wrong instance, absent target, invalid native session, or stale build identity stops the row before chat and records `RESULT <ID> FAIL setup: <specific observed mismatch>`. The validator-cleared isolated `newgame:Empire Citizen` is an acceptable 4080 test world; do not impose a copied-save-only gate. Do not retry an unchanged setup. Allow the documented ~8 seconds after `wait-world` before the first `say`.

ActivityGoals rows are separately pinned under `../live-activity-queue/`. They cover seven lifecycle cases and print BLOCKED until an exact reviewed, composed native+server release is installed on the rig. Component hashes are not install pins.

## Evidence and result rule

For a PASS, the operator must preserve one correlated evidence bundle containing: the exact row/utterance and time window; native Stobe log `TEST_INBOX: say` for that utterance and the target's native reply; backend event/dialogue record for the same actor and time; and the relevant before/after durable trip state (plus relationship state if it changed). A KAH ACK or plausible NPC wording alone is never enough. For rows 001 and 002, verify no unrelated trip state was created/changed; row 002 must leave any pre-existing trip state unchanged. Row 003 is only a proposal: record the proposed/decision state and prove that no acceptance, trip start, or movement dispatch occurred without explicit NPC consent. If the operator cannot capture any required native/backend/state evidence, report `FAIL evidence: <missing evidence>` or `INCONCLUSIVE`; never print PASS.

For delayed chat responses, use the bounded correlation helper in `tools/stobe-chat-correlation.py` on copied log files. It links the KAH request ID, exact target/utterance, backend request ID and HTTP result, and later native NPC reply using explicit rig timezone offset. Missing evidence at an observation cutoff is `PENDING`, not a terminal no-response classification. See `pending-fixes/stobe-chat-correlation/README.md` and its synthetic copied-log regression fixture.

Each row emitter shows its exact PASS and setup-failure `RESULT` forms. Replace bracketed fields with observed receipts only. Scripts are immutable by ID: later revisions must use a new ID and preserve the earlier file.
