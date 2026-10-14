#!/usr/bin/env bash
# Immutable replacement greeting row KAH-CHAT-004. Prints instructions only.
cat <<'ROW'
ROW KAH-CHAT-004 — 4080 direct greeting with verified exact target identity
Replaces KAH-CHAT-001 for the 4080 greeting after the target mismatch. Scope: one safe direct greeting only.

Required lane/build gates: authorized 4080 operator; isolated instance 3 and copied save `kah-fresh-start-4080-copy-20261013`; live process/PID and loaded Stobe SHA rechecked against the current queue ledger; native session/readiness gate freshly passed. Record each observed value. A mismatch is setup FAIL before chat.

Fresh read-only target gate immediately before the single send:
1. `stobe-auto chars 80` — identify one candidate and record exact displayed name, `#serial/index`, distance, and alive state (not KO/DEAD).
2. `stobe-auto where "<candidate exact name>"` — require the same exact name and identical `#serial/index`; require alive/not KO and distance <=80. If duplicate names make identity ambiguous, stop.
3. `stobe-auto stobe_ping` — require the bridge response's `nearest=` name to equal that same exact candidate name. Since ping reports a name rather than a handle, the chars/where serial-index match must be unique in the live `chars 80` result. If ping names another NPC, returns none, or any observation is stale/disagrees, stop.
4. Preserve all three read-only outputs with one timestamp window. Recheck that the candidate remains within 80 and alive immediately before sending; if it vanishes or changes handle, stop. Do not retry a failed gate or a failed send unchanged.

Only after all gates match, issue exactly once with the verified exact name substituted:
  stobe-auto stobe_say "<verified exact name>" "Hello there. How are you doing today?"
No `ui` suffix. Do not use UI, keyboard/mouse input, or focus operations.

PASS requires the matching native `TEST_INBOX: say`, target's native reply, correlated backend dialogue/event record, and before/after durable trip state proving no trip/dispatch was created by the greeting. KAH ACK alone is not evidence. Record paths/IDs/time window, target handle, and baseline state.
Expected RESULT PASS form:
  RESULT KAH-CHAT-004 PASS rig=4080 instance=3 target=<exact name #serial/index dist<=80 alive> ping=<matching nearest receipt> native_say=<log:line> reply=<log:line> backend=<event-id> trip_before_after=<receipt>
Setup stop form (no utterance issued):
  RESULT KAH-CHAT-004 FAIL setup: <specific host/build/save/session/target identity/range/alive mismatch>
Evidence stop form (utterance may have been sent):
  RESULT KAH-CHAT-004 FAIL evidence: <specific missing native reply/backend/trip receipt>
ROW
