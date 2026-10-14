#include "NativeTravelLifecycle.h"
#include "Globals.h"
#include "AutonomyExecutor.h"
#include "KenshiAiCompat.h"
#include "LocalTravel.h"
#include "NativeTravelReceiptPolicy.h"
#include "PlaythroughSession.h"
#include "Utils.h"
#include <kenshi/AI/AITaskSystem.h>
#include <kenshi/Character.h>
#include <kenshi/Faction.h>
#include <kenshi/CharMovement.h>
#include <kenshi/CharBody.h>
#include <kenshi/Tasker.h>
#include <objbase.h>
#include <map>
#include <float.h>
#include <sstream>
#include <vector>
#include <cmath>
#include <cstdlib>
#include <cerrno>
#include <ctime>

namespace Stobe { namespace NativeTravelLifecycle {
namespace {
struct Controller { unsigned long long revision; bool present; Controller():revision(0),present(false) {} };
struct Receipt {
  unsigned int actor, speaker;
  bool follow, terminal, arrived, released;
  bool direct, fullyReleased;
  bool notStarted;
  bool dispatchAccepted;
  bool endPending, pendingArrived;
  std::string pendingPhase, pendingReason;
  long long expires;
  int startTime;
  DWORD issuedTick;
  int pathFailureSamples;
  hand actorHandle, subject;
  Stobe::Autonomy::OrderFingerprint order;
  unsigned long long revision, evidence;
  unsigned long sessionGeneration;
  std::string agreement, request, world, task, phase, reason;
  std::string dispatchEnvelope;
  Receipt():actor(0),speaker(0),follow(false),terminal(false),arrived(false),released(false),
    direct(false),fullyReleased(false),notStarted(false),dispatchAccepted(false),endPending(false),pendingArrived(false),
    expires(0),startTime(0),issuedTick(0),pathFailureSamples(0),revision(0),evidence(0),sessionGeneration(0) {}
};
struct Mutex { CRITICAL_SECTION cs; Mutex(){InitializeCriticalSection(&cs);} ~Mutex(){DeleteCriticalSection(&cs);} } mutex;
struct Lock { Mutex &m; Lock(Mutex &value):m(value){EnterCriticalSection(&m.cs);} ~Lock(){LeaveCriticalSection(&m.cs);} };
template<typename T> std::string Number(T value) { std::ostringstream out; out << value; return out.str(); }
std::map<unsigned int, Controller> follows, routes;
std::map<unsigned int, std::vector<Receipt> > receipts;
std::map<std::string, Receipt> issuedRequests;
struct Absence { bool verified; long long gamets, unixTime; std::string evidence; Absence():verified(false),gamets(0),unixTime(0) {} };
std::map<unsigned int, Absence> absence;
std::string worldId;
unsigned long long sequence = 0;
DWORD lastTick = 0;
long long observedGameTs = 0, observedUnix = 0;
bool GameThread() { return g_mainThreadId != 0 && GetCurrentThreadId() == g_mainThreadId; }
std::string Quote(const std::string &s) {
  std::ostringstream out; out << '"';
  for (size_t i=0;i<s.size();++i) { unsigned char c=static_cast<unsigned char>(s[i]);
    if (c == '"' || c == '\\') out << '\\' << char(c);
    else if (c >= 32 && c < 127) out << char(c);
    else { const char *hex = "0123456789abcdef"; out << "\\u00" << hex[c >> 4] << hex[c & 15]; }
  }
  out << '"'; return out.str();
}
bool Token(const std::string &s, size_t max) {
  if (s.empty() || s.size() > max) return false;
  for (size_t i=0;i<s.size();++i) { char c=s[i]; if (!((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') ||
      (c >= '0' && c <= '9') || c == '-' || c == '_' || c == ':')) return false; }
  return true;
}
void Emit(Receipt &r, const std::string &phase, const std::string &reason,
          bool terminal, bool released = false, bool arrived = false) {
  r.phase = phase; r.reason = reason; r.terminal = terminal;
  r.released = released; r.arrived = arrived; r.evidence = ++sequence;
}
Receipt *Active(unsigned int actor) {
  auto i = receipts.find(actor);
  if (i == receipts.end() || i->second.empty() || i->second.back().terminal) return nullptr;
  return &i->second.back();
}
Receipt *Latest(unsigned int actor) {
  auto i = receipts.find(actor);
  return i == receipts.end() || i->second.empty() ? nullptr : &i->second.back();
}
Stobe::NativeTravelReceiptPolicy::Scope ReceiptScope(const Receipt &r) {
  Stobe::NativeTravelReceiptPolicy::Scope scope;
  scope.actor = r.actor; scope.speaker = r.speaker; scope.agreement = r.agreement;
  scope.request = r.request; scope.world = r.world; scope.task = r.task;
  scope.sessionGeneration = r.sessionGeneration;
  return scope;
}
bool SameHand(const hand &a, const hand &b) {
  return a.serial == b.serial && a.index == b.index && a.type == b.type &&
         a.container == b.container && a.containerSerial == b.containerSerial;
}
bool CaptureOrder(Character *actor, Receipt &r, bool initial, std::string &reason) {
  if (!actor || !SameHand(actor->getHandle(), r.actorHandle)) { reason = "actor_identity_changed"; return false; }
  OrdersReceiver *orders = actor->getOrdersReciever();
  if (!orders || orders->orders.list.size() != 1) { reason = "owned_order_missing_or_other_orders_present"; return false; }
  Tasker *first = orders->orders.list.front();
  if (!first || !first->taskData || int(first->taskData->key) != r.order.taskType ||
      !SameHand(first->subject, r.subject)) { reason = "native_order_identity_changed"; return false; }
  const Ogre::Vector3 location = first->getLocation();
  if (!r.follow && (std::fabs(location.x - r.order.x) > 0.5 ||
      std::fabs(location.y - r.order.y) > 0.5 || std::fabs(location.z - r.order.z) > 0.5)) {
    reason = "native_order_destination_changed"; return false;
  }
  const unsigned long long pointer = reinterpret_cast<unsigned long long>(first);
  if (!initial && (pointer != r.order.runtimePointer || first->startTime != r.startTime)) {
    reason = "native_order_replaced"; return false;
  }
  r.order.runtimePointer = pointer; r.order.orderCount = 1; r.startTime = first->startTime;
  return true;
}
bool NativeEnded(Character *actor, const Receipt &r) {
  if (!actor || !SameHand(actor->getHandle(),r.actorHandle)) return false;
  OrdersReceiver *orders = actor->getOrdersReciever();
  if (!orders || !orders->orders.list.empty()) return false;
  const TaskMatch &goal = orders->getCurrentGoal();
  if (goal.taskData && int(goal.key()) == r.order.taskType && SameHand(goal.subject,r.subject)) return false;
  CharBody *body = actor->getBody();
  if (!body) return false;
  Tasker *action = body->currentAction;
  if (action && action->taskData && int(action->taskData->key) == r.order.taskType &&
      SameHand(action->subject,r.subject)) return false;
  CharMovement *movement = actor->getMovement();
  if (!movement) return false;
  // GOAP can leave a movement subtask after its parent order disappears.
  // Until movement settles we cannot prove that work actually stopped.
  return !movement->isCurrentlyMoving();
}
bool CancelDirect(GameWorld *world, Receipt &r, std::string &reason) {
  Character *actor = Stobe::KenshiAi::ResolveCharacter(world, r.actor);
  // Validate actual task data ourselves; the shared helper checks pointer/count.
  if (!CaptureOrder(actor, r, false, reason)) return false;
  if (!Stobe::Autonomy::TryCancelOwnedOrder(world, r.actor, r.order, reason)) return false;
  r.endPending = true;
  const bool absentNow = NativeEnded(actor,r);
  r.fullyReleased = Stobe::NativeTravelReceiptPolicy::MatchesRelease(
    ReceiptScope(r), r.actor, r.speaker, r.agreement, worldId,
    PlaythroughSession::Generation(), r.task, absentNow);
  if (!r.fullyReleased) reason = "owned_order_removed_native_end_pending";
  return r.fullyReleased;
}
}
void Reset() {
  if (!GameThread()) return;
  Lock lock(mutex);
  follows.clear(); routes.clear(); receipts.clear(); issuedRequests.clear(); absence.clear(); sequence = 0; lastTick = 0;
  observedGameTs = 0; observedUnix = 0;
  GUID id;
  worldId.clear();
  if (SUCCEEDED(CoCreateGuid(&id))) {
    std::ostringstream out; out << "travel-" << std::hex;
    const unsigned char *bytes = reinterpret_cast<const unsigned char *>(&id);
    const char *hex = "0123456789abcdef";
    for (size_t i = 0; i < sizeof(id); ++i) out << hex[bytes[i] >> 4] << hex[bytes[i] & 15];
    worldId = out.str();
  } // UUID failure deliberately disables binding; no reusable fallback world.
}
std::string WorldId() {
  Lock lock(mutex); return worldId;
}
void ControllerChanged(unsigned int actor, bool follow, bool present) {
  if (!actor) return; // Metadata only: chat interrupts can clear controllers off-thread.
  Lock lock(mutex);
  Controller &c = (follow ? follows : routes)[actor];
  if (present) absence[actor].verified = false;
  // Every assignment changes ownership even if the destination is identical.
  // Removing an already absent controller does not invalidate the other kind.
  if (!present && !c.present) return;
  Receipt *r = Active(actor);
  if (r && !r->direct && r->follow == follow && r->revision == c.revision)
    Emit(*r, "failed", present ? "controller_replaced" : "controller_removed_without_end_evidence", true);
  ++c.revision; c.present = present;
}
int Prepare(unsigned int actor, unsigned int speaker, bool follow,
            const std::string &agreement, const std::string &request,
            const std::string &expectedWorld, unsigned long long &previousRevision) {
  previousRevision = 0;
  if (!GameThread() || !actor || !speaker || !Token(agreement, 96) || !Token(request, 96)) return -1;
  Lock lock(mutex);
  if (worldId.empty() || expectedWorld != worldId) return -1;
  auto found = issuedRequests.find(Stobe::NativeTravelReceiptPolicy::RequestKey(agreement, request));
  if (found != issuedRequests.end()) {
    const Receipt &r = found->second;
    return r.actor == actor && r.agreement == agreement && r.speaker == speaker && r.follow == follow ? 0 : -1;
  }
  // Reject overflow instead of forgetting deduplication and replaying old work.
  if (issuedRequests.size() >= 4096) return -1;
  Receipt *latest = Latest(actor);
  if (Active(actor) || (latest && latest->direct && !latest->fullyReleased)) return -1;
  previousRevision = (follow ? follows : routes)[actor].revision;
  return 1;
}
bool Bind(unsigned int actor, unsigned int speaker, bool follow,
          const std::string &agreement, const std::string &request,
          const std::string &expectedWorld, unsigned long long previousRevision) {
  if (!GameThread() || !actor || !speaker || !Token(agreement, 96) || !Token(request, 96)) return false;
  Lock lock(mutex);
  if (worldId.empty() || expectedWorld != worldId) return false;
  Controller &c = (follow ? follows : routes)[actor];
  if (!c.present || c.revision != previousRevision + 1) return false;
  Receipt *old = Active(actor);
  if (old) {
    // Retries cannot steal an existing controller or rebind a task to new terms.
    return old->agreement == agreement && old->request == request && old->speaker == speaker &&
           old->follow == follow && old->revision == c.revision;
  }
  Receipt r; r.actor = actor; r.speaker = speaker; r.follow = follow;
  r.agreement = agreement; r.request = request; r.world = worldId; r.revision = c.revision;
  std::ostringstream task; task << (follow ? "follow:" : "route:") << actor << ':' << c.revision;
  r.task = task.str(); Emit(r, "running", "native_controller_assigned", false);
  std::vector<Receipt> &history = receipts[actor];
  // Keep a bounded receipt history so a replacement does not erase the previous
  // terminal acknowledgment before the next ordinary context push.
  if (history.size() >= 32) history.erase(history.begin());
  r.sessionGeneration = PlaythroughSession::Generation();
  r.dispatchAccepted = true;
  history.push_back(r);
  issuedRequests[Stobe::NativeTravelReceiptPolicy::RequestKey(agreement, request)] = r;
  return true;
}
bool Release(unsigned int actor, unsigned int speaker, const std::string &agreement,
             const std::string &world, const std::string &task) {
  if (!GameThread()) return false;
  struct StateLock {
    StateLock() { EnterCriticalSection(&g_stateMutex); }
    ~StateLock() { LeaveCriticalSection(&g_stateMutex); }
  } stateLock;
  // Global-state lock precedes the module lock, matching Globals mutators.
  bool follow = false;
  {
    Lock lock(mutex);
    Receipt *r = Active(actor);
    if (!r || r->direct || world.empty() || world != worldId || r->world != world || r->task != task ||
        r->agreement != agreement || r->speaker != speaker) return false;
    Controller &c = (r->follow ? follows : routes)[actor];
    if (!c.present || c.revision != r->revision) return false;
    follow = r->follow;
    Emit(*r, "failed", "owned_controller_released_native_ai_end_unverified", true, true);
  }
  if (follow) ClearFollowTarget(actor); else ClearTravelTarget(actor);
  return true; // Controller relinquished; NOT proof the native AI task stopped.
}
void RouteReached(unsigned int actor, float x, float y, float z) {
  if (!GameThread()) return;
  const auto targets = SnapshotTravelTargets();
  const auto target = targets.find(actor);
  if (target == targets.end()) return;
  if (!Stobe::NativeTravelReceiptPolicy::AtAgreedEndpoint(
        x, y, z, target->second.x, target->second.y, target->second.z)) return;
  Lock lock(mutex);
  Receipt *r = Active(actor);
  if (!r || r->follow || !routes[actor].present || r->revision != routes[actor].revision) return;
  Emit(*r, "completed", "measured_within_route_arrival_radius", true, false, true);
}
void Failed(unsigned int actor, bool follow, const std::string &reason) {
  if (!GameThread()) return;
  Lock lock(mutex);
  Receipt *r = Active(actor);
  if (r && r->follow == follow) Emit(*r, "failed", reason.substr(0, 160), true);
}
std::string SnapshotJson(unsigned int actor) {
  Lock lock(mutex);
  std::ostringstream out; out << "{\"world_id\":" << Quote(worldId)
    << ",\"session_generation\":" << PlaythroughSession::Generation()
    << ",\"actor_serial\":" << actor << ",\"observed_gamets\":" << observedGameTs
    << ",\"observed_unix\":" << observedUnix;
  auto idle = absence.find(actor);
  if (idle != absence.end()) {
    out << ",\"scoped_travel_absent_verified\":" << (idle->second.verified ? "true" : "false")
        << ",\"absence_evidence_id\":" << Quote(idle->second.evidence)
        << ",\"absence_observed_gamets\":" << idle->second.gamets
        << ",\"absence_observed_unix\":" << idle->second.unixTime;
  } else out << ",\"scoped_travel_absent_verified\":false";
  out << ",\"receipts\":[";
  bool comma = false;
  auto it = receipts.find(actor);
  if (it != receipts.end()) for (size_t index=0;index<it->second.size();++index) {
    const Receipt &r = it->second[index];
    if (r.phase == "dispatching") continue; // Reservation is not execution evidence.
    if (comma) out << ','; comma = true;
    out << "{\"agreement_id\":" << Quote(r.agreement) << ",\"request_id\":" << Quote(r.request)
        << ",\"world_id\":" << Quote(r.world) << ",\"task_id\":" << Quote(r.task)
        << ",\"actor_serial\":" << r.actor << ",\"speaker_serial\":" << r.speaker
        << ",\"session_generation\":" << r.sessionGeneration
        << ",\"dispatch_outcome\":" << Quote(r.notStarted ? "not_started_verified" :
             (r.dispatchAccepted ? "accepted" : "uncertain"))
        << ",\"phase\":" << Quote(r.phase) << ",\"reason\":" << Quote(r.reason)
        << ",\"evidence_id\":" << Quote(r.world + ":" + Number(r.evidence))
        << ",\"ownership_scope\":" << Quote(r.direct ? "native_order" : "stobe_travel_controller")
        << ",\"controller_released\":" << (r.released ? "true" : "false")
        << ",\"owned_work_released\":" << (r.fullyReleased ? "true" : "false")
        << ",\"not_started_verified\":" << (r.notStarted ? "true" : "false")
        << ",\"end_condition_verified\":" << (r.arrived ? "true" : "false") << '}';
  }
  out << "]}"; return out.str();
}
bool Start(GameWorld *world, Character *actor, unsigned int speaker, Character *target,
           float x, float y, float z, const std::string &agreement,
           const std::string &request, const std::string &expectedWorld,
           const std::string &dispatchEnvelope, long long expiresGameTs,
           long long nowGameTs, std::string &reason) {
  if (!GameThread() || !world || !actor || !speaker || !_finite(x) || !_finite(y) || !_finite(z)) {
    reason = "invalid_travel_request"; return false;
  }
  if (expiresGameTs <= nowGameTs || expiresGameTs - nowGameTs > 86400) { reason = "invalid_travel_deadline"; return false; }
  const unsigned int serial = actor->getHandle().serial;
  const std::string requestKey = Stobe::NativeTravelReceiptPolicy::RequestKey(agreement, request);
  {
    Lock lock(mutex);
    const auto existing = issuedRequests.find(requestKey);
    const Stobe::NativeTravelReceiptPolicy::DuplicateResult duplicate =
      Stobe::NativeTravelReceiptPolicy::ClassifyDuplicate(existing != issuedRequests.end(),
        existing == issuedRequests.end() ? std::string() : existing->second.dispatchEnvelope,
        dispatchEnvelope, existing != issuedRequests.end() && existing->second.dispatchAccepted,
        existing != issuedRequests.end() && existing->second.notStarted);
    if (duplicate == Stobe::NativeTravelReceiptPolicy::DUPLICATE_EXACT_ACCEPTED) {
      reason = "request_already_issued"; return true;
    }
    if (duplicate == Stobe::NativeTravelReceiptPolicy::DUPLICATE_EXACT_UNCERTAIN) {
      reason = "request_outcome_uncertain_no_retry"; return false;
    }
    if (duplicate == Stobe::NativeTravelReceiptPolicy::DUPLICATE_EXACT_NOT_STARTED) {
      reason = "request_already_rejected_not_started"; return false;
    }
    if (duplicate == Stobe::NativeTravelReceiptPolicy::DUPLICATE_CONFLICT) {
      reason = "request_identity_conflict"; return false;
    }
  }
  unsigned long long unused = 0;
  const int prepare = Prepare(serial, speaker, target != nullptr, agreement, request, expectedWorld, unused);
  if (prepare == 0) { reason = "request_already_reserved"; return false; }
  if (prepare != 1) { reason = "travel_identity_or_ownership_rejected"; return false; }
  // Existing native orders and legacy follow/route controllers retain ownership.
  if (SnapshotFollowTargets().count(serial) || SnapshotTravelTargets().count(serial)) {
    reason = "existing_travel_controller"; return false;
  }
  try {
    OrdersReceiver *orders = actor->getOrdersReciever();
    Faction *faction = actor->getFaction();
    if (actor->isDead() || actor->isUnconcious() || actor->isPlayerCharacter() ||
        (faction && faction->isThePlayer()) ||
        !orders || orders->hasPlayerOrders() || !orders->orders.list.empty()) {
      reason = "npc_has_existing_orders_or_unavailable"; return false;
    }
    if (target && (target == actor || target->isDead() || target->getHandle().serial != speaker)) {
      reason = "follow_target_not_agreed_speaker"; return false;
    }
    Receipt r; r.actor = serial; r.speaker = speaker; r.actorHandle = actor->getHandle();
    r.follow = target != nullptr; r.direct = true; r.expires = expiresGameTs;
    r.issuedTick = GetTickCount();
    r.agreement = agreement; r.request = request; r.world = expectedWorld;
    r.sessionGeneration = PlaythroughSession::Generation();
    r.dispatchEnvelope = dispatchEnvelope;
    r.subject = target ? target->getHandle() : hand();
    r.order.taskType = r.follow ? int(STAY_CLOSE_TO_TARGET) : int(MOVE_CUS_ORDERED);
    r.order.subjectSerial = r.subject.serial; r.order.x = x; r.order.y = y; r.order.z = z;
    const int jobs = orders->getPermajobCount(); const bool jobsOn = orders->isJobsEnabled();
    {
      Lock lock(mutex);
      absence[serial].verified = false;
      r.task = "order:" + Number(serial) + ":" + Number(++sequence);
      r.phase = "dispatching"; r.reason = "native_dispatch_started_outcome_pending"; r.terminal = true;
      std::vector<Receipt> &history = receipts[serial];
      if (history.size() >= 32) history.erase(history.begin());
      history.push_back(r); issuedRequests[requestKey] = r;
    }
    orders->addOrder(static_cast<TaskType>(r.order.taskType), r.subject, Ogre::Vector3(x,y,z), false, false);
    // Claim immediately, before reThink can progress or replace the order.
    const bool captured = CaptureOrder(actor, r, true, reason);
    {
      Lock lock(mutex);
      r.dispatchAccepted = captured;
      Emit(r, captured ? "running" : "failed", captured ? "native_owned_order_assigned" : reason, !captured);
      *Latest(serial) = r; issuedRequests[requestKey] = r;
    }
    if (!captured) return false; // Retain failed ownership, never issue a second task blindly.
    if (jobs != orders->getPermajobCount() || jobsOn != orders->isJobsEnabled()) {
      Lock lock(mutex);
      Emit(*Latest(serial), "failed", "native_job_state_changed", true); return false;
    }
    actor->reThinkCurrentAIAction(); reason = "native_owned_order_assigned"; return true;
  } catch (...) {
    reason = "owned_travel_dispatch_exception";
    Lock lock(mutex);
    Receipt *r = Latest(serial);
    if (r && r->request == request && r->agreement == agreement) Emit(*r, "failed", reason, true);
    return false;
  }
}
bool ReleaseOwned(GameWorld *world, unsigned int actor, unsigned int speaker,
                  const std::string &agreement, const std::string &expectedWorld,
                  unsigned long sessionGeneration, const std::string &task,
                  std::string &reason) {
  if (!GameThread()) { reason = "not_game_thread"; return false; }
  Lock lock(mutex);
  Receipt *r = Latest(actor);
  if (!r || !r->direct || expectedWorld.empty() || expectedWorld != worldId ||
      !Stobe::NativeTravelReceiptPolicy::MatchesCurrentScope(
        ReceiptScope(*r), actor, speaker, agreement, r->request, expectedWorld,
        sessionGeneration) || sessionGeneration != PlaythroughSession::Generation() ||
      r->task != task) {
    reason = "owned_travel_identity_mismatch"; return false;
  }
  if (r->fullyReleased) { reason = "already_released"; return true; }
  try {
    r->pendingPhase = "cancelled"; r->pendingReason = "exact_owned_order_cancelled"; r->pendingArrived = false;
    if (r->endPending) {
      Character *npc = Stobe::KenshiAi::ResolveCharacter(world,actor);
      if (!NativeEnded(npc,*r)) { reason = "native_end_pending"; return false; }
      r->fullyReleased = true;
      Emit(*r,"cancelled",r->pendingReason,true,true); return true;
    }
    if (!CancelDirect(world, *r, reason)) {
      Emit(*r, r->endPending ? "running" : "failed", reason, !r->endPending); return false;
    }
    Emit(*r, "cancelled", "exact_owned_order_cancelled", true, true); return true;
  } catch (...) { Emit(*r, "failed", "owned_cancel_exception", true); reason = r->reason; return false; }
}
void Tick(GameWorld *world, long long nowGameTs) {
  if (!GameThread() || !world) return;
  Lock lock(mutex);
  if (worldId.empty()) Reset(); // Also initialize on first stable load with no GUI teardown.
  const DWORD nowTick = GetTickCount();
  if (lastTick && nowTick - lastTick < 250) return;
  lastTick = nowTick;
  if (observedGameTs > 0 && nowGameTs < observedGameTs) { Reset(); return; }
  observedGameTs = nowGameTs; observedUnix = static_cast<long long>(std::time(nullptr));
  for (std::map<unsigned int,std::vector<Receipt> >::iterator entry=receipts.begin(); entry!=receipts.end(); ++entry) {
    if (entry->second.empty()) continue;
    Receipt &r = entry->second.back();
    if (!r.direct || (r.terminal && !r.endPending) || r.fullyReleased) continue;
    try {
      Character *actor = Stobe::KenshiAi::ResolveCharacter(world, r.actor);
      if (!actor) {
        Emit(r, "running", "actor_unloaded_observation_unavailable", false); continue;
      }
      if (!SameHand(actor->getHandle(), r.actorHandle)) {
        Emit(r, "failed", "actor_identity_changed", true); continue;
      }
      OrdersReceiver *orders = actor->getOrdersReciever();
      if (!orders) { Emit(r, "failed", "orders_unavailable", true); continue; }
      if (r.endPending) {
        const bool absentNow = NativeEnded(actor,r);
        if (Stobe::NativeTravelReceiptPolicy::MatchesRelease(
              ReceiptScope(r), r.actor, r.speaker, r.agreement, worldId,
              PlaythroughSession::Generation(), r.task, absentNow)) {
          r.fullyReleased = true;
          const bool viable = !actor->isDead() && !actor->isUnconcious();
          const bool complete = r.pendingArrived && viable;
          Emit(r, r.pendingPhase == "completed" && !viable ? "failed" : r.pendingPhase,
               viable ? r.pendingReason : "actor_unavailable_before_verified_end", true,true,complete);
        }
        continue;
      }
      const Ogre::Vector3 pos = actor->getPosition();
      bool arrived = Stobe::NativeTravelReceiptPolicy::AtAgreedEndpoint(
        pos.x, pos.y, pos.z, r.order.x, r.order.y, r.order.z);
      if (r.follow && arrived) {
        Character *leader = Stobe::KenshiAi::ResolveCharacter(world, r.speaker);
        if (!leader || !SameHand(leader->getHandle(), r.subject)) arrived = false;
        else {
          const Ogre::Vector3 leadPos = leader->getPosition();
          arrived = Stobe::NativeTravelReceiptPolicy::RouteArrival(true,
            pos.x, pos.y, pos.z, leadPos.x, leadPos.y, leadPos.z,
            r.order.x, r.order.y, r.order.z);
        }
      }
      const bool viable = !actor->isDead() && !actor->isUnconcious();
      if (orders->orders.list.empty()) {
        r.pendingArrived = arrived && viable; r.pendingPhase = r.pendingArrived ? "completed" : "failed";
        r.pendingReason = r.pendingArrived ? "measured_route_arrival_order_ended" : "native_order_ended_before_goal";
        r.endPending = true; r.fullyReleased = NativeEnded(actor,r);
        Emit(r, r.fullyReleased ? r.pendingPhase : "running",
             r.fullyReleased ? r.pendingReason : "native_order_gone_end_unverified",
             r.fullyReleased,r.fullyReleased,r.fullyReleased && r.pendingArrived);
        continue;
      }
      std::string reason;
      if (!CaptureOrder(actor, r, false, reason)) { Emit(r, "failed", reason, true); continue; }
      CharMovement *movement = actor->getMovement();
      const bool pathFailed = movement && movement->pathFailed() && nowTick - r.issuedTick >= 1000;
      r.pathFailureSamples = pathFailed ? r.pathFailureSamples + 1 : 0;
      const bool failed = actor->isDead() || actor->isUnconcious() || r.pathFailureSamples >= 3;
      const bool expired = nowGameTs >= r.expires;
      if (arrived || expired || failed) {
        r.pendingArrived = arrived && viable && !failed;
        r.pendingPhase = r.pendingArrived ? "completed" : "failed";
        r.pendingReason = r.pendingArrived ? "measured_route_arrival" : expired ? "agreement_expired" : "native_path_or_actor_failure";
        if (CancelDirect(world, r, reason)) {
          Emit(r, r.pendingPhase, r.pendingReason, true, true, r.pendingArrived);
        } else Emit(r, r.endPending ? "running" : "failed", reason, !r.endPending);
      }
    } catch (...) { Emit(r, "failed", "owned_travel_observation_exception", true); }
  }
}
void ObserveIdle(GameWorld *world, Character *actor, long long nowGameTs) {
  if (!GameThread() || !world || !actor) return;
  const unsigned int serial = actor->getHandle().serial;
  const bool controlled = SnapshotFollowTargets().count(serial) || SnapshotTravelTargets().count(serial);
  bool verified = false;
  try {
    OrdersReceiver *orders = actor->getOrdersReciever();
    CharBody *body = actor->getBody(); CharMovement *movement = actor->getMovement();
    auto travelTask = [](const Tasker *task) -> bool {
      return task && task->taskData && (task->taskData->key == STAY_CLOSE_TO_TARGET || task->taskData->key == MOVE_CUS_ORDERED);
    };
    auto listHasTravel = [&travelTask](const lektor<Tasker *> &list) -> bool {
      if (list.size() > 4096 || (list.size() && !list.valid())) return true;
      for (unsigned int i=0; i<list.size(); ++i) if (travelTask(list[i])) return true;
      return false;
    };
    if (!controlled && orders && body && movement && orders->orders.list.empty() &&
        !movement->isCurrentlyMoving() && !travelTask(body->currentAction)) {
      const TaskMatch &goal = orders->getCurrentGoal();
      bool remaining = goal.taskData && (goal.key()==STAY_CLOSE_TO_TARGET || goal.key()==MOVE_CUS_ORDERED);
      remaining = remaining || listHasTravel(orders->jobs) || listHasTravel(orders->permajobs) || travelTask(orders->holdPositionOrders);
      for (int i=0; i<5; ++i) remaining = remaining || listHasTravel(orders->goals[i]) || listHasTravel(orders->squadAIPackage[i]);
      verified = !remaining;
    }
  } catch (...) { verified = false; }
  Lock lock(mutex);
  Receipt *latest = Latest(serial);
  if (latest && latest->direct && !latest->fullyReleased) {
    if (Stobe::NativeTravelReceiptPolicy::MatchesRelease(
          ReceiptScope(*latest), latest->actor, latest->speaker, latest->agreement,
          worldId, PlaythroughSession::Generation(), latest->task, verified) &&
        latest->terminal && !latest->endPending) {
      latest->fullyReleased = true;
      Emit(*latest,"failed","owned_travel_absence_observed",true,true);
    } else verified = false;
  }
  Absence fact; fact.verified = verified && !worldId.empty(); fact.gamets = nowGameTs;
  fact.unixTime = static_cast<long long>(std::time(nullptr));
  fact.evidence = worldId + ":absence:" + Number(++sequence);
  absence[serial] = fact;
}
bool DispatchWire(GameWorld *world, Character *actor, const std::string &json,
                  long long nowGameTs, std::string &reason) {
  if (!GameThread() || !actor || json.size() > 4096 || json.empty() || json.front() != '{') {
    reason = "invalid_owned_travel_envelope"; return false;
  }
  auto field = [&json](const char *key) -> std::string { return JsonReadField(json, key); };
  auto integer = [&field](const char *key, long long &out) -> bool {
    const std::string value = field(key);
    if (value.empty() || value.find_first_not_of("0123456789") != std::string::npos) return false;
    errno = 0; char *end = nullptr; out = _strtoi64(value.c_str(), &end, 10);
    return errno != ERANGE && end && *end == 0;
  };
  long long actorId = 0, speaker = 0;
  if (!integer("actor_serial", actorId) || actorId != actor->getHandle().serial ||
      !integer("speaker_serial", speaker) || speaker <= 0 || speaker > 0xffffffffLL) {
    reason = "owned_travel_participant_mismatch"; return false;
  }
  const std::string agreement = field("agreement_id"), expectedWorld = field("world_id");
  long long sessionGeneration = 0;
  if (!integer("session_generation", sessionGeneration) || sessionGeneration < 1 ||
      static_cast<unsigned long>(sessionGeneration) != PlaythroughSession::Generation()) {
    reason = "session_generation_mismatch"; return false;
  }
  if (field("operation") == "release")
    return ReleaseOwned(world, static_cast<unsigned int>(actorId), static_cast<unsigned int>(speaker),
                        agreement, expectedWorld, static_cast<unsigned long>(sessionGeneration),
                        field("task_id"), reason);
  if (field("operation") != "start") { reason = "unknown_owned_travel_operation"; return false; }
  const std::string request = field("request_id");
  auto reject = [&](const std::string &why) -> bool {
    reason = why;
    Lock lock(mutex);
    if (!worldId.empty() && expectedWorld == worldId && Token(agreement,96) && Token(request,96) &&
        issuedRequests.count(Stobe::NativeTravelReceiptPolicy::RequestKey(agreement,request)) == 0 && issuedRequests.size() < 4096) {
      Receipt r; r.actor = static_cast<unsigned int>(actorId); r.speaker = static_cast<unsigned int>(speaker);
      r.agreement = agreement; r.request = request; r.world = expectedWorld;
      r.sessionGeneration = PlaythroughSession::Generation(); r.dispatchEnvelope = json;
      r.follow = field("kind") == "follow"; r.direct = true; r.notStarted = true; r.fullyReleased = true;
      Emit(r,"failed",why,true,true);
      std::vector<Receipt> &history = receipts[r.actor];
      if (history.size() >= 32) history.erase(history.begin());
      // Rejected competing requests must not hide an active task from Tick.
      if (!history.empty() && !history.back().fullyReleased) history.insert(history.end()-1,r);
      else history.push_back(r);
      issuedRequests[Stobe::NativeTravelReceiptPolicy::RequestKey(agreement,request)] = r;
    }
    return false;
  };
  long long expiry = 0;
  if (!integer("expires_gamets", expiry)) return reject("invalid_owned_travel_expiry");
  Character *target = nullptr; float point[3] = {0,0,0};
  if (field("kind") == "follow") {
    target = Stobe::KenshiAi::ResolveCharacter(world, static_cast<unsigned int>(speaker));
    if (!target) return reject("agreed_follow_target_unavailable");
  } else if (field("kind") != "route") return reject("unknown_owned_travel_kind");
  {
    const char *keys[] = {"x","y","z"};
    for (int i = 0; i < 3; ++i) {
      const std::string value = field(keys[i]); char *end = nullptr; errno = 0;
      const double number = std::strtod(value.c_str(), &end);
      if (value.empty() || !end || *end || errno == ERANGE || !_finite(number) || std::fabs(number) > 10000000) {
        return reject("invalid_owned_travel_coordinate");
      }
      point[i] = static_cast<float>(number);
    }
    const std::string candidate = field("candidate_id");
    if (!candidate.empty() && !Stobe::LocalTravel::ValidateForDispatch(world, actor, candidate,
        point[0], point[1], point[2], field("label"), reason)) return reject(reason);
  }
  if (!Start(world, actor, static_cast<unsigned int>(speaker), target, point[0], point[1], point[2],
               agreement, request, expectedWorld, json, expiry, nowGameTs, reason)) return reject(reason);
  return true;
}
} }
