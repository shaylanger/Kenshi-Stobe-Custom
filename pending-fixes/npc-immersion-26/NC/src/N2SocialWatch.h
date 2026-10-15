#pragma once
// N2: proximity follow-up trigger. Fires the optional bored turn (server decides; it answers "ok" and does
// nothing when nothing is claimable) when
//   (a) the selected player character comes within talking range of an idle squad companion after being
//       away (> 30 m for >= 45 s), or on the first stable scan after a load (once, 8 s delay);
//   (b) 1-3 s after a combat_start within 60 m of the selected player character: nearest able companion
//       within 40 m (the attention block carries in_combat so the server can allow a threat remark).
// Pure rules (rate limits 90 s global / 10 min per NPC, away/return, load once) live in N2Policy.h.
// Log lines: "N2_PROXIMITY: ..." in stobe.log.
class GameWorld;
class Character;
namespace Stobe { namespace N2SocialWatch {
// Main game thread, every frame (rate-limited to one scan per 2 s inside).
void Update(GameWorld* world, Character* selected);
// Load / new game / import: forget all state.
void Reset();
// Any thread: a combat_start event was logged (actor and target handle serials, 0 = unknown).
void NoteCombatStart(unsigned actorSerial, unsigned targetSerial);
} }
