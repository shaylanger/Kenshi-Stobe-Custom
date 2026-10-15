#pragma once
#include <string>
#include <vector>
class GameWorld;
namespace Stobe { namespace Activity {
// Read-only observation of danger around a running activity (game thread only).
// Feeds Events::Tracker: who is hurt, and which hostile is attacking the actor or requester.
struct DangerFacts {
 bool actorHealthValid; int actorPercent;
 bool requesterHealthValid; int requesterPercent;
 bool threatObserved; unsigned threatSerial; std::string threatName; int threatDistance;
 DangerFacts();
};
// quarry = agreed targets (fighting them is the activity, not a threat). Returns false if the actor cannot be read.
bool ObserveDanger(GameWorld* world, unsigned actor, unsigned requester, const std::vector<unsigned>& quarry,
                   unsigned currentTarget, DangerFacts& out);
} }
