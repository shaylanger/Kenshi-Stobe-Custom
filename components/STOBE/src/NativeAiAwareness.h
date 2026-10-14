#pragma once
#include <string>
class Character;
class GameWorld;
namespace Stobe { namespace NativeAiAwareness {
// Call only while collecting context on the game thread. No retained pointers,
// state mutations, background work, or inferred action ownership.
std::string CaptureJson(GameWorld* world, Character* actor);
} }
