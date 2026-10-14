#include "ProfilePortrait.h"
#include "Utils.h"
#include <core/Functions.h>
#include <cstring>

#include <kenshi/Appearance.h>
#include <kenshi/Character.h>
#include <kenshi/GameData.h>
#include <kenshi/Inventory.h>
#include <kenshi/Item.h>
#include <kenshi/RaceData.h>
#include <kenshi/RenderToTextureotron.h>
#include <ogre/Ogre.h>
#include <ogre/Compositor/OgreCompositorWorkspace.h>
#include <Windows.h>
#include <stdexcept>
#include <algorithm>
#include <cctype>
#include <set>
#include <sstream>
#include <vector>

namespace {

// These SDK accessors are inline and use a different Entity layout than the
// shipped Ogre DLL (SDK skeleton at 0x2f8; game at 0x300). Resolve the native
// accessors instead of reading SDK fields or baking version-specific offsets.
Ogre::OldSkeletonInstance *NativeSkeleton(Ogre::Entity *entity) {
  typedef Ogre::OldSkeletonInstance *(__fastcall *Accessor)(const Ogre::Entity *);
  static Accessor accessor = reinterpret_cast<Accessor>(GetProcAddress(
      GetModuleHandleA("OgreMain_x64.dll"),
      "?getSkeleton@Entity@Ogre@@QEBAPEAVOldSkeletonInstance@2@XZ"));
  if (!accessor)
    throw std::runtime_error("Ogre Entity skeleton accessor unavailable");
  return entity ? accessor(entity) : nullptr;
}

Ogre::SceneNode *NativeParentNode(Ogre::Entity *entity) {
  typedef Ogre::SceneNode *(__fastcall *Accessor)(const Ogre::MovableObject *);
  static Accessor accessor = reinterpret_cast<Accessor>(GetProcAddress(
      GetModuleHandleA("OgreMain_x64.dll"),
      "?getParentSceneNode@MovableObject@Ogre@@QEBAPEAVSceneNode@2@XZ"));
  if (!accessor)
    throw std::runtime_error("Ogre parent scene node accessor unavailable");
  return entity ? accessor(entity) : nullptr;
}

// Both mutations happen before the private workspace starts culling. The old
// SceneManager preFindVisibleObjects callback is too late in this Ogre build:
// it runs in phase two, after phase-one visibility has already been cached.
unsigned char ExcludePrivateHeadgear(Ogre::Entity *entity) {
  typedef void (__fastcall *SetGroup)(Ogre::Entity *, unsigned char);
  typedef unsigned char (__fastcall *GetGroup)(const Ogre::MovableObject *);
  typedef void (__fastcall *SetVisible)(Ogre::MovableObject *, bool);
  typedef bool (__fastcall *IsVisible)(const Ogre::MovableObject *);
  HMODULE ogre = GetModuleHandleA("OgreMain_x64.dll");
  static SetGroup set = reinterpret_cast<SetGroup>(GetProcAddress(ogre,
      "?setRenderQueueGroup@Entity@Ogre@@UEAAXE@Z"));
  static GetGroup get = reinterpret_cast<GetGroup>(GetProcAddress(ogre,
      "?getRenderQueueGroup@MovableObject@Ogre@@QEBAEXZ"));
  static SetVisible setVisible = reinterpret_cast<SetVisible>(GetProcAddress(ogre,
      "?setVisible@MovableObject@Ogre@@QEAAX_N@Z"));
  static IsVisible isVisible = reinterpret_cast<IsVisible>(GetProcAddress(ogre,
      "?isVisible@MovableObject@Ogre@@QEBA_NXZ"));
  if (!set || !get || !setVisible || !isVisible)
    throw std::runtime_error("Ogre render queue accessors unavailable");
  setVisible(entity, false);
  if (isVisible(entity))
    throw std::runtime_error("private headgear still visible before culling");
  set(entity, 254);
  return get(entity);
}

std::string MeshKey(const std::string &name) {
  std::string key = name;
  std::replace(key.begin(), key.end(), '\\', '/');
  const size_t slash = key.find_last_of('/');
  if (slash != std::string::npos)
    key.erase(0, slash + 1);
  for (size_t i = 0; i < key.size(); ++i)
    key[i] = static_cast<char>(std::tolower(static_cast<unsigned char>(key[i])));
  return key;
}

bool AddHeadgearMeshes(Inventory *inventory, AttachSlot slot,
                      std::set<std::string> &meshes, std::set<GameData *> &equipment, std::string &reason) {
  if (!inventory)
    return true;
  InventorySection *section = inventory->getSectionOfType(slot);
  if (!section)
    return true;
  const auto &items = section->getItems();
  for (size_t i = 0; i < items.size(); ++i) {
    Item *item = items[i].item;
    if (!item)
      continue;
    GameData *data = item->getGameData();
    if (data) {
      equipment.insert(data);
      for (auto it = data->filesdata.begin(); it != data->filesdata.end(); ++it) {
        const std::string key = MeshKey(it->second);
        if (key.size() >= 5 && key.substr(key.size() - 5) == ".mesh") {
          meshes.insert(key);
        }
      }
    }
    // A race/deformation-specific resource may not appear in these filenames.
    // Resolve its live attachment below, then validate an actual private match.
    if (!data) {
      reason = "profile_headgear_data_unavailable";
      return false;
    }
  }
  return true;
}

// The SDK leaves AttachedEntity incomplete. Native AppearanceBase::createEntity
// (Steam 1.0.65 RVA 0x536c00) reads equipment GameData at +0x78 and stores its
// Ogre entity at +0x80. Its optional +0xc0 filename override can differ from
// GameData metadata, so read the actual live resource. Never dereference the
// candidate until it is confirmed
// among the live body's node attachments. These are READS only: hiding happens
// later on fresh entities owned by RenderToTextureotron.
void AddLiveHeadgearMeshes(AppearanceBase *appearance, Ogre::Entity *body,
                          const std::set<GameData *> &equipment,
                          std::set<std::string> &meshes) {
  Ogre::SceneNode *node = NativeParentNode(body);
  if (!node || equipment.empty())
    return;
  std::set<Ogre::MovableObject *> attached;
  typedef size_t (__fastcall *Count)(const Ogre::SceneNode *);
  typedef Ogre::MovableObject *(__fastcall *Get)(Ogre::SceneNode *, size_t);
  HMODULE ogre = GetModuleHandleA("OgreMain_x64.dll");
  Count count = reinterpret_cast<Count>(GetProcAddress(ogre,
      "?numAttachedObjects@SceneNode@Ogre@@QEBA_KXZ"));
  Get get = reinterpret_cast<Get>(GetProcAddress(ogre,
      "?getAttachedObject@SceneNode@Ogre@@QEAAPEAVMovableObject@2@_K@Z"));
  if (!count || !get)
    throw std::runtime_error("Ogre scene attachment accessors unavailable");
  const size_t attachedCount = count(node);
  for (size_t i = 0; i < attachedCount; ++i)
    attached.insert(get(node, i));
  for (auto it = appearance->attachedObjects.begin();
       it != appearance->attachedObjects.end(); ++it) {
    if (!it->second)
      continue;
    const char *record = reinterpret_cast<const char *>(it->second);
    GameData *data = nullptr;
    Ogre::Entity *entity = nullptr;
    std::memcpy(&data, record + 0x78, sizeof(data));
    if (equipment.find(data) == equipment.end())
      continue;
    std::memcpy(&entity, record + 0x80, sizeof(entity));
    if (entity && entity != body && attached.find(entity) != attached.end())
      meshes.insert(MeshKey(entity->getMesh()->getName()));
  }
}

// Kenshi renderCharacter creates fresh entities in the renderer's own scene,
// copies the character's body proportions/materials, and applies a portrait pose.
// It then randomizes camera yaw/pitch from portraitSerial. Adjustment runs after
// that setup but BEFORE the workspace starts any nodes, passes or visibility
// culling, on this private scene ONLY.
// No equipment, live skeleton, live camera, or vanilla atlas is modified.
class ProfileSceneListener {
public:
  ProfileSceneListener(RenderToTextureotron &renderer, const std::string &body,
                       const std::set<std::string> &headgear, size_t equipmentCount,
                       const Ogre::Vector3 &portraitOffset)
      : applied(false), excluded(0), renderer_(renderer), body_(body), headgear_(headgear),
        equipmentCount_(equipmentCount), portraitOffset_(portraitOffset) {}

