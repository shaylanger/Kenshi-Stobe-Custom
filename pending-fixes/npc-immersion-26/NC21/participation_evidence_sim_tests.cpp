// NC21 sim test: compiles the REAL ParticipationEvidence.h / ParticipationIdentity.h from the source tree against g++ stubs
// (stubs/ = Character, InstanceID, hand, GameWorld) and replays the 13-c situation: the engine returns NULL from
// Character::getInstanceID() for every Character. Fails on NC20 (bound=0 forever), passes on NC21.
// Build/run: see NC21/offline-tests.sh.
#include <cstdio>
#include <map>
#include <string>
#include "ParticipationEvidence.h"

static int g_pass = 0, g_fail = 0;
static void Check(const char *name, bool ok, const std::string &detail = std::string()) {
  if (ok) { ++g_pass; std::printf("PASS %s\n", name); }
  else { ++g_fail; std::printf("FAIL %s %s\n", name, detail.c_str()); }
}

static std::map<unsigned, Character *> g_known;
namespace Stobe { namespace KenshiAi {
Character *ResolveCharacter(GameWorld *, unsigned serial) {
  std::map<unsigned, Character *>::iterator i = g_known.find(serial);
  return i == g_known.end() ? 0 : i->second;
}
} }

static const unsigned CIND = 2529907200u, SHAY = 971557632u;

static void Setup(Character &c, unsigned serial, const char *name, float x, float z) {
  c = Character(); c.h.serial = serial; c.name = name; c.pos = Ogre::Vector3(x, 330.f, z); c.iid = 0; // engine reality: NULL InstanceID
  g_known[serial] = &c;
}

typedef Stobe::Participation::Evidence Ev;

// Walk together for `seconds` game seconds at `speed` u/s with the partner `offset` u behind the actor.
static void Walk(Ev &e, GameWorld *w, Character &a, Character &p, long long &now, int seconds, float speed, float offset) {
  for (int i = 0; i < seconds; ++i) {
    ++now; a.pos.x += speed; p.pos.x = a.pos.x - offset;
    e.Sample(w, "world1", now, 0);
  }
}

