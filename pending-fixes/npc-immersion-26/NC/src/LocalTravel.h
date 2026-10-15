#pragma once
#include <string>
class Character;
class GameWorld;
namespace Stobe { namespace LocalTravel {
std::string CandidatesJson(GameWorld *world, Character *actor, bool forceRefresh = false);
bool Validate(GameWorld *world, Character *actor, const std::string &id,
              float x, float y, float z, const std::string &label, std::string &reason);
bool ValidateForDispatch(GameWorld *world, Character *actor, const std::string &id,
                         float x, float y, float z, const std::string &label,
                         std::string &reason);
bool ValidateForDispatch(GameWorld *world, Character *actor, const std::string &id,
                        float x, float y, float z, const std::string &label,
                        const std::string &kind, std::string &reason);
void Reset();
} }
