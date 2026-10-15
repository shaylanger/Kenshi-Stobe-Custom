#pragma once
#include <string>
class Character;
class GameWorld;
namespace Stobe { namespace NpcReferralPeople {
// Game-thread context capture only. No AI, movement, inventory or relation writes.
std::string CaptureJson(GameWorld* world, Character* actor);
} }
