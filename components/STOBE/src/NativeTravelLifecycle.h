#pragma once
#include <string>
class GameWorld;
class Character;

// New scoped travel owns one exact native order. The legacy-controller API
// tracks only Stobe re-enforcement and never claims arbitrary AI goal ownership.
// Game mutations are main-thread-only; snapshots and metadata hooks are locked.
namespace Stobe { namespace NativeTravelLifecycle {
void Reset();
// Dedicated scoped executor; never enters the legacy hard-follow controllers.
// target!=nullptr means FOLLOW, otherwise x/y/z is the validated route endpoint.
bool Start(GameWorld *world, Character *actor, unsigned int speaker, Character *target,
           float x, float y, float z, const std::string &agreement,
           const std::string &request, const std::string &expectedWorld,
           const std::string &dispatchEnvelope, long long expiresGameTs,
           long long nowGameTs, std::string &reason);
void Tick(GameWorld *world, long long nowGameTs);
void ObserveIdle(GameWorld *world, Character *actor, long long nowGameTs);
// Internal server-generated envelope only; never expose as an LLM action.
bool DispatchWire(GameWorld *world, Character *actor, const std::string &json,
                  long long nowGameTs, std::string &reason);
bool ReleaseOwned(GameWorld *world, unsigned int actor, unsigned int speaker,
                  const std::string &agreement, const std::string &worldId,
                  const std::string &task, std::string &reason);
std::string WorldId();
void ControllerChanged(unsigned int actor, bool follow, bool present);
// Call BEFORE issuing an action: 1=new request, 0=already issued (skip replay),
// -1=reject. Pass previousRevision to Bind after successful native assignment.
int Prepare(unsigned int actor, unsigned int speaker, bool follow,
            const std::string &agreement, const std::string &request,
            const std::string &expectedWorld, unsigned long long &previousRevision);
bool Bind(unsigned int actor, unsigned int speaker, bool follow,
          const std::string &agreement, const std::string &request,
          const std::string &expectedWorld, unsigned long long previousRevision);
bool Release(unsigned int actor, unsigned int speaker,
             const std::string &agreement, const std::string &world,
             const std::string &task);
// Call BEFORE removing the route controller, only from its measured arrival
// branch. Arrival is a route end condition; it is never a hunting/work result.
void RouteReached(unsigned int actor, float x, float y, float z);
void Failed(unsigned int actor, bool follow, const std::string &reason);
std::string SnapshotJson(unsigned int actor);
} }
