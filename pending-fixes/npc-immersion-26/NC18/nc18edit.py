# NC18 = NC16 (96C6FDDF...) + native-owned travel can actually finish (rows IMM-13-c, 13-c-neg, 19-d, 23-a).
# Usage: python3 nc18edit.py <NC16-tree-root>   (root contains src/). Edits src/NativeTravelLifecycle.cpp only
# (new file src/NativeTravelRouteTarget.h is copied separately). Every edit asserts its anchor exactly once.
import sys, io
root = sys.argv[1]
p = root + '/src/NativeTravelLifecycle.cpp'
s = io.open(p, 'r', encoding='utf-8', newline='').read()
nl = '\r\n' if '\r\n' in s else '\n'
def rep(old, new, count=1):
    global s
    old = old.replace('\n', nl); new = new.replace('\n', nl)
    assert s.count(old) == count, (s.count(old), old[:90])
    s = s.replace(old, new)

# E1 includes
rep('#include "NativeTravelReceiptPolicy.h"\n',
    '#include "NativeTravelReceiptPolicy.h"\n#include "NativeTravelRouteTarget.h"\n')
rep('#include <kenshi/CharMovement.h>\n',
    '#include <kenshi/CharMovement.h>\n#pragma push_macro("min")\n#pragma push_macro("max")\n#undef min\n#undef max\n'
    '#include <kenshi/GameWorld.h>\n#include <kenshi/HavokCharacter.h>\n'
    '#include <kenshi/NavMesh.h>\n#include <kenshi/util/UtilityT.h>\n#include <iomanip>\n'
    '#pragma pop_macro("max")\n#pragma pop_macro("min")\n')

# E2 Receipt diag fields
rep('  int pathFailureSamples;\n  hand actorHandle, subject;\n',
    '  int pathFailureSamples;\n  DWORD diagTick;\n  float reqX, reqY, reqZ;\n  hand actorHandle, subject;\n')
rep('expires(0),startTime(0),issuedTick(0),pathFailureSamples(0),revision(0)',
    'expires(0),startTime(0),issuedTick(0),pathFailureSamples(0),diagTick(0),reqX(0),reqY(0),reqZ(0),revision(0)')

# E3 Emit logs every phase/reason change (never per tick)
rep('''  if (terminal && r.partBegun) r.participation.Freeze(phase == "completed" && arrived, observedGameTs);
  r.phase = phase; r.reason = reason; r.terminal = terminal;
  r.released = released; r.arrived = arrived; r.evidence = ++sequence;
}''',
'''  if (terminal && r.partBegun) r.participation.Freeze(phase == "completed" && arrived, observedGameTs);
  const bool changed = r.phase != phase || r.reason != reason || r.terminal != terminal;
  r.phase = phase; r.reason = reason; r.terminal = terminal;
  r.released = released; r.arrived = arrived; r.evidence = ++sequence;
  if (changed) Log("NATIVE_TRAVEL: task=" + r.task + " actor=" + Number(r.actor) + " phase=" + phase + " reason=" + reason +
                   " terminal=" + (terminal ? "1" : "0") + " released=" + (released ? "1" : "0") + " arrived=" + (arrived ? "1" : "0") +
                   " participation_qualified=" + (r.partBegun && r.participation.frozen.find("\\"qualified\\":true") != std::string::npos ? "1" : "0"));
}''')

