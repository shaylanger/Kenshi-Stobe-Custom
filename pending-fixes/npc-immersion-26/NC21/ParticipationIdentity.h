#pragma once
// NC21 (row 13-c, participation_bound=0): pure identity rules for the participation proof (no Kenshi types, g++-testable).
//
// Root cause: Character::getInstanceID() is RootObject::getInstanceID(), which returns NULL for every Character (only
// Building overrides it; kenshi_x64.exe RVA 0xD1EE0 is "xor eax,eax; ret"). So the InstanceID uid never exists for an
// NPC or the player, and the whole mod already identifies characters as hand_<serial> (Context.cpp GetStorageIDFor and the
// snapshot "id"; the server's core_npc.storage_id and the relationship ledger use the same string). ParticipationEvidence
// refused that fallback, so participation_bound was 0 for every trip. The proof now carries exactly the id the server
// stores: the uid when the engine ever provides one, else hand_<serial>.
#include <string>
#include <sstream>

namespace Stobe { namespace Participation { namespace Identity {

// Same rule and format as Context.cpp GetStorageIDFor: uid if non-empty, else hand_<serial>, else empty (unusable).
inline std::string StorageId(const std::string *uidOrNull, unsigned serial) {
  if (uidOrNull && !uidOrNull->empty()) return *uidOrNull;
  if (serial == 0) return std::string();
  std::ostringstream o; o << "hand_" << serial; return o.str();
}

inline bool IsHandFallback(const std::string &id) { return id.compare(0, 5, "hand_") == 0; }

enum Verdict {
  BIND_OK = 0, BIND_ACTOR_UNRESOLVED, BIND_PARTNER_UNRESOLVED, BIND_SAME_SERIAL, BIND_SCOPE_EMPTY,
  BIND_NO_ACTOR_IDENTITY, BIND_NO_PARTNER_IDENTITY, BIND_SAME_IDENTITY
};

// Order matters only for the reported reason; every non-OK verdict leaves the proof unbound (never qualified).
inline Verdict Decide(bool actorResolved, bool partnerResolved, unsigned actor, unsigned partner, bool scopeNonEmpty,
                      const std::string &actorId, const std::string &partnerId) {
  if (!actorResolved) return BIND_ACTOR_UNRESOLVED;
  if (!partnerResolved) return BIND_PARTNER_UNRESOLVED;
  if (actor == partner) return BIND_SAME_SERIAL;
  if (!scopeNonEmpty) return BIND_SCOPE_EMPTY;
  if (actorId.empty()) return BIND_NO_ACTOR_IDENTITY;
  if (partnerId.empty()) return BIND_NO_PARTNER_IDENTITY;
  if (actorId == partnerId) return BIND_SAME_IDENTITY;
  return BIND_OK;
}

inline const char *VerdictName(Verdict v, const std::string &actorId) {
  switch (v) {
    case BIND_OK: return IsHandFallback(actorId) ? "ok_hand_fallback" : "ok_uid";
    case BIND_ACTOR_UNRESOLVED: return "actor_unresolved";
    case BIND_PARTNER_UNRESOLVED: return "partner_unresolved";
    case BIND_SAME_SERIAL: return "same_actor_partner";
    case BIND_SCOPE_EMPTY: return "world_agreement_or_task_empty";
    case BIND_NO_ACTOR_IDENTITY: return "actor_no_identity";
    case BIND_NO_PARTNER_IDENTITY: return "partner_no_identity";
    case BIND_SAME_IDENTITY: return "same_identity";
  }
  return "unknown";
}

} } }
