#pragma once
// g++ stub for ParticipationEvidence.h (NC21 sim test). Mirrors only what the header uses.
#include <string>
#include <cmath>
struct hand { unsigned serial, index, type, container, containerSerial; hand():serial(0),index(0),type(0),container(0),containerSerial(0){} };
namespace Ogre { struct Vector3 { float x, y, z; Vector3():x(0),y(0),z(0){} Vector3(float a,float b,float c):x(a),y(b),z(c){} }; }
inline int _finite(double v) { return std::isfinite(v) ? 1 : 0; }
class GameWorld {};
class InstanceID { public: std::string uid; };
class Character {
public:
  hand h; std::string name; InstanceID *iid; Ogre::Vector3 pos; bool dead, ko;
  Character():iid(0),dead(false),ko(false){}
  hand getHandle() { return h; }
  InstanceID *getInstanceID() { return iid; }
  std::string getName() { return name; }
  Ogre::Vector3 getPosition() { return pos; }
  bool isDead() { return dead; }
  bool isUnconcious() { return ko; }
};
namespace Stobe { namespace KenshiAi { Character *ResolveCharacter(GameWorld *w, unsigned serial); } }
