// NC21 repro of row 13-c: engine reality = Character::getInstanceID() NULL. Compiles against NC20 AND NC21 (8-arg Begin only).
// NC20: prints "RESULT null_uid_bound FAIL bound=0"; NC21: "RESULT null_uid_bound PASS bound=1". Exit 0 only when bound.
#include <cstdio>
#include <map>
#include "ParticipationEvidence.h"
static std::map<unsigned, Character *> g_known;
namespace Stobe { namespace KenshiAi { Character *ResolveCharacter(GameWorld *, unsigned s) { std::map<unsigned, Character *>::iterator i = g_known.find(s); return i == g_known.end() ? 0 : i->second; } } }
int main() {
  GameWorld w; Character cind, shay;
  cind.h.serial = 2529907200u; cind.name = "Cind"; shay.h.serial = 971557632u; shay.name = "Shay"; // iid stays NULL
  g_known[cind.h.serial] = &cind; g_known[shay.h.serial] = &shay;
  Stobe::Participation::Evidence e; e.Begin(&w, cind.h.serial, shay.h.serial, "world1", "trip-1", "order:1", true, Ogre::Vector3(1000.f, 0.f, 0.f));
  std::printf("RESULT null_uid_bound %s bound=%d\n", e.bound ? "PASS" : "FAIL", e.bound ? 1 : 0);
  return e.bound ? 0 : 1;
}
