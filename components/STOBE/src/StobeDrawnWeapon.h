#pragma once
// Drawn-weapon reactions (Shay, 2026-10-06). A player character with a weapon in
// hand near an NPC that can see him (native SensoryData::canISeeThisGuy, plus an
// optional view cone) makes that NPC react, first- and third-person alike:
//   neutral-or-better: one Stobe line (why is the weapon out?); town guards tell
//   the player to put it away; below neutral: a warning line, then a native attack
//   if the weapon stays out in range for WarnSeconds or the player closes in to
//   AttackDistance. Holstering cancels a pending warning. Never the player's own
//   faction, never during combat. The state machine is StobeDrawnWeaponPolicy.h.
//
// Settings: Stobe.ini / StobeCustom.ini [DrawnWeapon] Enabled, Radius,
// WarnSeconds, AttackDistance, CooldownSeconds, RewarnSeconds, ViewConeDeg,
// HostileRelationBelow (read at game start, `stobe_drawn set` changes them live).
// Log lines: "DRAWN_WEAPON: ..." in stobe.log. Test command: stobe_drawn.

#include <string>
#include <vector>

class GameWorld;
class Character;

namespace Stobe {
namespace DrawnWeapon {

typedef std::string (*IniStringFn)(const char *section, const char *key, const char *def);

// From LoadStobeRuntimeConfig: read the [DrawnWeapon] settings (layered ini reader).
void LoadConfig(IniStringFn read);

// Main game thread, every frame (rate-limited inside).
void Update(GameWorld *world);

// Load / new game: forget all per-NPC state.
void Reset();

// Test command `stobe_drawn <status|draw|sheathe|hold|reset|set|pair>`; f = the
// harness fields (f[0] id, f[1] "drawn", f[2..] arguments).
std::string TestCommand(GameWorld *world, Character *sel,
                        const std::vector<std::string> &f, bool &ok,
                        Character *(*resolve)(GameWorld *, Character *, const std::string &));

} // namespace DrawnWeapon
} // namespace Stobe
