#pragma once
// N2: native attention / role / squad reads for one character (game thread only, no retained pointers).
#include <string>
class Character;
class GameWorld;
namespace Stobe { namespace NativeAttention {
// {"observed":true,busy,sleeping,injured,crippled,bleeding,exhausted,afraid,fleeing,hungry,in_combat,blood_pct,busy_reason}
// or {"observed":false} when the character cannot be read.
std::string AttentionJson(Character* npc);
// native_ai json (NativeAiAwareness::CaptureJson) with ,"attention":{...} appended when observed.
std::string WithAttention(const std::string& nativeAiJson, Character* npc);
// Public occupation of a bystander: trader|shopkeeper|guard|medic|slave|"" (<=24 chars).
std::string RoleFor(Character* npc);
// Squad name / id / current town name of a character ("" / 0 when unknown).
std::string SquadName(Character* npc);
unsigned SquadId(Character* npc);
std::string SettlementName(Character* npc);
// 0 none, 1 knocked_out, 2 bleeding_out, 3 downed (N2Policy::PartnerState); alive characters only.
int PartnerState(Character* npc);
// Alive, conscious, not downed (can walk away).
bool IsFree(Character* npc);
// Not in combat, not sleeping, not busy, not fleeing: fit for an optional chat turn.
bool IsIdle(Character* npc);
} }
