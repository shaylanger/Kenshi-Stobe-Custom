#pragma once
// NC22 (row 14-d): pure ownership decision for IsProtectedActivityTarget, no engine types so it is unit-testable.
// Cause: the old check was `getMySlaveOwner().serial != 0` alone. For freshly spawned wild Dust Bandits (harness
// createRandomCharacter, platoon-mates) that hand is non-zero for some members and not for others, so ClearGroup rejected
// them as owned_target (14-d NC20 diag: Prenn/Othra protected=1, Wulf/Doran/Falt protected=0, same spawn).
// A non-zero owner handle alone is therefore NOT proof of ownership. A person (non-animal) is owned only when the owner
// handle is corroborated by the engine's own slave state (isSlave() != NOT_SLAVE, i.e. IS_SLAVE/ESCAPING/EX) or the chained
// mode. A character in a prison cage is a captive and stays protected. Animals keep the strict rule (any owner handle).
namespace Stobe { namespace Activity { namespace Ownership {
// slaveState = int(SlaveStateEnum): 0 NOT_SLAVE, 1 IS_SLAVE, 2 ESCAPING_SLAVE, 3 EX_SLAVE.
// Returns "" when not owned/captive, else the protection reason.
inline const char* Decide(bool animal, unsigned ownerSerial, int slaveState, bool chained, bool inPrison) {
 if(inPrison) return "captive_target";
 if(animal) return ownerSerial ? "owned_target" : "";
 if(slaveState != 0 || chained) return "owned_target";
 return "";
}
}}}