  ~ProfileSceneListener() {
    for (size_t i = 0; i < privateMaterials_.size(); ++i) {
      try { Ogre::MaterialManager::getSingleton().remove(privateMaterials_[i]); }
      catch (...) {}
    }
  }

  void restorePrivateHead(Ogre::Entity *body) {
    if (!body) return;
    typedef bool (__fastcall *HasProgram)(const Ogre::Pass *);
    static HasProgram hasProgram = reinterpret_cast<HasProgram>(GetProcAddress(
        GetModuleHandleA("OgreMain_x64.dll"), "?hasVertexProgram@Pass@Ogre@@QEBA_NXZ"));
    if (!hasProgram) throw std::runtime_error("Ogre pass program accessor unavailable");
    static unsigned long materialSequence = 0;
    for (size_t i = 0; i < body->getNumSubEntities(); ++i) {
      Ogre::SubEntity *part = body->getSubEntity(i);
      const Ogre::MaterialPtr original = part->getMaterial();
      if (original.isNull()) continue;
      std::ostringstream name;
      name << "StobeProfileHeadMaterial_" << ++materialSequence;
      Ogre::MaterialPtr copy = original->clone(name.str());
      privateMaterials_.push_back(copy->getHandle());
      for (unsigned short t = 0; t < copy->getNumTechniques(); ++t) {
        Ogre::Technique *technique = copy->getTechnique(t);
        for (unsigned short p = 0; p < technique->getNumPasses(); ++p) {
          Ogre::Pass *pass = technique->getPass(p);
          if (!hasProgram(pass)) continue;
          Ogre::GpuProgramParametersSharedPtr params = pass->getVertexProgramParameters();
          const Ogre::GpuConstantDefinition *def = params->_findNamedConstantDefinition("hiddenMask", false);
          if (!def) continue;
          int mask = 0;
          params->_readRawConstants(def->physicalIndex, 1, &mask);
          // KenshiFP uses bit 9 for the head on its painted race part maps.
          // Preserve clothing and missing-limb masks. Only this private copy
          // changes; the live character's first-person head stays hidden.
          params->setNamedConstant("hiddenMask", mask & ~0x200);
        }
      }
      part->setMaterial(copy);
    }
  }

