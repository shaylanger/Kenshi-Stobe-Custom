#include "NpcReferralPeople.h"
#include "Utils.h"
#include <kenshi/Character.h>
#include <kenshi/GameWorld.h>
#include <kenshi/SensoryData.h>
#include <kenshi/util/UtilityT.h>
#include <algorithm>
#include <vector>
#include <sstream>
#include <locale>
#include <ctime>
#include <float.h>

namespace Stobe { namespace NpcReferralPeople {
namespace {
struct Person { unsigned int serial; std::string name, title; float distance;
  bool operator<(const Person& other) const { return distance < other.distance; } };
std::string Quote(const std::string& value) { return "\""+EscapeJSON(value)+"\""; }
}
std::string CaptureJson(GameWorld* world, Character* actor) {
  if (!world || !actor) return "{\"observed\":false}";
  std::vector<Person> people;
  try {
    SensoryData* senses=actor->getSensoryData();
    if (!senses) return "{\"observed\":false}";
    const Ogre::Vector3 origin=actor->getPosition();
    lektor<RootObject*> nearby;
    world->getObjectsWithinSphere(nearby,origin,600.0f,CHARACTER,96,(RootObject*)actor);
    for (unsigned int i=0; i<nearby.size(); ++i) {
      Character* other=(Character*)nearby.stuff[i];
      if (!other || other==actor || other->isAnimal() || !senses->canISeeThisGuy(other)) continue;
      Person p; p.serial=other->getHandle().serial; p.name=other->getName();
      if (!p.serial || p.name.empty() || p.name.size()>160) continue;
      const size_t open=p.name.find('['), close=p.name.find(']',open==std::string::npos?0:open+1);
      if (open==std::string::npos || close==std::string::npos || close<=open+1 || close-open>61) continue;
      p.title=p.name.substr(open+1,close-open-1);
      p.distance=(other->getPosition()-origin).length();
      if (!_finite(p.distance) || p.distance>600.0f) continue;
      people.push_back(p);
    }
    std::sort(people.begin(),people.end());
    std::ostringstream out; out.imbue(std::locale::classic());
    out << "{\"version\":1,\"observed\":true,\"actor_serial\":" << actor->getHandle().serial
        << ",\"observed_unix\":" << std::time(NULL) << ",\"game_ts\":"
        << world->getTimeStamp_inGameHours().getTotalSeconds() << ",\"people\":[";
    for (size_t i=0; i<people.size() && i<6; ++i) {
      if (i) out << ',';
      out << "{\"target_serial\":" << people[i].serial << ",\"name\":" << Quote(people[i].name)
          << ",\"public_title\":" << Quote(people[i].title) << ",\"observation\":\"visible\"}";
    }
    return out.str()+"]}";
  } catch (...) { return "{\"observed\":false}"; }
}
} }
