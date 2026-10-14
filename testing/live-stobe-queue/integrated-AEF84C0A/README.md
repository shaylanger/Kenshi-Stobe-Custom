# Integrated Stobe candidate runtime rows

These immutable row emitters print operator packets only; they never connect to a rig, install a DLL, issue KAH commands, or alter a game/save. Every row is **BLOCKED until safe isolated staging completes**. Exact Stobe DLL pin: `AEF84C0A682DF036EB2CD0DC30A809E52E19956933F142C3A1D5877C4EB1907C`; exact source manifest SHA-256: `AD63A137D74CFE23DEFF8914B06C56B8DC51693E88FBDA55AE1E365EE7B0445C`; payload manifest SHA-256: `475B58A78C02377C3B67B1F7F6677F7E9AD912F018EC737CDE85807AB6D7FB0A`. Independent package review is CLEAR for integrity/source inclusion, not release readiness. Safe isolated staging is pending; do not use the shared-Steam installer.

The source manifest confirms this package includes the Stobe slash hotkey, NPC selection refresh, portraits/fallbacks, and native travel TTL/provenance. The separately packaged KenshiFP payload hash is `50C1698688D65E2A548C43E7C38F694BD28383FEEA36C1F269D990F2B574D270`; it is not part of the Stobe DLL hash. The ActivityGoals release candidate is explicitly excluded from this package; do not execute ActivityGoals gameplay rows against it.

## Rows

| ID | Scope | Bound |
|---|---|---|
| `KAH-INT-001` | Chat `/` open, textbox focus, literal draft, fresh untouched close | 5 min |
| `KAH-INT-002` | NPC Info follows selected target across two live humans | 5 min |
| `KAH-INT-003` | Two humanoid portraits: face, headgear removal, natural color, no stale target | 8 min including visual review |
| `KAH-INT-004` | Private-render failure falls back to native atlas | Fails setup unless exact candidate has a documented safe hook |
| `KAH-INT-005` | Both render paths unavailable falls back to initials | Fails setup unless exact candidate has a documented safe hook |
| `KAH-INT-006` | Travel TTL/provenance refresh and exact endpoint/status | 12 min, including >600,000 ms wait |

Run on both rigs where the operator confirms matching isolated candidate staging and test context. By default, each rig needs its own verified isolated instance and copied save, PID/instance/save receipt, exact loaded DLL and source/payload manifest receipt, fresh world/authenticated backend readiness, and recorded configs. The narrow `KAH-INT-001` local-UI-only exception is defined in [`kah-int-001-local-ui-exception-5090.packet.md`](kah-int-001-local-ui-exception-5090.packet.md): it waives only authenticated backend/session readiness; it still requires the exact isolated instance, copied save, PID, loaded build/manifests, config, unpaused world, and input-isolation/focus gates. No backend request is made by that row. For travel, require the exact matching private backend/API pin from the staging receipt; if absent, stop as setup FAIL. Never use live user saves, production/shared services, or an old binary's result as evidence for this build.

For every UI key/click row: first require `stobe-auto input_isolation on`, then `stobe-auto input_isolation status` with `isolation=on` and `focused=0`; keep that real foreground status through the row and recheck after interactions. Every click/key must be a KAH `mouse_inject`/`key_inject` or documented isolated helper only. No physical input, AppActivate, foreground changes, or focus helper. ACKs are transport only. Retain read-only UI state (`stobe-auto ui`, `stobe-auto stobe_npcinfo read`, and where relevant `stobe-auto fp_keys state`) plus screenshot/log evidence.

Each completed row has exactly one `RESULT <ID> PASS|FAIL ...` line. PASS requires actual behavior plus the row's captured evidence, not command ACKs. Setups that are not staged remain blocked; missing forced-failure hooks are setup failures, never product failures. The bounded timer starts after all setup gates clear; stop at the bound and report INCONCLUSIVE when the assertion was not reached.
