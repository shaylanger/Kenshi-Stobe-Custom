# FP combat handoff 21 — full resume context
Status: MERGED (938d2e2) — fp-combat is merged into main; one session works on it directly (edits /root/KenshiFP + components/KenshiFP, builds, installs, runs the game, commits + pushes). The ownership, request/candidate and "push blocked" rules below are pre-merge history and are superseded. Current state: see "Status after merge" right below and `C:\KenshiModding\FP_COMBAT_COORDINATION_CONTEXT.md`.

## Status (2026-10-06)
- Installed KenshiFP 4FD22DEF on both rigs (main ac56752: manual melee adapter, spatial wounds, wound pick diagnostics),
  harness 2995EE5E; manual combat OFF by default.
- Open rows and current state: COMBAT_TEST_PLAN.md ("Current state"); context FP_COMBAT_COORDINATION_CONTEXT.md.
- The pre-merge development log (candidates, requests, validation-resume runs, ownership rules) was removed 2026-10-06:
  the work is merged and its rows passed; read it with `git log -p` on this file if needed.

## Accepted design
1. Persistent FP-style WASD controls while wheel zooms continuously between eyes and third person; wheel no longer throttles run speed. Retain old toggle as native-control fallback.
2. Inspect/select another squad member's stats/inventory without transferring camera/movement; explicit control transfer.
3. RMB hold raises/ADS crossbow; LMB one legal shot; R or automatic native-duration visible reload. Preserve native skills/spread, ammo, damage/armour/XP. Actual first collision victim is injured, including an intervening NPC; spatial body part rather than weighted random reroll. Invisible skill-dependent spread calibrated against matched native torso accuracy/fire rate. High-skill limb aim is tactical, not automatic disarm/cripple.
4. Ready melee click initiates a native swing promptly, not a queue waiting for AI initiative. Native animation/state commitment and recovery gate actions. Spam cannot reset/accelerate. RMB legal responsive defence, WASD yields committed root motion. Optional <=0.20s buffer only in the tail of one's own recovery.
5. Automated mechanical and statistical tests using existing harness; keep visual/feel checks separate. Never call mocks native validation or promise a bug-free system.

## Native analysis and exact findings
Read-only binary D:\Steam\steamapps\common\Kenshi\kenshi_x64.exe (36718592 bytes); x86_64-w64-mingw32-objdump available in WSL. capstone/pefile not installed; stdlib PE parsing used.
Analysis scripts and bounded assembly files in staging/native; staging scripts are NOT project artifacts or runtime commands.
Verified unique current exe signatures: native RC updateT=0x438c70, updateMT=0x43aee0, end=0x437470; gun shoot=0x43a730, animationUpdate=0x51e4e0, getGun=0x4345c0, GunClass reloadAmmo=0x436fb0.
GunClass::reloadAmmo immediately copies max loaded count into current ammo and updates meshes. It alone has no timer/inventory debit. Never enable old prototype instant reload.
Native RC reloadCheck at 0x437ce0: derives skill reload time, _isReloading +0x80, max/timer +0x74/+0x78, decrement by engine game-time global; updates reload pose/UI, debits correct inventory ammunition at completion, refill helper and native stat/DEX XP. This is correct adapter path to investigate.
Ranged animationUpdate clears gun readiness, drives reload/aim animation; null target lowers arms, non-null tested for presence, not dereferenced in this function. Existing prototype passed player as sentinel. readiness depends on real anim progress.
Gun shoot applies native skill+Perception spread once via Ogre randomDeviant and records actual projectile. NULL target skips target-height adjustment and intended target notification. Do not assume it proves parity.
Medical iShotYou at 0x439c90 passes CUT_PIERCED to MedicalSystem::addWound and retains native damage/hostility. Native addWound target=0x6508d0 (resolved internal JMP thunk 0x1dddb), weighted body-part selection inside function. Changing aim alone does NOT select spatial limb.
Gun spawn helper internal JMP thunk 0x39676 resolves 0x43a2f0; returns Harpoon*, potential narrowly scoped projectile tracking hook. Harpoon mesh node +0x58; tracer +0x68; native damage +0x4c; fields require further proof before use. No Harpoon definition found in SDK.
physHit definition IS in KenshiLib-src/Include/kenshi/CharMovement.h: size0x60, hit byte+7, position+8, normal+0x14, distance+0x20, shape+0x28, hand+0x30, group+0x50, unsafePtr+0x58; exported constructor/hitObjectUnsafePtr/Utility trace functions available.
KenshiLib.dll root game folder exports native RC lifecycle, getCombatClass, CombatClass changeState/setCombatState/initialiseBlock/setAttackTarget, AttackState initialiseAttack, physHit/trace and iShotYou. Enumerated exports via staging/export_contracts.py. Bindings are version-aware; game interception still unique-scan native target.
SDK located /root/KenshiLib-src/Include/kenshi. Address deltas vary; speculative SDK+offset dumps can land in other functions. Never use those guesses live. Use verified signatures, native thunk targets/callgraph/RTTI.
Last analysis staging/rtti_map.py parsed MSVC RTTI, found CombatClassAI vtable 0x16f67b8 and base0x16f6698. Entries point to JMP thunks, NOT function bodies. Next unwrap their E9 branches and disassemble real bodies:
AI slots 0x28->0xd4a9, 0x40->0xcc34, 0x48->0x2d44d, 0x50->0x2ee0b, 0x58->0x15875, 0x60->0x25ac7.
Base slots 0x28->0x109c9, 0x40->0xcc34, 0x48->0x45732, 0x50->0x2ca02, 0x58->0xd7a6, 0x60->0x16ee1.
AttackState vtable0x16b3bb8: validate thunk0x39202, initialise0xddf5, update0x29393, end0x479bf.
Combat SDK fields: active+0x130, isAttacking+0x140, inDeadTime+0x144, deadTimer+0x148, stateTimer+0x14c, technique+0x150, techniqueFinished+0x158, movement+0x170, me+0x188, combatState+0x1f0, nextMove+0x1f4, target+0x290/hand+0x298. Enum CHOP0/BLOCK1/REACTION_BLOCK2/STARTUP3/DECISION4/CIRCLE5/WAIT6/HESITATE7/STUMBLE8/FINISHED9/PATHSTART10/PATH11. Validate these native observations.

