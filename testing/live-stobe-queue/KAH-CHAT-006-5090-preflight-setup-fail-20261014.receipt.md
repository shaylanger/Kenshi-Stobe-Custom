# KAH-CHAT-006 — 5090 read-only identity preflight

**Result:** `RESULT KAH-CHAT-006 FAIL setup: fresh chars 80 contained only the player; no distinct live NPC target was available for exact-name versus #serial/index comparison.`

**Observed:** 2026-10-14T02:53:58Z, host DESKTOP-JFLPK99. No chat, UI, keyboard, mouse, focus, save, or game-state action was issued.

## Exact row and build checks

- Reviewed row script: `testing/live-stobe-queue/kah-chat-006-target-identity-readonly.sh`, SHA256 `CBDC2B69192A5AE4A7A2AAD2032B9923B172A4DD177044AF806BE8BFEB2F1397`.
- Isolated main-install instance 1: PID 86884, executable `D:\Steam\steamapps\common\Kenshi\RE_Kenshi\kenshi_x64.exe`, process responding.
- KAH world/save: `phase=world save=kah-5090-legacy-auth-20261013-1740`, `paused=0`, `speed=1.0`, player Beak.
- Loaded Stobe module: `D:\Steam\steamapps\common\Kenshi\mods\Stobe\Stobe.dll`, SHA256 `AEF84C0A682DF036EB2CD0DC30A809E52E19956933F142C3A1D5877C4EB1907C`.
- Loaded AutomationHarness: `D:\Steam\steamapps\common\Kenshi\mods\AutomationHarness\AutomationHarness.dll`, SHA256 `974DBA03F136D6CB08153F29ACC497C485C39BAECEB8BF50C8B5291661D3025D`.
- Source manifest SHA256 `AD63A137D74CFE23DEFF8914B06C56B8DC51693E88FBDA55AE1E365EE7B0445C`; it includes `src/TestInboxTargetRef.h` at SHA256 `CA50BAE4D01AB610455D56CEBB35623B7A9B3EE358471474602CAE52261DD418`.
- Payload manifest SHA256 `475B58A78C02377C3B67B1F7F6677F7E9AD912F018EC737CDE85807AB6D7FB0A`.
- Read-only session result: `ready|current_campaign|false|t|t`; canonical and session identity fingerprints matched (`4041de5d5c481056bf2a49ca33be441abca2eeeaa25b1acf46930ff23a089b64`). Raw identity and token were not emitted.
- Backend `127.0.0.1:8083`: HTTP 200; database and schema ready, no missing database items.
- Input isolation remained ON with `focused=0`, window on DISPLAY2.

## Target gate

Fresh KAH `chars 80` returned exactly one entry: player Beak `#3172973568/2` at distance 0.0. No external actor was in the returned target set, so querying a stale or guessed target handle would violate the row's fail-closed rule. `stobe_ping` separately reported nearest `Trov [Gate Guard Mtislav]`, but that actor was not present in the fresh `chars 80` list and was not queried. No `where` command was issued, no native request was created, and no gameplay result is claimed.

**Next safe step:** wait for a distinct live NPC to appear in a fresh `chars 80` response, then re-run only this read-only identity row after the required fresh gates. Do not reuse a stale handle.