  void beforeWorkspaceUpdate(Ogre::SceneManager *source) {
    if (applied || source != renderer_.sceneManager ||
        !renderer_.camera)
      return;
    const char *step = "enumerate_entities";
    try {
      excluded = 0;
      observed.clear();
      excludedMeshes.clear();
      Ogre::Entity *body = nullptr;
      Ogre::SceneManager::MovableObjectIterator it =
          source->getMovableObjectIterator("Entity");
      while (it.hasMoreElements()) {
        Ogre::Entity *entity = static_cast<Ogre::Entity *>(it.getNext());
        if (!entity)
          continue;
        step = "entity_mesh";
        const std::string mesh = MeshKey(entity->getMesh()->getName());
        observed.insert(mesh);
        if (mesh != body_ && headgear_.find(mesh) != headgear_.end()) {
          step = "hide_headgear_before_cull";
          const unsigned char queue = ExcludePrivateHeadgear(entity);
          if (queue != 254) {
            failure = "profile_headgear_queue_exclusion_failed";
            return;
          }
          excludedMeshes.insert(mesh + ":visible0:queue254");
          ++excluded;
        }
        if (mesh == body_)
          body = entity;
      }
      // Native portrait setup may omit an equipped attachment (distance/LOD or
      // attachment readiness). Absence is already the desired result; requiring
      // one clone per inventory item incorrectly falls back to the angled,
      // helmet-wearing atlas even when this private scene is bareheaded.
      step = "restore_private_head_mask";
      restorePrivateHead(body);
      step = "private_skeleton";
      Ogre::OldSkeletonInstance *skeleton = NativeSkeleton(body);
      Ogre::SceneNode *node = NativeParentNode(body);
      if (!skeleton || !node || !skeleton->hasBone("Bip01 Head")) {
        failure = "profile_private_head_unavailable";
        return;
      }
      step = "head_transform";
      Ogre::OldBone *head = skeleton->getBone("Bip01 Head");
      const Ogre::Vector3 target =
          node->_getFullTransform() * head->_getDerivedPosition() + portraitOffset_;
      step = "camera_position";
      Ogre::Camera *camera = renderer_.camera;
      const float distance = (camera->getPosition() - target).length();
      if (!(distance > 0.01f && distance < 10000.0f)) {
        failure = "profile_camera_distance_invalid";
        return;
      }
      // Kenshi's neutral humanoid model faces +Z, with +Y up. Retain the
      // renderer's race-scaled distance; remove its serial-dependent orbit.
      const Ogre::Quaternion orientation = node->_getDerivedOrientation();
      camera->setFixedYawAxis(true, orientation * Ogre::Vector3::UNIT_Y);
      camera->setPosition(target + (orientation * Ogre::Vector3::UNIT_Z) * distance);
      camera->lookAt(target);
      // renderCharacter sets this shared RTT shader matrix before starting its
      // render. Refresh it after changing its private camera. Despite the name,
      // native code supplies getViewMatrix(true), not its mathematical inverse.
      step = "shader_view_matrix";
      Ogre::GpuProgramManager::getSingleton()
          .getSharedParameters("SharedRTTViewMatrix")
          ->setNamedConstant("inverseView", camera->getViewMatrix(true));
      applied = true;
    } catch (const Ogre::Exception &error) {
      failure = std::string("profile_scene_") + step + ": " + error.getFullDescription();
    } catch (const std::exception &error) {
      failure = std::string("profile_scene_") + step + ": " + error.what();
    } catch (...) {
      failure = std::string("profile_scene_") + step + ": native_fault";
    }
  }

