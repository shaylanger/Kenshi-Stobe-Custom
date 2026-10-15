#pragma once
#include "ActivityGoals.h"
#include <map>
#include <string>
class GameWorld;
namespace Stobe { namespace Activity {
// Game-thread host for HandBack::Machine (ActivityHandBackPolicy.h). One entry per agreement.
// Only acts when the server set the `handback` envelope flag (Agreement::handBack).
struct HandBackView {
 bool holds;        // keep the published phase at "handing_back"
 bool returning;    // walking toward the requester
 bool finished;
 std::string status; // delivered | kept_by_npc | not_applicable | pending
 std::string reason;
 unsigned amount;
 HandBackView() : holds(false), returning(false), finished(false), status("pending"), amount(0) {}
};
class HandBackHost {
public:
 HandBackHost();
 ~HandBackHost();
 void Bind(GameWorld* world, const std::string& worldId, Clock gameNow);
 void Step(const Agreement& a, bool goalComplete, bool goalEnded, bool cleanupComplete, unsigned delivered, HandBackView& view);
 void Forget(const std::string& agreementId);
 void Clear();
private:
 HandBackHost(const HandBackHost&); HandBackHost& operator=(const HandBackHost&);
 struct Entry;
 GameWorld* world_; std::string worldId_; Clock now_;
 std::map<std::string, Entry*> entries_;
};
} }
