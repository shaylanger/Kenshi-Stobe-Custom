# KAH-INT-002 — 5090 second-pass panel selection refresh

**Result:** `RESULT KAH-INT-002 PASS rig=5090 loaded_stobe=AEF84C0A682DF036EB2CD0DC30A809E52E19956933F142C3A1D5877C4EB1907C targets=Kaela#2256103424/2(Shek),Meklin#1276001024/2(Dra'ak) A_to_B=gen91-to-gen96 B_to_A=gen96-to-gen98 coherent_text_portrait=1`

**Observed:** 2026-10-14 01:33 UTC, on host DESKTOP-JFLPK99, Kenshi PID 86884, main install instance 1, isolated copied save `kah-5090-legacy-auth-20261013-1740`.

## Preflight

- Live process module enumeration resolved `Stobe.dll` to `D:\Steam\steamapps\common\Kenshi\mods\Stobe\Stobe.dll`, SHA256 `AEF84C0A682DF036EB2CD0DC30A809E52E19956933F142C3A1D5877C4EB1907C`.
- Loaded `AutomationHarness.dll`: `D:\Steam\steamapps\common\Kenshi\mods\AutomationHarness\AutomationHarness.dll`, SHA256 `974DBA03F136D6CB08153F29ACC497C485C39BAECEB8BF50C8B5291661D3025D`.
- Source manifest SHA256 `AD63A137D74CFE23DEFF8914B06C56B8DC51693E88FBDA55AE1E365EE7B0445C`; payload manifest SHA256 `475B58A78C02377C3B67B1F7F6677F7E9AD912F018EC737CDE85807AB6D7FB0A`.
- KAH status: `phase=world`, `paused=0`, `speed=1.0`; input isolation ON, `focused=0`, DISPLAY2. Fresh `stobe_ping` reported speaker Kint. Stobe backend `127.0.0.1:8083` returned HTTP 200 with database and schema ready.
- Read-only SQL session receipt: `ready`, `current_campaign`, `new_game=false`, empty load character ID, canonical/session fingerprints matched (`4041de5d5c481056bf2a49ca33be441abca2eeeaa25b1acf46930ff23a089b64`). Raw identity and token were not emitted.
- A=Kaela [Hundred Guardian Olga], handle `2256103424/2`, Shek; read-only actor state reported alive and conscious, with Scrap Ringer Helm equipped. B=Meklin, handle `1276001024/2`, Dra'ak; read-only actor state reported alive and conscious. Both were distinct human targets already present in the world; no spawn or teleport.

## KAH A→B→A evidence

KAH transactions are the correlation IDs for this UI-only row; no native chat `TEST_INBOX` request is expected.

1. Open A: transaction `k1791941521625_73180_1_0` returned `open key=2256103424|Kint gen=90`.
2. Read A: transaction `k1791941537335_51472_1_0` returned `key=2256103424|Kint gen=91 loaded=1 portrait=1 tex=StobeProfilePortrait_77`, with Kaela's name, job, Shek faction, Shek-woman description, and matching bio/dealings text.
3. Screenshot A: transaction `k1791941537335_51472_1_1`, path `D:\Steam\steamapps\common\Kenshi\mods\AutomationHarness\shots\kah-int002-second-pass-A.png`, 1600×900, SHA256 `17F07AD1130FF0369DCC936C8E1FB83D20BA8FD7B89D7E9EB9AE13CAF92CD7BF`.
4. Select B: transaction `k1791941552505_109576_1_0` acknowledged `selected Meklin`.
5. Read B: transaction `k1791941577266_69368_1_0` returned `key=1276001024|Kint gen=96 loaded=1 portrait=1 tex=StobeProfilePortrait_78`, with Meklin's name, Shek Kingdom faction, Dra'ak-man description, and Meklin-specific bio/dealings text.
6. Screenshot B: transaction `k1791941582340_33800_1_0`, path `D:\Steam\steamapps\common\Kenshi\mods\AutomationHarness\shots\kah-int002-second-pass-B.png`, 1600×900, SHA256 `615C5127DE54516A2082594C2A38FFB3DA6AA55265268E2293D5FCE3E753F89B`.
7. Select A: transaction `k1791941587909_120712_1_0` acknowledged `selected Kaela [Hundred Guardian Olga]`.
8. Read A return: transaction `k1791941592897_101792_1_0` returned `key=2256103424|Kint gen=98 loaded=1 portrait=1 tex=StobeProfilePortrait_79`, restoring Kaela-specific text and portrait.
9. Screenshot A return: transaction `k1791941600410_27872_1_0`, path `D:\Steam\steamapps\common\Kenshi\mods\AutomationHarness\shots\kah-int002-second-pass-A-return.png`, 1600×900, SHA256 `6DCCCDC1D825261416BAD0D4F54D926EBD3AA8CE9EE80CB40BDA678F2B21D28F`.
10. Final isolation transaction `k1791941600410_27872_1_1` remained ON, `focused=0`, DISPLAY2.

All three screenshots were visually reviewed. The selected target's identifying text and portrait stayed coherent through both transitions. Kaela's profile image showed her face without the equipped Scrap Ringer Helm; Meklin's different portrait was recognizable and near-frontal. The B and return-to-A screenshots were dark because the in-game scene was at night, but target text and portrait remained readable enough to confirm the switch. No OS input, focus change, equipment change, save write, or native chat was used.

## Artifacts

- KAH outbox: `D:\Steam\steamapps\common\Kenshi\mods\AutomationHarness\outbox.txt`
- Harness screenshot log: `D:\Steam\steamapps\common\Kenshi\mods\AutomationHarness\harness.log`
- Native log: `D:\Steam\steamapps\common\Kenshi\RE_Kenshi\mods\Stobe\stobe.log`
- Screenshots: `D:\Steam\steamapps\common\Kenshi\mods\AutomationHarness\shots\kah-int002-second-pass-A.png`, `...\kah-int002-second-pass-B.png`, `...\kah-int002-second-pass-A-return.png`.
