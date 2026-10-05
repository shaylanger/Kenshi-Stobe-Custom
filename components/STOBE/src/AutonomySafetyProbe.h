#pragma once

#include <string>

class Character;
class GameWorld;

// Runs on the hooked PlayerInterface update thread after the world is stable.
void UpdateAutonomySafetyProbe(GameWorld *world, Character *selectedCharacter);

// Invalidates the runtime target binding without repeating a consumed command.
void ResetAutonomySafetyProbe(const char *reason);

// One-line JSON of the character's AI/order/movement state (test inbox).
std::string DescribeCharacterAiStateJson(Character *character);

// NPC info panel: short readable "what are they doing now" ("" if unreadable).
std::string DescribeCharacterLiveActivity(Character *character);

// mods\Stobe folder next to the executable (same as the config dir).
std::string GetTestInboxDir();

