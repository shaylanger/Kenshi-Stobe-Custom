#pragma once
#include <string>
class Character;
class Building;
class Inventory;
namespace Stobe { namespace Activity {
struct MineLeaseSnapshot {
  unsigned actorSerial, buildingSerial, baseline, expectedCount, outputCount, creditedOutput;
  std::string item;
  bool found, identityMatches, outputCountConsistent, contributionObserved;
  MineLeaseSnapshot() : actorSerial(0), buildingSerial(0), baseline(0), expectedCount(0),
      outputCount(0), creditedOutput(0), found(false), identityMatches(false),
      outputCountConsistent(false), contributionObserved(false) {}
};
// All calls are game-thread only. True includes uncertain protection.
bool IsProtectedActivityTarget(Character*, Character*, std::string& reason);
bool BeginMineLease(const std::string& agreement, Character*, Building*,
                    const std::string& itemSid, std::string& reason);
void EndMineLease(const std::string& agreement);
void ResetMineLeases();
unsigned MineOutputCredit(const std::string& agreement);
// Read-only copy of the synchronous mine observer state; does not call Check,
// mutate lease validity, expose pointers, or claim native output absent proof.
bool InspectMineLease(const std::string& agreement, Character* expectedActor,
                      Building* expectedBuilding, MineLeaseSnapshot& out);
bool ConfirmMineOutputTaken(const std::string& agreement, unsigned amount);
Inventory* NaturalResourceOutput(Building*, Character*, const std::string& itemSid,
                                 bool requireExclusive, std::string& reason);
// Recovery only. Caller must first resolve original actor/building identity in
// original world. This verifies retained original section/inventory, without
// granting new work after cancellation or producer contamination.
Inventory* RetainedMineOutput(const std::string& agreement, Building*, Character*);
} }
namespace Stobe { namespace Activity {
bool MineSourcePermitted(Building*, Character*, std::string& resourceId, std::string& reason);
} }