# E4 helpers (route target projection + 1-decimal formatter) placed before Start
rep('bool Start(GameWorld *world, Character *actor, unsigned int speaker, Character *target,\n           float x, float y, float z, const std::string &agreement,\n           const std::string &request, const std::string &expectedWorld,\n           const std::string &planHash, const std::string &dispatchEnvelope, long long expiresGameTs,\n           long long nowGameTs, std::string &reason) {\n  if (!GameThread()',
'''namespace {
std::string F1(double v) { std::ostringstream o; o.setf(std::ios::fixed); o.precision(1); o << v; return o.str(); }
struct RtTerrain { double operator()(float x, float z) const { return double(UtilityT::getTerrainHeight(x, z)); } };
struct RtSnap {
  GameWorld *world;
  bool operator()(const Stobe::NativeTravelRouteTarget::Pt &q, Stobe::NativeTravelRouteTarget::Pt &out) const {
    if (!world || !world->navmesh) return false;
    Ogre::Vector3 point;
    if (world->navmesh->getClosestPoint(Ogre::Vector3(q.x, q.y, q.z), 60.0f, 1.0f, false, point) != 1) return false;
    if (!_finite(point.x) || !_finite(point.y) || !_finite(point.z) || UtilityT::isIndoorsFast(point)) return false;
    const float h = UtilityT::getTerrainHeight(point.x, point.z);
    if (_finite(h) && std::fabs(point.y - h) > 25.0f) return false; // roof / bridge, not walkable ground
    out = Stobe::NativeTravelRouteTarget::Pt(point.x, point.y, point.z); return true;
  }
};
struct RtReach {
  GameWorld *world; HavokCharacter *avatar; Ogre::Vector3 actorPos; DWORD t0;
  int operator()(const Stobe::NativeTravelRouteTarget::Pt &p) const {
    if (!world || !world->navmesh || !avatar) return -1;
    if (GetTickCount() - t0 > 150) return -1; // main-thread frame budget: stop, never guess
    const double dx = double(p.x) - actorPos.x, dz = double(p.z) - actorPos.z;
    if (dx * dx + dz * dz > 3000.0 * 3000.0) return -1; // long legs: navmesh connectivity not trusted
    if (!avatar->isOnNavmesh()) return -1;
    const int rc = world->navmesh->pathExists(avatar, Ogre::Vector3(p.x, p.y, p.z));
    return rc == 1 ? 1 : (rc == 0 ? 0 : -1);
  }
};
}
bool Start(GameWorld *world, Character *actor, unsigned int speaker, Character *target,
           float x, float y, float z, const std::string &agreement,
           const std::string &request, const std::string &expectedWorld,
           const std::string &planHash, const std::string &dispatchEnvelope, long long expiresGameTs,
           long long nowGameTs, std::string &reason) {
  if (!GameThread()''')

# E5 Start: route targets are checked/substituted BEFORE the order exists (follow keeps the player as subject)
rep('    Receipt r; r.actor = serial; r.speaker = speaker; r.actorHandle = actor->getHandle();\n    r.follow = target != nullptr;',
'''    const float requestedX = x, requestedY = y, requestedZ = z;
    std::string targetVerdict = "follow_endpoint_kept", targetNote;
    int targetProbes = 0; double targetDrift = 0;
    if (!target) {
      namespace Rt = Stobe::NativeTravelRouteTarget;
      CharMovement *mv = actor->getMovement();
      RtReach reach; reach.world = world; reach.avatar = mv ? mv->havokCharacter : nullptr;
      reach.actorPos = actor->getPosition(); reach.t0 = GetTickCount();
      RtSnap snap; snap.world = world; RtTerrain terrain;
      const double bearing = std::atan2(double(reach.actorPos.z) - requestedZ, double(reach.actorPos.x) - requestedX);
      const Rt::Choice choice = Rt::Choose(Rt::Pt(requestedX, requestedY, requestedZ), bearing, terrain, snap, reach);
      if (choice.verdict == Rt::ADJUSTED) { x = choice.point.x; y = choice.point.y; z = choice.point.z; }
      targetVerdict = Rt::VerdictName(choice.verdict); targetNote = choice.note;
      targetProbes = choice.probes; targetDrift = choice.drift;
    }
    Receipt r; r.actor = serial; r.speaker = speaker; r.actorHandle = actor->getHandle();
    r.reqX = requestedX; r.reqY = requestedY; r.reqZ = requestedZ;
    r.follow = target != nullptr;''')

# E5b Start: one log line with everything the next live run needs
rep('''    const bool captured = CaptureOrder(actor, r, true, reason);
    {
      Lock lock(mutex);
      r.dispatchAccepted = captured;''',
'''    const bool captured = CaptureOrder(actor, r, true, reason);
    {
      const Ogre::Vector3 here = actor->getPosition();
      Log("NATIVE_TRAVEL_START: task=" + r.task + " actor=" + Number(serial) + " kind=" + (target ? "follow" : "route") +
          " requested=" + F1(requestedX) + "," + F1(requestedY) + "," + F1(requestedZ) +
          " goal=" + F1(x) + "," + F1(y) + "," + F1(z) + " target=" + targetVerdict + (targetNote.empty() ? "" : ":" + targetNote) +
          " probes=" + Number(targetProbes) + " drift=" + F1(targetDrift) +
          " terrain_y=" + F1(UtilityT::getTerrainHeight(x, z)) + " actor=" + F1(here.x) + "," + F1(here.y) + "," + F1(here.z) +
          " planar_to_goal=" + F1(Stobe::NativeTravelRouteTarget::Planar(Stobe::NativeTravelRouteTarget::Pt(here.x, here.y, here.z),
                                                                           Stobe::NativeTravelRouteTarget::Pt(x, y, z))) +
          " captured=" + (captured ? "1" : "0") + " participation_bound=" + (r.participation.bound ? "1" : "0"));
    }
    {
      Lock lock(mutex);
      r.dispatchAccepted = captured;''')