  bool applied;
  size_t excluded;
  std::set<std::string> observed;
  std::set<std::string> excludedMeshes;
  std::string failure;

private:
  RenderToTextureotron &renderer_;
  std::string body_;
  std::set<std::string> headgear_;
  size_t equipmentCount_;
  Ogre::Vector3 portraitOffset_;
  std::vector<Ogre::ResourceHandle> privateMaterials_;
};

// Kenshi's portrait workspace is created and updated inside renderCharacter,
// so it cannot be configured by the caller ahead of time. Intercept the native
// exported workspace entry instead. Its first instructions precede even the
// workspacePreUpdate listener (Ogre 1.0.65 RVA 3C7700/3C7746), hence all culling.
// A thread-local scope and native scene identity keep other workspaces untouched;
// their existing listeners and the original update always run normally.
typedef void (__fastcall *WorkspaceUpdate)(Ogre::CompositorWorkspace *);
typedef Ogre::SceneManager *(__fastcall *WorkspaceScene)(const Ogre::CompositorWorkspace *);
WorkspaceUpdate originalWorkspaceUpdate = nullptr;
WorkspaceScene nativeWorkspaceScene = nullptr;
__declspec(thread) ProfileSceneListener *activePortraitAdjustment = nullptr;

void __fastcall ProfileWorkspaceUpdate(Ogre::CompositorWorkspace *workspace) {
  ProfileSceneListener *active = activePortraitAdjustment;
  if (active && nativeWorkspaceScene) {
    try { active->beforeWorkspaceUpdate(nativeWorkspaceScene(workspace)); }
    catch (...) { active->failure = "profile_workspace_pre_cull_native_fault"; }
  }
  // Installed only when the detour API supplies a valid original trampoline.
  if (originalWorkspaceUpdate) originalWorkspaceUpdate(workspace);
}

bool EnsureWorkspaceHook(std::string &reason) {
  static bool attempted = false;
  if (originalWorkspaceUpdate) return true;
  if (attempted) { reason = "profile_workspace_hook_unavailable"; return false; }
  attempted = true;
  HMODULE ogre=GetModuleHandleA("OgreMain_x64.dll");
  void *entry=reinterpret_cast<void *>(GetProcAddress(ogre,
      "?_update@CompositorWorkspace@Ogre@@QEAAXXZ"));
  nativeWorkspaceScene=reinterpret_cast<WorkspaceScene>(GetProcAddress(ogre,
      "?getSceneManager@CompositorWorkspace@Ogre@@QEBAPEAVSceneManager@2@XZ"));
  if (!entry || !nativeWorkspaceScene || KenshiLib::AddHook(entry,
      reinterpret_cast<void *>(&ProfileWorkspaceUpdate),
      reinterpret_cast<void **>(&originalWorkspaceUpdate)) != KenshiLib::SUCCESS ||
      !originalWorkspaceUpdate) {
    reason = "profile_workspace_hook_unavailable";
    Log("PROFILE_PORTRAIT: early workspace hook installation failed");
    return false;
  }
  Log("PROFILE_PORTRAIT: early workspace hook installed (private scene only, before culling)");
  return true;
}

class ScopedPortraitAdjustment {
public:
  explicit ScopedPortraitAdjustment(ProfileSceneListener *listener)
      : previous_(activePortraitAdjustment) { activePortraitAdjustment=listener; }
  ~ScopedPortraitAdjustment() { activePortraitAdjustment=previous_; }
private:
  ProfileSceneListener *previous_;
};

void ReleaseTexture(Ogre::TexturePtr &texture) {
  if (texture.isNull())
    return;
  Ogre::TextureManager::getSingleton().remove(texture->getHandle());
  texture.setNull();
}

} // namespace

