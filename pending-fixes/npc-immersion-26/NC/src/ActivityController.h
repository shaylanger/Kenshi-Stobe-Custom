#pragma once
#include "ActivityGoals.h"
#include <string>
class GameWorld;
bool QueueActivityGrant(const Stobe::Activity::Agreement&, unsigned revision);
bool QueueActivityRevoke(const std::string& id,const std::string& worldId,unsigned revision);
std::string ActivityControllerWorldId();
Stobe::Activity::Clock ActivityControllerGameClock();
std::string ActivityControllerStatusJson();
// Separate bounded read-only view for the Harness. It never changes the legacy
// array consumed by ActivityTransport::PollWorker.
std::string ActivityControllerStatusSnapshotJson(const std::string& activityId);
std::string CaptureActivityChatFacts(unsigned actor,unsigned requester);
void UpdateActivityController(GameWorld*);
void ResetActivityController(const char* reason);
