#pragma once

#include <string>
class Character;
class GameWorld;

namespace Stobe { namespace BodyguardContractProbe {
// Opt-in, read-only diagnostic. Start with a pinned copied-save identity via
// `stobe_bodyguard_probe start:<quick.save-sha256>:<copy-id>`; call Observe
// from the game thread. Every emitted record is bound to that identity.
std::string Command(const std::string& action);
void Observe(GameWorld* world, Character* anchor);
void RecordDialogueChoice(void* dialogue, const std::string& reply,
                          const char* sourceTag);
void Reset();
} }