int main() {
  GameWorld world;
  Character cind, shay;

  // 1. NULL InstanceID for both parties (what the 4080/5090 lanes showed): must bind with hand_<serial>.
  g_known.clear(); Setup(cind, CIND, "Cind", -61980.f, 16250.f); Setup(shay, SHAY, "Shay", -61990.f, 16250.f);
  Ev e1; e1.Begin(&world, CIND, SHAY, "world1", "trip-1", "order:2529907200:22", true, Ogre::Vector3(-61000.f, 328.f, 16250.f), &cind);
  Check("1a: NULL InstanceID binds (participation_bound=1)", e1.bound, e1.bindWhy);
  Check("1b: why = ok_hand_fallback", e1.bindWhy == "ok_hand_fallback", e1.bindWhy);
  Check("1c: actor id hand_2529907200", e1.actorStorage == "hand_2529907200", e1.actorStorage);
  Check("1d: partner id hand_971557632", e1.partnerStorage == "hand_971557632", e1.partnerStorage);

  // 2. A 60 game-second walk together qualifies and the proof carries the hand_ ids the server stores.
  long long now = 1000;
  e1.Sample(&world, "world1", now, 0);
  Walk(e1, &world, cind, shay, now, 60, 8.f, 6.f);
  e1.Freeze(true, now);
  Check("2a: proof qualified", e1.frozen.find("\"qualified\":true") != std::string::npos, e1.frozen + " | " + e1.Diag());
  Check("2b: proof actor_storage_id", e1.frozen.find("\"actor_storage_id\":\"hand_2529907200\"") != std::string::npos, e1.frozen);
  Check("2c: proof partner_storage_id", e1.frozen.find("\"partner_storage_id\":\"hand_971557632\"") != std::string::npos, e1.frozen);
  Check("2d: no breaks on a clean walk", e1.Diag().find("brk_sep:0,brk_jump:0,brk_gap:0,brk_state:0,brk_scope:0,brk_other:0") != std::string::npos, e1.Diag());

  // 3. Unbound evidence never qualifies (even with a perfect walk): the identity gate still protects the award.
  g_known.clear(); Setup(cind, CIND, "Cind", 0.f, 0.f); Setup(shay, SHAY, "Shay", -5.f, 0.f);
  Ev e3; e3.Begin(&world, CIND, SHAY, "world1", "trip-1", "t1", true, Ogre::Vector3(500.f, 330.f, 0.f), &cind);
  e3.bound = false; now = 2000; Walk(e3, &world, cind, shay, now, 60, 8.f, 6.f); e3.Freeze(true, now);
  Check("3a: bound=false never qualifies", e3.frozen.find("\"qualified\":false") != std::string::npos, e3.frozen);

  // 4. A real uid, when the engine provides one, still wins over the hand_ fallback.
  InstanceID ua, up; ua.uid = "uid-cind-1"; up.uid = "uid-shay-1";
  g_known.clear(); Setup(cind, CIND, "Cind", 0.f, 0.f); Setup(shay, SHAY, "Shay", -5.f, 0.f); cind.iid = &ua; shay.iid = &up;
  Ev e4; e4.Begin(&world, CIND, SHAY, "world1", "trip-1", "t1", true, Ogre::Vector3(500.f, 330.f, 0.f), &cind);
  Check("4a: uid used when present", e4.bound && e4.actorStorage == "uid-cind-1" && e4.partnerStorage == "uid-shay-1" && e4.bindWhy == "ok_uid", e4.bindWhy);
  // identity change mid-run (uid swapped) -> unbound
  now = 3000; e4.Sample(&world, "world1", now, 0); ua.uid = "uid-other";
  e4.Sample(&world, "world1", now + 1, 0);
  Check("4b: identity change mid-run unbinds", !e4.bound);

  // 5. Actor handle cache miss: the actor Character* passed by the caller is enough.
  g_known.clear(); Setup(cind, CIND, "Cind", 0.f, 0.f); Setup(shay, SHAY, "Shay", -5.f, 0.f);
  Character *cindPtr = &cind; g_known.erase(CIND);
  Ev e5; e5.Begin(&world, CIND, SHAY, "world1", "trip-1", "t1", true, Ogre::Vector3(500.f, 330.f, 0.f), cindPtr);
  Check("5a: actor hint binds without the handle cache", e5.bound, e5.bindWhy);
  Ev e5b; e5b.Begin(&world, CIND, SHAY, "world1", "trip-1", "t1", true, Ogre::Vector3(500.f, 330.f, 0.f));
  Check("5b: no hint + cache miss -> actor_unresolved (named)", !e5b.bound && e5b.bindWhy == "actor_unresolved", e5b.bindWhy);

  // 6. Named failures.
  g_known.clear(); Setup(cind, CIND, "Cind", 0.f, 0.f);
  Ev e6; e6.Begin(&world, CIND, SHAY, "world1", "trip-1", "t1", true, Ogre::Vector3(), &cind);
  Check("6a: partner missing -> partner_unresolved", !e6.bound && e6.bindWhy == "partner_unresolved", e6.bindWhy);
  Setup(shay, SHAY, "Shay", -5.f, 0.f);
  Ev e6b; e6b.Begin(&world, CIND, CIND, "world1", "trip-1", "t1", true, Ogre::Vector3(), &cind);
  Check("6b: same actor and partner -> same_actor_partner", !e6b.bound && e6b.bindWhy == "same_actor_partner", e6b.bindWhy);
  Ev e6c; e6c.Begin(&world, CIND, SHAY, "world1", "", "t1", true, Ogre::Vector3(), &cind);
  Check("6c: empty agreement -> world_agreement_or_task_empty", !e6c.bound && e6c.bindWhy == "world_agreement_or_task_empty", e6c.bindWhy);

  // 7. The jump/teleport guard is unchanged (anti-teleport); the diag names it.
  g_known.clear(); Setup(cind, CIND, "Cind", 0.f, 0.f); Setup(shay, SHAY, "Shay", -5.f, 0.f);
  Ev e7; e7.Begin(&world, CIND, SHAY, "world1", "trip-1", "t1", true, Ogre::Vector3(5000.f, 330.f, 0.f), &cind);
  now = 4000; Walk(e7, &world, cind, shay, now, 20, 8.f, 6.f);
  shay.pos.x += 30.f; // partner teleports 30 u in one game second (> 20*1+5)
  ++now; e7.Sample(&world, "world1", now, 0);
  Check("7a: partner jump is a counted break", e7.Diag().find("brk_jump:1") != std::string::npos, e7.Diag());
  Walk(e7, &world, cind, shay, now, 20, 8.f, 6.f); e7.Freeze(true, now);
  Check("7b: 20 s after the jump is too short (needs 30): not qualified, best_span names the longest run",
        e7.frozen.find("\"qualified\":false") != std::string::npos && e7.Diag().find("best_span:20") != std::string::npos, e7.Diag());

  // 8. Separation guard unchanged.
  g_known.clear(); Setup(cind, CIND, "Cind", 0.f, 0.f); Setup(shay, SHAY, "Shay", -5.f, 0.f);
  Ev e8; e8.Begin(&world, CIND, SHAY, "world1", "trip-1", "t1", true, Ogre::Vector3(5000.f, 330.f, 0.f), &cind);
  now = 5000; Walk(e8, &world, cind, shay, now, 60, 8.f, 40.f); e8.Freeze(true, now);
  Check("8a: partner 40 u behind never qualifies", e8.frozen.find("\"qualified\":false") != std::string::npos && e8.Diag().find("brk_sep:0") == std::string::npos, e8.Diag());

  std::printf("\n%d passed, %d failed\n", g_pass, g_fail);
  return g_fail ? 1 : 0;
}
