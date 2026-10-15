#pragma once
#include "ActivityGoals.h"
#include "AutonomyMonitor.h"
#include <map>
#include <kenshi/util/hand.h>
class GameWorld;
class Character;
class Building;
class Inventory;
class Item;
namespace Stobe { namespace Activity {
struct NativeDestination { Target facts; double x, y, z; NativeDestination(); };
// Required trusted policy: checks current agreement authority, source identity,
// actor-specific ownership/crime/protection/ceasefire and fresh target facts.
// Called on the game thread immediately before dispatch and during polling.
class NativePolicy {
public:
 virtual ~NativePolicy() {}
 virtual bool Revalidate(const Agreement&, const Request&, Target&, std::string&) = 0;
 virtual bool CampScopeCurrentForCleanup(const Agreement&, unsigned int target, std::string&) = 0;
 virtual Building* ResolveResource(const Agreement&, unsigned int serial) = 0;
 // Only an explicitly permitted production-output inventory, never inputs or
 // arbitrary building storage. Must verify actor is the exclusive producer;
 // shared production cannot be credited to this goal. Returning null fails closed.
 virtual Inventory* ResourceOutput(const Agreement&, Building*) = 0;
};
class NativeExecutor {
public:
 explicit NativeExecutor(NativePolicy&);
 void Bind(GameWorld*, const std::string& worldId, Clock now);
 bool Observe(const Agreement&, Target&, Facts&);
 bool Dispatch(const Agreement&, const Request&, const NativeDestination&, std::string&);
 Receipt Poll(const std::string& requestId);
 bool SnapshotNative(const std::string& requestId, GoalStatusSnapshot& out);
 bool CancelOwned(const std::string& requestId);
 unsigned int Delivered(const std::string& agreementId) const;
private:
 struct Operation {
   Agreement agreement; Request request; NativeDestination destination;
   Autonomy::OrderFingerprint owned; Receipt receipt;
   bool cleanupRequired, mineLease, orderCaptured, orderRemoved; int orderStartTime;
   hand actorIdentity, subjectIdentity, targetIdentity;
   unsigned int outputBaseline;
   bool transferRecovery; Item* detached; Inventory* transferSource;
   unsigned int transferAmount, sourceBefore, recipientBefore;
   Operation();
 };
 NativePolicy& policy_; GameWorld* world_; std::string worldId_; Clock now_;
 std::map<std::string, Operation> operations_;
 std::map<std::string, unsigned int> delivered_;
 bool Transfer(Operation&, Inventory*, std::string&);
 bool RecoverTransfer(Operation&);
 bool CaptureOwned(Character*, Operation&, bool initial);
 bool NativeEnded(Character*, const Operation&);
};
} }

