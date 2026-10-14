#!/usr/bin/env bash
# Immutable instruction emitter NPC-AGE-001. Prints the gated offline row only.
cat <<'ROW'
ROW NPC-AGE-001 — in-memory profile-age persistence/render fixture (BOTH RIG QUEUES)
STATUS: BLOCKED until all file hashes below are independently matched in the operator's isolated scratch copy and a PHP CLI route with network/database access disabled is confirmed. This emitter does not execute the fixture or connect to any rig/service.

Purpose: exercise lazy JSONB metadata persistence, JSON-string reload/idempotence, concurrent-edit CAS protection, stable identity metadata, and the age line rendered by the in-game biography view, using only the fixture's disposable in-memory adapter. This is not a real PostgreSQL integration test.

Exact file pins (SHA-256):
  pending-fixes/npc-profile-age/persistence-render-regression.php  FAA6922D6515F4300B2CDDC04E1877C65EC5680B75764E788D268814DB6D78A0
  pending-fixes/npc-profile-age/profile_age.php                    062BEEF9B9C72FBC9CBCFD58B9ACCC3BAF28CFA1E36F3F1B325CFF847DC0A73C
  pending-fixes/npc-profile-age/live/lib/profile_age.php            062BEEF9B9C72FBC9CBCFD58B9ACCC3BAF28CFA1E36F3F1B325CFF847DC0A73C
  pending-fixes/npc-profile-age/live/lib/npc_player_view.php        EAC57731EC462B3DAD0E696C15DCF863215F04AAF2A14603DAA7BF0EC8A88C8F
  pending-fixes/npc-profile-age/live/lib/data_functions.php         B5C497158537F23E698E9D1981A837882B5E26FF73DAF2CD97C746EAC8B4CDFE
  pending-fixes/npc-profile-age/merge/lib/profile_age.php           062BEEF9B9C72FBC9CBCFD58B9ACCC3BAF28CFA1E36F3F1B325CFF847DC0A73C
  pending-fixes/npc-profile-age/merge/lib/npc_player_view.php       EAC57731EC462B3DAD0E696C15DCF863215F04AAF2A14603DAA7BF0EC8A88C8F
  pending-fixes/npc-profile-age/merge/lib/data_functions.php        1F49B3EE97E18A8E40571CE2230EFA60ACF92944A725FDB4FFA4CDC46BC85410

Before execution: use a disposable isolated scratch copy; compare every listed SHA exactly; verify PHP CLI exists; disable network access and ensure no application DB bootstrap/config/credentials are supplied. If any condition cannot be proven, stop before PHP execution. Do not run the fixture from the live/merge application tree; use the pinned test fixture and its in-memory adapter. The fixture must not be modified.

Exact commands, from workspace root after the gates:
  sha256sum pending-fixes/npc-profile-age/persistence-render-regression.php pending-fixes/npc-profile-age/profile_age.php pending-fixes/npc-profile-age/live/lib/profile_age.php pending-fixes/npc-profile-age/live/lib/npc_player_view.php pending-fixes/npc-profile-age/live/lib/data_functions.php pending-fixes/npc-profile-age/merge/lib/profile_age.php pending-fixes/npc-profile-age/merge/lib/npc_player_view.php pending-fixes/npc-profile-age/merge/lib/data_functions.php
  php -l pending-fixes/npc-profile-age/persistence-render-regression.php
  php -l pending-fixes/npc-profile-age/live/lib/profile_age.php
  php -l pending-fixes/npc-profile-age/live/lib/npc_player_view.php
  php -l pending-fixes/npc-profile-age/live/lib/data_functions.php
  php -l pending-fixes/npc-profile-age/merge/lib/profile_age.php
  php -l pending-fixes/npc-profile-age/merge/lib/npc_player_view.php
  php -l pending-fixes/npc-profile-age/merge/lib/data_functions.php
  php pending-fixes/npc-profile-age/persistence-render-regression.php

Required receipt: rig and isolated scratch identity; network-off proof; PHP version; all exact observed hashes; all lint outputs; fixture output; confirm no DB endpoint was contacted. The fixture must print its assertions/result itself. Do not convert static review or a prior run into a current PASS.

PASS only if exact pins match, all seven PHP lint checks pass, the unmodified fixture completes its expected assertions, and the receipt proves the in-memory-only/no-network boundary:
  RESULT NPC-AGE-001 PASS rig=<4080|5090> fixture=FAA6922D...6D78A0 deps=exact lint=7/7 assertions=<observed> db=none network=off receipt=<path>
Setup/block:
  RESULT NPC-AGE-001 FAIL setup: <first precise mismatch or unproven isolation/PHP gate>
Fixture failure:
  RESULT NPC-AGE-001 FAIL: <actual fixture/lint failure and receipt path>
ROW
