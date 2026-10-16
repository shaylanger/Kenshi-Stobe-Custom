# NC17 = NC16 (96C6FDDF...) + player-faction companion is a legal Hunt/activity partner (rows IMM-26-a, 22-a, 26-b, 26-c)

After NC16 the Activity record reached `accepted` but `NativeTravelLifecycle::Start` refused the actor with
`npc_has_existing_orders_or_unavailable` (old check: `actor->isPlayerCharacter() || faction->isThePlayer() || hasPlayerOrders || orders non-empty`).
A recruited/refactioned companion (Malzin, Cind[Nameless]) is in the player faction, so every Hunt with a squad partner died at Start.

Design: the decision is now a pure function `NativeTravelReceiptPolicy::ClassifyStartActor` (src/NativeTravelReceiptPolicy.h).
- A player-faction actor is allowed only when the requester/speaker resolves to a live player character AND is not the actor itself.
  (A player-faction actor with a non-player requester is refused: `player_faction_no_player_requester`.)
- Kept unchanged: dead/unconscious, existing orders list, player-given orders (`hasPlayerOrders`), missing orders receiver,
  non-squad actor that is a player character, plus every check in Prepare/ValidateForDispatch/VerifyGrant/executor.
- The refusal reason keeps its prefix and gets a cause suffix: `npc_has_existing_orders_or_unavailable:<down|actor_is_requester|player_character|player_faction_no_player_requester|no_orders_receiver|has_player_orders|has_orders>`
  (shows in ACTIVITY_END_DIAG). Nothing consumes the old exact string (checked native/tests/server).
- Only `Start` changed; it is called only from Activity (ActivityRuntimeBindings DispatchRoute, ActivityHandBack). The `isPlayerCharacter()` meaning for squad members could not be proven offline, so a player-faction actor flagged player-character is allowed with a player requester (otherwise the fix would be vacuous); remaining blocker would show as a `:has_player_orders` / `:has_orders` suffix.

Files: `nc17edit.py <NC16 tree>` (asserts anchors), `nc17-over-nc16.patch`, tests `components/STOBE/tests/cpp/native_travel_receipt_tests.cpp` (+14 NC17 checks, 51 PASS total) and `activity_player_faction_partner_source_tests.py` (fails on NC16 tree, passes on NC17), `offline-tests.sh` (WSL).
Build: `RESULT NC-BUILD PASS objects=69`, work tree `C:\KenshiTestRuns\imm26-nc17`, DLL `NC17\Stobe.dll` SHA256 `6DDCA6483530E0E6D054E7A589049E83EFDA2591AEDF366B56668B8D982EB39B` (gitignored). NOT installed on any lane.
Reproduce: copy `imm26-nc16\{src,legacy-v1,tests}` to a new tree, `python3 nc17edit.py <tree>`, build with `NC\build.ps1 -Out <tree>\build -SrcDir <tree>\src -LegacyDir <tree>\legacy-v1`.
