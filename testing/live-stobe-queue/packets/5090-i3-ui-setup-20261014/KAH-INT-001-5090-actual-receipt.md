# KAH-INT-001 actual isolated 5090 run — 2026-10-14

Owner `/root/5090_runner_guard_recovery`, instance 3, lock `5090c-ui-setup-20261014`; PID 26972 exact executable `D:\KenshiInst\3\RE_Kenshi\kenshi_x64.exe`. Main PID 86884 untouched.

## Setup proof

- Stage FD5BDCC96B33C69708706605FCB76E9547329D915ED34B68DE464C0D63A6FC13 succeeded with private copied save `kah-5090c-ui-20261014`; rollback is `D:\KenshiInst\3\stobe-ui-rollback-20261014`.
- Original invalid monitor regex repaired; final ctl FDE7F4A10A46BCDB27A7482F6F495030EB99B37D1C3EF93835466942C573A665 independently CLEAR and MONSEL PASS24. Actual attached hardware DISPLAY1 is Samsung SAM0B49, so exact DISPLAY2 ASUS AUS32B1 selected. Background launch returned exit 0, autoaccepted mod-order warning at 10:25:56, native frame listener running and fixture autoload initiated. No focus was taken; foreground remained ChatGPT.
- Loaded module probe ties Stobe path `D:\KenshiInst\3\mods\Stobe\Stobe.dll` to PID26972 with on-disk SHA AEF84C0A682DF036EB2CD0DC30A809E52E19956933F142C3A1D5877C4EB1907C; Harness path `D:\KenshiInst\3\mods\AutomationHarness\AutomationHarness.dll` SHA974DBA03F136D6CB08153F29ACC497C485C39BAECEB8BF50C8B5291661D3025D.
- Source manifest AD63A137D74CFE23DEFF8914B06C56B8DC51693E88FBDA55AE1E365EE7B0445C and payload manifest475B58A78C02377C3B67B1F7F6677F7E9AD912F018EC737CDE85807AB6D7FB0A were stage gates. Effective config had slash and loopback18086 with no listener during UIrow.
- Original WSL wrapper failed `-d: command not found`; exact independently reviewed v2 transport FB3DF600F01CFF63D0B44E678AF5104F7FAE231F727FF9DD4E22516D9B7FC8AE executed world-ui AF111BAD6C6F391C73B4120431A1E4694FB639BE5671248CAC1799753A17BD05 successfully.
- Native status: `phase=world save=kah-5090c-ui-20261014 last_saved=kah-fp-m08 paused=0 speed=1.0 squad=1 player=Shay`; time `game_hours=34.3036 day=1 time=10:18 speed=1.0 paused=0`.
- Isolation ON, focused0, heldnone, iconic0; frames2458→2473→4843→5794, actual monitorDISPLAY2.

## Actual row evidence

Closed baseline: `ERROR: no visible widget named or captioned 'Stobe_ChatWindow'` (expected).
First slash action: `key 0xBF dik=0x35 tap 120ms keyboards=1`.
After transition and later independent observation: same missing chat widget. Isolation reports injected_keys2, heldnone, focused0. Screenshot `D:\KenshiInst\3\mods\AutomationHarness\shots\kah-int-001-5090-i3-20261014-01-open.png` (1280x720) inspected: live world, no Stobe chat. No textbox/draft/second-close action was attempted. No chat message was sent.

The visible first-open assertion failed. Cause is unproven: product shortcut polling vs injected-input interoperability needs diagnostic ownership; no PASS and no claim that physical focused shortcut is broken. No backend session was needed for this UI case.

RESULT KAH-INT-001 FAIL evidence: first injected slash ACK produced no visible Stobe_ChatWindow; rig=5090 instance=3 pid=26972 isolation=on focused=0 injected_keys=2 screenshot=kah-int-001-5090-i3-20261014-01-open.png remaining_assertions=unrun

Backend owner notified of terminal UI boundary and permission to start already reviewed privateHTTP18086; game remains alive for next P0 case. Next: diagnose first-key interoperability separately while P0 proceeds.
