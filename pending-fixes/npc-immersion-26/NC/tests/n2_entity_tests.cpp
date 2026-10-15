// N2 entity export + abandoned_in_danger kind (SocialEventProtocol.cpp).
#include "SocialEventProtocol.h"
#include <iostream>
#include <string>
static int g_fail = 0, g_pass = 0;
#define CHECK(c) do { if (c) ++g_pass; else { ++g_fail; std::cout << "FAIL line " << __LINE__ << ": " #c "\n"; } } while (0)
static bool Has(const std::string &s, const char *x) { return s.find(x) != std::string::npos; }

int main() {
  StobeSocial::EntityInfo a, b;
  a.serial = 11; a.name = "Leaver"; a.storageId = "hand_11"; a.faction = "Nameless"; a.inPlayerFaction = 1; a.conscious = 1;
  b.serial = 12; b.name = "Partner"; b.inPlayerFaction = 1; b.conscious = 0;
  b.inPlayerSquad = 1; b.squadId = 77; b.squadName = "Wanderers \"A\""; b.settlement = "Hub";
  CHECK(StobeSocial::StructuredKind("abandoned_in_danger"));
  CHECK(StobeSocial::StructuredKind("harm"));
  CHECK(!StobeSocial::StructuredKind("nonsense"));
  std::string facts = "\"evidence_id\":\"abandon:11:12:1000\",\"partner_state\":\"knocked_out\",\"distance_m\":45,\"seconds\":22,\"observer_saw_leaving\":false";
  std::string env = StobeSocial::StructuredEnvelope("camp1", "sess1", 1, 1, 1000, "abandoned_in_danger", &a, &b, facts);
  CHECK(!env.empty());
  CHECK(Has(env, "\"event_kind\":\"abandoned_in_danger\""));
  CHECK(Has(env, "\"in_player_squad\":true"));
  CHECK(Has(env, "\"squad_id\":\"squad_77\""));
  CHECK(Has(env, "\"squad_name\":\"Wanderers \\\"A\\\"\""));
  CHECK(Has(env, "\"settlement\":\"Hub\""));
  CHECK(Has(env, "\"evidence_id\":\"abandon:11:12:1000\""));
  // the leaver (no squad data) keeps the old entity shape: exactly one in_player_squad / squad_id in the envelope
  CHECK(env.find("in_player_squad") == env.rfind("in_player_squad"));
  CHECK(env.find("squad_id") == env.rfind("squad_id"));
  std::string plain = StobeSocial::StructuredEnvelope("camp1", "sess1", 1, 2, 1000, "harm", &a, nullptr, "");
  CHECK(!Has(plain, "in_player_squad") && !Has(plain, "squad_name") && !Has(plain, "settlement"));
  std::string w = StobeSocial::WitnessJson(b, "sess1", 1, true, true, 1, 1, 1);
  CHECK(Has(w, "\"settlement\":\"Hub\"") && Has(w, "\"sees_actor\":true"));
  b.squadName = std::string(80, 'x');
  CHECK(!Has(StobeSocial::StructuredEnvelope("camp1", "sess1", 1, 3, 1000, "harm", &b, nullptr, ""), "squad_name"));
  std::cout << "N2 entity tests: " << g_pass << " passed, " << g_fail << " failed\n";
  return g_fail ? 1 : 0;
}
