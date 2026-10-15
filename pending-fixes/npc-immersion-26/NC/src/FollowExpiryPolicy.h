#pragma once
// Pure logic: safety-net expiry and reporting for the legacy (unscoped) FOLLOW controller.
// A non-squad NPC that was told to follow must not follow forever; the server's default end
// condition is its own business, this is the native floor. Squad members (player faction) are
// never expired, and neither are follows owned by a scoped travel lifecycle (it has its own
// expiry and receipts).
#include <sstream>
#include <string>
namespace Stobe { namespace FollowExpiry {

static const long long kDefaultLimitGameSeconds = 24LL * 3600LL; // 24 game hours

struct Info {
 bool present; long long startGameTs; long long nowGameTs; long long limitSeconds;
 Info() : present(false), startGameTs(0), nowGameTs(0), limitSeconds(kDefaultLimitGameSeconds) {}
};
// 0 start = unknown (world clock was not available when the follow was registered).
inline long long AgeSeconds(long long startGameTs, long long nowGameTs) {
 if (startGameTs <= 0 || nowGameTs < startGameTs) return 0;
 return nowGameTs - startGameTs;
}
// limitSeconds <= 0 disables expiry.
inline bool ShouldExpire(long long startGameTs, long long nowGameTs, long long limitSeconds, bool squadMember, bool ownedTravel) {
 if (squadMember || ownedTravel || limitSeconds <= 0 || startGameTs <= 0) return false;
 return AgeSeconds(startGameTs, nowGameTs) >= limitSeconds;
}
// native_ai.temporary_companion block (observed:true always carries the 'present' answer).
inline std::string TemporaryCompanionJson(const Info& i, bool squadMember, bool ownedTravel, const std::string& agreementId) {
 if (!i.present) return "{\"observed\":true,\"present\":false}";
 std::ostringstream s;
 s << "{\"observed\":true,\"present\":true,\"source\":\"" << (ownedTravel ? "owned_travel" : "legacy_follow")
   << "\",\"squad_member\":" << (squadMember ? "true" : "false");
 if (i.startGameTs > 0) {
  s << ",\"since_game_ts\":" << i.startGameTs << ",\"age_game_seconds\":" << AgeSeconds(i.startGameTs, i.nowGameTs);
  if (i.limitSeconds > 0 && !squadMember && !ownedTravel) s << ",\"expires_gamets\":" << (i.startGameTs + i.limitSeconds);
 }
 if (!agreementId.empty()) {
  std::string clean; for (size_t k = 0; k < agreementId.size() && k < 80; ++k) { const char c = agreementId[k]; if (c != '"' && c != '\\' && (unsigned char)c >= 0x20) clean += c; }
  s << ",\"agreement_id\":\"" << clean << "\"";
 }
 return s.str() + "}";
}
} }
