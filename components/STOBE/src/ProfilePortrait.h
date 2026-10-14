#pragma once

#include <ogre/OgreTexture.h>
#include <string>

class Character;

namespace Stobe {

// Owns a dedicated profile texture, never a region in the game's portrait atlas.
// Render and destruction must run on the game thread while Ogre is available.
class ProfilePortrait {
public:
  ProfilePortrait();
  ~ProfilePortrait();
  bool render(Character *npc, std::string &reason);
  void reset();
  Ogre::Texture *texture() const { return texture_.getPointer(); }

private:
  ProfilePortrait(const ProfilePortrait &);
  ProfilePortrait &operator=(const ProfilePortrait &);
  Ogre::TexturePtr texture_;
};

} // namespace Stobe
