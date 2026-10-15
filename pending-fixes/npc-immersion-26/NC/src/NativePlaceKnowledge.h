#pragma once
#include <string>
#include <vector>
#include <ogre/OgreVector3.h>
class Character;
struct NativeKnownPlace {
  unsigned int serial, mapSerial;
  std::string name;
  Ogre::Vector3 point;
  NativeKnownPlace() : serial(0), mapSerial(0) {}
};
void CaptureNativeKnownPlaces(Character *actor,std::vector<NativeKnownPlace> &places);
bool ValidateNativeKnownPlace(Character *actor,unsigned int serial,unsigned int mapSerial,const Ogre::Vector3 &point,const std::string &name);