# E6 Tick arrival: ground-plane radius + bounded vertical slop (follow also needs the leader there)
rep('''      bool arrived = Stobe::NativeTravelReceiptPolicy::AtAgreedEndpoint(
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
        r.pendingArrived = arrived && viable; r.pendingPhase = r.pendingArrived ? "completed" : "failed";''',
'''      namespace Rt = Stobe::NativeTravelRouteTarget;
      const Rt::Pt goalPt(r.order.x, r.order.y, r.order.z), herePt(pos.x, pos.y, pos.z);
      Rt::Pt leadPt(herePt);
      bool leaderOk = true;
      if (r.follow) {
        Character *leader = Stobe::KenshiAi::ResolveCharacter(world, r.speaker);
        if (!leader || !SameHand(leader->getHandle(), r.subject)) leaderOk = false;
        else { const Ogre::Vector3 leadPos = leader->getPosition(); leadPt = Rt::Pt(leadPos.x, leadPos.y, leadPos.z); }
      }
      bool arrived = leaderOk && Rt::RouteNear(r.follow, herePt, leadPt, goalPt, Rt::kArriveRadius);
      // The engine removed the MOVE order itself: its own completion radius is a little wider than ours.
      const bool endedNear = arrived || (leaderOk && Rt::RouteNear(r.follow, herePt, leadPt, goalPt, Rt::kEngineEndRadius));
      const bool viable = !actor->isDead() && !actor->isUnconcious();
      if (nowTick - r.diagTick >= 2000) {
        r.diagTick = nowTick;
        CharMovement *dm = actor->getMovement();
        std::string md = "n/a";
        try { if (dm) { const Ogre::Vector3 d = dm->getDestination(); md = F1(Rt::Planar(Rt::Pt(d.x, d.y, d.z), goalPt)); } } catch (...) {}
        Log("NATIVE_TRAVEL_OBS: task=" + r.task + " kind=" + (r.follow ? "follow" : "route") + " pos=" + F1(pos.x) + "," + F1(pos.y) + "," + F1(pos.z) +
            " goal=" + F1(r.order.x) + "," + F1(r.order.y) + "," + F1(r.order.z) + " planar=" + F1(Rt::Planar(herePt, goalPt)) +
            " dy=" + F1(double(pos.y) - r.order.y) + " moving=" + (dm && dm->isCurrentlyMoving() ? "1" : "0") +
            " orders=" + Number(orders->orders.list.size()) + " move_dest_to_goal=" + md + " arrived8=" + (arrived ? "1" : "0"));
      }
      if (orders->orders.list.empty()) {
        Log("NATIVE_TRAVEL_ORDER_ENDED: task=" + r.task + " planar=" + F1(Rt::Planar(herePt, goalPt)) + " dy=" + F1(double(pos.y) - r.order.y) +
            " arrived8=" + (arrived ? "1" : "0") + " near16=" + (endedNear ? "1" : "0") + " leader_ok=" + (leaderOk ? "1" : "0") + " viable=" + (viable ? "1" : "0"));
        r.pendingArrived = endedNear && viable; r.pendingPhase = r.pendingArrived ? "completed" : "failed";''')

# E7 Tick: log the arrival decision before the cancel
rep('''        if (CancelDirect(world, r, reason)) {
          Emit(r, r.pendingPhase, r.pendingReason, true, true, r.pendingArrived);''',
'''        Log("NATIVE_TRAVEL_FINISH: task=" + r.task + " phase=" + r.pendingPhase + " reason=" + r.pendingReason + " planar=" +
            F1(Rt::Planar(herePt, goalPt)) + " dy=" + F1(double(pos.y) - r.order.y));
        if (CancelDirect(world, r, reason)) {
          Emit(r, r.pendingPhase, r.pendingReason, true, true, r.pendingArrived);''')

io.open(p, 'w', encoding='utf-8', newline='').write(s)
print('nc18edit OK', p)
