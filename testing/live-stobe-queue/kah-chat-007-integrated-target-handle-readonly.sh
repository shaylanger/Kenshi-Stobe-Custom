#!/usr/bin/env bash
# Immutable row emitter KAH-CHAT-007. Prints instructions only.
cat <<'ROW'
ROW KAH-CHAT-007 — exact-handle target resolver confirmation on integrated native build
Purpose: live read-only confirmation of exact `#serial/index` references after the reviewed native integration is installed. This does not test chat transport and does not block KAH-CHAT-005.

HARD INSTALL PIN: loaded Stobe DLL must be exactly `AEF84C0A682DF036EB2CD0DC30A809E52E19956933F142C3A1D5877C4EB1907C`, built from source manifest SHA `AD63A137D74CFE23DEFF8914B06C56B8DC51693E88FBDA55AE1E365EE7B0445C`; independent review is CLEAR, but isolated install route is still pending. Do not run until an operator confirms this exact installed/loaded SHA and the queue's instance mapping.

At the authorized isolated route, verify instance/PID, current world/backend/session identity, DLL SHA, and input isolation. Take one fresh `stobe-auto chars 300`; select a currently listed, live NPC with its exact current name and `#serial/index`. Do not reuse a historical handle if it has disappeared or changed. Then run only these read-only lookups:
  stobe-auto where "<exact current display name>"
  stobe-auto where "#<current serial>/<current index>"
Capture raw requests/responses and native log lines. The exact-handle query must resolve the same live actor identity as the fresh roster/name query with coherent position/distance. Record any name/alias discrepancy separately; do not issue chat or native orders.

PASS:
  RESULT KAH-CHAT-007 PASS rig=<4080|5090> instance=<n> DLL=AEF84C0A...1907C manifest=AD63A137...7B0445C world=<id> actor=<name> handle=<serial/index> chars=<receipt> where_name=<receipt> where_handle=<receipt> same_actor=yes
Setup stop:
  RESULT KAH-CHAT-007 FAIL setup: <install/world/session/current-target gate>
Resolver failure:
  RESULT KAH-CHAT-007 FAIL: <unsupported reference or identity mismatch plus exact read-only receipts>
ROW
