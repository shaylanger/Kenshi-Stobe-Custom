# NC Stobe.dll install on 5090 lanes i4 and i5 (2026-10-15, imm26-install-nc-5090)

DLL `NC\Stobe.dll` SHA256 `4D18E32CE45C08B799B56A9FC5E998BAFC270C3F1881543573C61BFAB3568766`. i3 NOT touched (operator imm26-5090-i3op2 still RUNNING); Shay's Steam install NOT touched.

Active plugin path per runbook = `D:\KenshiInst\<n>\mods\Stobe\Stobe.dll` (was E607 e60752c8...); the stray `RE_Kenshi\mods\Stobe\Stobe.dll` (was e64c6593...) was replaced too so both agree. Backups: `D:\KenshiInst\4\imm26-backup-nc-*` and `D:\KenshiInst\5\imm26-backup-nc-*` (Stobe.mods.dll, Stobe.re.dll).

Procedure: `kenshi-ctl.ps1 stop` per lane (KAH_INSTANCE/KAH_OWNER env), copy, sha256 check, relaunch per runbook (DISPLAY2, low gfx, 1024x768 @30), saves i4 `kah-imm26-i4-trip2`, i5 `kah-imm26-i5-op3`, `stobe-auto wait-world`, speed set to 0.5, lane-window place.

| lane | DLL SHA on active path | commands | ctxpush | metadata keys (core_npc_master) | isolation |
|---|---|---|---|---|---|
| i4 | 4D18E32C... (mods\Stobe and RE_Kenshi\mods\Stobe) | `TEST_HARNESS: connected ... 11 commands (...bodyguard_probe/ctxpush)` | Cind [Hungry Bandit] (len 43076), Opajil, Liplom: `native_ai=1 referral_people=1 travel_destinations=1`, log `CONTEXT_PUSH: test_inbox reason=ctxpush` | Cind, Opajil, Liplom all have native_ai, referral_people, travel_destinations | lane-isolation 5090 SUMMARY PASS n_fail=0 |
| i5 | same | 11 commands | Cind (len 19528), Opajil, Liplom: same | same three NPCs, all three keys | PASS |

Server `/context` already stores the three keys in `core_npc_master.metadata` (no server patch needed).

Notes
- Target name must be the full in-game name: `stobe-auto stobe_ctxpush "Cind [Hungry Bandit]"` ("Cind" alone and `#serial` without `/idx` give `target not found`; Opajil/Liplom work by short name).
- Snags fixed: `tools/automation/lane-backend.sh` failed on the BOM in lanes-5090.json (now reads utf-8-sig). Monitor layout changed (DISPLAY2 is now primary at 0,0; DISPLAY1 1920x1080 at -1920,360), so registry slots in `C:\KenshiTestRuns\lanes\lanes-5090.json` were stale and all three windows sat at 0,0 (isolation `windows` FAIL): slots updated to i3 0,0 / i4 1300,0 DISPLAY2 / i5 -1500,400 DISPLAY1 (backup `lanes-5090.json.bak-imm26nc`), windows placed, isolation PASS.
- Both lanes are running, world loaded, speed 0.5, unpaused, markers/locks unchanged (`inflight\5090-imm26-i4|i5`, game-4/5.lock).