namespace Stobe {

ProfilePortrait::ProfilePortrait() {}
ProfilePortrait::~ProfilePortrait() { reset(); }

void ProfilePortrait::reset() {
  try { ReleaseTexture(texture_); } catch (...) { texture_.setNull(); }
}

bool ProfilePortrait::render(Character *npc, std::string &reason) {
  reason.clear();
  Ogre::TexturePtr candidate;
  try {
    if (!npc || !npc->isHuman()) {
      reason = "profile_not_humanoid";
      return false;
    }
    if (!EnsureWorkspaceHook(reason)) return false;
    AppearanceBase *appearance = npc->getAppearance();
    Ogre::Entity *body = appearance ? appearance->getBody() : nullptr;
    if (!body || !NativeSkeleton(body)) {
      reason = "profile_body_not_ready";
      return false;
    }
    std::set<std::string> headgear;
    std::set<GameData *> headgearData;
    Inventory *inventory = npc->getInventory();
    if (!AddHeadgearMeshes(inventory, ATTACH_HAT, headgear, headgearData, reason) ||
        !AddHeadgearMeshes(inventory, ATTACH_EYES, headgear, headgearData, reason))
      return false;
    AddLiveHeadgearMeshes(appearance, body, headgearData, headgear);
    if (!headgearData.empty() && headgear.empty()) {
      reason = "profile_headgear_mesh_unresolved";
      return false;
    }

    RenderToTextureotron renderer;
    renderer.setupSceneManager();
    if (!renderer.sceneManager) {
      reason = "profile_scene_unavailable";
      return false;
    }
    static unsigned long sequence = 0;
    std::ostringstream name;
    name << "StobeProfilePortrait_" << ++sequence;
    iVector2 size;
    // RTT_Portrait uses a fixed 128x128 chroma-interleaved GBuffer. Its resolve
    // shader derives checkerboard parity and neighboring samples from the
    // output viewport; a 256 output corrupts colour reconstruction (green cast).
    // Scale the fully resolved image in the UI, never this shader's output.
    size.x = 128;
    size.y = 128;
    candidate = renderer.createTexture(name.str(), size, false);
    if (candidate.isNull()) {
      reason = "profile_texture_unavailable";
      return false;
    }
    // Preserve the game's race-specific framing, including its age multiplier.
    Ogre::Vector3 portraitOffset = Ogre::Vector3::ZERO;
    RaceData *race = npc->getRace();
    if (race && race->data) {
      const char *keys[] = {"portrait offset x", "portrait offset y", "portrait offset z"};
      for (size_t i = 0; i < 3; ++i) {
        auto value = race->data->fdata.find(keys[i]);
        if (value != race->data->fdata.end())
          portraitOffset[i] = value->second;
      }
      portraitOffset *= npc->getAge();
    }
    ProfileSceneListener listener(renderer, MeshKey(body->getMesh()->getName()),
                                  headgear, headgearData.size(), portraitOffset);
    {
      ScopedPortraitAdjustment scope(&listener);
      renderer.renderCharacter(npc, candidate, size, Ogre::TRect<float>(0, 0, 1, 1));
    }
    std::ostringstream diagnostic;
    diagnostic << "PROFILE_PORTRAIT: npc=" << npc->getName()
               << " equipment=" << headgearData.size()
               << " phase=workspace_pre_cull hidden_before_cull=" << listener.excluded << " expected=";
    for (auto it = headgear.begin(); it != headgear.end(); ++it)
      diagnostic << *it << ";";
    diagnostic << " excluded_meshes=";
    for (auto it = listener.excludedMeshes.begin(); it != listener.excludedMeshes.end(); ++it)
      diagnostic << *it << ";";
    diagnostic << " observed=";
    for (auto it = listener.observed.begin(); it != listener.observed.end(); ++it)
      diagnostic << *it << ";";
    diagnostic << " applied=" << (listener.applied ? 1 : 0);
    Log(diagnostic.str());
    if (!listener.applied) {
      reason = listener.failure.empty() ? "profile_workspace_pre_cull_callback_missing" : listener.failure;
      ReleaseTexture(candidate);
      return false;
    }
    reset();
    texture_ = candidate;
    return true;
  } catch (...) {
    reason = "profile_render_exception";
    try { ReleaseTexture(candidate); } catch (...) {}
    return false;
  }
}

} // namespace Stobe
