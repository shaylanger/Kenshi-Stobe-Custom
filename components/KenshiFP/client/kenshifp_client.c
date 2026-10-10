/*
 * KenshiFP client DLL — first-person mode for Kenshi 1.0.68 "Newland" x64.
 *
 * M1 (this file): CAMERA LOCK. Builds on the verified stage-0 read path. While
 * FP mode is ON (toggle: F), each frame re-asserts CameraClass::followObject on
 * the selected player character so the camera tracks it (a chase-cam lock);
 * on toggle OFF, calls stopFollowing once to release. Everything else is still
 * read-only observation, logged at 1 Hz.
 *
 * Verified stage-0 anchors it stands on (re/NOTES.md):
 *   - per-frame MinHook trampoline on GameWorld::mainLoop_GPUSensitiveStuff,
 *   - CameraClass instance at *(base + 0x2133310) (camera+0x68 == scene cam),
 *   - player char via GameWorld->player->playerCharacters[0] + getPosition,
 *   - WASD/toggle via Win32 GetAsyncKeyState (works under Proton).
 * New M1 writes: followObject (0x6ae520) / stopFollowing (0x6ae560), both tiny
 * leaf setters (no allocation) — safe to call from the main-thread hook.
 *
 * Loaded via Plugins_x64.cfg (Plugin=KenshiFP_x64), no RE_Kenshi.
 * All offsets: see ../re/NOTES.md.
 */
#include <windows.h>
#include "KenshiAutomationHarness.h" /* test commands, if the harness is installed */
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <math.h>
#include <setjmp.h>
#define DIRECTINPUT_VERSION 0x0800
#include <dinput.h>
#ifndef KFP_RE_PLUGIN
#include "MinHook.h"    /* standalone edition only; the RE edition hooks via
                         * KenshiLib::AddHook so it ships no inline-hook code */
#endif

/* ---- per-frame hook (proven in KenshiMP, same binary) ---- */
#define RVA_MAINLOOP      0x788a00u  /* GameWorld::mainLoop_GPUSensitiveStuff(GameWorld*, float) */
#define GW_FRAMESPEED_OFF 0x700      /* GameWorld::frameSpeedMult (float) */
#define GW_PLAYER         0x580      /* GameWorld::player (PlayerInterface*) */
#define PLAYER_CURFLOOR   0x1E4      /* PlayerInterface::currentFloor -- drives interior floor culling */
#define PLAYER_TRACKEDFLOOR 0x290    /* PlayerInterface::trackedCharacterFloor -- game's selected-char floor */

/* ---- camera (M0, re/NOTES.md — confirmed via the CameraClass ctor) ----
 * The global at RVA 0x2133300 is the camera/scene holder struct; the engine
 * fills it in FUN_14086cf90(&holder):
 *   holder+0x08 -> scene/render context (DAT_142133308; its +0x58 is the
 *                  Ogre::Camera used for getViewMatrix each frame),
 *   holder+0x10 -> the CameraClass* (Kenshi's camera brain).
 * So the CameraClass INSTANCE pointer lives at RVA 0x2133310. The ctor
 * (FUN_1406afbf0, RVA 0x6afbf0) proved the header field layout is valid for
 * 1.0.68: camera(Ogre::Camera*)+0x68, center(SceneNode*)+0x58, node+0x70,
 * objectCurrentlyFollowing(hand)+0x28. */
#define RVA_CAM_INSTANCE  0x2133310u /* *(CameraClass**)(base + this) */
/* InputHandler is statically located (its pan bools at +0xDB..0xDE line up with
 * the camera update's DAT_14213344b..e -> base RVA 0x2133370). controlEnabled
 * (+0xD0, RVA 0x2133440) is FALSE while a dialogue/menu grabs input -> release
 * the FP cursor so the player can click UI. */
#define RVA_INPUT_CONTROLENABLED 0x2133440u
#define RVA_INPUT_MWHEEL         0x2133488u /* InputHandler.mWheel (+0x118); OIS wheel delta */
#define RVA_SCENE_CTX     0x2133308u /* scene/render context; +0x58 Ogre::Camera* */
#define SCENE_OGRE_CAMERA 0x58
/* CameraClass field offsets (KenshiLib header, ctor-confirmed layout): */
#define CC_YAW            0x18
#define CC_PITCH          0x1C
#define CC_FOLLOW_HAND    0x28       /* hand objectCurrentlyFollowing */
#define CC_FOLLOW_IDS     0x30       /* the hand's 5 id dwords (what followObject writes) */
#define CC_CENTER         0x58       /* Ogre::SceneNode* center */
#define CC_CAMERA         0x68       /* Ogre::Camera* */
#define CC_NODE           0x70       /* Ogre::SceneNode* */
#define CC_ALTITUDE       0x60
#define CC_FREECAM        0xBF

/* CameraClass methods (M1 writes; RVAs derived in ../re/NOTES.md).
 *   followObject(this /RCX/, const hand* object /RDX/): copies object's 5 id
 *     dwords (object+0x8..+0x18) into this->objectCurrentlyFollowing (+0x30..).
 *   stopFollowing(this /RCX/): resets those ids to the null-hand constants. */
#define RVA_FOLLOW_OBJECT 0x6ae520u
#define RVA_STOP_FOLLOW   0x6ae560u
/* Character::handle (a `hand`) at Character+0x58; ids at +0x60.. (=hand+0x8). */
#define CHAR_HANDLE       0x58

/* ---- M3 WASD movement ----
 * Character->movement (CharMovement*) is at +0x640. CharMovement::setDestination
 * (const Vec3&, UpdatePriority, bool) VERIFIED at RVA 0x661270 (vt[18]/+0x90 of
 * the live CharMovement vtable; Ghidra typed arg2 as Vector3*). UpdatePriority:
 * LOW=0, MED=1, HIGH=2. We breadcrumb a point ahead in the camera heading while
 * WASD is held (~10 Hz), and order the current position on release (halt).
 * NOTE: KenshiCoop found player chars can ignore a bare CharMovement dest; if so
 * this won't move them and we'll switch to the Character-level order path. */
#define CHAR_MOVEMENT      0x640   /* Character::movement (CharMovement*) */
#define CHAR_ANIM          0x448   /* Character::animation (AnimationClass*) */
#define ANIM_APPEARANCE    0xE8    /* AnimationClass::appearance (AppearanceHuman*) */
#define APP_MATERIAL       0x128   /* AppearanceBase::bodyMaterial (SharedPtr<Material>; +0 = Material*) */
/* ---- worn-item map on AppearanceHuman (head-covering gear hide) --------------------
 * Layout lifted from the vanilla "a hat hides the hair/beard" routine (1.0.65
 * FUN_140537200, decompiled), which walks this exact container. It is a custom
 * Ogre-allocator hash map holding ONE intrusive node list; the head of that list lives
 * in the sentinel bucket slot one past the end of the bucket array: buckets[bucketCount]. */
#define APP_ITEM_NBUCK     0x28    /* bucket count (also the index of the list-head slot) */
#define APP_ITEM_COUNT     0x30    /* element count; 0 = empty, the list head is not valid */
#define APP_ITEM_BUCKETS   0x48    /* void** bucket array */
#define APP_HIDE_HEADWEAR  0x181   /* vanilla "headwear is hidden" flag (FUN_140537200 writes it) */
#define MAPN_NEXT          0x00    /* node: next pointer */
#define MAPN_KEY           0x10    /* node: key std::string (MSVC: inline buf16 | heap ptr) */
#define MAPN_KEYLEN        0x20    /* node: key size */
#define MAPN_KEYCAP        0x28    /* node: key capacity (>15 => the key data is a pointer) */
#define MAPN_VALUE         0x38    /* node: value (Item* here, int in the GameData int-map) */
#define ITEM_GAMEDATA      0x78    /* Item::gameData (GameData*) */
#define ITEM_MESH          0x80    /* Item::mesh (Ogre::MovableObject*); NULL = the game destroyed it */
#define GD_INTMAP          0x178   /* GameData int-field map (same node layout, int value) */
/* AttachSlot (the game's own fcs_enums.def) -- these are the BIT INDICES of the
 * headgear_slots ini bitmask: WEAPON 0, BACK 1, HAIR 2, HAT 3, EYES 4, BODY 5, LEGS 6,
 * NONE 7, SHIRT 8, BOOTS 9, GLOVES 10, NECK 11, BACKPACK 12, BEARD 13, BELT 14. */
#define ATTACH_WEAPON      0
#define ATTACH_BACK        1
#define ATTACH_HAIR        2
#define ATTACH_HAT         3
#define ATTACH_EYES        4
#define ATTACH_BODY        5
#define ATTACH_LEGS        6
#define ATTACH_SHIRT       8
#define ATTACH_BOOTS       9
#define ATTACH_GLOVES      10
#define ATTACH_NECK        11
#define ATTACH_BACKPACK    12
#define ATTACH_BEARD       13
#define ATTACH_BELT        14
#define HEADGEAR_SLOTS_DEF ((1u << ATTACH_HAIR) | (1u << ATTACH_HAT) \
                          | (1u << ATTACH_EYES) | (1u << ATTACH_BEARD))  /* 0x201C */
#define CHAR_WEAPON_IN_HANDS 0x6D8 /* CharacterHuman::weaponInHands (Weapon*); non-null = drawn */
#define CHAR_MOVEMENT     0x640    /* Character::movement (CharMovement*) */
#define CHAR_STATS        0x450    /* Character::stats (CharStats*) */
#define CHAR_STEALTH_MODE   0xD4   /* Character::stealthMode (bool) */
#define CHAR_STEALTH_UNSEEN 0xE8   /* Character::stealthUnseen (YesNoMaybe.key: 0=NO/seen, 1=YES/hidden, 2=MAYBE) */
#define CHAR_STEALTH_ARROWS 0x230  /* Character::stealthMarkerArrows (AttachedArrowManager; ents lektor {begin,end,cap} at +0x0) */
#define CHAR_RANGEDCOMBAT 0x2F0    /* Character::rangedCombat (RangedCombatClass*) */
#define RC_COMBATMODE     0x36     /* RangedCombatClass::combatMode (bool) */
#define ANIM_SKELETON      0xB8    /* AnimationClass::skeleton (Ogre::OldSkeletonInstance*) */
#define ANIM_RAGDOLL_MASK  0x2f8   /* AnimationClass ragdoll-active-parts bitmask (u32); != 0 = down */
#define GW_FRAMESPEED      0x700   /* GameWorld::frameSpeedMult (float); 1.0 = 1x */
#define RVA_CHARMOVE_SETDEST 0x661270u   /* CharMovement::setDestination (raw move; no navmesh) */
#define RVA_CHAR_SETDEST     0x5c84e0u   /* NOT setDestination: teleport+facing placement
                                          * (3rd arg = Ogre::Quaternion* facing). Unused. */
/* NB: the player move order (playerMoveOrderDefault) is called via the Character
 * VTABLE slot +0x318 (see try_move_to_pos) -- NOT a hard-coded RVA -- so there is
 * deliberately no RVA_MOVE_TO_POS. (The old 0x5d22b0 was never that function.) */
#define CHAR_TASKHOLDER      0x648       /* Character+0x648 -> task holder */
#define TASK_CUR             0x68        /* holder+0x68 = current task */
#define TASK_DESC            0x70        /* task+0x70 = descriptor */
#define TASKDESC_TYPE        0x44        /* descriptor+0x44 = order type id */
#define TASK_MOVE_ID         0x1d        /* Task_Move (player walk order) */
/* Authoritative from KenshiLib Character.h (member/vtable offsets are layout-
 * stable across point releases, unlike RVAs). */
#define CHAR_PRONE_STATE     0xE0        /* _currentProneState (ProneState 0..4) */
#define CHAR_WANTS_GETUP     0xEC        /* playerWantsMeToGetUp (bool) -- the game's OWN get-up req */
#define CHAR_IN_SOMETHING    0x2F8       /* inSomething (UseStuffState: 0 nothing/1 bed/2 prison) */
#define CHAR_VT_PLAYERMOVE   (0x318/8)   /* vtable: playerMoveOrderDefault(Building*,RootObject*,Vector3&) */
#define PS_NORMAL 0                      /* ProneState: 0 normal, 2 crippled, 3 playing-dead */
#define PS_KO 4                          /* ...4 = KO, truly out (cannot get up until recovered) */
/* --- UI-panel-open detection (decompile-verified 1.0.68). ForgottenGUI is a
 * static INSTANCE at 0x21337b0; other window singletons are static pointers.
 * Everything below is a pure read or a tiny getVisible (widget flag read). --- */
#define RVA_GUI_INV_COUNT   0x2133870u  /* gui+0xC0: inventoryWindowsOpen map SIZE --
                                         * covers inventory, loot, trade, animal,
                                         * research inventories */
#define RVA_GUI_STATS_BEG   0x2133978u  /* gui+0x1C8: stats-windows vector begin */
#define RVA_GUI_STATS_END   0x2133980u  /* gui+0x1D0: vector end */
#define RVA_GUI_WINSTACK    0x21339c0u  /* gui+0x210: open-window stack count */
#define RVA_GUI_DLGWND      0x21337d0u  /* gui+0x20: DialogueWindow* */
#define RVA_DLG_GETVIS      0x721ec0u
#define RVA_ESCMENU_PTR     0x212f4b8u  /* EscMenu singleton */
#define RVA_ESC_GETVIS      0x913040u
#define RVA_OVERVIEW_PTR    0x212f4f8u  /* OverviewWindow: map/factions/squads/etc */
#define RVA_OVW_GETVIS      0x48bb70u
#define RVA_OPTIONS_PTR     0x212f090u  /* OptionsWindow */
#define RVA_OPT_GETVIS      0x3e7240u
#define RVA_PROSPECT_PTR    0x212ea60u  /* ProspectingWindow */
#define RVA_PRO_GETVIS      0x48bf50u
#define RVA_SAVELOAD_PTR    0x212ebd8u  /* save/load dialogs: widget slots +0x100.. */
#define RVA_MSGBOX_COUNT    0x1f29a30u  /* modal message boxes open */
#define RVA_PLAYER_IFACE    0x2134690u  /* PlayerInterface* (GameWorld+0x580, verified) */
#define RVA_CTXMENU_VISIBLE 0x21332d0u  /* game's own per-frame cache byte of
                                         * ContextMenu::isVisible (written each frame
                                         * by the mouse handler; decompile-verified).
                                         * The REAL check = menuGUI->mMainWidget->
                                         * getVisible (widget's OWN flag -- inherited
                                         * visibility never updates, object lifetime
                                         * never ends; both earlier heuristics wedged). */
#define UIMASK_OVERVIEW     0x080       /* fullscreen map/factions/squads screen */
#define RVA_CAM_UPDATE       0x6b0f90u   /* CameraClass::update(bool controlEnabled) -- verified
                                          * M1. Hooked so the FP eye is re-asserted MID-frame:
                                          * the game's follow camera lags 30-100u behind the eye
                                          * while moving, and foliage paging + mesh LOD read that
                                          * stale position right after update() -> flicker. */
#define REISSUE_DIST         1.0f        /* re-issue the move order only when the target moved
                                          * this far -- per-frame re-issue restarts the path
                                          * (stutter) and was the earlier crash cause. */
#define RVA_TERRAIN_PTR      0x2133318u  /* Terrain* singleton (holder+0x18, same setup struct
                                          * as the camera globals). Class lives in
                                          * Plugin_Terrain_x64.dll. */
#define TERRAIN_GETHEIGHT_SYM "?getHeight@Terrain@@QEBA?AUHit@1@AEBVVector3@Ogre@@@Z"
#define TERRAIN_INTERSECT_SYM "?intersect@Terrain@@QEBA?AUHit@1@AEBVRay@Ogre@@@Z"

/* --- Building-interior preload (FP QoL): show interiors when NEAR, not only
 * when inside. All RVAs decompile-verified for 1.0.68. --- */
#define RVA_TOWNMGR_PTR    0x2134100u  /* TownManager* global */
#define RVA_NEAREST_TOWN   0x928890u   /* Town* fn(TownManager*, const Vec3*, int 0) */
#define RVA_INTERIOR_LOAD  0x562540u   /* void fn(BuildingInterior*): idempotent lazy
                                        * graphics load + keep-alive refresh; the fn the
                                        * game itself calls per visible interior. Does
                                        * NOT cut the roof/shell away. */
#define TOWN_GETLIST_VTOFF (0x2d8 / 8) /* Town vtable slot: lektor* fn(Town*, int, void*) */
#define BLDG_LIST_TYPE     0x13        /* list id: buildings with interior layouts */
#define BLDG_POS_X         0x48        /* Building world pos floats +0x48/+0x4C/+0x50 */
#define BLDG_INTERIOR      0x1F0       /* Building::myInterior (BuildingInterior*) */
#define BLDG_DESTROYED     0x1A1       /* Building::destroyed (bool) -- ruins */
#define BLDG_FLOORNUM      0xA4        /* Building::floornum (int, FCS "floornum") -- floor count.
                                        * Top floor index = floornum-1. (Ghidra 1.0.65 serialise
                                        * 0x551890/deserialise 0x5520e0, both key "floornum".) */
#define INTERIOR_RADIUS    400.0f      /* preload interiors within this range (~40 m) */
#define UPDATE_PRIORITY_HIGH 2

/* ---- custom FP character controller (motion drive, NO move orders) ----
 * Re-issuing destinations fought the order system (path/"official position"
 * bookkeeping resets are why the camera lagged while a plain right-click was
 * perfect). Instead we drive CharMovement's motion state directly each frame —
 * the same technique KenshiCoop's applyMotion uses to animate proxy bodies —
 * and rotate the character to the input direction with faceDirection.
 * CharMovement fields (KenshiLib layout, KenshiCoop-proven):   */
#define MV_CURRENTLY_MOVING 0x24   /* bool  */
#define MV_CURRENT_MOTION   0xA8   /* Ogre::Vector3 (velocity) */
#define MV_MAX_SPEED        0xB4   /* float */
#define MV_CURRENT_SPEED    0xB8   /* float */
#define MV_DESIRED_SPEED    0xBC   /* float (keep == current so accel logic doesn't idle us) */
#define MV_WALK_SPEED       0xC0   /* float */
#define MV_FACEDIR_VTOFF    6      /* faceDirection = live vtable slot 6 (+0x30) */
#define MV_MANUALMOVE_VTOFF 14     /* manualMovement(desiredMotion) = slot 14 (+0x70);
                                    * engine-driven velocity move (combat-strafe path):
                                    * ground-clamps + animates + NO auto-turn */
/* CharMovement OVERRIDES the position setters at higher slots than the
 * AbstractMovementBase ones (+0x20/0x28 are the base-class members — calling
 * slot 5 did nothing). The real overrides (header +0xB8/0xC0/0xC8):
 *   slot 23 _setPositionAndTeleport(const Vec3&, int floor)  <- the one KenshiCoop
 *   slot 24 _setPositionDirectionAndTeleport(Vec3&, Quat&)      proves moves the
 *   slot 25 _setPositionSimple(const Vec3&)                     physics proxy too */
#define MV_SETPOSTELE_VTOFF 23
/* Orient-to-direction movement: setDestination makes the character turn to face
 * the target and walk (no strafing). We aim FAR ahead so it commits to a full-
 * speed walk, and only RE-ISSUE when the heading or key set changes (or a slow
 * refresh) — re-issuing a near target every frame made it re-path and creep. */
/* Distance-controls-speed: the move target's distance is set by look pitch, the
 * way right-clicking near your feet walks slowly and clicking far runs. Kenshi
 * accelerates toward farther orders. Look DOWN (pitch +) -> near/slow; look UP
 * (pitch -) -> far/run. */
#define MOVE_NEAR          10.0f   /* target distance looking straight down (slow) */
#define MOVE_FAR           350.0f  /* target distance looking up (full run) */
#define MOVE_RETARGET_FRAC 0.4f    /* re-issue once the char has closed to this fraction of the target */
#define MOVE_KEEPALIVE_MS  2000    /* safety re-issue if nothing else triggers */
#define MOVE_TURN_EPS      0.12f   /* radians of heading change that forces a re-issue */
#define EYE_DROP           (-1.5f) /* offset from the head bone Y (negative = raise); tune */
#define FP_EYE_FORWARD     (g_cfg_eye_fwd)  /* eye forward of the head (config) */
#define FP_MOVE_FORWARD    (g_cfg_move_fwd) /* EXTRA forward push while moving (config) */

/* ---- FOV ----
 * Ogre::Frustum::setFOVy(const Radian&) [Camera inherits it]; Radian == {float}.
 * getFOVy returns a const ref (pointer in RAX -> safe ABI, unlike the by-value
 * get* accessors). We capture the default FOV once, force FP_FOV while in first
 * person, and restore on exit. */
#define OGRE_SETFOVY_SYM  "?setFOVy@Frustum@Ogre@@UEAAXAEBVRadian@2@@Z"
#define OGRE_GETFOVY_SYM  "?getFOVy@Frustum@Ogre@@UEBAAEBVRadian@2@XZ"
#define FP_FOV_DEG        (g_cfg_fov)  /* vertical FOV while first-person (config) */
#define DEG2RAD           0.01745329f

/* ---- near clip ----
 * Kenshi's RTS camera sits far from everything, so its near clip is large; at
 * eye level that clips nearby geometry and you see through walls/meshes. Pull it
 * in while first-person. Frustum::setNearClipDistance(float) / getNearClipDistance
 * (returns Real=float by value -> XMM0, safe scalar ABI). Kenshi is ~10 units/m. */
#define OGRE_SETNEARCLIP_SYM "?setNearClipDistance@Frustum@Ogre@@UEAAXM@Z"
#define OGRE_GETNEARCLIP_SYM "?getNearClipDistance@Frustum@Ogre@@UEBAMXZ"
#define OGRE_GETFARCLIP_SYM  "?getFarClipDistance@Frustum@Ogre@@UEBAMXZ"  /* diag: near/far ratio */
#define FP_NEARCLIP       (vm_nearclip(g_cfg_nearclip)) /* world units; clip very-near geometry
                                    * (own head/hair edges) a tiny bit; tune */

/* ---- MyGUI cursor (hide the default arrow, keep contextual sword/speech) ----
 * The visible cursor is a MyGUI sprite (ShowCursor can't touch it). MyGUI is a
 * separate DLL with PointerManager exports. We hook setPointer(const string&) —
 * Kenshi calls it when the cursor type changes — and, while FP is on, hide the
 * cursor when the new pointer == the default (arrow) and show it otherwise. */
#define MYGUI_DLL         "MyGUIEngine_x64.dll"
#define MYGUI_SETPOINTER_SYM  "?setPointer@PointerManager@MyGUI@@QEAAXAEBV?$basic_string@DU?$char_traits@D@std@@V?$allocator@D@2@@std@@@Z"
#define MYGUI_SETVISIBLE_SYM  "?setVisible@PointerManager@MyGUI@@QEAAX_N@Z"
#define MYGUI_GETDEFAULT_SYM  "?getDefaultPointer@PointerManager@MyGUI@@QEBAAEBV?$basic_string@DU?$char_traits@D@std@@V?$allocator@D@2@@std@@XZ"
#define MYGUI_GETINSTANCE_SYM "?getInstancePtr@?$Singleton@VPointerManager@MyGUI@@@MyGUI@@SAPEAVPointerManager@2@XZ"

/* ---- crosshair (replace the hidden default cursor with our image) ----
 * Create a MyGUI ImageBox at screen center showing crosshair.png (deployed to
 * <install>/kenshifp/, registered as an Ogre resource location). Show it while
 * the pointer is the default (gameplay, looking at nothing); the contextual
 * sword/speech cursors still render via the normal (un-hidden) pointer. */
#define MYGUI_GUI_GETINSTANCE_SYM "?getInstancePtr@?$Singleton@VGui@MyGUI@@@MyGUI@@SAPEAVGui@2@XZ"
#define MYGUI_CREATEWIDGET_SYM "?createWidgetT@Gui@MyGUI@@QEAAPEAVWidget@2@AEBV?$basic_string@DU?$char_traits@D@std@@V?$allocator@D@2@@std@@0HHHHUAlign@2@00@Z"
#define MYGUI_SETIMAGETEX_SYM  "?setImageTexture@ImageBox@MyGUI@@QEAAXAEBV?$basic_string@DU?$char_traits@D@std@@V?$allocator@D@2@@std@@@Z"
/* Point an ImageBox at a game ResourceImageSet (like the layout's ImageResource/
 * ImageGroup/ImageName) -- lets us reuse Kenshi's OWN "Kenshi_CharacterNameTags"
 * / "Stealth" eye, so we ship no texture and match whatever UI the player runs. */
#define MYGUI_SETITEMRES_SYM  "?setItemResource@ImageBox@MyGUI@@QEAA_NAEBV?$basic_string@DU?$char_traits@D@std@@V?$allocator@D@2@@std@@@Z"
#define MYGUI_SETITEMGRP_SYM  "?setItemGroup@ImageBox@MyGUI@@QEAAXAEBV?$basic_string@DU?$char_traits@D@std@@V?$allocator@D@2@@std@@@Z"
#define MYGUI_SETITEMNAME_SYM "?setItemName@ImageBox@MyGUI@@QEAAXAEBV?$basic_string@DU?$char_traits@D@std@@V?$allocator@D@2@@std@@@Z"
/* Widget::setColour(const Colour& {r,g,b,a}) -- the layout's "Colour" property;
 * tints resource ImageBoxes where the sub-widget colour path does not. */
#define MYGUI_SETCOLOUR_SYM   "?setColour@Widget@MyGUI@@QEAAXAEBUColour@2@@Z"
#define MYGUI_SETPOS_SYM      "?setPosition@Widget@MyGUI@@QEAAXHH@Z"   /* setPosition(int x, int y) */
#define MYGUI_WIDGET_INHVIS_SYM "?getInheritedVisible@Widget@MyGUI@@QEBA_NXZ"
#define MYGUI_WIDGET_SETVIS_SYM "?setVisible@Widget@MyGUI@@UEAAX_N@Z"
#define OGRE_RGM_GETSINGLETON_SYM "?getSingletonPtr@ResourceGroupManager@Ogre@@SAPEAV12@XZ"
#define OGRE_RGM_ADDLOCATION_SYM  "?addResourceLocation@ResourceGroupManager@Ogre@@QEAAXAEBV?$basic_string@DU?$char_traits@D@std@@V?$allocator@D@2@@std@@00_N1@Z"
#define OGRE_RGM_CREATEGROUP_SYM  "?createResourceGroup@ResourceGroupManager@Ogre@@QEAAXAEBV?$basic_string@DU?$char_traits@D@std@@V?$allocator@D@2@@std@@_N@Z"
#define OGRE_RGM_INITGROUP_SYM    "?initialiseResourceGroup@ResourceGroupManager@Ogre@@QEAAXAEBV?$basic_string@DU?$char_traits@D@std@@V?$allocator@D@2@@std@@@Z"
#define CROSSHAIR_SIZE    80         /* px on screen; tune */
#define SNEAK_ICON_SIZE   30         /* screen-space sneak eye, above the crosshair (~1.5x smaller) */

/* ---- M2 first-person (Ogre node override) ----
 * Scene graph (from the ctor): root -> center(+0x58) -> node(+0x70) -> camera
 * (+0x68 attached). CameraClass::update keeps `center` at the character and
 * offsets `node` (local, relative to center) up-and-back for 3rd person. For FP
 * we override `node`'s LOCAL transform every frame after update() ran: a small
 * eye-height offset above center + a mouse-look orientation. LOCAL (not world)
 * so it's independent of Kenshi's world coordinate space — setting a *derived*
 * (world) position to the global char coords fought the hierarchy and flung the
 * camera away. OgreMain_x64.dll exports, resolved by mangled name:
 *   Node::setPosition(const Vector3&)     [local]
 *   Node::setOrientation(Quaternion)      [local; 16B struct -> passed by ptr] */
#define OGRE_SETPOS_SYM   "?setPosition@Node@Ogre@@QEAAXAEBVVector3@2@@Z"
#define OGRE_SETORI_SYM   "?setOrientation@Node@Ogre@@QEAAXVQuaternion@2@@Z"
/* World-space transform: set camera node's DERIVED pos/orientation directly, so
 * the parent `center` node's transform can't induce dip or roll. Need center's
 * world position to place the eye = centerWorld + (head-feet) offset. */
#define OGRE_SETDPOS_SYM  "?_setDerivedPosition@Node@Ogre@@QEAAXAEBVVector3@2@@Z"
#define OGRE_GETDPOS_SYM  "?_getDerivedPosition@Node@Ogre@@QEBA?AVVector3@2@XZ"
#define OGRE_GETPOS_SYM   "?getPosition@Node@Ogre@@QEBAAEBVVector3@2@XZ"
#define OGRE_SETVISIBLE_SYM "?setVisible@MovableObject@Ogre@@QEAAX_N@Z"  /* hide arrow entities */
#define OGRE_GETVISIBLE_SYM "?getVisible@MovableObject@Ogre@@QEBA_NXZ"   /* headgear re-show detection */
/* Ogre::OldSkeletonInstance::disableBone(std::string name, bool disable) --
 * Kenshi's own decapitation call; disabling a bone collapses its mesh and
 * PERSISTS across the per-frame animation update. Version-independent export. */
#define OGRE_DISABLEBONE_SYM "?disableBone@OldSkeletonInstance@Ogre@@QEAAXV?$basic_string@DU?$char_traits@D@std@@V?$allocator@D@2@@std@@_N@Z"
/* Read the head bone's WORLD orientation, version-independently: skeleton
 * (Character+0x448 anim, +0xB8 skel) -> getBone(name) -> OldBone* -> its
 * derived (world) orientation. Both Ogre exports; getBone takes std::string&,
 * _getDerivedOrientation returns const Quaternion& (safe ABI). */
#define OGRE_GETBONE_SYM  "?getBone@Skeleton@Ogre@@UEBAPEAVOldBone@2@AEBV?$basic_string@DU?$char_traits@D@std@@V?$allocator@D@2@@std@@@Z"
#define OGRE_OLDNODE_GETDORI_SYM "?_getDerivedOrientation@OldNode@Ogre@@UEBAAEBVQuaternion@2@XZ"
#define OGRE_OLDNODE_GETDPOS_SYM "?_getDerivedPosition@OldNode@Ogre@@UEBAAEBVVector3@2@XZ"
#define OGRE_GETDPOS_UPD_SYM  "?_getDerivedPositionUpdated@Node@Ogre@@QEAA?AVVector3@2@XZ"
/* Procedural bone control (additive aim/IK): read animated LOCAL pose, write it
 * back with an offset, flag derived transforms dirty. All OldNode/OldBone. */
#define OGRE_OLDNODE_GETORI_SYM  "?getOrientation@OldNode@Ogre@@UEBAAEBVQuaternion@2@XZ"
#define OGRE_OLDNODE_SETORI_SYM  "?setOrientation@OldNode@Ogre@@UEAAXAEBVQuaternion@2@@Z"
#define OGRE_OLDNODE_NEEDUPD_SYM "?needUpdate@OldNode@Ogre@@UEAAX_N@Z"
#define OGRE_OLDBONE_SETMANUAL_SYM "?setManuallyControlled@OldBone@Ogre@@QEAAX_N@Z"
/* BIND pose access for the locomotion retarget: a bone's initial state IS the
 * binding pose (Skeleton::setBindingPose -> OldNode::setInitialState), constant
 * regardless of the currently-playing animation or the character's facing.
 * Verified exported from Kenshi's OgreMain_x64.dll (objdump). */
#define OGRE_OLDNODE_GETINITORI_SYM "?getInitialOrientation@OldNode@Ogre@@UEBAAEBVQuaternion@2@XZ"
#define OGRE_OLDNODE_GETINITPOS_SYM "?getInitialPosition@OldNode@Ogre@@UEBAAEBVVector3@2@XZ"
#define OGRE_OLDNODE_GETPARENT_SYM  "?getParent@OldNode@Ogre@@UEBAPEAV12@XZ"
#define OGRE_OLDNODE_SETPOS_SYM     "?setPosition@OldNode@Ogre@@UEAAXAEBVVector3@2@@Z"  /* pelvis
    * drop for the foot IK (downhill reach) */
#define OGRE_OLDNODE_GETDSCALE_SYM  "?_getDerivedScale@OldNode@Ogre@@UEBAAEBVVector3@2@XZ"  /* body
    * sliders scale bones -- IK lengths = bind geometry x derived scale */
#define OGRE_OLDNODE_SETSCALE_SYM "?setScale@OldNode@Ogre@@UEAAXAEBVVector3@2@@Z"  /* collapse head bone = hide head */
/* head-hide via the character body material's "hiddenMask" shader constant (the
 * mechanism a full-face helmet uses; the head is part of ONE composited body mesh
 * so per-vertex hide-groups are the only clean way -- Ghidra: AppearanceHuman::
 * updateHiddenParts 0x531230, mask uploaded to the body material's vertex params). */
#define OGRE_MAT_GETTECH_SYM  "?getTechnique@Material@Ogre@@QEAAPEAVTechnique@2@G@Z"
#define OGRE_TECH_GETPASS_SYM "?getPass@Technique@Ogre@@QEAAPEAVPass@2@G@Z"
#define OGRE_PASS_GETVPP_SYM  "?getVertexProgramParameters@Pass@Ogre@@QEBA?AV?$SharedPtr@VGpuProgramParameters@Ogre@@@2@XZ"
/* The game (updateHiddenParts) uses the INT overload (import 0x142247ad8 = ...H@Z),
 * NOT the uint (I) overload -- the uint one is a different function that writes a
 * different constant buffer and crashed. Match the game exactly. */
#define OGRE_GPUP_SETNAMEDI_SYM "?setNamedConstant@GpuProgramParameters@Ogre@@QEAAXAEBV?$basic_string@DU?$char_traits@D@std@@V?$allocator@D@2@@std@@H@Z"
#define OGRE_GPUP_IGNOREMISS_SYM "?setIgnoreMissingParams@GpuProgramParameters@Ogre@@QEAAX_N@Z"
#define OGRE_GPUP_FINDDEF_SYM "?_findNamedConstantDefinition@GpuProgramParameters@Ogre@@QEBAPEBUGpuConstantDefinition@2@AEBV?$basic_string@DU?$char_traits@D@std@@V?$allocator@D@2@@std@@_N@Z"
#define OGRE_MAT_NUMTECH_SYM  "?getNumTechniques@Material@Ogre@@QEBAGXZ"
#define OGRE_TECH_NUMPASS_SYM "?getNumPasses@Technique@Ogre@@QEBAGXZ"
#define OGRE_GETPARENTSCENENODE_SYM "?getParentSceneNode@MovableObject@Ogre@@QEBAPEAVSceneNode@2@XZ"
#define MYGUI_GETSUBMAIN_SYM "?getSubWidgetMain@SkinItem@MyGUI@@QEAAPEAVISubWidgetRect@2@XZ"
#define MYGUI_SUBSETCOLOUR_SYM "?_setColour@SubSkin@MyGUI@@UEAAXAEBUColour@2@@Z"
/* ---- in-game settings UI (MyGUI, resolved by mangled name from the DLL) ---- */
#define MYGUI_GUI_FINDWIDGET_SYM "?findWidgetT@Gui@MyGUI@@QEAAPEAVWidget@2@AEBV?$basic_string@DU?$char_traits@D@std@@V?$allocator@D@2@@std@@_N@Z"
#define MYGUI_WIDGET_CREATEWIDGET_SYM "?createWidgetT@Widget@MyGUI@@QEAAPEAV12@AEBV?$basic_string@DU?$char_traits@D@std@@V?$allocator@D@2@@std@@0HHHHUAlign@2@0@Z"
#define MYGUI_TABCTRL_ITEMCOUNT_SYM "?getItemCount@TabControl@MyGUI@@QEBA_KXZ"
#define MYGUI_TABCTRL_ITEMAT_SYM "?getItemAt@TabControl@MyGUI@@QEAAPEAVTabItem@2@_K@Z"
/* Hit-testing via MyGUI itself: ask which widget is under the mouse and compare
 * pointers -- avoids the fragile coordinate getters entirely. */
#define MYGUI_INPUT_GETINST_SYM "?getInstancePtr@?$Singleton@VInputManager@MyGUI@@@MyGUI@@SAPEAVInputManager@2@XZ"
#define MYGUI_MOUSEFOCUS_SYM "?getMouseFocusWidget@InputManager@MyGUI@@QEBAPEAVWidget@2@XZ"
#define MYGUI_KEYFOCUS_SYM   "?getKeyFocusWidget@InputManager@MyGUI@@QEBAPEAVWidget@2@XZ"
#define MYGUI_GETPARENT_SYM  "?getParent@Widget@MyGUI@@QEBAPEAV12@XZ"
#define MYGUI_SCROLL_SETRANGE_SYM "?setScrollRange@ScrollBar@MyGUI@@QEAAX_K@Z"
#define MYGUI_SCROLL_SETPOS_SYM "?setScrollPosition@ScrollBar@MyGUI@@QEAAX_K@Z"
#define MYGUI_SCROLL_GETPOS_SYM "?getScrollPosition@ScrollBar@MyGUI@@QEBA_KXZ"
#define MYGUI_BTN_GETSEL_SYM "?getStateSelected@Button@MyGUI@@QEBA_NXZ"
#define MYGUI_BTN_SETSEL_SYM "?setStateSelected@Button@MyGUI@@QEAAX_N@Z"
#define MYGUI_TEXTBOX_SETCAP_SYM "?setCaption@TextBox@MyGUI@@UEAAXAEBVUString@2@@Z"
#define MYGUI_WINDOW_SETCAP_SYM  "?setCaption@Window@MyGUI@@UEAAXAEBVUString@2@@Z"   /* Window overrides it */
#define MYGUI_USTRING_CTOR_SYM "??0UString@MyGUI@@QEAA@PEBD@Z"    /* UString(const char*) */
#define MYGUI_USTRING_DTOR_SYM "??1UString@MyGUI@@QEAA@XZ"
/* Recursive widget search (vanilla menu widgets carry a layout name-prefix that
 * findWidgetT can't match, so we DFS the widget tree matching the suffix). The
 * Enumerator is returned by value: { bool m_first; Widget** begin; Widget** end }
 * -- read begin(+8)/end(+16) and iterate the pointer range directly. */
#define MYGUI_GUI_GETENUM_SYM "?getEnumerator@Gui@MyGUI@@QEBA?AV?$Enumerator@V?$vector@PEAVWidget@MyGUI@@V?$allocator@PEAVWidget@MyGUI@@@std@@@std@@@2@XZ"
#define MYGUI_WIDGET_GETENUM_SYM "?getEnumerator@Widget@MyGUI@@QEBA?AV?$Enumerator@V?$vector@PEAVWidget@MyGUI@@V?$allocator@PEAVWidget@MyGUI@@@std@@@std@@@2@XZ"
#define MYGUI_WIDGET_GETNAME_SYM "?getName@Widget@MyGUI@@QEBAAEBV?$basic_string@DU?$char_traits@D@std@@V?$allocator@D@2@@std@@XZ"
#define OGRE_ENTITY_GETSKEL_SYM  "?getSkeleton@Entity@Ogre@@QEBAPEAVOldSkeletonInstance@2@XZ"
#define OGRE_ENTITY_UPDATEANIM_SYM "?_updateAnimation@Entity@Ogre@@QEAAXXZ"  /* camera weld:
    * force THIS frame's skeletal pose before the camera reads the head (frame-guarded,
    * the engine's render-time call then no-ops) */
#define OGRE_ENTITY_GETSKEL_SYM2 "?getSkeleton@Entity@Ogre@@QEBAPEAVSkeletonInstance@2@XZ"

/* ---- head-bone tracking (real first-person feel: eye = head bone) ----
 * Character::getBoneWorldPosition(this, retVec3, std::string* name) — RVA
 * 0x440360 (confirmed: falls back to getPosition/vtable+0x40 when the bone is
 * absent). Returns the bone position in the SAME game-world frame as
 * getPosition. So we take (head - feet) as a world-axis offset and apply it as
 * the camera node's LOCAL position above `center` (which the engine keeps at
 * the character in Ogre space). This tracks animation AND ragdoll (the head
 * bone follows the physics), and removes the eye-height guesswork/into-ground
 * dip. MEMBER-STRUCT-RETURN ABI: this=RCX, retbuf=RDX, args=R8 (per KenshiCoop;
 * same pattern as the working getPosition — NOT retbuf-first). */
#define RVA_GET_BONE_WORLD 0x440360u

/* ===== version-dependent address tables ===================================
 * KenshiFP's game addresses are build-specific. Steam 1.0.68 is the base
 * target; RE_Kenshi downgrades installs to Steam 1.0.65, so we ship both and
 * pick at load by the mainLoop prologue signature. The RVA_* macros above hold
 * the 1.0.68 values and seed T_1068; below they are redefined to read the
 * active table (g_rva), so all use-sites switch automatically. */
typedef struct {
    uintptr_t MAINLOOP, CAM_INSTANCE, INPUT_CONTROLENABLED, INPUT_MWHEEL, SCENE_CTX,
        FOLLOW_OBJECT, STOP_FOLLOW, CHARMOVE_SETDEST, CHAR_SETDEST,
        GUI_INV_COUNT, GUI_STATS_BEG, GUI_STATS_END, GUI_WINSTACK, GUI_DLGWND,
        DLG_GETVIS, ESCMENU_PTR, ESC_GETVIS, OVERVIEW_PTR, OVW_GETVIS,
        OPTIONS_PTR, OPT_GETVIS, PROSPECT_PTR, PRO_GETVIS, SAVELOAD_PTR,
        MSGBOX_COUNT, PLAYER_IFACE, CTXMENU_VISIBLE, CAM_UPDATE, TERRAIN_PTR,
        TOWNMGR_PTR, NEAREST_TOWN, INTERIOR_LOAD, GET_BONE_WORLD,
        RANGED_ANIMUPD, GUN_SHOOT, FACE_DIR, GUN_RELOAD, SHEATHE, GUN_CREATEPHYS,
        RC_GETGUN, CAM_MANUAL_SETOZ, SET_DIRECT_MOVE, CHARMOVE_UPDATE, XP_RUNNING,
        HANDMAP_PTR, HAND_TO_BUILDING, WALLCULL, GET_TOWN, SET_FLOORBYTE,
        MANUAL_MOVE,   /* CharMovement::manualMovement -- REAL override; the vtable slot
                        * +0x70 is the AbstractMovementBase no-op stub (same trap as the
                        * setPosition family, see MV_SETPOSTELE_VTOFF comment) */
        INVALIDATE_PATH, /* CharMovement mover destroy -- DO NOT CALL while driving (the
                          * +0x320 object is the physics mover; update() early-returns
                          * without it). Kept resolved for potential teardown uses. */
        ANIM_SETPOSDIR,  /* AnimationClass::setPositionAndDirection(anim, &pos, &facing):
                          * the call that actually turns the rendered body. update() feeds
                          * it facing(+0xD0)=velocity dir in MOVE_DIRECTION (the auto-turn);
                          * re-feeding it with the camera dir AFTER update wins the frame. */
        GROUND_HEIGHT,   /* standing-height query used by CharMovement::manualMovement */
        GROUND_NOHIT,    /* DATA: float sentinel GROUND_AT returns when nothing is below */
        RAGDOLL_QUEUED,  /* Character::ragdollQueued(this, bool on, u32 mask) -- the REAL
                          * gameplay knockdown API (1.0.65 0x5cb2d0): dedups + queues
                          * {on,mask} into the request deque at char+0x3E0; Character::update
                          * pumps it into setRagdoll (0x5d0320) which picks the male/female
                          * ragdoll template and hands CharMovement currentMotion(+0xA8) to
                          * the Scythe/Havok ragdoll as launch velocity. mask 1 = whole body,
                          * 0x800 = the knockout variant. NOT the old "ragdollMode" (0x5cb500)
                          * -- that one only drops carried items (decomp-proven). */
        STOP_RAGDOLL,    /* Character::stopRagdoll(this, bool immediate): applies (or queues)
                          * {off, 0x8000=all parts}. The ragdoll settle callback
                          * (ScytheRagdollPhysicsT vt slot 15, 0x7d2a20) calls this itself
                          * when the body comes to rest -> vanilla auto get-up. */
        CREATE_MOVER,    /* CharMovement::createMover (0x661500): rebuilds the +0x320 physics
                          * mover at the character's current position (setRagdoll(on) destroyed
                          * it via INVALIDATE_PATH). Idempotent: checks +0x320 == NULL first.
                          * The vanilla KO-exit path (setUnconscious(off)) calls it. */
        SET_UNCON,       /* Character::setUnconscious(this, bool): full KO enter/exit (queues
                          * mask 0x800 + drops weapons + cancels orders + mover teardown/rebuild).
                          * Unused for now -- fall KO comes from vanilla fall damage. */
        GROUND_AT,       /* float groundAt(const Vec3* pos, char inclObjects, char flag):
                          * the character ground query manualMovement uses -- terrain AND
                          * building floors/stairs. Basis of the foot-to-ground IK.
                          * FIELD ORDER MATCHES THE TABLES (GROUND_HEIGHT..SET_UNCON
                          * precede it) -- a mismatch here silently zeroed GROUND_AT. */
        SLABEL_UPDATE,   /* ScreenLabel::update (vt[1] of vftable w/ RTTI .?AVScreenLabel@@):
                          * the per-frame world->screen projector for the floating status
                          * texts ("Pick failed", "Pick success!", "*Thunk*", "Free!", ...).
                          * Lazy-creates its TextBox ("Kenshi_TextboxStandardText"/"Dialog"
                          * layer, widget* at +0x48), projects pos(+0xC) [+ tracked hand
                          * (+0x70) object pos when hand type(+0x78) != 0xb] via the shared
                          * helper (1.0.68 0x9b33f0 family) and setPosition()s the widget.
                          * Hooked: post-orig we re-pin the FP character's own labels near
                          * the crosshair. Expiry is deferred (dead-list + flag +0x9c), so
                          * touching the label right after orig is safe. */
        PBAR_UPDATE,     /* FloatingProgressBar::update (vt[1], RTTI .?AVFloatingProgressBar@@):
                          * the lockpicking/job % bar. visible flag +0x8, world pos +0xC,
                          * label string +0x20, progress int +0x48, widget wrapper +0x50
                          * (real MyGUI widget at wrapper+0x8, ProgressBar sub at +0xA0).
                          * Same hook treatment as SLABEL_UPDATE. */
        SET_PAUSE,       /* setPause(GameWorld*, char) -- KenshiMP-proven. Decomp: stashes/
                          * restores frameSpeedMult(+0x700) through a saved-speed global, so
                          * paused == framespeed 0.0. Used to swallow the vanilla spacebar
                          * pause under the FP jump (task #20). APPEND-ONLY table position. */
        KEYPRESSED,      /* MainListener::keyPressed(this, OIS::KeyEvent&) -- the game's OIS
                          * keyboard handler (RTTI: .?AVMainListener@@, KeyListener sub-vtable
                          * at +0x20, slot 1; keycode read at evt+0x10, DIK scan codes).
                          * Hooked to swallow the jump key's keydown in FP BEFORE the command
                          * dispatch: kills the vanilla space-pause AND its sound at the
                          * source. Cross-validated: vtable slot resolves to this fn in both
                          * Steam builds. */
        RAYCAST,         /* the GENERAL ray query GROUND_AT wraps (GROUND_AT = this with a
                          * static down vector): raycast(Vec3* outHit, const Vec3* origin,
                          * const Vec3* dir, u32 mask) -- normalizes dir, casts through the
                          * physics scene ([global]+0xE8, vt+0x380), writes the hit POINT to
                          * outHit or the GROUND_NOHIT sentinel in ALL THREE components on a
                          * miss (decomp: the miss constant IS DAT_GROUND_NOHIT). mask
                          * 0x88204 = both fall-system channel sets + objects. Basis of the
                          * jump/fall arc's wall collision. */
        IH_KEYDOWN,      /* InputHandler::keyDownEvent(this, int key): the only producer of the
                          * vanilla command queue (toggle_fps_camera = cmd 0x28 etc.; callers:
                          * MainListener::keyPressed, mousePressed). Hooked so FP-bound keys
                          * never reach a vanilla command (CS05). APPEND-ONLY position. */
        IH_KEYBOARD;     /* data: InputHandler+0xA0 = OIS::Keyboard* (written right after
                          * MainListener's keyboard->setEventCallback). KenshiFP puts its own
                          * KeyListener in front of the keyboard's one (CS05 path 2: RE_Kenshi's
                          * listener wrapper runs toggle_fps_camera itself). APPEND-ONLY. */
} addr_table_t;

static const addr_table_t T_1068 = {
    RVA_MAINLOOP, RVA_CAM_INSTANCE, RVA_INPUT_CONTROLENABLED, RVA_INPUT_MWHEEL, RVA_SCENE_CTX,
    RVA_FOLLOW_OBJECT, RVA_STOP_FOLLOW, RVA_CHARMOVE_SETDEST, RVA_CHAR_SETDEST,
    RVA_GUI_INV_COUNT, RVA_GUI_STATS_BEG, RVA_GUI_STATS_END, RVA_GUI_WINSTACK, RVA_GUI_DLGWND,
    RVA_DLG_GETVIS, RVA_ESCMENU_PTR, RVA_ESC_GETVIS, RVA_OVERVIEW_PTR, RVA_OVW_GETVIS,
    RVA_OPTIONS_PTR, RVA_OPT_GETVIS, RVA_PROSPECT_PTR, RVA_PRO_GETVIS, RVA_SAVELOAD_PTR,
    RVA_MSGBOX_COUNT, RVA_PLAYER_IFACE, RVA_CTXMENU_VISIBLE, RVA_CAM_UPDATE, RVA_TERRAIN_PTR,
    RVA_TOWNMGR_PTR, RVA_NEAREST_TOWN, RVA_INTERIOR_LOAD, RVA_GET_BONE_WORLD,
    0x51e4e0,   /* RangedCombatClass::animationUpdate (verified: reads gun+0x28,
                 * me+0x68 -> +0x448 anim, plays "reload 1 phase"; R8 = aimpos) */
    0x43a730,   /* GunClass::shoot(me,target,stat,aimpos&): projectile dir =
                 * getAimDir(aimpos) + skill randomDeviant (verified in decomp) */
    0x665250,   /* CharMovement::faceDirection (derived): stores facing at
                 * this+0xD0; lookatPosition funnels here via vtable+0x30 */
    0x436fb0,   /* GunClass::reloadAmmo: refills ammo(+0x20) from clip(+0x1C),
                 * handles bolt visibility (verified: unique 8b411c894120 body) */
    0x5cc820,   /* CharacterHuman::sheatheWeapon (verified: "hands" slot + anim
                 * at this+0x448); AI re-sheathes our manual draw through this */
    0x436a50,   /* Character gun-visual setup: derives body-entity parent node +
                 * material, calls gun(+0x440)->createPhysical, syncs visibility */
    0x4345c0,   /* RangedCombatClass::getGun: me->getCurrentWeapon()->vt[0x2D8]
                 * ->+0x240 (carried) or turret+0x440 (mounted) */
    0x6ae8e0,   /* CameraClass::manuallySetOrientationAndZoom(quat&, zoom):
                 * center(+0x58) ori + camera(+0x70) local (0,0,z) + manual flag */
    0x333300,   /* CharMovement::setDirectMovement(Vector3& d, float limit):
                 * setMovementMode(MOVE_DIRECTION) + desiredMotion + sqrt(limit).
                 * Engine-native direction-driven locomotion (verified decomp) */
    0x65ffa0,   /* CharMovement::update (via base-vtable+0x58 thunk; contains the
                 * MOVE_DIRECTION consumer branch at +0x11c -- self-verifying) */
    0x8C6660,   /* CharStats::xpRunning(time, speed): awards athletics(17) +
                 * strength(1) XP each move-frame. LOCATED BY DISASM -- the
                 * KenshiLib header RVA (0x8C4EB0) is stale/wrong for this region.
                 * WASD (MOVE_DIRECTION) bypasses the game's call to it, so we
                 * call it ourselves. Confirmed: calls calcAthleticsXPMult(speed)
                 * then xpGeneral(.,.,STAT_ATHLETICS) + calcStrengthXPMultFromWalking
                 * then xpGeneral(.,.,STAT_STRENGTH). */
    0, 0,           /* HANDMAP_PTR, HAND_TO_BUILDING: TODO 1.0.68 (floor look-ahead clamp) */
    0,              /* WALLCULL: TODO 1.0.68 (Object::updateVisibility floor-above reveal) */
    0, 0,           /* GET_TOWN, SET_FLOORBYTE: TODO 1.0.68 (per-building floor-byte bump) */
    0x65de00,       /* MANUAL_MOVE: CharMovement::manualMovement (decomp-verified) */
    0x65fe40,       /* INVALIDATE_PATH: mover free + null (decomp-verified; do not call while driving) */
    0x5b18f0,       /* ANIM_SETPOSDIR: AnimationClass::setPositionAndDirection (decomp-verified) */
    0x9b3ee0,       /* GROUND_HEIGHT: ground height query incl. buildings (decomp-verified) */
    0x168bda0,      /* GROUND_NOHIT: float sentinel DAT_14168bda0 (no-hit branch of the
                     * inner groundAt raycast FUN_1409b39d0; decomp-verified) */
    0x5cbd60,       /* RAGDOLL_QUEUED: unique prologue match of 1.0.65 0x5cb2d0 */
    0x5d2d20,       /* STOP_RAGDOLL: unique prologue match of 1.0.65 0x5d2290 */
    0x661f90,       /* CREATE_MOVER: unique prologue match of 1.0.65 0x661500 */
    0x5ce9c0,       /* SET_UNCON: unique prologue match of 1.0.65 0x5cdf30 */
    0x9b3ee0,       /* GROUND_AT: same query (the GROUND_HEIGHT twin field) */
    0x6ea9f0,       /* SLABEL_UPDATE: ScreenLabel::update (RTTI vt[1] real target) */
    0x6e87c0,       /* PBAR_UPDATE: FloatingProgressBar::update (RTTI vt[1] real target) */
    0x787fb0,       /* SET_PAUSE: setPause(GameWorld*, char) (KenshiMP-proven; decomp:
                     * frameSpeedMult stash/restore -- see addr_table_t comment) */
    0x82b010,       /* KEYPRESSED: MainListener::keyPressed (RTTI walk, KeyListener
                     * sub-vtable +0x20 slot 1; keycode remap table at fn+0x4a) */
    0x9b39d0,       /* RAYCAST: general ray query (decomp: GROUND_AT's inner fn) */
    0x360b30,       /* IH_KEYDOWN: InputHandler::keyDownEvent (keyPressed's dispatch call
                     * 0x82b25f -> thunk 0x46722) */
    0x2133410,      /* IH_KEYBOARD: InputHandler(0x2133370)+0xA0, stored at 0x8299e5 */
};
/* Steam 1.0.65 (RE_Kenshi's downgrade build). Signature-transplant mapped;
 * 0 = TODO (Ghidra pass in progress) or unused-in-client. Same field order. */
static const addr_table_t T_1065 = {
    0x787e70, 0x21322c0, 0x21323f0, 0, 0x21322b8,
    0x6aed00, 0x6aed40, 0x6607e0,
    0x5c7a50,   /* CHAR_SETDEST: teleport+facing placement (1.0.68 twin 0x5c84e0,
                 * unique prologue match) -- moves character AND its physics mover;
                 * the walk-off fall tier integrates gravity through it */
    0x2132810, 0x2132918, 0x2132920, 0x2132960, 0x2132770,
    0x721390, 0x212e4a8, 0x912170, 0x212e4e8, 0x48b0e0,
    0x212e080, 0x3e7100, 0x212da50, 0x48b4c0, 0x212dbc8,
    0x1f28a20, 0x2133630, 0x2132280, 0x6b1540, 0x21322c8,
    0x21330a0, 0x9279c0, 0x561ab0, 0x43ffc0,
    0x51da50,   /* animationUpdate: sig-transplant, matches KenshiLib-0x310 delta */
    0x43a390,   /* GunClass::shoot: sig-transplant (unique 32-byte prologue match) */
    0x6647c0,   /* faceDirection: masked sig-transplant, = KenshiLib-0x310 exactly */
    0x436c10,   /* reloadAmmo: unique body match at same +0x2b, identical prologue */
    0x5cbd90,   /* sheatheWeapon: "hands" xref at +0x3e + identical prologue */
    0x4366b0,   /* gun-visual setup: masked-sig pair match (same 0xe0 sibling gap) */
    0x434220,   /* getGun: unique 24-byte sig (me+0x68 -> getCurrentWeapon call) */
    0x6af0c0,   /* manuallySetOrientationAndZoom: byte-identical prologue, +0x7E0 */
    0x3332c0,   /* setDirectMovement: unique 22-byte prologue match */
    0x65f510,   /* CharMovement::update: unique 28-byte prologue match */
    0x8C5790,   /* CharStats::xpRunning: masked-sig transplant from 1.0.68 0x8C6660
                 * (unique match; prologue 40 53 48 83 EC 40 48 8B D9 48 8B 49 10) */
    0x2132f50,  /* HANDMAP_PTR: &DAT (hand->object map manager) for the floor clamp */
    0x9f8050,   /* HAND_TO_BUILDING: FUN_1409f8050(mapmgr, hand)->Building* (verified decomp) */
    0x5c94d0,   /* WALLCULL: FUN_1405c94d0 Object::updateVisibility -- per-object floor-cull
                 * applier; sets interior flag +0xe5 = getFloor(+0xa4)<=byte, render flag +0x1a8 */
    0xf6be0,    /* GET_TOWN: FUN_1400f6be0(building) -> owning Town* (verified: refreshInterior
                 * + FUN_14092b0a0 both call it before the byte lookup) */
    0x92b0f0,   /* SET_FLOORBYTE: FUN_14092b0f0(town, building, char byte) -> writes the
                 * per-building cutaway floor record+0x78 via the town's hash map (town+0x250) */
    0x65d370,   /* MANUAL_MOVE: CharMovement::manualMovement (pos += v, ground clamp,
                 * speed=|v|; decomp-verified on 1.0.68 twin 0x65de00; unique 28-byte
                 * prologue match incl. the telltale `add rcx,0xC4` position lea) */
    0x65f3b0,   /* INVALIDATE_PATH: 1.0.68 twin 0x65fe40, unique prologue match */
    0x5b0e60,   /* ANIM_SETPOSDIR: 1.0.68 twin 0x5b18f0, unique prologue match */
    0x9b3010,   /* GROUND_HEIGHT: manualMovement's standing-height query (terrain + buildings) */
    0x168ada0,  /* GROUND_NOHIT: float sentinel (DAT_14168ada0) = "no ground below" */
    0x5cb2d0,   /* RAGDOLL_QUEUED: Character::ragdollQueued(on, mask) (decomp-verified;
                 * request deque at char+0x3E0, pumped by Character::update 0x5d21a0).
                 * NOT 0x5cb500 "ragdollMode" -- that only drops carried items. */
    0x5d2290,   /* STOP_RAGDOLL: Character::stopRagdoll(immediate) (decomp-verified:
                 * {off, 0x8000} apply-or-queue) */
    0x661500,   /* CREATE_MOVER: CharMovement::createMover (decomp-verified:
                 * _aligned_malloc(400) mover rebuild at current pos, +0x320 null-check) */
    0x5cdf30,   /* SET_UNCON: Character::setUnconscious (decomp-verified: 0x800 KO ragdoll
                 * + order cancel; off-path recreates the mover) */
    0x9b3010,   /* GROUND_AT: same query (the GROUND_HEIGHT twin field) */
    0x6ea250,   /* SLABEL_UPDATE: RTTI vtable walk on kenshi_1065.exe (thunk 0x554c -> real) */
    0x6e8020,   /* PBAR_UPDATE: RTTI vtable walk on kenshi_1065.exe (thunk 0x535c6 -> real) */
    0x787470,   /* SET_PAUSE: sig-transplant of 1.0.68 0x787fb0 (26-byte masked prologue,
                 * unique in both exes; scratchpad transplant_setpause.py 2026-08-24) */
    0x82a460,   /* KEYPRESSED: sig-transplant of 1.0.68 0x82b010 -- identical body
                 * (keycode read [rdx+0x10]) AND the 1.0.65 KeyListener vtable slot 1
                 * thunk resolves here (double-confirmed) */
    0x9b2b00,   /* RAYCAST: sig-transplant of 1.0.68 0x9b39d0 (byte-identical prologue;
                 * also matches the region's known -0xED0 delta exactly) */
    0x360ad0,   /* IH_KEYDOWN: keyPressed's dispatch call 0x82a6af -> thunk 0x466f0; body
                 * identical to 1.0.68 0x360b30 except call rel32s */
    0x21323c0,  /* IH_KEYBOARD: InputHandler(0x2132320)+0xA0, stored at 0x828e15 */
};
/* GOG 1.0.68 ("Kenshi 1.0.68 - x64 (Newland) (GOG)", stamp 0x6602d5e3, image
 * 0x232c000, entry 0xed6bec) -- the sibling compile of Steam 1.0.68 linked
 * without steam_api. Produced by tools/transplant_rvas.py (capstone-masked
 * sig transplant from kenshi_1065.exe; every field unique-matched or data
 * consensus-matched; MAINLOOP/CAM_UPDATE/XP_RUNNING cross-checked against
 * independent full-.text signature scans). CAUTION: its SizeOfImage equals
 * Steam 1.0.65's, so detection must test the GOG stamp BEFORE any
 * img==0x232c000 fallback. */
static const addr_table_t T_GOG68 = {
    0x788360, 0x2132240, 0x2132370,
    0x21323b8,  /* INPUT_MWHEEL: CONTROLENABLED+0x48 (same InputHandler object;
                 * struct-internal offset, matches 1.0.68's 0x2133440/0x2133488) */
    0x2132238,
    0x6adec0, 0x6adf00, 0x660c10, 0x5c7e80,
    0x21327a0, 0x21328a8, 0x21328b0, 0x21328f0, 0x2132700,
    0x721860, 0x212e3e8, 0x912780, 0x212e428, 0x48b510,
    0x212dfc0, 0x3e6be0, 0x212d990, 0x48b8f0, 0x212db08,
    0x1f28a30, 0x21335c0, 0x2132200, 0x6b0930, 0x2132248,
    0x2133030, 0x927fd0, 0x561ee0, 0x43fd00,
    0x51de80, 0x43a0d0, 0x664bf0, 0x436950, 0x5cc1c0, 0x4363f0,
    0x433f60, 0x6ae280, 0x332ca0, 0x65f940, 0x8c5da0,
    0x2132ee0, 0x9f8660, 0x5c9900,
    0xf6c00,    /* GET_TOWN: COMDAT twin (identical copy also at 0x2962e0) */
    0x92b700,
    0x65d7a0, 0x65f7e0, 0x5b1290, 0x9b3620, 0x168ada0,
    0x5cb700, 0x5d26c0, 0x661930, 0x5ce360,
    0x9b3620,   /* GROUND_AT: same query (the GROUND_HEIGHT twin field) */
    0x6ea390,   /* SLABEL_UPDATE: transplant of 1.0.65 0x6ea250 (unique 24B) */
    0x6e8160,   /* PBAR_UPDATE:   transplant of 1.0.65 0x6e8020 (unique 27B) */
    0,          /* SET_PAUSE: TODO GOG (no GOG exe on hand to transplant; jump works,
                 * only the spacebar-pause swallow degrades -- rebind pause in-game) */
    0,          /* KEYPRESSED: TODO GOG (same) */
    0,          /* RAYCAST: TODO GOG (same; arc collision degrades to none) */
    0,          /* IH_KEYDOWN: TODO GOG (runtime sig fills it) */
    0,          /* IH_KEYBOARD: TODO GOG (front key listener off) */
};
/* GOG 1.0.65 ("Kenshi 1.0.65 - x64 (Newland) (GOG)", stamp 0x65d60519, image
 * 0x232a000, entry 0xed5cfc) -- RE_Kenshi's GOG downgrade exe, i.e. THE build
 * every GOG RE_Kenshi user actually runs. Sibling compile of Steam 1.0.65
 * (stamp +66s). Produced by tools/transplant_rvas.py from kenshi_1065.exe;
 * CROSS-CONFIRMED against live GOG user logs: the runtime signature scan had
 * independently resolved MAINLOOP=0x7877a0, CAM_UPDATE=0x6b05e0 and
 * XP_RUNNING=0x8c4eb0 on this exe -- all three match this table exactly. */
static const addr_table_t T_GOG65 = {
    0x7877a0, 0x2130230, 0x2130360,
    0x21303a8,  /* INPUT_MWHEEL: CONTROLENABLED+0x48 (struct-internal offset,
                 * same InputHandler object as on the other builds) */
    0x2130228,
    0x6adda0, 0x6adde0, 0x660af0, 0x5c7d60,
    0x2130780, 0x2130888, 0x2130890, 0x21308d0, 0x21306e0,
    0x720cf0, 0x212c3e8, 0x911890, 0x212c428, 0x48b3f0,
    0x212bfc0, 0x3e6d20, 0x212b990, 0x48b7d0, 0x212bb08,
    0x1f26a30, 0x21315a0, 0x21301f0, 0x6b05e0, 0x2130238,
    0x2131010, 0x9270e0, 0x561dc0, 0x43fbe0,
    0x51dd60, 0x439fb0, 0x664ad0, 0x436830, 0x5cc0a0, 0x4362d0,
    0x433e40, 0x6ae160, 0x332e50, 0x65f820, 0x8c4eb0,
    0x2130ec0, 0x9f7770, 0x5c97e0,
    0xf6be0,    /* GET_TOWN: same RVA as Steam 1.0.65 */
    0x92a810,
    0x65d680, 0x65f6c0, 0x5b1170, 0x9b2730, 0x1689da0,
    0x5cb5e0, 0x5d25a0, 0x661810, 0x5ce240,
    0x9b2730,   /* GROUND_AT: same query (the GROUND_HEIGHT twin field) */
    0x6e9b60,   /* SLABEL_UPDATE: transplant of 1.0.65 0x6ea250 (unique 24B) */
    0x6e7930,   /* PBAR_UPDATE:   transplant of 1.0.65 0x6e8020 (unique 27B) */
    0,          /* SET_PAUSE: TODO GOG (see T_GOG68 note) */
    0,          /* KEYPRESSED: TODO GOG (see T_GOG68 note) */
    0,          /* RAYCAST: TODO GOG (see T_GOG68 note) */
    0,          /* IH_KEYDOWN: TODO GOG (runtime sig fills it) */
    0,          /* IH_KEYBOARD: TODO GOG (front key listener off) */
};
static addr_table_t g_rva;   /* active table, selected at load by build signature */

/* Runtime signature resolution. The RE_Kenshi build uses it as its PRIMARY
 * resolver (version-independent); the standalone build uses it only to fill
 * gaps a recognised static table left at 0 (see kfp_resolve_missing). */
#include "../re_plugin/rva_sigs.h"

#undef RVA_MAINLOOP
#undef RVA_CAM_INSTANCE
#undef RVA_INPUT_CONTROLENABLED
#undef RVA_INPUT_MWHEEL
#undef RVA_SCENE_CTX
#undef RVA_FOLLOW_OBJECT
#undef RVA_STOP_FOLLOW
#undef RVA_CHARMOVE_SETDEST
#undef RVA_CHAR_SETDEST
#undef RVA_GUI_INV_COUNT
#undef RVA_GUI_STATS_BEG
#undef RVA_GUI_STATS_END
#undef RVA_GUI_WINSTACK
#undef RVA_GUI_DLGWND
#undef RVA_DLG_GETVIS
#undef RVA_ESCMENU_PTR
#undef RVA_ESC_GETVIS
#undef RVA_OVERVIEW_PTR
#undef RVA_OVW_GETVIS
#undef RVA_OPTIONS_PTR
#undef RVA_OPT_GETVIS
#undef RVA_PROSPECT_PTR
#undef RVA_PRO_GETVIS
#undef RVA_SAVELOAD_PTR
#undef RVA_MSGBOX_COUNT
#undef RVA_PLAYER_IFACE
#undef RVA_CTXMENU_VISIBLE
#undef RVA_CAM_UPDATE
#undef RVA_TERRAIN_PTR
#undef RVA_TOWNMGR_PTR
#undef RVA_NEAREST_TOWN
#undef RVA_INTERIOR_LOAD
#undef RVA_GET_BONE_WORLD
#define RVA_MAINLOOP            (g_rva.MAINLOOP)
#define RVA_RANGED_ANIMUPD      (g_rva.RANGED_ANIMUPD)
#define RVA_GUN_SHOOT           (g_rva.GUN_SHOOT)
#define RVA_FACE_DIR            (g_rva.FACE_DIR)
#define RVA_GUN_RELOAD          (g_rva.GUN_RELOAD)
#define RVA_SHEATHE             (g_rva.SHEATHE)
#define RVA_GUN_CREATEPHYS      (g_rva.GUN_CREATEPHYS)
#define RVA_RC_GETGUN           (g_rva.RC_GETGUN)
#define RVA_CAM_MANUAL_SETOZ    (g_rva.CAM_MANUAL_SETOZ)
#define RVA_SET_DIRECT_MOVE     (g_rva.SET_DIRECT_MOVE)
#define RVA_MANUAL_MOVE         (g_rva.MANUAL_MOVE)
#define RVA_INVALIDATE_PATH     (g_rva.INVALIDATE_PATH)
#define RVA_ANIM_SETPOSDIR      (g_rva.ANIM_SETPOSDIR)
#define RVA_GROUND_NOHIT        (g_rva.GROUND_NOHIT)
#define RVA_RAGDOLL_QUEUED      (g_rva.RAGDOLL_QUEUED)
#define RVA_STOP_RAGDOLL        (g_rva.STOP_RAGDOLL)
#define RVA_CREATE_MOVER        (g_rva.CREATE_MOVER)
#define RVA_SET_UNCON           (g_rva.SET_UNCON)
#define RVA_GROUND_AT           (g_rva.GROUND_AT)
#define MV_MOVER                0x320   /* CharMovement::mover (physics mover object*) */
#define MV_ANIMATION            0x3A0   /* CharMovement::animation (AnimationClass*) */
#define RVA_CHARMOVE_UPDATE     (g_rva.CHARMOVE_UPDATE)
#define RVA_HANDMAP_PTR         (g_rva.HANDMAP_PTR)
#define RVA_HAND_TO_BUILDING    (g_rva.HAND_TO_BUILDING)
#define RVA_WALLCULL            (g_rva.WALLCULL)
#define RVA_GET_TOWN            (g_rva.GET_TOWN)
#define RVA_SET_FLOORBYTE       (g_rva.SET_FLOORBYTE)
#define RVA_CAM_INSTANCE        (g_rva.CAM_INSTANCE)
#define RVA_INPUT_CONTROLENABLED (g_rva.INPUT_CONTROLENABLED)
#define RVA_INPUT_MWHEEL        (g_rva.INPUT_MWHEEL)
#define RVA_SCENE_CTX           (g_rva.SCENE_CTX)
#define RVA_FOLLOW_OBJECT       (g_rva.FOLLOW_OBJECT)
#define RVA_STOP_FOLLOW         (g_rva.STOP_FOLLOW)
#define RVA_CHARMOVE_SETDEST    (g_rva.CHARMOVE_SETDEST)
#define RVA_CHAR_SETDEST        (g_rva.CHAR_SETDEST)
#define RVA_GUI_INV_COUNT       (g_rva.GUI_INV_COUNT)
#define RVA_GUI_STATS_BEG       (g_rva.GUI_STATS_BEG)
#define RVA_GUI_STATS_END       (g_rva.GUI_STATS_END)
#define RVA_GUI_WINSTACK        (g_rva.GUI_WINSTACK)
#define RVA_GUI_DLGWND          (g_rva.GUI_DLGWND)
#define RVA_DLG_GETVIS          (g_rva.DLG_GETVIS)
#define RVA_ESCMENU_PTR         (g_rva.ESCMENU_PTR)
#define RVA_ESC_GETVIS          (g_rva.ESC_GETVIS)
#define RVA_OVERVIEW_PTR        (g_rva.OVERVIEW_PTR)
#define RVA_OVW_GETVIS          (g_rva.OVW_GETVIS)
#define RVA_OPTIONS_PTR         (g_rva.OPTIONS_PTR)
#define RVA_OPT_GETVIS          (g_rva.OPT_GETVIS)
#define RVA_PROSPECT_PTR        (g_rva.PROSPECT_PTR)
#define RVA_PRO_GETVIS          (g_rva.PRO_GETVIS)
#define RVA_SAVELOAD_PTR        (g_rva.SAVELOAD_PTR)
#define RVA_MSGBOX_COUNT        (g_rva.MSGBOX_COUNT)
#define RVA_PLAYER_IFACE        (g_rva.PLAYER_IFACE)
#define RVA_CTXMENU_VISIBLE     (g_rva.CTXMENU_VISIBLE)
#define RVA_CAM_UPDATE          (g_rva.CAM_UPDATE)
#define RVA_TERRAIN_PTR         (g_rva.TERRAIN_PTR)
#define RVA_TOWNMGR_PTR         (g_rva.TOWNMGR_PTR)
#define RVA_NEAREST_TOWN        (g_rva.NEAREST_TOWN)
#define RVA_INTERIOR_LOAD       (g_rva.INTERIOR_LOAD)
#define RVA_GET_BONE_WORLD      (g_rva.GET_BONE_WORLD)
#define RVA_SET_PAUSE           (g_rva.SET_PAUSE)
#define RVA_KEYPRESSED          (g_rva.KEYPRESSED)
#define RVA_RAYCAST             (g_rva.RAYCAST)
#define RVA_IH_KEYDOWN          (g_rva.IH_KEYDOWN)
#define RVA_IH_KEYBOARD         (g_rva.IH_KEYBOARD)
/* ========================================================================= */
#define HEAD_BONE_NAME    "Bip01 Head"
/* World-space orientation setter. Used for the look direction so it's immune to
 * the parent `center` node's orientation — setting a *local* orientation made
 * the camera ROLL when yawing (local combined with center's tilt). Position
 * stays LOCAL (small eye offset above center) to avoid world-coordinate issues.
 * NOTE: Ogre's get* accessors return BY VALUE and crashed across our ABI, so we
 * never read node state; FP exit just levels local orientation to identity. */
#define OGRE_SETDORI_SYM  "?_setDerivedOrientation@Node@Ogre@@QEAAXAEBVQuaternion@2@@Z"
#define EYE_HEIGHT        1.7f    /* fallback eye height ONLY when the head bone
                                   * read fails; head-bone offset is used when valid */
#define LOOK_SENS         (0.0025f * g_cfg_sens) /* radians per mouse count (config-scaled) */

/* ---- player character / position (proven in KenshiMP) ---- */
#define PI_PLAYERCHARS    0x2B0      /* PlayerInterface::playerCharacters (lektor<Character*>) */
#define PI_SELECTED_CHAR  0xF0       /* PlayerInterface::selectedCharacter (hand) */
#define HAND_IDS          0x8        /* hand: vftable(8) then 5 id dwords (+0x8..+0x18) */
#define LEK_COUNT         0x8        /* lektor::count (u32) */
#define LEK_STUFF         0x10       /* lektor::stuff (T*) */
#define GETPOS_VTABLE_SLOT 8         /* Character::getPosition; ABI Vec3*(this RCX, out RDX) */
#define GETFLOOR_VTABLE_SLOT (0x60/8) /* Character::getFloor; ABI int(this RCX) */

/* ---- input (Win32, zero engine dependency for stage 0) ---- */
/* ---- user configuration (KenshiFP.ini, hot-reloaded in-game) ------------ */
static int g_cfg_aim_lean = 1;     /* aim_lean: spine bend with weapon drawn */
static int g_cfg_freeaim  = 1;     /* ranged_freeaim: crosshair aim in combat */
#include "kfp_view.h"
#include "kfp_weld.h"
static KfpView g_view;
static int g_cfg_camera_zoom=1;
static int g_cfg_direct_default = 1; /* always direct controls after world load */
static int g_cfg_key_take_control = 0x75; /* F6: explicit control transfer */
static int g_cfg_combat_auto_reload = 1; /* manual ranged: reload while aiming an empty weapon */
static float g_cfg_spread_scale = 1.0f;  /* PT15: manual crossbow skill cone scale (0 = off) */
static int g_cfg_wheel    = 1;     /* wheel_speed: scrollwheel gait control */
static int g_cfg_vignette = 1;     /* ko_vignette: dark edges while knocked out */
static int g_cfg_key_fp   = 0xA5;  /* key_toggle_fp (VK code; default Right Alt) */
static int g_cfg_key_w    = 0x57;  /* key_forward */
static int g_cfg_key_a    = 0x41;  /* key_left */
static int g_cfg_key_s    = 0x53;  /* key_back */
static int g_cfg_key_d    = 0x44;  /* key_right */
static int g_cfg_key_settings = 0x79;  /* key_settings (VK code; default F10) -- toggles the settings window */
static int g_cfg_manual_combat = 1;    /* manual_combat: FP manual melee/ranged combat (F10 toggle; harness
                                        * fp_combat on|off overrides at runtime until this changes) */
/* FP combat binds (VK codes, mouse buttons allowed: 1 LMB, 2 RMB, 4 MMB, 5/6 side buttons). interact = block
 * (default) keeps the tap-RMB-while-holstered context menu; a separate interact key opens it on press. */
static int g_cfg_key_attack = 0x01, g_cfg_key_block = 0x02, g_cfg_key_select = 0x04,
           g_cfg_key_interact = 0x02, g_cfg_key_draw = 0x52;
static int   g_cfg_sneak_eye = 1;   /* show the screen-space sneak eye in FP */
static int   g_cfg_stealth_arrows = 0; /* show the world-space 3D stealth arrows in FP (0 = hidden, default) */
static int   g_cfg_hide_head   = 1;    /* always hide the player's head mesh in FP (not just FF) */
static unsigned g_cfg_head_mask = 0x200;      /* hiddenMask head bit: teal row-0 part-map paint = bit 9. This
                                        * hides head vertices WITHOUT touching Bip01 Head (bone-
                                        * scaling froze the camera's anchor bone -> fly-away). All
                                        * bits by default; narrow via ini head_hide_mask if it
                                        * hides too much. */
static int   g_cfg_hide_headgear = 1;  /* hide worn HEAD-COVERING gear (hat/helmet/mask/hair/beard)
                                        * whenever the head mesh itself is hidden. Those are separate
                                        * Ogre entities, so without this you sit inside your own
                                        * floating helmet in FP. */
static unsigned g_cfg_headgear_slots = HEADGEAR_SLOTS_DEF;  /* bitmask over the AttachSlot enum
                                        * (bit N = slot N); default 0x201C = HAIR|HAT|EYES|BEARD.
                                        * Add e.g. bit 11 (0x800, NECK) if a scarf-type item still
                                        * shows in front of the camera. */
static int   g_cfg_auto_floors = 1;    /* auto-reveal the character's building floor in FP */
static int   g_cfg_falling   = 0;      /* falling: walk off cliff/roof/stair edges in FP (ini
                                        * falling=0 to disable). Rides the REAL vanilla ragdoll
                                        * (Character::ragdollQueued) -- fall physics, fall damage,
                                        * landing and get-up are all engine-native. */
static float g_cfg_fall_drop = 3.0f;   /* fall_drop: min height drop (units) that counts as an edge */
static float g_cfg_fall_probe = 1.3f;  /* fall_probe: how far ahead (units) to test for the edge.
                                        * Keep SHORT (just past the body): a long probe passes
                                        * UNDER raised stairs/ramps ahead and reads the ground
                                        * far below them -> false edges while climbing. */
static float g_cfg_fall_air  = 1.6f;   /* fall_air: absolute airtime cap -- falls longer than this
                                        * KO-ragdoll regardless of impact (long float configs) */
static float g_cfg_fall_ko   = 110.0f; /* fall_ko: impact velocity (units/s) at/above which the
                                        * landing crumples into the KO ragdoll (110 = a ~40-unit
                                        * / 4-story fall at gravity 150; 80 crumpled 2-story
                                        * drops that should be knee-absorbs). Velocity, not
                                        * airtime: a time gate broke when gravity changed. */
static float g_cfg_fall_settle = 0.8f; /* fall_settle: seconds at rest before we request get-up */
static float g_cfg_fall_timeout = 8.0f;/* fall_timeout: max seconds tumbling before forced get-up */
static float g_cfg_fall_gravity = 150.0f; /* fall_gravity: units/s^2 (walk-off integrator).
                                        * Scaled to this world's speeds (sprint ~55 u/s):
                                        * 90 felt float-y ("no gravity acceleration"). */
static float g_cfg_fall_maxvel  = 200.0f;/* fall_maxvel: terminal velocity (walk-off tier) */
static int   g_cfg_jump      = 0;      /* jump: Space = FP jump (task #20). The vanilla
                                        * spacebar PAUSE toggle is swallowed while FP is
                                        * on (setPause revert); needs falling=1 -- the
                                        * jump IS a walk-off arc with upward launch. */
static float g_cfg_jump_vel  = 45.0f;  /* jump_vel: takeoff vertical velocity (units/s).
                                        * apex height = vel^2 / (2 * fall_gravity) */
static int   g_cfg_key_jump  = 0x20;   /* key_jump: VK code (default VK_SPACE) */
static int   g_cfg_key_pause = 0x50;   /* key_pause: FP pause toggle (default P).
                                        * Space is the jump in FP, so pausing moves
                                        * here -- outside FP the vanilla spacebar
                                        * pause is untouched. 0 disables. */
static float g_cfg_sneak_x   = 0.0f; /* sneak eye X offset from default position (px) */
static float g_cfg_sneak_y   = 0.0f; /* sneak eye Y offset from default position (px) */
static int   g_cfg_screen_status = 1; /* FP: pin the player's own floating statuses (the
                                       * ScreenLabel texts "Pick failed"/"Pick success!"/
                                       * "*Thunk*"/... and the FloatingProgressBar lockpick/
                                       * job % bar) near the crosshair instead of letting
                                       * them project from the character's head */
static float g_cfg_status_x  = 0.0f; /* status text/bar X offset from default position (px) */
static float g_cfg_status_y  = 0.0f; /* status text/bar Y offset from default position (px) */
static float g_cfg_exit_zoom = 0.0f; /* exit_camera_zoom: 0 = auto (use the zoom captured on FP
                                      * enter). Nonzero overrides the third-person distance the
                                      * camera returns to on FP exit; negative flips it to the
                                      * other side of the character. Hot-reloads. */
static int g_cfg_key_sprint = 0xA0; /* key_sprint (default Left Shift) -- HOLD to sprint;
                                     * the scrollwheel throttle covers walk..jog only */
static int g_cfg_key_free = 0xA4;  /* key_free_cursor (default Left Alt) -- HOLD to free the
                                    * mouse (like an open panel) without opening UI; 0 = off.
                                    * Read passively via GetAsyncKeyState, so Kenshi's own
                                    * Left-Alt behaviour is NOT overridden. */
static float g_cfg_fov      = 70.0f;   /* fov: vertical degrees in FP */
static float g_cfg_nearclip = 3.0f;    /* near_clip: world units. DEFAULT 3.0 -- z-buffer
                                        * precision scales with the near plane, and Kenshi's
                                        * far plane is 50000: below ~3.0 the depth test at
                                        * foliage/rock burial seams falls under the precision
                                        * floor at mid/far range, so buried bases z-fight
                                        * through the terrain -- "foliage flickers every
                                        * frame while the camera rotates" (rotation re-rolls
                                        * rasterization noise; translation barely moves
                                        * distant screen positions -- hence W-clean/look-
                                        * flicker). Field-verified 2026-08-25: 0.05..1.0 all
                                        * flicker, 3.0 completely clean. Same artifact
                                        * exists in VANILLA at ground-level zoom -- it's an
                                        * engine constant nobody tuned for eye-level cameras.
                                        * Cost: geometry closer than ~0.3m clips; fine in FP. */
static float g_cfg_sens     = 1.0f;    /* sensitivity: mouse multiplier */
static float g_cfg_eye_fwd  = 0.8f;    /* eye_forward: eye ahead of head bone (default 0.8,
                                        * just in front of the head; true head attachment
                                        * carries the offset in the head frame). UNCAPPED negative:
                                        * large negative values pull the camera behind the
                                        * head = over-the-shoulder third person */
static int   g_cfg_cam_weld = 1;       /* cam_weld: 1 = camera welded to the animated head
                                        * bone (true-FP feel: bob, lean, hurt sways). 0 =
                                        * UN-welded TPS-controller feel: horizontal anchor
                                        * = the mover (feet), height low-passed -- no
                                        * animation coupling reaches the camera */
static float g_cfg_eye_up    = 0.0f;   /* eye_up: world-vertical camera raise(+)/lower(-) */
static float g_cfg_eye_shift = 0.0f;   /* eye_shift: camera lateral, +right/-left of the
                                        * look direction (right vector matches the D-strafe
                                        * heading: (-cos yaw, sin yaw)) */
static float g_cfg_move_fwd = 1.0f;    /* move_forward: weld-lag prediction scale
                                        * (1.0 = exact one-frame root-motion lead,
                                        * 0 = off; was a tuned absolute push pre-fix) */
static float g_cfg_move_ref = 60.0f;   /* move_speed_ref: feet units/sec that counts as "full run" */
static float g_cfg_lean     = 0.5f;    /* aim_lean_amount: spine bend gain */
#define VK_TOGGLE_FP      (g_cfg_key_fp)
#define VK_W (g_cfg_key_w)
#define VK_A (g_cfg_key_a)
#define VK_S (g_cfg_key_s)
#define VK_D (g_cfg_key_d)

typedef struct { float x, y, z; } Vec3;
typedef struct { float w, x, y, z; } Quat;   /* Ogre::Quaternion order */
typedef Vec3 *(*get_position_t)(void *self, Vec3 *out);
typedef int   (*get_floor_t)(void *self);   /* Character::getFloor, vtable slot +0x60 */
typedef void (*mainloop_t)(void *gw, float time);
typedef void *(*follow_object_t)(void *cam, void *hand);
typedef void (*stop_follow_t)(void *cam);
/* PlayerInterface::startTrackCharacter(PlayerInterface* this, RootObject* target):
 * the game's NATIVE character tracker -- sets the tracked character so the game's
 * own updateFloorVisibility follows it indoors (interior/floor/roof handled the
 * vanilla way). This is exactly what Kenshi-Direct-Control calls each frame; poking
 * currentFloor by hand fought this system. Resolved by signature (build-independent,
 * 1.0.65 = 0x7f4860). */
typedef void (*start_track_char_t)(void *player, void *target);
/* hand->Building* map lookup: FUN_1409f8050(mapmgr=&DAT_142132f50, hand). Used to
 * get the char's current building (char->vtable+0x1d8 = current-building hand) so
 * the floor look-ahead can clamp to Building+0xA4 (floornum). 1.0.65 verified. */
typedef void *(*hand2bld_t)(void *mapmgr, void *hand);
#define CHAR_VT_CURBLDG_HAND (0x330/8)   /* Character::isStandingOnBuilding vtable slot -> building hand&
                                          * (+0x1d8 was "building the char BELONGS to" = null for wanderers) */
#define BLDG_FLOORNUM_OFF    0xA4        /* Building::floornum (floor COUNT) */
typedef void (*node_set_pos_t)(void *node, const Vec3 *v);   /* local setPosition */
typedef void (*node_set_ori_t)(void *node, const Quat *q);   /* local setOrientation */
typedef void (*node_set_dori_t)(void *node, const Quat *q);  /* world _setDerivedOrientation */
typedef void (*cam_set_fovy_t)(void *camera, const float *rad);
typedef const float *(*cam_get_fovy_t)(void *camera);
typedef void (*cam_set_nearclip_t)(void *camera, float dist);
typedef float (*cam_get_nearclip_t)(void *camera);
typedef void (*pm_setpointer_t)(void *pm, const void *name_stdstr);
typedef void (*pm_setvisible_t)(void *pm, char visible);
typedef const void *(*pm_getdefault_t)(void *pm);   /* returns std::string* */
typedef void *(*pm_getinstance_t)(void);
typedef void *(*gui_getinstance_t)(void);
typedef void *(*gui_createwidget_t)(void *gui, const void *type, const void *skin,
                                    int l, int t, int w, int h, int align,
                                    const void *layer, const void *name);
typedef void (*imgbox_setimage_t)(void *imgbox, const void *texname);
typedef char (*imgbox_setres_t)(void *imgbox, const void *str);   /* setItemResource -> bool */
typedef void (*imgbox_setgrp_t)(void *imgbox, const void *str);   /* setItemGroup */
typedef void (*imgbox_setnm_t)(void *imgbox, const void *str);    /* setItemName */
typedef void (*widget_setcolour_t)(void *widget, const float *rgba);  /* Widget::setColour */
typedef void (*widget_setpos_t)(void *widget, int x, int y);          /* Widget::setPosition */
typedef void (*widget_setvisible_t)(void *widget, char visible);
typedef char (*widget_inhvis_t)(void *widget);   /* Widget::getInheritedVisible */
typedef void *(*rgm_getsingleton_t)(void);
typedef void (*rgm_addlocation_t)(void *rgm, const void *name, const void *loctype,
                                  const void *group, char recursive, char readonly);
typedef void (*rgm_creategroup_t)(void *rgm, const void *group, char inGlobalPool);
typedef void (*rgm_initgroup_t)(void *rgm, const void *group);
typedef void (*charmove_setdest_t)(void *mv, const Vec3 *dest, int pri, char shift);
typedef void (*char_setdest_t)(void *self, const Vec3 *pos, const void *facingQuat);

/* Terrain::getHeight / intersect result (Plugin_Terrain_x64.dll). Retbuf ABI:
 * this=RCX, TerrainHit* ret=RDX, arg=R8. Pure const query, main-thread safe. */
typedef struct {
    unsigned char hit, flag; unsigned short pad;
    Vec3 position;    /* +0x04: ground point (y = height) */
    Vec3 normal;      /* +0x10 */
} TerrainHit;         /* 0x1C bytes */
typedef TerrainHit *(*terrain_getheight_t)(void *self, TerrainHit *ret, const Vec3 *pos);
typedef struct { Vec3 origin; Vec3 dir; } OgreRay;   /* Ogre::Ray, 24 bytes */
typedef TerrainHit *(*terrain_intersect_t)(void *self, TerrainHit *ret, const OgreRay *ray);
typedef void (*cam_update_t)(void *cam, char controlEnabled);
typedef void *(*nearest_town_t)(void *mgr, const Vec3 *pos, int flags);
typedef void *(*town_getlist_t)(void *town, int listType, void *unused);
typedef void (*interior_load_t)(void *buildingInterior);
typedef void (*face_direction_t)(void *mv, const Vec3 *dir);
typedef void (*manual_move_t)(void *mv, const Vec3 *desiredMotion);
/* _setPositionAndTeleport(const Vec3& p, int floor): (this RCX, Vec3* RDX, floor R8) */
typedef void (*set_pos_tele_t)(void *mv, const Vec3 *pos, int floor);
typedef void (*node_set_dpos_t)(void *node, const Vec3 *v);   /* world _setDerivedPosition */
typedef void (*ent_setvisible_t)(void *movable, char visible); /* Ogre::MovableObject::setVisible */
typedef Vec3 *(*node_get_dpos_t)(void *node, Vec3 *ret);      /* world _getDerivedPosition (this=RCX,ret=RDX) */
typedef const Vec3 *(*node_get_pos_t)(void *node);            /* LOCAL getPosition (const Vector3&) */
/* member-struct-return: this=RCX, retbuf=RDX, name=R8 */
typedef Vec3 *(*get_bone_world_t)(void *character, Vec3 *ret, const void *name);

static FILE *g_log;
static uintptr_t g_base;
static mainloop_t g_mainloop_orig;
static void *g_mainloop_target;        /* saved for the re-arm watchdog */
static volatile LONG g_heartbeat;      /* bumped every frame the hook fires */

/* Cooperative hooking. RE_Kenshi's KenshiLib docs: "DO use KenshiLib's built-in
 * function hooking system... DON'T use 3rd-party detour libraries as these can
 * cause issues when multiple plugins hook using different libraries." Our
 * MinHook detours silently never fire alongside RE_Kenshi. Fix: when KenshiLib
 * is loaded (RE_Kenshi present), route our hooks through its exported AddHook
 * (resolved at runtime -- no MSVC link needed); else use MinHook as before. */
#define KLIB_ADDHOOK_SYM "?AddHook@KenshiLib@@YA?AW4HookStatus@1@PEAX0PEAPEAX@Z"
typedef int (*klib_addhook_t)(void *target, void *detour, void **original); /* 0=SUCCESS */
static klib_addhook_t g_klib_addhook;
static int g_wrong_build;               /* set if the exe is neither 1.0.68 nor 1.0.65 */
static int g_rva_gaps;   /* fields a recognised table left at 0 that the sig scan filled */
static int g_build;                     /* 68 or 65 (the detected game build) */
static int g_gog;                       /* 1 = GOG edition of that build */
static follow_object_t g_follow_object;
static stop_follow_t g_stop_following;
static start_track_char_t g_start_track_char;   /* resolved by signature at load */
static hand2bld_t g_hand2bld;                   /* hand->Building* map lookup (table RVA) */
typedef void *(*get_town_t)(void *building);              /* FUN_1400f6be0: building -> Town* */
typedef void  (*set_floorbyte_t)(void *town, void *building, char byte); /* FUN_14092b0f0 */
static get_town_t      g_get_town;
static set_floorbyte_t g_set_floorbyte;
/* prologue of startTrackCharacter; the +0x2a8 ref (48 8B 81 A8 02 00 00) is distinctive.
 * byte 21 (the jump displacement after 75) is wildcarded. */
static const unsigned char STC_SIG[29] = {
    0x40,0x53,0x55,0x56,0x57,0x41,0x54,0x48,0x83,0xec,0x20,0x48,0x8b,0xfa,0x4c,0x8b,
    0xe1,0x48,0x85,0xd2,0x75,0x00,0x48,0x8b,0x81,0xa8,0x02,0x00,0x00 };
static const char STC_MASK[30] = "xxxxxxxxxxxxxxxxxxxxx?xxxxxxx";
static node_set_pos_t g_node_set_pos;   /* Ogre::Node::setPosition (local) */
static node_set_ori_t g_node_set_ori;   /* Ogre::Node::setOrientation (local) */
static node_set_dori_t g_node_set_dori; /* Ogre::Node::_setDerivedOrientation (world) */
static node_set_dpos_t g_node_set_dpos; /* Ogre::Node::_setDerivedPosition (world) */
static ent_setvisible_t g_ent_setvisible; /* Ogre::MovableObject::setVisible (hide arrows) */
typedef char (*ent_getvisible_t)(void *movable);  /* Ogre::MovableObject::getVisible */
static ent_getvisible_t g_ent_getvisible;
static node_get_dpos_t g_node_get_dpos; /* Ogre::Node::_getDerivedPosition (world) */
static node_get_pos_t  g_node_get_pos;  /* Ogre::Node::getPosition (LOCAL) */
static float g_vanilla_zoom = 40.0f;    /* camera-node local Z = vanilla zoom (saved on FP enter) */
static float g_vanilla_alt  = 0.0f;     /* CameraClass altitude (0x60), saved on FP enter */
typedef void (*disable_bone_t)(void *skel, const void *name /*std::string*/, char disable);
static disable_bone_t g_disable_bone;   /* OldSkeletonInstance::disableBone */
typedef void *(*skel_getbone_t)(void *skel, const void *name);  /* -> OldBone* */
typedef const Quat *(*oldnode_getdori_t)(void *node);           /* const Quaternion& */
static skel_getbone_t g_skel_getbone;
static oldnode_getdori_t g_oldnode_getdori;
typedef const Vec3 *(*oldnode_getdpos_t)(void *node);   /* skeleton-space derived pos */
static oldnode_getdpos_t g_oldnode_getdpos;
typedef Vec3 *(*node_getdpos_upd_t)(void *node, Vec3 *ret);  /* FORCES transform recompute */
static node_getdpos_upd_t g_node_getdpos_upd;
typedef Quat *(*node_getdori_t)(void *node, Quat *ret); static node_getdori_t g_node_getdori_v;   /* X1 */
typedef Vec3 *(*node_getdvec_t)(void *node, Vec3 *ret); static node_getdvec_t g_node_getdpos_v, g_node_getdscale_v;
typedef const Quat *(*oldnode_getori_t)(void *node);           /* const Quaternion& (LOCAL) */
typedef void (*oldnode_setori_t)(void *node, const Quat *q);   /* setOrientation(LOCAL) */
typedef void (*oldnode_needupd_t)(void *node, char force);     /* needUpdate(bool) */
typedef void (*oldbone_setmanual_t)(void *bone, char manual);  /* OldBone::setManuallyControlled */
typedef void (*oldnode_setscale_t)(void *node, const Vec3 *scale);  /* OldNode::setScale(Vector3&) */
static oldnode_getori_t   g_oldnode_getori;
static oldnode_setori_t   g_oldnode_setori;
static oldnode_needupd_t  g_oldnode_needupd;
static oldbone_setmanual_t g_oldbone_setmanual;
static oldnode_setscale_t  g_oldnode_setscale;
/* bind-pose access (locomotion retarget) */
typedef const Quat *(*oldnode_getinitori_t)(void *node);  /* initial (=bind) LOCAL orientation */
typedef const Vec3 *(*oldnode_getinitpos_t)(void *node);  /* initial (=bind) LOCAL position */
typedef void *(*oldnode_getparent_t)(void *node);         /* OldNode* parent, NULL at root */
static oldnode_getinitori_t g_oldnode_getinitori;
static oldnode_getinitpos_t g_oldnode_getinitpos;
static oldnode_getparent_t  g_oldnode_getparent;
typedef void (*oldnode_setpos_t)(void *node, const Vec3 *p);
static oldnode_setpos_t     g_oldnode_setpos;
typedef const Vec3 *(*oldnode_getpos_t)(void *node);  /* getPosition (LOCAL); fp-eye-drift diag */
static oldnode_getpos_t     g_oldnode_getpos;
typedef const Vec3 *(*oldnode_getdscale_t)(void *node);
static oldnode_getdscale_t  g_oldnode_getdscale;
/* head-hide (hiddenMask shader constant) */
typedef void *(*mat_gettech_t)(void *material, unsigned short idx);
typedef void *(*tech_getpass_t)(void *technique, unsigned short idx);
typedef void *(*pass_getvpp_t)(void *pass, void *out_sharedptr /*16 bytes; +0 = params*/);
typedef void (*gpup_setnamedi_t)(void *params, const void *name /*std::string*/, int val);
typedef void (*gpup_ignoremiss_t)(void *params, char ignore);
typedef void *(*gpup_finddef_t)(void *params, const void *name, char throw_if_missing);
typedef unsigned short (*mat_numtech_t)(void *material);
typedef unsigned short (*tech_numpass_t)(void *technique);
static mat_gettech_t   g_mat_gettech;
static tech_getpass_t  g_tech_getpass;
static pass_getvpp_t   g_pass_getvpp;
static gpup_setnamedi_t g_gpup_setnamedi;
static gpup_ignoremiss_t g_gpup_ignoremiss;
static gpup_finddef_t  g_gpup_finddef;
static mat_numtech_t   g_mat_numtech;
static tech_numpass_t  g_tech_numpass;
static void  *g_head_params;             /* cached body-material vertex GpuProgramParameters* (has hiddenMask) */
static void  *g_head_params_mat;         /* the Material* we searched (found or not); re-search if it changes */
static int    g_head_dead;               /* head-hide self-disabled after a fault */
static void  *g_player_app;              /* player's AppearanceHuman, cached for the updateHiddenParts hook */
/* AppearanceHuman::updateHiddenParts(this) -- the game recomputes+uploads hiddenMask here
 * on every appearance update and would clobber our head bits; we hook it and re-inject. */
typedef void (*update_hidden_t)(void *app);
static update_hidden_t g_update_hidden_orig;
static const unsigned char UHP_SIG[38] = {
    0x48,0x8b,0xc4,0x55,0x57,0x41,0x54,0x41,0x55,0x41,0x56,0x48,0x8d,0x68,0xa1,0x48,0x81,0xec,
    0xd0,0x00,0x00,0x00,0x48,0xc7,0x45,0xa7,0xfe,0xff,0xff,0xff,0x48,0x89,0x58,0x10,0x48,0x89,0x70,0x18 };
static const char UHP_MASK[39] = "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx";
typedef void *(*get_parent_scenenode_t)(void *movable);
static get_parent_scenenode_t g_get_parent_scenenode;
typedef void *(*entity_getskel_t)(void *entity);
static entity_getskel_t g_entity_getskel;
typedef void (*entity_updateanim_t)(void *entity);   /* Entity::_updateAnimation */
static entity_updateanim_t g_entity_updateanim;
static int g_anim_ent_off = -1;         /* AnimationClass offset of body Entity* (probed) */
static unsigned char g_bone_spine1[32], g_bone_spine2[32], g_bone_neck[32];  /* SSO std::strings */
static unsigned char g_bone_rootspine[32];      /* "Bip01 Spine": facing ref (not controlled) */
static int g_spine_ready;                       /* spine-bend exports + names resolved */
static int g_spine_manual;                      /* bones set manually-controlled (once) */
static Quat g_spine_rest[3];                    /* captured reference pose the aim pivots around */
/* fp-eye-drift: manual bones are not reset by the animation, but its tracks still
 * translate() them each frame -> position must be re-pinned every frame too. */
static Vec3 g_spine_rest_pos[3]; static int g_spine_rest_pos_ok[3];
static float g_spine_pos_fix; static unsigned g_spine_pos_fixes;
static Vec3 g_fwd_local; static int g_have_fwd; /* body forward in root-local frame (calibrated) */
/* --- ranged free-aim (RangedCombatClass::animationUpdate hook) --- */
#define RC_AIMPOS 0x38                          /* RangedCombatClass::currentAimPos (Vector3) */
#define RC_ME     0x68                          /* RangedCombatClass::me (Character*) */
typedef void (*ranged_animupd_t)(void *rc, float ft, Vec3 *aimpos, void *target);
static ranged_animupd_t g_ranged_animupd_orig;
static void *g_player_pc;                       /* player char, cached each frame for hooks */
#define RC_GUN     0x28                         /* RangedCombatClass::gun (GunClass*) */
#define RC_STAT    0x30                         /* RangedCombatClass::currentStat */
#define GUN_AMMO   0x20                         /* GunClass ammo count (shoot decrements it) */
static void manual_fire_update(void *pcx);      /* defined with the hooks below */
static void fp_putdown_update(void *pcx);      /* bug 100: G puts down a carried NPC */
static int fp_aim_point(Vec3 *out);
static void make_mstr(unsigned char *b32, const char *s);
static int g_aim_mode;                          /* R-toggled: weapon raised, manual aim */
/* TABLED: out-of-combat manual aim (R raise + LMB fire). The AI task layer owns
 * the draw/aim pipeline too tightly for field-forcing; revisit in the KenshiLib
 * plugin rewrite. In-combat free-aim (pose/projectile/facing hooks) stays ON. */
#define KFP_MANUAL_AIM 0
/* Verbose periodic diagnostics ([tick]/[foliage]/[spine]/[orient]/[ui]).
 * 0 for release: load-time lines and FAULT/error paths always stay. */
#define KFP_DEBUG_LOG 0
#define VK_AIM_TOGGLE 0x52                      /* R */
#define RC_STATE_OFF 0x00                       /* RangedCombatClass::state (SHOOTING=0) */
static float g_head_above = 2.0f;               /* head Y over feet; small => truly prone/KO */
static Quat g_qref; static int g_have_qref;   /* head orientation while upright */
static float g_down_blend;                     /* 0=upright look .. 1=follow head (ragdoll) */
static int   g_is_down;                         /* ragdolled this frame; freezes look input */
static jmp_buf g_guard_jb;                     /* VEH crash-guard (used from get_head_quat on) */
static volatile LONG g_guard_armed;
static volatile DWORD g_guard_tid;             /* thread that armed the guard */

/* Arm the crash guard for the CURRENT thread. Must run immediately after
 * setjmp(g_guard_jb). Zeroes the jmp_buf Frame qword -- this build's setjmp is
 * _setjmp(jb, rbp), so without this msvcrt longjmp does a real RtlUnwindEx --
 * and records the arming thread so veh_guard ignores exceptions raised on
 * other threads (Kenshi's background save thread throws C++ exceptions as
 * normal control flow; longjmp'ing from there onto the main thread's stack
 * killed the process with STATUS_INVALID_UNWIND_TARGET). */
static void guard_arm(void)
{
    ((unsigned long long *)g_guard_jb)[0] = 0;   /* jmp_buf Frame = 0: plain register restore */
    g_guard_tid = GetCurrentThreadId();
    g_guard_armed = 1;
}
static int g_head_hidden;               /* our head-hide state (>1x fast-forward) */
static void *g_head_hidden_char;        /* the exact character whose head we hid */
static void *g_gear_hid[8];   /* the mesh entities WE hid, so the restore is exact and we
                               * never re-show something the game had hidden on its own */
static int   g_gear_n;
static get_bone_world_t g_get_bone_world;   /* Character::getBoneWorldPosition */
static unsigned char g_head_bone[32];   /* MSVC std::string "Bip01 Head" (SSO) */
static int g_ogre_ready;
static DWORD g_last_tick_ms;
static int g_fp_mode;              /* toggled by VK_TOGGLE_FP edge */
static volatile LONG g_toggle_edge;    /* FP-toggle press latched by the DI poll thread */
static volatile LONG g_kah_inject_click, g_kah_inject_putdown; /* harness-injected presses */
static void fp_manual_combat_tick(void *,float);
static void fp_combat_native_init(void);
static void fp_melee_observe_init(void);
static void fp_melee_manual_init(void);
static void fp_melee_manual_tick(void *,void *,int,int,float);
static void fp_melee_release(void);
static int fp_melee_state_append(char *,size_t,const void *);
static void fp_melee_set_passive(unsigned);
static void fp_melee_spam_start(unsigned,unsigned);
static void fp_melee_click_legal_start(unsigned);
static void fp_melee_set_force_chase(int);
static void fp_melee_swingstat_reset(void);
static int fp_melee_swingstat_append(char *,size_t);
static void fp_melee_hold_ground(void *);
static void fp_melee_observe_swing(void *,float);
static int kah_fp_melee(const char *,int,const char *const *,KAH_Reply *,void *);
static int fp_combat_suppress_shot(void *,void *);
/* T2-T5 FP turret control (kfp_turret.inc) */
static void fp_turret_shot_diag(void *,void *,void *,int,const Vec3 *,const char *);
static void *g_tur_pc,*g_tur_rc,*g_tur_gun,*g_tur_harp;static int g_tur_dispatch;static int g_tur_ui_fire;static unsigned g_tur_updt_suppressed,g_tur_r_ignored;
static int fp_turret_tick(void *,void *,void *,float);static void fp_turret_drop(const char *);static int fp_turret_suppress_shot(void *);
static int kah_fp_turret(const char *,int,const char *const *,KAH_Reply *,void *);
static unsigned g_fp_ctl_shoot_calls;   /* PT18: GunClass::shoot calls (not suppressed) by the FP-controlled char */
static int install_hook(void *,void *,void **);
static int kah_fp_combat(const char *,int,const char *const *,KAH_Reply *,void *);
static void fp_view_input(void);
static int fp_view_is_eye(void);
static int kah_fp_camera(const char *,int,const char *const *,KAH_Reply *,void *);
static void *fp_controlled_char(void *gw);
static int fp_char_in_squad(void *gw, void *pc);
static int game_has_focus(void);
/* TEST ONLY (fp_keys focus on): act as the foreground window. A locked test rig
 * (no foreground window at all) can then run the cursor-hidden/look-mode rows. */
static int g_test_focus;
static void kah_bridge_tick(void);    /* registers the harness test commands */
/* FP control scheme (kfp_controls.inc) */
static int fpc_cam_pre(void *cam,float *yaw,float *pitch);
static void fpc_cam_post(void *cam,float yaw,float pitch);
static int fpc_key_swallow(unsigned dik);
static int fpc_key_owned(unsigned dik);
static int fpc_key_bound_any(unsigned dik);
static void fpc_key_note_swallow(unsigned dik);
static int fpc_suppress_sheathe(void *pc);
static int g_fpc_own_sheathe;   /* kfp_controls.inc: our own (R) sheathe in progress, never suppressed */
static int g_fpc_ranged;         /* kfp_controls.inc: the ranged weapon is the one in hands (PT28 aim-stall log) */
static void fp_controls_tick(void *gw,float dt);
static void fp_controls_init(void);
static int kah_fp_keys(const char *,int,const char *const *,KAH_Reply *,void *);
static void fpc_hud_update(int show);
static void fpc_ctl_menu_update(void *gw);   /* PT20 Control button */
static const char *g_fpc_ui_state;   /* tentative: defined in kfp_controls.inc */
static int g_cfg_state_hud = 1;      /* state_hud: FP combat state label under the crosshair */
static int g_prev_fp;             /* g_fp_mode from last frame (camera_lock edge) */
static int g_ovr_prev;            /* was the FP node override active last frame */
static unsigned g_fp_keys_swallowed, g_fp_last_swallow_dik;
static unsigned g_bound_toggle_reverts;    /* CS05: vanilla FPS toggles from a bound key undone */
static unsigned g_ih_swallowed, g_ih_leak_logs;   /* CS05: bound DIKs dropped at InputHandler::keyDownEvent */
static unsigned g_fp_swallow_ms;           /* GetTickCount of the last swallowed bound key */
static int g_fp_swallow_seen;              /* g_fp_swallow_ms valid */
static unsigned g_kl_installs, g_kl_eaten; /* CS05 path 2: OIS front key listener */
/* FP R holster lowering window (kfp_controls.inc fpc_draw_toggle / fpc_holster_tick), declared here so the
 * viewmodel (kfp_viewmodel.inc, included earlier) can read it. While g_fpc_holster_pending is 1 the weapon is
 * still in the hand (drawn=1, weaponInHands set) and the game's sheathe has NOT run yet: the viewmodel lowers it
 * out of view, g_fpc_holster_prog going 0 -> 1 over g_fpc_holster_delay real seconds; at 1 the sheathe is issued
 * (pending back to 0, the weapon leaves the hand that frame). Cancelled (pending 0, weapon stays) by a second R,
 * a weapon change, KO; finished at once on FP off / control switch. */
static volatile int   g_fpc_holster_pending;
static volatile float g_fpc_holster_prog;
static float g_fpc_holster_delay = 0.3f;     /* fp_keys set holster_delay <s> (0..2), 0 = instant (old behaviour) */
/* PT25 (m67): an R holster sticks out of a fight (kfp_controls.inc): drawWeapon on that char is refused until R draws,
 * a fight starts, control switches or FP goes off; our own draws clear it first (fpc_unheld_clear). */
static int  fpc_suppress_draw(void *pc);
static void fpc_unheld_clear(const char *why);
static const char *g_fpc_hud_hide_why = "none";   /* PT01 (m67): what hid the state HUD flash last (kfp_controls.inc) */
static void kfp_front_listener_tick(void);
static int kfp_front_listener_on(void);
#include "kfp_bound_toggle.h"
static unsigned g_combat_stale_ends;
static unsigned g_freecam_clears;          /* vanilla free/FPS camera cleared on FP enter / after a load */
static int g_freecam_clear_pending;        /* set on world teardown: clear once FP is on again */   /* C05-KO: stale native ranged combat mode ended under manual ownership */   /* fp_state diag: FP-bound keys kept from vanilla binds */
static float g_yaw, g_pitch;      /* accumulated mouse-look angles (radians) */
static cam_set_fovy_t g_cam_set_fovy;
static cam_get_fovy_t g_cam_get_fovy;
static int g_fov_saved;
static float g_fov_default;
static cam_set_nearclip_t g_cam_set_nearclip;
static cam_get_nearclip_t g_cam_get_nearclip;
static cam_get_nearclip_t g_cam_get_farclip;   /* same scalar-return ABI as the near getter */
static int g_nearclip_saved;
static float g_nearclip_default;
static float g_fov_applied = -1.0f;   /* last FOV/near WE wrote: write-on-change only --
                                       * a per-frame re-set invalidates the frustum every
                                       * frame (grass-flicker suspect); reset on FP exit
                                       * so re-entry re-applies over the restored vanilla */
static float g_nc_applied  = -1.0f;
static pm_setpointer_t g_pm_setpointer_orig;   /* MinHook trampoline */
static pm_setvisible_t g_pm_setvisible;
static pm_getdefault_t g_pm_getdefault;
static pm_getinstance_t g_pm_getinstance;
static gui_getinstance_t g_gui_getinstance;
static gui_createwidget_t g_gui_createwidget;
static imgbox_setimage_t g_imgbox_setimage;
static imgbox_setres_t g_imgbox_setres;
static imgbox_setgrp_t g_imgbox_setgrp;
static imgbox_setnm_t  g_imgbox_setnm;
static widget_setcolour_t g_widget_setcolour;
static widget_setpos_t g_widget_setpos;
static widget_setvisible_t g_widget_setvisible;
static widget_inhvis_t g_widget_inhvis;   /* Widget::getInheritedVisible */
static rgm_getsingleton_t g_rgm_getsingleton;
static rgm_addlocation_t g_rgm_addlocation;
static rgm_creategroup_t g_rgm_creategroup;
static rgm_initgroup_t g_rgm_initgroup;
static void *g_crosshair;          /* the ImageBox widget */
static void *g_vignette;           /* fullscreen KO tunnel-vignette ImageBox */
static void *g_black_ov;           /* fullscreen solid-black blackout ImageBox */
static void *g_sneak_icon;         /* screen-space sneak/detection eye (near crosshair) */
static volatile LONG g_sneak_want; /* 0 off | 1 hidden | 2 being-noticed | 3 seen (set per-frame) */
typedef void *(*gui_getsubmain_t)(void *widget);
typedef void (*gui_subsetcolour_t)(void *sub, const float *rgba);
static gui_getsubmain_t   g_gui_getsubmain;
static gui_subsetcolour_t g_gui_subsetcolour;

/* ---- in-game settings UI ---- */
typedef void *(*gui_findwidget_t)(void *gui, const void *name_str, char throw_);
typedef void *(*widget_createwidget_t)(void *self, const void *type, const void *skin,
                                       int l, int t, int w, int h, int align, const void *name);
typedef size_t (*tabctrl_itemcount_t)(void *tabctrl);
typedef void *(*tabctrl_itemat_t)(void *tabctrl, size_t index);
typedef void *(*input_getinst_t)(void);
typedef void *(*mousefocus_t)(void *inputmgr);
typedef void *(*keyfocus_t)(void *inputmgr);
typedef void *(*getparent_t)(void *widget);
typedef void (*scroll_setrange_t)(void *sb, size_t range);
typedef void (*scroll_setpos_t)(void *sb, size_t pos);
typedef size_t (*scroll_getpos_t)(void *sb);
typedef char (*btn_getsel_t)(void *btn);
typedef void (*btn_setsel_t)(void *btn, char sel);
typedef void (*textbox_setcap_t)(void *tb, const void *ustr);
typedef void *(*ustring_ctor_t)(void *self, const char *cstr);
typedef void (*ustring_dtor_t)(void *self);
typedef void (*getenum_t)(void *self, void *enum_retbuf24);   /* by-value: this=RCX, ret=RDX */
typedef const void *(*widget_getname_t)(void *widget);        /* -> const std::string* */
static gui_findwidget_t      g_gui_findwidget;
static widget_createwidget_t g_widget_createwidget;
static tabctrl_itemcount_t   g_tabctrl_itemcount;
static tabctrl_itemat_t      g_tabctrl_itemat;
static input_getinst_t       g_input_getinst;
static mousefocus_t          g_mousefocus;
static keyfocus_t            g_keyfocus;
static getparent_t           g_widget_getparent;
static scroll_setrange_t     g_scroll_setrange;
static scroll_setpos_t       g_scroll_setpos;
static scroll_getpos_t       g_scroll_getpos;
static btn_getsel_t          g_btn_getsel;
static btn_setsel_t          g_btn_setsel;
static textbox_setcap_t      g_textbox_setcap;
static textbox_setcap_t      g_window_setcap;   /* Window::setCaption (title bar) */
static ustring_ctor_t        g_ustring_ctor;
static ustring_dtor_t        g_ustring_dtor;
static getenum_t             g_gui_getenum, g_widget_getenum;
static widget_getname_t      g_widget_getname;

/* Fade helper: MyGUI has no exported Widget::setAlpha, but the main sub-widget
 * accepts an RGBA colour multiply -- alpha included. VEH-unsafe-free (pure
 * pointer walks + one virtual-free exported call). */
static int readable(const void *p, size_t n);
static int char_prone_state(void *pc);   /* fwd: used by the down-state detect before its def */
static int combat_char_unconscious(void *pc);   /* kfp_combat_native.inc: medical KO flag */
static int fp_body_down(void *pc);              /* physics owns the body: no FP writes (C05-KO) */
static void fp_down_note(const char *site, void *pc);
/* Tint a widget (incl. resource ImageBoxes) via Widget::setColour -- the same path
 * the layout's "Colour" property uses; the sub-widget colour path leaves resource
 * images untinted (white). Falls back to sub-colour if setColour is unavailable. */
static void widget_colour(void *w, float r, float g, float b, float a)
{
    if (!w) return;
    if (g_widget_setcolour) { float c[4] = { r, g, b, a }; g_widget_setcolour(w, c); return; }
    if (!g_gui_getsubmain || !g_gui_subsetcolour) return;
    void *sub = g_gui_getsubmain(w);
    if (!readable(sub, 8)) return;
    float rgba[4] = { r, g, b, a };
    g_gui_subsetcolour(sub, rgba);
}
static void widget_alpha(void *w, float a) { widget_colour(w, 1.0f, 1.0f, 1.0f, a); }
static int g_crosshair_red;        /* crosshair currently on the red (enemy) texture */
static int g_pointer_default = 1;  /* current MyGUI pointer is the default (arrow) */
static charmove_setdest_t g_charmove_setdest;  /* CharMovement::setDestination (raw move) */
static char_setdest_t g_char_setdest;          /* teleport+facing placement (unused) */
static int g_movetopos_dead;                   /* set if playerMoveOrderDefault ever faults */
static terrain_getheight_t g_terrain_getheight; /* Terrain::getHeight (Plugin_Terrain dll) */
static terrain_intersect_t g_terrain_intersect; /* Terrain::intersect (ray -> ground point) */
static int g_terrain_dead;                     /* set if the terrain query ever faults */
static cam_update_t g_cam_update_orig;         /* CameraClass::update trampoline */
static volatile LONG g_cam_heartbeat;          /* bumped every camera-update call */
static Vec3 g_last_eye;                        /* FP eye from the previous frame */
static float g_rebase_hold_t;  /* seconds left of post-landing rebase-detect holdoff:
                                * the landing teleport makes the vanilla center node
                                * snap-catch-up over several frames, which forges the
                                * ">50u/frame = Ogre rebase" signature and corrupted T
                                * (the "camera flies away after slope landings" bug) */
static Quat g_last_ori;                        /* FP look from the previous frame */
static int  g_have_eye;                        /* re-assert mid-frame only when valid */
static int  g_calib_wait;                      /* frames until T may recalibrate */
static void *g_gw_cache;                       /* GameWorld* for the mid-frame hook */
static float g_frame_dt;                       /* last frame's dt (stutter diag) */
static int g_ui_mask;                          /* which panel checks are open */
static Vec3 g_eye_sm;                          /* smoothed eye (X/Z low-pass) */
static int  g_eye_sm_ok;
static float g_lead_sm;                        /* smoothed W-ray lead distance */
static nearest_town_t g_nearest_town;          /* TownManager -> nearest Town */
static interior_load_t g_interior_load;        /* BuildingInterior lazy load + keep-alive */
static interior_load_t g_refresh_interior_orig;/* hooked FUN_140561ab0 (refreshInterior) trampoline */
static int g_reveal_dead;                       /* interior-reveal self-disabled after a fault */
static int g_interiors_dead;                   /* set if the interior preload ever faults */
static DWORD g_last_move_ms;
static int g_was_moving;
static int g_was_direct;           /* current WASD hold uses engine direct drive */
static int g_stuck_frames;         /* direct-driving but body not translating (seated/bed/pinned); kfp_stuck.h */
static int g_dbg_prone, g_dbg_in_bed, g_dbg_downed, g_dbg_ko;   /* last locomotion frame, for "fp_move state" */
static int g_eye_from_head;        /* this frame's eye came from the head bone (not fallback) */
/* Direct-drive intent, published by fp_movement and ENFORCED inside the
 * CharMovement::update hook -- applying there (before the original runs) wins
 * the race against combat AI locomotion, which otherwise resets the movement
 * mode every update and freezes WASD during fights. */
static void *g_dm_mv;              /* the player's CharMovement while driving */
static Vec3  g_dm_dir;             /* desired world direction */
static Vec3  g_dm_motion;          /* dir * speed for manualMovement (facing-lock strafe drive) */
static int   g_dm_speed;           /* MoveSpeed: 0 walk / 1 jog / 2 run */
static volatile LONG g_dm_active;  /* WASD held, direct drive on */
static float g_speed_scale = 0.6f; /* scrollwheel throttle: walk (low) .. run (high) */
/* PT04 (Shay 2026-10-08: FP walk/run = the speeds the game uses outside FP for the same char/state): the drive uses
 * the character's OWN speed order (the gait a right-click order gets: run by default, walk/grouped if set), captured
 * when a hold starts and written back when it ends (the old drive left the char on JOG = ~half the vanilla run).
 * Meter: horizontal position rate per GAME second of the hold (rate_avg from 1 s in = steady state). */
static int   g_dm_vso = -1;        /* vanilla speed order of the driven char (-1 = no hold) */
static void *g_dm_vso_pc;
static int   g_gm_gait = -1, g_gm_vso = -1;   /* last hold: gait driven / vanilla order */
static float g_gm_t, g_gm_dist, g_gm_dist1, g_gm_t1, g_gm_win, g_gm_wint, g_gm_winrate, g_gm_peak;
static float g_gm_max, g_gm_des, g_gm_walk, g_gm_cur;
static Vec3  g_gm_last; static int g_gm_have; static LARGE_INTEGER g_gm_qpc;
static unsigned g_gm_holds, g_gm_restores;
static const char *gait_name(int so)
{
    static const char *const n[] = { "walk", "jog", "run", "grouped", "no_change" };
    return so >= 0 && so < 5 ? n[so] : "none";
}
/* True-FP facing lock: body faces the CAMERA (not the movement direction) so WASD
 * produces real strafe/backpedal locomotion; while idle the body stays planted until
 * the camera deviates past the turn-in-place threshold, then swivels at a fixed rate
 * (the loco system animates the foot steps). g_face_dir is re-asserted after
 * CharMovement::update (same last-write-wins trick as direct drive). */
static volatile LONG g_face_active;   /* enforce facing in the charmove-update hook */
static Vec3  g_face_dir;              /* world look dir the body must face */
static float g_face_yaw;              /* commanded body yaw (the TIP state machine) */
static int   g_face_have;             /* g_face_yaw initialized */
static int   g_face_turning;          /* mid turn-in-place swivel */
static Vec3 g_last_dest;           /* last issued move-order target (for the re-issue gate) */
static int  g_have_dest;
static int g_dbg_wheel;
static HINSTANCE g_hinst;
static volatile LONG g_wheel_accum;  /* wheel (±120/notch) accumulated by the DI poll thread */
static float g_last_move_dir;      /* heading of last issued destination (radians) */
static int g_last_move_keys;       /* WASD bitmask of last issued destination */
static float g_move_tx, g_move_tz, g_move_dist;  /* last issued target + its distance */
static float g_dbg_center_y, g_dbg_eye_y;  /* diagnostics for eye-height tuning */
static float g_dbg_head_x, g_dbg_center_x;  /* frame check: head vs center X */
static int g_cursor_hidden;        /* our ShowCursor state */
static int g_ui_prev;              /* dialogue/menu open last frame (edge) */
static int g_ui_open;              /* dialogue/menu open THIS frame (read by the setPointer hook) */
static int g_ui_moveblock;         /* HARD block (control disabled: dialogue/cutscene); halts WASD */
static int g_settings_open;        /* our settings window is showing -> free the cursor like a panel */
static int g_free_toggle;          /* key_free_cursor TOGGLE: 1 = cursor freed (like a panel) */
static unsigned g_free_key_toggles, g_free_key_refocus, g_free_load_resets;   /* PT25 evidence (fp_keys) */
static int g_dbg_control;          /* controlEnabled read, for verification */
/* S03 diag: the five ui_open inputs of the last FP frame (fp_state + [ui] edge log) */
static int g_ui_c_control = 1, g_ui_c_keyfocus, g_ui_c_mask, g_ui_c_pframes;
static unsigned g_ui_open_edges;    /* 0->1 transitions of g_ui_open since launch */
static void *g_settings_win;       /* tentative decl; defined with the settings window */
static const char *ui_why_str(int control, int kf, int panels_gate, int settings, int freet, char *b, size_t n)
{
    snprintf(b, n, "%s%s%s%s%s", control == 0 ? "control," : "", kf ? "key_focus," : "",
             panels_gate ? "panels," : "", settings ? "settings," : "", freet ? "free," : "");
    size_t l = strlen(b);
    if (l) b[l - 1] = 0; else snprintf(b, n, "none");
    return b;
}
static float g_tx, g_tz;           /* game->Ogre translation, calibrated when still */
static int g_have_t;
static float g_prevraw_tx, g_prevraw_tz;  /* prev-frame raw (centerW-feet), for rebase detect */
static KfpWeldPend g_weld_pend;           /* world-scale centre jump awaiting confirmation (kfp_weld.h) */
static int   g_have_prevraw;              /* g_prevraw_* is valid (continuous FP) */
static float g_last_feet_x, g_last_feet_z;  /* prev-frame feet (horizontal), for speed calc */
static int   g_have_last_feet;              /* g_last_feet_* is valid */
static float g_move_speed;                  /* smoothed horizontal feet speed, units/sec */

/* True if p points inside the loaded kenshi_x64.exe image (where real vtables
 * and functions live). Used to reject false-positive "objects" before calling
 * through them — e.g. at the main menu there's no player, but a garbage pointer
 * can still pass readable(); its "vtable" won't be in the module. */
static int in_module(const void *p)
{
    uintptr_t a = (uintptr_t)p;
    return a >= g_base && a < g_base + 0x3000000;   /* exe image ~36MB */
}

/* Minimal .text signature scan available to BOTH editions (the RE plugin's
 * sigscan.h is KFP_RE_PLUGIN-only). pat[i] compared where mask[i]=='x', wildcard
 * where mask[i]=='?'. Returns the VA of the first match, or 0. Used to resolve
 * functions whose per-build RVA we don't have hard-coded (build-independent). */
static uintptr_t kfp_text_scan(const unsigned char *pat, const char *mask, size_t len)
{
    unsigned char *b = (unsigned char *)g_base;
    IMAGE_DOS_HEADER *dos = (IMAGE_DOS_HEADER *)b;
    if (dos->e_magic != IMAGE_DOS_SIGNATURE) return 0;
    IMAGE_NT_HEADERS *nt = (IMAGE_NT_HEADERS *)(b + dos->e_lfanew);
    if (nt->Signature != IMAGE_NT_SIGNATURE) return 0;
    IMAGE_SECTION_HEADER *sec = IMAGE_FIRST_SECTION(nt);
    uintptr_t tbase = 0; size_t tsize = 0;
    for (int i = 0; i < nt->FileHeader.NumberOfSections; i++) {
        if (memcmp(sec[i].Name, ".text", 5) == 0) {
            tbase = g_base + sec[i].VirtualAddress;
            tsize = sec[i].Misc.VirtualSize ? sec[i].Misc.VirtualSize : sec[i].SizeOfRawData;
            break;
        }
    }
    if (!tbase || tsize < len) return 0;
    for (size_t off = 0; off + len <= tsize; off++) {
        const unsigned char *p = (const unsigned char *)(tbase + off);
        size_t j = 0;
        for (; j < len; j++) if (mask[j] == 'x' && p[j] != pat[j]) break;
        if (j == len) return tbase + off;
    }
    return 0;
}

static void logline(const char *fmt, ...)
{
    if (!g_log) return;
    SYSTEMTIME st; GetLocalTime(&st);
    fprintf(g_log, "[%02u:%02u:%02u.%03u] ", st.wHour, st.wMinute, st.wSecond, st.wMilliseconds);
    va_list ap; va_start(ap, fmt); vfprintf(g_log, fmt, ap); va_end(ap);
    fputc('\n', g_log); fflush(g_log);
}

/* Cheap pointer sanity check (no MSVC SEH under mingw). Rejects null /
 * non-canonical / unmapped; enough when driven from a live game frame. */
static int readable(const void *p, size_t n)
{
    if (!p) return 0;
    uintptr_t a = (uintptr_t)p;
    if (a < 0x10000 || a >= 0x0008000000000000ULL) return 0;
    MEMORY_BASIC_INFORMATION mbi;
    if (!VirtualQuery(p, &mbi, sizeof mbi)) return 0;
    if (mbi.State != MEM_COMMIT) return 0;
    if (mbi.Protect & (PAGE_NOACCESS | PAGE_GUARD)) return 0;
    return (uintptr_t)mbi.BaseAddress + mbi.RegionSize >= a + n;
}

/* First player character (index 0) or NULL. */
static int char_valid(void *c)
{
    if (!readable(c, 0x60)) return 0;
    /* Reject anything whose vtable isn't in the exe (menu false positives). */
    void **vt = *(void ***)c;
    return readable(vt, (GETPOS_VTABLE_SLOT + 1) * 8) && in_module(vt);
}

/* The character FP controls: the game's CURRENTLY SELECTED squad member
 * (PlayerInterface::selectedCharacter hand, resolved by matching hand ids
 * against the player-characters list), falling back to squad slot 0. Following
 * the selection is what lets camera-locking another squad member swap FP to
 * them -- v1 hardwired stuff[0] and fought every switch attempt. */
static void *first_player_char(void *gw)
{
    if (!readable(gw, GW_PLAYER + 8)) return NULL;
    void *player = *(void **)((uintptr_t)gw + GW_PLAYER);
    if (!readable(player, PI_PLAYERCHARS + LEK_STUFF + 8)) return NULL;
    uint32_t count = *(uint32_t *)((uintptr_t)player + PI_PLAYERCHARS + LEK_COUNT);
    void **stuff   = *(void ***)((uintptr_t)player + PI_PLAYERCHARS + LEK_STUFF);
    if (count == 0 || count > 4096 || !readable(stuff, 8)) return NULL;

    if (readable((void *)((uintptr_t)player + PI_SELECTED_CHAR + HAND_IDS), 20)) {
        uint32_t *sel = (uint32_t *)((uintptr_t)player + PI_SELECTED_CHAR + HAND_IDS);
        if (sel[0] != 0xb) {                 /* type 0xb = null-hand (nobody) */
            for (uint32_t i = 0; i < count && i < 256; i++) {
                void *c = readable(&stuff[i], 8) ? stuff[i] : NULL;
                if (!c || !readable((void *)((uintptr_t)c + CHAR_HANDLE + HAND_IDS), 20))
                    continue;
                uint32_t *h = (uint32_t *)((uintptr_t)c + CHAR_HANDLE + HAND_IDS);
                if (h[0]==sel[0] && h[1]==sel[1] && h[2]==sel[2]
                    && h[3]==sel[3] && h[4]==sel[4] && char_valid(c))
                    return c;
            }
        }
    }
    return char_valid(stuff[0]) ? stuff[0] : NULL;   /* fallback: squad slot 0 */
}

/* Character::getPosition via live vtable slot 8 (proven ABI). */
/* PT16: Character::isBeingCarried (KenshiLib export); 0 if unresolved. Caller holds the crash guard. */
static int g_fp_carried;
static int fp_char_carried(void *pc)
{
    static unsigned char (*fn)(void *); static int res;
    if (!res) { res = 1; HMODULE k = GetModuleHandleA("KenshiLib.dll");
        fn = k ? (unsigned char (*)(void *))GetProcAddress(k, "?isBeingCarried@Character@@QEBA_NXZ") : NULL; }
    return fn && readable(pc, 8) ? fn(pc) != 0 : 0;
}
static int char_position(void *c, Vec3 *out)
{
    if (!readable(c, 8)) return 0;
    void **vt = *(void ***)c;
    if (!readable(vt, (GETPOS_VTABLE_SLOT + 1) * 8) || !in_module(vt)) return 0;
    get_position_t getpos = (get_position_t)vt[GETPOS_VTABLE_SLOT];
    if (!in_module((void *)getpos)) return 0;   /* real fn lives in .text */
    Vec3 tmp = {0,0,0};
    getpos(c, &tmp);
    /* (0,0,0) = no position (char between bodies/rebuilt): a failed read. Used as
     * feet/head it put the FP eye at the world origin for a frame ("[weld]
     * world-scale centre jump tx-54127"); each 5090 game with that line lost the
     * NavMesh thread ~5 s later (m50 batches K/M). */
    if (tmp.x == 0.0f && tmp.y == 0.0f && tmp.z == 0.0f) {
        static unsigned zero_reads;
        if ((zero_reads++ & 255) == 0)
            logline("[pos] getPosition returned 0,0,0 for %p (read refused, n=%u)", c, zero_reads);
        return 0;
    }
    *out = tmp;
    return 1;
}

static int ui_panels_open(void);   /* forward decl (defined after the VEH guard) */
static void fp_lookat_click_guard(void *gw); /* bug 79, defined after game_has_focus */

/* Clear the game InputHandler's stuck keyboard-modifier flags. The instance's
 * controlEnabled sits at InputHandler+0xD0 (== RVA_INPUT_CONTROLENABLED, already
 * resolved), and ctrl/shift/alt are the next three bytes (+0xD8/+0xD9/+0xDA).
 * Right Alt is AltGr on many layouts: the OS expands it to Left-Ctrl + Right-Alt,
 * and if that phantom Ctrl's key-UP is missed during an FP toggle, InputHandler
 * ::ctrl latches on -- and since move/order commands test CTRL_MASK, EVERYTHING
 * then reads as Ctrl-held = sneak. Clearing the flags un-sticks it. */
static void clear_input_mods(void)
{
    uintptr_t ce = g_base + RVA_INPUT_CONTROLENABLED;   /* InputHandler + 0xD0 */
    if (readable((void *)(ce + 0xA), 1)) {
        *(unsigned char *)(ce + 8) = 0;    /* ctrl  (+0xD8) */
        *(unsigned char *)(ce + 9) = 0;    /* shift (+0xD9) */
        *(unsigned char *)(ce + 0xA) = 0;  /* alt   (+0xDA) */
    }
}

static int g_clearmod_frames;      /* countdown: keep clearing stuck mods after a toggle */

static void poll_input(void)
{
    /* One toggle per physical press, consumed from the ~1kHz DI poll thread's
     * key-DOWN edge (g_toggle_edge). The thread is separate, so it never misses
     * a press even if a bare Alt stalls the game's message loop.
     *
     * A second, per-frame GetAsyncKeyState edge detector used to live here as
     * "belt-and-braces". It RACED the poll thread: the poll edge fired the
     * toggle ON while this frame's own key read still saw the key as up, so
     * g_toggle_was_down stayed 0 and the NEXT frame's async edge re-fired and
     * flipped it straight back OFF -- a single Right Alt press landing as
     * ON->OFF (worse at high fps, where frames are ~10ms apart). Removed; the
     * poll-thread edge alone is reliable and there is no LL hook to fall back
     * from anymore. */
    LONG edge = InterlockedExchange(&g_toggle_edge, 0);
    if (edge) {
        /* AltGr guard: on many EU layouts Right Alt is AltGr (typing € @ etc);
         * don't yank the player into FP while they type in an open panel. */
        if (g_fp_mode || !ui_panels_open()) {
            g_fp_mode = !g_fp_mode;
            logline("[input] FP mode toggled -> %s", g_fp_mode ? "ON" : "OFF");
        }
        /* Toggling with Right Alt (AltGr) can leave InputHandler::ctrl stuck ->
         * everything reads as sneak. Scrub the phantom modifiers for a short
         * window (the missed key-up may lag the toggle by a few frames). */
        g_clearmod_frames = 20;
    }
    if (g_clearmod_frames > 0 && !(GetAsyncKeyState(VK_TOGGLE_FP) & 0x8000)) {
        g_clearmod_frames--;
        clear_input_mods();
    }

    /* [sneak diag] Dump the game input state so we can SEE what "sneak" is:
     * InputHandler modifier/pan bytes (base 0x2133370: +0xD0 controlEnabled,
     * +0xD4 gameMode, +0xD8 ctrl, +0xD9 shift, +0xDA alt, +0xDB..DE arrows) and
     * the selected character's stealthMode (Character+0xD4). Throttled; any
     * physical key held is noted so we can correlate. */
    if (KFP_DEBUG_LOG) {
        static int sd;
        if ((++sd % 30) == 0) {
            unsigned char *ih = (unsigned char *)(g_base + RVA_INPUT_CONTROLENABLED - 0xD0); /* InputHandler base */
            int anykey = 0;
            for (int vk = 0x08; vk <= 0xFE; vk++)
                if ((GetAsyncKeyState(vk) & 0x8000) && vk != VK_TOGGLE_FP) { anykey = vk; break; }
            int stealth = -1;
            if (g_player_pc && readable((void *)((uintptr_t)g_player_pc + 0xD4), 1))
                stealth = *(unsigned char *)((uintptr_t)g_player_pc + 0xD4);
            if (readable(ih, 0xE0))
                logline("[sneak] fp=%d ctrlEn=%d gameMode=%d ctrl=%d shift=%d alt=%d arrows=%d%d%d%d stealthMode=%d heldVK=0x%02X",
                        g_fp_mode, ih[0xD0], ih[0xD4], ih[0xD8], ih[0xD9], ih[0xDA],
                        ih[0xDB], ih[0xDC], ih[0xDD], ih[0xDE], stealth, anykey);
        }
    }
}

/* Throttled read-only observation of everything the FP work will drive. */
static void fp_tick(void *gw)
{
    /* CameraClass instance (holder+0x10). Read its ctor-confirmed fields. */
    void *cam = *(void **)(g_base + RVA_CAM_INSTANCE);
    void *ogre_cam = NULL, *center = NULL, *node = NULL;
    float yaw = 0, pitch = 0, alt = 0;
    unsigned char freecam = 0;
    if (readable(cam, CC_FREECAM + 1)) {
        ogre_cam = *(void **)((uintptr_t)cam + CC_CAMERA);
        center   = *(void **)((uintptr_t)cam + CC_CENTER);
        node     = *(void **)((uintptr_t)cam + CC_NODE);
        yaw      = *(float *)((uintptr_t)cam + CC_YAW);
        pitch    = *(float *)((uintptr_t)cam + CC_PITCH);
        alt      = *(float *)((uintptr_t)cam + CC_ALTITUDE);
        freecam  = *(unsigned char *)((uintptr_t)cam + CC_FREECAM);
    }
    /* cross-check: the scene context's Ogre::Camera should equal cam+0x68 */
    void *scene = *(void **)(g_base + RVA_SCENE_CTX);
    void *scene_cam = readable(scene, SCENE_OGRE_CAMERA + 8)
        ? *(void **)((uintptr_t)scene + SCENE_OGRE_CAMERA) : NULL;

    float speedmult = readable(gw, GW_FRAMESPEED_OFF + 4)
        ? *(float *)((uintptr_t)gw + GW_FRAMESPEED_OFF) : -1.0f;

    void *pc = first_player_char(gw);
    Vec3 pos = {0,0,0};
    int havepos = pc && char_position(pc, &pos);

    int w = (GetAsyncKeyState(VK_W) & 0x8000) != 0;
    int a = (GetAsyncKeyState(VK_A) & 0x8000) != 0;
    int s = (GetAsyncKeyState(VK_S) & 0x8000) != 0;
    int d = (GetAsyncKeyState(VK_D) & 0x8000) != 0;

    /* head-bone offset (head - feet) for tuning the eye position. */
    Vec3 hoff = {0,0,0};
    if (havepos && g_get_bone_world) {
        Vec3 head;
        g_get_bone_world(pc, &head, g_head_bone);
        hoff.x = head.x - pos.x; hoff.y = head.y - pos.y; hoff.z = head.z - pos.z;
    }
    (void)ogre_cam; (void)scene_cam; (void)center; (void)node;
    (void)yaw; (void)pitch; (void)alt; (void)freecam; (void)speedmult;

    logline("[tick] fp=%d pos=(%.1f,%.1f,%.1f) eyeY=%.1f look(yaw=%.2f pitch=%.2f) control=%d wheel=%d speed=%.2f | WASD=%d%d%d%d",
            g_fp_mode, pos.x, pos.y, pos.z,
            g_dbg_eye_y, g_yaw, g_pitch, g_dbg_control, g_dbg_wheel, g_speed_scale, w, a, s, d);
}

/* Stobe bridge. Work/task goals, the goal panel, stobe_action.request / unequip_item.request,
 * the STOP_FIGHT truce, U/Shift+U/Ctrl+U voice markers and lifelike signals run inside
 * Stobe.dll (StobeGoals.cpp) since 2026-10-06. FP combat only asks whether a truce is pending,
 * through Stobe's named export (absent Stobe or older build: no truce). */
typedef int (*stobe_truce_active_t)(void);
static int stobe_fight_truce_active(void)
{
    static stobe_truce_active_t fn;
    static DWORD next_try;
    if (!fn) {
        DWORD now = GetTickCount();
        if (next_try && (LONG)(now - next_try) < 0) return 0;
        next_try = now + 5000;
        HMODULE mod = GetModuleHandleA("Stobe.dll");
        if (mod) fn = (stobe_truce_active_t)(void *)GetProcAddress(mod, "StobeFightTruceActive");
        if (!fn) return 0;
        logline("[stobe] truce bridge: StobeFightTruceActive resolved");
    }
    static int last = -1;
    int on = fn() != 0;
    if (on != last) { if (last >= 0 || on) logline("[stobe] truce bridge: active=%d", on); last = on; }
    return on;
}

/* M1 camera lock. Runs every frame. While FP is on, re-assert followObject on
 * the selected character so the camera tracks it and any vanilla pan that
 * cleared the follow is immediately overridden. On the FP->off edge, release. */
static void camera_lock(void *gw)
{
    void *cam = *(void **)(g_base + RVA_CAM_INSTANCE);
    if (!readable(cam, CC_FREECAM + 1)) return;

    kah_bridge_tick();

    static void *followed;                  /* the actor the FP camera followed last frame */
    if (g_fp_mode) {
        void *pc = fp_controlled_char(gw);   /* camera follows controlled, not inspected */
        if (pc && readable((void *)((uintptr_t)pc + CHAR_HANDLE), 0x20)) {
            g_follow_object(cam, (void *)((uintptr_t)pc + CHAR_HANDLE));
            followed = pc;
        }
    } else if (g_prev_fp) {
        /* FP off: hand the camera to the game's own follow on the actor FP was driving (vanilla
         * pan releases it, as after the vanilla follow key). Releasing the follow here (old code)
         * left the camera centre wherever the FP eye snap had parked it; with W held that is the
         * weld anchor, and a bad anchor left the RTS camera off in an unloaded zone: Kenshi then
         * pauses on "Loading..." forever (4080 b28 C04-FALLBACK). The native follow moves the
         * centre back to the actor in game space, independent of our floating-origin weld. */
        void *pc = (followed && fp_char_in_squad(gw, followed)) ? followed : first_player_char(gw);
        if (pc && readable((void *)((uintptr_t)pc + CHAR_HANDLE), 0x20))
            g_follow_object(cam, (void *)((uintptr_t)pc + CHAR_HANDLE));
        else
            g_stop_following(cam);
        followed = NULL;
        g_have_prevraw = 0;                 /* no rebase compare across an FP gap */
        logline("[cam] FP off: camera handed to the native follow on %p", pc);
    }
    g_prev_fp = g_fp_mode;
}

/* M2 first-person override. After the game's camera update ran this frame,
 * force the camera node to the character's eye position and a mouse-look
 * orientation. Mouse-look v1: absolute cursor position maps to yaw/pitch
 * (read-only, no cursor recenter -> no fight with the engine's own cursor). */
static void mygui_cursor(int visible);   /* forward decl (defined below) */
static void ensure_crosshair(void);

/* --- quaternion helpers (Ogre {w,x,y,z}) --- */
static Quat quat_mul(Quat a, Quat b)
{
    Quat r;
    r.w = a.w*b.w - a.x*b.x - a.y*b.y - a.z*b.z;
    r.x = a.w*b.x + a.x*b.w + a.y*b.z - a.z*b.y;
    r.y = a.w*b.y - a.x*b.z + a.y*b.w + a.z*b.x;
    r.z = a.w*b.z + a.x*b.y - a.y*b.x + a.z*b.w;
    return r;
}
static Quat quat_conj(Quat q) { Quat r = { q.w, -q.x, -q.y, -q.z }; return r; }
static Quat quat_norm(Quat q)
{
    float n = sqrtf(q.w*q.w + q.x*q.x + q.y*q.y + q.z*q.z);
    if (n < 1e-6f) { Quat id = {1,0,0,0}; return id; }
    q.w/=n; q.x/=n; q.y/=n; q.z/=n; return q;
}
/* shortest-arc slerp from a to b by t in [0,1] */
static Quat quat_slerp(Quat a, Quat b, float t)
{
    float d = a.w*b.w + a.x*b.x + a.y*b.y + a.z*b.z;
    if (d < 0) { b.w=-b.w; b.x=-b.x; b.y=-b.y; b.z=-b.z; d=-d; }
    if (d > 0.9995f) {   /* nearly identical -> lerp */
        Quat r = { a.w+(b.w-a.w)*t, a.x+(b.x-a.x)*t, a.y+(b.y-a.y)*t, a.z+(b.z-a.z)*t };
        return quat_norm(r);
    }
    float th = acosf(d), s = sinf(th);
    float wa = sinf((1-t)*th)/s, wb = sinf(t*th)/s;
    Quat r = { wa*a.w+wb*b.w, wa*a.x+wb*b.x, wa*a.y+wb*b.y, wa*a.z+wb*b.z };
    return r;
}

/* Head bone WORLD orientation (version-independent, via Ogre exports).
 * VEH-guarded. Returns 1 + the quaternion on success. */
static int get_head_quat(void *pc, Quat *out)
{
    if (!g_skel_getbone || !g_oldnode_getdori || !pc) return 0;
    void *anim = readable((void *)((uintptr_t)pc + CHAR_ANIM), 8)
        ? *(void **)((uintptr_t)pc + CHAR_ANIM) : NULL;
    if (!readable(anim, ANIM_SKELETON + 8)) return 0;
    void *skel = *(void **)((uintptr_t)anim + ANIM_SKELETON);
    if (!readable(skel, 8)) return 0;
    if (setjmp(g_guard_jb)) { g_skel_getbone = NULL; logline("head-orient read FAULTED -- disabled"); return 0; }
    guard_arm();
    void *bone = g_skel_getbone(skel, g_head_bone);   /* "Bip01 Head" std::string */
    const Quat *q = readable(bone, 8) ? g_oldnode_getdori(bone) : NULL;
    g_guard_armed = 0;
    if (!readable((void *)q, 16)) return 0;
    *out = *q;
    return 1;
}

/* --- Procedural aim-pitch through the spine/neck (PoC) --------------------
 * Additive: each frame read the bone's ANIMATED local orientation, post-
 * multiply a fractional pitch about a local axis, write it back, and flag the
 * derived transforms dirty so skinning + the head-welded camera pick it up.
 * No setManuallyControlled -> we layer on the live walk/run animation.
 * The local pitch axis + gain + sign are tuned in-game (Biped bones permuted).
 * VEH-guarded; pitch>0 = looking down. */
#define SPINE_BEND_GAIN (g_cfg_lean)  /* total lean as a fraction of look-pitch (config) */
#define SPINE_ROLL_UP   0.30f     /* roll gain, looking up   (pitch<0) */
#define SPINE_ROLL_DOWN 0.30f     /* roll gain, looking down (pitch>0) */
#define SPINE_ROLL_BIAS 0.0f      /* |pitch| roll, SAME direction both ways */

/* Rotate a vector by a quaternion (v' = q * v * conj(q)), efficient form. */
static Vec3 quat_rotvec(Quat q, Vec3 v)
{
    Vec3 u = { q.x, q.y, q.z };
    Vec3 t = { 2.0f*(u.y*v.z - u.z*v.y), 2.0f*(u.z*v.x - u.x*v.z), 2.0f*(u.x*v.y - u.y*v.x) };
    Vec3 r = { v.x + q.w*t.x + (u.y*t.z - u.z*t.y),
               v.y + q.w*t.y + (u.z*t.x - u.x*t.z),
               v.z + q.w*t.z + (u.x*t.y - u.y*t.x) };
    return r;
}

/* ---- LANDING ABSORB state (Destreza landing port; fed by the fall driver,
 * consumed by the locomotion IK below -- declared before the include). A soft
 * fall landing sets amt from the impact velocity; the loco layer dips the
 * pelvis on an envelope, the leg IK keeps the feet planted (knees bend), and
 * the head-welded FP camera dips with it. ---- */
static float g_land_amt;   /* 0..1 impact severity of the last soft landing */
static float g_land_age;   /* seconds since that landing */
static float g_land_dip;   /* current pelvis dip (skeleton units, <= 0) */
static float g_loco_reassert_t; /* WINDOW (seconds): re-claim owned bones (setManual +
                               * disableBone) EVERY loco frame while > 0. Set after fall
                               * landings -- the landing teleport's render update (and a
                               * ragdoll cycle) re-register the game's animation layers,
                               * clearing our per-bone disable flags; the game's anims
                               * then fight the loco writes (perturbed stuck walk). A
                               * one-shot re-assert loses the race when the engine's
                               * re-registration lands a few frames AFTER our landing
                               * commit, so hold the claim through the whole window. */

/* custom full-body FP locomotion (Destreza Humanoid_ clips retargeted onto Bip01).
 * Included here, after the Vec3/Quat helpers it builds on. See re/LOCOMOTION_SPEC.md. */
static void make_mstr(unsigned char *b32, const char *s);        /* fwd decl (defined ~line 3018) */
static void *make_mstr_long(unsigned char *b32, const char *s);  /* heap std::string for names >=16 chars */
/* ---- EMBEDDED ASSET RESOURCES (see kenshifp.rc) ---------------------------
 * The clip pack and every UI image are compiled into the DLL, so a KenshiFP
 * install is a single binary that cannot be broken by a missing side file --
 * which is what the Steam Workshop item needs (users never assemble that
 * folder by hand). Real files still WIN when present: locomotion.kfa next to
 * the DLL overrides the embedded pack, and any image already in kenshifp/ is
 * left alone, so custom bakes and reskins keep working without a rebuild. */
#define KFP_RES_KFA 100
static const struct { int id; const char *name; } KFP_RES_IMG[] = {
    { 200, "blk0.png" },      { 201, "blk1.png" },      { 202, "blk2.png" },
    { 203, "blk3.png" },      { 204, "blk4.png" },      { 205, "blk5.png" },
    { 206, "blk6.png" },      { 207, "blk7.png" },      { 208, "blk8.png" },
    { 209, "blk9.png" },      { 210, "crosshair.png" }, { 211, "vignette.png" },
    { 212, "xhair_grn.png" }, { 213, "xhair_red.png" }, { 214, "xhair_ylw.png" },
};

/* Write the embedded images into "<dll dir>\kenshifp\" if they are not
 * already there. Ogre's resource system loads GUI textures from a FileSystem
 * location (it has no memory-stream path we can reach from here), so the
 * images must exist as files -- this just means the DLL ships its own copy and
 * lays it down once, instead of the user having to keep the folder together.
 * Only missing files are written; anything the user replaced is preserved. */
static void kfp_extract_assets(void)
{
    wchar_t dllw[MAX_PATH];
    DWORD n = GetModuleFileNameW(g_hinst, dllw, MAX_PATH);
    if (!n || n >= MAX_PATH) return;
    char dlla[MAX_PATH];
    if (WideCharToMultiByte(CP_UTF8, 0, dllw, -1, dlla, sizeof dlla, NULL, NULL) <= 0) return;
    char *slash = strrchr(dlla, '\\');
    if (!slash) return;
    *slash = 0;
    char dir[MAX_PATH];
    snprintf(dir, sizeof dir, "%s\\kenshifp", dlla);
    CreateDirectoryA(dir, NULL);                  /* ok if it already exists */
    int wrote = 0, failed = 0;
    for (int i = 0; i < (int)(sizeof KFP_RES_IMG / sizeof KFP_RES_IMG[0]); i++) {
        char path[MAX_PATH];
        snprintf(path, sizeof path, "%s\\%s", dir, KFP_RES_IMG[i].name);
        if (GetFileAttributesA(path) != INVALID_FILE_ATTRIBUTES) continue;   /* user copy wins */
        HRSRC r = FindResourceA(g_hinst, MAKEINTRESOURCEA(KFP_RES_IMG[i].id), RT_RCDATA);
        HGLOBAL h = r ? LoadResource(g_hinst, r) : NULL;
        const void *p = h ? LockResource(h) : NULL;
        DWORD sz = r ? SizeofResource(g_hinst, r) : 0;
        if (!p || !sz) { failed++; continue; }
        FILE *f = fopen(path, "wb");
        if (!f) { failed++; continue; }
        if (fwrite(p, 1, sz, f) == sz) wrote++; else failed++;
        fclose(f);
    }
    if (wrote || failed)
        logline("[assets] extracted %d embedded image(s) to %s%s",
                wrote, dir, failed ? " (some FAILED -- read-only install?)" : "");
}

#include "kfp_locomotion.h"
#include "kfp_cmd_args.h"
#include "kfp_free_key.h"
#include "kfp_stuck.h"
#include "kfp_fling.h"
#include "kfp_control.inc"
#include "kfp_combat_probe.inc" /* passive native lifecycle prerequisite */
#include "kfp_meshray.h"   /* true-geometry .mesh triangle raycasts (task #22) */

/* Perch ground for the loco layer: while standing on a mesh, foot-IK probes
 * resolve against the perch entity's TRUE triangles (fast: one cached mesh,
 * no scene query). Falls through (-99999) to the engine query on a miss so
 * probes that hang past the rock's edge still read the terrain. */
static float perch_ground_fn(const Vec3 *p)
{
    return meshray_perch_column(p->x, p->y, p->z);
}

static void bend_spine(void *pc, float pitch)
{
    if (!g_spine_ready || !g_skel_getbone || !pc) return;
    void *anim = readable((void *)((uintptr_t)pc + CHAR_ANIM), 8)
        ? *(void **)((uintptr_t)pc + CHAR_ANIM) : NULL;
    if (!readable(anim, ANIM_SKELETON + 8)) return;
    void *skel = *(void **)((uintptr_t)anim + ANIM_SKELETON);
    if (!readable(skel, 8)) return;

    float total = pitch * SPINE_BEND_GAIN;    /* look down (pitch>0) -> bend forward */
    /* Bend only spine1+spine2; the neck and head animate naturally on top of the
     * lean. Manually controlling the neck warped the neck/head junction (our
     * neck rotation fighting whatever drives the head). */
    struct { unsigned char *nm; float w; const char *tag; } chain[] = {
        { g_bone_spine1, 0.5f, "spine1" },
        { g_bone_spine2, 0.5f, "spine2" },
    };
    const int NB = (int)(sizeof(chain) / sizeof(chain[0]));
    if (setjmp(g_guard_jb)) { g_spine_ready = 0; logline("spine-bend FAULTED -- disabled"); return; }
    guard_arm();
    static int dbg;
    int logit = KFP_DEBUG_LOG && ((++dbg) % 120) == 0;

    void *bones[4];
    for (int i = 0; i < NB; i++) {
        bones[i] = g_skel_getbone(skel, chain[i].nm);
        if (!readable(bones[i], 8)) { g_guard_armed = 0; return; }
    }

    /* One-time: capture each bone's current (animated) local pose as the aim
     * reference, then mark the bones manually-controlled so the animation stops
     * resetting them each frame -- otherwise our writes are wiped before the
     * render (only our own head-position read saw them). */
    if (!g_spine_manual) {
        if (!g_oldbone_setmanual) { g_guard_armed = 0; return; }
        for (int i = 0; i < NB; i++) {
            const Quat *lq = g_oldnode_getori(bones[i]);
            g_spine_rest[i] = readable((void *)lq, 16) ? *lq : (Quat){ 1, 0, 0, 0 };
            {   /* fp-eye-drift: bind position = what the vanilla reset would restore */
                const Vec3 *ip = g_oldnode_getinitpos ? g_oldnode_getinitpos(bones[i]) : NULL;
                g_spine_rest_pos_ok[i] = readable((void *)ip, 12);
                if (g_spine_rest_pos_ok[i]) g_spine_rest_pos[i] = *ip;
            }
            g_oldbone_setmanual(bones[i], 1);
        }
        g_spine_manual = 1;
        logline("[spine] bones set manuallyControlled; rest poses captured");
    }

    /* WORLD pitch axis = character's LATERAL (left-right) axis. Deriving it from
     * g_yaw alone isn't rotation-agnostic: the body's TRUE facing (set by the
     * game when you turn in place) doesn't track g_yaw through a 180, so the bend
     * inverted when facing behind. Instead: calibrate the lateral direction once
     * in the root spine's LOCAL frame (from g_yaw, valid while idle-facing), then
     * each frame rotate it by the root's CURRENT world orientation -- so it
     * follows the real body facing through any turn. Root spine isn't one of our
     * controlled bones, so its derived reflects the animation's true facing. */
    Vec3 world_axis, fwd_w;
    void *rootb = g_skel_getbone(skel, g_bone_rootspine);
    const Quat *rdq = readable(rootb, 8) ? g_oldnode_getdori(rootb) : NULL;
    if (readable((void *)rdq, 16) && g_have_fwd) {
        /* g_fwd_local is calibrated by calibrate_spine_fwd() while the weapon is
         * SHEATHED and the body idle/level -- the only time "body faces g_yaw"
         * actually holds. NEVER calibrate here: with a weapon drawn the combat
         * stance blades the body sideways, and a skewed axis turns pitch into
         * roll (the session-dependent weapon-roll ghost we chased with gains). */
        Vec3 fw = quat_rotvec(*rdq, g_fwd_local);          /* body forward -> world, tracks facing */
        float hl = sqrtf(fw.x*fw.x + fw.z*fw.z);
        if (hl < 1e-4f) hl = 1e-4f;
        fw.x /= hl; fw.z /= hl;                             /* flatten to horizontal, normalize */
        fwd_w = (Vec3){ fw.x, 0.0f, fw.z };                /* forward axis for roll correction */
        /* lateral = forward x up: guaranteed perpendicular to forward AND
         * horizontal -> pitch about it is pure, no roll (any calibration error
         * becomes an imperceptible yaw offset instead of visible weapon roll).
         * Sign: a positive look-down pitch (g_pitch>0) must bend the torso
         * FORWARD/down, so the axis is forward x up = (-fw.z,0,fw.x); the
         * opposite (up x forward) inverted the lean (looked-down -> leaned back). */
        world_axis = (Vec3){ -fw.z, 0.0f, fw.x };
    } else {
        world_axis = (Vec3){ -cosf(g_yaw), 0.0f, sinf(g_yaw) };  /* fallback */
        fwd_w      = (Vec3){ sinf(g_yaw), 0.0f, cosf(g_yaw) };
    }

    /* Rebuild each bone's REST-pose world orientation from the root's live derived
     * and the captured rest locals (NOT the bent derived), and project the axis
     * through that. Reading the bent derived fed the bend back into the axis and
     * leaked pitch into roll; the rest chain is feedback-free -> pure pitch. */
    Quat rest_der = readable((void *)rdq, 16) ? *rdq : (Quat){ 1, 0, 0, 0 };  /* root, live facing */
    for (int i = 0; i < NB; i++) {
        rest_der = quat_norm(quat_mul(rest_der, g_spine_rest[i])); /* bone i rest world orient */
        Vec3 Al = quat_rotvec(quat_conj(rest_der), world_axis);   /* world axis -> rest frame */
        float a = total * chain[i].w;
        float c = cosf(a * 0.5f), s = sinf(a * 0.5f);
        Quat dpitch = { c, Al.x*s, Al.y*s, Al.z*s };
        /* Roll correction about the forward axis, proportional to this bone's
         * pitch, to cancel the CW/CCW weapon twist the arm rig adds. */
        Vec3 Fl = quat_rotvec(quat_conj(rest_der), fwd_w);
        float rollg = (pitch < 0.0f ? SPINE_ROLL_UP : SPINE_ROLL_DOWN);
        float ar = rollg * a + SPINE_ROLL_BIAS * fabsf(a);   /* linear (flips) + bias (same both ways) */
        float cr = cosf(ar * 0.5f), sr = sinf(ar * 0.5f);
        Quat droll = { cr, Fl.x*sr, Fl.y*sr, Fl.z*sr };
        Quat d  = quat_norm(quat_mul(dpitch, droll));
        Quat nq = quat_norm(quat_mul(g_spine_rest[i], d)); /* rest * (pitch + roll correct) */
        g_oldnode_setori(bones[i], &nq);
        if (g_oldnode_setpos && g_spine_rest_pos_ok[i]) {   /* fp-eye-drift */
            const Vec3 *cp = g_oldnode_getpos ? g_oldnode_getpos(bones[i]) : NULL;
            if (readable((void *)cp, 12)) {
                float dx = cp->x - g_spine_rest_pos[i].x, dy = cp->y - g_spine_rest_pos[i].y,
                      dz = cp->z - g_spine_rest_pos[i].z;
                float dl = sqrtf(dx*dx + dy*dy + dz*dz);
                if (i == 0) g_spine_pos_fix = dl; else if (dl > g_spine_pos_fix) g_spine_pos_fix = dl;
                if (dl > 1e-4f) g_spine_pos_fixes++;
            }
            g_oldnode_setpos(bones[i], &g_spine_rest_pos[i]);
        }
        g_oldnode_needupd(bones[i], 1);
        if (logit)
            logline("[spine] %s a=%.2f rollg=%.2f Al=(%.2f,%.2f,%.2f) set=(%.3f,%.3f,%.3f,%.3f)",
                    chain[i].tag, a, rollg, Al.x, Al.y, Al.z, nq.w, nq.x, nq.y, nq.z);
    }
    g_guard_armed = 0;
}

/* Calibrate the body-forward axis in root-spine local frame. Call ONLY when
 * "body faces g_yaw" holds: weapon sheathed, idle, looking level (orient-to-
 * control has squared the body to the camera). The result is a skeleton
 * constant, so it persists across draw/sheathe and only refreshes when the
 * conditions are met again. */
static void calibrate_spine_fwd(void *pc)
{
    if (!g_spine_ready || !g_skel_getbone || !pc) return;
    void *anim = readable((void *)((uintptr_t)pc + CHAR_ANIM), 8)
        ? *(void **)((uintptr_t)pc + CHAR_ANIM) : NULL;
    if (!readable(anim, ANIM_SKELETON + 8)) return;
    void *skel = *(void **)((uintptr_t)anim + ANIM_SKELETON);
    if (!readable(skel, 8)) return;
    if (setjmp(g_guard_jb)) { g_guard_armed = 0; return; }
    guard_arm();
    void *rootb = g_skel_getbone(skel, g_bone_rootspine);
    const Quat *rdq = readable(rootb, 8) ? g_oldnode_getdori(rootb) : NULL;
    if (readable((void *)rdq, 16)) {
        g_fwd_local = quat_rotvec(quat_conj(*rdq),
                                  (Vec3){ sinf(g_yaw), 0.0f, cosf(g_yaw) });
        if (!g_have_fwd) logline("[spine] fwd axis calibrated (sheathed+idle+level)");
        g_have_fwd = 1;
    }
    g_guard_armed = 0;
}

/* Hand the spine/neck back to the animation. Called when we leave active FP
 * (free cam, FP off) -- otherwise the frozen manual pose flails as the body
 * turns. Re-entering FP re-captures rest poses via bend_spine; the calibrated
 * forward axis persists (it's a skeleton constant, not per-stance state). */
static void release_spine(void *pc)
{
    if (!g_spine_manual) return;
    g_spine_manual = 0;
    if (!g_oldbone_setmanual || !g_skel_getbone || !pc) return;
    void *anim = readable((void *)((uintptr_t)pc + CHAR_ANIM), 8)
        ? *(void **)((uintptr_t)pc + CHAR_ANIM) : NULL;
    if (!readable(anim, ANIM_SKELETON + 8)) return;
    void *skel = *(void **)((uintptr_t)anim + ANIM_SKELETON);
    if (!readable(skel, 8)) return;
    unsigned char *names[3] = { g_bone_spine1, g_bone_spine2, g_bone_neck };
    if (setjmp(g_guard_jb)) { g_guard_armed = 0; return; }
    guard_arm();
    for (int i = 0; i < 3; i++) {
        void *b = g_skel_getbone(skel, names[i]);
        if (readable(b, 8)) g_oldbone_setmanual(b, 0);
    }
    g_guard_armed = 0;
    logline("[spine] manual control released");
}

/* Find the character's body Ogre::Entity on the AnimationClass by PROBING its
 * members: the right pointer is the one whose Entity::getSkeleton() equals the
 * skeleton we already know (anim+0xB8). Self-validating -- no vtable-slot or
 * offset guessing. Probed once, then cached. Each candidate call VEH-guarded.
 * NOTE: clobbers g_guard_jb; call OUTSIDE any other guarded region. */
static void *find_body_entity(void *animc)
{
    if (!g_entity_getskel || !readable(animc, ANIM_SKELETON + 8)) return NULL;
    void *skel = *(void **)((uintptr_t)animc + ANIM_SKELETON);
    if (!skel) return NULL;
    if (g_anim_ent_off == -2) return NULL;   /* probe already failed for good */
    if (g_anim_ent_off >= 0)
        return readable((void *)((uintptr_t)animc + g_anim_ent_off), 8)
            ? *(void **)((uintptr_t)animc + g_anim_ent_off) : NULL;
    for (int off = 0; off < 0x300; off += 8) {
        if (!readable((void *)((uintptr_t)animc + off), 8)) break;
        void *p = *(void **)((uintptr_t)animc + off);
        if (!readable(p, 0x100)) continue;
        void *sk;
        if (setjmp(g_guard_jb)) { g_guard_armed = 0; continue; }
        guard_arm();
        sk = g_entity_getskel(p);
        g_guard_armed = 0;
        if (sk == skel) {
            g_anim_ent_off = off;
            logline("[aim] body Entity found at anim+0x%x -> %p", off, p);
            return p;
        }
    }
    logline("[aim] body Entity probe FAILED (getskel=%p)", (void *)g_entity_getskel);
    g_anim_ent_off = -2;   /* don't re-probe every frame */
    return NULL;
}

/* --- DirectInput mouse (FP look deltas) ---------------------------------
 * The one delta source that both FEELS right and COEXISTS with the game:
 *  - RegisterRawInputDevices stole Wine-dinput's registration -> right-click
 *    broke (one raw-input target per device per process).
 *  - Cursor-warp / LL-hook positions ride the laggy coalesced cursor stream
 *    -> sluggish-then-teleport look.
 *  - A second NON-EXCLUSIVE BACKGROUND DirectInput mouse device reads the
 *    same high-rate relative stream the game does; Wine serves both. */
static IDirectInputDevice8A *g_di_mouse;
static int g_di_ready;
static const GUID g_guid_sysmouse =
    {0x6F1D2B60,0xD5A0,0x11CF,{0xBF,0xC7,0x44,0x45,0x53,0x54,0x00,0x00}};
static const GUID g_iid_idi8a =
    {0xBF798030,0x483A,0x4DA2,{0xAA,0x99,0x5D,0x64,0xED,0x36,0x97,0x00}};
typedef HRESULT (WINAPI *di8create_t)(HINSTANCE, DWORD, REFIID, LPVOID *, LPUNKNOWN);

static DWORD WINAPI di_poll_thread(void *unused);   /* defined below */
static int g_di_thread_on;

static void ensure_dinput(void)
{
    static int tried;
    if (g_di_ready || tried >= 600) return;   /* retry through early frames */
    tried++;
    HWND w = FindWindowA("OgreD3D11Wnd", NULL);
    if (!w) w = GetForegroundWindow();
    if (!w) return;
    if (!g_di_mouse) {
        HMODULE dll = LoadLibraryA("dinput8.dll");
        di8create_t create = dll ? (di8create_t)GetProcAddress(dll, "DirectInput8Create") : NULL;
        IDirectInput8A *di = NULL;
        if (!create || FAILED(create(g_hinst, DIRECTINPUT_VERSION, &g_iid_idi8a,
                                     (void **)&di, NULL)) || !di) { tried = 600; return; }
        if (FAILED(di->lpVtbl->CreateDevice(di, &g_guid_sysmouse, &g_di_mouse, NULL))
            || !g_di_mouse) { tried = 600; return; }
        g_di_mouse->lpVtbl->SetDataFormat(g_di_mouse, &c_dfDIMouse2);
    }
    g_di_mouse->lpVtbl->SetCooperativeLevel(g_di_mouse, w,
                                            DISCL_BACKGROUND | DISCL_NONEXCLUSIVE);
    if (SUCCEEDED(g_di_mouse->lpVtbl->Acquire(g_di_mouse))) {
        g_di_ready = 1;   /* the poll thread (started at load) now reads the mouse */
        logline("DirectInput mouse acquired (non-exclusive background)");
    }
}

/* Relative deltas since the previous call (mouse axes default to relative).
 * Called ONLY from the poll thread once it starts (single GetDeviceState
 * consumer -- concurrent calls would split deltas unpredictably). */
static int di_get_deltas(LONG *dx, LONG *dy, LONG *dz)
{
    if (!g_di_ready) return 0;
    DIMOUSESTATE2 st;
    if (FAILED(g_di_mouse->lpVtbl->GetDeviceState(g_di_mouse, sizeof st, &st))) {
        g_di_mouse->lpVtbl->Acquire(g_di_mouse);   /* lost: re-acquire, skip frame */
        return 0;
    }
    *dx = st.lX; *dy = st.lY; *dz = st.lZ;   /* lZ = wheel (±120/notch, like WM_MOUSEWHEEL) */
    return 1;
}

/* True while a window of OUR process is the foreground window. The DirectInput
 * mouse is DISCL_BACKGROUND (keeps reporting even unfocused), so without this the
 * poll thread would accumulate deltas from mouse movement in OTHER apps while the
 * player is alt-tabbed -- on return the camera had spun away, unrecoverable. */
/* Bug 79: in FP a captured-cursor left click on a squad member made Kenshi
 * select her, and FP follows the selection. Revert such a switch so looking at
 * and clicking a squad member never takes control; portrait clicks (free
 * cursor) still switch. */
#define KLIB_PI_SELECTPC_SYM "?_selectPlayerCharacter@PlayerInterface@@QEAAXPEAVRootObject@@_N1@Z"
typedef void (*pi_selectpc_t)(void *, void *, unsigned char, unsigned char);
#define KLIB_GUI_SHOWSTATS_SYM "?showCharacterStatsWindow@ForgottenGUI@@QEAAXAEBVhand@@@Z"
#define RVA_GUI_INSTANCE 0x21337b0u /* static ForgottenGUI instance (see RVA_GUI_* above) */
typedef void (*gui_showstats_t)(void *, const void *);
static int game_has_focus(void);

/* ---- Kenshi Automation Harness bridge (TEST ONLY) ----
 * fp_mode / fp_click / fp_putdown / fp_state, registered only when
 * AutomationHarness.dll is loaded (retried once a second). Handlers just latch
 * presses; the FP code consumes them on its next frame. */
static KAH_Api g_kah;
static int g_kah_connected;
static DWORD g_kah_last_try;

static int kah_fp_mode(const char *id, int argc, const char *const *argv, KAH_Reply *r, void *u)
{
    (void)id; (void)u;
    if (argc < 2 || (_stricmp(argv[1], "on") && _stricmp(argv[1], "off"))) {
        r->append(r, "usage: fp_mode on|off");
        return KAH_ERROR;
    }
    int want = !_stricmp(argv[1], "on");
    if (want == (g_fp_mode != 0)) {
        r->append(r, want ? "FP mode already ON" : "FP mode already OFF");
        return KAH_OK;
    }
    InterlockedExchange(&g_toggle_edge, 1);
    r->append(r, want ? "FP mode toggling ON (next frame; log [input] FP mode toggled)"
                      : "FP mode toggling OFF (next frame)");
    return KAH_OK;
}

static int kah_fp_click(const char *id, int argc, const char *const *argv, KAH_Reply *r, void *u)
{
    (void)id; (void)argc; (void)argv; (void)u;
    if (!g_fp_mode) { r->append(r, "FP mode is off (fp_mode on first)"); return KAH_ERROR; }
    InterlockedExchange(&g_kah_inject_click, 1);
    r->append(r, "left click injected: select a squad member within 1 s (bug 79 guard)");
    return KAH_OK;
}

static int kah_fp_putdown(const char *id, int argc, const char *const *argv, KAH_Reply *r, void *u)
{
    (void)id; (void)argc; (void)argv; (void)u;
    if (!g_fp_mode) { r->append(r, "FP mode is off (fp_mode on first)"); return KAH_ERROR; }
    InterlockedExchange(&g_kah_inject_putdown, 1);
    r->append(r, "G injected (bug 100 put down; log [fp] put down)");
    return KAH_OK;
}

static int kah_fp_state(const char *id, int argc, const char *const *argv, KAH_Reply *r, void *u)
{
    (void)id; (void)u;
    char b[768], wb[64];
    const int fsa = kfp_fp_state_args(argc, argv);   /* argv[0] = command name */
    if (fsa == KFP_FPSTATE_FREE_OFF) {
        /* S03 recovery: drop a stuck free-cursor toggle / our settings window */
        int was_free = g_free_toggle, was_set = g_settings_open;
        g_free_toggle = 0;
        if (g_settings_open) {
            g_settings_open = 0;
            if (g_settings_win && g_widget_setvisible) g_widget_setvisible(g_settings_win, 0);
        }
        snprintf(b, sizeof(b), "free cleared (free %d->0, settings %d->0)", was_free, was_set);
        r->append(r, b);
        return KAH_OK;
    }
    if (fsa == KFP_FPSTATE_USAGE) { r->append(r, "usage: fp_state [free off]"); return KAH_ERROR; }
    int pgate = g_ui_c_mask && g_ui_c_pframes >= 8;
    /* CS06 diag: why the camera hook is (in)active. active = fp_mode && controlled && !freecam */
    int freecam = -1;
    if (g_base) {
        void *cam = *(void **)(g_base + RVA_CAM_INSTANCE);
        if (readable(cam, CC_FREECAM + 1)) freecam = *(unsigned char *)((uintptr_t)cam + CC_FREECAM);
    }
    int controlled = (g_fp_mode && g_gw_cache) ? (fp_controlled_char(g_gw_cache) != NULL) : 0;
    snprintf(b, sizeof(b), "fp_mode=%d cursor_hidden=%d ui_open=%d ui_why=%s control=%d key_focus=%d"
             " panels=0x%03x panel_frames=%d settings=%d free=%d ui_open_edges=%u"
             " active=%d freecam=%d ovr_prev=%d controlled=%d focus=%d keys_swallowed=%u last_swallow_dik=0x%02X"
             " freecam_clears=%u bound_toggle_reverts=%u ih_swallowed=%u kl_front=%d kl_eaten=%u",
             g_fp_mode ? 1 : 0, g_cursor_hidden ? 1 : 0, g_ui_open ? 1 : 0,
             ui_why_str(g_ui_c_control, g_ui_c_keyfocus, pgate, g_settings_open, g_free_toggle, wb, sizeof(wb)),
             g_ui_c_control, g_ui_c_keyfocus, g_ui_c_mask, g_ui_c_pframes, g_settings_open ? 1 : 0,
             g_free_toggle ? 1 : 0, g_ui_open_edges,
             (g_fp_mode && controlled && freecam == 0) ? 1 : 0, freecam, g_ovr_prev ? 1 : 0, controlled,
             game_has_focus() ? 1 : 0, g_fp_keys_swallowed, g_fp_last_swallow_dik, g_freecam_clears,
             g_bound_toggle_reverts, g_ih_swallowed, kfp_front_listener_on(), g_kl_eaten);
    r->append(r, b);
    return KAH_OK;
}

static int kah_fp_vm(const char *, int, const char *const *, KAH_Reply *, void *);  /* kfp_viewmodel.inc */
static void kah_bridge_tick(void)
{
    if (g_kah_connected) return;
    DWORD now = GetTickCount();
    if (now - g_kah_last_try < 1000) return;
    g_kah_last_try = now;
    if (!KAH_Connect(&g_kah)) return;
    g_kah_connected = 1;
    int n = g_kah.registerCommand("fp_mode", "fp_mode on|off", kah_fp_mode, NULL)
          + g_kah.registerCommand("fp_click", "fp_click (then select a squad member)", kah_fp_click, NULL)
          + g_kah.registerCommand("fp_putdown", "fp_putdown (G while carrying)", kah_fp_putdown, NULL)
          + g_kah.registerCommand("fp_state", "fp_state", kah_fp_state, NULL)
          + g_kah.registerCommand("fp_combat_probe", "fp_combat_probe begin|end|state|events [after_sequence]|clear", kah_fp_combat_probe, NULL)
          + g_kah.registerCommand("fp_control", "fp_control state|take|press", kah_fp_control, NULL)
          + g_kah.registerCommand("fp_move", "fp_move <wasd|none> [ms] | state (TEST ONLY WASD hold)", kah_fp_move, NULL)
          + g_kah.registerCommand("fp_camera", "fp_camera state|probe|distance <0..60>|wheel <delta>|look <yaw radians> <pitch radians>|ray x y z dx dy dz [range] [mask]|floors cx cz half step ytop ybot", kah_fp_camera, NULL)
          + g_kah.registerCommand("fp_combat", "fp_combat on|off|state|aim (read-only)|physical|input <aim> <fire> <reload>", kah_fp_combat, NULL)
          + g_kah.registerCommand("fp_turret", "fp_turret [state] (FP turret control: aim, reload, shots)", kah_fp_turret, NULL)
          + g_kah.registerCommand("fp_melee", "fp_melee state (read-only native melee)", kah_fp_melee, NULL)
          + g_kah.registerCommand("fp_keys", "fp_keys state|press <lmb|rmb|mmb|r> [ms]|release|native <lmb|rmb> [frames]|pick [show]|sneak [show]|movers [show]|swallow on|off|focus on|off (TEST)|reset", kah_fp_keys, NULL)
          + g_kah.registerCommand("fp_vm", "fp_vm state|probe|dump|on|off|set <key> <v>", kah_fp_vm, NULL);
    g_kah.log("KenshiFP: first-person test commands registered");
    logline("[kah] connected to the automation harness: %d commands (fp_mode/fp_click/fp_putdown/fp_state)", n);
}

static void fp_lookat_click_guard(void *gw)
{
    static int lmb_prev, dead;
    static DWORD click_ms;
    static void *keep;
    static pi_selectpc_t fn;
    if (dead) return;
    int lmb = (GetAsyncKeyState(VK_LBUTTON) & 0x8000) != 0;
    int injected = InterlockedExchange(&g_kah_inject_click, 0) != 0; /* harness fp_click */
    DWORD now = GetTickCount();
    if ((lmb && !lmb_prev && g_fp_mode && g_cursor_hidden && !g_ui_open && game_has_focus())
        || (injected && g_fp_mode && !g_ui_open)) {
        click_ms = now ? now : 1;
        keep = g_player_pc;
        if (injected) logline("[fp] look-at click (harness-injected)");
    }
    lmb_prev = lmb;
    if (!click_ms) return;
    if ((LONG)(now - click_ms) > 1000) { click_ms = 0; return; }
    void *cur = first_player_char(gw);
    if (!keep || !cur || cur == keep || !char_valid(keep)) return;
    click_ms = 0;
    if (!fn) {
        HMODULE k = GetModuleHandleA("KenshiLib.dll");
        if (k) fn = (pi_selectpc_t)GetProcAddress(k, KLIB_PI_SELECTPC_SYM);
        if (!fn) { dead = 1; logline("[fp] look-at click guard: export missing -- disabled"); return; }
    }
    void *pi = *(void **)((uintptr_t)gw + GW_PLAYER);
    if (setjmp(g_guard_jb)) { g_guard_armed = 0; dead = 1; logline("[fp] look-at click guard faulted -- disabled"); return; }
    guard_arm();
    fn(pi, keep, 0, 0);
    g_guard_armed = 0;
    logline("[fp] look-at click selected another squad member: kept control (bug 79)");
    /* PT22 (Shay 2026-10-07): no stats window any more (bug 79b popup removed); LMB never selects in FP
     * (fpc_playercontrol_hook + fpc_mouse_key_swallow), this re-select stays only as a safety net. */
}

/* Harness input isolation (AutomationHarness.dll KAH_InputIsolated, 2026-10-07): automated runs keep the game
 * unfocused while Shay uses the PC; the harness then feeds GetAsyncKeyState and DirectInput (OIS + our look mouse)
 * with injected input only (key_inject / mouse_inject), so the game counts as focused. Looked up once a second until
 * found; cheap enough for the 1 kHz poll thread. */
typedef int (*kah_isolated_t)(void);
static kah_isolated_t volatile g_kah_isolated;
static DWORD g_kah_isolated_try;
static int kah_input_isolated(void)
{
    kah_isolated_t f = g_kah_isolated;
    if (!f) {
        DWORD now = GetTickCount();
        if (now - g_kah_isolated_try < 1000) return 0;
        g_kah_isolated_try = now;
        HMODULE h = GetModuleHandleA(KAH_DLL_NAME);
        f = h ? (kah_isolated_t)(void *)GetProcAddress(h, "KAH_InputIsolated") : NULL;
        if (!f) return 0;
        g_kah_isolated = f;
    }
    return f();
}

static int game_has_focus(void)
{
    if (g_test_focus) return 1;
    if (kah_input_isolated()) return 1;
    HWND fg = GetForegroundWindow();
    if (!fg) return 0;
    DWORD pid = 0;
    GetWindowThreadProcessId(fg, &pid);
    return pid == GetCurrentProcessId();
}

/* Frame-rate-independent look capture: a dedicated ~1kHz thread owns the
 * DirectInput reads and accumulates counts; each frame consumes the total.
 * Per-frame GetDeviceState sampled the mouse at the FRAME rate, and at high
 * fps that aliases against the mouse's own report rate (beat patterns of
 * 0/2-count frames = visible wobble; felt fine only at the frame rates we
 * developed at). Constant-rate capture decouples feel from fps entirely. */
static volatile LONG g_acc_dx, g_acc_dy;
static DWORD WINAPI di_poll_thread(void *unused)
{
    (void)unused;
    timeBeginPeriod(1);              /* 1ms Sleep granularity for this loop */
    int fp_key_down = 0;
    for (;;) {
        /* FP-toggle detection lives HERE, not in a global WH_KEYBOARD_LL hook:
         * a dedicated thread whose job is a global keyboard hook is the textbook
         * keylogger pattern and trips antivirus behavioral heuristics. A passive
         * GetAsyncKeyState poll (the same call the game uses for WASD) does not,
         * and because this thread is off the frame loop it still catches the
         * toggle even if an Alt press briefly stalls the game's message loop. */
        int kd = (GetAsyncKeyState(g_cfg_key_fp) & 0x8000) != 0;
        /* Only while Kenshi has focus: GetAsyncKeyState is global, so a Right Alt/AltGr
         * typed in another window toggled FP mid-test (fp-5090-5 R12-LOAD: [input] FP mode
         * toggled -> OFF with no harness fp_mode call). */
        if (kd && !fp_key_down && game_has_focus()) InterlockedExchange(&g_toggle_edge, 1);   /* press edge */
        fp_key_down = kd;

        /* Mouse look + wheel from DirectInput (once acquired) -- no WH_MOUSE_LL. */
        if (g_di_ready) {
            LONG dx, dy, dz;
            if (di_get_deltas(&dx, &dy, &dz)) {
                /* Always CONSUME the deltas (di_get_deltas reads relative counts, so
                 * this keeps the baseline current), but only ACCUMULATE when our
                 * window is focused -- otherwise alt-tabbed mouse motion in another
                 * app would spin the camera away. */
                if (game_has_focus()) {
                    if (dx) InterlockedAdd(&g_acc_dx, dx);
                    if (dy) InterlockedAdd(&g_acc_dy, dy);
                    if (dz) InterlockedExchangeAdd(&g_wheel_accum, dz);   /* wheel notches */
                }
            }
        }
        Sleep(1);
    }
    return 0;
}
/* Consume (and zero) the accumulated deltas. */
static void di_take_acc(LONG *dx, LONG *dy)
{
    *dx = InterlockedExchange(&g_acc_dx, 0);
    *dy = InterlockedExchange(&g_acc_dy, 0);
}

/* Hand the camera back to the vanilla system CONTINUOUSLY: seat the center
 * node on our current FP look direction and the camera node at (0,0,zoom),
 * via the game's own manuallySetOrientationAndZoom -- so the RTS camera (or
 * the map fly-out) resumes facing exactly where the player was looking,
 * with a legit zoom state (no endless zoom-out, no view cut). */
static void vanilla_cam_handoff(void *cam, void *camnode, float zoom)
{
    float qy = cosf(g_yaw * 0.5f),   sqy = sinf(g_yaw * 0.5f);
    float qp = cosf(g_pitch * 0.5f), sqp = sinf(g_pitch * 0.5f);
    Quat q = { qy * qp, qy * sqp, sqy * qp, -sqy * sqp };
    /* vanilla keeps the camera node's LOCAL orientation at identity (only the
     * center rotates); our per-frame derived-ori writes dirtied it, and
     * manuallySetOrientationAndZoom doesn't reset it -- do that here. */
    Quat ident = { 1.0f, 0.0f, 0.0f, 0.0f };
    if (readable(camnode, 8)) g_node_set_ori(camnode, &ident);
    if (setjmp(g_guard_jb)) { g_guard_armed = 0; return; }
    guard_arm();
    ((void (*)(void *, const Quat *, float))(g_base + RVA_CAM_MANUAL_SETOZ))(cam, &q, zoom);
    g_guard_armed = 0;
}

/* Hide the world-space 3D stealth-detection arrows (Character::stealthMarkerArrows,
 * an AttachedArrowManager whose `ents` lektor {begin,end,cap} of Ogre::Entity* sits
 * at +0x0). We just flip each arrow entity invisible every frame -- non-destructive,
 * so the game's own arrow bookkeeping (add/clear per frame) is untouched. Default:
 * hidden; the F10 "Stealth arrows" toggle turns them back on. */
static int g_arrows_dead;
static void hide_stealth_arrows(void *pc)
{
    if (g_arrows_dead || !pc || !g_ent_setvisible) return;
    /* AttachedArrowManager layout (from Ghidra decomp of addArrow @1.0.65 0x5dbd40):
     *   +0x08 uint32 size (pool slots) | +0x10 Ogre::Entity*[] data | +0x18 uint32 index (active).
     * The game's arrow-reuse path does NOT call setVisible(true), so once we hide an entity it
     * stays hidden -- to bring them back on toggle-on we must actively re-show the active ones. */
    unsigned char *aam = (unsigned char *)((uintptr_t)pc + CHAR_STEALTH_ARROWS);
    if (!readable(aam, 0x20)) return;
    unsigned size  = *(unsigned *)(aam + 0x8);
    unsigned index = *(unsigned *)(aam + 0x18);
    void **data    = *(void ***)(aam + 0x10);
    if (!data || size == 0 || size > 64 || !readable(data, (size_t)size * 8)) return;
    char vis   = g_cfg_stealth_arrows ? 1 : 0;
    unsigned n = g_cfg_stealth_arrows ? index : size;   /* on: show the active arrows; off: hide all slots */
    if (n > size) n = size;
    if (setjmp(g_guard_jb)) { g_guard_armed = 0; g_arrows_dead = 1;
        logline("stealth-arrow vis FAULTED -- disabled for this session"); return; }
    guard_arm();
    for (unsigned i = 0; i < n; i++)
        if (readable(data[i], 8)) g_ent_setvisible(data[i], vis);
    g_guard_armed = 0;
}

/* ---- screen-label crosshair remap (FP status text + lockpick % bar) --------------------
 * Kenshi's floating statuses are NOT world-space 3D: they are 2D MyGUI widgets that a
 * per-frame sweep re-positions by projecting a tracked world position (ScreenLabel /
 * FloatingProgressBar / CharacterNameTag, all ScreenLabelInterface subclasses living in
 * the global label lektor @1.0.68 DAT_142133a20). In FP that projected point is the
 * player's own head = the camera, so the labels swim around the screen edge. We hook the
 * two update virtuals and, AFTER the game has done its own layout, re-pin the widget of
 * any label that belongs to the FP character to a fixed spot under the crosshair --
 * exactly the treatment the sneak eye got, but by moving the game's own widgets instead
 * of mirroring state into ours.
 *
 * Ownership gates: a ScreenLabel tracking a hand (+0x70; type dword +0x78, 0xb = none)
 * must match the player's handle ids; anchor-only labels (and every FloatingProgressBar
 * -- it has no hand) must sit within a small radius of the player's feet, which covers
 * the lockpicked door/cage without capturing other characters' labels in a melee.
 * Labels whose text starts with a digit/sign stay in world space: those are the damage
 * floaters, and dragging an enemy's -23 onto our crosshair would be noise.
 *
 * Lifetime: expiry defers to a dead-list (flag +0x9c) freed by the manager sweep, so
 * dereferencing the label right after orig returns cannot use-after-free. The sweep runs
 * on the render thread (it creates MyGUI widgets), so setPosition here is as safe as the
 * game's own call one instruction earlier. */
typedef void (*label_update_t)(void *label);
static label_update_t g_slabel_update_orig, g_pbar_update_orig;
static Vec3     g_lbl_player_pos;     /* published per-frame from the mainloop hook */
static int      g_lbl_player_ok;
static uint32_t g_lbl_player_hand[5]; /* CHAR_HANDLE id dwords (all-zero = unknown) */
static int      g_lbl_text_slot;      /* per-frame stack index: captured text labels */
static int      g_lbl_bar_slot;       /*   "  : captured progress bars */

static int lbl_near_player(const float *v)
{
    if (!g_lbl_player_ok || !readable((void *)v, 12)) return 0;
    float dx = v[0] - g_lbl_player_pos.x;
    float dy = v[1] - g_lbl_player_pos.y;
    float dz = v[2] - g_lbl_player_pos.z;
    return dx * dx + dz * dz < 2.5f * 2.5f && dy * dy < 4.0f * 4.0f;
}

static int lbl_hand_is_player(const unsigned char *hnd)
{
    const uint32_t *a = (const uint32_t *)(hnd + HAND_IDS);
    int i, any = 0;
    for (i = 0; i < 5; i++) { if (a[i] != g_lbl_player_hand[i]) return 0; any |= a[i]; }
    return any != 0;
}

/* Size of the game's render view (client area of the Ogre window); MyGUI coordinates are in this space.
 * Falls back to the desktop size if the window isn't found. Windowed / below-desktop resolutions need this:
 * SM_CXSCREEN put the crosshair outside a 1600x900 window. */
static void kfp_view_size(int *w, int *h)
{
    static HWND hw;
    RECT r;
    if (!hw || !IsWindow(hw)) {
        HWND f = FindWindowA("OgreD3D11Wnd", NULL);
        DWORD pid = 0;
        if (f) GetWindowThreadProcessId(f, &pid);
        hw = (f && pid == GetCurrentProcessId()) ? f : NULL;
    }
    if (hw && GetClientRect(hw, &r) && r.right - r.left > 64 && r.bottom - r.top > 64) {
        *w = r.right - r.left; *h = r.bottom - r.top; return;
    }
    *w = GetSystemMetrics(SM_CXSCREEN); *h = GetSystemMetrics(SM_CYSCREEN);
    if (*w <= 0) *w = 1920;
    if (*h <= 0) *h = 1080;
}

static void lbl_screen_center(int *cx, int *cy)
{
    kfp_view_size(cx, cy);
}

static void hooked_slabel_update(void *label)
{
    g_slabel_update_orig(label);
    if (!g_fp_mode || !g_cfg_screen_status || !g_widget_setpos) return;
    unsigned char *b = (unsigned char *)label;
    if (!readable(b, 0xa0) || b[0x9c]) return;             /* dead-listed */
    void *w = *(void **)(b + 0x48);
    if (!readable(w, 8)) return;                           /* widget not created yet */
    int mine = (*(int *)(b + 0x78) != 0xb) ? lbl_hand_is_player(b + 0x70)
                                           : lbl_near_player((float *)(b + 0x0c));
    if (!mine) return;
    /* MSVC std::string at +0x20 (size +0x30, cap +0x38): skip damage floaters */
    size_t cap = *(size_t *)(b + 0x38);
    const char *txt = (cap > 15) ? *(const char **)(b + 0x20) : (const char *)(b + 0x20);
    if (!readable((void *)txt, 1)) return;
    if ((txt[0] >= '0' && txt[0] <= '9') || txt[0] == '-' || txt[0] == '+') return;
    int cx, cy;
    lbl_screen_center(&cx, &cy);
    /* just ABOVE the lockpick % bar (bar base = center+40): the first label takes
     * the prime slot at center+20; simultaneous extras overflow BELOW the bar
     * (center+68+) so nothing ever stacks onto the crosshair or the bar. A trimmed
     * hint of the vanilla rise (label age +0x64) keeps the text reading as motion. */
    float age = *(float *)(b + 0x64);
    int drift = (int)(age * 25.0f);
    if (drift < 0) drift = 0; else if (drift > 8) drift = 8;
    int y = (g_lbl_text_slot == 0) ? cy / 2 + 20
                                   : cy / 2 + 68 + (g_lbl_text_slot - 1) * 18;
    g_widget_setpos(w, cx / 2 - 40 + (int)g_cfg_status_x,
                    y - drift + (int)g_cfg_status_y);
    g_lbl_text_slot++;
    if (KFP_DEBUG_LOG) {
        static char seen[8][24]; static int nseen;
        int i, hit = 0;
        for (i = 0; i < nseen; i++) if (strncmp(seen[i], txt, 23) == 0) { hit = 1; break; }
        if (!hit && nseen < 8) {
            snprintf(seen[nseen], sizeof seen[0], "%s", txt); nseen++;
            logline("[label] captured status \"%s\"", txt);
        }
    }
}

static void hooked_pbar_update(void *bar)
{
    g_pbar_update_orig(bar);
    if (!g_fp_mode || !g_cfg_screen_status || !g_widget_setpos) return;
    unsigned char *b = (unsigned char *)bar;
    if (!readable(b, 0x58) || !b[0x08]) return;            /* hidden this frame */
    void *wrap = *(void **)(b + 0x50);
    if (!readable(wrap, 0x10)) return;
    void *w = *(void **)((uintptr_t)wrap + 8);
    if (!readable(w, 0x30)) return;
    if (!lbl_near_player((float *)(b + 0x0c))) return;
    int cx, cy;
    lbl_screen_center(&cx, &cy);
    int bw = *(int *)((uintptr_t)w + 0x28);                /* IntCoord width */
    if (bw < 0 || bw > 4096) bw = 0;
    g_widget_setpos(w, cx / 2 - bw / 2 + (int)g_cfg_status_x,
                    cy / 2 + 40 + g_lbl_bar_slot * 16 + (int)g_cfg_status_y);
    g_lbl_bar_slot++;
}

/* ---- FP falling (task #19): walking off a cliff/roof/stair edge ------------------------
 * Kenshi's pathfinding refuses to route off edges, so in FP you just stall at the lip.
 * But the game fully supports falling -- combat knocks people off walls -- through
 * Character::ragdollQueued(on, mask): queue a whole-body (mask 1) ragdoll request and
 * Character::update applies it via setRagdoll, which hands CharMovement's currentMotion
 * to the Havok ragdoll as launch velocity. From there EVERYTHING is engine-native:
 * gravity, tumbling, fall damage, the settle callback's auto get-up, and KO if the
 * landing was hard. Our job is only (a) detect the edge + push intent, (b) give the
 * mover a convincing launch velocity, (c) after landing, make sure the physics mover
 * (+0x320, destroyed by setRagdoll-on) exists again before handing control back.
 *
 * The pre-RE kinematic integrator (write CharMovement+0xC4 + gravity) is kept as a
 * FALLBACK for builds where the ragdoll RVAs don't resolve. */
/* NOTE: fp_fall_update runs at the MAINLOOP rate (~200Hz measured, not render
 * fps) -- every wait here is in SECONDS accumulated from g_frame_dt; frame
 * counters were 5x too fast (28ms "press", 70ms cooldowns -> instant re-fires). */
static float g_fall_cd_t, g_fall_press_t;
static int   g_fall_dead;
static int   g_fall_active;    /* walk-off tier fall in progress (movement-hook integrator) */
static float g_fall_vy;        /* walk-off: vertical velocity (units/s, negative = down) */
static float g_fall_hx, g_fall_hz;  /* horizontal launch velocity over the lip */
static float g_fall_y0;        /* start height (for the drop-distance log) */
static float g_fall_t;         /* walk-off: seconds airborne (drives the ragdoll escalation) */
static float g_fall_launch_y;  /* vertical velocity handed to the ragdoll at conversion */
static float g_fall_qw = 1.0f, g_fall_qy; /* facing quat (w,y) fed to the teleport placement */
static Vec3  g_fall_pos;       /* walk-off: OUR integrated position. The engine teleport
                                * ground-clamps, and mv+0xC4 re-syncs from the mover every
                                * tick, so neither can carry a mid-air arc -- this is the
                                * only position that falls. */
static float g_fall_trace_t;   /* post-landing diagnostic window (seconds) */
/* ragdoll-fall driver state */
#define FALLRD_OFF      0
#define FALLRD_QUEUED   1      /* ragdoll requested; waiting for the parts mask to set */
#define FALLRD_AIRBORNE 2      /* mask set: physics owns the body; waiting for settle */
#define FALLRD_GETUP    3      /* get-up requested; waiting for the mask to clear */
static int   g_fall_rd;        /* FALLRD_* phase */
static float g_fall_rd_t;      /* seconds in the current phase */
static float g_fall_settle_t;  /* seconds the ragdoll has been at rest */
static int   g_fall_rd_landed; /* QUEUED entered from a LANDED crumple (vs a lip dive):
                                * on engage-timeout just stand up -- do NOT restart a fall */
static float g_fall_settle_goal = 0.8f; /* rest time needed before wake-up -- scaled per fall:
                                        * barely-over-KO impacts get up almost immediately,
                                        * massive ones take the full fall_settle beat */
static Vec3  g_fall_rd_pos;    /* last position (settle detection) */
static int   g_fall_jump;      /* the current walk-off arc is a JUMP: landing is allowed
                                * as soon as the arc is descending (a flat hop returns to
                                * START-height ground, which the lip-grace would reject) */
static int   g_jump_fire_req;  /* space-press handoff: the mainloop hook posts a small
                                * frame countdown, the fall driver consumes it. Expires so
                                * a mid-air press doesn't queue a takeoff for touchdown. */
static float g_fall_airland;   /* landing anticipation 0..1 (last 0.25s of the descent,
                                * from time-to-impact): fed to the loco layer so the
                                * plant IK pre-shapes the legs to the landing surface
                                * BEFORE contact (squash blend, no slope-pop) */
static float g_fall_startx, g_fall_startz;  /* takeoff x/z (tunnel-abort return point) */
static int   g_fall_gnd_ok;    /* last arc tick had a readable ground column (the
                                * readable->blind edge marks entering a mesh volume) */
static int   g_fall_perched;
static float g_fall_perch_y;      /* smoothed perch rest height (pop filter) */
static float g_fall_perch_grace;  /* detect-miss hysteresis (s): hold the perch
                                   * through single-tick scene-query blinks */   /* standing on a MESH TOP (arc alive, vy=0): the engine
                                * can't host a character there (landing-commit corrupts
                                * the mover), so the arc itself is the ground -- WASD
                                * walks the surface kinematically, space jumps off */

/* Ground query for the fall system: union of BOTH channel sets of the engine
 * groundAt (flag3 adds mask 0x88000 -- some structure colliders, e.g. stair
 * ramps, only exist there; querying one set alone let arcs phase through
 * stairs). Returns the HIGHER hit; nohit only if both miss. */
static float fall_ground(const Vec3 *p)
{
    float (*gat)(const Vec3 *, char, char) =
        (float (*)(const Vec3 *, char, char))(g_base + RVA_GROUND_AT);
    float nohit = *(float *)(g_base + RVA_GROUND_NOHIT);
    float a = gat(p, 1, 0), b = gat(p, 1, 1);
    if (a == nohit) return b;
    if (b == nohit) return a;
    return a > b ? a : b;
}

/* General engine ray query (the fn GROUND_AT wraps with a static down vector).
 * Writes the hit POINT to *hit, or the GROUND_NOHIT sentinel in all three
 * components on a miss. dir need not be normalized (normalized inside). mask
 * 0x88204 = the union of both fall-system ground channel sets + objects --
 * terrain, building shells, interiors, rocks, props: the collision world. */
static int fall_ray_m(const Vec3 *from, const Vec3 *dir, Vec3 *hit, unsigned mask)
{
    if (!RVA_RAYCAST || !RVA_GROUND_NOHIT) return 0;
    ((void (*)(Vec3 *, const Vec3 *, const Vec3 *, unsigned))
        (g_base + RVA_RAYCAST))(hit, from, dir, mask);
    return hit->y != *(float *)(g_base + RVA_GROUND_NOHIT);
}
static int fall_ray(const Vec3 *from, const Vec3 *dir, Vec3 *hit)
{
    return fall_ray_m(from, dir, hit, 0x88204u);
}
#include "kfp_view.inc"

/* Horizontal sweep for the arc: is a surface within `reach` units of `from`
 * along `dirh`, at either of two body heights? (two rays: shin and chest) */
/* Returns the blocking height index +1 (1..3) or 0; writes the hit distance.
 * THREE heights -- ankle catches the small boulders the old shin ray flew
 * over. Mask 0xfffffffe: bit 0 excluded (self-hits own body at d=0, nearbits
 * probe); rocks are bit 0x40, walls/structures in the 0x88200 set. */
static int fall_sweep_blocked(const Vec3 *pos, const Vec3 *dirh, float reach,
                              float bh, float *dist)
{
    static const float hf[3] = { 0.08f, 0.45f, 0.85f };
    for (int hh = 0; hh < 3; hh++) {
        Vec3 from = { pos->x, pos->y + bh * hf[hh], pos->z };
        Vec3 hit;
        if (fall_ray_m(&from, dirh, &hit, 0xfffffffeu)) {
            float dx = hit.x - from.x, dz = hit.z - from.z;
            float d2 = dx * dx + dz * dz;
            if (d2 < reach * reach) {
                /* WALKING-SURFACE filter: a hit lying ON the engine ground of
                 * its own column is the slope underfoot, not a wall face --
                 * the ankle ray fired into uphill terrain and blocked slope
                 * jumps at d=0.04 ("prevented from jumping" regression). */
                Vec3 gq = { hit.x, hit.y + 2.0f, hit.z };
                float gh2 = fall_ground(&gq);
                if (gh2 != *(float *)(g_base + RVA_GROUND_NOHIT)
                    && hit.y <= gh2 + 1.2f) continue;
                if (dist) *dist = sqrtf(d2);
                return hh + 1;
            }
        }
    }
    return 0;
}

static unsigned fall_ragdoll_mask(void *pc)
{
    void *anim = readable((void *)((uintptr_t)pc + CHAR_ANIM), 8)
        ? *(void **)((uintptr_t)pc + CHAR_ANIM) : NULL;
    return (anim && readable((void *)((uintptr_t)anim + ANIM_RAGDOLL_MASK), 4))
        ? *(unsigned *)((uintptr_t)anim + ANIM_RAGDOLL_MASK) : 0;
}

/* C05-KO (4080 b31/b32): a KO'd Axima flew 186 m then 80 km while W was held, and the next load
 * crashed. g_is_down lags the knockdown (it waits for the head to be low), so the pose/facing/
 * locomotion writers kept acting on a body the ragdoll already owned. This is the one gate for
 * every FP writer: KO flag, whole-body/KO ragdoll bits, KO prone state, or g_is_down. */
static int fp_body_down(void *pc)
{
    if (!pc) return 0;
    if (g_is_down) return 1;
    if (combat_char_unconscious(pc)) return 1;
    if (fall_ragdoll_mask(pc) & 0x801u) return 1;
    return char_prone_state(pc) == PS_KO;
}
/* One log line per suppressed writer per down episode (KenshiFP.log evidence for C05-KO). */
static unsigned g_down_note_mask;
static void fp_down_note(const char *site, void *pc)
{
    unsigned bit = 0;
    for (const char *c = site; *c; ++c) bit = bit * 31u + (unsigned char)*c;
    bit = 1u << (bit % 31u);
    if (g_down_note_mask & bit) return;
    g_down_note_mask |= bit;
    logline("[down] suppressed %s write on downed actor %p (is_down=%d ko=%d mask=0x%x prone=%d)",
            site, pc, g_is_down, combat_char_unconscious(pc), fall_ragdoll_mask(pc), char_prone_state(pc));
}

/* Fall finished (mask cleared): vanilla's plain ragdoll-off does NOT rebuild the
 * physics mover (only the KO-exit path does), so recreate it ourselves if it's
 * still missing -- CharMovement::update early-returns forever without it. */
static void fall_restore_mover(void *pc)
{
    void *mv = readable((void *)((uintptr_t)pc + CHAR_MOVEMENT), 8)
        ? *(void **)((uintptr_t)pc + CHAR_MOVEMENT) : NULL;
    if (!mv || !readable((void *)((uintptr_t)mv + MV_MOVER), 8)) return;
    if (*(void **)((uintptr_t)mv + MV_MOVER) != NULL) return;   /* game already rebuilt it */
    if (!RVA_CREATE_MOVER) return;
    ((void (*)(void *))(g_base + RVA_CREATE_MOVER))(mv);
    logline("[fall] mover was gone after get-up -> recreated");
}

static void fp_fall_update(void *pc)
{
    if ((!g_cfg_falling && !g_cfg_jump) || g_fall_dead || !pc
        || !RVA_GROUND_AT || !RVA_GROUND_NOHIT) { g_fall_active = 0; g_fall_rd = FALLRD_OFF; return; }
    float fdt = (g_frame_dt > 0.0f && g_frame_dt < 0.25f) ? g_frame_dt : 0.016f;
    if (setjmp(g_guard_jb)) { g_guard_armed = 0; g_fall_dead = 1; g_fall_rd = FALLRD_OFF;
        g_fall_active = 0; g_fall_jump = 0; g_jump_fire_req = 0; g_fall_perched = 0;
        logline("[fall] fall driver FAULTED -- falling disabled"); return; }
    guard_arm();

    /* ---- ragdoll-fall monitor: runs every frame (even FP-off) so an in-flight
     * fall always completes cleanly ---- */
    if (g_fall_rd != FALLRD_OFF) {
        g_fall_rd_t += fdt;
        unsigned mask = fall_ragdoll_mask(pc);
        if (g_fall_rd == FALLRD_QUEUED) {
            if (mask) {                                   /* physics took the body */
                g_fall_rd = FALLRD_AIRBORNE; g_fall_rd_t = 0.0f; g_fall_settle_t = 0.0f;
                char_position(pc, &g_fall_rd_pos);
                logline("[fall] ragdoll engaged (mask=0x%x)", mask);
            } else if (g_fall_rd_t > 0.6f) {              /* request refused/ignored */
                if (g_fall_rd_landed) {
                    /* already ON the ground (crumple-at-landing): the engine
                     * refused the KO ragdoll (down-state busy?) -- finish as a
                     * soft landing instead of freezing (the old fallback
                     * RESTARTED a kinematic fall at the landing spot: ~2s of
                     * stuck-in-place per hard landing). */
                    logline("[fall] KO ragdoll never engaged (state=%d) -- standing landing",
                            readable((void *)((uintptr_t)pc + 0x2F8), 4)
                                ? *(int *)((uintptr_t)pc + 0x2F8) : -1);
                    g_fall_rd = FALLRD_OFF; g_fall_cd_t = 0.8f;
                    g_have_last_feet = 0; g_move_speed = 0.0f; g_have_prevraw = 0; g_rebase_hold_t = 1.0f;
                    g_loco_reassert_t = 0.7f;
                } else {
                    logline("[fall] ragdoll never engaged -- using kinematic fallback");
                    g_fall_rd = FALLRD_OFF;
                    g_fall_active = 1; g_fall_jump = 0;
                    g_fall_vy = 0.0f;                     /* g_fall_y0/hx/hz still set */
                }
            }
        } else if (g_fall_rd == FALLRD_AIRBORNE) {
            Vec3 now;
            if (char_position(pc, &now)) {
                float dx = now.x - g_fall_rd_pos.x, dy = now.y - g_fall_rd_pos.y,
                      dz = now.z - g_fall_rd_pos.z;
                float v = sqrtf(dx*dx + dy*dy + dz*dz) / fdt;   /* units/s */
                g_fall_settle_t = (v < 1.2f) ? g_fall_settle_t + fdt : 0.0f;   /* "at rest"
                    * tolerates residual twitching -- get up sooner */
                g_fall_rd_pos = now;
            }
            if (!mask) {                                  /* engine already got them up */
                logline("[fall] landed after %.1f units (engine get-up)",
                        g_fall_y0 - g_fall_rd_pos.y);
                fall_restore_mover(pc);
                g_fall_rd = FALLRD_OFF; g_fall_cd_t = 1.0f;
                g_have_last_feet = 0; g_move_speed = 0.0f; g_have_prevraw = 0; g_rebase_hold_t = 1.0f;
                g_loco_reassert_t = 0.7f;
                g_fall_trace_t = 1.5f;
            } else if (g_fall_settle_t > g_fall_settle_goal || g_fall_rd_t > g_cfg_fall_timeout) {
                /* body at rest (or timeout): VANILLA ORDER matters here --
                 * setUnconscious(0) only plays the get-up animation (0x5c7b00)
                 * and rebuilds the mover when the ragdoll is ALREADY off at
                 * call time (decomp). So: request ragdoll-off now; the KO exit
                 * is called in the GETUP phase once the mask clears. */
                if (RVA_STOP_RAGDOLL)
                    ((void (*)(void *, char))(g_base + RVA_STOP_RAGDOLL))(pc, 0);
                else if (RVA_SET_UNCON)
                    ((void (*)(void *, char))(g_base + RVA_SET_UNCON))(pc, 0);
                g_fall_rd = FALLRD_GETUP; g_fall_rd_t = 0.0f;
                logline("[fall] landed after %.1f units -> wake-up requested",
                        g_fall_y0 - g_fall_rd_pos.y);
            }
        } else { /* FALLRD_GETUP */
            if (!mask) {
                /* ragdoll is off now: the KO exit takes its animation branch --
                 * plays the get-up-off-the-ground anim and rebuilds the mover */
                if (RVA_SET_UNCON)
                    ((void (*)(void *, char))(g_base + RVA_SET_UNCON))(pc, 0);
                fall_restore_mover(pc);
                g_fall_rd = FALLRD_OFF; g_fall_cd_t = 1.0f;   /* re-arm delay */
                g_have_last_feet = 0; g_move_speed = 0.0f; g_have_prevraw = 0; g_rebase_hold_t = 1.0f;
                g_loco_reassert_t = 0.7f;
                g_fall_trace_t = 1.5f;
            } else if (g_fall_rd_t > 4.0f) {
                /* still down: hard landing KO'd them -- vanilla medical recovery
                 * owns the character now (get-up + mover rebuild via the KO-exit
                 * path). Stand down with a long cooldown. */
                logline("[fall] still down after landing (KO) -- vanilla recovery owns it");
                g_fall_rd = FALLRD_OFF; g_fall_cd_t = 4.0f;
                g_have_prevraw = 0; g_rebase_hold_t = 1.0f;
            }
        }
        g_guard_armed = 0;
        return;
    }

    /* ---- jump FROM a mesh-top perch: the arc is alive (g_fall_active) but
     * we're standing on the surface -- re-launch the arc from the PERCH
     * position (g_fall_pos; the engine char is still parked at the original
     * takeoff commit, so char_position must not be used here) ---- */
    if (g_fall_active && g_fall_perched && g_fp_mode && !g_is_down && g_jump_fire_req) {
        g_jump_fire_req = 0;
        if (g_cfg_jump) {
            int pw = (GetAsyncKeyState(g_cfg_key_w) & 0x8000) != 0;
            int pa = (GetAsyncKeyState(g_cfg_key_a) & 0x8000) != 0;
            int ps = (GetAsyncKeyState(g_cfg_key_s) & 0x8000) != 0;
            int pd = (GetAsyncKeyState(g_cfg_key_d) & 0x8000) != 0;
            int pmf = pw - ps, pms = pd - pa;
            float ph = g_yaw, pl = 0.0f;
            if (pmf || pms) {
                ph = g_yaw + atan2f(-(float)pms, (float)pmf);
                int spr = g_cfg_key_sprint
                       && (GetAsyncKeyState(g_cfg_key_sprint) & 0x8000);
                pl = (spr ? 60.0f : 38.0f) * g_speed_scale;   /* ground tiers */
                if (pl > 35.0f) pl = 35.0f;    /* same carry cap as ground jumps */
            }
            g_fall_hx = sinf(ph) * pl;
            g_fall_hz = cosf(ph) * pl;
            g_fall_y0 = g_fall_pos.y;
            g_fall_startx = g_fall_pos.x; g_fall_startz = g_fall_pos.z;
            g_fall_vy = g_cfg_jump_vel;
            g_fall_t  = 0.0f;
            g_fall_jump = 1;
            g_fall_perched = 0;
            g_fall_gnd_ok = 0;   /* mesh-top columns often read no engine ground --
                                  * don't let the first tick trip the blind-veto */
            logline("[jump] takeoff from mesh top (carry=%.1f)", pl);
        }
        g_guard_armed = 0;
        return;
    }
    /* ---- edge trigger ---- */
    if (!g_fp_mode || g_fall_active || fp_body_down(pc)) { g_guard_armed = 0; return; }   /* C05-KO: no arc for a downed body */
    if (g_fall_cd_t > 0.0f) { g_fall_cd_t -= fdt; g_guard_armed = 0; return; }
    /* ---- JUMP (task #20): consume the space-press the mainloop hook posted.
     * A jump IS a walk-off arc launched upward: vy = +jump_vel, WASD momentum
     * carried over the same hx/hz fields, and flight/landing/absorb/KO are all
     * the shared integrator. Gating is inherited from the early-returns above
     * (grounded state only: not airborne, not ragdolled, not down, cooldown
     * honored); here we only add "standing on measurable ground" -- the same
     * ray-blind-platform guard the edge scan uses, since an arc that can't see
     * the deck below would tunnel through it. */
    if (g_jump_fire_req) {
        /* THE SPRINT-ONLY BUG (03:44 log): the vanilla space bind pauses the
         * game a frame after the press, so the request used to be consumed on
         * a framespeed==0 frame and silently refused -- the post-frame swallow
         * then restored speed, one frame too late. (Shift+space worked only
         * because the vanilla bind doesn't fire with the modifier held.) While
         * paused, do NOT consume the request: leave it to retry after the
         * swallow restores speed; its frame countdown still bounds the wait. */
        float jfs = (g_gw_cache && readable((void *)((uintptr_t)g_gw_cache + GW_FRAMESPEED), 4))
                  ? *(float *)((uintptr_t)g_gw_cache + GW_FRAMESPEED) : 1.0f;
        if (jfs <= 0.01f) { g_guard_armed = 0; return; }
        g_jump_fire_req = 0;
        if (g_cfg_jump && RVA_CHAR_SETDEST) {
            Vec3 jh;
            if (char_position(pc, &jh)) {
                float jnohit = *(float *)(g_base + RVA_GROUND_NOHIT);
                Vec3 js = { jh.x, jh.y + 3.0f, jh.z };
                float jg = fall_ground(&js);
                /* interiors: the +3 ray can read the NEXT storey's floor slab
                 * -- re-probe low when implausible (same as the edge scan) */
                if (jg != jnohit && jg > jh.y + 1.0f) {
                    Vec3 j2 = { jh.x, jh.y + 1.0f, jh.z };
                    float g2 = fall_ground(&j2);
                    if (g2 != jnohit) jg = g2;
                }
                /* Ground plausibility: on a steep (unwalkable, surf) slope the
                 * capsule rides 7-14 units ABOVE the down-ray's surface reading
                 * (11:23 log: y-gh up to 13.9 while clearly in contact), so the
                 * old 2.5 tolerance refused every slide jump. Ray-blind platform
                 * towns -- the case this gate exists for -- read HUNDREDS of
                 * units of air below (297 in the field log), so 18 separates
                 * them cleanly. */
                if (jg != jnohit && jg > jh.y - 18.0f && jg < jh.y + 4.0f) {
                    /* upper bound widened +1.5 -> +4: on downhill-facing slope
                     * stances the local terrain read sits a couple units ABOVE
                     * the embedded feet (log: gh-y = +2.1 refusals) */
                    int jw = (GetAsyncKeyState(g_cfg_key_w) & 0x8000) != 0;
                    int ja = (GetAsyncKeyState(g_cfg_key_a) & 0x8000) != 0;
                    int jsK = (GetAsyncKeyState(g_cfg_key_s) & 0x8000) != 0;
                    int jd = (GetAsyncKeyState(g_cfg_key_d) & 0x8000) != 0;
                    int jmf = jw - jsK, jms = jd - ja;
                    float jheading = g_yaw, jlaunch = 0.0f;
                    if (jmf || jms) {   /* moving jump: carry the measured speed
                                         * along the WASD heading (same basis as
                                         * the edge-fire launch) */
                        jheading = g_yaw + atan2f(-(float)jms, (float)jmf);
                        jlaunch = g_move_speed;
                        if (jlaunch > 35.0f) jlaunch = 35.0f;
                    }
                    g_fall_hx = sinf(jheading) * jlaunch;
                    g_fall_hz = cosf(jheading) * jlaunch;
                    /* FACING: the arc renders with g_face_dir and lands with the
                     * qw/qy quat -- both must be the BODY facing (g_face_yaw, the
                     * TIP state machine's committed yaw), NOT the movement heading
                     * (a backpedal jump would land facing away) and NOT a stale
                     * g_face_dir (only refreshed while moving: after an idle
                     * turn-in-place the jump faced the OLD direction). */
                    float jfy = g_face_have ? g_face_yaw : g_yaw;
                    g_fall_qw = cosf(jfy * 0.5f);
                    g_fall_qy = sinf(jfy * 0.5f);
                    g_face_dir.x = sinf(jfy); g_face_dir.y = 0.0f; g_face_dir.z = cosf(jfy);
                    g_fall_y0  = jh.y;
                    g_fall_startx = jh.x; g_fall_startz = jh.z;
                    g_fall_gnd_ok = 1;
                    g_fall_pos = jh;
                    g_fall_vy  = g_cfg_jump_vel;
                    g_fall_t   = 0.0f;
                    g_fall_active = 1;
                    g_fall_jump   = 1;
                    logline("[jump] takeoff vy=%.0f carry=%.1f (ground %.2f under feet)",
                            g_fall_vy, jlaunch, jh.y - jg);
                    if (KFP_DEBUG_LOG && RVA_RAYCAST) {   /* [rdbg] cross-check: DOWN ray through
                        * our wrapper vs the proven GROUND_AT result -- separates
                        * "call broken" from "geometry absent from the ray world" */
                        static int rj;
                        if (rj < 6) { rj++;
                            Vec3 dn = { 0.0f, -1.0f, 0.0f }, ht;
                            Vec3 fd = { jh.x, jh.y + 3.0f, jh.z };
                            int r = fall_ray(&fd, &dn, &ht);
                            logline("[rdbg] takeoff down-ray hit=%d y=%.2f (GROUND_AT said %.2f)",
                                    r, ht.y, jg);
                            Vec3 fw = { sinf(g_yaw), 0.0f, cosf(g_yaw) };
                            r = fall_ray(&fd, &fw, &ht);
                            logline("[rdbg] takeoff fwd-ray hit=%d p=(%.1f,%.1f,%.1f)",
                                    r, ht.x, ht.y, ht.z);
                        }
                    }
                } else {
                    logline("[jump] refused: no measurable ground (gh=%.1f y=%.1f)",
                            jg == jnohit ? -9999.0f : jg, jh.y);
                }
            }
        }
        g_guard_armed = 0;
        return;   /* consumed this pass; the edge scan resumes next frame */
    }
    /* Everything below is the WALK-OFF EDGE SCAN -- the "Falling" feature.
     * Jumping (above) shares the arc integrator but is independently toggled,
     * so with Falling off you can still jump (and land, and take the fall if
     * you jump off a cliff) while edges keep their vanilla stall. */
    if (!g_cfg_falling) { g_guard_armed = 0; return; }
    /* WASD -> world heading (same formula as the loco feed; independent so it works loco-off) */
    int kw = (GetAsyncKeyState(g_cfg_key_w) & 0x8000) != 0;
    int ka = (GetAsyncKeyState(g_cfg_key_a) & 0x8000) != 0;
    int ks = (GetAsyncKeyState(g_cfg_key_s) & 0x8000) != 0;
    int kd = (GetAsyncKeyState(g_cfg_key_d) & 0x8000) != 0;
    int mf = kw - ks, mstr = kd - ka;
    if (!mf && !mstr) { g_fall_press_t = 0.0f; g_guard_armed = 0; return; }
    /* SIGN: the movement drive maps D to heading (yaw - pi/2) -- its basis is
     * fx=-sin,fz=-cos / rx=+cos,rz=-sin with a final negation. atan2(+mstr,mf)
     * gave the MIRRORED strafe heading: pressing A/D probed the opposite side
     * of the direction the body actually strafes (W/S agree by symmetry), so
     * strafe falls could never fire. */
    float heading = g_yaw + atan2f(-(float)mstr, (float)mf);
    float dirx = sinf(heading), dirz = cosf(heading);
    Vec3 here;
    if (!char_position(pc, &here)) { g_guard_armed = 0; return; }
    /* FORWARD-PROGRESS gate input: total speed is the wrong stall signal -- the
     * mover SLIDES ALONG a lip at 25-35 u/s when pushed at an angle (log), so
     * "speed < x" only opened on a perfectly square push. What distinguishes
     * "pinned/grinding an edge" from "walking freely" is progress ALONG the
     * push heading: ~0 while grinding, full walk/run speed while climbing. */
    /* rolling peak of the measured speed (for launch momentum: by the time a
     * stalled push fires, the instant speed has decayed to ~0) */
    static float g_fall_peak_spd;
    g_fall_peak_spd -= 50.0f * fdt;
    if (g_fall_peak_spd < g_move_speed) g_fall_peak_spd = g_move_speed;
    float fwd_spd = 999.0f;
    {
        static Vec3 fp_last; static int fp_have;
        if (fp_have && fdt > 0.0001f) {
            float vx = (here.x - fp_last.x) / fdt, vz = (here.z - fp_last.z) / fdt;
            fwd_spd = vx * dirx + vz * dirz;
        }
        fp_last = here; fp_have = 1;
    }
    /* Edge scan: GROUND_AT raycasts straight DOWN from the given point, so all
     * rays start `lift` above foot height (a foot-height ray starts underground
     * on any uphill and no-hits -> the old slope bug). */
    float lift = 3.0f;
    Vec3 self  = { here.x, here.y + lift, here.z };
    float gh = fall_ground(&self);
    float nohit = *(float *)(g_base + RVA_GROUND_NOHIT);
    /* INTERIORS: a +3 ray can poke above the NEXT STOREY's floor slab and read
     * it instead of the ground we stand on -- re-probe low when implausible */
    if (gh != nohit && gh > here.y + 1.0f) {
        Vec3 s2 = { here.x, here.y + 1.0f, here.z };
        float g2 = fall_ground(&s2);
        if (g2 != nohit) gh = g2;
    }
    /* RAY-BLIND structures (large platform towns / multi-storey towers): the
     * ground query reads 200+ units of AIR below the deck the mover stands on
     * -- their walkable surfaces live in collision the raycast doesn't cover.
     * Any "edge" measured there is terrain relief far below, and firing sends
     * the player through the equally ray-blind building (log: standing at
     * y=2073 with gh=1776, arcs falling 300 units through every floor). No
     * reliable measurement -> no falling on these surfaces; the vanilla edge
     * stall is preserved instead. */
    if (gh != nohit && gh < here.y - 6.0f) {
        g_fall_press_t = 0.0f; g_guard_armed = 0; return;
    }
    int edge = 0;
    float edge_drop = 0.0f;
    float edge_dist = 99.0f;               /* fan distance of the detected lip */
    float hs3[3] = { -9999.0f, -9999.0f, -9999.0f };
    if (gh != nohit && gh - here.y < lift) {      /* own ray hit the floor we stand
                                                   * on, not a roof above the head */
        /* THREE probe directions (heading and +/-25 degrees), each an independent
         * 7-sample scan with its own rising-veto: a CURVED lip crossed obliquely
         * by the exact-heading ray breaks the adjacent-pair pattern (head-on-only
         * falls), and strafe pushes rarely align perfectly -- whichever ray
         * crosses the lip square enough wins. An edge = TWO ADJACENT samples in
         * one direction both showing the full drop (one alone fired on stairwell
         * voids); reach ~6 units (mover stall distance at town-roof lips is
         * 3.5-5+); rising ground vetoes only ITS OWN direction. */
        for (int dd = 0; dd < 3 && !edge; dd++) {
            float da = (dd == 0) ? 0.0f : (dd == 1 ? -0.44f : 0.44f);
            float dx2 = sinf(heading + da), dz2 = cosf(heading + da);
            int rising = 0;
            float h5[7];
            for (int i = 0; i < 7; i++) {
                float d = g_cfg_fall_probe + 0.8f * (float)i;
                Vec3 p = { here.x + dx2 * d, here.y + lift, here.z + dz2 * d };
                h5[i] = fall_ground(&p);
                /* INTERIOR stairwells: the lifted ray pokes above the next
                 * storey's floor slab and reads it as RISING ground, vetoing
                 * every indoor stair edge. A hit far above our own ground
                 * (> +2.2: a slab/ceiling, not a ramp's gradual rise) gets
                 * re-probed from a LOW ray that stays under the slab. */
                if (h5[i] != nohit && h5[i] > gh + 2.2f) {
                    Vec3 pl = { p.x, here.y + 1.0f, p.z };
                    float hl = fall_ground(&pl);
                    if (hl != nohit && hl < gh + 0.5f) h5[i] = hl;
                }
                if (dd == 0 && i < 3) hs3[i] = h5[i];
                if (h5[i] != nohit && h5[i] > gh + 0.5f) { rising = 1; break; }
            }
            if (rising) continue;
            for (int i = 0; i < 6; i++) {
                if (h5[i] != nohit && h5[i+1] != nohit
                    && gh - h5[i]   > g_cfg_fall_drop
                    && gh - h5[i+1] > g_cfg_fall_drop)
                    { edge = 1; edge_dist = g_cfg_fall_probe + 0.8f * (float)i;
                      edge_drop = gh - h5[i]; break; }
            }
        }
    }
    /* PRESS ACCOUNTING -- flicker-proof. The gates only decide whether this
     * frame CONTRIBUTES; nothing drains the press. It resets only when no edge
     * has been seen for 0.4s (walked away) or the keys were released.
     *  - stall gate: at a real lip the engine pins you (no forward progress);
     *    climbing stairs/slopes you move freely, so mid-stride drops (stair
     *    flight sides, switchback voids) never accumulate;
     *  - edge + stalled for a total of 0.1s -> go. */
    int fire = 0;
    {
        static float since_edge, flat_t, prev_gh; static int have_gh;
        int stalled = fwd_spd < 8.0f;      /* no forward progress = pinned/grinding */
        if (edge) since_edge = 0.0f; else since_edge += fdt;
        if (since_edge > 0.4f) g_fall_press_t = 0.0f;
        /* graded press credit: full while pinned, HALF while creeping under
         * walking speed -- the mover surges against a lip in jitter spikes
         * (log: fwd 0.5->16.3 flicker) and all-or-nothing credit let those
         * spikes starve the press for seconds */
        if (edge && stalled)              g_fall_press_t += fdt;
        else if (edge && fwd_spd < 12.0f) g_fall_press_t += 0.5f * fdt;
        /* FLAT-APPROACH tracker: own-ground vertical rate. Roof/cliff-top
         * approaches are level (|dgh/dt| ~ 0); stair RAMPS move gh at 25+ u/s
         * under a runner, and switchback platforms are crossed in <0.1s -- so
         * demanding 0.25s of sustained flat ground under you excludes every
         * false running-fire the logs produced. */
        float dgh = (have_gh && fdt > 0.0001f) ? (gh - prev_gh) / fdt : 999.0f;
        prev_gh = gh; have_gh = 1;
        flat_t = (dgh > -8.0f && dgh < 8.0f) ? flat_t + fdt : 0.0f;
        /* RUNNING fire: flat approach + edge in the fan + PREDICTIVE, speed-
         * scaled reach (~0.12s of lead): a sprint fires as soon as the fan sees
         * the lip (no invisible-wall bump); a walk only when it is nearly
         * underfoot. */
        float lead = fwd_spd * 0.12f; if (lead < 1.6f) lead = 1.6f;
        int runfire = edge && !stalled && flat_t > 0.25f && edge_dist <= lead;
        fire = (edge && g_fall_press_t >= 0.1f) || runfire;
        /* [fdbg] full gate state, time-limited */
        static float dbg_t;
        dbg_t += fdt;
        if (KFP_DEBUG_LOG && dbg_t >= 0.3f) {
            dbg_t = 0.0f;
            logline("[fdbg] y=%.2f gh=%.2f ahead=%.2f/%.2f/%.2f edge=%d d=%.1f fwd=%.1f press=%.2f flat=%.2f",
                    here.y, gh, hs3[0], hs3[1], hs3[2], edge, edge_dist, fwd_spd,
                    g_fall_press_t, flat_t);
        }
    }
    if (!fire) { g_guard_armed = 0; return; }
    {
        g_fall_press_t = 0.0f;
        g_fall_y0 = here.y;
        /* Momentum carry: use the recent PEAK speed, not the instant value --
         * a stalled push has already decayed g_move_speed to ~0 by fire time,
         * flattening every non-running launch to the floor. The peak tracker
         * (decays ~50 u/s^2) still remembers the approach speed. Cap + post-
         * 0.6s air drag + the landing crossing-guard keep arcs from sailing
         * through whole buildings. */
        float launch = g_fall_peak_spd;
        if (launch < 12.0f) launch = 12.0f;
        if (launch > 30.0f) launch = 30.0f;
        /* scale the carry to the measured drop: a 30 u/s leap off a 6-unit
         * INTERIOR stair edge drifts across the stairwell shaft and falls
         * through the slab openings floor after floor (log: drop=5.9 measured,
         * 283 units fallen). Small drops get a step, big ones keep momentum. */
        {
            float lmax = 10.0f + edge_drop;
            if (launch > lmax) launch = lmax;
        }
        g_fall_hx = sinf(heading) * launch;
        g_fall_hz = cosf(heading) * launch;
        float drop = edge_drop;
        /* facing quat for the teleport placement: yaw about +Y (Ogre w,x,y,z) */
        g_fall_qw = cosf(heading * 0.5f);
        g_fall_qy = sinf(heading * 0.5f);
        /* EVERY fall is a walk-off PUSH off the lip -- the arc mechanism is the
         * one path that reliably clears edges (an upfront ragdoll at the lip
         * tumbles in place and settles back on the ledge: log "landed after
         * -6.x"). Ragdoll now happens AT LANDING, scaled by fall time, inside
         * the integrator. The direct KO dive survives only as a fallback for
         * builds where the teleport placement didn't resolve. */
        if (RVA_CHAR_SETDEST) {
            g_fall_active = 1;
            g_fall_jump = 0;
            g_fall_vy = 0.0f;
            g_fall_t  = 0.0f;
            g_fall_startx = here.x; g_fall_startz = here.z;
            g_fall_gnd_ok = 1;
            g_fall_pos = here;
            logline("[fall] edge ahead (drop=%.1f, launch=%.1f) -> walk-off push",
                    drop, launch);
        } else if (RVA_SET_UNCON || RVA_RAGDOLL_QUEUED) {
            void *mv = readable((void *)((uintptr_t)pc + CHAR_MOVEMENT), 8)
                ? *(void **)((uintptr_t)pc + CHAR_MOVEMENT) : NULL;
            g_fall_launch_y = 2.5f;
            if (mv && readable((void *)((uintptr_t)mv + MV_CURRENT_MOTION), 12)) {
                Vec3 *cm = (Vec3 *)((uintptr_t)mv + MV_CURRENT_MOTION);
                cm->x = g_fall_hx; cm->y = g_fall_launch_y; cm->z = g_fall_hz;
                if (readable((void *)((uintptr_t)mv + MV_CURRENT_SPEED), 4))
                    *(float *)((uintptr_t)mv + MV_CURRENT_SPEED) = launch;
            }
            g_fall_settle_goal = g_cfg_fall_settle;
            if (RVA_SET_UNCON)
                ((void (*)(void *, char))(g_base + RVA_SET_UNCON))(pc, 1);
            else
                ((void (*)(void *, char, int))(g_base + RVA_RAGDOLL_QUEUED))(pc, 1, 1);
            g_fall_rd = FALLRD_QUEUED; g_fall_rd_t = 0.0f; g_fall_rd_landed = 0;
            logline("[fall] edge ahead (drop=%.1f) -> ragdoll dive (no teleport fn)", drop);
        }
    }
    g_guard_armed = 0;
}

static int ini_int(const char *line, const char *key, int *out);
static int ini_float(const char *line, const char *key, float *out);
#include "kfp_viewmodel.inc" /* PT13/14/17: weapon-in-view arm raise */

static void fp_camera_override(void *gw)
{
    if (!g_ogre_ready) return;
    kfp_front_listener_tick();
    void *cam = *(void **)(g_base + RVA_CAM_INSTANCE);
    if (!readable(cam, CC_FREECAM + 1)) return;
    void *node = *(void **)((uintptr_t)cam + CC_NODE);
    if (!readable(node, 8)) return;

    {   /* m51-F: a vanilla FPS camera left on (survives a save reload) kept FP inactive for good.
         * Clear it when FP turns on and after a world load; a free cam toggled while FP is on stays. */
        static int fpm_prev;
        if (g_fp_mode && (!fpm_prev || g_freecam_clear_pending)) {
            g_freecam_clear_pending = 0;
            unsigned char *fcp = (unsigned char *)((uintptr_t)cam + CC_FREECAM);
            if (*fcp) {
                *fcp = 0; ++g_freecam_clears;
                logline("[cam] vanilla FPS camera was on: cleared (%s)", fpm_prev ? "after load" : "FP enter");
            }
        }
        fpm_prev = g_fp_mode;
    }
    {   /* CS05 defense in depth: a bound FP key that still reached vanilla toggle_fps_camera
         * flips cam+0xBF 0->1 right after we swallowed it. Undo that edge only (a free cam
         * switched on with an unbound key, no recent swallow, stays). */
        static int fc_prev = -1;
        unsigned char *fcp = (unsigned char *)((uintptr_t)cam + CC_FREECAM);
        int fc = *fcp ? 1 : 0;
        if (kfp_bound_toggle_revert(g_fp_mode, fc_prev, fc, g_fp_swallow_seen,
                                    (unsigned)GetTickCount(), g_fp_swallow_ms)) {
            *fcp = 0; fc = 0; ++g_bound_toggle_reverts; g_fp_swallow_seen = 0;
            logline("[cam] vanilla FPS toggle from bound key reverted (dik=0x%02X)", g_fp_last_swallow_dik);
        }
        fc_prev = fc;
    }
    /* Only drive the override while FP is on AND not in free-cam mode. */
    int active = g_fp_mode && fp_controlled_char(gw) && !*(unsigned char *)((uintptr_t)cam + CC_FREECAM);

    {   /* [map-bug diag] log every state flip that can knock us out of FP */
        static int pa = -1, pf = -1, po = -1, pm = -1;
        int fc = *(unsigned char *)((uintptr_t)cam + CC_FREECAM);
        int ov = (g_ui_mask & UIMASK_OVERVIEW) ? 1 : 0;
        if (KFP_DEBUG_LOG && (active != pa || fc != pf || ov != po || g_fp_mode != pm)) {
            logline("[cam] fp=%d freecam=%d overview=%d active=%d mask=0x%03x",
                    g_fp_mode, fc, ov, active, g_ui_mask);
            pa = active; pf = fc; po = ov; pm = g_fp_mode;
        }
    }

    /* Drive the aim-lean whenever FP is ON -- including free cam, so it stays
     * visible for third-person inspection while you orbit (the rotation-agnostic
     * axis keeps it body-relative). Release when FP is off or while ragdolled,
     * handing the spine back to the animation. Runs before the eye block below
     * so the FP eye still rides the bend. */
    {
        fp_lookat_click_guard(gw);   /* bug 79: before the swap below sees her */
        void *pcx = fp_controlled_char(gw);
        /* Character swap (selected a different squad member): release the old
         * character's driven bones and reset all per-character calibrations so
         * FP re-seats cleanly on the new body. */
        static void *pc_prev;
        if (pcx != pc_prev) {
            /* the old body must still be a live squad member before its bones are touched
             * (after a load pc_prev is freed: forget, never write; b27b) */
            if (pc_prev && !fp_char_in_squad(gw, pc_prev)) { g_spine_manual = 0; loco_forget(); }
            if (pc_prev && g_spine_manual) release_spine(pc_prev);
            if (pc_prev && g_loco_ready) {      /* old body's bones may be freed: guarded */
                if (setjmp(g_guard_jb)) { g_guard_armed = 0; g_loco_ready = 0; }
                else { guard_arm(); loco_release(); g_guard_armed = 0; }
            }
            g_have_qref = 0; g_down_blend = 0.0f; g_is_down = 0;  /* ragdoll ref */
            g_have_fwd = 0;                                       /* spine fwd axis */
            g_have_last_feet = 0; g_move_speed = 0.0f; g_have_prevraw = 0; g_rebase_hold_t = 1.0f;            /* speed-push tracker */
            g_have_prevraw = 0;                                   /* rebase-detect tracker */
            /* NOTE: g_have_t/g_tx/g_tz are NOT reset -- T is the floating-origin
             * translation (ogre vs game coords), scene-global and identical for
             * every character. Resetting it on swap opened an uncalibrated
             * window where the center-snap fallback fed back on itself and the
             * camera glided away while holding WASD (even paused). */
            pc_prev = pcx;
        }
        g_player_pc = first_player_char(gw); /* preserve shared selected-actor cache */
        g_fp_control_actor = g_fp_mode ? pcx : NULL; /* private controlled-actor hook cache */
        /* Sneak/detection state for the screen-space eye (drawn post-frame in
         * fp_gui_update). Field reads only -- no game calls. */
        {
            int want = 0;
            if (readable((void *)((uintptr_t)pcx + CHAR_STEALTH_MODE), 1) &&
                *(unsigned char *)((uintptr_t)pcx + CHAR_STEALTH_MODE)) {
                int unseen = readable((void *)((uintptr_t)pcx + CHAR_STEALTH_UNSEEN), 4)
                           ? *(int *)((uintptr_t)pcx + CHAR_STEALTH_UNSEEN) : 1;
                want = (unseen == 1) ? 1 : (unseen == 2) ? 2 : 3; /* hidden / noticed / seen */
            }
            InterlockedExchange(&g_sneak_want, want);
        }
        /* Player pos + handle ids for the screen-label crosshair remap hooks
         * (ScreenLabel / FloatingProgressBar update detours). One sweep runs per
         * frame, so resetting the stack slots here keeps 0..n-1 stable. */
        {
            Vec3 pp;
            g_lbl_player_ok = (pcx && char_position(pcx, &pp)) ? (g_lbl_player_pos = pp, 1) : 0;
            if (pcx && readable((void *)((uintptr_t)pcx + CHAR_HANDLE + HAND_IDS), 20))
                memcpy(g_lbl_player_hand,
                       (void *)((uintptr_t)pcx + CHAR_HANDLE + HAND_IDS), 20);
            else
                memset(g_lbl_player_hand, 0, sizeof g_lbl_player_hand);
            g_lbl_text_slot = 0;
            g_lbl_bar_slot  = 0;
        }
        hide_stealth_arrows(pcx);   /* world-space detection arrows: hidden unless toggled on */
        fp_fall_update(pcx);        /* walk off edges -> ragdoll fall (task #19) */
        /* Only lean when a weapon is drawn (in hands) -- the aim-lean is for
         * aiming, and looked odd during normal unarmed/sheathed movement. */
        void *wih = (pcx && readable((void *)((uintptr_t)pcx + CHAR_WEAPON_IN_HANDS), 8))
            ? *(void **)((uintptr_t)pcx + CHAR_WEAPON_IN_HANDS) : NULL;
        int weapon_drawn = (wih != NULL);
        static int prev_drawn = -1;
        if (KFP_DEBUG_LOG && weapon_drawn != prev_drawn) {
            logline("[spine] weaponInHands=%p drawn=%d", wih, weapon_drawn);
            prev_drawn = weapon_drawn;
        }
        int body_down = fp_body_down(pcx);
        if (body_down && g_fp_mode && ((weapon_drawn && g_cfg_aim_lean && !g_cfg_loco) || (g_cfg_loco && g_loco_ready)))
            fp_down_note("spine/loco pose", pcx);
        if (g_fp_mode && !body_down && weapon_drawn && g_cfg_aim_lean && !g_cfg_loco) bend_spine(pcx, g_pitch);
        else if (g_spine_manual && !g_cfg_loco)      release_spine(pcx);

        /* custom full-body locomotion (Milestone 0): retarget a Destreza clip onto Bip01.
         * Opt-in (ini locomotion=1). Owns the body bones via manuallyControlled while active. */
        if (g_fp_mode && pcx) {   /* one-shot diag: why isn't loco activating? */
            static int ldiag;
            if (!ldiag && !g_loco_ready) { ldiag = 1;
                void *an = readable((void *)((uintptr_t)pcx + CHAR_ANIM), 8) ? *(void **)((uintptr_t)pcx + CHAR_ANIM) : NULL;
                void *sk = (an && readable((void *)((uintptr_t)an + ANIM_SKELETON), 8)) ? *(void **)((uintptr_t)an + ANIM_SKELETON) : NULL;
                logline("[loco] gate: cfg_loco=%d fp=%d is_down=%d dead=%d kfa=%d getbone=%p anim=%p skel=%p",
                        g_cfg_loco, g_fp_mode, g_is_down, g_loco_dead, g_kfa.loaded, (void*)g_skel_getbone, an, sk); }
        }
        if (g_cfg_loco && g_fp_mode && !body_down && !g_loco_dead && g_kfa.loaded && g_skel_getbone && pcx) {
            void *anim = readable((void *)((uintptr_t)pcx + CHAR_ANIM), 8)
                       ? *(void **)((uintptr_t)pcx + CHAR_ANIM) : NULL;
            void *skel = (anim && readable((void *)((uintptr_t)anim + ANIM_SKELETON), 8))
                       ? *(void **)((uintptr_t)anim + ANIM_SKELETON) : NULL;
            if (skel) {
                if (setjmp(g_guard_jb)) { g_guard_armed = 0; g_loco_dead = 1;
                    logline("[loco] retarget FAULTED -- disabled for this session"); }
                else {
                    guard_arm();
                    if (loco_setup(skel)) {
                        float ldt = (g_frame_dt > 0.0f && g_frame_dt < 0.25f) ? g_frame_dt : 0.016f;
                        /* feed movement state to the blendspace: game-speed multiplier,
                         * pure speed (game-speed divided out), WASD -> world heading */
                        float lgs = readable((void *)((uintptr_t)gw + GW_FRAMESPEED), 4)
                                  ? *(float *)((uintptr_t)gw + GW_FRAMESPEED) : 1.0f;
                        if (!(lgs >= 0.0f)) lgs = 0.0f;
                        if (lgs > 6.0f) lgs = 6.0f;
                        int kw = (GetAsyncKeyState(g_cfg_key_w) & 0x8000) != 0;
                        int ka = (GetAsyncKeyState(g_cfg_key_a) & 0x8000) != 0;
                        int ks = (GetAsyncKeyState(g_cfg_key_s) & 0x8000) != 0;
                        int kd = (GetAsyncKeyState(g_cfg_key_d) & 0x8000) != 0;
                        int mf = kw - ks, mstr = kd - ka;
                        g_loco_in_moving  = (mf || mstr);
                        g_loco_in_heading = g_yaw + atan2f((float)mstr, (float)mf);
                        g_loco_in_gs      = lgs;
                        g_loco_in_speed   = (lgs > 0.1f) ? g_move_speed / lgs : 0.0f;
                        g_loco_in_bodyyaw  = g_face_yaw;   /* commanded facing (fp_movement) */
                        g_loco_in_havebody = (g_face_have && g_cfg_loco_facelock) ? 1 : 0;
                        g_loco_in_turning  = g_face_turning;
                        g_loco_in_sneak    = (readable((void *)((uintptr_t)pcx + CHAR_STEALTH_MODE), 1)
                                           && *(unsigned char *)((uintptr_t)pcx + CHAR_STEALTH_MODE)) ? 1 : 0;
                        g_loco_in_pitch    = g_pitch;      /* aim offsets */
                        g_loco_in_camyaw   = g_yaw;
                        /* world velocity for the accel-lean spring (engine-measured) */
                        void *mvl = readable((void *)((uintptr_t)pcx + CHAR_MOVEMENT), 8)
                                  ? *(void **)((uintptr_t)pcx + CHAR_MOVEMENT) : NULL;
                        if (mvl && readable((void *)((uintptr_t)mvl + MV_CURRENT_MOTION), 12)) {
                            Vec3 cmv = *(Vec3 *)((uintptr_t)mvl + MV_CURRENT_MOTION);
                            g_loco_in_velx = cmv.x; g_loco_in_velz = cmv.z;
                        } else { g_loco_in_velx = 0; g_loco_in_velz = 0; }
                        if (mvl && readable((void *)((uintptr_t)mvl + 0xC4), 12)) {
                            Vec3 cpv = *(Vec3 *)((uintptr_t)mvl + 0xC4);   /* world position */
                            g_loco_in_posx = cpv.x; g_loco_in_posy = cpv.y; g_loco_in_posz = cpv.z;
                        }
                        /* airborne state for the leg air-tuck (Destreza AirPose):
                         * envelope 0.85 * max(0, 1 - |vy|/jumpVel) -- zero at
                         * takeoff, peak at the apex, zero as fall speed builds */
                        /* PERCHED counts as GROUNDED for the loco layer: the
                         * arc is our floor, so the legs must stand (not air-
                         * tuck), turn-in-place must run, and the blendspace
                         * needs the kinematic walk speed (the engine feet
                         * tracker reads the PARKED char = 0 while perched). */
                        g_loco_in_air = (g_fall_active && !g_fall_perched) ? 1 : 0;
                        if (g_fall_active && !g_fall_perched) {
                            float jvn = g_cfg_jump_vel > 5.0f ? g_cfg_jump_vel : 5.0f;
                            float te = 1.0f - fabsf(g_fall_vy) / jvn;
                            g_loco_in_airtuck = te > 0.0f ? 0.85f * te : 0.0f;
                            g_loco_in_airland = g_fall_airland;
                        } else { g_loco_in_airtuck = 0.0f; g_loco_in_airland = 0.0f; }
                        if (g_fall_perched) {
                            float pspd = sqrtf(g_fall_hx * g_fall_hx
                                             + g_fall_hz * g_fall_hz);
                            g_loco_in_speed = pspd;      /* pure speed: the perch
                                * walk is real-time, not game-speed scaled */
                            g_loco_in_velx = g_fall_hx;  /* accel-lean spring */
                            g_loco_in_velz = g_fall_hz;
                            g_loco_in_posx = g_fall_pos.x;
                            g_loco_in_posy = g_fall_pos.y;
                            g_loco_in_posz = g_fall_pos.z;
                        }
                        /* foot-IK ground source: true mesh surface while perched */
                        g_loco_in_groundfn = (g_fall_perched && g_mr_ready && !g_mr_dead)
                                           ? perch_ground_fn : NULL;
                        loco_update(ldt);
                    }
                    g_guard_armed = 0;
                }
            }
        } else if (g_loco_ready) {
            /* gate dropped (left FP, knocked down, loco toggled off) -- hand the bones back,
             * otherwise the body stays frozen in the last retargeted pose forever */
            if (setjmp(g_guard_jb)) { g_guard_armed = 0; g_loco_ready = 0; }
            else { guard_arm(); loco_release(); g_guard_armed = 0; }
        }
        /* CAMERA WELD: force the body entity's skeletal animation NOW -- with this
         * frame's bone writes and anim state -- so the head pose the camera reads
         * below is TODAY's, not yesterday's (Ogre otherwise applies animation at
         * render-queue time, leaving the camera one frame behind the rendered body).
         * Frame-guarded: the engine's own later call no-ops, no double cost. */
        /* C05-KO: not on a downed body -- the ragdoll owns its bones; a forced mid-frame animation
         * update re-poses a physics-driven skeleton (one frame of camera lag while down instead). */
        if (body_down) fp_down_note("forced entity animation update", pcx);
        if (g_fp_mode && pcx && g_entity_updateanim && !body_down) {
            void *animc = readable((void *)((uintptr_t)pcx + CHAR_ANIM), 8)
                        ? *(void **)((uintptr_t)pcx + CHAR_ANIM) : NULL;
            void *went = animc ? find_body_entity(animc) : NULL;   /* clobbers g_guard_jb: called unguarded */
            if (went) {
                if (setjmp(g_guard_jb)) { g_guard_armed = 0; }
                else { guard_arm(); g_entity_updateanim(went); g_guard_armed = 0; }
            }
        }
        /* Calibrate the forward axis only when the body reliably faces the
         * camera: sheathed (no bladed combat stance), idle, looking level. */
        if (g_fp_mode && !g_is_down && !weapon_drawn && !g_was_moving
            && g_pitch > -0.10f && g_pitch < 0.10f) {
            calibrate_spine_fwd(pcx);
            loco_calibrate_facing();   /* root-frame facing ref for the blendspace/turn-in-place */
        }

        if (KFP_MANUAL_AIM)
            manual_fire_update(pcx);    /* LMB -> GunClass::shoot at crosshair */
        fp_putdown_update(pcx);         /* bug 100: G -> put down whoever you carry */

        /* R toggles manual aim: raise the ranged weapon with no target needed.
         * While on, force the ranged state machine into aiming every frame
         * (combat updates keep trying to end it without a target); this also
         * lights up the pose/facing overrides, so the weapon tracks the
         * crosshair. Cleared on sheathe / FP off. */
        if (KFP_MANUAL_AIM) {
            static int r_prev;
            static int draw_grace;              /* frames to wait for the draw anim */
            int r = (GetAsyncKeyState(VK_AIM_TOGGLE) & 0x8000) != 0;
            if (r && !r_prev && !weapon_drawn && !g_ui_open && pcx) {
                /* Out of combat the weapon is holstered (weaponInHands NULL) and
                 * the game only draws it in combat -- so R draws it ourselves:
                 * vtable+0x3C8 getThePreferredWeapon, vtable+0x3D8 drawWeapon
                 * (Item*, std::string by-value = ptr to 32B SSO temp). */
                typedef void *(*get_pref_t)(void *pc);
                typedef char (*draw_weap_t)(void *pc, void *item, void *sso_str);
                if (setjmp(g_guard_jb)) { g_guard_armed = 0; logline("[aim] drawWeapon FAULTED"); }
                else {
                    guard_arm();
                    void **vt = readable(pcx, 8) ? *(void ***)pcx : NULL;
                    if (readable((void *)((uintptr_t)vt + 0x3D8), 8)) {
                        void *w = ((get_pref_t)vt[0x3C8 / 8])(pcx);
                        if (w) {
                            unsigned char empty[32]; make_mstr(empty, "");
                            ((draw_weap_t)vt[0x3D8 / 8])(pcx, w, empty);
                            g_aim_mode = 1; draw_grace = 90;
                            logline("[aim] drew weapon %p; aim RAISED", w);
                        } else logline("[aim] no preferred weapon to draw");
                    }
                    g_guard_armed = 0;
                }
            } else if (r && !r_prev && weapon_drawn && !g_ui_open) {
                g_aim_mode = !g_aim_mode;
                void *rcd = readable((void *)((uintptr_t)pcx + CHAR_RANGEDCOMBAT), 8)
                    ? *(void **)((uintptr_t)pcx + CHAR_RANGEDCOMBAT) : NULL;
                void *gund = (rcd && readable((void *)((uintptr_t)rcd + RC_GUN), 8))
                    ? *(void **)((uintptr_t)rcd + RC_GUN) : NULL;
                int st = (rcd && readable(rcd, 4)) ? *(int *)rcd : -1;
                int cm = (rcd && readable((void *)((uintptr_t)rcd + RC_COMBATMODE), 1))
                    ? *(unsigned char *)((uintptr_t)rcd + RC_COMBATMODE) : -1;
                int am = (gund && readable((void *)((uintptr_t)gund + GUN_AMMO), 4))
                    ? *(int *)((uintptr_t)gund + GUN_AMMO) : -1;
                int physflag = (gund && readable((void *)((uintptr_t)gund + 0x60), 2))
                    ? *(unsigned char *)((uintptr_t)gund + 0x60)
                      | (*(unsigned char *)((uintptr_t)gund + 0x61) << 8) : -1;
                logline("[aim] manual aim %s | rc=%p gun=%p state=%d combatMode=%d ammo=%d phys/vis=0x%x gpsn=%p",
                        g_aim_mode ? "RAISED" : "lowered", rcd, gund, st, cm, am,
                        physflag, (void *)g_get_parent_scenenode);
            }
            r_prev = r;
            if (draw_grace > 0) draw_grace--;   /* the draw anim needs frames */
            else if (!weapon_drawn) g_aim_mode = 0;
            if (!g_fp_mode) g_aim_mode = 0;
            static int aim_prev;
            if (aim_prev && !g_aim_mode && pcx) {   /* lower: hide gun + stop aim anim */
                void *rc2 = readable((void *)((uintptr_t)pcx + CHAR_RANGEDCOMBAT), 8)
                    ? *(void **)((uintptr_t)pcx + CHAR_RANGEDCOMBAT) : NULL;
                void *g2 = (rc2 && readable((void *)((uintptr_t)rc2 + RC_GUN), 8))
                    ? *(void **)((uintptr_t)rc2 + RC_GUN) : NULL;
                if (setjmp(g_guard_jb)) { g_guard_armed = 0; }
                else {
                    guard_arm();
                    if (g2 && readable(g2, 0x10)) {
                        void **gvt = *(void ***)g2;
                        if (readable((void *)((uintptr_t)gvt + 0x10), 8))
                            ((void (*)(void *, char))gvt[1])(g2, 0);
                    }
                    /* animationUpdate's target==NULL branch STOPS the aim anim --
                     * the exact cleanup vanilla runs on combat end. Without it the
                     * driven anim keeps its weight and the pose sticks (hug). */
                    if (rc2 && g_ranged_animupd_orig) {
                        Vec3 z = { 0, 0, 0 };
                        g_ranged_animupd_orig(rc2, 0.016f, &z, NULL);
                        logline("[aim] aim anim stopped (lowered)");
                    }
                    g_guard_armed = 0;
                }
                if (readable((void *)((uintptr_t)rc2 + RC_COMBATMODE), 1))
                    *(unsigned char *)((uintptr_t)rc2 + RC_COMBATMODE) = 0;  /* let AI end combat */
            }
            aim_prev = g_aim_mode;
            if (g_aim_mode && pcx) {
                void *rc = readable((void *)((uintptr_t)pcx + CHAR_RANGEDCOMBAT), 8)
                    ? *(void **)((uintptr_t)pcx + CHAR_RANGEDCOMBAT) : NULL;
                void *gun = (rc && readable((void *)((uintptr_t)rc + RC_GUN), 8))
                    ? *(void **)((uintptr_t)rc + RC_GUN) : NULL;
                if (readable((void *)((uintptr_t)rc + RC_COMBATMODE), 1)) {
                    *(unsigned char *)((uintptr_t)rc + RC_COMBATMODE) = 1;
                    if (readable((void *)((uintptr_t)rc + RC_STATE_OFF), 4))
                        *(int *)((uintptr_t)rc + RC_STATE_OFF) = 3;   /* WAITING = held aim */
                }
                /* The AI task layer is the ONLY caller of updateT->animationUpdate
                 * (verified: 0x438c70 is the sole caller, invoked from AI task
                 * objects), so with no combat task we drive the pose ourselves.
                 * Also reload directly when empty (instant for now). */
                /* Probe/fetch the body entity BEFORE the guarded region below
                 * (the probe uses g_guard_jb itself). */
                void *animx = readable((void *)((uintptr_t)pcx + CHAR_ANIM), 8)
                    ? *(void **)((uintptr_t)pcx + CHAR_ANIM) : NULL;
                void *body_ent = animx ? find_body_entity(animx) : NULL;
                Vec3 aim;
                if (rc && g_ranged_animupd_orig && fp_aim_point(&aim)) {
                    if (setjmp(g_guard_jb)) { g_guard_armed = 0; g_aim_mode = 0;
                        logline("[aim] pose drive FAULTED -- aim mode off"); }
                    else {
                        guard_arm();
                        /* Out of combat rc->gun is NULL (setup nulls the cache;
                         * only combat repopulates it) -- fetch it the game's way
                         * and prime the cache so animationUpdate can use it. */
                        if (!gun) {
                            gun = ((void *(*)(void *))(g_base + RVA_RC_GETGUN))(rc);
                            if (gun && readable((void *)((uintptr_t)rc + RC_GUN), 8)) {
                                *(void **)((uintptr_t)rc + RC_GUN) = gun;
                                logline("[aim] gun fetched via getGun: %p", gun);
                            }
                        }
                        if (gun && readable((void *)((uintptr_t)gun + GUN_AMMO), 4)
                            && *(int *)((uintptr_t)gun + GUN_AMMO) <= 0) {
                            typedef void (*gun_reload_t)(void *gun);
                            ((gun_reload_t)(g_base + RVA_GUN_RELOAD))(gun);
                            logline("[aim] reloaded");
                        }
                        /* The wielded crossbow visual is the GUN's own mesh (the
                         * item stays on the back). GunClassPersonal shares the
                         * createPhysical(parentNode, material) impl the turret
                         * wrapper showed us: parent = body entity's scene node.
                         * Body entity = anim->vt[+0x20]() (the same getter draw/
                         * sheathe use); parent via Ogre getParentSceneNode. */
                        if (gun && g_get_parent_scenenode
                            && readable((void *)((uintptr_t)gun + 0x60), 1)
                            && !*(unsigned char *)((uintptr_t)gun + 0x60)) {
                            void *parent = body_ent ? g_get_parent_scenenode(body_ent) : NULL;
                            if (parent && readable(parent, 0x40) && readable(gun, 0x20)) {
                                void **gvt0 = *(void ***)gun;
                                unsigned char mat[32]; make_mstr(mat, "");
                                logline("[aim] createPhysical attempt: gun=%p parent=%p", gun, parent);
                                ((char (*)(void *, void *, void *))gvt0[3])(gun, parent, mat);
                                logline("[aim] createPhysical -> flag=%d",
                                        (int)*(unsigned char *)((uintptr_t)gun + 0x60));
                            } else {
                                logline("[aim] createPhysical skipped: ent=%p parent=%p", body_ent, parent);
                            }
                        }
                        if (gun && readable(gun, 0x118)) {
                            void **gvt = *(void ***)gun;
                            typedef void (*gun_setvis_t)(void *g, char on);
                            typedef void (*gun_update_t)(void *g, const Vec3 *fallback);
                            /* setVisible's SHOW branch is gated on +0x110 == 0
                             * (decomp-verified); clear it while manually aiming. */
                            if (*(unsigned char *)((uintptr_t)gun + 0x110)) {
                                *(unsigned char *)((uintptr_t)gun + 0x110) = 0;
                                logline("[aim] cleared gun+0x110 hide flag");
                            }
                            static int visdbg;
                            if ((++visdbg % 300) == 1)
                                logline("[aim] gun meshes: drawn=%p undrawn=%p bolts=%d",
                                        *(void **)((uintptr_t)gun + 0x100),
                                        *(void **)((uintptr_t)gun + 0x108),
                                        *(int *)((uintptr_t)gun + 0xA8));
                            if (readable((void *)((uintptr_t)gvt + 0x10), 8)) {
                                ((gun_setvis_t)gvt[1])(gun, 1);      /* vt+0x08 setVisible */
                                ((gun_update_t)gvt[2])(gun, &aim);   /* vt+0x10 update */
                            }
                        }
                        /* target must be NON-NULL: the null branch STOPS the aim
                         * anim (arms drop); non-null plays the aim-hold anim,
                         * drives lookatPosition(aimpos) and readyToShoot. It is
                         * only null-checked here, never dereferenced -- pass
                         * the player object as a safe stand-in. */
                        g_ranged_animupd_orig(rc, 0.016f, &aim, pcx);
                        g_guard_armed = 0;
                    }
                }
            }
        }

        /* Ranged lock-on breaker: with an explicit right-click target the
         * facing is driven by a path that bypasses faceDirection, so while in
         * FP ranged combat force the facing member (CharMovement+0xD0,
         * verified via getFacingDirection) to the look direction each frame. */
        if (g_fp_mode && g_cfg_freeaim && pcx) {
            void *rc = readable((void *)((uintptr_t)pcx + CHAR_RANGEDCOMBAT), 8)
                ? *(void **)((uintptr_t)pcx + CHAR_RANGEDCOMBAT) : NULL;
            if (readable((void *)((uintptr_t)rc + RC_COMBATMODE), 1)
                && *(unsigned char *)((uintptr_t)rc + RC_COMBATMODE)
                && readable((void *)((uintptr_t)pcx + CHAR_MOVEMENT), 8)) {
                void *mv = *(void **)((uintptr_t)pcx + CHAR_MOVEMENT);
                if (readable((void *)((uintptr_t)mv + 0xD0), 12)) {
                    Vec3 *fdir = (Vec3 *)((uintptr_t)mv + 0xD0);
                    fdir->x = sinf(g_yaw); fdir->y = 0.0f; fdir->z = cosf(g_yaw);
                }
            }
        }
    }

    if (active) {
        /* [foliage diag] sample the camera node's derived position as the game left
         * it this frame -- i.e. what foliage paging/culling saw during g_mainloop_orig,
         * before our override runs. Compared against the FP eye below. */
        Vec3 cam_pre = { 0, 0, 0 };
        int have_pre = g_node_get_dpos && g_node_get_dpos(node, &cam_pre);

        int cx = GetSystemMetrics(SM_CXSCREEN) / 2;
        int cy = GetSystemMetrics(SM_CYSCREEN) / 2;
        if (cx <= 0) cx = 960;
        if (cy <= 0) cy = 540;

        POINT cur; GetCursorPos(&cur);

        /* Dialogue/menu open? Game control is disabled then -> free the cursor so
         * the player can click UI; don't recenter or turn the camera. */
        int control = readable((void *)(g_base + RVA_INPUT_CONTROLENABLED), 1)
                      ? *(char *)(g_base + RVA_INPUT_CONTROLENABLED) : 1;
        g_dbg_control = control;
        /* Debounce the panel checks: the game transiently creates inventory
         * window state for ~0.5s during some NPC interactions (mask blips
         * 0x005 in the log). Reacting to those churned halt/restart orders
         * into the middle of NPC-driven task changes -> crash. Dialogue
         * (control==0) stays immediate. */
        int panels_now = ui_panels_open();
        static int panel_frames;
        if (panels_now) { if (panel_frames < 1000) panel_frames++; }
        else panel_frames = 0;
        /* TOGGLE-free-cursor (default Left Alt): PRESS to free the mouse + pause
         * look (like an open panel), press again to re-lock. Read passively
         * (GetAsyncKeyState), so it does NOT consume the key -- Kenshi's own
         * Left-Alt behaviour still fires. On re-lock, the look deltas accumulated
         * while free are drained by the existing g_ui_prev path so the view never
         * jumps. g_free_toggle is reset when FP turns off (see the exit block). */
        {
            static KfpFreeKey free_key;
            /* GetAsyncKeyState is desktop-global: an Alt typed in another window
             * flipped the toggle (S03), and Alt+Tab OUT of Kenshi starts with
             * focus, so it flipped it too (S04 soak). Toggle on a clean tap only:
             * release, focus kept, no switch-away combo key (Tab/Esc/F4/Win)
             * during the hold. Movement keys held while tapping still count. */
            int kd = g_cfg_key_free && (GetAsyncKeyState(g_cfg_key_free) & 0x8000);
            int other = kd && ((GetAsyncKeyState(VK_TAB) | GetAsyncKeyState(VK_ESCAPE) | GetAsyncKeyState(VK_F4)
                                | GetAsyncKeyState(VK_LWIN) | GetAsyncKeyState(VK_RWIN)) & 0x8000);
            /* PT25 (Shay 2026-10-08, loaded straight into FP: the cursor went free 7 s after the load, RMB = walk
             * orders, MMB dead until FP off/on): the Alt of an Alt+Tab back into Kenshi is held when focus returns
             * (or when frames resume after the load / a stall), so its release looked like a clean tap. A press
             * that starts within 600 ms of Kenshi getting focus back, or of a >250 ms gap in this per-frame code,
             * never toggles. */
            {   static DWORD last_run, focus_at; static int had_focus;
                DWORD t = GetTickCount(); int foc = game_has_focus();
                if ((foc && !had_focus) || t - last_run > 250) focus_at = t;
                had_focus = foc; last_run = t;
                if (kd && !free_key.down && t - focus_at < 600) {
                    other = 1; ++g_free_key_refocus;
                    logline("[controls] free-cursor key held as focus/frames came back (%lu ms): not a tap", (unsigned long)(t - focus_at)); }
            }
            if (kfp_free_key_step(&free_key, kd, game_has_focus(), other)) {
                g_free_toggle = !g_free_toggle; ++g_free_key_toggles;
                logline("[controls] free cursor %s (key 0x%02X tap)", g_free_toggle ? "ON" : "OFF", g_cfg_key_free);
            }
        }
        /* STOBE's chat entry is a MyGUI EditBox but it does not toggle any of
         * Kenshi's vanilla panel/control flags. A focused MyGUI keyboard widget is
         * therefore an independent signal that the player is typing into UI.
         * Free/show the cursor immediately while that focus exists. */
        int key_focus_open = 0;
        if (g_input_getinst && g_keyfocus) {
            void *im = g_input_getinst();
            if (im) key_focus_open = (g_keyfocus(im) != NULL);
        }
        int ui_open = (control == 0) || key_focus_open || (panels_now && panel_frames >= 8)
                      || g_settings_open || g_free_toggle;
        g_ui_c_control = control; g_ui_c_keyfocus = key_focus_open;
        g_ui_c_mask = g_ui_mask; g_ui_c_pframes = panel_frames;
        {   /* S03 diag: log which check holds ui_open, on every change of the set */
            int sig = (control == 0) | (key_focus_open ? 2 : 0) | ((panels_now && panel_frames >= 8) ? 4 : 0)
                      | (g_settings_open ? 8 : 0) | (g_free_toggle ? 16 : 0);
            static int sig_prev = -1, suppressed;
            static DWORD last_log;
            if (ui_open && !g_ui_open) g_ui_open_edges++;
            if (sig != sig_prev) {
                DWORD t = GetTickCount();
                if (sig_prev == -1 || t - last_log >= 250 || sig == 0) {
                    char wb[64];
                    logline("[ui] ui_open=%d why=%s control=%d key_focus=%d mask=0x%03x panel_frames=%d settings=%d free=%d edges=%u suppressed=%d",
                            ui_open, ui_why_str(control, key_focus_open, panels_now && panel_frames >= 8,
                            g_settings_open, g_free_toggle, wb, sizeof(wb)), control, key_focus_open,
                            g_ui_mask, panel_frames, g_settings_open, g_free_toggle, g_ui_open_edges, suppressed);
                    last_log = t; suppressed = 0;
                } else suppressed++;
                sig_prev = sig;
            }
        }
        int overview_now = (g_ui_mask & UIMASK_OVERVIEW) ? 1 : 0;
        static int overview_prev;
        g_ui_open = ui_open;                    /* read by the setPointer hook */
        /* Movement remains available while the fullscreen overview/map is open.
         * The map gets the render camera, but we keep its follow target pinned to
         * the player below so checking the map while fleeing does not stop WASD. */
        g_ui_moveblock = (control == 0);
        if (!g_ovr_prev) {                                            /* FP enter */
            mygui_cursor(0); g_pointer_default = 1;
            /* Save the vanilla zoom: the camera node's LOCAL position is
             * (0,0,zoom) under the rotating center node (verified in
             * manuallySetOrientationAndZoom). Our FP writes trash the local
             * position, and vanilla never resets it -- restoring this exact
             * value on exit is what prevents the unending zoom-out. */
            if (g_node_get_pos) {
                const Vec3 *lp = g_node_get_pos(node);
                /* Capture the SIGN, not just the magnitude: vanilla can park the
                 * camera node at a NEGATIVE local Z (camera on the -Z side of the
                 * center). The old guard (z > 2) rejected that, so we restored the
                 * +default on exit and the camera came back on the WRONG side --
                 * in front of the player. Accept either sign now. */
                if (readable((void *)lp, 12)) {
                    float z = lp->z, az = z < 0 ? -z : z;
                    if (az > 2.0f && az < 2000.0f) g_vanilla_zoom = az;  /* magnitude */
                }
            }
            /* Also save the vanilla camera altitude (0x60). FP work seats the
             * camera at eye height; if the RTS camera comes back at that low
             * altitude it sits on/under the floor -- restore it on exit. */
            if (readable((void *)((uintptr_t)cam + CC_ALTITUDE), 4)) {
                float a = *(float *)((uintptr_t)cam + CC_ALTITUDE);
                if (a > 0.5f && a < 5000.0f) g_vanilla_alt = a;
            }
        }
        /* NB: all MyGUI widget work (crosshair/vignette/blackout create,
         * setVisible, setImageTexture) happens POST-FRAME in fp_gui_update --
         * NEVER here. This hook runs mid-frame (during the game's UI update),
         * and touching widgets then corrupted MyGUI's lists and crashed the
         * order/job/inventory ItemBoxes. */

        /* Shay 2026-10-06: never grab/recenter the mouse while Kenshi is not the
         * foreground window (other monitors/apps stay usable while the game runs). */
        int cur_free = ui_open || !game_has_focus();
        if (cur_free) {
            if (g_cursor_hidden) { while (ShowCursor(TRUE) < 0) { } g_cursor_hidden = 0; }
            mygui_cursor(1);                    /* dialogue: keep the game cursor visible */
            /* cursor free; leave look angle frozen */
        } else {
            if (!g_cursor_hidden) { while (ShowCursor(FALSE) >= 0) { } g_cursor_hidden = 1; }
            ensure_dinput();
            if (!g_ovr_prev) {
                /* FP enter (incl. returning from free cam). Don't reset while
                 * ragdolled -- keep the frozen look and head reference so the
                 * follow resumes. g_qref self-recalibrates every upright frame,
                 * so no explicit clear is needed. */
                if (!g_is_down) { g_yaw = 0.0f; g_pitch = 0.0f; }
                g_have_prevraw = 0;   /* don't bridge a rebase across the FP gap */
                LONG jx, jy; di_take_acc(&jx, &jy);     /* drain pre-FP motion */
            } else if (!g_ui_prev) {            /* skip the delta on the frame a dialogue closes */
                /* DirectInput relative deltas (see ensure_dinput comment);
                 * cursor-warp deltas only as fallback. */
                LONG rdx, rdy;
                if (g_di_ready) {
                    di_take_acc(&rdx, &rdy);   /* poll thread accumulates at ~1kHz */
                } else {
                    rdx = cur.x - cx; rdy = cur.y - cy;   /* warp fallback */
                }
                /* Freeze look input while ragdolled: the camera follows the head,
                 * and world-axis yaw/pitch would map to the wrong axes on the
                 * rolled view (mouse-up -> roll etc.). Still drain the deltas so
                 * they don't accumulate and jump the view on get-up. */
                if (!g_is_down) {
                    g_yaw   -= (float)rdx * LOOK_SENS;   /* mouse right -> look right */
                    g_pitch += (float)rdy * LOOK_SENS;   /* mouse down  -> look down  */
                    if (g_pitch >  1.4f) g_pitch =  1.4f;
                    if (g_pitch < -1.4f) g_pitch = -1.4f;
                }
            } else {
                LONG jx, jy; di_take_acc(&jx, &jy);     /* dialogue frame: discard */
            }
            SetCursorPos(cx, cy);  /* recenter so the cursor never drifts to edges */
        }
        g_ui_prev = cur_free;

        /* Fullscreen overview (map/factions/squads) REPURPOSES the render view:
         * keeping our per-frame camera writes running while the map owns the
         * camera crashed the game seconds after opening it. Stand down fully --
         * cursor is already freed above; resume when it closes. (Dialogue and
         * item panels keep the normal 3D view, so the override continues for
         * them and the FP framing is preserved.) */
        if (ui_open && overview_now) {
            if (!overview_prev && g_have_eye) {
                /* Hand off only on the OPEN edge. The overview owns the render
                 * camera, so do not run the FP node/orientation override here. */
                vanilla_cam_handoff(cam, node, 2.0f);
            }

            /* The overview update clears/repurposes CameraClass's follow state
             * after camera_lock() has already run earlier in the frame. Re-assert
             * the player's hand HERE, after the map's camera update, every frame.
             * This lets the map camera track the moving player without touching
             * the map's own orientation/zoom and without blocking WASD. */
            void *pc_map = fp_controlled_char(gw);
            if (pc_map && readable((void *)((uintptr_t)pc_map + CHAR_HANDLE), 0x20))
                g_follow_object(cam, (void *)((uintptr_t)pc_map + CHAR_HANDLE));

            overview_prev = 1;
            g_have_eye = 0;            /* no FP mid-frame re-asserts while map owns view */
            g_ovr_prev = active;
            return;
        }

        if (overview_prev) {
            /* Overview just closed. Re-bind the vanilla follow target and give
             * Kenshi one full frame to rebuild its center node around the player
             * before deriving our FP eye from it. Without this re-anchor the
             * center remains at the map's last world position, so FP resumes
             * metres away while the character walks off independently. */
            void *pc_map = fp_controlled_char(gw);
            if (pc_map && readable((void *)((uintptr_t)pc_map + CHAR_HANDLE), 0x20))
                g_follow_object(cam, (void *)((uintptr_t)pc_map + CHAR_HANDLE));
            overview_prev = 0;
            g_have_eye = 0;
            g_eye_sm_ok = 0;
            g_have_last_feet = 0;
            g_lead_sm = 0.0f;
            g_ovr_prev = active;
            return;
        }

        /* Eye position, fully in WORLD space: centerWorld + (head - feet). The
         * head-feet offset (world axes, from getBoneWorldPosition/getPosition)
         * tracks animation + ragdoll; centerWorld comes from the center node's
         * derived position. Both derived -> no dip, and orientation stays roll-
         * free (below). */
        void *center = *(void **)((uintptr_t)cam + CC_CENTER);
        Vec3 centerW;
        if (readable(center, 8)
            && (g_node_getdpos_upd ? g_node_getdpos_upd(center, &centerW)   /* FORCED fresh */
                                   : g_node_get_dpos(center, &centerW))) {
            /* The `center` node bobs/smooths with the vanilla camera, so it is a
             * bad vertical anchor. Take X/Z from it (Ogre space; X/Z are rebased
             * by the floating origin so we must stay in Ogre space + add the head
             * lean), but take Y straight from the head bone (Y is NOT rebased and
             * is stable) -> the eye is welded to head height, no bob. */
            Vec3 eyeW = { centerW.x, centerW.y + EYE_HEIGHT - EYE_DROP, centerW.z };  /* fallback */
            g_eye_from_head = 0;
            if (g_get_bone_world) {
                void *pc = fp_controlled_char(gw);
                Vec3 feet, head;
                if (pc && char_position(pc, &feet)) {
                    /* Horizontal ground speed from feet delta / dt (framerate-
                     * independent). Drives the speed-scaled forward push below so
                     * the eye leads faster movement instead of getting left behind. */
                    {
                        float dt = (g_frame_dt > 0.0f && g_frame_dt < 0.25f) ? g_frame_dt : 0.016f;
                        if (g_have_last_feet) {
                            float dfx = feet.x - g_last_feet_x, dfz = feet.z - g_last_feet_z;
                            float inst = sqrtf(dfx*dfx + dfz*dfz) / dt;
                            /* REJECT teleport/paging jumps outright -- clamping them
                             * (old: min(inst,400)) still spiked the low-pass to
                             * sprint-cap and fed a 40 u/s launch into the next fall
                             * (log: launch=40.0 after every landing teleport).
                             * The threshold is GAME-SPEED-AWARE: on-screen feet speed
                             * scales with fast-forward (full run 60 u/s -> 300 u/s at
                             * 5x), and a fixed 120 gate rejected ALL legitimate run
                             * samples at >=2x, freezing g_move_speed (and with it the
                             * loco blendspace speed) below its real value. */
                            float sgs = readable((void *)((uintptr_t)gw + GW_FRAMESPEED), 4)
                                      ? *(float *)((uintptr_t)gw + GW_FRAMESPEED) : 1.0f;
                            if (!(sgs >= 1.0f)) sgs = 1.0f;
                            if (sgs > 6.0f) sgs = 6.0f;
                            if (inst < 120.0f * sgs)
                                g_move_speed += (inst - g_move_speed) * 0.20f;   /* ~0.15s low-pass */
                        }
                        g_last_feet_x = feet.x; g_last_feet_z = feet.z; g_have_last_feet = 1;
                    }
                    g_get_bone_world(pc, &head, g_head_bone);
                    Vec3 h = { head.x - feet.x, head.y - feet.y, head.z - feet.z };
                    /* A failed head-bone read returns the feet (|h| ~ 0): keep the last
                     * height instead of reading it as "prone" (C05-KO b33: head_above=0.00
                     * after the fling => downed=1 => no fresh walk on a standing char). */
                    if (h.x*h.x + h.y*h.y + h.z*h.z > 0.25f)
                        g_head_above = h.y;   /* head height over feet; small => actually prone */
                    if (h.x*h.x + h.y*h.y + h.z*h.z > 0.25f) {
                        eyeW.y = head.y - EYE_DROP;   /* head-bone Y directly (Y not rebased) */
                        /* Floating-origin rebase guard: loading a new map chunk
                         * makes Ogre recenter the scene -- centerW (Ogre coords)
                         * jumps by the rebase delta in a single frame while feet
                         * (game coords) stay continuous, so (centerW-feet) jumps.
                         * During movement g_tx is frozen, so without this the eye
                         * would stay in the OLD Ogre frame and the camera teleports
                         * away. A one-frame jump this large is a rebase (camera lag
                         * drifts only a few units/frame), so shift the frozen T by
                         * it and the weld survives the chunk load seamlessly. */
                        float rawtx = centerW.x - feet.x, rawtz = centerW.z - feet.z;
                        /* Rebase detection is DISABLED through fall/ragdoll/down
                         * states: the camera center drifts after the tumbling
                         * body and then SNAPS back 50-60u in one frame -- the
                         * shift branch read that snap as an Ogre origin rebase
                         * and moved T by it, detaching the eye by exactly that
                         * distance (log 15:51:06.830: tx +57.4 mid-ragdoll, eye
                         * +57.5). A real rebase missed here is repaired by the
                         * next idle recalibration. */
                        /* POST-LANDING HOLDOFF: the landing commit is a teleport,
                         * and the vanilla center node SNAPS after it over SEVERAL
                         * frames at 200-300u each (07:44:53 log: tx +285,+283,+70
                         * in 3 frames after a 19-unit slope landing) -- the 1-frame
                         * prevraw reset only skipped the first. Each snap frame
                         * matched the ">50u/frame = rebase" test and shifted T by
                         * ~+638 total: the eye then flew ~640 units from the body
                         * for the whole downhill slide (no idle recalibration while
                         * moving). A real rebase missed inside the window is
                         * repaired by the next idle recalibration, same as ever. */
                        if (g_rebase_hold_t > 0.0f) {
                            float dtr = (g_frame_dt > 0.0f && g_frame_dt < 0.25f)
                                      ? g_frame_dt : 0.016f;
                            g_rebase_hold_t -= dtr;
                        }
                        /* WORLD-SCALE OUTLIERS: 4080 b28 logged "rebase shift tx-54047.5
                         * tz+6810.6" and 0.37 s later "+54145.1 -6904.3": a one-frame
                         * centre read the size of the world coordinates, not a rebase.
                         * Shifting T by it parks the eye (and the centre snap that follows
                         * it while moving) kilometres away; a missed return frame (holdoff,
                         * fall, swap) keeps it there, and an FP exit then left the RTS
                         * camera in an unloaded zone ("Loading..." forever). So: a jump
                         * that lands back on the calibrated weld is the end of an outlier
                         * (no shift); a jump over WELD_BIG_JUMP must hold still for
                         * WELD_CONFIRM frames before it is taken as a rebase, and while it
                         * is pending neither T nor the idle calibration uses this frame. */
                        int weld_suspect = 0;
                        if (g_have_prevraw && g_have_t && g_rebase_hold_t <= 0.0f
                            && !g_is_down && !g_fall_active && g_fall_rd == FALLRD_OFF) {
                            float ddx = rawtx - g_prevraw_tx, ddz = rawtz - g_prevraw_tz;
                            KfpWeldStep ws = kfp_weld_step(&g_weld_pend, rawtx, rawtz,
                                                           g_prevraw_tx, g_prevraw_tz, g_tx, g_tz);
                            if (ws == KFP_WELD_SHIFT) {
                                g_tx += ddx; g_tz += ddz;
                                logline("[weld] rebase shift tx%+.1f tz%+.1f centre=%.1f,%.1f,%.1f feet=%.1f,%.1f,%.1f",
                                        ddx, ddz, centerW.x, centerW.y, centerW.z, feet.x, feet.y, feet.z);
                            } else if (ws == KFP_WELD_PENDING) {
                                weld_suspect = 1;
                                if (g_weld_pend.n == 1)
                                    logline("[weld] world-scale centre jump tx%+.1f tz%+.1f held (not a rebase until it holds)"
                                            " centre=%.1f,%.1f,%.1f feet=%.1f,%.1f,%.1f prev_t=%.1f,%.1f pc=%p",
                                            ddx, ddz, centerW.x, centerW.y, centerW.z, feet.x, feet.y, feet.z,
                                            g_prevraw_tx, g_prevraw_tz, (void *)pc);
                            } else if (ws == KFP_WELD_RETURNED) {
                                logline("[weld] centre back on the weld after an outlier: no shift");
                            }
                        } else g_weld_pend.n = 0;
                        if (weld_suspect) g_calib_wait = 30;   /* never calibrate T on an outlier */
                        else { g_prevraw_tx = rawtx; g_prevraw_tz = rawtz; g_have_prevraw = 1; }
                        /* head/feet are GAME coords, center is OGRE; they differ by
                         * a constant floating-origin translation T. Calibrate T ONLY
                         * while idle (the center node has caught up); freeze it during
                         * movement, when the center lags and would corrupt T. Then use
                         * head_game + T -> exact, lag-free tracking. */
                        /* Calibrate T only after the center node has settled:
                         * during movement we snap the center to the eye (grass
                         * paging fix), so give it ~0.5s post-stop to lerp back
                         * to its vanilla follow point before trusting it. */
                        if (g_was_moving || g_fall_active || g_fall_rd != FALLRD_OFF
                            || g_is_down || g_move_speed > 3.0f) {
                            /* Freeze whenever the BODY is moving or down, not just
                             * when WE drive it: falling, ragdolling, and being
                             * CARRIED by an NPC after a KO all move the body while
                             * g_was_moving stays false -- calibrating T against the
                             * lagging center node then corrupts the weld (the
                             * "camera detaches when carried/falling" bugs). */
                            g_calib_wait = 30;
                        } else if (g_calib_wait > 0) {
                            g_calib_wait--;
                        } else {
                            g_tx = centerW.x - feet.x;
                            g_tz = centerW.z - feet.z;
                            g_have_t = 1;
                        }

                        if (g_have_t) {
                            eyeW.x = head.x + g_tx;
                            eyeW.z = head.z + g_tz;
                        } else {                       /* until first calibration */
                            eyeW.x = centerW.x + h.x; eyeW.z = centerW.z + h.z;
                        }
                        if (!g_cfg_cam_weld) {
                            /* UN-WELDED (TPS-controller feel): horizontal anchor =
                             * the MOVER (feet) instead of the animated head bone, so
                             * step sway / combat-anim lurches never reach the camera;
                             * height = head height through a strong low-pass, so
                             * crouch/knockdown still track but per-step bob is
                             * filtered. Large jumps (teleport, load, FP re-enter)
                             * snap instead of gliding. */
                            static float smy; static int smy_ok;
                            float ty = eyeW.y;         /* head.y - EYE_DROP from above */
                            if (!smy_ok || fabsf(ty - smy) > 3.0f) { smy = ty; smy_ok = 1; }
                            else smy += (ty - smy) * 0.06f;
                            eyeW.y = smy;
                            if (g_have_t) { eyeW.x = feet.x + g_tx; eyeW.z = feet.z + g_tz; }
                            else          { eyeW.x = centerW.x;     eyeW.z = centerW.z; }
                        }
                        g_dbg_head_x = head.x; g_dbg_center_x = centerW.x;
                        g_eye_from_head = 1;
                    }
                    /* [weld diag] temporary: 6 CONSECUTIVE frames every ~5s --
                     * shows whether the head bone animates per frame (bob/lean)
                     * or goes quasi-static under MOVE_DIRECTION. */
                    static int wd;
                    if (KFP_DEBUG_LOG && ((++wd) % 15) == 0) {
                        int kw = (GetAsyncKeyState(VK_W) & 0x8000) != 0;
                        int ka = (GetAsyncKeyState(VK_A) & 0x8000) != 0;
                        int ks = (GetAsyncKeyState(VK_S) & 0x8000) != 0;
                        int kd = (GetAsyncKeyState(VK_D) & 0x8000) != 0;
                        logline("[weld2] k=%d%d%d%d move=%d dir=%d eyeY=%.2f headY=%.2f feetY=%.2f centerY=%.2f tx=%.1f",
                                kw, ka, ks, kd, g_was_moving, g_was_direct,
                                eyeW.y, head.y, feet.y, centerW.y, g_tx);
                    }
                }
            }
            /* [weld diag] why did the head branch fail while moving? */
            if (KFP_DEBUG_LOG && !g_eye_from_head && g_was_moving) {
                static int fl;
                if ((++fl % 30) == 1) {
                    void *pcd = fp_controlled_char(gw);
                    Vec3 fd = {0,0,0}; int cpok = pcd && char_position(pcd, &fd);
                    logline("[weld] FALLBACK while moving: pc=%p charpos=%d gbw=%p feet=(%.1f,%.1f,%.1f)",
                            pcd, cpok, (void *)g_get_bone_world, fd.x, fd.y, fd.z);
                }
            }
            /* [wtrc] post-landing weld trace: which branch drove the eye, and from
             * what inputs? (the detach reproduces only after landings while moving) */
            if (g_fall_trace_t > 0.0f) {
                static float wtacc2; static double wt_last;
                wtacc2 += 0.02f;   /* approx; rate-limit only */
                (void)wt_last;
                static int wtn;
                if ((++wtn % 8) == 0)
                    logline("[wtrc] fromhead=%d haveT=%d wait=%d tx=%.1f tz=%.1f eye=(%.1f,%.1f,%.1f) center=(%.1f,%.1f)",
                            g_eye_from_head, g_have_t, g_calib_wait, g_tx, g_tz,
                            eyeW.x, eyeW.y, eyeW.z, centerW.x, centerW.z);
            }

            /* EXACT weld-lag compensation. The head sample above predates this
             * frame's root motion: the character node is moved AFTER this hook
             * (CharMovement::update -> AnimationClass apply), so the rendered
             * body ends up currentMotion * (real dt * gameSpeed) AHEAD of the
             * sampled head -- the "camera trails the body" lag, growing with
             * fast-forward. currentMotion(+0xA8) is the mover's world velocity
             * in u/s at 1x (the engine multiplies it by scaled dt), so adding
             * exactly that displacement, AS A VECTOR along the motion, predicts
             * the applied position: self-scales with game speed, framerate and
             * heading (strafe/backpedal included). Replaces the old scalar
             * move_forward heuristic (framerate-blind, camera-yaw-aligned, and
             * its speed input collapsed at >=2x when the fixed teleport gate
             * rejected all run samples). move_forward now SCALES the exact
             * prediction: 1.0 = physically exact (new default), 0 = off. */
            float gs = readable((void *)((uintptr_t)gw + GW_FRAMESPEED), 4)
                     ? *(float *)((uintptr_t)gw + GW_FRAMESPEED) : 1.0f;
            if (!(gs >= 1.0f)) gs = 1.0f;          /* paused/garbage -> treat as 1x */
            if (gs > 6.0f) gs = 6.0f;              /* clamp (max button is 5x) */
            float leadx = 0.0f, leadz = 0.0f;
            /* Weld path only (the un-welded feet anchor has no lag), and only
             * while the mover normally drives motion -- during ragdoll/fall the
             * mod renders the arc itself and currentMotion can hold a stale
             * launch velocity. */
            if (g_cfg_cam_weld && !g_is_down && !g_fall_active
                && g_fall_rd == FALLRD_OFF) {
                void *pcl = fp_controlled_char(gw);
                void *mvl = (pcl && readable((void *)((uintptr_t)pcl + CHAR_MOVEMENT), 8))
                          ? *(void **)((uintptr_t)pcl + CHAR_MOVEMENT) : NULL;
                if (mvl && readable((void *)((uintptr_t)mvl + MV_CURRENT_MOTION), 12)) {
                    Vec3 cml = *(Vec3 *)((uintptr_t)mvl + MV_CURRENT_MOTION);
                    float ldt = (g_frame_dt > 0.0f && g_frame_dt < 0.25f) ? g_frame_dt : 0.016f;
                    if (cml.x*cml.x + cml.z*cml.z < 400.0f * 400.0f) {   /* garbage guard */
                        leadx = cml.x * ldt * gs * FP_MOVE_FORWARD;
                        leadz = cml.z * ldt * gs * FP_MOVE_FORWARD;
                    }
                    if (KFP_DEBUG_LOG) {   /* field verification: lag prediction */
                        static int ldn;
                        if (((++ldn) % 180) == 0 && (leadx != 0.0f || leadz != 0.0f))
                            logline("[lead] gs=%.1f cm=(%.1f,%.1f) dt=%.4f lead=(%.2f,%.2f) mspd=%.1f",
                                    gs, cml.x, cml.z, ldt, leadx, leadz, g_move_speed);
                    }
                }
            }
            /* TRUE HEAD ATTACHMENT: the anatomical eye offset lives in the HEAD BONE's
             * frame -- offset = R_yaw(bodyFacing) * headDerived * faceLocal(bind), so the
             * camera rides the head's ACTUAL animated orientation (bob, spine lean, nod,
             * hurt sways) instead of a synthetic camera-angle push. Orientation stays
             * mouse-driven (attaching it would feed back into the aim offsets).
             * The movement LEAD stays horizontal: it compensates horizontal weld lag. */
            int headAttached = 0;
            if (g_cfg_cam_weld && g_loco_ready && g_loco_head && g_oldnode_getdori
                && g_loco_in_havebody) {
                const Quat *hd = g_oldnode_getdori(g_loco_head);
                if (readable((void *)hd, 16)) {
                    Vec3 fs = quat_rotvec(*hd, g_head_facelocal);   /* skeleton space */
                    float cy = cosf(g_face_yaw), sy = sinf(g_face_yaw);
                    eyeW.x +=  (cy * fs.x + sy * fs.z) * FP_EYE_FORWARD + leadx;
                    eyeW.y +=  fs.y * FP_EYE_FORWARD;
                    eyeW.z += (-sy * fs.x + cy * fs.z) * FP_EYE_FORWARD + leadz;
                    headAttached = 1;
                }
            }
            if (!headAttached) {   /* un-welded / loco off / head unavailable:
                                    * camera-angle push (no head-frame coupling) */
                float cp = cosf(g_pitch), sp = sinf(g_pitch);
                eyeW.x += sinf(g_yaw) * FP_EYE_FORWARD * cp + leadx;
                eyeW.z += cosf(g_yaw) * FP_EYE_FORWARD * cp + leadz;
                eyeW.y -= FP_EYE_FORWARD * sp;   /* g_pitch > 0 = looking down */
            }
            /* Player camera placement (over-the-shoulder third person etc):
             * world-vertical raise + lateral shift along the camera-right vector
             * (same handedness as the D-strafe heading). Applied on top of both
             * eye paths so the offsets behave identically with loco on or off. */
            if (g_cfg_eye_up != 0.0f || g_cfg_eye_shift != 0.0f) {
                eyeW.y += g_cfg_eye_up;
                eyeW.x += -cosf(g_yaw) * g_cfg_eye_shift;
                eyeW.z +=  sinf(g_yaw) * g_cfg_eye_shift;
            }

            /* Eye follows the head bone RAW (no horizontal smoothing) so the
             * camera stays welded through the run animation's forward lean --
             * a low-pass here made the camera lag the leaning head, most
             * visible at high game speed. Input smoothness comes from
             * DirectInput now, not from damping the eye path. */

            fp_view_apply(&eyeW); /* distance/collision after calibrated eye anchor */
            g_dbg_center_y = centerW.y; g_dbg_eye_y = eyeW.y;   /* for tuning */
            /* [fdbg] eye trace, every camera frame while airborne: this is the
             * position the player actually SEES. Repeated y across consecutive
             * lines (camera frozen between fall-arc ticks) or uneven y steps =
             * the descent jitter, measured at its output. */
            if (KFP_DEBUG_LOG && (g_fall_active || g_fall_rd == FALLRD_AIRBORNE))
                logline("[fdbg] eye y=%.2f x=%.1f z=%.1f", eyeW.y, eyeW.x, eyeW.z);
            g_node_set_dpos(node, &eyeW);
            g_last_eye = eyeW;             /* for the mid-frame re-assert */

            /* [foliage diag] how far is the game's per-frame camera position (used
             * by grass paging) from our FP eye? A large gap => grass pages around
             * the wrong point => pop-in under the feet. (2026-08-24 per-frame trace:
             * pre/eye/center all march smoothly, gap 3-13u, no oscillation -- the
             * foliage flicker was z-buffer precision vs near_clip, NOT camera churn;
             * see g_cfg_nearclip and re/NOTES.md 2026-08-25.) */
            if (KFP_DEBUG_LOG && have_pre) {
                static int fcnt;
                if (((++fcnt) % 120) == 0) {
                    float ddx = cam_pre.x - eyeW.x, ddy = cam_pre.y - eyeW.y, ddz = cam_pre.z - eyeW.z;
                    logline("[foliage] cam_pre=(%.1f,%.1f,%.1f) fp_eye=(%.1f,%.1f,%.1f) gap=%.1f (dY=%.1f)",
                            cam_pre.x, cam_pre.y, cam_pre.z, eyeW.x, eyeW.y, eyeW.z,
                            sqrtf(ddx*ddx + ddy*ddy + ddz*ddz), ddy);
                }
            }
        }

        /* World look orientation q = q_yaw(Y) * q_pitch(X); no roll. Ogre camera
         * looks down -Z at identity. DERIVED (world) with normal inheritance. */
        float oyaw = g_yaw + (g_view.applied > 0.001f ? g_view_orbit : 0.0f);   /* test orbit (zoomed out) */
        float qy = cosf(oyaw * 0.5f),   sqy = sinf(oyaw * 0.5f);
        float qp = cosf(g_pitch * 0.5f), sqp = sinf(g_pitch * 0.5f);
        Quat q = { qy * qp, qy * sqp, sqy * qp, -sqy * sqp };

        /* Ragdoll orientation follow: while knocked down, tumble the view with
         * the head. We track the head's world orientation as the "upright"
         * reference WHILE NOT down, and freeze it when down -- so delta =
         * head_now * conj(upright) is the pure world-space rotation the head has
         * undergone from standing (bone-axis convention cancels). Apply that to
         * the look direction, blended in/out so knockdown and get-up are smooth. */
        {
            void *pc2 = fp_controlled_char(gw);
            void *anim = (pc2 && readable((void *)((uintptr_t)pc2 + CHAR_ANIM), 8))
                ? *(void **)((uintptr_t)pc2 + CHAR_ANIM) : NULL;
            int is_down = readable((void *)((uintptr_t)anim + ANIM_RAGDOLL_MASK + 4), 4)
                          && *(unsigned int *)((uintptr_t)anim + ANIM_RAGDOLL_MASK) != 0;
            Quat qh;
            if (pc2 && get_head_quat(pc2, &qh)) {
                /* Discriminate knocked-out (head heavily rolled -> follow + freeze
                 * look) from crawling-crippled (head near-upright, still conscious
                 * -> keep normal look). Tilt = angle between head-now and upright. */
                float tiltdeg = 0.0f;
                if (g_have_qref) {
                    Quat d = quat_norm(quat_mul(qh, quat_conj(g_qref)));
                    float w = d.w; if (w < 0) w = -w; if (w > 1) w = 1;
                    tiltdeg = 2.0f * acosf(w) * 57.29578f;
                }
                /* Require the head to actually be low (body prone), not just the
                 * ragdoll-parts mask + head tilt -- a critically injured but
                 * UPRIGHT character sets the mask and can slump the head past the
                 * tilt threshold while still standing (head stays ~1.6m up).
                 * PS_KO (authoritative prone state) triggers it directly too: the
                 * tilt heuristic needs an UPRIGHT reference (g_qref) captured
                 * before the knockdown, which we DON'T have after switching to a
                 * character who is ALREADY unconscious -- so the vignette used to
                 * vanish on swap. PS_KO doesn't need the reference. */
                int ko = char_prone_state(pc2) == PS_KO;
                /* PT16 (Shay 2026-10-07): KO'd and carried, the view sat upright at the carried body's head
                 * ("standing on the carrier's shoulders"): carried counts as down (view follows the head,
                 * look frozen, upright reference kept from before the pick-up). */
                int carried = fp_char_carried(pc2);
                {   static int prev_carried;
                    if (carried != prev_carried) {
                        Vec3 cf = {0,0,0}; char_position(pc2, &cf);
                        logline("[down] carried=%d ko=%d is_down=%d headY=%.2f feet=%.1f,%.1f,%.1f",
                                carried, ko, is_down, g_head_above, cf.x, cf.y, cf.z);
                        prev_carried = carried;
                    }
                    g_fp_carried = carried; }
                int truly_down = ko || carried ||
                                 (is_down && g_have_qref && tiltdeg > 55.0f
                                  && g_head_above < 0.9f);
                g_is_down = truly_down;   /* next frame's look-input freeze reads this */
                static int prev_down = -1;
                if (KFP_DEBUG_LOG && ((int)truly_down != prev_down || (is_down && !truly_down))) {
                    logline("[orient] is_down=%d truly=%d ko=%d tilt=%.0f headY=%.2f",
                            is_down, truly_down, ko, tiltdeg, g_head_above);
                    prev_down = truly_down;
                }
                /* Freeze the upright reference on the raw ragdoll signal (not on
                 * truly_down) so tilt measures from the pre-down pose and can
                 * actually accumulate as the head rolls -- otherwise it collapses
                 * to the per-frame delta (~0) and never crosses the threshold. */
                if (!is_down && !carried) { g_qref = qh; g_have_qref = 1; }
                float target = truly_down ? 1.0f : 0.0f;
                g_down_blend += (target - g_down_blend) * 0.15f; /* ~0.3s ease */
                if (g_down_blend > 0.002f && g_have_qref) {
                    Quat delta = quat_norm(quat_mul(qh, quat_conj(g_qref)));
                    Quat ragq = quat_norm(quat_mul(delta, q));   /* head tumble applied to view */
                    /* Head bone's local axes are permuted from camera-frame: seat with
                     * a 90-right yaw then a 90-up pitch, applied in the view's frame. */
                    static const Quat YAW90R  = { 0.70710678f, 0.0f, -0.70710678f, 0.0f }; /* -90 Y */
                    static const Quat PITCH90U = { 0.70710678f, -0.70710678f, 0.0f, 0.0f }; /* -90 X */
                    ragq = quat_norm(quat_mul(ragq, quat_mul(YAW90R, PITCH90U)));
                    q = quat_slerp(q, ragq, g_down_blend);
                }
            } else {
                g_down_blend = 0.0f;
            }
        }
        g_node_set_dori(node, &q);
        g_last_ori = q; g_have_eye = 1;    /* mid-frame re-assert now armed */
        vm_frame(g_fp_control_actor, g_fp_control_actor ? fp_body_down(g_fp_control_actor) : 1);

        /* FOV: capture default once, then force the FP FOV each frame. */
        void *ogre_cam = *(void **)((uintptr_t)cam + CC_CAMERA);
        if (g_cam_set_fovy && readable(ogre_cam, 8)) {
            if (!g_fov_saved && g_cam_get_fovy) {
                const float *d = g_cam_get_fovy(ogre_cam);
                /* sanity range ~17..115 deg: never trust a transitional value,
                 * it would get restored on exit and poison future captures */
                if (readable((void *)d, 4) && *d > 0.30f && *d < 2.0f) {
                    g_fov_default = *d; g_fov_saved = 1;
                }
            }
            /* Write ONLY on change: setFovy/setNearClipDistance invalidate the
             * frustum unconditionally (even for an identical value), and vanilla
             * never re-sets them per frame. A per-frame invalidation is exactly
             * the kind of projection churn the PagedGeometry grass (GrassLoader/
             * GrassPage, namespace Forests, main exe) could key page rebuilds
             * off -> near-field grass blinking every frame in FP. */
            float rad = FP_FOV_DEG * DEG2RAD;
            if (rad != g_fov_applied) {
                g_cam_set_fovy(ogre_cam, &rad);
                g_fov_applied = rad;
            }
        }

        /* Near clip: capture default once, then pull it in so nearby meshes
         * don't get clipped away (seeing through walls) at eye level. */
        if (g_cam_set_nearclip && readable(ogre_cam, 8)) {
            if (!g_nearclip_saved && g_cam_get_nearclip) {
                g_nearclip_default = g_cam_get_nearclip(ogre_cam);
                g_nearclip_saved = 1;
                logline("[cam] vanilla clip captured: near=%.4f far=%.1f (fp near_clip=%.3f)",
                        g_nearclip_default,
                        g_cam_get_farclip ? g_cam_get_farclip(ogre_cam) : -1.0f,
                        g_cfg_nearclip);
            }
            if (FP_NEARCLIP != g_nc_applied) {         /* write only on change (see FOV) */
                g_cam_set_nearclip(ogre_cam, FP_NEARCLIP);
                g_nc_applied = FP_NEARCLIP;
            }
        }
    } else if (g_ovr_prev) {
        /* FP exit: release the cursor, restore FOV, and level the node
         * orientation to identity so update()'s incremental rotations no longer
         * drift off our FP angle (position is left for update() to reset). */
        while (ShowCursor(TRUE) < 0) { }
        g_cursor_hidden = 0; g_ui_prev = 0; g_ui_open = 0; g_ui_moveblock = 0;
        g_free_toggle = 0;                      /* clear the free-cursor toggle on exit */
        mygui_cursor(1);                        /* FP exit: restore the game cursor */
        /* widget hides handled post-frame by fp_gui_update (sees !g_fp_mode) */
        g_have_eye = 0;                         /* stop the mid-frame re-assert */
        g_eye_sm_ok = 0; g_lead_sm = 0.0f;      /* reset smoothing state */
        /* Restore FOV/near-clip but KEEP the cached defaults (g_*_saved stays
         * set): re-capturing on every FP enter meant one bad capture (mid-zoom
         * transition) got restored on exit, then read back as "default" on the
         * next enter -- permanently poisoned FOV. Capture once per session. */
        void *ogre_cam = *(void **)((uintptr_t)cam + CC_CAMERA);
        if (g_fov_saved && g_cam_set_fovy && readable(ogre_cam, 8))
            g_cam_set_fovy(ogre_cam, &g_fov_default);
        if (g_nearclip_saved && g_cam_set_nearclip && readable(ogre_cam, 8))
            g_cam_set_nearclip(ogre_cam, g_nearclip_default);
        g_fov_applied = -1.0f; g_nc_applied = -1.0f;   /* re-apply on next FP enter */
        if (KFP_DEBUG_LOG) {   /* one-shot exit-state diagnostic (dev builds only) */
            const Vec3 *lp = g_node_get_pos ? g_node_get_pos(node) : NULL;
            float calt = readable((void *)((uintptr_t)cam + CC_ALTITUDE), 4)
                       ? *(float *)((uintptr_t)cam + CC_ALTITUDE) : -999.0f;
            logline("[fpexit] vzoom=%.1f valt=%.1f fp_pitch=%.2f nodeLocalZ=%.1f camAlt=%.1f",
                    g_vanilla_zoom, g_vanilla_alt, g_pitch, lp ? lp->z : -999.0f, calt);
        }
        /* Restore the vanilla altitude BEFORE the handoff so the RTS camera comes
         * back at its normal height, not at eye level (which reads as "zoomed
         * into the floor"). */
        if (g_vanilla_alt > 0.5f && readable((void *)((uintptr_t)cam + CC_ALTITUDE), 4))
            *(float *)((uintptr_t)cam + CC_ALTITUDE) = g_vanilla_alt;
        /* Seat the vanilla camera at our look direction + the saved zoom via
         * the game's own API. Fixes the endless zoom-out (garbage local pos
         * was left as the zoom) and keeps view continuity on exit. exit_camera_zoom
         * (ini, hot-reload) overrides the distance/side if the auto value is off. */
        /* Our FP look-orientation makes the camera-node +Z the FRONT side, so a
         * positive offset lands the camera in front of the player -- NEGATE it so
         * third-person returns BEHIND. `d` is the (positive) distance behind:
         * auto = the zoom captured on enter, or the exit_camera_zoom override. */
        float d = (g_cfg_exit_zoom != 0.0f) ? g_cfg_exit_zoom : g_vanilla_zoom;
        float exit_zoom = -d;
        if (KFP_DEBUG_LOG)
            logline("[fpexit] exit_zoom=%.1f (dist=%.1f cfg=%.1f auto_vzoom=%.1f)",
                    exit_zoom, d, g_cfg_exit_zoom, g_vanilla_zoom);
        vanilla_cam_handoff(cam, node, exit_zoom);
    }
    g_ovr_prev = active;
}

/* M3: drive the followed character with WASD relative to where we're looking.
 * Breadcrumb CharMovement::setDestination a few metres ahead at ~10 Hz; halt at
 * the current position when all keys release. */
/* --- VEH crash guard: poor-man's __try/__except for calls into game code. ---
 * mingw has no MSVC __try, so: setjmp, guard_arm(), call the game fn; if it
 * faults (or raises an MSVC C++ exception, 0xE06D7363 -- what KenshiCoop's SEH
 * catches around this very call), the vectored handler longjmps back here.
 * guard_arm() zeroes the jmp_buf Frame (this build's setjmp captures RBP, so
 * an unzeroed frame makes longjmp run a real RtlUnwindEx across foreign game
 * frames) and pins the guard to the arming thread -- exceptions on other
 * threads (e.g. the background save thread's routine C++ throws) fall through
 * to the game's own handlers instead of being hijacked. (Declarations hoisted
 * above get_head_quat, which also uses the guard.) */

static void kfp_mod_off(DWORD64 a, char *b, size_t n)
{
    HMODULE m = NULL; char path[MAX_PATH];
    if (a && GetModuleHandleExA(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS | GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT,
                                (LPCSTR)(uintptr_t)a, &m) && m && GetModuleFileNameA(m, path, sizeof path)) {
        const char *sl = strrchr(path, 92);
        snprintf(b, n, "%s+0x%llX", sl ? sl + 1 : path, (unsigned long long)(a - (DWORD64)(uintptr_t)m));
    } else snprintf(b, n, "0x%llX", (unsigned long long)a);
}
/* crash trace: unwind the faulting thread (RtlVirtualUnwind over .pdata; a frame without unwind info, e.g. a
 * call to a garbage address, is treated as a leaf: return address at [rsp]) and log module+offset per frame. */
static void kfp_crash_trace(EXCEPTION_POINTERS *ep)
{
    static char line[2400]; char m[128];
    CONTEXT c = *ep->ContextRecord; EXCEPTION_RECORD *er = ep->ExceptionRecord;
    kfp_mod_off(c.Rip, m, sizeof m);
    int k = snprintf(line, sizeof line, "[crash] code=%08lX tid=%lu rip=%s info=%llX,%llX rcx=%llX rdx=%llX stack:",
                     er->ExceptionCode, GetCurrentThreadId(), m,
                     (unsigned long long)(er->NumberParameters > 0 ? er->ExceptionInformation[0] : 0),
                     (unsigned long long)(er->NumberParameters > 1 ? er->ExceptionInformation[1] : 0),
                     (unsigned long long)c.Rcx, (unsigned long long)c.Rdx);
    for (int i = 0; i < 48 && c.Rip && k < (int)sizeof line - 160; i++) {
        DWORD64 ib = 0; PRUNTIME_FUNCTION f = RtlLookupFunctionEntry(c.Rip, &ib, NULL);
        if (!f) { if (!readable((void *)(uintptr_t)c.Rsp, 8)) break; c.Rip = *(DWORD64 *)(uintptr_t)c.Rsp; c.Rsp += 8; }
        else { PVOID hd = NULL; DWORD64 ef = 0; RtlVirtualUnwind(0 /* UNW_FLAG_NHANDLER */, ib, c.Rip, f, &c, &hd, &ef, NULL); }
        if (!c.Rip) break;
        kfp_mod_off(c.Rip, m, sizeof m); k += snprintf(line + k, sizeof line - k, " < %s", m);
    }
    logline("%s", line);
}

static LONG CALLBACK veh_guard(EXCEPTION_POINTERS *ep)
{
    DWORD code = ep->ExceptionRecord->ExceptionCode;
    if (g_guard_armed && g_guard_tid == GetCurrentThreadId() &&
        (code == EXCEPTION_ACCESS_VIOLATION || code == EXCEPTION_ILLEGAL_INSTRUCTION
         || code == EXCEPTION_PRIV_INSTRUCTION || code == 0xE06D7363u /* MSVC C++ throw */
         || code == EXCEPTION_IN_PAGE_ERROR || code == EXCEPTION_INT_DIVIDE_BY_ZERO
         || code == EXCEPTION_INT_OVERFLOW || code == EXCEPTION_ARRAY_BOUNDS_EXCEEDED
         || code == EXCEPTION_DATATYPE_MISALIGNMENT)) {
        g_guard_armed = 0;
        longjmp(g_guard_jb, 1);
    }
    if (code == EXCEPTION_ACCESS_VIOLATION || code == EXCEPTION_ILLEGAL_INSTRUCTION || code == EXCEPTION_PRIV_INSTRUCTION) {
        static DWORD64 seen[64]; static volatile LONG nseen; DWORD64 rip = ep->ContextRecord->Rip; int dup = 0;
        for (LONG i = 0; i < nseen && i < 64; i++) if (seen[i] == rip) { dup = 1; break; }
        if (!dup && nseen < 64) { seen[InterlockedIncrement(&nseen) - 1] = rip; kfp_crash_trace(ep); }   /* unguarded fault: log where, once per fault address */
    }
    return EXCEPTION_CONTINUE_SEARCH;
}

/* Any interactive UI panel open? (inventory/loot/trade, stats, window stack,
 * dialogue, ESC menu, overview map/factions/squads, options, prospecting,
 * save/load, modal boxes). Pure reads + tiny getVisible calls, VEH-guarded.
 * Used to free the captured FP cursor whenever the player needs to click UI. */
typedef char (*ui_getvis_t)(void *w);
static int ui_panels_open(void)
{
    static int dead;
    if (dead) return 0;
    uintptr_t B = g_base;

    int mask = 0;

    /* pure static reads */
    if (readable((void *)(B + RVA_GUI_INV_COUNT), 8)
        && *(unsigned long long *)(B + RVA_GUI_INV_COUNT)) mask |= 0x001;
    if (readable((void *)(B + RVA_GUI_STATS_BEG), 16)
        && *(void **)(B + RVA_GUI_STATS_BEG) != *(void **)(B + RVA_GUI_STATS_END)) mask |= 0x002;
    if (readable((void *)(B + RVA_GUI_WINSTACK), 4)) {
        /* The stack holds persistent members (main HUD) even with nothing
         * open -- baseline was 1, which kept the gate stuck. Track the
         * session minimum and flag only counts ABOVE it. */
        unsigned ws = *(unsigned *)(B + RVA_GUI_WINSTACK);
        static unsigned ws_min = 0xffffffffu;
        if (ws < ws_min) ws_min = ws;
        if (ws > ws_min) mask |= 0x004;
    }
    if (readable((void *)(B + RVA_MSGBOX_COUNT), 4)
        && *(unsigned *)(B + RVA_MSGBOX_COUNT)) mask |= 0x008;
    /* right-click context menu: the engine's own cached isVisible byte */
    if (RVA_CTXMENU_VISIBLE && readable((void *)(B + RVA_CTXMENU_VISIBLE), 1)
        && *(unsigned char *)(B + RVA_CTXMENU_VISIBLE)) mask |= 0x400;
    if (readable((void *)(B + RVA_SAVELOAD_PTR), 8)) {
        unsigned char *sv = *(unsigned char **)(B + RVA_SAVELOAD_PTR);
        if (readable(sv, 0x118)
            && (*(void **)(sv + 0x100) || *(void **)(sv + 0x108) || *(void **)(sv + 0x110)))
            mask |= 0x010;
    }

    /* optional singletons: null-check pointer, then a one-line getVisible */
    /* runtime-initialised (RVA_* now read the active version table) */
    const struct { uintptr_t ptr_rva, fn_rva; } chk[] = {
        { RVA_GUI_DLGWND,   RVA_DLG_GETVIS },   /* 0x020 */
        { RVA_ESCMENU_PTR,  RVA_ESC_GETVIS },   /* 0x040 */
        { RVA_OVERVIEW_PTR, RVA_OVW_GETVIS },   /* 0x080 */
        { RVA_OPTIONS_PTR,  RVA_OPT_GETVIS },   /* 0x100 */
        { RVA_PROSPECT_PTR, RVA_PRO_GETVIS },   /* 0x200 */
    };
    if (setjmp(g_guard_jb)) {
        dead = 1;
        logline("ui_panels_open FAULTED -- disabled for this session");
        return 0;
    }
    guard_arm();
    int i;
    for (i = 0; i < 5; i++) {
        if (!chk[i].ptr_rva || !chk[i].fn_rva) continue;   /* unmapped on this build */
        if (!readable((void *)(B + chk[i].ptr_rva), 8)) continue;
        void *w = *(void **)(B + chk[i].ptr_rva);
        if (!readable(w, 0x60)) continue;
        if (((ui_getvis_t)(B + chk[i].fn_rva))(w)) mask |= (0x020 << i);
    }
    g_guard_armed = 0;

    static int last_mask = -1;
    if (KFP_DEBUG_LOG && mask != last_mask) {  /* diag: which check flips the gate */
        last_mask = mask;
        logline("[ui] panel mask=0x%03x", mask);
    }
    g_ui_mask = mask;
    return mask != 0;
}

/* Character::playerMoveOrderDefault(Building* dest, RootObject* subject,
 * Vector3& loc) -- THE vanilla right-click walk order (KenshiLib: vtable +0x318,
 * RVA 0x5D1B30 in the SDK build). Called via the VTABLE SLOT, not a hard-coded
 * RVA: the previous hard-coded 0x5d22b0 was NOT this function (it isn't a
 * Character method in the SDK header at all) -- point releases shift RVAs while
 * the vtable layout stays put, so the slot is correct on every build/edition.
 * Issues/live-updates a Task_Move(0x1d): pathfinds, ground-follows, animates,
 * cancels the current job, and makes a downed/seated/bedded character get up.
 * Crash-guarded. Returns 1 if the call completed, 0 if unavailable/faulted. */
static int try_move_to_pos(void *pc, const Vec3 *tgt)
{
    if (g_movetopos_dead) return 0;
    void **vt = *(void ***)pc;
    if (!in_module(vt)) return 0;
    void (*fn)(void *, void *, void *, const Vec3 *) =
        (void (*)(void *, void *, void *, const Vec3 *))vt[CHAR_VT_PLAYERMOVE];
    if (!in_module((void *)fn)) return 0;
    if (setjmp(g_guard_jb)) {          /* longjmp target: the call blew up */
        g_movetopos_dead = 1;
        g_guard_armed = 0;
        logline("playerMoveOrderDefault FAULTED -- disabled for this session");
        return 0;
    }
    guard_arm();
    fn(pc, NULL, NULL, tgt);          /* NULL,NULL = plain ground point */
    g_guard_armed = 0;
    return 1;
}

/* Character::_currentProneState (member 0xE0): 0 normal, 2 crippled, 3 playing
 * dead, 4 KO. Authoritative -- replaces the head-height heuristic for get-up. */
static int char_prone_state(void *pc)
{
    return readable((void *)((uintptr_t)pc + CHAR_PRONE_STATE), 4)
        ? *(int *)((uintptr_t)pc + CHAR_PRONE_STATE) : PS_NORMAL;
}

/* Set the game's OWN "the player wants me up" flag (member 0xEC). This is what
 * a vanilla move order sets to break a character out of playing-dead / a bed /
 * a seat and start the get-up. A plain, safe memory write -- no call. */
static void char_request_getup(void *pc)
{
    if (readable((void *)((uintptr_t)pc + CHAR_WANTS_GETUP), 1))
        *(unsigned char *)((uintptr_t)pc + CHAR_WANTS_GETUP) = 1;
}

/* Is the character's CURRENT task our walk order (Task_Move 0x1d)? Used to
 * choose moveToPosition's cheap live-update path vs the queue-clearing create
 * path, and to avoid stomping NPC-forced tasks (dialogue, grabs, jobs). */
static int char_task_is_move(void *pc)
{
    void *tholder = readable((void *)((uintptr_t)pc + CHAR_TASKHOLDER), 8)
        ? *(void **)((uintptr_t)pc + CHAR_TASKHOLDER) : NULL;
    if (!readable(tholder, TASK_CUR + 8)) return 0;
    void *cur = *(void **)((uintptr_t)tholder + TASK_CUR);
    if (!readable(cur, TASK_DESC + 8)) return 0;
    void *desc = *(void **)((uintptr_t)cur + TASK_DESC);
    return readable(desc, TASKDESC_TYPE + 4)
        && *(int *)((uintptr_t)desc + TASKDESC_TYPE) == TASK_MOVE_ID;
}

/* Clamp a target point onto the terrain surface via Terrain::getHeight
 * (Plugin_Terrain_x64.dll; pure const query). THE slope fix: the raw mover
 * stalls when the fabricated target Y is underground (uphill) or midair
 * (downhill); an on-ground destination walks fine (right-click parity). */
static void terrain_clamp(Vec3 *p)
{
    if (g_terrain_dead || !g_terrain_getheight) return;
    void *terr = readable((void *)(g_base + RVA_TERRAIN_PTR), 8)
        ? *(void **)(g_base + RVA_TERRAIN_PTR) : NULL;
    if (!readable(terr, 8)) return;
    if (setjmp(g_guard_jb)) {
        g_terrain_dead = 1;
        logline("Terrain::getHeight FAULTED -- disabled for this session");
        return;
    }
    guard_arm();
    TerrainHit hit; memset(&hit, 0, sizeof hit);
    g_terrain_getheight(terr, &hit, p);
    g_guard_armed = 0;
    if (hit.hit) {
        static int logged;
        if (!logged) { logged = 1; logline("terrain clamp live: y %.1f -> %.1f", p->y, hit.position.y); }
        p->y = hit.position.y;
    }
}

/* Cast a ray into the terrain (Terrain::intersect -- the SAME function the
 * game's right-click picking uses). Returns 1 + the surface point on hit.
 * With the FP cursor locked to screen center, eye+look ray == "where a
 * right-click would land". */
static int terrain_ray(const Vec3 *origin, const Vec3 *dir, Vec3 *out)
{
    if (g_terrain_dead || !g_terrain_intersect) return 0;
    void *terr = readable((void *)(g_base + RVA_TERRAIN_PTR), 8)
        ? *(void **)(g_base + RVA_TERRAIN_PTR) : NULL;
    if (!readable(terr, 8)) return 0;
    if (setjmp(g_guard_jb)) {
        g_terrain_dead = 1;
        logline("Terrain::intersect FAULTED -- disabled for this session");
        return 0;
    }
    guard_arm();
    OgreRay ray; ray.origin = *origin; ray.dir = *dir;
    TerrainHit hit; memset(&hit, 0, sizeof hit);
    g_terrain_intersect(terr, &hit, &ray);
    g_guard_armed = 0;
    if (!hit.hit) return 0;
    *out = hit.position;
    return 1;
}

/* --- direct-drive locomotion (indoor-reliable movement) --------------------
 * The engine has a NATIVE direction-driven mode (MOVE_DIRECTION): feed
 * CharMovement::setDirectMovement(dir, limit) a direction each frame and the
 * game's own locomotion moves the character -- collision, floors, ramps,
 * platforms all handled by the engine. No destination point, no pathfinder,
 * no terrain ray: this is what makes movement reliable INSIDE buildings,
 * where the click-order + terrain-ray scheme picked unreachable/underground
 * targets. (Approach learned from smokefoolius/Kenshi-Direct-Control.)
 * Prone/downed characters keep the order path: crawling and the get-up flow
 * need the click-order system, and MOVE_DIRECTION is standing-only. */
#define MV_SPEEDORDERS    0x20     /* CharMovement::speedOrders (MoveSpeed) */
#define MV_MOVEMODE       0x378    /* MovementMode: 0 normal, 1 combat, 2 direction */
#define MV_DESIREDMOTION  0x38C    /* Vector3, consumed when mode==2 */
#define MV_CHARACTER 0x3A8 /* CharMovement::character */
#define MV_HALT_SLOT      (0x98/8) /* vtable: halt() -- cancels current orders */
#define MV_SETSPEED_SLOT  (0xA8/8) /* vtable: setDesiredSpeed(MoveSpeed) */

/* Stop only our own direct vector; preserve native combat/root motion.
 * live = the caller saw pc in the live squad list (fp_char_in_squad). A character that is not
 * (world teardown on load/quit, actor gone) is only forgotten: its CharMovement may already be
 * freed, and freed memory still passes readable() and the handle-id compare, so a write there
 * corrupts the heap (4080 b27b: D3D11 NULL read ~40 s after an in-world reload). */
static void fp_control_release_actor(void *pc,int live) {
    void *mv=g_dm_mv;
    int driven=(g_dm_active || g_was_direct || g_was_moving);
    InterlockedExchange(&g_dm_active,0); InterlockedExchange(&g_face_active,0);
    if (driven && live && char_valid(pc) &&
        readable((void *)((uintptr_t)pc+CHAR_HANDLE+HAND_IDS),20) &&
        !memcmp(g_fp_control_ids,(void *)((uintptr_t)pc+CHAR_HANDLE+HAND_IDS),20) &&
        readable((void *)((uintptr_t)pc+CHAR_MOVEMENT),8) &&
        *(void **)((uintptr_t)pc+CHAR_MOVEMENT)==mv &&
        readable((void *)((uintptr_t)mv+MV_MOVEMODE),4) &&
        *(int *)((uintptr_t)mv+MV_MOVEMODE)==2) {
        if (readable((void *)((uintptr_t)mv+MV_DESIREDMOTION),12))
            memset((void *)((uintptr_t)mv+MV_DESIREDMOTION),0,12);
        *(int *)((uintptr_t)mv+MV_MOVEMODE)=0;
    }
    g_dm_mv=NULL; g_was_moving=0; g_was_direct=0;
    kfp_stuck_idle(&g_stuck_frames);
    g_have_dest=0; g_face_have=0; g_face_turning=0; g_lead_sm=0;
}

/* --- athletics + strength XP for WASD movement (v0.4.6) ---------------------
 * WASD drives the character with MOVE_DIRECTION (setDirectMovement), which
 * bypasses the move-order/pathfinding path where Kenshi calls CharStats::xpRunning
 * to grant athletics (from speed) and strength (from walking-while-encumbered) XP.
 * The character physically moves but never runs the XP routine -- so we call it
 * ourselves each frame we drive it, with the same (frameTime, currentSpeed) the
 * game passes. Crash-guarded: a fault disables just this, not movement. */
typedef void (*xprunning_t)(void *charstats, float time, float speed);
static xprunning_t g_xp_running;
static int g_xp_dead;            /* set on fault -> XP award disabled this session */
static void award_move_xp(void *pc, void *mv, float dt)
{
    if (g_xp_dead || !g_xp_running || !pc || !mv) return;
    if (!(dt > 0.0f) || dt > 1.0f) return;                 /* sane per-frame delta */
    if (!readable((void *)((uintptr_t)pc + CHAR_STATS), 8)) return;
    void *stats = *(void **)((uintptr_t)pc + CHAR_STATS);
    if (!readable(stats, 8)) return;
    float speed = readable((void *)((uintptr_t)mv + MV_CURRENT_SPEED), 4)
                ? *(float *)((uintptr_t)mv + MV_CURRENT_SPEED) : 0.0f;
    if (!(speed > 0.1f)) return;                            /* only while actually moving */
    { static int logged; if (!logged) { logged = 1;
        logline("[xp] WASD athletics/strength XP tick LIVE (stats=%p speed=%.1f)", stats, speed); } }
    if (setjmp(g_guard_jb)) { g_guard_armed = 0; g_xp_dead = 1;
        logline("xpRunning FAULTED -- WASD athletics/strength XP disabled for this session");
        return; }
    guard_arm();
    g_xp_running(stats, dt, speed);
    g_guard_armed = 0;
}

static int combat_char_unconscious(void *pc);   /* kfp_combat_native.inc: medical KO flag */
/* C05-KO trace (4080 b33): the KO'd body still flew 7 km in ONE tick, 58 ms after the knockdown was
 * first seen, with no FP writer armed (dm=0 face=0 fall=0 rd=0). Logged per episode: the last 6
 * standing ticks and the first 12 down ticks, with the CharMovement state a KO ragdoll inherits
 * (currentMotion +0xA8, currentSpeed, desiredMotion, movementMode) and the loco/IK bone ownership.
 * At the knockdown edge the mover's motion is zeroed when no fall/dive owns it, so the ragdoll
 * can't inherit a drive vector (the hold may have left MOVE_DIRECTION state behind). */
typedef struct { DWORD ms; Vec3 p, cm, dmo; float spd; int mode, mask, prone, ko, loco, ikp, dm, wd; void *mover; } KfpDownSample;
static KfpDownSample g_down_ring[6];
static int g_down_ring_n, g_down_ring_i, g_down_trace_left, g_down_prev;
static unsigned g_down_episodes, g_down_motion_cleared;
static void *fp_char_mover(void *pc)
{
    return (pc && readable((void *)((uintptr_t)pc + CHAR_MOVEMENT), 8)) ? *(void **)((uintptr_t)pc + CHAR_MOVEMENT) : NULL;
}
static void fp_down_sample(void *pc, int ko, KfpDownSample *s)
{
    memset(s, 0, sizeof *s);
    s->ms = GetTickCount(); s->mode = -1; s->spd = -1.0f;
    char_position(pc, &s->p);
    void *mv = fp_char_mover(pc);
    if (mv && readable((void *)((uintptr_t)mv + MV_CURRENT_MOTION), 12)) s->cm = *(Vec3 *)((uintptr_t)mv + MV_CURRENT_MOTION);
    if (mv && readable((void *)((uintptr_t)mv + MV_CURRENT_SPEED), 4)) s->spd = *(float *)((uintptr_t)mv + MV_CURRENT_SPEED);
    if (mv && readable((void *)((uintptr_t)mv + MV_DESIREDMOTION), 12)) s->dmo = *(Vec3 *)((uintptr_t)mv + MV_DESIREDMOTION);
    if (mv && readable((void *)((uintptr_t)mv + MV_MOVEMODE), 4)) s->mode = *(int *)((uintptr_t)mv + MV_MOVEMODE);
    if (mv && readable((void *)((uintptr_t)mv + MV_MOVER), 8)) s->mover = *(void **)((uintptr_t)mv + MV_MOVER);
    s->mask = (int)fall_ragdoll_mask(pc); s->prone = char_prone_state(pc); s->ko = ko;
    s->loco = g_loco_ready; s->ikp = g_ik_pospushed; s->dm = (int)g_dm_active; s->wd = g_was_direct;
}
static void fp_down_log(const char *tag, const KfpDownSample *s)
{
    logline("[down] trace %s t=%lu pos=%.1f,%.1f,%.1f cm=%.2f,%.2f,%.2f spd=%.2f desired=%.2f,%.2f,%.2f mode=%d mask=0x%x prone=%d ko=%d loco=%d ikpush=%d dm=%d was_direct=%d physmover=%p",
            tag, (unsigned long)s->ms, s->p.x, s->p.y, s->p.z, s->cm.x, s->cm.y, s->cm.z, s->spd,
            s->dmo.x, s->dmo.y, s->dmo.z, s->mode, (unsigned)s->mask, s->prone, s->ko, s->loco, s->ikp, s->dm, s->wd, s->mover);
}
/* C05-KO fling guard (kfp_fling.h): undo a physically impossible move of the controlled body that
 * starts in a KO/down episode (restore on the wake edge and during the post-wake watch window). */
static KfpFling g_fling;
static void *g_fling_pc;
static int g_wake_trace_left;
static void fp_fling_restore(void *pc, const KfpDownSample *s)
{
    Vec3 back = { g_fling.ax, g_fling.ay + 0.5f, g_fling.az };
    float yaw = g_face_have ? g_face_yaw : g_yaw;
    float q[4] = { cosf(yaw * 0.5f), 0.0f, sinf(yaw * 0.5f), 0.0f };
    if (g_char_setdest) g_char_setdest(pc, &back, q);
    fall_restore_mover(pc);
    void *mv = fp_char_mover(pc);
    if (mv && readable((void *)((uintptr_t)mv + MV_CURRENT_MOTION), 12)) memset((void *)((uintptr_t)mv + MV_CURRENT_MOTION), 0, 12);
    if (mv && readable((void *)((uintptr_t)mv + MV_CURRENT_SPEED), 4)) *(float *)((uintptr_t)mv + MV_CURRENT_SPEED) = 0.0f;
    fp_mover_clear_direct(mv, MV_MOVEMODE, MV_DESIREDMOTION, 0);
    if (mv && readable(mv, 8)) { void **vt = *(void ***)mv; if (in_module(vt)) ((void (*)(void *))vt[MV_HALT_SLOT])(mv); }
    g_have_last_feet = 0; g_move_speed = 0.0f; g_have_prevraw = 0; g_rebase_hold_t = 1.0f;
    Vec3 now = s->p; char_position(pc, &now);
    logline("[down] FLING undone (restore %d, total %u): body at %.1f,%.1f,%.1f -> back to %.1f,%.1f,%.1f (now %.1f,%.1f,%.1f) last_jump=%.1f physmover=%p",
            g_fling.restores, g_fling.restored, s->p.x, s->p.y, s->p.z, back.x, back.y, back.z, now.x, now.y, now.z,
            g_fling.last_jump, s->mover);
    g_wake_trace_left = 30;
}
static void fp_down_trace(void *pc, int body_down, int ko)
{
    KfpDownSample s;
    fp_down_sample(pc, ko, &s);
    if (pc != g_fling_pc) { kfp_fling_reset(&g_fling); g_fling_pc = pc; }
    {
        int fr = kfp_fling_step(&g_fling, body_down, s.p.x, s.p.y, s.p.z, (unsigned)s.ms);
        if (fr == KFP_FLING_DETECTED) {
            logline("[down] FLING detected (%s): jump %.1f units to %.1f,%.1f,%.1f; anchor %.1f,%.1f,%.1f cm=%.2f,%.2f,%.2f mode=%d mask=0x%x physmover=%p",
                    body_down ? "while down" : "restore budget spent", g_fling.last_jump, s.p.x, s.p.y, s.p.z,
                    g_fling.ax, g_fling.ay, g_fling.az, s.cm.x, s.cm.y, s.cm.z, s.mode, (unsigned)s.mask, s.mover);
            if (body_down && g_down_trace_left < 12) g_down_trace_left = 12;
        } else if (fr == KFP_FLING_RESTORE) fp_fling_restore(pc, &s);
    }
    if (!body_down && g_down_prev) {   /* wake edge: trace the get-up (b36b drifted ~10 km after the wake) */
        logline("[down] wake edge: pos=%.1f,%.1f,%.1f physmover=%p cm=%.2f,%.2f,%.2f spd=%.2f mode=%d flung=%d",
                s.p.x, s.p.y, s.p.z, s.mover, s.cm.x, s.cm.y, s.cm.z, s.spd, s.mode, g_fling.flung);
        if (g_wake_trace_left < 30) g_wake_trace_left = 30;
    }
    if (!body_down && g_wake_trace_left > 0) {
        static DWORD wlast;
        if (s.ms - wlast >= 100u || g_wake_trace_left == 30) { wlast = s.ms; --g_wake_trace_left; fp_down_log("wake", &s); }
    }
    if (body_down && !g_down_prev) {
        ++g_down_episodes;
        /* Always one line per knockdown edge with the mover state (b34: a later save load crashed at
         * exe+0x37f665 after a fling), whether or not the motion is cleared below. */
        logline("[down] knockdown edge #%u: mover=%p cm=%.2f,%.2f,%.2f spd=%.2f mode=%d fall_rd=%d fall_active=%d ko=%d mask=0x%x prone=%d",
                g_down_episodes, fp_char_mover(pc), s.cm.x, s.cm.y, s.cm.z, s.spd, s.mode, (int)g_fall_rd, (int)g_fall_active,
                ko, (unsigned)s.mask, s.prone);
        int n = g_down_ring_n < 6 ? g_down_ring_n : 6;
        for (int i = 0; i < n; ++i) fp_down_log("pre", &g_down_ring[(g_down_ring_i + 6 - n + i) % 6]);
        g_down_trace_left = 12;
        void *mv = fp_char_mover(pc);
        if (mv && g_fall_rd == FALLRD_OFF && !g_fall_active
            && readable((void *)((uintptr_t)mv + MV_CURRENT_MOTION), 12)
            && readable((void *)((uintptr_t)mv + MV_CURRENT_SPEED), 4)) {
            Vec3 *cm = (Vec3 *)((uintptr_t)mv + MV_CURRENT_MOTION);
            logline("[down] knockdown edge: mover motion cleared (cm was %.2f,%.2f,%.2f spd=%.2f mode=%d)",
                    cm->x, cm->y, cm->z, *(float *)((uintptr_t)mv + MV_CURRENT_SPEED), s.mode);
            cm->x = cm->y = cm->z = 0.0f;
            *(float *)((uintptr_t)mv + MV_CURRENT_SPEED) = 0.0f;
            ++g_down_motion_cleared;
        }
    }
    if (body_down && g_down_trace_left > 0) { --g_down_trace_left; fp_down_log("down", &s); }
    if (!body_down) {
        g_down_ring[g_down_ring_i] = s; g_down_ring_i = (g_down_ring_i + 1) % 6;
        if (g_down_ring_n < 6) ++g_down_ring_n;
    }
    g_down_prev = body_down;
}

static void fp_gait_read(void *mv)
{
    g_gm_max  = readable((void *)((uintptr_t)mv + MV_MAX_SPEED), 4) ? *(float *)((uintptr_t)mv + MV_MAX_SPEED) : -1.0f;
    g_gm_des  = readable((void *)((uintptr_t)mv + MV_DESIRED_SPEED), 4) ? *(float *)((uintptr_t)mv + MV_DESIRED_SPEED) : -1.0f;
    g_gm_walk = readable((void *)((uintptr_t)mv + MV_WALK_SPEED), 4) ? *(float *)((uintptr_t)mv + MV_WALK_SPEED) : -1.0f;
    g_gm_cur  = readable((void *)((uintptr_t)mv + MV_CURRENT_SPEED), 4) ? *(float *)((uintptr_t)mv + MV_CURRENT_SPEED) : -1.0f;
}
/* PT04: hand the char its vanilla speed order back (pc must be live: a freed CharMovement still passes readable()). */
static void fp_gait_restore(void *pc, const char *why)
{
    if (g_dm_vso < 0) return;
    int vso = g_dm_vso; void *vpc = g_dm_vso_pc;
    g_dm_vso = -1; g_dm_vso_pc = NULL;
    if (g_gm_t > 0.0f)
        logline("[move] gait hold end (%s): drove %s (vanilla order %s) %.2f game s, %.1f u, rate_avg=%.1f u/s (from 1 s)"
                " peak_win=%.1f | mover max=%.1f desired=%.1f walk=%.1f current=%.1f", why, gait_name(g_gm_gait),
                gait_name(g_gm_vso), g_gm_t, g_gm_dist, g_gm_t1 > 0.0f ? g_gm_dist1 / g_gm_t1 : 0.0f, g_gm_peak,
                g_gm_max, g_gm_des, g_gm_walk, g_gm_cur);
    if (!pc || pc != vpc || !char_valid(pc)) return;   /* actor gone/changed: forget only */
    void *mv = fp_char_mover(pc);
    if (!readable(mv, 8) || !readable((void *)((uintptr_t)mv + MV_SPEEDORDERS), 4)) return;
    void **vt = *(void ***)mv;
    if (!in_module(vt) || !in_module(vt[MV_SETSPEED_SLOT])) return;
    *(int *)((uintptr_t)mv + MV_SPEEDORDERS) = vso;
    ((void (*)(void *, int))vt[MV_SETSPEED_SLOT])(mv, vso);
    ++g_gm_restores;
}
/* PT04 meter: called every direct-drive frame (start = first frame of a hold). */
static void fp_gait_meter(void *gw, void *pc, void *mv, int start)
{
    LARGE_INTEGER now, fq; QueryPerformanceCounter(&now); QueryPerformanceFrequency(&fq);
    Vec3 p; int have = char_position(pc, &p);
    float fs = (gw && readable((void *)((uintptr_t)gw + GW_FRAMESPEED), 4)) ? *(float *)((uintptr_t)gw + GW_FRAMESPEED) : 1.0f;
    if (start) {
        g_gm_t = g_gm_dist = g_gm_dist1 = g_gm_t1 = g_gm_win = g_gm_wint = g_gm_winrate = g_gm_peak = 0.0f;
        g_gm_gait = g_dm_speed; g_gm_vso = g_dm_vso; ++g_gm_holds;
        fp_gait_read(mv);
        logline("[move] gait hold start: drive %s (vanilla order %s) | mover max=%.1f desired=%.1f walk=%.1f",
                gait_name(g_dm_speed), gait_name(g_dm_vso), g_gm_max, g_gm_des, g_gm_walk);
    } else if (g_gm_have && have) {
        float rdt = (float)(now.QuadPart - g_gm_qpc.QuadPart) / (float)fq.QuadPart;
        float gdt = rdt * (fs > 0.0f && fs < 1000.0f ? fs : 1.0f);
        float dx = p.x - g_gm_last.x, dz = p.z - g_gm_last.z, d = sqrtf(dx * dx + dz * dz);
        if (rdt > 0.0f && rdt < 0.5f && d < 400.0f) {     /* a hitch / teleport is not a gait sample */
            g_gm_t += gdt; g_gm_dist += d;
            if (g_gm_t > 1.0f) { g_gm_t1 += gdt; g_gm_dist1 += d; }
            g_gm_win += d; g_gm_wint += gdt;
            if (g_gm_wint >= 0.5f) {
                g_gm_winrate = g_gm_win / g_gm_wint;
                if (g_gm_winrate > g_gm_peak) g_gm_peak = g_gm_winrate;
                g_gm_win = g_gm_wint = 0.0f;
            }
        }
        fp_gait_read(mv);
    }
    g_gm_qpc = now; g_gm_last = p; g_gm_have = have;
}
/* C04-TAKE: why direct drive is refused while movement keys are held for the controlled actor.
 * Logged on a reason change, else at most every 2 s; a NULL reason (drive engaged / no keys)
 * re-arms it. */
static void fp_move_refusal(const char *why)
{
    static const char *last; static DWORD last_ms;
    if (!why) { last = NULL; return; }
    DWORD now = GetTickCount();
    if (why == last && now - last_ms < 2000) return;
    last = why; last_ms = now;
    logline("[move] direct drive refused for the controlled actor: %s (prone=%d bed=%d head=%.2f pinned=%d"
            " ui_moveblock=%d down=%d fall=%d)", why, g_dbg_prone, g_dbg_in_bed, g_head_above,
            g_stuck_frames > KFP_STUCK_PINNED_FRAMES, g_ui_moveblock, g_is_down, g_fall_active);
}
static int fp_move_keys_held(void)
{
    if (g_kah_move_keys) return 1;
    return game_has_focus() && ((GetAsyncKeyState(VK_W) | GetAsyncKeyState(VK_A)
                                 | GetAsyncKeyState(VK_S) | GetAsyncKeyState(VK_D)) & 0x8000);
}

static void fp_movement(void *gw, float dt)
{
    if (!g_fp_mode || !g_charmove_setdest) {
        if (g_dm_vso >= 0) fp_gait_restore(fp_controlled_char(gw), "fp off");
        InterlockedExchange(&g_dm_active, 0);   /* FP off mid-hold: stand down */
        InterlockedExchange(&g_face_active, 0);
        g_face_have = 0; g_face_turning = 0;
        return;
    }
    void *pc = fp_controlled_char(gw);
    if (!pc) return;
    /* While ragdolled (incl. a fall in progress) the physics owns the body -- our per-frame
     * move orders would drag it back onto walkable ground (that was the "pushed back" bug).
     * Stand the driver down and let the game land + get up on its own. */
    /* C05-KO (4080 b30): the KO sets the medical unconscious flag at once, but the prone state
     * (4) and g_is_down follow only when the body has fallen; until then the standing branch
     * below kept direct drive on a KO'd actor (dm_active=1 on the first KO sample). */
    int ko_now = combat_char_unconscious(pc);
    g_dbg_ko = ko_now;
    int body_down = fp_body_down(pc);
    {   /* C05-KO evidence: any large per-tick jump of a downed body, with which FP writers were armed */
        static Vec3 dprev; static int dhave;
        Vec3 dp;
        if (body_down && char_position(pc, &dp)) {
            float jx = dp.x - dprev.x, jy = dp.y - dprev.y, jz = dp.z - dprev.z;
            if (dhave && jx * jx + jy * jy + jz * jz > 100.0f * 100.0f)
                logline("[down] position jump %.0f,%.0f,%.0f -> %.0f,%.0f,%.0f while down (ko=%d mask=0x%x prone=%d dm=%ld face=%ld fall=%d rd=%d)",
                        dprev.x, dprev.y, dprev.z, dp.x, dp.y, dp.z, ko_now, fall_ragdoll_mask(pc), char_prone_state(pc),
                        g_dm_active, g_face_active, g_fall_active, (int)g_fall_rd);
            dprev = dp; dhave = 1;
        } else dhave = 0;
        if (!body_down) g_down_note_mask = 0;   /* next episode logs again */
    }
    fp_down_trace(pc, body_down, ko_now);
    if (body_down || g_fall_active || g_fall_rd != FALLRD_OFF) {
        if (fp_move_keys_held()) fp_move_refusal(body_down ? "body down (ragdoll/KO)" : "falling");
        /* C05-KO: keys held into a knockdown are dropped (no walk resumes on get-up) */
        if (body_down && g_kah_move_keys) { InterlockedExchange(&g_kah_move_keys, 0); logline("[down] held fp_move keys dropped on knockdown"); }
        InterlockedExchange(&g_dm_active, 0);
        InterlockedExchange(&g_face_active, 0);
        g_was_moving = 0; g_face_turning = 0;
        /* C01/C02/C05 (4080 b30/b31): restart the pinned estimate and drop the stale walk target here --
         * the release branch below is gated on g_was_moving, which this stand-down just cleared, so a
         * stale "pinned" sent the next W hold down the order path. */
        kfp_stuck_idle(&g_stuck_frames);
        g_have_dest = 0; g_lead_sm = 0.0f;
        g_dbg_prone = char_prone_state(pc); g_dbg_downed = 1;
        /* C05-KO: a hold that was direct-driving leaves MOVE_DIRECTION + desired motion
         * behind; clear them once (the fall driver owns currentMotion, so leave that). */
        if (body_down && g_was_direct) {
            void *dmv = readable((void *)((uintptr_t)pc + CHAR_MOVEMENT), 8)
                ? *(void **)((uintptr_t)pc + CHAR_MOVEMENT) : NULL;
            fp_mover_clear_direct(dmv, MV_MOVEMODE, MV_DESIREDMOTION, 0);
            g_was_direct = 0;
        }
        fp_gait_restore(pc, "body down / falling");
        /* Facing state: cleared ONLY for the ragdoll tiers (the body tumbles,
         * its final yaw is genuinely unknown). The walk-off/jump arc keeps the
         * body on its feet with its committed facing -- clearing g_face_have
         * here killed g_loco_in_havebody one frame into EVERY arc, which shut
         * down the airborne leg tuck ([air] fired exactly once per session)
         * and re-seeded the facing from scratch at each landing. */
        if (body_down || g_fall_rd != FALLRD_OFF) g_face_have = 0;
        return;
    }
    void *mv = readable((void *)((uintptr_t)pc + CHAR_MOVEMENT), 8)
        ? *(void **)((uintptr_t)pc + CHAR_MOVEMENT) : NULL;
    if (!readable(mv, 8)) { if (fp_move_keys_held()) fp_move_refusal("no CharMovement"); return; }

    /* Wheel consumed by fp_view_input; locomotion speed is independent. */

    int w = (game_has_focus() && (GetAsyncKeyState(VK_W) & 0x8000) != 0) || kah_move_key(1);
    int s = (game_has_focus() && (GetAsyncKeyState(VK_S) & 0x8000) != 0) || kah_move_key(2);
    int a = (game_has_focus() && (GetAsyncKeyState(VK_A) & 0x8000) != 0) || kah_move_key(4);
    int d = (game_has_focus() && (GetAsyncKeyState(VK_D) & 0x8000) != 0) || kah_move_key(8);
    int keys = w | (s << 1) | (a << 2) | (d << 3);
    float mf = (float)(w - s);     /* forward/back */
    float mr = (float)(d - a);     /* left/right (turns the char, not strafe) */

    (void)dt;
    /* Treat a HARD UI block (dialogue/cutscene, control disabled) as keys-
     * released: halt if moving. A plain side panel does NOT block movement --
     * WASD keeps walking the character while inventory/squad/jobs are open,
     * matching vanilla (which still pans the camera then). */
    if (g_ui_moveblock || keys == 0 || (mf == 0.0f && mr == 0.0f)) {
        if (keys && g_ui_moveblock) fp_move_refusal("ui_moveblock (dialogue/cutscene/control disabled)");
        else if (!keys) fp_move_refusal(NULL);
        if (g_was_moving) {         /* release: halt at current position */
            if (g_was_direct) {
                /* direct drive: instant stop -- zero the motion, return the
                 * mode to normal so vanilla ordering owns the character again */
                InterlockedExchange(&g_dm_active, 0);
                if (readable((void *)((uintptr_t)mv + MV_DESIREDMOTION), 12)) {
                    Vec3 *dm = (Vec3 *)((uintptr_t)mv + MV_DESIREDMOTION);
                    dm->x = dm->y = dm->z = 0.0f;
                    *(int *)((uintptr_t)mv + MV_MOVEMODE) = 0;   /* MOVE_NORMAL */
                }
                g_was_direct = 0;
                fp_gait_restore(pc, "keys released");
                /* Belt-and-suspenders: if a Task_Move somehow re-appeared during
                 * the hold, replace it with stop-here so releasing WASD leaves us
                 * where we stopped instead of resuming an old destination. */
                Vec3 hpos;
                if (char_task_is_move(pc) && char_position(pc, &hpos))
                    try_move_to_pos(pc, &hpos);
            } else {
                Vec3 here;
                /* Halt ONLY if our walk task still owns the character. If an
                 * NPC-forced task (dialogue, grab, arrest) took over, issuing a
                 * halt would CLEAR their queue mid-mutation -> crash. */
                if (char_task_is_move(pc) && char_position(pc, &here)) {
                    if (!try_move_to_pos(pc, &here))   /* order to current pos = stop */
                        g_charmove_setdest(mv, &here, UPDATE_PRIORITY_HIGH, 0);
                }
            }
            g_was_moving = 0;
            g_have_dest = 0;
            g_lead_sm = 0.0f;           /* fresh lead estimate on next move */
        }
        kfp_stuck_idle(&g_stuck_frames);    /* fresh pinned estimate on next move (any release, kfp_stuck.h) */
        /* ACTIVE BRAKE (all tiers): proportionally damp the mover's residual velocity
         * every glide frame -- cuts the momentum slide roughly in half at the default
         * loco_brake=6 (walk, jog AND sprint), for a more responsive stop across the
         * board. Below walking pace, finish with a clean halt. */
        if (g_loco_ready && g_cfg_loco_facelock && g_move_speed > 0.5f) {
            float bdt = (dt > 0.0f && dt < 0.25f) ? dt : 0.016f;
            float bk = expf(-g_cfg_loco_brake * bdt);
            if (readable((void *)((uintptr_t)mv + MV_CURRENT_MOTION), 12)) {
                Vec3 *cmb = (Vec3 *)((uintptr_t)mv + MV_CURRENT_MOTION);
                cmb->x *= bk; cmb->y *= bk; cmb->z *= bk;
            }
            if (readable((void *)((uintptr_t)mv + MV_CURRENT_SPEED), 4))
                *(float *)((uintptr_t)mv + MV_CURRENT_SPEED) *= bk;
            if (g_move_speed < 2.0f) {
                void **mvbrk = *(void ***)mv;
                if (in_module(mvbrk)) ((void (*)(void *))mvbrk[MV_HALT_SLOT])(mv);
                if (readable((void *)((uintptr_t)mv + MV_DESIREDMOTION), 12)) {
                    Vec3 *dmv = (Vec3 *)((uintptr_t)mv + MV_DESIREDMOTION);
                    dmv->x = dmv->y = dmv->z = 0.0f;
                }
                if (readable((void *)((uintptr_t)mv + MV_MOVEMODE), 4))
                    *(int *)((uintptr_t)mv + MV_MOVEMODE) = 0;
            }
        }
        /* Orient-to-control while standing (faceDirection, CharMovement vtable slot 6).
         * Vanilla behavior glued the body to the camera every frame; with the custom
         * locomotion we instead run the TURN-IN-PLACE gate: the body stays planted
         * while the camera free-looks, and only once the deviation passes tip_start
         * does it swivel toward the camera at tip_turn deg/s -- the loco leg system
         * sees the root yawing and animates the compensating foot steps. */
        float fy = g_yaw;
        if (g_loco_ready && g_cfg_loco_facelock) {
            if (!g_face_have) { g_face_yaw = g_yaw; g_face_have = 1; g_face_turning = 0; }
            /* HEAD_MAX neck-twist cap (Destreza HeadMax): standing, the camera cannot
             * yaw past ~83 deg off the body -- pushing the mouse against the cap DRAGS
             * the body through the turn-in-place at its honest rate, so you can never
             * free-spin the camera around a stationary body ("turn lock"). */
            if (g_cfg_headmax_deg > 1.0f && g_cfg_headmax_deg < 179.0f) {
                float hmax = g_cfg_headmax_deg * 0.0174533f;
                float dcap = loco_wrap_pi(g_yaw - g_face_yaw);
                if (dcap >  hmax) g_yaw = loco_wrap_pi(g_face_yaw + hmax);
                if (dcap < -hmax) g_yaw = loco_wrap_pi(g_face_yaw - hmax);
            }
            float dev = loco_wrap_pi(g_yaw - g_face_yaw);
            float startA = g_cfg_tip_start_deg * 0.0174533f;
            if (!g_face_turning && fabsf(dev) > startA) g_face_turning = 1;
            if (g_face_turning) {
                float dts = (dt > 0.0f && dt < 0.25f) ? dt : 0.016f;   /* sane per-frame dt */
                float cap = g_cfg_tip_turn_deg * 0.0174533f * dts;
                float stepv = dev < -cap ? -cap : dev > cap ? cap : dev;
                g_face_yaw = loco_wrap_pi(g_face_yaw + stepv);
                if (fabsf(loco_wrap_pi(g_yaw - g_face_yaw)) < 0.03f) g_face_turning = 0;
            }
            fy = g_face_yaw;
        } else {
            g_face_yaw = g_yaw; g_face_have = 1;   /* vanilla: body tracks camera */
        }
        void **mvvt = *(void ***)mv;
        if (in_module(mvvt)) {
            face_direction_t face = (face_direction_t)mvvt[MV_FACEDIR_VTOFF];
            if (in_module((void *)face)) {
                Vec3 lookDir = { sinf(fy), 0.0f, cosf(fy) };
                face(mv, &lookDir);
            }
        }
        /* MOMENTUM GLIDE: keys released but the body still slides -- keep the facing
         * re-feed armed (the engine's auto-face otherwise turns the body toward the
         * residual velocity, then orient-to-control yanks it back: rotate+snap at
         * every stop). Disarm only once the character has physically stopped. */
        if (g_loco_ready && g_cfg_loco_facelock && g_move_speed > 1.0f) {
            g_face_dir.x = sinf(fy); g_face_dir.y = 0.0f; g_face_dir.z = cosf(fy);
            InterlockedExchange(&g_face_active, 1);
        } else
            InterlockedExchange(&g_face_active, 0);
        if (g_loco_ready && g_cfg_loco_facelock) {   /* TIP/aim diag */
            static int tl;
            if ((++tl % 45) == 1)
                logline("[tip] dev=%.2f turning=%d idleaim=%d pitch=%.2f leanF=%.3f leanR=%.3f",
                        loco_wrap_pi(g_yaw - g_face_yaw), g_face_turning, g_idleaim_owned,
                        g_pitch, g_lean_f, g_lean_r);
        }
        return;
    }

    /* Heading relative to camera yaw (negated: W=forward, S=back, A=left, D=right). */
    float th = g_yaw;
    float fx = -sinf(th), fz = -cosf(th);
    float rx =  cosf(th), rz = -sinf(th);
    float dx = fx * mf + rx * mr;
    float dz = fz * mf + rz * mr;
    float len = sqrtf(dx * dx + dz * dz);
    if (len < 0.001f) return;
    dx = -dx / len; dz = -dz / len;
    /* 180-degree backpedal clamp: with the motion EXACTLY opposite the locked facing,
     * the engine's turn logic picks a rotation direction arbitrarily each tick and
     * fights the facing re-feed (179<->181 flip jitter on straight S). Keep the motion
     * 3 degrees off the axis -- imperceptible path skew, kills the ambiguity. */
    if (g_loco_ready && g_cfg_loco_facelock) {
        float myaw = atan2f(dx, dz);
        float rel = loco_wrap_pi(myaw - g_yaw);
        const float BACK_LIM = 3.089f;   /* 177 degrees */
        if (rel >  BACK_LIM) { myaw = g_yaw + BACK_LIM; dx = sinf(myaw); dz = cosf(myaw); }
        if (rel < -BACK_LIM) { myaw = g_yaw - BACK_LIM; dx = sinf(myaw); dz = cosf(myaw); }
    }

    /* Pinned-state detection: MOVE_DIRECTION only drives a STANDING body. When
     * the character is seated (chair/bench/bar), in a bed, or mid get-up, the
     * head is still up (so head_above doesn't flag it) yet setDirectMovement
     * can't translate them -- it just spins them in place. Detect "commanding
     * direct drive but not actually moving" and route to the point-click ORDER
     * path instead, which cancels the holding job and walks us out. Clears as
     * soon as real movement resumes, so normal standing locomotion is untouched
     * (walking is ~26 u/s, far above the 2 u/s pinned floor). */
    int pinned = kfp_stuck_step(&g_stuck_frames, g_was_direct, g_move_speed);  /* ~0.25s of no progress under direct drive */
    {   /* C05-KO (4080 m51g): a standing body pinned under direct drive -- obstacle or a held mover? Log the edge once
         * per hold with the mover state, so the next case says which (mode 2 + desired set + no speed = blocked). */
        static int pin_logged;
        if (!pinned) pin_logged = 0;
        else if (!pin_logged) {
            Vec3 pp = {0,0,0}; char_position(pc, &pp);
            int pmode = readable((void *)((uintptr_t)mv + MV_MOVEMODE), 4) ? *(int *)((uintptr_t)mv + MV_MOVEMODE) : -1;
            Vec3 pdm = readable((void *)((uintptr_t)mv + MV_DESIREDMOTION), 12) ? *(Vec3 *)((uintptr_t)mv + MV_DESIREDMOTION) : (Vec3){0,0,0};
            float pcs = readable((void *)((uintptr_t)mv + MV_CURRENT_SPEED), 4) ? *(float *)((uintptr_t)mv + MV_CURRENT_SPEED) : -1.0f;
            logline("[move] pinned edge: pos=%.1f,%.1f,%.1f dir=(%.2f,%.2f) spd=%.2f cur_speed=%.2f mode=%d desired=%.2f,%.2f,%.2f task_move=%d prone=%d head=%.2f",
                    pp.x, pp.y, pp.z, dx, dz, g_move_speed, pcs, pmode, pdm.x, pdm.y, pdm.z, char_task_is_move(pc),
                    char_prone_state(pc), g_head_above);
            pin_logged = 1;
        }
    }

    /* Authoritative state (KenshiLib members): prone state and bed flag tell us
     * directly when the character can't do standing MOVE_DIRECTION locomotion
     * and must instead be issued a get-up move order. */
    int prone = char_prone_state(pc);   /* 0 normal, 2 crippled, 3 play-dead, 4 KO */
    int in_bed = readable((void *)((uintptr_t)pc + CHAR_IN_SOMETHING), 4)
                 && *(int *)((uintptr_t)pc + CHAR_IN_SOMETHING) == 1;   /* IN_BED */
    /* "downed" = anything that isn't normal standing: an authoritative prone
     * state (playing dead / crippled / KO / staying-low), lying in a bed, a
     * physically low head, or the pinned fallback (a SEAT is a job, not a prone
     * state, so only stuck-detection catches it). Route these to the order path,
     * which cancels the holding job and runs the get-up. */
    int downed = (prone != PS_NORMAL) || in_bed || (g_head_above < 0.9f) || pinned;
    g_dbg_prone = prone; g_dbg_in_bed = in_bed; g_dbg_downed = downed;
    if (KFP_DEBUG_LOG) {
        static int lg;
        if ((++lg % 20) == 1) {
            int mode = readable((void *)((uintptr_t)mv + MV_MOVEMODE), 4)
                       ? *(int *)((uintptr_t)mv + MV_MOVEMODE) : -1;
            int engaged = readable((void *)((uintptr_t)pc + 0x250), 1)
                          ? *(unsigned char *)((uintptr_t)pc + 0x250) : -1;   /* _isEngagedWithAPlayer */
            logline("[getup] prone=%d in_bed=%d headY=%.2f pinned=%d spd=%.1f downed=%d dm_active=%ld was_direct=%d mode=%d engaged=%d",
                    prone, in_bed, g_head_above, pinned, g_move_speed, downed,
                    g_dm_active, g_was_direct, mode, engaged);
        }
    }

    /* STANDING: engine-native direct drive -- reliable on floors, platforms,
     * ramps, and everywhere the terrain-ray/click-order scheme wasn't. */
    if (!downed) {
        void **mvvt = *(void ***)mv;
        if (in_module(mvvt)) {
            /* Point-click DISENGAGE on the WASD press edge (outside the setjmp
             * guard below -- try_move_to_pos has its own). This is the vanilla
             * right-click order, and it cancels WHATEVER state currently holds
             * the character: a leftover move order, a chair/bench, a bed, combat
             * lock, playing dead. It is deliberately NOT gated on task type --
             * gating on Task_Move (our own order only) left seated/bedded/jobbed
             * characters pinned, so WASD merely SPUN them in place instead of
             * getting them up. Issue it toward the WASD direction (not the exact
             * spot) so the engine commits to stand-up + step. moveToPosition is
             * the same call a right-click makes and is SEH-guarded, so a fault on
             * a genuinely non-orderable state is contained rather than fatal. */
            if (!g_was_direct) {
                char_request_getup(pc);   /* break a seat before pinned-detect kicks in */
                /* facelock: NO point-click disengage order -- the order system turns the
                 * body toward the path point for a frame (visible rotate-then-snap at
                 * every movement start) before the drive + facing re-feed win. Without
                 * facelock the turn matched the auto-face anyway, so keep it there. */
                if (!(g_loco_ready && g_cfg_loco_facelock)) {
                    Vec3 hpos;
                    if (char_position(pc, &hpos)) {
                        Vec3 dis = { hpos.x + dx * 6.0f, hpos.y, hpos.z + dz * 6.0f };
                        try_move_to_pos(pc, &dis);
                    }
                }
            }
            if (setjmp(g_guard_jb)) { g_guard_armed = 0; return; }
            guard_arm();
            if (!g_was_direct)   /* entering direct drive: also stop the mover */
                ((void (*)(void *))mvvt[MV_HALT_SLOT])(mv);
            /* speed tiers: the scrollwheel throttle covers walk..jog only; SPRINT (tier
             * 2) is a held modifier key (default Left Shift) -- classic FP controls */
            /* PT04: the char's own vanilla gait (speed order outside FP), captured at the hold start; walk only
             * from the wheel throttle (wheel_speed mode), the sprint key = the vanilla run (never faster) */
            int gstart = 0;
            if (g_dm_vso >= 0 && g_dm_vso_pc != pc) fp_gait_restore(NULL, "controlled char changed");
            if (g_dm_vso < 0) {
                int so = readable((void *)((uintptr_t)mv + MV_SPEEDORDERS), 4) ? *(int *)((uintptr_t)mv + MV_SPEEDORDERS) : 2;
                g_dm_vso = (so >= 0 && so <= 3) ? so : 2; g_dm_vso_pc = pc; gstart = 1;
            }
            int spd = g_dm_vso;
            if (g_cfg_wheel && !g_cfg_camera_zoom && g_speed_scale < 0.4f) spd = 0;
            if (g_cfg_key_sprint && (GetAsyncKeyState(g_cfg_key_sprint) & 0x8000))
                spd = 2;
            /* Publish the intent; the CharMovement::update hook enforces it
             * per-update (beats combat AI), and we also apply once here so
             * movement works even if that hook failed to install. */
            g_dm_dir.x = dx; g_dm_dir.y = 0.0f; g_dm_dir.z = dz;
            g_dm_speed = spd; g_dm_mv = mv;
            InterlockedExchange(&g_dm_active, 1);
            /* facing lock: body faces the CAMERA while moving -> true strafe/backpedal.
             * Published for the charmove-update hook, which re-asserts it after the
             * engine's own turn-toward-motion (last write wins). */
            if (g_loco_ready && g_cfg_loco_facelock) {
                /* body yaw LAGS the camera slightly (~0.1s catch-up): the transient
                 * deviation drives the aim yaw-lead (upper body turns first, body
                 * follows) and body rotation reads natural instead of glued */
                if (!g_face_have) { g_face_yaw = g_yaw; g_face_have = 1; }
                /* deadzone follow: the body only chases the beyond-deadzone part of the
                 * camera deviation, so looking around while moving holds a SUSTAINED
                 * upper-body twist (the aim yaw) instead of the body gluing to the look */
                float fdev = loco_wrap_pi(g_yaw - g_face_yaw);
                float fdt  = (dt > 0.0f && dt < 0.25f) ? dt : 0.016f;
                float dead = g_cfg_loco_fdead * 0.0174533f;
                float chase = (fdev >  dead) ? fdev - dead
                            : (fdev < -dead) ? fdev + dead : 0.0f;
                float fcap = g_cfg_loco_frate * fdt;
                g_face_yaw = loco_wrap_pi(g_face_yaw +
                    (chase < -fcap ? -fcap : chase > fcap ? fcap : chase));
                g_face_turning = 0;
                g_face_dir.x = sinf(g_face_yaw); g_face_dir.y = 0.0f; g_face_dir.z = cosf(g_face_yaw);
                InterlockedExchange(&g_face_active, 1);
            } else
                InterlockedExchange(&g_face_active, 0);
            if (readable((void *)((uintptr_t)mv + MV_SPEEDORDERS), 4))
                *(int *)((uintptr_t)mv + MV_SPEEDORDERS) = spd;   /* WALK/JOG/RUN */
            ((void (*)(void *, int))mvvt[MV_SETSPEED_SLOT])(mv, spd);
            /* Movement: ALWAYS the proven mode-2 direct drive (this is the one mechanism
             * that reliably translates the character). With facing lock, the body yaw is
             * steered separately: the auto-turn is NOT faceDirection -- update() writes
             * facing(+0xD0) from the velocity and feeds AnimationClass::setPositionAnd-
             * Direction; the charmove-update hook re-feeds it with the camera dir AFTER
             * the original runs, and the last feed wins the frame. */
            ((void (*)(void *, const Vec3 *, float))(g_base + RVA_SET_DIRECT_MOVE))(mv, &g_dm_dir, 99.0f);
            if (g_face_active) {
                static int sfl;
                static Vec3 pprev;
                if ((++sfl % 30) == 1) {
                    Vec3 pos = readable((void *)((uintptr_t)mv + 0xC4), 12)
                             ? *(Vec3 *)((uintptr_t)mv + 0xC4) : (Vec3){0,0,0};
                    logline("[strafe] mode2 dir=(%.2f,%.2f) dpos=(%.3f,%.3f) animfix=%d",
                            dx, dz, pos.x - pprev.x, pos.z - pprev.z, RVA_ANIM_SETPOSDIR != 0);
                    pprev = pos;
                }
            }
            g_guard_armed = 0;
            g_was_direct = 1;
            g_was_moving = 1;
            fp_move_refusal(NULL);
            /* MOVE_DIRECTION skips the game's own athletics/strength XP tick --
             * run it ourselves so WASD trains like click-move. */
            award_move_xp(pc, mv, dt);
            fp_gait_meter(gw, pc, mv, gstart);
            return;
        }
    }
    fp_move_refusal(downed ? (prone != PS_NORMAL ? "downed: prone state" : in_bed ? "downed: in bed"
                              : pinned ? "downed: pinned (no progress under direct drive)" : "downed: head low")
                           : "mover vtable outside the game module");
    if (g_was_direct) {   /* fell/crippled mid-hold: return mode to normal */
        InterlockedExchange(&g_dm_active, 0);
        if (readable((void *)((uintptr_t)mv + MV_DESIREDMOTION), 12)) {
            Vec3 *dm = (Vec3 *)((uintptr_t)mv + MV_DESIREDMOTION);
            dm->x = dm->y = dm->z = 0.0f;
            *(int *)((uintptr_t)mv + MV_MOVEMODE) = 0;
        }
        g_was_direct = 0;
    }
    fp_gait_restore(pc, "drive refused mid-hold");

    /* Speed from the scrollwheel throttle (down = walk, up = run). */
    float dist = MOVE_NEAR + g_speed_scale * (MOVE_FAR - MOVE_NEAR);

    Vec3 here;
    if (!char_position(pc, &here)) return;

    /* Order-based move (animates + ground-clamps + turns to face path); re-issue
     * every frame so it holds. Camera stays welded via calibrated T.
     * NOTE: this is the raw CharMovement mover -- no navmesh pathfinding, so it
     * struggles on steep slopes (target Y is fixed). The player-path
     * Character::setDestination (0x5c84e0) DOES pathfind but crashes when called
     * from our post-frame hook without the game's SEH-guarded order setup. */
    /* Destination: replicate right-click as faithfully as possible.
     * Moving forward: cast the camera LOOK ray into the terrain (the very pick
     * right-click uses; FP cursor == screen center) -> the visible surface
     * point ahead. On a steep slope face that's a NEAR, reachable point, so
     * climbing works exactly like drag-move -- a fabricated far target lands
     * beyond the crest / inside the hill and stalls the pathfinder (observed:
     * stall at y=1555 with target y=1511 214u ahead). Capped to `dist` so the
     * scrollwheel speed control (distance = speed) still rules.
     * Strafe/backpedal (look != move dir) or sky-aimed ray: fabricate the
     * point ahead and ground-clamp its height. */
    Vec3 tgt; int via_ray = 0;
    if (downed) {
        /* GET UP from the ground, a bed, being seated, or playing dead. Set the
         * game's OWN get-up flag (what a real move order sets to break the state)
         * and issue a FAR, un-clamped ground order in the WASD direction. That
         * combination reliably commits the engine to get-up + walk -- the near,
         * terrain-clamped targeting below is tuned for standing slope-climbing and
         * doesn't trigger get-up dependably (and a bed sits above the ground, so
         * clamping to the surface underneath can fabricate an unreachable target).
         * If the character is genuinely KO the engine ignores it until recovery,
         * so it does no harm. */
        char_request_getup(pc);
        tgt.x = here.x + dx * 500.0f; tgt.y = here.y; tgt.z = here.z + dz * 500.0f;
    } else if (mf > 0.0f && mr == 0.0f) {
        float cp = cosf(g_pitch);
        Vec3 ro = { here.x, here.y + 16.0f, here.z };            /* ~eye, game frame */
        Vec3 rd = { dx * cp, -sinf(g_pitch), dz * cp };          /* unit look dir */
        Vec3 hitp;
        if (terrain_ray(&ro, &rd, &hitp)) {
            float vx = hitp.x - here.x, vz = hitp.z - here.z;
            float hd = sqrtf(vx * vx + vz * vz);
            if (hd > 0.5f) {
                if (hd > dist) hd = dist; /* cap: scrollwheel speed still rules */
                if (hd < 25.0f) hd = 25.0f; /* min lead: never ARRIVE mid-hold --
                                             * arrival completes the task and the
                                             * restart gap reads as stutter/stall
                                             * (broke slope climbing) */
                /* Smooth the lead distance: the raw ray distance jumps every
                 * frame while the view sweeps terrain, and Kenshi scales run
                 * speed by target distance -> surge/brake = jittery mouse feel
                 * while moving. Converges in ~0.1s so steep-face near targeting
                 * (the slope fix) engages promptly. */
                if (g_lead_sm <= 0.0f) g_lead_sm = hd;
                g_lead_sm += (hd - g_lead_sm) * 0.3f;
                float hl = sqrtf(vx * vx + vz * vz);
                tgt.x = here.x + (vx / hl) * g_lead_sm;
                tgt.z = here.z + (vz / hl) * g_lead_sm;
                tgt.y = here.y;
                terrain_clamp(&tgt);
                via_ray = 1;
            }
        }
    }
    if (!via_ray && !downed) {
        tgt.x = here.x + dx * dist; tgt.y = here.y; tgt.z = here.z + dz * dist;
        terrain_clamp(&tgt);
    }

    /* Primary drive: the REAL right-click walk order (Task_Move) -- pathfinds
     * over slopes, animates, triggers get-up when downed.
     * moveToPosition live-updates the destination when the CURRENT task is
     * already Task_Move (drag-move path, cheap, per-frame safe). When it is
     * NOT (movement start, stagger, or a JOB like Bodyguard holds the task
     * slot), each call CLEARS the queue + allocates a fresh task -- at 60/s
     * that wars with the job system's own queue mutations (heap-churn crash
     * when assigning Bodyguard). So: per-frame updates while the walk task is
     * current; task CREATION allowed instantly a few times, then ~4/s.
     * (An earlier removal of this throttle blamed it for chunky turning --
     * that was actually the warp-mouse input, since fixed by DirectInput.) */
    int cur_is_move = char_task_is_move(pc);
    static int create_streak, issue_cd;
    if (cur_is_move) create_streak = 0;
    if (issue_cd > 0) issue_cd--;
    if (cur_is_move || create_streak < 3 || issue_cd <= 0) {
        if (!try_move_to_pos(pc, &tgt))
            g_charmove_setdest(mv, &tgt, UPDATE_PRIORITY_HIGH, 1);
        if (!cur_is_move) { create_streak++; issue_cd = 15; }
    }

    g_was_moving = 1;
}

/* Read an MSVC std::string into out. Layout: [+0x0] SSO buf or heap ptr,
 * [+0x10] size, [+0x18] capacity; heap when capacity >= 16. */
static void read_mstring(const void *str, char *out, size_t outsz)
{
    out[0] = '\0';
    if (!readable(str, 0x20)) return;
    size_t cap  = *(size_t *)((uintptr_t)str + 0x18);
    size_t size = *(size_t *)((uintptr_t)str + 0x10);
    const char *data = (cap >= 16) ? *(const char **)str : (const char *)str;
    if (size >= outsz) size = outsz - 1;
    if (size > 512 || !readable(data, size + 1)) return;
    memcpy(out, data, size);
    out[size] = '\0';
}

/* Build an MSVC std::string (SSO) in a 32-byte buffer. len must be < 16. */
static void make_mstr(unsigned char *b32, const char *s)
{
    memset(b32, 0, 32);
    size_t len = strlen(s);
    if (len > 15) len = 15;
    memcpy(b32, s, len);
    *(size_t *)(b32 + 0x10) = len;
    *(size_t *)(b32 + 0x18) = 15;   /* SSO capacity */
}

/* Build an MSVC std::string in b32 for ANY length. len<16 -> SSO (returns NULL);
 * len>=16 -> data at a heap buffer we malloc and RETURN so the caller frees it
 * AFTER the (copying) consumer call. Never let MSVC free it (allocator mismatch);
 * the consumer copies the content, we free our own buffer. */
static void *make_mstr_long(unsigned char *b32, const char *s)
{
    memset(b32, 0, 32);
    size_t len = strlen(s);
    if (len < 16) {
        memcpy(b32, s, len);
        *(size_t *)(b32 + 0x10) = len;
        *(size_t *)(b32 + 0x18) = 15;
        return NULL;
    }
    char *buf = (char *)malloc(len + 1);
    if (!buf) { *(size_t *)(b32 + 0x18) = 15; return NULL; }
    memcpy(buf, s, len + 1);
    *(char **)b32 = buf;               /* heap data ptr at offset 0 */
    *(size_t *)(b32 + 0x10) = len;     /* size */
    *(size_t *)(b32 + 0x18) = len;     /* capacity >=16 => heap mode */
    return buf;
}

/* Lazily create the crosshair ImageBox once MyGUI is up (retried each FP enter
 * until it succeeds). Registers the image folder as an Ogre resource location. */
static void ensure_crosshair(void)
{
    if (g_crosshair) return;
    if (!g_gui_getinstance || !g_gui_createwidget || !g_imgbox_setimage
        || !g_widget_setvisible) return;
    void *gui = g_gui_getinstance();
    if (!readable(gui, 8)) return;   /* MyGUI not initialised yet */

    /* Register the image folder in Kenshi's "GUI" resource group -- that is the
     * group MyGUI's data manager searches for textures (its ./data/gui/ folder).
     * MyGUI globs the group live (findResourceNames), so a location added now is
     * picked up; "General"/a fresh group are NOT searched by MyGUI. */
    kfp_extract_assets();   /* lay down the embedded images before Ogre globs
                             * the folder (the group is scanned at add time) */
    if (g_rgm_getsingleton && g_rgm_addlocation) {
        void *rgm = g_rgm_getsingleton();
        if (readable(rgm, 8)) {
            unsigned char ft[32], grp[32];
            make_mstr(ft, "FileSystem"); make_mstr(grp, "GUI");
            /* (1) CWD-relative: the standalone edition ships kenshifp/ next to
             * the game exe (CWD = install root). */
            unsigned char loc[32];
            make_mstr(loc, "kenshifp");
            g_rgm_addlocation(rgm, loc, ft, grp, 0, 1);
            /* (2) Next to THIS DLL, by absolute path: the RE_Kenshi edition lives
             * in mods/KenshiFP/ (or the Steam Workshop content dir), so its images
             * ship in a kenshifp/ subfolder THERE, not at the game root. Without
             * this the mod-folder install finds no textures -> no crosshair /
             * vignette / KO blackout. Works for the standalone too (its DLL is at
             * the root, so this resolves to the same folder as (1)). */
            wchar_t dllw[MAX_PATH];
            DWORD n = GetModuleFileNameW(g_hinst, dllw, MAX_PATH);
            if (n > 0 && n < MAX_PATH) {
                for (DWORD k = n; k > 0; k--)
                    if (dllw[k-1] == L'\\' || dllw[k-1] == L'/') { dllw[k-1] = 0; break; }
                char dlla[MAX_PATH];
                if (WideCharToMultiByte(CP_UTF8, 0, dllw, -1, dlla, MAX_PATH, NULL, NULL)) {
                    char path[MAX_PATH + 16];
                    snprintf(path, sizeof path, "%s\\kenshifp", dlla);
                    unsigned char loc2[32];
                    void *heap = make_mstr_long(loc2, path);
                    g_rgm_addlocation(rgm, loc2, ft, grp, 0, 1);
                    if (heap) free(heap);
                }
            }
        }
    }

    int cx = GetSystemMetrics(SM_CXSCREEN), cy = GetSystemMetrics(SM_CYSCREEN);
    if (cx <= 0) cx = 1920;
    if (cy <= 0) cy = 1080;
    /* KO vignette: fullscreen, created FIRST so it renders under the
     * crosshair within the same layer. Shown while knocked out. */
    if (!g_vignette) {
        unsigned char vt[32], vs[32], vl[32], vn[32], vtex[32];
        make_mstr(vt, "ImageBox"); make_mstr(vs, "ImageBox"); make_mstr(vl, "Wallpaper");
        make_mstr(vn, "FPVignette"); make_mstr(vtex, "vignette.png");
        void *vw = g_gui_createwidget(gui, vt, vs, 0, 0, cx, cy,
                                      0 /*Align::Default*/, vl, vn);
        if (readable(vw, 8)) {
            g_imgbox_setimage(vw, vtex);
            g_widget_setvisible(vw, 0);
            g_vignette = vw;
        }
    }
    if (!g_black_ov) {
        unsigned char bt[32], bs[32], bl[32], bn[32], btex[32];
        make_mstr(bt, "ImageBox"); make_mstr(bs, "ImageBox"); make_mstr(bl, "Wallpaper");
        make_mstr(bn, "FPBlackout"); make_mstr(btex, "blk0.png");
        void *bw = g_gui_createwidget(gui, bt, bs, 0, 0, cx, cy,
                                      0, bl, bn);
        if (readable(bw, 8)) {
            g_imgbox_setimage(bw, btex);
            g_widget_setvisible(bw, 0);
            g_black_ov = bw;
        }
    }
    /* Skin MUST be "ImageBox" (defined in Kenshi's common_skins.xml): a widget
     * renders through its skin's sub-items, so an empty skin draws nothing --
     * that was why the widget existed + texture loaded, yet nothing showed. */
    unsigned char type[32], skin[32], layer[32], name[32], tex[32];
    make_mstr(type, "ImageBox"); make_mstr(skin, "ImageBox"); make_mstr(layer, "Pointer");
    make_mstr(name, "FPCrosshair"); make_mstr(tex, "crosshair.png");
    int vw, vh;
    kfp_view_size(&vw, &vh);
    void *w = g_gui_createwidget(gui, type, skin,
                                 vw / 2 - CROSSHAIR_SIZE / 2, vh / 2 - CROSSHAIR_SIZE / 2,
                                 CROSSHAIR_SIZE, CROSSHAIR_SIZE, 0 /*Align::Center*/, layer, name);
    if (readable(w, 8)) {
        g_imgbox_setimage(w, tex);
        g_widget_setvisible(w, 0);
        g_crosshair = w;
        g_crosshair_red = 0;   /* fresh widget starts on the white texture */
        logline("crosshair widget created %p", w);
    }
    /* Screen-space sneak/detection eye, just ABOVE the crosshair (so it doesn't
     * cover the aim point). One white icon, tinted per detection state + ~50%
     * alpha in fp_gui_update. */
    if (!g_sneak_icon && g_imgbox_setres && g_imgbox_setgrp && g_imgbox_setnm) {
        unsigned char st[32], ss[32], sl[32], sn[32];
        make_mstr(st, "ImageBox"); make_mstr(ss, "ImageBox"); make_mstr(sl, "Pointer");
        make_mstr(sn, "FPSneak");
        int sw_px = SNEAK_ICON_SIZE, sh_px = SNEAK_ICON_SIZE * 27 / 38; /* eye is 38x27 */
        void *sw = g_gui_createwidget(gui, st, ss, cx / 2 - sw_px / 2, cy / 2 - sh_px - 18,
                                      sw_px, sh_px, 0, sl, sn);
        if (readable(sw, 8)) {
            /* Draw Kenshi's OWN stealth-eye (Kenshi_CharacterNameTags/Stealth) -- the
             * same graphic the floating name tag uses -- so we ship no texture and it
             * matches whatever UI the player runs. */
            unsigned char rr[32], gg[32], nn[32];
            void *rheap = make_mstr_long(rr, "Kenshi_CharacterNameTags");
            make_mstr(gg, "Stealth"); make_mstr(nn, "Stealth");
            g_imgbox_setres(sw, rr);
            g_imgbox_setgrp(sw, gg);
            g_imgbox_setnm(sw, nn);
            if (rheap) free(rheap);
            g_widget_setvisible(sw, 0);
            g_sneak_icon = sw;
        }
    }
}

/* Desired crosshair tint (0 white / 1 red / 2 yellow), published by the
 * setPointer hook and APPLIED post-frame in fp_gui_update -- calling MyGUI
 * setImageTexture from inside the hook (which runs during the game's own UI
 * processing) was a reentrancy hazard that could corrupt MyGUI's widget
 * lists and crash the order/job/inventory ItemBoxes. */
static volatile LONG g_crosshair_want;

/* MyGUI PointerManager::setPointer hook: while FP is on, hide the default (arrow)
 * cursor — we show our crosshair instead — and keep contextual icon pointers
 * (speech/door/loot/...) visible. The vanilla COLORED-ARROW pointers are
 * special-cased: "attk" (red, hostile) and "green" (ally) are suppressed and
 * our crosshair takes their color instead. */
static void hooked_setpointer(void *pm, const void *name)
{
    g_pm_setpointer_orig(pm, name);
    if (!g_fp_mode || !g_pm_setvisible) return;
    if (g_ui_open) { g_pm_setvisible(pm, 1); g_pointer_default = 0; return; }
    if (!g_pm_getdefault) return;
    char cur[128], def[128];
    read_mstring(name, cur, sizeof cur);
    read_mstring(g_pm_getdefault(pm), def, sizeof def);
    /* one-shot state map: record each pointer name the first time it appears
     * (cheap, bounded) -- authoritative record of which states the game uses */
    if (KFP_DEBUG_LOG) {
        static char seen[16][24]; static int nseen;
        int i, hit = 0;
        for (i = 0; i < nseen; i++) if (strcmp(seen[i], cur) == 0) { hit = 1; break; }
        if (!hit && nseen < 16 && cur[0]) {
            snprintf(seen[nseen], sizeof seen[0], "%s", cur); nseen++;
            logline("[ptr] first seen: \"%s\"", cur);
        }
    }
    int is_default = (cur[0] != '\0' && strcmp(cur, def) == 0);
    int tint = (strcmp(cur, "attk") == 0) ? 1
             : (strcmp(cur, "green") == 0) ? 2 : 0;
    InterlockedExchange(&g_crosshair_want, tint);   /* applied post-frame */
    /* colored arrows: hide the vanilla cursor, our tinted crosshair stands in.
     * setVisible on the PointerManager is safe (not a widget-list op). */
    g_pm_setvisible(pm, (is_default || tint) ? 0 : 1);
    g_pointer_default = is_default || tint;
}

/* Force the MyGUI cursor visible/hidden (used on FP enter/exit). */
static void mygui_cursor(int visible)
{
    if (!g_pm_setvisible || !g_pm_getinstance) return;
    void *pm = g_pm_getinstance();
    if (readable(pm, 8)) g_pm_setvisible(pm, (char)(visible ? 1 : 0));
}

/* FP QoL: preload interiors of nearby buildings while approaching from OUTSIDE
 * (vanilla shows an interior only once a character is inside / build mode).
 * ~1 Hz: nearest Town at the player's position -> its buildings-with-layout
 * list (Town vt slot +0x2d8, list id 0x13) -> for each with a BuildingInterior
 * within INTERIOR_RADIUS, call the game's own idempotent lazy-loader (0x562540:
 * loads graphics once + refreshes the 10s keep-alive; roof stays on). The
 * game's visibility diff only hides hands from its OWN set, so it won't fight
 * this. VEH-guarded like every other game call. */
/* Make the game natively track the FP character so interiors/floors are handled
 * the VANILLA way. Kenshi drives interior floor culling from the TRACKED character
 * (PlayerInterface::updateFloorVisibility each frame); the RTS selection normally
 * keeps that in sync, but locking the camera for FP left it stale, so interiors
 * didn't follow the player. Rather than poke currentFloor by hand (which fought the
 * game and produced open-sky/black-void/exterior-bleed), call the game's OWN
 * PlayerInterface::startTrackCharacter(player, char) each frame -- exactly what
 * Kenshi-Direct-Control does. The game then reveals the right building/floor with
 * correct occlusion. VEH-guarded like every other game call. */
static int g_track_dead;
static int g_cur_floornum;   /* char's current building floor count (Building+0xA4); 0 = unknown */
static int g_floornum_dead;
/* Resolve the char's current building floor COUNT. Chain (Ghidra 1.0.65):
 *   hand = char->vtable[+0x1d8]()          (current-building hand&)
 *   Building* = FUN_1409f8050(&handmap, hand)
 *   count = *(int*)(Building + 0xA4)        (floornum)
 * Own VEH guard (call OUTSIDE any other guarded region). 0 = unknown. */
static int get_char_floornum(void *pc)
{
    if (g_floornum_dead || !g_hand2bld || !RVA_HANDMAP_PTR || !pc) return 0;
    void **vt = *(void ***)pc;
    if (!readable(vt, (CHAR_VT_CURBLDG_HAND + 1) * 8) || !in_module(vt)) return 0;
    /* Pass a retbuf as arg2: if the getter returns const hand& (reference), RDX is
     * ignored and RAX = hand*; if it returns hand BY VALUE, the struct is written to
     * the retbuf and RAX = retbuf. Either way RAX points at the hand -- no stack
     * corruption from a value-vs-reference mismatch (which VEH couldn't catch). */
    void *(*get_hand)(void *, void *) = (void *(*)(void *, void *))vt[CHAR_VT_CURBLDG_HAND];
    if (!in_module((void *)get_hand)) return 0;
    void *mapmgr = (void *)(g_base + RVA_HANDMAP_PTR);
    unsigned char handbuf[0x40] = {0};
    if (setjmp(g_guard_jb)) { g_guard_armed = 0; g_floornum_dead = 1;
        logline("[floor] building floornum FAULTED -- clamp disabled"); return 0; }
    guard_arm();
    int fn = 0;
    void *hand = get_hand(pc, handbuf);
    void *bld = NULL; int raw = -999; int handok = readable(hand, 0x18);
    if (handok) {
        bld = g_hand2bld(mapmgr, hand);
        if (readable(bld, BLDG_FLOORNUM_OFF + 4) && in_module(*(void ***)bld))
            { raw = *(int *)((uintptr_t)bld + BLDG_FLOORNUM_OFF); fn = raw; }
    }
    g_guard_armed = 0;
    static int dbg;
    if (dbg < 4) { dbg++;
        int htype = (handok) ? *(int *)((uintptr_t)hand + 8) : -1;
        void *mgrvt = readable(mapmgr, 8) ? *(void **)mapmgr : NULL;
        logline("[floor] resolve: hand=%p type@8=%d mapmgr=%p mgrvt=%p mgrvt_inmod=%d bld=%p raw@A4=%d",
                hand, htype, mapmgr, mgrvt, mgrvt ? in_module(mgrvt) : -1, bld, raw); }
    return (fn > 0 && fn <= 12) ? fn : 0;
}

/* Reveal (setVisible=1) the INTERIOR entities of one specific floor of a BuildingInterior,
 * WITHOUT touching the exterior shell (which stays at the native currentFloor). Mirrors the
 * two entity containers refreshInterior (0x561ab0) walks: container A = hands (resolved via
 * the object map), container B = direct Entity*. Entity getFloor = vtable+0x60, setVisible =
 * vtable+0x100. Caller MUST hold the VEH guard. */
static int g_reveal_dbg;
static void reveal_interior_floor(void *bi, int floor)
{
    void *mapmgr = (void *)(g_base + RVA_HANDMAP_PTR);
    int a_iter = 0, a_hit = 0, b_iter = 0, b_hit = 0;
    int a_hist[8] = {0}, b_hist[8] = {0};
    if (g_hand2bld && *(uintptr_t *)((uintptr_t)bi + 0x108)) {           /* container A: hands */
        void **node = *(void ***)(*(uintptr_t *)((uintptr_t)bi + 0x120)
                                  + *(uintptr_t *)((uintptr_t)bi + 0x100) * 8);
        for (int cap = 0; readable(node, 0x20) && cap < 8192; node = *(void **)node, cap++) {
            if (*(int *)((uintptr_t)node + 0x18) != 0) continue;
            void *ent = g_hand2bld(mapmgr, (void *)((uintptr_t)node + 0x10));
            if (!readable(ent, 8) || !in_module(*(void ***)ent)) continue;
            void **evt = *(void ***)ent;
            int gf = ((int (*)(void *))evt[0x60 / 8])(ent);
            a_iter++; if (gf >= 0 && gf < 8) a_hist[gf]++;
            if (gf == floor) { ((void (*)(void *, char))evt[0x100 / 8])(ent, 1); a_hit++; }
        }
    }
    if (*(uintptr_t *)((uintptr_t)bi + 0x148)) {                          /* container B: Entity* */
        void **node = *(void ***)(*(uintptr_t *)((uintptr_t)bi + 0x160)
                                  + *(uintptr_t *)((uintptr_t)bi + 0x140) * 8);
        for (int cap = 0; readable(node, 0x18) && cap < 8192; node = *(void **)node, cap++) {
            void *ent = *(void **)((uintptr_t)node + 0x10);
            if (!readable(ent, 8) || !in_module(*(void ***)ent)) continue;
            void **evt = *(void ***)ent;
            int gf = ((int (*)(void *))evt[0x60 / 8])(ent);
            b_iter++; if (gf >= 0 && gf < 8) b_hist[gf]++;
            if (gf == floor) { ((void (*)(void *, char))evt[0x100 / 8])(ent, 1); b_hit++; }
        }
    }
    if (g_reveal_dbg < 3) { g_reveal_dbg++;
        logline("[floor] reveal f=%d bldg=%p A(n=%d hit=%d hist=%d,%d,%d,%d,%d) B(n=%d hit=%d hist=%d,%d,%d,%d,%d)",
                floor, readable(bi,8)?*(void**)bi:NULL, a_iter, a_hit,
                a_hist[0],a_hist[1],a_hist[2],a_hist[3],a_hist[4],
                b_iter, b_hit, b_hist[0],b_hist[1],b_hist[2],b_hist[3],b_hist[4]); }
}

/* Highest floor index that has interior entities = the building's top floor. Walks the same
 * A/B containers as reveal_interior_floor (Building+0xA4 "floornum" reads 0 on 1.0.65 -- stale
 * header offset -- so we derive the top floor from the interior instead). -1 if none/unloaded. */
static int interior_max_floor(void *bi)
{
    void *mapmgr = (void *)(g_base + RVA_HANDMAP_PTR);
    int maxf = -1;
    if (g_hand2bld && *(uintptr_t *)((uintptr_t)bi + 0x108)) {           /* container A: hands */
        void **node = *(void ***)(*(uintptr_t *)((uintptr_t)bi + 0x120)
                                  + *(uintptr_t *)((uintptr_t)bi + 0x100) * 8);
        for (int cap = 0; readable(node, 0x20) && cap < 8192; node = *(void **)node, cap++) {
            if (*(int *)((uintptr_t)node + 0x18) != 0) continue;
            void *ent = g_hand2bld(mapmgr, (void *)((uintptr_t)node + 0x10));
            if (!readable(ent, 8) || !in_module(*(void ***)ent)) continue;
            int gf = ((int (*)(void *))(*(void ***)ent)[0x60 / 8])(ent);
            if (gf > maxf && gf < 8) maxf = gf;
        }
    }
    if (*(uintptr_t *)((uintptr_t)bi + 0x148)) {                          /* container B: Entity* */
        void **node = *(void ***)(*(uintptr_t *)((uintptr_t)bi + 0x160)
                                  + *(uintptr_t *)((uintptr_t)bi + 0x140) * 8);
        for (int cap = 0; readable(node, 0x18) && cap < 8192; node = *(void **)node, cap++) {
            void *ent = *(void **)((uintptr_t)node + 0x10);
            if (!readable(ent, 8) || !in_module(*(void ***)ent)) continue;
            int gf = ((int (*)(void *))(*(void ***)ent)[0x60 / 8])(ent);
            if (gf > maxf && gf < 8) maxf = gf;
        }
    }
    return maxf;
}

/* The walls/floor/roof are the building's SHELL entities (Building+0x228 vector<Entity*>),
 * floor-culled every frame by the world cull (setVisible getFloor<=byte). Reveal the shell
 * pieces of one floor -- called PER FRAME (after the game's cull) so they aren't re-hidden. */
static int g_shell_dbg;
/* Iterate one group of the shell container (count @ off+0, Entity*[] @ off+8), setVisible=1
 * on game-object entities whose getFloor==floor. Returns count revealed. */
static int reveal_shell_group(void *cont, size_t cntoff, size_t dataoff, int floor, int *hist)
{
    unsigned n = *(unsigned *)((uintptr_t)cont + cntoff);
    if (n == 0 || n > 8192) return 0;
    void **data = *(void ***)((uintptr_t)cont + dataoff);
    if (!readable(data, (size_t)n * 8)) return 0;
    int rev = 0;
    for (unsigned i = 0; i < n; i++) {
        void *ent = data[i];
        if (!readable(ent, 8) || !in_module(*(void ***)ent)) continue;
        void **evt = *(void ***)ent;
        int gf = ((int (*)(void *))evt[0x60 / 8])(ent);
        if (hist && gf >= 0 && gf < 8) hist[gf]++;
        if (gf == floor) { ((void (*)(void *, char))evt[0x100 / 8])(ent, 1); rev++; }
    }
    return rev;
}
static void reveal_shell_floor(void *bldg, int floor)
{
    if (!readable(bldg, 0x230)) return;
    void *cont = *(void **)((uintptr_t)bldg + 0x228);   /* Building::entities container ptr */
    if (!readable(cont, 0x48)) return;
    int hist[8] = {0}, rev = 0;
    /* three groups Building::setVisible walks: cnt@+8/data@+0x10, +0x20/+0x28, +0x38/+0x40 */
    rev += reveal_shell_group(cont, 0x08, 0x10, floor, hist);
    rev += reveal_shell_group(cont, 0x20, 0x28, floor, hist);
    rev += reveal_shell_group(cont, 0x38, 0x40, floor, hist);
    if (g_shell_dbg < 5) { g_shell_dbg++;
        logline("[floor] shell f=%d cont=%p g1n=%u g2n=%u g3n=%u rev=%d hist=%d,%d,%d,%d,%d",
                floor, cont, *(unsigned*)((uintptr_t)cont+8), *(unsigned*)((uintptr_t)cont+0x20),
                *(unsigned*)((uintptr_t)cont+0x38), rev, hist[0],hist[1],hist[2],hist[3],hist[4]); }
}

static void *g_cur_building;   /* char's building (BuildingInterior+0), cached for per-frame reveal */
static void *g_cur_bi;         /* the BuildingInterior itself (for the per-frame interior reveal) */
static int   g_cur_ibyte = -1; /* its applied floor byte */
static int   g_cur_topf  = -1; /* highest interior floor of the char's building (open top) */
static float g_last_footy = -1e9f; /* char foot Y last frame (top-approach climb detection) */
static int   g_climb_frames;   /* consecutive ascending frames (hysteresis) */
#define CLIMB_RISE 0.02f       /* per-frame world-Y rise that counts as "climbing the stairs" */
/* refreshInterior detour: reveal the floor-above's INTERIOR props here, and cache the building
 * so the per-frame shell reveal (hooked_mainloop) can reveal its walls/floor without the cull
 * re-hiding them. No currentFloor bump -> exterior stays correctly hidden. */
static void hooked_refresh_interior(void *bi)
{
    g_refresh_interior_orig(bi);
    if (g_reveal_dead || !g_fp_mode || !g_cfg_auto_floors || !readable(bi, 0x168)) return;
    int byte = *(signed char *)((uintptr_t)bi + 0x2d);
    if (byte < 0 || byte >= 4) { g_cur_building = NULL; g_cur_ibyte = -1; g_cur_topf = -1; return; }
    if (setjmp(g_guard_jb)) { g_guard_armed = 0; g_reveal_dead = 1;
        logline("[floor] interior-reveal FAULTED -- disabled"); return; }
    guard_arm();
    g_cur_building = *(void **)bi;   /* BuildingInterior+0 = owning Building* */
    g_cur_bi = bi;
    g_cur_ibyte = byte;
    /* Floor look-ahead: raise THIS building's cutaway (record+0x78) so the game natively renders
     * `depth` floors above the char AS INTERIOR. Per-building (NOT global currentFloor), so the
     * exterior shell stays hidden. KEY CLAMP: never look-ahead INTO a tall building's TOP floor --
     * that top level is open-air (no roof), so revealing it from below cuts the char's own ceiling
     * and exposes sky ("renders incorrectly"). A 2-floor building's top IS enclosed and safe to
     * reveal. So maxreveal = floornum-2 for tall (3+) buildings, floornum-1 for short ones.
     * floornum = Building+0xA4 (floor count). Also does a belt-and-suspenders manual prop reveal. */
    g_cur_topf = interior_max_floor(bi);
    if (g_cur_building) {
        int topf = g_cur_topf;
        /* Reveal one floor above the char, but STOP one below the building's top floor for tall
         * (3+ floor) buildings: that top level is open-air, so revealing it from below cuts the
         * char's ceiling and exposes sky. It reveals naturally when you step onto it. A 2-floor
         * building's top IS enclosed and safe to reveal. */
        int maxreveal = (topf >= 2) ? topf - 1 : topf;
        int target = byte + 1;
        if (target > maxreveal) target = maxreveal;
        if (target > byte) {
            for (int fl = byte + 1; fl <= target; fl++) reveal_interior_floor(bi, fl);
            if (g_get_town && g_set_floorbyte) {
                void *town = g_get_town(g_cur_building);
                if (readable(town, 0x260)) g_set_floorbyte(town, g_cur_building, (char)target);
            }
        }
    }
    g_guard_armed = 0;
}

/* Per-frame shell reveal: reveal the floor-above's shell walls/floor for the char's building,
 * after the game's world cull has hidden them. VEH-guarded. */
static int g_shell_dead;
/* The walls/floor are the building's SHELL, floor-culled every frame by the global cull
 * FUN_1409fa670 (setVisible getFloor<=byte). We hook it: after it runs, re-reveal the shell
 * pieces of the floor ABOVE (byte+1) for the CHAR's building only, so they persist. Shell
 * objects are hands in the cull's container (+0x128 idx/+0x130 cnt/+0x148 buckets), resolved
 * by g_resolve_shell_obj (FUN_14000d049); each object's building via g_resolve_bld
 * (FUN_140791d70); getFloor=vt+0x60, curBuildingHand=vt+0x1d8, setVisible=vt+0x100. */
typedef void  (*shell_cull_t)(void *mgr);
typedef void *(*resolve1_t)(void *hand);
static shell_cull_t g_shell_cull_orig;
static resolve1_t   g_resolve_shell_obj;   /* FUN_14000d049: shell-object hand -> object */
static resolve1_t   g_resolve_bld;         /* FUN_140791d70: building hand -> Building* */
static void hooked_shell_cull(void *mgr)
{
    g_shell_cull_orig(mgr);
    if (g_shell_dead || !g_fp_mode || !g_cur_building || g_cur_ibyte < 0 || g_cur_ibyte >= 3
        || !g_resolve_shell_obj || !g_resolve_bld || !readable(mgr, 0x150)) return;
    if (*(uintptr_t *)((uintptr_t)mgr + 0x130) == 0) return;
    if (setjmp(g_guard_jb)) { g_guard_armed = 0; g_shell_dead = 1;
        logline("[floor] shell-cull hook FAULTED -- disabled"); return; }
    guard_arm();
    int want = g_cur_ibyte + 1, rev = 0, iter = 0, walked = 0, resolved = 0, bldmatch = 0;
    void **node = *(void ***)(*(uintptr_t *)((uintptr_t)mgr + 0x148)
                              + *(uintptr_t *)((uintptr_t)mgr + 0x128) * 8);
    for (int cap = 0; readable(node, 0x18) && cap < 16384; node = *(void **)node, cap++) {
        walked++;
        void *obj = g_resolve_shell_obj((void *)((uintptr_t)node + 0x10));
        if (!readable(obj, 0x190) || !in_module(*(void ***)obj)) continue;
        resolved++;
        if (*(int *)((uintptr_t)obj + 0x188) != 0) continue;
        void **ovt = *(void ***)obj;
        int gf = ((int (*)(void *))ovt[0x60 / 8])(obj);
        iter++;
        if (gf != want) continue;
        unsigned char handbuf[0x40] = {0};
        void *bhand = ((void *(*)(void *, void *))ovt[0x1d8 / 8])(obj, handbuf);
        void *bld = readable(bhand, 0x18) ? g_resolve_bld(bhand) : NULL;
        if (bld == g_cur_building) { ((void (*)(void *, char))ovt[0x100 / 8])(obj, 1); rev++; }
        else bldmatch++;
    }
    g_guard_armed = 0;
    if (g_shell_dbg < 8) { g_shell_dbg++;
        logline("[floor] shell-cull mgr=%p +130=%llu want=%d walked=%d resolved=%d atfloor(iter)=%d bld!=cur=%d rev=%d",
                mgr, (unsigned long long)*(uintptr_t *)((uintptr_t)mgr + 0x130),
                want, walked, resolved, iter, bldmatch, rev); }
}

/* FUN_1405c94d0 detour: the per-object floor-visibility applier that sets the object's
 * INTERIOR (+0xe5) and EXTERIOR (+0xe4) render flags from getFloor(+0xa4)<=byte. It runs
 * per renderable per frame. For the char's building's floor-ABOVE objects (walls/floor of
 * byte+1), force the INTERIOR flag on so they show as interior alongside the current floor. */
typedef char (*wallcull_t)(void *obj, float f);
static wallcull_t g_wallcull_orig;
static int g_wall_dead, g_wall_dbg, g_wall_hits;
static char hooked_wallcull(void *obj, float f)
{
    char r = g_wallcull_orig(obj, f);
    /* Cheap gates first: only floor-ABOVE objects that the original judged frustum-visible
     * (+0x1a9) but interior-hidden (+0xe5==0) are candidates. Everything else falls through
     * at ~zero cost (this runs per renderable per frame). */
    if (g_wall_dead || !g_fp_mode || !g_cur_building || g_cur_ibyte < 0 || g_cur_ibyte >= 3
        || !g_hand2bld || !RVA_HANDMAP_PTR || !readable(obj, 0x1b0)) return r;
    if (*(int *)((uintptr_t)obj + 0xa4) != g_cur_ibyte + 1) return r;   /* getFloor != byte+1 */
    if (*(unsigned char *)((uintptr_t)obj + 0x1a9) == 0) return r;      /* not frustum-visible */
    if (*(unsigned char *)((uintptr_t)obj + 0xe5) != 0) return r;       /* already interior-shown */
    if (setjmp(g_guard_jb)) { g_guard_armed = 0; g_wall_dead = 1;
        logline("[floor] wallcull FAULTED -- disabled"); return r; }
    guard_arm();
    /* Resolve this object's building exactly as the original does:
     * hand = obj->vt[0x1d8](); if hand.type(+8)==0: bld = g_hand2bld(&map, hand). */
    void **ovt = *(void ***)obj;
    void *bld = NULL;
    if (in_module(ovt)) {
        void *hand = ((void *(*)(void *))ovt[0x1d8 / 8])(obj);
        if (readable(hand, 0x10) && *(int *)((uintptr_t)hand + 8) == 0)
            bld = g_hand2bld((void *)(g_base + RVA_HANDMAP_PTR), hand);
    }
    if (bld == g_cur_building) {
        unsigned char e5_before = *(unsigned char *)((uintptr_t)obj + 0xe5);
        unsigned char r8_before = *(unsigned char *)((uintptr_t)obj + 0x1a8);
        *(unsigned char *)((uintptr_t)obj + 0xe5)  = 1;  /* interior visible */
        *(unsigned char *)((uintptr_t)obj + 0x1a8) = 1;  /* final render decision (was 0) */
        g_wall_hits++;
        if (g_wall_dbg < 8) { g_wall_dbg++;
            uintptr_t vt = (uintptr_t)(*(void ***)obj) - g_base;
            logline("[floor] wallcull obj=%p vt=+%llx floor=%d e4=%d e5:%d->1 r8:%d->1 flag188=%llx hits=%d",
                    obj, (unsigned long long)vt, *(int *)((uintptr_t)obj + 0xa4),
                    *(unsigned char *)((uintptr_t)obj + 0xe4), e5_before, r8_before,
                    (unsigned long long)*(uintptr_t *)((uintptr_t)obj + 0x188), g_wall_hits);
        }
    }
    g_guard_armed = 0;
    return r;
}

static void fp_sync_floor(void *gw)
{
    if (!g_cfg_auto_floors || g_track_dead || !g_start_track_char || !g_fp_mode || !gw) return;
    if (!readable((void *)((uintptr_t)gw + GW_PLAYER), 8)) return;
    void *player = *(void **)((uintptr_t)gw + GW_PLAYER);
    if (!readable(player, 8) || !in_module(*(void ***)player)) return;
    void *pc = fp_controlled_char(gw);
    if (!pc) return;
    if (setjmp(g_guard_jb)) { g_guard_armed = 0; g_track_dead = 1;
        logline("[floor] startTrackCharacter FAULTED -- native tracking disabled"); return; }
    guard_arm();
    g_start_track_char(player, pc);   /* native double-click: currentFloor=charFloor. Shell/exterior
                                       * stay correct; the seamless-UP reveal of the floor above's
                                       * INTERIOR is done in the refreshInterior hook. */
    g_guard_armed = 0;
}

static void fp_load_nearby_interiors(void *gw)
{
    if (!g_fp_mode || g_interiors_dead || !g_nearest_town || !g_interior_load) return;
    static int cooldown;
    if (cooldown > 0) { cooldown--; return; }
    cooldown = 60;                                  /* ~1 Hz at 60 fps */

    void *pc = fp_controlled_char(gw);
    Vec3 here;
    if (!pc || !char_position(pc, &here)) return;

    void *mgr = readable((void *)(g_base + RVA_TOWNMGR_PTR), 8)
        ? *(void **)(g_base + RVA_TOWNMGR_PTR) : NULL;
    if (!readable(mgr, 8)) return;

    if (setjmp(g_guard_jb)) {
        g_interiors_dead = 1;
        logline("interior preload FAULTED -- disabled for this session");
        return;
    }
    guard_arm();
    int loaded = 0;
    void *town = g_nearest_town(mgr, &here, 0);
    if (readable(town, 8) && in_module(*(void ***)town)) {
        town_getlist_t getlist = (town_getlist_t)(*(void ***)town)[TOWN_GETLIST_VTOFF];
        if (in_module((void *)getlist)) {
            void *lek = getlist(town, BLDG_LIST_TYPE, pc);
            if (readable(lek, 0x18)) {
                unsigned int n = *(unsigned int *)((uintptr_t)lek + 0x8);
                void **data = *(void ***)((uintptr_t)lek + 0x10);
                if (n < 4096 && readable(data, (size_t)n * sizeof(void *))) {
                    for (unsigned int i = 0; i < n; i++) {
                        void *b = data[i];
                        if (!readable(b, BLDG_INTERIOR + 8)) continue;
                        /* skip ruins: the vanilla updater gates on isDestroyed()
                         * too -- refreshing a ruin resurrects its intact
                         * walls/roof at low LOD */
                        if (*(unsigned char *)((uintptr_t)b + BLDG_DESTROYED)) continue;
                        void *bi = *(void **)((uintptr_t)b + BLDG_INTERIOR);
                        if (!readable(bi, 0x30)) continue;   /* no interior layout */
                        float bx = *(float *)((uintptr_t)b + BLDG_POS_X);
                        float bz = *(float *)((uintptr_t)b + BLDG_POS_X + 8);
                        float ddx = bx - here.x, ddz = bz - here.z;
                        if (ddx * ddx + ddz * ddz > INTERIOR_RADIUS * INTERIOR_RADIUS)
                            continue;
                        g_interior_load(bi);
                        loaded++;
                    }
                }
            }
        }
    }
    g_guard_armed = 0;
    static int last_loaded = -1;
    if (loaded != last_loaded) {                    /* log on change only */
        last_loaded = loaded;
        logline("interior preload: %d building(s) in range", loaded);
    }
}

/* ===== head-covering gear hide ==============================================
 * Hiding the head MESH alone is only half the job: hats, helmets, face plates, hair
 * and beards are SEPARATE Ogre entities hung off the AppearanceHuman, so with the head
 * gone they keep floating exactly where it used to be -- in FP that is the inside of
 * your own helmet parked on the camera. Hide those entities too.
 *
 * This mirrors what the game itself already does: 1.0.65 FUN_140537200 (the "a hat
 * hides your hair/beard" routine) walks the SAME worn-item map and calls
 * Ogre::MovableObject::setVisible(*(MovableObject**)(item + 0x80), vis). So entity
 * setVisible IS the working lever for worn items -- unlike the BODY entity at app+0xd8,
 * which ignores setVisible entirely (that dead end is documented in re/NOTES.md).
 *
 * The item's slot is the INT GameData field "attach slot" in the map at gd+0x178. The
 * vanilla code reads it through that map's operator[] (1.0.65 0x6cef0 / 1.0.68 0x6cf30,
 * reached via a jmp thunk). We deliberately do NOT call it: operator[] INSERTS on a miss
 * (it allocates a 0x40-byte node through Ogre's pooling allocator and mutates the map),
 * and its prologue is byte-identical across seven sibling template instantiations, so it
 * cannot be signature-scanned for the RE_Kenshi build. A read-only walk of the node list
 * needs no build-specific address at all and cannot perturb game state. */

/* Read an INT GameData field by name out of the map at gd+0x178 (read-only node walk).
 * CALLER MUST hold the VEH guard. Returns 1 and fills *out on a hit. */
static int gd_int_field(void *gd, const char *key, int *out)
{
    if (!readable(gd, GD_INTMAP + 0x40)) return 0;
    unsigned char *m = (unsigned char *)gd + GD_INTMAP;
    size_t nb = *(size_t *)(m + 0x18);          /* bucket count */
    size_t n  = *(size_t *)(m + 0x20);          /* element count */
    void **bk = *(void ***)(m + 0x38);          /* bucket array */
    if (!n || !nb || nb > 0x10000 || !readable(bk, (nb + 1) * sizeof(void *))) return 0;
    size_t klen = strlen(key);
    void *node = bk[nb];                        /* sentinel slot = head of the node list */
    for (size_t i = 0; node && i < 4096; i++, node = *(void **)((uintptr_t)node + MAPN_NEXT)) {
        if (!readable(node, MAPN_VALUE + 4)) return 0;
        unsigned char *k = (unsigned char *)node + MAPN_KEY;
        size_t len = *(size_t *)((uintptr_t)node + MAPN_KEYLEN);
        size_t cap = *(size_t *)((uintptr_t)node + MAPN_KEYCAP);
        /* MSVC std::string SSO: <=15 chars live inline in the 16-byte buffer */
        const char *s = (cap > 15) ? *(const char **)k : (const char *)k;
        if (len == klen && readable(s, klen) && memcmp(s, key, klen) == 0) {
            *out = *(int *)((uintptr_t)node + MAPN_VALUE);
            return 1;
        }
    }
    return 0;
}

/* g_gear_hid / g_gear_n live next to g_head_hidden (fp_head_forget_world in kfp_control.inc) */
static int   g_gear_dead;     /* headgear hide self-disabled after a fault */
static int   g_gear_diag;     /* capped count of re-show diagnostic log lines */

/* NUL-terminated copy of a worn-map node's key (MSVC std::string, SSO-aware) for
 * logging. CALLER MUST hold the VEH guard (heap keys are followed). */
static void gearnode_key(void *node, char *out, size_t outsz)
{
    out[0] = 0;
    size_t len = *(size_t *)((uintptr_t)node + MAPN_KEYLEN);
    size_t cap = *(size_t *)((uintptr_t)node + MAPN_KEYCAP);
    const char *k = (const char *)node + MAPN_KEY;
    if (len >= outsz) len = outsz - 1;
    if (cap > 15) {   /* heap string: MAPN_KEY holds the pointer */
        k = *(const char **)((uintptr_t)node + MAPN_KEY);
        if (!readable((void *)k, len + 1)) return;
    }
    memcpy(out, k, len); out[len] = 0;
}

/* Hide (hide=1) or restore (hide=0) the player's head-covering worn items.
 * CALLER MUST hold the VEH guard. */
static void headgear_set_hidden(void *app, int hide, int logit)
{
    /* NB: the config gate applies to HIDING only -- a restore must always be able to run,
     * or turning the F10 toggle off would strand the gear invisible. */
    if (g_gear_dead || !g_ent_setvisible || (hide && !g_cfg_hide_headgear)) return;
    if (!readable(app, APP_ITEM_BUCKETS + 8)) return;
    size_t nb = *(size_t *)((uintptr_t)app + APP_ITEM_NBUCK);
    size_t n  = *(size_t *)((uintptr_t)app + APP_ITEM_COUNT);
    void **bk = *(void ***)((uintptr_t)app + APP_ITEM_BUCKETS);
    if (!n || !nb || nb > 0x10000 || !readable(bk, (nb + 1) * sizeof(void *))) {
        if (logit) logline("[head] worn-item map unusable: app=%p nbuck=%u count=%u buckets=%p",
                           app, (unsigned)nb, (unsigned)n, (void *)bk);
        return;
    }
    /* The game has its own "headwear hidden" state (app+0x181, set by FUN_140537200).
     * If it is on, vanilla WANTS hats invisible -- don't fight it on the way out. */
    int gamehides = readable((void *)((uintptr_t)app + APP_HIDE_HEADWEAR), 1)
                 && *(unsigned char *)((uintptr_t)app + APP_HIDE_HEADWEAR) != 0;
    int nhid = 0;
    /* Rebuild the record on every hide pass: appearance rebuilds recycle item entities,
     * so a list kept across passes would go stale. We only ever COMPARE the recorded
     * pointers (never dereference them) and only ever call setVisible on a pointer we
     * just read out of the LIVE map -- so a freed entity can never be touched.
     * The PREVIOUS pass's list is snapshotted first: re-assert passes diff against it
     * to catch the game re-showing or replacing an entity we hid (field diagnosis:
     * facial hair reported visible after a clean hide pass). */
    void *prev[8]; int prevn = 0;
    if (hide) {
        prevn = g_gear_n;
        memcpy(prev, g_gear_hid, sizeof prev);
        g_gear_n = 0;
    }
    void *node = bk[nb];
    for (size_t i = 0; node && i < 256; i++, node = *(void **)((uintptr_t)node + MAPN_NEXT)) {
        if (!readable(node, MAPN_VALUE + 8)) return;
        void *item = *(void **)((uintptr_t)node + MAPN_VALUE);
        if (!readable(item, ITEM_MESH + 8)) continue;
        void *gd   = *(void **)((uintptr_t)item + ITEM_GAMEDATA);
        void *mesh = *(void **)((uintptr_t)item + ITEM_MESH);
        /* mesh == NULL means the game already destroyed this entity -- that is exactly
         * how vanilla hides hair/beard under a hat, so leave it alone. */
        if (!mesh || !readable(mesh, 8)) continue;
        /* Classification is by the map-node KEY (the map is keyed by attachment-slot
         * name -- field log 2026-08-24: "hair", "beard", "legs", "hip"), with the
         * GameData "attach slot" int as confirmation when present. The earlier
         * no-slot heuristic ("no attach slot = own hair") was WRONG: the no-slot
         * entries were "legs"/"hip" (clothing) and got hidden in FP -- never again. */
        char kn[48]; gearnode_key(node, kn, sizeof kn);
        int slot = -1;
        int haveslot = gd_int_field(gd, "attach slot", &slot);
        int keyhead = !haveslot && (!strcmp(kn, "hair") || !strcmp(kn, "beard")
                   || !strcmp(kn, "hat") || !strcmp(kn, "eyes") || !strcmp(kn, "face"));
        int slothead = haveslot && slot >= 0 && slot <= 31
                    && ((g_cfg_headgear_slots >> slot) & 1u);
        if (!slothead && !keyhead) {
            if (logit) logline("[head] gear key=\"%s\" item=%p slot=%d mesh=%p -> kept (not head-covering, slots=0x%x)",
                               kn, item, slot, mesh, g_cfg_headgear_slots);
            continue;
        }
        if (hide) {
            /* re-assert diagnostics: an entity we hid last pass reading visible again
             * (the game flipped it back), or a mesh pointer we have never seen (the
             * game re-created the entity). Capped; the re-hide below cures both. */
            if (prevn > 0 && g_gear_diag < 12) {
                int wasours = 0;
                for (int j = 0; j < prevn && j < 8; j++)
                    if (prev[j] == mesh) { wasours = 1; break; }
                int vis = g_ent_getvisible ? (g_ent_getvisible(mesh) != 0) : -1;
                if (vis == 1 || !wasours) {
                    g_gear_diag++;
                    logline("[head] REASSERT: key=\"%s\" mesh=%p knownMesh=%d visible=%d -> re-hidden",
                            kn, mesh, wasours, vis);
                }
            }
            g_ent_setvisible(mesh, 0);
            if (g_gear_n < (int)(sizeof g_gear_hid / sizeof g_gear_hid[0]))
                g_gear_hid[g_gear_n++] = mesh;
            nhid++;
            if (logit) logline("[head] gear key=\"%s\" item=%p slot=%d mesh=%p -> hidden",
                               kn, item, slot, mesh);
        } else if (!gamehides) {
            for (int j = 0; j < g_gear_n; j++)
                if (g_gear_hid[j] == mesh) { g_ent_setvisible(mesh, 1); nhid++; break; }
        }
    }
    if (!hide) g_gear_n = 0;
    if (logit) logline("[head] headgear %s: %d item(s) (slots=0x%x, gameHidesHeadwear=%d)",
                       hide ? "hidden" : "restored", nhid, g_cfg_headgear_slots, gamehides);
}

/* Run headgear_set_hidden under its OWN VEH guard (never nested inside the caller's --
 * one setjmp buffer, one armed region). A fault latches the feature off for the session
 * instead of taking the game down with it. */
static void headgear_apply(void *app, int hide, int logit)
{
    if (g_gear_dead || !g_ent_setvisible || !app || (hide && !g_cfg_hide_headgear)) return;
    if (setjmp(g_guard_jb)) { g_guard_armed = 0; g_gear_dead = 1;
        logline("[head] headgear hide FAULTED -- headgear hide disabled for this session"); return; }
    guard_arm();
    headgear_set_hidden(app, hide, logit);
    g_guard_armed = 0;
}

/* Set the body material's "hiddenMask" shader constant to maskval. CALLER MUST hold the
 * VEH guard. Finds+caches the vertex-params object that declares hiddenMask. This hides
 * head vertices via per-vertex hide-groups (how a full-face helmet works) WITHOUT touching
 * any bone -- so the head-welded camera is never disturbed (bone-scaling froze Bip01 Head
 * and flew the camera away). setNamedConstant is the INT overload (the uint one crashed). */
static int apply_head_mask(void *app, int maskval, int logit)
{
    if (!readable(app, APP_MATERIAL + 8)) return 0;
    void *mat = *(void **)((uintptr_t)app + APP_MATERIAL);   /* SharedPtr: +0 = Material* */
    if (!readable(mat, 8)) return 0;
    unsigned char name[32];
    make_mstr(name, "hiddenMask");
    if (mat != g_head_params_mat) {   /* new material -> search it exactly once */
        g_head_params = NULL; g_head_params_mat = mat;
        unsigned nt = g_mat_numtech ? g_mat_numtech(mat) : 1;
        if (nt > 16) nt = 16;
        for (unsigned ti = 0; ti < nt && !g_head_params; ti++) {
            void *tech = g_mat_gettech(mat, (unsigned short)ti);
            if (!readable(tech, 8)) continue;
            unsigned np = g_tech_numpass ? g_tech_numpass(tech) : 1;
            if (np > 16) np = 16;
            for (unsigned pi = 0; pi < np; pi++) {
                void *pass = g_tech_getpass(tech, (unsigned short)pi);
                if (!readable(pass, 8)) continue;
                unsigned char sp[16] = {0};
                g_pass_getvpp(pass, sp);
                void *params = *(void **)sp;
                if (!readable(params, 8)) continue;
                void *def = g_gpup_finddef ? g_gpup_finddef(params, name, 0) : NULL;
                if (def) {
                    if (g_gpup_ignoremiss) g_gpup_ignoremiss(params, 1);
                    g_head_params = params;
                    if (logit) logline("[head] hiddenMask found: tech=%u pass=%u params=%p", ti, pi, params);
                    break;
                }
            }
        }
        if (!g_head_params && logit)
            logline("[head] hiddenMask NOT FOUND on any technique/pass of mat=%p", mat);
    }
    if (!g_head_params) return 0;
    g_gpup_setnamedi(g_head_params, name, maskval);
    return 1;
}

static int set_head_disabled(void *pc, int disable)
{
    if (g_head_dead || !g_gpup_setnamedi || !g_mat_gettech || !g_tech_getpass
        || !g_pass_getvpp || !pc) return 0;
    void *anim = readable((void *)((uintptr_t)pc + CHAR_ANIM), 8)
        ? *(void **)((uintptr_t)pc + CHAR_ANIM) : NULL;
    if (!readable(anim, ANIM_APPEARANCE + 8)) return 0;
    void *app = *(void **)((uintptr_t)anim + ANIM_APPEARANCE);
    g_player_app = app;   /* cache so the updateHiddenParts hook knows which appearance is ours */
    static int dbg; int logit = (dbg == 0); if (logit) dbg = 1;
    if (setjmp(g_guard_jb)) { g_guard_armed = 0; g_head_dead = 1;
        logline("head-mask FAULTED -- head-hide disabled"); return 0; }
    guard_arm();
    /* The head verts carry hiddenMask bit 9 (0x200): KenshiFP ships the race part-map textures
     * (skins/masks/*Mask_Default.png) with their TOP ROW painted teal #008080; the game's own
     * per-vertex bake CLAMPS head UVs (v<0) to that row at mesh load, so bit 9 == "head".
     * Hiding = set ONLY that bit; restoring = let the game recompute its vanilla mask. */
    if (disable) {
        apply_head_mask(app, (int)g_cfg_head_mask, logit);
    } else {
        if (g_update_hidden_orig) g_update_hidden_orig(app);
        else apply_head_mask(app, 0, 0);
    }
    g_guard_armed = 0;
    /* Worn head-slot gear (hat/helmet/mask/hair/beard) rides the same toggle: with the
     * head gone they would otherwise float in front of the camera. Own guard, so a fault
     * in the item walk can't take the (working) head mask down with it. */
    headgear_apply(app, disable, logit);
    return 1;
}

/* AppearanceHuman::updateHiddenParts detour: the game recomputes the hide mask from
 * equipment here and re-uploads it, clobbering our head bits. Re-inject right after so
 * the shader always sees the head hidden. This is the piece a per-frame write can't win. */
static void hooked_update_hidden(void *app)
{
    g_update_hidden_orig(app);
    if (g_head_dead || !g_cfg_hide_head || !g_fp_mode || !fp_view_is_eye() || !app || app != g_player_app) return;
    if (setjmp(g_guard_jb)) { g_guard_armed = 0; g_head_dead = 1;
        logline("[head] updateHiddenParts hook FAULTED -- head-hide disabled"); return; }
    guard_arm();
    /* the game just recomputed+uploaded its own mask -- re-add the head bit on top.
     * (The vanilla armor hide-bits are lost while head-hide is on; restored on FP exit.) */
    apply_head_mask(app, (int)g_cfg_head_mask, 0);
    g_guard_armed = 0;
    /* The same rebuild re-creates/re-shows worn item entities (equip changes, LOD, race
     * rebuilds), so re-hide the head-slot gear right after the game is done with it. */
    if (g_head_hidden) headgear_apply(app, 1, 0);
}

/* Hide the player's head mesh in FP. Two triggers:
 *  - user opt-in "Hide head" (g_cfg_hide_head): always hidden while in FP;
 *  - fast-forward (>1x game speed): the head-welded camera visibly lags the
 *    head mesh at high speed, so hide it then regardless of the setting.
 * Re-applied EVERY frame while active: the game's updateHiddenParts recomputes
 * the mask on any appearance change and would drop our head bits otherwise. */
static void fp_head_visibility(void *gw)
{
    if (g_head_dead || !g_gpup_setnamedi) return;
    float speed = readable((void *)((uintptr_t)gw + GW_FRAMESPEED), 4)
        ? *(float *)((uintptr_t)gw + GW_FRAMESPEED) : 1.0f;
    void *pc = fp_controlled_char(gw);
    int want = g_fp_mode && fp_view_is_eye() && pc && (g_cfg_hide_head || speed > 1.05f);
    if (want) {
        if (g_head_hidden && g_head_hidden_char && g_head_hidden_char != pc) {
            /* char switched: restore the old head -- only if that character is still a
             * live squad member (a freed one must never reach updateHiddenParts) */
            if (fp_char_in_squad(gw, g_head_hidden_char)) set_head_disabled(g_head_hidden_char, 0);
            else fp_head_forget_world();
            g_head_hidden = 0;
        }
        /* Apply ONLY on transition -- manuallyControlled persists our scale, and
         * re-latching it every frame is what made the head spin. */
        if (!g_head_hidden && set_head_disabled(pc, 1)) { g_head_hidden = 1; g_head_hidden_char = pc; }
        /* Re-assert the GEAR hide every frame while active: the game can re-show or
         * re-create hair/beard entities through paths that never touch
         * updateHiddenParts (field report: facial hair back after a clean hide).
         * The walk is a handful of nodes; transitions are logged (capped) inside. */
        else if (g_head_hidden && g_cfg_hide_headgear && g_player_app)
            headgear_apply(g_player_app, 1, 0);
        /* The F10 "Hide headgear" toggle can go off while the head stays hidden -- put the
         * worn head gear back immediately instead of stranding it invisible until FP exit. */
        if (!g_cfg_hide_headgear && g_gear_n > 0) headgear_apply(g_player_app, 0, 0);
    } else if (g_head_hidden) {
        void *hc = g_head_hidden_char ? g_head_hidden_char : pc;
        if (fp_char_in_squad(gw, hc)) set_head_disabled(hc, 0);
        else fp_head_forget_world();   /* gone (load/unload): nothing live to restore */
        g_head_hidden = 0; g_head_hidden_char = NULL;
    }
}

/* CameraClass::update hook: right after the game's follow camera runs, compute
 * and apply the FP camera FRESH (fp_camera_override), so every consumer later
 * in the same frame -- foliage paging, mesh LOD, shadow cascades, culling,
 * render -- sees ONE consistent, current camera. (Re-asserting last frame's
 * eye here instead caused shadow shimmer on distant meshes + rotation jitter
 * while moving: mid-frame passes used a one-frame-stale camera vs the render.)
 * Also snap the CENTER (look-at/focus) node to the eye while moving: it is the
 * lagging source grass paging keys off (proven fix for underfoot pop-in). At
 * idle the center stays vanilla for the floating-origin T calibration. */
static void hooked_cam_update(void *cam, char controlEnabled)
{
    InterlockedIncrement(&g_cam_heartbeat);
    float mmb_yaw, mmb_pitch;   /* FP owns MMB (select): the native MMB rotate is undone */
    int mmb_swallow = fpc_cam_pre(cam, &mmb_yaw, &mmb_pitch);
    g_cam_update_orig(cam, mmb_swallow ? 0 : controlEnabled);
    if (mmb_swallow) fpc_cam_post(cam, mmb_yaw, mmb_pitch);
    /* Fully inert unless FP is (or was just) engaged: at the main menu / load
     * screens this hook fires while the game is half-initialised, and running
     * the override there crashed the title screen. */
    if (!g_fp_mode && !g_ovr_prev) return;
    if (g_gw_cache) fp_camera_override(g_gw_cache);   /* fresh eye/ori, mid-frame */
    if (!g_fp_mode || !g_have_eye) return;
    if (!readable(cam, CC_FREECAM + 1)) return;
    if (*(unsigned char *)((uintptr_t)cam + CC_FREECAM)) return;   /* free-cam: hands off */
    /* Snap ONLY when this frame's eye was anchored to the head bone: a
     * fallback eye derives FROM the center (center.y + EYE_HEIGHT), so
     * snapping center=eye ratchets the camera straight UP every fallback
     * frame (visible even paused). Any head-read hiccup while moving would
     * otherwise launch the camera. */
    if (g_was_moving && g_have_t && g_eye_from_head && g_node_set_dpos) {
        void *center = *(void **)((uintptr_t)cam + CC_CENTER);
        if (readable(center, 8)) {
            g_node_set_dpos(center, g_view_have_anchor ? &g_view_anchor : &g_last_eye);
            /* CRITICAL ordering: the camera node is a CHILD of the center.
             * _setDerivedPosition converts derived->local against the parent's
             * CACHED derived transform, and after the snap the center's cache
             * is STALE until the scene-graph update -- so a plain re-assert
             * still bakes the wrong local offset and the camera rides up by
             * the center displacement (~6u, "camera rises while holding WASD").
             * Force the center's derived recompute FIRST (the game's own
             * manual-camera code does exactly this), then re-seat the camera. */
            Vec3 tmp;
            if (g_node_getdpos_upd) g_node_getdpos_upd(center, &tmp);
            void *node = *(void **)((uintptr_t)cam + CC_NODE);
            if (readable(node, 8)) {
                g_node_set_dpos(node, &g_last_eye);
                g_node_set_dori(node, &g_last_ori);
            }
        }
    }
}

/* --- optional FPS cap (KenshiFP.ini: fps_cap=N) --------------------------
 * Kenshi has no framerate limiter besides vsync, and vsync's frame pacing adds
 * jitter/latency in FP (also uncapped menus run 1000+ fps = coil whine). We own
 * the frame loop, so cap here: hybrid Sleep/spin against QueryPerformanceCounter
 * for accuracy that plain Sleep can't give. 0 (or no ini) = off. */
static int g_fps_cap;                        /* frames/sec; 0 = disabled */
static void fps_cap_wait(void)
{
    static LARGE_INTEGER freq, next;
    static int inited;
    if (g_fps_cap <= 0) return;
    if (!inited) { QueryPerformanceFrequency(&freq); QueryPerformanceCounter(&next); inited = 1; }
    LONGLONG period = freq.QuadPart / g_fps_cap;
    next.QuadPart += period;
    LARGE_INTEGER now; QueryPerformanceCounter(&now);
    if (next.QuadPart < now.QuadPart) { next = now; return; }   /* running behind: no wait */
    /* sleep the bulk (leave ~2ms), spin the remainder for precision */
    while (next.QuadPart - now.QuadPart > (freq.QuadPart / 500)) {
        Sleep(1);
        QueryPerformanceCounter(&now);
    }
    while (now.QuadPart < next.QuadPart) { YieldProcessor(); QueryPerformanceCounter(&now); }
}

static int ini_int(const char *line, const char *key, int *out)
{
    size_t kl = strlen(key);
    while (*line == ' ' || *line == '\t') line++;
    if (strncmp(line, key, kl) != 0) return 0;
    line += kl;
    while (*line == ' ' || *line == '\t') line++;
    if (*line++ != '=') return 0;
    while (*line == ' ' || *line == '\t') line++;
    *out = (int)strtol(line, NULL, 0);   /* decimal or 0x hex */
    return 1;
}

static int ini_float(const char *line, const char *key, float *out)
{
    size_t kl = strlen(key);
    while (*line == ' ' || *line == '\t') line++;
    if (strncmp(line, key, kl) != 0) return 0;
    line += kl;
    while (*line == ' ' || *line == '\t') line++;
    if (*line++ != '=') return 0;
    *out = (float)atof(line);
    return 1;
}

/* Resolve where KenshiFP.ini lives, once. The standalone reads it from the game
 * root (CWD, next to KenshiFP.log). The RE_Kenshi edition lives in a mod folder,
 * so a root-level ini is unintuitive -- prefer <this dll's folder>\KenshiFP.ini
 * if present, else fall back to the CWD path. (Existence is checked once; a new
 * file in the other location is picked up on the next game launch.) */
static const char *kfp_ini_path(void)
{
    static char path[MAX_PATH]; static int done;
    if (done) return path;
    done = 1;
    wchar_t dllw[MAX_PATH];
    DWORD n = GetModuleFileNameW(g_hinst, dllw, MAX_PATH);
    if (n > 0 && n < MAX_PATH) {
        for (DWORD k = n; k > 0; k--)
            if (dllw[k-1] == L'\\' || dllw[k-1] == L'/') { dllw[k-1] = 0; break; }
        char dlla[MAX_PATH];
        if (WideCharToMultiByte(CP_UTF8, 0, dllw, -1, dlla, MAX_PATH, NULL, NULL)) {
            char cand[MAX_PATH];
            snprintf(cand, sizeof cand, "%s\\KenshiFP.ini", dlla);
            FILE *t = fopen(cand, "r");
            if (t) { fclose(t); strncpy(path, cand, sizeof path - 1); return path; }
        }
    }
    strcpy(path, "KenshiFP.ini");   /* CWD (game root) fallback */
    return path;
}

static void load_ini(void)
{
    FILE *f = fopen(kfp_ini_path(), "r");   /* mod folder, else CWD = game dir */
    if (!f) return;
    char line[160]; int v; float fv;
    while (fgets(line, sizeof line, f)) {
        if (line[0] == ';' || line[0] == '#') continue;
        if (ini_int(line, "fps_cap", &v))        g_fps_cap = (v >= 15 && v <= 1000) ? v : 0;
        else if (ini_int(line, "aim_lean", &v))       g_cfg_aim_lean = !!v;
        else if (ini_int(line, "ranged_freeaim", &v)) g_cfg_freeaim  = !!v;
        else if (ini_int(line, "camera_zoom", &v)) g_cfg_camera_zoom=!!v;
        else if (ini_int(line, "combat_auto_reload", &v)) g_cfg_combat_auto_reload=!!v;
        else if (ini_float(line, "spread_scale", &fv)) { if (fv >= 0 && fv <= 5) g_cfg_spread_scale = fv; }
        else if (ini_int(line, "direct_control_default", &v)) g_cfg_direct_default = !!v;
        else if (ini_int(line, "key_take_control", &v)) { if (v>0 && v<255) g_cfg_key_take_control=v; }
        else if (ini_int(line, "wheel_speed", &v))    g_cfg_wheel    = !!v;
        else if (ini_int(line, "ko_vignette", &v))    g_cfg_vignette = !!v;
        else if (ini_int(line, "key_toggle_fp", &v))  { if (v > 0 && v < 255) g_cfg_key_fp = v; }
        else if (ini_int(line, "key_forward", &v))    { if (v > 0 && v < 255) g_cfg_key_w = v; }
        else if (ini_int(line, "key_left", &v))       { if (v > 0 && v < 255) g_cfg_key_a = v; }
        else if (ini_int(line, "key_back", &v))       { if (v > 0 && v < 255) g_cfg_key_s = v; }
        else if (ini_int(line, "key_right", &v))      { if (v > 0 && v < 255) g_cfg_key_d = v; }
        else if (ini_int(line, "key_settings", &v))   { if (v > 0 && v < 255) g_cfg_key_settings = v; }
        else if (ini_int(line, "manual_combat", &v))  g_cfg_manual_combat = !!v;
        else if (ini_int(line, "key_attack", &v))     { if (v > 0 && v < 255) g_cfg_key_attack = v; }
        else if (ini_int(line, "key_block", &v))      { if (v > 0 && v < 255) g_cfg_key_block = v; }
        else if (ini_int(line, "key_select", &v))     { if (v > 0 && v < 255) g_cfg_key_select = v; }
        else if (ini_int(line, "key_interact", &v))   { if (v > 0 && v < 255) g_cfg_key_interact = v; }
        else if (ini_int(line, "key_draw", &v))       { if (v > 0 && v < 255) g_cfg_key_draw = v; }
        else if (ini_int(line, "key_free_cursor", &v)) { if (v >= 0 && v < 255) g_cfg_key_free = v; }
        else if (ini_int(line, "key_sprint", &v))     { if (v >= 0 && v < 255) g_cfg_key_sprint = v; }
        else if (ini_float(line, "fov", &fv))             { if (fv >= 40 && fv <= 120) g_cfg_fov = fv; }
        else if (ini_float(line, "near_clip", &fv))       { if (fv >= 0.5f && fv <= 10) g_cfg_nearclip = fv; }
        else if (ini_float(line, "sensitivity", &fv))     { if (fv >= 0.05f && fv <= 10) g_cfg_sens = fv; }
        else if (ini_float(line, "eye_forward", &fv))     { if (fv >= -50 && fv <= 10) g_cfg_eye_fwd = fv; }
        else if (ini_float(line, "eye_up", &fv))          { if (fv >= -50 && fv <= 50) g_cfg_eye_up = fv; }
        else if (ini_int(line, "cam_weld", &v))           g_cfg_cam_weld = !!v;
        else if (ini_float(line, "eye_shift", &fv))       { if (fv >= -50 && fv <= 50) g_cfg_eye_shift = fv; }
        else if (ini_float(line, "move_forward", &fv))    { if (fv >= 0 && fv <= 10) g_cfg_move_fwd = fv; }
        else if (ini_float(line, "move_speed_ref", &fv))  { if (fv >= 5 && fv <= 400) g_cfg_move_ref = fv; }
        else if (ini_float(line, "aim_lean_amount", &fv)) { if (fv >= 0 && fv <= 1.5f) g_cfg_lean = fv; }
        else if (ini_float(line, "exit_camera_zoom", &fv)) { if (fv >= -500 && fv <= 500) g_cfg_exit_zoom = fv; }
        else if (ini_int(line, "sneak_eye", &v))          g_cfg_sneak_eye = !!v;
        else if (ini_int(line, "stealth_arrows", &v))     g_cfg_stealth_arrows = !!v;
        else if (ini_int(line, "screen_status", &v))      g_cfg_screen_status = !!v;
        else if (ini_int(line, "hide_head", &v))          g_cfg_hide_head = !!v;
        else if (ini_int(line, "head_hide_mask", &v))     g_cfg_head_mask = (unsigned)v;
        else if (ini_int(line, "hide_headgear", &v))      g_cfg_hide_headgear = !!v;
        else if (ini_int(line, "headgear_slots", &v))     g_cfg_headgear_slots = (unsigned)v;
        else if (ini_int(line, "auto_floors", &v))        g_cfg_auto_floors = !!v;
        else if (ini_int(line, "falling", &v))            g_cfg_falling = !!v;
        else if (ini_float(line, "fall_drop", &fv))       { if (fv >= 2 && fv <= 200) g_cfg_fall_drop = fv; }
        else if (ini_float(line, "fall_probe", &fv))      { if (fv >= 1 && fv <= 100) g_cfg_fall_probe = fv; }
        else if (ini_float(line, "fall_air", &fv))        { if (fv >= 0.2f && fv <= 10) g_cfg_fall_air = fv; }
        else if (ini_float(line, "fall_ko", &fv))         { if (fv >= 20 && fv <= 500) g_cfg_fall_ko = fv; }
        else if (ini_float(line, "fall_settle", &fv))     { if (fv >= 0.2f && fv <= 10) g_cfg_fall_settle = fv; }
        else if (ini_float(line, "fall_timeout", &fv))    { if (fv >= 2 && fv <= 60) g_cfg_fall_timeout = fv; }
        else if (ini_float(line, "fall_gravity", &fv))    { if (fv >= 5 && fv <= 2000) g_cfg_fall_gravity = fv; }
        else if (ini_float(line, "fall_maxvel", &fv))     { if (fv >= 10 && fv <= 5000) g_cfg_fall_maxvel = fv; }
        else if (ini_int(line, "jump", &v))               g_cfg_jump = !!v;
        else if (ini_float(line, "jump_vel", &fv))        { if (fv >= 10 && fv <= 200) g_cfg_jump_vel = fv; }
        else if (ini_int(line, "key_jump", &v))           { if (v > 0 && v < 255) g_cfg_key_jump = v; }
        else if (ini_int(line, "key_pause", &v))          { if (v >= 0 && v < 255) g_cfg_key_pause = v; }
        else if (vm_ini(line))                            ;
        else if (ini_int(line, "locomotion", &v))         g_cfg_loco = !!v;
        else if (ini_int(line, "state_hud", &v))          g_cfg_state_hud = !!v;
        else if (ini_int(line, "loco_clip", &v))          { if (v >= -1 && v < 64) g_cfg_loco_clip = v; }
        else if (ini_int(line, "loco_hips", &v))          g_cfg_loco_hips = !!v;
        else if (ini_float(line, "loco_walk_ref", &fv))   { if (fv >= 1 && fv <= 400) g_cfg_loco_walkref = fv; }
        else if (ini_float(line, "loco_jog_ref", &fv))    { if (fv >= 2 && fv <= 400) g_cfg_loco_jogref = fv; }
        else if (ini_int(line, "loco_face_lock", &v))     g_cfg_loco_facelock = !!v;
        else if (ini_int(line, "loco_foot_ik", &v))       g_cfg_loco_footik = !!v;
        else if (ini_float(line, "ik_lift", &fv))         { if (fv >= -0.5f && fv <= 0.5f) g_cfg_ik_lift = fv; }
        else if (ini_float(line, "tip_start_deg", &fv))   { if (fv >= 5 && fv <= 180) g_cfg_tip_start_deg = fv; }
        else if (ini_float(line, "tip_turn_deg", &fv))    { if (fv >= 30 && fv <= 1000) g_cfg_tip_turn_deg = fv; }
        else if (ini_float(line, "head_max_deg", &fv))    { if (fv >= 0 && fv <= 180) g_cfg_headmax_deg = fv; }
        else if (ini_int(line, "loco_aim", &v))           g_cfg_loco_aim = !!v;
        else if (ini_float(line, "loco_aim_pitch", &fv))  { if (fv >= 0 && fv <= 4) g_cfg_loco_aim_p = fv; }
        else if (ini_float(line, "loco_aim_yaw", &fv))    { if (fv >= 0 && fv <= 4) g_cfg_loco_aim_y = fv; }
        else if (ini_float(line, "loco_aim_roll", &fv))   { if (fv >= 0 && fv <= 2) g_cfg_loco_aim_r = fv; }
        else if (ini_float(line, "loco_lean", &fv))       { if (fv >= 0 && fv <= 5) g_cfg_loco_lean = fv; }
        else if (ini_float(line, "loco_brake", &fv))      { if (fv >= 0 && fv <= 30) g_cfg_loco_brake = fv; }
        else if (ini_float(line, "loco_follow_rate", &fv)) { if (fv >= 0.5f && fv <= 30) g_cfg_loco_frate = fv; }
        else if (ini_float(line, "loco_follow_dead_deg", &fv)) { if (fv >= 0 && fv <= 45) g_cfg_loco_fdead = fv; }
        else if (ini_float(line, "sneak_offset_x", &fv))  { if (fv >= -2000 && fv <= 2000) g_cfg_sneak_x = fv; }
        else if (ini_float(line, "sneak_offset_y", &fv))  { if (fv >= -2000 && fv <= 2000) g_cfg_sneak_y = fv; }
        else if (ini_float(line, "status_offset_x", &fv)) { if (fv >= -2000 && fv <= 2000) g_cfg_status_x = fv; }
        else if (ini_float(line, "status_offset_y", &fv)) { if (fv >= -2000 && fv <= 2000) g_cfg_status_y = fv; }
    }
    fclose(f);
    if (g_fps_cap) timeBeginPeriod(1);
    logline("config: fps_cap=%d aim_lean=%d freeaim=%d wheel=%d vignette=%d fpkey=0x%02X loco=%d clip=%d hips=%d",
            g_fps_cap, g_cfg_aim_lean, g_cfg_freeaim, g_cfg_wheel, g_cfg_vignette, g_cfg_key_fp,
            g_cfg_loco, g_cfg_loco_clip, g_cfg_loco_hips);
}

/* Persist the current settings to the ini so F10 changes survive a restart.
 * Full rewrite (all keys) to the same path load_ini() reads. Called on discrete
 * UI events (toggle, reset, window close) -- not per-frame. The hot-reload will
 * notice the new mtime and re-parse the identical values (harmless no-op). */
static void save_ini(void)
{
    const char *path = kfp_ini_path();
    FILE *f = fopen(path, "w");
    if (!f) { logline("[settings] save FAILED (%s)", path); return; }
    fprintf(f, "; KenshiFP settings -- written by the F10 panel; edited values hot-reload.\n");
    fprintf(f, "fps_cap=%d\n",          g_fps_cap);
    fprintf(f, "fov=%.2f\n",            g_cfg_fov);
    fprintf(f, "near_clip=%.3f\n",      g_cfg_nearclip);
    fprintf(f, "sensitivity=%.3f\n",    g_cfg_sens);
    fprintf(f, "eye_forward=%.3f\n",    g_cfg_eye_fwd);
    fprintf(f, "eye_up=%.3f\n",         g_cfg_eye_up);
    fprintf(f, "cam_weld=%d\n",         g_cfg_cam_weld);
    fprintf(f, "eye_shift=%.3f\n",      g_cfg_eye_shift);
    fprintf(f, "move_forward=%.3f\n",   g_cfg_move_fwd);
    fprintf(f, "move_speed_ref=%.2f\n", g_cfg_move_ref);
    fprintf(f, "aim_lean_amount=%.3f\n",g_cfg_lean);
    fprintf(f, "exit_camera_zoom=%.2f\n",g_cfg_exit_zoom);
    fprintf(f, "aim_lean=%d\n",         g_cfg_aim_lean);
    fprintf(f, "ranged_freeaim=%d\n",   g_cfg_freeaim);
    fprintf(f, "camera_zoom=%d\n",g_cfg_camera_zoom);
    fprintf(f, "direct_control_default=%d\n",g_cfg_direct_default);
    fprintf(f, "key_take_control=%d\n",g_cfg_key_take_control);
    fprintf(f, "wheel_speed=%d\n",      g_cfg_wheel);
    fprintf(f, "ko_vignette=%d\n",      g_cfg_vignette);
    fprintf(f, "sneak_eye=%d\n",        g_cfg_sneak_eye);
    fprintf(f, "state_hud=%d\n",        g_cfg_state_hud);
    fprintf(f, "stealth_arrows=%d\n",   g_cfg_stealth_arrows);
    fprintf(f, "screen_status=%d\n",    g_cfg_screen_status);
    fprintf(f, "hide_head=%d\n",        g_cfg_hide_head);
    fprintf(f, "head_hide_mask=0x%x\n", g_cfg_head_mask);
    fprintf(f, "hide_headgear=%d\n",    g_cfg_hide_headgear);
    fprintf(f, "headgear_slots=0x%x\n", g_cfg_headgear_slots);
    fprintf(f, "auto_floors=%d\n",      g_cfg_auto_floors);
    fprintf(f, "falling=%d\n",          g_cfg_falling);
    fprintf(f, "fall_drop=%.1f\n",      g_cfg_fall_drop);
    fprintf(f, "fall_probe=%.1f\n",     g_cfg_fall_probe);
    fprintf(f, "fall_air=%.1f\n",       g_cfg_fall_air);
    fprintf(f, "fall_ko=%.1f\n",        g_cfg_fall_ko);
    fprintf(f, "fall_settle=%.1f\n",    g_cfg_fall_settle);
    fprintf(f, "fall_timeout=%.1f\n",   g_cfg_fall_timeout);
    fprintf(f, "fall_gravity=%.1f\n",   g_cfg_fall_gravity);
    fprintf(f, "fall_maxvel=%.1f\n",    g_cfg_fall_maxvel);
    fprintf(f, "jump=%d\n",             g_cfg_jump);
    fprintf(f, "jump_vel=%.1f\n",       g_cfg_jump_vel);
    fprintf(f, "key_jump=%d\n",         g_cfg_key_jump);
    fprintf(f, "key_pause=%d\n",        g_cfg_key_pause);
    fprintf(f, "locomotion=%d\n",       g_cfg_loco);
    fprintf(f, "loco_clip=%d\n",        g_cfg_loco_clip);
    fprintf(f, "loco_hips=%d\n",        g_cfg_loco_hips);
    fprintf(f, "loco_walk_ref=%.1f\n",  g_cfg_loco_walkref);
    fprintf(f, "loco_jog_ref=%.1f\n",   g_cfg_loco_jogref);
    fprintf(f, "loco_face_lock=%d\n",   g_cfg_loco_facelock);
    fprintf(f, "loco_foot_ik=%d\n",     g_cfg_loco_footik);
    fprintf(f, "ik_lift=%.2f\n",        g_cfg_ik_lift);
    fprintf(f, "tip_start_deg=%.1f\n",  g_cfg_tip_start_deg);
    fprintf(f, "tip_turn_deg=%.1f\n",   g_cfg_tip_turn_deg);
    fprintf(f, "head_max_deg=%.1f\n",   g_cfg_headmax_deg);
    fprintf(f, "loco_aim=%d\n",         g_cfg_loco_aim);
    fprintf(f, "loco_aim_pitch=%.2f\n", g_cfg_loco_aim_p);
    fprintf(f, "loco_aim_yaw=%.2f\n",   g_cfg_loco_aim_y);
    fprintf(f, "loco_aim_roll=%.2f\n",  g_cfg_loco_aim_r);
    fprintf(f, "loco_lean=%.2f\n",      g_cfg_loco_lean);
    fprintf(f, "loco_brake=%.1f\n",     g_cfg_loco_brake);
    fprintf(f, "loco_follow_rate=%.1f\n", g_cfg_loco_frate);
    fprintf(f, "loco_follow_dead_deg=%.1f\n", g_cfg_loco_fdead);
    fprintf(f, "sneak_offset_x=%.1f\n", g_cfg_sneak_x);
    fprintf(f, "sneak_offset_y=%.1f\n", g_cfg_sneak_y);
    fprintf(f, "status_offset_x=%.1f\n", g_cfg_status_x);
    fprintf(f, "status_offset_y=%.1f\n", g_cfg_status_y);
    fprintf(f, "key_toggle_fp=%d\n",    g_cfg_key_fp);
    fprintf(f, "key_forward=%d\n",      g_cfg_key_w);
    fprintf(f, "key_left=%d\n",         g_cfg_key_a);
    fprintf(f, "key_back=%d\n",         g_cfg_key_s);
    fprintf(f, "key_right=%d\n",        g_cfg_key_d);
    fprintf(f, "key_settings=%d\n",     g_cfg_key_settings);
    fprintf(f, "key_free_cursor=%d\n",  g_cfg_key_free);
    fprintf(f, "key_sprint=%d\n",       g_cfg_key_sprint);
    fprintf(f, "manual_combat=%d\n",    g_cfg_manual_combat);
    fprintf(f, "key_attack=%d\n",       g_cfg_key_attack);
    fprintf(f, "key_block=%d\n",        g_cfg_key_block);
    fprintf(f, "key_select=%d\n",       g_cfg_key_select);
    fprintf(f, "key_interact=%d\n",     g_cfg_key_interact);
    fprintf(f, "key_draw=%d\n",         g_cfg_key_draw);
    fclose(f);
    logline("[settings] saved to %s", path);
}

/* Hot reload: re-parse when the file's write time changes (checked ~2 Hz),
 * so settings apply in-game without a restart. */
static void ini_hot_reload(void)
{
    static DWORD last_check; static FILETIME last_wt;
    DWORD now = GetTickCount();
    if (now - last_check < 500) return;
    last_check = now;
    WIN32_FILE_ATTRIBUTE_DATA fad;
    if (!GetFileAttributesExA(kfp_ini_path(), GetFileExInfoStandard, &fad)) return;
    if (CompareFileTime(&fad.ftLastWriteTime, &last_wt) != 0) {
        last_wt = fad.ftLastWriteTime;
        load_ini();
    }
}

/* All MyGUI widget work, run POST-FRAME (from hooked_mainloop, after the
 * game's frame + UI update completed) so we never touch MyGUI's widget lists
 * mid-update. Reads only globals published during the frame. */
/* ------- in-game settings UI (MyGUI) : M1 = button + toggle window --------- */
static void *g_settings_win;    /* our floating settings Window (Kenshi_WindowCX) */
static void *g_settings_btn;    /* the injected "KenshiFP Settings" options-tab button */
/* g_settings_open declared up top (read by the FP cursor-lock code) */

/* Set a widget's caption from a C string via a temporary MyGUI::UString (a single
 * basic_string<char16> = 0x20 bytes). Construct on the stack, set, destruct. */
/* Set a caption via `setter` (Window::setCaption for the title bar,
 * TextBox::setCaption for plain labels), building a temporary MyGUI::UString. */
static void caption_set(void *w, const char *text, textbox_setcap_t setter)
{
    if (!w || !setter || !g_ustring_ctor) return;   /* dtor optional (tiny leak ok) */
    unsigned char ustr[0x40] = {0};   /* UString (basic_string<u16>) */
    g_ustring_ctor(ustr, text);
    setter(w, ustr);
    if (g_ustring_dtor) g_ustring_dtor(ustr);
}

static int g_settings_dead;     /* a MyGUI call faulted -> stand down permanently */

/* DFS the MyGUI widget tree for a widget whose name (minus its layout prefix,
 * the part after the last '_') equals `target`. The Enumerator returned by
 * getEnumerator is { bool m_first; Widget** begin; Widget** end } -- iterate the
 * begin..end pointer range. Depth-capped; assumes the caller armed g_guard_jb. */
static int g_find_budget;   /* nodes left to visit this search (runaway guard) */
__attribute__((unused))
static void *find_widget_suffix(void **begin, void **end, const char *target, int depth)
{
    if (!begin || !end || depth > 10) return NULL;
    /* sanity the enumerator range: a bad ABI/stale vector would give a wild
     * begin..end and iterating it would read wild memory forever. */
    if (end < begin || (size_t)(end - begin) > 2048) return NULL;
    for (void **it = begin; it != end; ++it) {
        if (--g_find_budget <= 0) return NULL;   /* total-node cap */
        if (!readable(it, 8)) return NULL;
        void *w = *it;
        if (!readable(w, 8)) continue;
        if (g_widget_getname) {
            const void *ns = g_widget_getname(w);
            char nm[128]; read_mstring(ns, nm, sizeof nm);
            const char *suf = strrchr(nm, '_'); suf = suf ? suf + 1 : nm;
            if (strcmp(suf, target) == 0) return w;
        }
        if (g_widget_getenum) {
            unsigned char ce[32];
            g_widget_getenum(w, ce);
            void *found = find_widget_suffix(*(void ***)(ce + 8), *(void ***)(ce + 16), target, depth + 1);
            if (found) return found;
        }
    }
    return NULL;
}

/* Find a vanilla menu widget by name-suffix, walking from the Gui roots. */
__attribute__((unused))
static void *settings_find(void *gui, const char *target)
{
    if (!g_gui_getenum) return NULL;
    g_find_budget = 4000;
    unsigned char ge[32];
    g_gui_getenum(gui, ge);
    return find_widget_suffix(*(void ***)(ge + 8), *(void ***)(ge + 16), target, 0);
}

/* Ensure our floating settings window exists (created lazily the first time the
 * button is clicked -- NOT at load, to avoid touching MyGUI during load/menu
 * transitions). Returns the window or NULL. */
/* Create a child widget on `parent`, handling skin/type/name strings of any
 * length (Kenshi skin names exceed the 15-char SSO limit). */
static void *make_child(void *parent, const char *type, const char *skin,
                        int l, int t, int w, int h, const char *name)
{
    if (!g_widget_createwidget || !parent) return NULL;
    unsigned char ty[32], sk[32], nm[32];
    void *tf = make_mstr_long(ty, type);
    void *sf = make_mstr_long(sk, skin);
    void *nf = make_mstr_long(nm, name);
    void *child = g_widget_createwidget(parent, ty, sk, l, t, w, h, 0, nm);
    if (tf) free(tf);
    if (sf) free(sf);
    if (nf) free(nf);
    return child;
}

/* --- settings model: numeric sliders + toggle checkboxes -------------------- */
typedef struct { const char *label; float *cfg; float lo, hi, def; void *slider, *valtb; int lastpos; } fset_t;
static fset_t g_fsets[] = {
    { "FOV",             &g_cfg_fov,      40.0f, 120.0f, 70.0f, 0, 0, -1 },
    { "Sensitivity",     &g_cfg_sens,      0.1f,   5.0f,  1.0f, 0, 0, -1 },
    { "Near clip",       &g_cfg_nearclip,  0.5f,   5.0f,  3.0f, 0, 0, -1 },
    { "Eye forward",     &g_cfg_eye_fwd, -30.0f,   8.0f,  0.8f, 0, 0, -1 },
    { "Eye upward",      &g_cfg_eye_up,  -10.0f,  10.0f,  0.0f, 0, 0, -1 },
    { "Eye shift",       &g_cfg_eye_shift,-8.0f,   8.0f,  0.0f, 0, 0, -1 },
    { "Move forward",    &g_cfg_move_fwd,  0.0f,   6.0f,  1.5f, 0, 0, -1 },
    { "Move speed ref",  &g_cfg_move_ref, 20.0f, 200.0f, 60.0f, 0, 0, -1 },
    { "Aim-lean amount", &g_cfg_lean,      0.0f,   1.5f,  0.5f, 0, 0, -1 },
    { "Sneak eye X",     &g_cfg_sneak_x, -400.0f, 400.0f,  0.0f, 0, 0, -1 },
    { "Sneak eye Y",     &g_cfg_sneak_y, -400.0f, 400.0f,  0.0f, 0, 0, -1 },
    { "Status X",        &g_cfg_status_x, -400.0f, 400.0f, 0.0f, 0, 0, -1 },
    { "Status Y",        &g_cfg_status_y, -400.0f, 400.0f, 0.0f, 0, 0, -1 },
};
typedef struct { const char *label; int *cfg, def; void *btn; } tset_t;
static tset_t g_tsets[] = {
    { "Aim lean",        &g_cfg_aim_lean, 1, 0 },
    { "Ranged free-aim", &g_cfg_freeaim,  1, 0 },
    { "Wheel speed",     &g_cfg_wheel,    1, 0 },
    { "KO vignette",     &g_cfg_vignette, 1, 0 },
    { "Falling",         &g_cfg_falling,  0, 0 },
    { "Jump (Space)",    &g_cfg_jump,     0, 0 },
    { "Custom anims",    &g_cfg_loco,     1, 0 },   /* the full-body locomotion
        * system (8-way blendspace, turn-in-place, foot IK). OFF = vanilla Kenshi
        * animations. The gate's else-branch already releases every bone we own,
        * so this is safe to flip mid-game. */
    { "Sneak eye",       &g_cfg_sneak_eye, 1, 0 },
    { "Combat state",    &g_cfg_state_hud, 1, 0 },
    { "Stealth arrows",  &g_cfg_stealth_arrows, 0, 0 },
    { "Status @ xhair",  &g_cfg_screen_status, 1, 0 },
    { "Head weld",       &g_cfg_cam_weld, 1, 0 },
    { "Hide head",       &g_cfg_hide_head, 1, 0 },
    { "Hide headgear",   &g_cfg_hide_headgear, 1, 0 },
    { "Auto floors",     &g_cfg_auto_floors, 1, 0 },
    { "Manual combat",   &g_cfg_manual_combat, 1, 0 },
};
/* key-bind rows: click the button, then press a key or mouse button (Esc cancels) */
typedef struct { const char *label; int *cfg, def; void *btn; } kset_t;
static kset_t g_ksets[] = {
    { "Attack",          &g_cfg_key_attack,   0x01, 0 },
    { "Block / aim",     &g_cfg_key_block,    0x02, 0 },
    { "Select target",   &g_cfg_key_select,   0x04, 0 },
    { "Interact",        &g_cfg_key_interact, 0x02, 0 },
    { "Draw / holster",  &g_cfg_key_draw,     0x52, 0 },
};
static int g_kb_cap = -1;      /* bind row waiting for a key, -1 = none */
static int g_kb_cap_armed;     /* all keys were up since the capture started */
static int g_kb_eat;           /* >0: swallow Esc/LMB in the settings window until they are released */
static void kb_name(int vk, char *out, size_t n)
{
    switch (vk) {
    case 0x01: snprintf(out, n, "Left mouse"); return;
    case 0x02: snprintf(out, n, "Right mouse"); return;
    case 0x04: snprintf(out, n, "Middle mouse"); return;
    case 0x05: snprintf(out, n, "Mouse 4"); return;
    case 0x06: snprintf(out, n, "Mouse 5"); return;
    }
    LONG sc = (LONG)MapVirtualKeyA((UINT)vk, 0 /* MAPVK_VK_TO_VSC */) << 16;
    if ((vk >= 0x21 && vk <= 0x2E) || vk == 0xA3 || vk == 0xA5 || vk == 0x5B || vk == 0x5C || vk == 0x6F || vk == 0x90)
        sc |= 1 << 24;          /* extended key: arrows, nav block, right ctrl/alt, win, num / */
    if (!sc || !GetKeyNameTextA(sc, out, (int)n)) snprintf(out, n, "Key 0x%02X", vk);
}
static void kb_caption(int i)
{
    char b[48];
    if (i == g_kb_cap) snprintf(b, sizeof b, "Press a key... (Esc)"); else kb_name(*g_ksets[i].cfg, b, sizeof b);
    if (g_ksets[i].btn) caption_set(g_ksets[i].btn, b, g_textbox_setcap);
}
/* While a bind row waits: first wait until every key is up (the click that started it), then take the next
 * pressed key/button. Generic Shift/Ctrl/Alt (0x10-0x12) are skipped so the left/right variant is stored. */
static int kb_capture_step(void)
{
    int down = 0;
    for (int vk = 1; vk < 0xFF; ++vk) {
        if (vk == 0x03 || vk == 0x07 || (vk >= 0x10 && vk <= 0x12)) continue;
        if (!(GetAsyncKeyState(vk) & 0x8000)) continue;
        if (!g_kb_cap_armed) return 0;
        down = vk; break;
    }
    if (!g_kb_cap_armed) { g_kb_cap_armed = 1; return 0; }
    if (!down) return 0;
    int i = g_kb_cap; g_kb_cap = -1; g_kb_eat = 1;
    if (down != VK_ESCAPE && down != g_cfg_key_settings) {
        *g_ksets[i].cfg = down;
        logline("[settings] bind %s = 0x%02X", g_ksets[i].label, down);
    }
    kb_caption(i);
    return down != VK_ESCAPE && down != g_cfg_key_settings;
}
static void *g_reset_btn, *g_close_btn;
#define KFP_SCROLL_RANGE 1000
#define FN(a) ((int)(sizeof(a)/sizeof((a)[0])))

/* Is the widget currently under the mouse `target` (or a descendant of it)?
 * Uses MyGUI's own mouse-focus tracking -- no coordinate math. */
static int widget_clicked(void *target)
{
    if (!target || !g_input_getinst || !g_mousefocus) return 0;
    void *im = g_input_getinst();
    if (!im) return 0;
    void *f = g_mousefocus(im);
    for (int i = 0; i < 10 && readable(f, 8); i++) {
        if (f == target) return 1;
        if (!g_widget_getparent) break;
        f = g_widget_getparent(f);
    }
    return 0;
}

/* Push a float setting's current value onto its slider + value label. */
static void settings_apply_slider(fset_t *fs)
{
    if (fs->slider && g_scroll_setpos) {
        float frac = (*fs->cfg - fs->lo) / (fs->hi - fs->lo);
        if (frac < 0) frac = 0; else if (frac > 1) frac = 1;
        int pos = (int)(frac * (KFP_SCROLL_RANGE - 1) + 0.5f);
        g_scroll_setpos(fs->slider, (size_t)pos);
        fs->lastpos = pos;
    }
    if (fs->valtb) { char vb[32]; snprintf(vb, sizeof vb, "%.2f", *fs->cfg); caption_set(fs->valtb, vb, g_textbox_setcap); }
}

static void settings_reset_defaults(void)
{
    for (int i = 0; i < FN(g_fsets); i++) { *g_fsets[i].cfg = g_fsets[i].def; settings_apply_slider(&g_fsets[i]); }
    for (int i = 0; i < FN(g_tsets); i++) {
        *g_tsets[i].cfg = g_tsets[i].def;
        if (g_tsets[i].btn && g_btn_setsel) g_btn_setsel(g_tsets[i].btn, *g_tsets[i].cfg ? 1 : 0);
    }
    g_kb_cap = -1;
    for (int i = 0; i < FN(g_ksets); i++) { *g_ksets[i].cfg = g_ksets[i].def; kb_caption(i); }
    if (KFP_DEBUG_LOG) logline("[settings] reset to defaults");
}

/* Build the rows once, on window creation. Sliders drag natively (we poll their
 * value); checkboxes we click-poll (a plain Button doesn't self-toggle). */
static void settings_build_content(void *win)
{
    if (!win || !g_scroll_setrange || !g_scroll_setpos) return;
    const int pad = 16, rowh = 30, labw = 150, sx = 175, sw = 210, vx = 395, vw = 95;
    int y = 14;
    for (int i = 0; i < FN(g_fsets); i++) {
        fset_t *fs = &g_fsets[i];
        char nm[32];
        snprintf(nm, sizeof nm, "KFPlbl%d", i);
        void *lbl = make_child(win, "TextBox", "Kenshi_GenericTextBoxFlat", pad, y, labw, 24, nm);
        if (lbl) caption_set(lbl, fs->label, g_textbox_setcap);
        snprintf(nm, sizeof nm, "KFPsld%d", i);
        void *sld = make_child(win, "ScrollBar", "Kenshi_ScrollBar", sx, y + 2, sw, 18, nm);
        if (sld) {
            g_scroll_setrange(sld, KFP_SCROLL_RANGE);
            float frac = (*fs->cfg - fs->lo) / (fs->hi - fs->lo);
            if (frac < 0) frac = 0; else if (frac > 1) frac = 1;
            int pos = (int)(frac * (KFP_SCROLL_RANGE - 1) + 0.5f);
            g_scroll_setpos(sld, (size_t)pos);
            fs->lastpos = pos;
        }
        fs->slider = sld;
        snprintf(nm, sizeof nm, "KFPval%d", i);
        void *val = make_child(win, "TextBox", "Kenshi_GenericTextBoxFlat", vx, y, vw, 24, nm);
        fs->valtb = val;
        if (val) { char vb[32]; snprintf(vb, sizeof vb, "%.2f", *fs->cfg); caption_set(val, vb, g_textbox_setcap); }
        y += rowh;
    }
    y += 10;
    /* toggles in TWO COLUMNS: the list outgrew the window */
    {
        int y0 = y, rows = (FN(g_tsets) + 1) / 2;
        for (int i = 0; i < FN(g_tsets); i++) {
            tset_t *ts = &g_tsets[i];
            int col = i / rows, row = i % rows;
            int lx = pad + col * 250, cx = lx + 156;
            int ry = y0 + row * rowh;
            char nm[32];
            snprintf(nm, sizeof nm, "KFPtl%d", i);
            void *lbl = make_child(win, "TextBox", "Kenshi_GenericTextBoxFlat", lx, ry, labw, 24, nm);
            if (lbl) caption_set(lbl, ts->label, g_textbox_setcap);
            snprintf(nm, sizeof nm, "KFPck%d", i);
            void *chk = make_child(win, "Button", "Kenshi_TickBoxSkin", cx, ry, 24, 24, nm);
            if (chk && g_btn_setsel) g_btn_setsel(chk, *ts->cfg ? 1 : 0);
            ts->btn = chk;
        }
        y = y0 + rows * rowh;
    }
    y += 10;
    {
        int y0 = y, rows = (FN(g_ksets) + 1) / 2;
        for (int i = 0; i < FN(g_ksets); i++) {
            kset_t *ks = &g_ksets[i];
            int col = i / rows, row = i % rows;
            int lx = pad + col * 250;
            int ry = y0 + row * rowh;
            char nm[32];
            snprintf(nm, sizeof nm, "KFPkl%d", i);
            void *lbl = make_child(win, "TextBox", "Kenshi_GenericTextBoxFlat", lx, ry, 100, 24, nm);
            if (lbl) caption_set(lbl, ks->label, g_textbox_setcap);
            snprintf(nm, sizeof nm, "KFPkb%d", i);
            ks->btn = make_child(win, "Button", "Kenshi_Button1", lx + 102, ry - 2, 138, 28, nm);
            kb_caption(i);
        }
        y = y0 + rows * rowh;
    }
    g_reset_btn = make_child(win, "Button", "Kenshi_Button1", pad, y + 8, 190, 32, "KFPreset");
    if (g_reset_btn) caption_set(g_reset_btn, "Reset to Defaults", g_textbox_setcap);
    g_close_btn = make_child(win, "Button", "Kenshi_Button1", pad + 200, y + 8, 110, 32, "KFPclose");
    if (g_close_btn) caption_set(g_close_btn, "Close", g_textbox_setcap);
    logline("[settings] built %d sliders + %d toggles + %d binds; reset=%p close=%p", FN(g_fsets), FN(g_tsets), FN(g_ksets), g_reset_btn, g_close_btn);
}

/* Poll widget state -> config, every frame while the window is open. */
static void settings_poll_content(void)
{
    for (int i = 0; i < FN(g_fsets); i++) {
        fset_t *fs = &g_fsets[i];
        if (!fs->slider || !g_scroll_getpos) continue;
        int pos = (int)g_scroll_getpos(fs->slider);
        if (pos == fs->lastpos) continue;           /* only on drag */
        fs->lastpos = pos;
        float frac = pos / (float)(KFP_SCROLL_RANGE - 1);
        if (frac < 0) frac = 0; else if (frac > 1) frac = 1;
        *fs->cfg = fs->lo + frac * (fs->hi - fs->lo);
        if (fs->valtb) { char vb[32]; snprintf(vb, sizeof vb, "%.2f", *fs->cfg); caption_set(fs->valtb, vb, g_textbox_setcap); }
    }
    /* checkbox click-poll: LMB release inside a box toggles its config */
    static int lmb_prev;
    int lmb = (GetAsyncKeyState(VK_LBUTTON) & 0x8000) != 0;
    int released = (lmb_prev && !lmb);
    lmb_prev = lmb;
    int changed = 0;
    if (g_kb_cap >= 0) { if (kb_capture_step()) save_ini(); return; }
    if (g_kb_eat) {     /* the key/click that ended a capture: eat it until released, plus one frame */
        int esc = (GetAsyncKeyState(VK_ESCAPE) & 0x8000) != 0;
        if (lmb || esc) g_kb_eat = 1; else if (++g_kb_eat > 2) g_kb_eat = 0;
        return;
    }
    for (int i = 0; i < FN(g_ksets); i++)
        if (released && g_ksets[i].btn && widget_clicked(g_ksets[i].btn)) {
            int was = g_kb_cap; g_kb_cap = i; g_kb_cap_armed = 0;
            if (was >= 0) kb_caption(was);
            kb_caption(i);
            return;
        }
    for (int i = 0; i < FN(g_tsets); i++) {
        tset_t *ts = &g_tsets[i];
        if (!ts->btn) continue;
        if (released && widget_clicked(ts->btn)) { *ts->cfg = !*ts->cfg; changed = 1; }
        if (g_btn_setsel) g_btn_setsel(ts->btn, *ts->cfg ? 1 : 0);
    }
    if (released && widget_clicked(g_reset_btn)) { settings_reset_defaults(); changed = 1; }
    if (changed) save_ini();   /* persist toggle/reset changes immediately */
}

static void settings_ensure_window(void *gui)
{
    if (g_settings_win || !g_gui_createwidget) return;
    unsigned char ty[32], sk[32], nm[32], lay[32];
    make_mstr(ty, "Window"); make_mstr(sk, "Kenshi_WindowCX");
    make_mstr(nm, "KFPSettingsWin"); make_mstr(lay, "Window");
    int sw, sh;
    kfp_view_size(&sw, &sh);
    /* dynamic height: fit all rows + the reset button + window chrome
     * (toggles are laid out in two columns) */
    int content_bottom = 14 + FN(g_fsets) * 30 + 10 + ((FN(g_tsets) + 1) / 2) * 30 + 10 + ((FN(g_ksets) + 1) / 2) * 30 + 8 + 32;
    int ww = 520, wh = content_bottom + 60;
    int wx = (sw > 0 ? sw / 2 - ww / 2 : 200), wy = (sh > 0 ? sh / 2 - wh / 2 : 150);
    g_settings_win = g_gui_createwidget(gui, ty, sk, wx, wy, ww, wh, 0, lay, nm);
    if (g_settings_win) {
        caption_set(g_settings_win, "KenshiFP Settings", g_window_setcap);
        settings_build_content(g_settings_win);
        g_widget_setvisible(g_settings_win, 0);
    }
    if (KFP_DEBUG_LOG) logline("[settings] window create -> %p", g_settings_win);
}

/* Post-frame (MyGUI-safe), independent of FP mode. FULLY crash-guarded: a fault
 * in any MyGUI call disables the settings UI for the session instead of taking
 * the game down, and the step logs pinpoint which call faulted. */
static void fp_settings_ui(void)
{
    if (g_settings_dead) return;
    if (!g_gui_getinstance || !g_gui_createwidget || !g_widget_createwidget
        || !g_gui_findwidget || !g_widget_setvisible
        || !g_tabctrl_itemcount || !g_tabctrl_itemat) return;
    /* let the game settle past the load screen before we touch the menu GUI */
    static int warmup; if (warmup < 120) { warmup++; return; }

    if (setjmp(g_guard_jb)) {          /* a MyGUI call blew up */
        g_guard_armed = 0;
        g_settings_dead = 1;
        logline("[settings] MyGUI FAULT -- settings UI disabled for this session");
        return;
    }
    guard_arm();

    void *gui = g_gui_getinstance();
    if (!gui) { g_guard_armed = 0; return; }

    /* Toggle the settings window with a HOTKEY (default F10). The menu-BUTTON
     * injection was abandoned: creating a widget into the game's options menu at
     * the exact frame it builds hard-crashes the game (a deferred render-time
     * crash the VEH guard can't catch -- confirmed via log: createWidgetT on the
     * mods tab the instant its item-count went 0->6). Our own top-level window is
     * safe (same as the crosshair/vignette widgets). [settings_find + the tree
     * walk are retained for a future, more careful button attempt.] */
    static int key_prev;
    int key = (GetAsyncKeyState(g_cfg_key_settings) & 0x8000) != 0;
    if (key && !key_prev) {
        settings_ensure_window(gui);
        g_settings_open = !g_settings_open;
        if (g_settings_win) g_widget_setvisible(g_settings_win, g_settings_open ? 1 : 0);
        if (!g_settings_open && g_settings_win) save_ini();  /* hotkey-close must
                                     * persist too -- only Esc/Close/X did before,
                                     * so F10-dismissed slider edits died on restart */
        if (KFP_DEBUG_LOG) logline("[settings] hotkey toggle -> %d win=%p", g_settings_open, g_settings_win);
    }
    key_prev = key;

    if (g_settings_open && g_settings_win) {
        settings_poll_content();
        /* Close on Escape, F10, the in-panel Close button, or the title-bar X.
         * The X is MyGUI's own close button -- a widget named "Button" that sits
         * (via the title-bar frame) directly under our window, distinct from our
         * content which lives under the window's "Client" sub-widget. Detect a
         * click on any "Button"-named descendant of the window. */
        static int esc_prev, lmb_prev;
        int esc = (GetAsyncKeyState(VK_ESCAPE) & 0x8000) != 0;
        int lmb = (GetAsyncKeyState(VK_LBUTTON) & 0x8000) != 0;
        int close = (esc && !esc_prev) && g_kb_cap < 0 && !g_kb_eat;
        if (lmb_prev && !lmb && g_kb_cap < 0 && !g_kb_eat) {
            if (widget_clicked(g_close_btn)) close = 1;
            void *im = g_input_getinst ? g_input_getinst() : NULL;
            void *f = (im && g_mousefocus) ? g_mousefocus(im) : NULL;
            if (f && g_widget_getname) {
                char nm[24]; read_mstring(g_widget_getname(f), nm, sizeof nm);
                if (strcmp(nm, "Button") == 0) {          /* MyGUI title-bar X */
                    void *a = f;
                    for (int i = 0; i < 12 && readable(a, 8); i++) {
                        if (a == g_settings_win) { close = 1; break; }
                        if (!g_widget_getparent) break;
                        a = g_widget_getparent(a);
                    }
                }
            }
        }
        esc_prev = esc; lmb_prev = lmb;
        if (close) {
            if (g_kb_cap >= 0) { int i = g_kb_cap; g_kb_cap = -1; kb_caption(i); }
            g_settings_open = 0;
            g_widget_setvisible(g_settings_win, 0);
            save_ini();               /* persist slider values on close */
            if (KFP_DEBUG_LOG) logline("[settings] closed");
        }
    }
    g_guard_armed = 0;
}

static void fp_gui_update(void)
{
    if (!g_gui_getinstance) return;
    fp_settings_ui();                     /* runs regardless of FP mode */
    static int prev_fp;
    if (!g_fp_mode) {                      /* FP off: keep everything hidden */
        /* UNCONDITIONAL (not edge-triggered): an edge can be missed around quit-to-
         * menu / save-load while the KO blackout is visible, leaving a fullscreen
         * black widget over the menu and the freshly loaded game ("black screen until
         * entering FP"). Hiding every frame outside FP makes stale overlays impossible;
         * four setVisible(0) calls per frame are negligible. */
        if (g_widget_setvisible) {
            if (g_crosshair) g_widget_setvisible(g_crosshair, 0);
            if (g_vignette)  g_widget_setvisible(g_vignette, 0);
            if (g_black_ov)  g_widget_setvisible(g_black_ov, 0);
            if (g_sneak_icon) g_widget_setvisible(g_sneak_icon, 0);
        }
        g_fpc_hud_hide_why = "fp_off";
        fpc_hud_update(0);
        fpc_ctl_menu_update(g_gw_cache);   /* PT20: hides the Control button outside FP */
        g_down_blend = 0.0f;   /* reset the KO fade so re-entering FP doesn't flash */
        prev_fp = 0;
        return;
    }
    prev_fp = 1;
    ensure_crosshair();                    /* create (post-frame = safe) */
    if (g_crosshair && g_widget_setpos) {  /* follow the view size (window resized / other monitor) */
        static int lw, lh;
        int vw, vh;
        kfp_view_size(&vw, &vh);
        if (vw != lw || vh != lh) {
            lw = vw; lh = vh;
            g_widget_setpos(g_crosshair, vw / 2 - CROSSHAIR_SIZE / 2, vh / 2 - CROSSHAIR_SIZE / 2);
            logline("[gui] view %dx%d: crosshair centred", vw, vh);
        }
    }

    /* crosshair tint (deferred from the setPointer hook) + visibility */
    if (g_crosshair && g_imgbox_setimage) {
        int want = (int)g_crosshair_want;
        if (want != g_crosshair_red) {
            g_crosshair_red = want;
            unsigned char tex[32];
            make_mstr(tex, want == 1 ? "xhair_red.png"
                        : want == 2 ? "xhair_ylw.png" : "crosshair.png");
            g_imgbox_setimage(g_crosshair, tex);
        }
    }
    if (g_crosshair && g_widget_setvisible)
        g_widget_setvisible(g_crosshair, (g_pointer_default && !g_ui_open) ? 1 : 0);
    /* PT01 (m67): the state flash no longer hides behind a contextual pointer (g_pointer_default=0: the native icon
     * replaces our crosshair, the label under it stays); hud_hide_why names what hid it last */
    g_fpc_hud_hide_why = !g_cfg_state_hud ? "setting" : !g_crosshair ? "no_crosshair" : g_ui_open ? "ui_open" : "none";
    fpc_hud_update(g_cfg_state_hud && g_crosshair && !g_ui_open);
    fpc_ctl_menu_update(g_gw_cache);       /* PT20: "Control" next to the native context menu on a squad mate */

    /* Screen-space sneak eye: shown only while sneaking (state set per-frame from
     * the followed character), tinted by detection at ~50% alpha, hidden in menus. */
    if (g_sneak_icon && g_widget_setvisible) {
        int sw = (int)g_sneak_want;
        /* Show whenever sneaking (even when the default cursor is up, e.g. hovering
         * something) -- NOT gated on the crosshair. Hide inside a UI panel, or if
         * the F10 "Sneak eye" toggle is off. */
        int show = sw && !g_ui_open && g_cfg_sneak_eye;
        g_widget_setvisible(g_sneak_icon, show ? 1 : 0);
        if (show) {
            /* Live X/Y offset from the F10 panel / ini, relative to the default
             * position just above the crosshair. */
            if (g_widget_setpos) {
                int scx, scy;
                kfp_view_size(&scx, &scy);
                int sw_px = SNEAK_ICON_SIZE, sh_px = SNEAK_ICON_SIZE * 27 / 38;
                int bx = scx / 2 - sw_px / 2, by = scy / 2 - sh_px - 18;   /* default pos */
                g_widget_setpos(g_sneak_icon, bx + (int)g_cfg_sneak_x, by + (int)g_cfg_sneak_y);
            }
            float r, g, b;
            if (sw == 1)      { r = 0.35f;  g = 0.6f;   b = 1.0f; }  /* unseen  -> blue         */
            else if (sw == 2) { r = 0.745f; g = 0.722f; b = 0.251f; } /* noticed -> #beb840 yellow */
            else              { r = 0.745f; g = 0.251f; b = 0.29f; } /* seen    -> #be404a red    */
            widget_colour(g_sneak_icon, r, g, b, 0.5f);
        }
    }

    /* Destreza-style unconsciousness: tunnel vignette + stepped blackout fade,
     * with a 1.7s smoothstep wake-up fade on regaining consciousness. */
    if (g_vignette && g_black_ov && g_widget_setvisible) {
        static float wake; static int prev_out;
        int out = g_is_down;
        if (prev_out && !out) wake = 1.0f;
        prev_out = out;
        float dt = (g_frame_dt > 0.0f && g_frame_dt < 0.25f) ? g_frame_dt : 0.016f;
        if (wake > 0.0f) { wake -= dt / 1.7f; if (wake < 0.0f) wake = 0.0f; }
        float wk = wake * wake * (3.0f - 2.0f * wake);
        float black = out ? g_down_blend : 0.0f;
        if (wk > black) black = wk;
        float tun = g_down_blend * 1.3f; if (tun > 1.0f) tun = 1.0f;
        if (!g_cfg_vignette) { black = 0.0f; tun = 0.0f; }
        int step = (int)(black * 10.0f); if (step > 9) step = 9;
        static int prev_step = -1;
        if (black > 0.03f && step != prev_step && g_imgbox_setimage) {
            unsigned char btex[32]; char nm[16];
            snprintf(nm, sizeof nm, "blk%d.png", step);
            make_mstr(btex, nm);
            g_imgbox_setimage(g_black_ov, btex);
            prev_step = step;
        }
        g_widget_setvisible(g_vignette, tun > 0.05f);
        g_widget_setvisible(g_black_ov, black > 0.03f);
    }
}

/* MainListener::keyPressed hook: consume the jump key's OIS keydown while the
 * FP jump owns it -- BEFORE the game's command dispatch runs, so the vanilla
 * space-pause (and its UI click SOUND, which the after-the-fact setPause
 * revert could never silence) simply never happens. OIS keycodes are DIK scan
 * codes; the configured VK is mapped per press (MapVirtualKeyA VK->VSC, space
 * 0x20 -> 0x39 = KC_SPACE, matching the game's own "pause"<-0x39 default bind
 * registration). Everything else passes through untouched; key RELEASES are
 * never filtered (mirror hygiene -- the handler clears held-key state). */
typedef char (*keypressed_t)(void *lst, void *evt);
static keypressed_t g_keypressed_orig;
static int kfp_keypress_eat(void *evt)
{
    if (g_cfg_jump && g_cfg_falling && g_fp_mode && !g_ui_open
        && readable((void *)((uintptr_t)evt + 0x10), 4)
        && (unsigned)*(int *)((uintptr_t)evt + 0x10)
           == MapVirtualKeyA((UINT)g_cfg_key_jump, 0 /* MAPVK_VK_TO_VSC */))
        return 1;   /* consumed by the FP jump: no dispatch, no pause, no sound */
    if (readable((void *)((uintptr_t)evt + 0x10), 4)
        && fpc_key_swallow((unsigned)*(int *)((uintptr_t)evt + 0x10)))
        return 1;   /* R = FP draw/holster */
    return 0;
}
static char hooked_keypressed(void *lst, void *evt)
{
    if (kfp_keypress_eat(evt)) return 1;
    return g_keypressed_orig(lst, evt);
}

/* CS05: InputHandler::keyDownEvent(this, int key) is the only producer of the vanilla command
 * queue (toggle_fps_camera = cmd 0x28 on DIK 0x27 by default). keyPressed above already drops
 * FP-bound keys, so a bound DIK arriving here came by a second path: drop it too and name the
 * caller in the log (bounded) so that path is identified. Mouse codes ((btn+1)<<12) pass. */
typedef void (*ih_keydown_t)(void *ih, int key);
static ih_keydown_t g_ih_keydown_orig;
static int fpc_mouse_key_swallow(int key);   /* kfp_controls.inc */
static void hooked_ih_keydown(void *ih, int key)
{
    if (fpc_mouse_key_swallow(key)) return;   /* PT07/PT21: FP owns the mouse commands */
    if (key > 0 && key < 0x100 && g_fp_mode && fpc_key_bound_any((unsigned)key)) {
        int owned = fpc_key_owned((unsigned)key);
        if (g_ih_leak_logs < 16) {
            ++g_ih_leak_logs;
            logline("[keys] bound DIK 0x%02X reached InputHandler::keyDownEvent past keyPressed"
                    " (caller rva 0x%llx) -> %s", key,
                    (unsigned long long)((uintptr_t)__builtin_return_address(0) - g_base),
                    owned ? "swallowed" : "passed (text focus / bind capture)");
        }
        if (owned) { ++g_ih_swallowed; fpc_key_note_swallow((unsigned)key); return; }
    }
    g_ih_keydown_orig(ih, key);
}

/* CS05 path 2: RE_Kenshi (the 1.0.65 downgrade has no toggle_fps_camera) re-adds that bind with
 * its own OIS KeyListener wrapped around the game's: it calls MainListener::keyPressed, ignores
 * the result, then maps evt.key through the InputHandler key->command map itself and calls
 * CameraClass::setFreeCameraMode -- past both hooks above. So KenshiFP sits in FRONT of whatever
 * listener the keyboard holds and eats FP-owned keys there; other keys and all releases are
 * forwarded. Object layout = MSVC KeyListener: vtable {dtor, keyPressed, keyReleased}. */
typedef char (*kfp_kl_key_t)(void *self, void *evt);
static void *g_kl_prev, *g_kl_first_prev;   /* listener wrapped now / at the first install */
static int g_kl_depth;
static void *kfp_kl_dtor(void *self, unsigned flags) { (void)flags; return self; }
static char kfp_kl_forward(void *evt, int slot)
{
    /* re-entered = a later wrapper of ours called back into us: go to the original chain */
    void *t = g_kl_depth > 1 ? g_kl_first_prev : g_kl_prev;
    if (!readable(t, 8) || !readable(*(void **)t, 3 * sizeof(void *))) return 0;
    return ((kfp_kl_key_t)(*(void ***)t)[slot])(t, evt);
}
static char kfp_kl_pressed(void *self, void *evt)
{
    char r;
    (void)self;
    ++g_kl_depth;
    if (g_kl_depth == 1 && kfp_keypress_eat(evt)) { ++g_kl_eaten; r = 1; }
    else r = kfp_kl_forward(evt, 1);
    --g_kl_depth;
    return r;
}
static char kfp_kl_released(void *self, void *evt)
{
    char r;
    (void)self;
    ++g_kl_depth;
    r = kfp_kl_forward(evt, 2);
    --g_kl_depth;
    return r;
}
static void *g_kl_vt[3] = { (void *)kfp_kl_dtor, (void *)kfp_kl_pressed, (void *)kfp_kl_released };
static struct { void **vt; } g_kl = { g_kl_vt };
static void *kfp_kl_keyboard(void)
{
    if (!g_base || !RVA_IH_KEYBOARD) return NULL;
    void *kb = *(void **)(g_base + RVA_IH_KEYBOARD);
    return readable(kb, 0x58) && readable(*(void **)kb, 0x48) ? kb : NULL;
}
static int kfp_front_listener_on(void)
{
    void *kb = kfp_kl_keyboard();
    return kb && *(void **)((uintptr_t)kb + 0x50) == (void *)&g_kl;
}
static void kfp_front_listener_tick(void)
{
    if (g_kl_installs >= 8) return;               /* someone keeps replacing it: stop, log says so */
    void *kb = kfp_kl_keyboard();
    if (!kb) return;
    void *cur = *(void **)((uintptr_t)kb + 0x50);   /* OIS::Keyboard::mListener */
    if (cur == (void *)&g_kl || !readable(cur, 8)) return;
    if (!g_kl_first_prev) g_kl_first_prev = cur;
    g_kl_prev = cur;
    ((void (*)(void *, void *))(*(void ***)kb)[8])(kb, &g_kl);   /* setEventCallback, vt+0x40 */
    ++g_kl_installs;
    char mn[MAX_PATH] = "?"; HMODULE m = NULL;
    if (GetModuleHandleExA(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS | GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT,
                           (LPCSTR)*(void **)cur, &m))
        GetModuleFileNameA(m, mn, sizeof mn);
    const char *bn = strrchr(mn, '\\');
    logline("[keys] OIS front key listener #%u installed over %s vtable (FP-bound keys never reach"
            " RE_Kenshi/vanilla key commands) -> %s", g_kl_installs, bn ? bn + 1 : mn,
            kfp_front_listener_on() ? "on" : "FAILED");
}

/* ---- JUMP input: space REBOUND to jump, pause moved to its own key --------
 * (task #20) In FP, space means jump -- so the pause the vanilla space bind
 * fires is un-toggled, and pausing lives on key_pause (default P) instead.
 * Pause is NEVER lost: outside FP the vanilla spacebar is untouched, and in FP
 * key_pause toggles through the same setPause the game uses.
 * setPause decomp: stashes/restores frameSpeedMult(+0x700) via a saved-speed
 * global, so paused == framespeed 0.0 exactly. The space swallow watches a
 * SHORT window (~0.15s) after an FP space press; if framespeed hits 0 inside
 * it, setPause(gw,0) restores the stashed speed -- the vanilla pause lives
 * under a frame and is invisible. The window is deliberately tight so it can
 * never eat a deliberate pause from key_pause or a user-rebound vanilla key
 * pressed moments after a jump. Presses with a UI open are left alone (typing
 * spaces, deliberate map-screen pausing). Space while ALREADY paused is also
 * left alone: the vanilla toggle UNpauses there, which a jump wants anyway. */
static int   g_jump_key_prev;
static int   g_pause_key_prev;
static float g_jump_swallow_t;
static void fp_jump_pause_guard(void *gw)
{
    if (!g_cfg_jump) { g_jump_fire_req = 0; return; }
    float fs = readable((void *)((uintptr_t)gw + GW_FRAMESPEED), 4)
             ? *(float *)((uintptr_t)gw + GW_FRAMESPEED) : 1.0f;
    /* FP pause toggle on its own key: the rebind's other half. Uses the same
     * setPause the vanilla bind calls, so the UI/pause state stays coherent. */
    if (g_cfg_key_pause && RVA_SET_PAUSE) {
        int pk = (GetAsyncKeyState(g_cfg_key_pause) & 0x8000) != 0;
        int pedge = pk && !g_pause_key_prev;
        g_pause_key_prev = pk;
        if (pedge && g_fp_mode && !g_ui_open) {
            if (setjmp(g_guard_jb)) { g_guard_armed = 0; }
            else {
                guard_arm();
                ((void (*)(void *, char))(g_base + RVA_SET_PAUSE))(gw, fs == 0.0f ? 0 : 1);
                g_guard_armed = 0;
                logline("[jump] FP pause toggle -> %s", fs == 0.0f ? "resume" : "paused");
            }
            g_jump_swallow_t = 0.0f;   /* a deliberate pause must not be swallowed */
            return;                    /* don't also treat this press as a jump */
        }
    }
    int jk = (GetAsyncKeyState(g_cfg_key_jump) & 0x8000) != 0;
    int jedge = jk && !g_jump_key_prev;
    g_jump_key_prev = jk;
    if (g_jump_fire_req > 0) g_jump_fire_req--;   /* expire an unconsumed press:
        * a mid-air tap must not queue a takeoff for the moment of touchdown */
    if (jedge && g_fp_mode && !g_ui_open) {
        g_jump_fire_req = 6;                      /* a few frames for the camera-hook
                                                   * driver to pick it up -- includes
                                                   * 1-2 paused frames spent waiting
                                                   * for the swallow to restore speed */
        g_jump_swallow_t = 0.15f;                 /* swallow the space-bind pause
                                                   * even when the jump can't fire
                                                   * (mid-air, cooldown): the press
                                                   * was for us. Tight window: a
                                                   * pause from ANY other key a
                                                   * beat later must survive. */
    }
    if (g_jump_swallow_t > 0.0f) {
        float dt = (g_frame_dt > 0.0f && g_frame_dt < 0.25f) ? g_frame_dt : 0.016f;
        g_jump_swallow_t -= dt;
        if (RVA_SET_PAUSE && fs == 0.0f) {
            if (setjmp(g_guard_jb)) { g_guard_armed = 0; }
            else {
                guard_arm();
                ((void (*)(void *, char))(g_base + RVA_SET_PAUSE))(gw, 0);
                g_guard_armed = 0;
                logline("[jump] swallowed vanilla spacebar pause");
            }
            g_jump_swallow_t = 0.0f;
        }
    }
}

/* PT05 (Shay 2026-10-07: a time-scale click, even 1 -> 1, ran ~10x for a moment). KenshiFP never writes the game
 * speed except setPause on its own P/space keys, so this only records the evidence: every frameSpeedMult change,
 * long frames, and the peak speed within 3 s of an LMB release (a UI click). fp_keys state: speed_*. */
static unsigned g_spd_changes, g_spd_long_frames, g_spd_clicks;
static float g_spd_peak_click = -1.0f, g_spd_last = -1.0f;

/* PT23 (Shay 2026-10-08: 0.5x -> 1x -> speed up runs ~10-100x for a moment). Cause: RE_Kenshi "UseCustomGameSpeeds"
 * (RE_Kenshi.ini GameSpeeds 0.5,1,2,5,10,...). Its OIS key hook writes GameSpeeds[idx +-1] on the speed_2/speed_3
 * key PRESS, the game's own speed_2/speed_3 handling then writes its vanilla 2x/5x while the key is held, and RE_Kenshi
 * only writes its value back on the RELEASE (2026-10-08 log: "1.00 -> 5.00" then "5.00 -> 1.00" ~150 ms later, every
 * press). Its 1x button also leaves its index where it was (0.5x -> 1x -> speed up = index 0 -> 1 = still 1x after the
 * 5x burst). Guard (before and after every frame, only with custom speeds on and RE_Kenshi's index found by code
 * bytes): while speed_2/speed_3 (controls.cfg) or LMB is held and frameSpeedMult is the vanilla 2/5 but not RE_Kenshi's
 * value, write RE_Kenshi's value; when the game sits at 1x (its 1x key/button) but RE_Kenshi's index points elsewhere,
 * move the index onto 1x so the next speed up goes to 2x. fp_keys: speed_guard speed_fixed speed_synced speed_target
 * speed_idx speed_peak_input speed_fix_run (longest run of consecutive frames the guard had to correct). */
static int g_spd_custom = -1, g_spd_n, g_spd_vk[3] = { '1', '2', '3' };
static float g_spd_list[32], g_spd_target = -1.0f, g_spd_peak_input = -1.0f;
static volatile int *g_spd_reidx;
static unsigned g_spd_fixed, g_spd_synced, g_spd_fix_run, g_spd_fix_run_max;
static FILETIME g_spd_ini_mt;
static int spd_vk_of(const char *v)
{
    while (*v == ' ' || *v == '\t') ++v;
    size_t n = strcspn(v, "\r\n \t");
    if (n == 1 && ((*v >= '0' && *v <= '9') || (*v >= 'A' && *v <= 'Z'))) return *v;
    if (n == 1 && *v >= 'a' && *v <= 'z') return *v - 32;
    if (n >= 2 && n <= 3 && (*v == 'F' || *v == 'f') && atoi(v + 1) >= 1 && atoi(v + 1) <= 12) return VK_F1 + atoi(v + 1) - 1;
    if (n == 4 && !_strnicmp(v, "NUM", 3) && v[3] >= '0' && v[3] <= '9') return VK_NUMPAD0 + v[3] - '0';
    return 0;
}
static void spd_read_ini(void)
{
    WIN32_FILE_ATTRIBUTE_DATA fa;
    if (!GetFileAttributesExA("RE_Kenshi.ini", GetFileExInfoStandard, &fa)) { g_spd_custom = 0; return; }
    if (g_spd_custom >= 0 && !CompareFileTime(&fa.ftLastWriteTime, &g_spd_ini_mt)) return;
    g_spd_ini_mt = fa.ftLastWriteTime;
    FILE *f = fopen("RE_Kenshi.ini", "rb"); if (!f) { g_spd_custom = 0; return; }
    static char buf[65536]; size_t len = fread(buf, 1, sizeof buf - 1, f); fclose(f); buf[len] = 0;
    const char *u = strstr(buf, "\"UseCustomGameSpeeds\""), *g = strstr(buf, "\"GameSpeeds\"");
    int on = 0;
    if (u && (u = strchr(u + 21, ':'))) { ++u; while (*u == ' ' || *u == '\t') ++u; on = !strncmp(u, "true", 4); }
    g_spd_n = 0;
    if (g && (g = strchr(g, '['))) {
        const char *e = strchr(g, ']'); ++g;
        while (e && g < e && g_spd_n < 32) { char *q; float v = strtof(g, &q); if (q == g) { ++g; continue; } g_spd_list[g_spd_n++] = v; g = q; }
    }
    g_spd_custom = on && g_spd_n > 0;
    f = fopen("controls.cfg", "rb");
    if (f) { char line[256]; while (fgets(line, sizeof line, f)) {
        for (int k = 0; k < 3; ++k) { char nm[16]; snprintf(nm, sizeof nm, "speed_%d=", k + 1);
            if (!strncmp(line, nm, 8)) { int vk = spd_vk_of(line + 8); if (vk) g_spd_vk[k] = vk; } } }
        fclose(f); }
    logline("[speed] RE_Kenshi custom speeds=%d n=%d first=%.2f keys speed_1/2/3=0x%x/0x%x/0x%x", g_spd_custom, g_spd_n,
            g_spd_n ? g_spd_list[0] : -1.0f, g_spd_vk[0], g_spd_vk[1], g_spd_vk[2]);
}
/* RE_Kenshi SetSpeed2/SetSpeed3 tail: mov [rip+idx],edx; mov rax,[rip+ou]; mov rcx,[rax]; movss xmm0,[r8+rdx*4];
 * movss [rcx+0x700],xmm0 (RE_Kenshi.dll RVA 0x12408 / 0x12698 -> idx 0x163040 in the 2026-09-24 build). */
static void spd_find_idx(void)
{
    static int tried; if (tried) return; tried = 1;
    HMODULE m = GetModuleHandleA("RE_Kenshi.dll"); if (!m) { logline("[speed] RE_Kenshi.dll not loaded: no speed guard"); return; }
    const unsigned char *b = (const unsigned char *)m;
    IMAGE_DOS_HEADER *dh = (IMAGE_DOS_HEADER *)m; IMAGE_NT_HEADERS64 *nh = (IMAGE_NT_HEADERS64 *)(b + dh->e_lfanew);
    IMAGE_SECTION_HEADER *sh = IMAGE_FIRST_SECTION(nh); unsigned hits = 0; uintptr_t first = 0; int ok = 1;
    static const unsigned char tail[] = { 0x48,0x8b,0x08,0xf3,0x41,0x0f,0x10,0x04,0x90,0xf3,0x0f,0x11,0x81,0x00,0x07,0x00,0x00 };
    for (unsigned si = 0; si < nh->FileHeader.NumberOfSections; ++si) {
        if (!(sh[si].Characteristics & IMAGE_SCN_MEM_EXECUTE)) continue;
        const unsigned char *t = b + sh[si].VirtualAddress; size_t sz = sh[si].Misc.VirtualSize;
        for (size_t i = 0; i + 30 < sz; ++i) {
            if (!(((uintptr_t)(t + i)) & 0xFFF) && !readable(t + i, 0x1000)) { i += 0xFFF; continue; }
            if (t[i] != 0x89 || t[i + 1] != 0x15 || t[i + 6] != 0x48 || t[i + 7] != 0x8b || t[i + 8] != 0x05) continue;
            if (memcmp(t + i + 13, tail, sizeof tail)) continue;
            uintptr_t a = (uintptr_t)(t + i + 6) + *(const int32_t *)(t + i + 2);
            if (!first) first = a; else if (a != first) ok = 0;
            ++hits;
        }
    }
    if (hits && ok && readable((void *)first, 4)) g_spd_reidx = (volatile int *)first;
    logline("[speed] RE_Kenshi speed index: %s (pattern hits=%u agree=%d rva=0x%llx idx=%d)", g_spd_reidx ? "found" : "NOT found",
            hits, ok, first ? (unsigned long long)(first - (uintptr_t)m) : 0ull, g_spd_reidx ? *g_spd_reidx : -1);
}
static void fp_speed_guard(void *gw, int post)
{
    static DWORD last_ini; static unsigned logs; static int fixed_prev;
    DWORD now = GetTickCount();
    if (g_spd_custom < 0 || now - last_ini > 2000) { last_ini = now; spd_read_ini(); spd_find_idx(); }
    if (g_spd_custom != 1 || !g_spd_reidx) return;
    float *pfs = (float *)((uintptr_t)gw + GW_FRAMESPEED); if (!readable(pfs, 4)) return;
    int idx = *g_spd_reidx; if (idx < 0) idx = 0; if (idx >= g_spd_n) idx = g_spd_n - 1;
    float fs = *pfs, tgt = g_spd_list[idx]; g_spd_target = tgt;
    int k2 = (GetAsyncKeyState(g_spd_vk[1]) & 0x8000) != 0, k3 = (GetAsyncKeyState(g_spd_vk[2]) & 0x8000) != 0;
    int l = (GetAsyncKeyState(VK_LBUTTON) & 0x8000) != 0, fixed = 0;
    if (fs > 0.0f && fs != tgt && ((fs == 2.0f && (k2 || l)) || (fs == 5.0f && (k3 || l)))) {
        *pfs = tgt; ++g_spd_fixed; fixed = 1;
        if (logs < 200) { ++logs; logline("[speed] guard: vanilla x%.2f while %s held -> RE_Kenshi x%.2f (idx %d, %s frame)",
                                           fs, k3 ? "speed_3" : k2 ? "speed_2" : "LMB", tgt, idx, post ? "after" : "before"); }
    } else if (post && fs == 1.0f && tgt != 1.0f && !k2 && !k3) {
        for (int i = 0; i < g_spd_n; ++i) if (g_spd_list[i] == 1.0f) {
            *g_spd_reidx = i; ++g_spd_synced; g_spd_target = 1.0f;
            if (logs < 200) { ++logs; logline("[speed] guard: game at x1 (1x key/button), RE_Kenshi index %d (x%.2f) -> %d (x1)", idx, tgt, i); }
            break; }
    }
    if (post) { if (fixed) { if (fixed_prev) ++g_spd_fix_run; else g_spd_fix_run = 1;
                             if (g_spd_fix_run > g_spd_fix_run_max) g_spd_fix_run_max = g_spd_fix_run; }
                fixed_prev = fixed; }
}
static void fp_speed_watch(void *gw, float time)
{
    static int lmbp, keyp; static DWORD lmb_up; static unsigned logs;
    float fs = readable((void *)((uintptr_t)gw + GW_FRAMESPEED), 4) ? *(float *)((uintptr_t)gw + GW_FRAMESPEED) : -1.0f;
    int l = (GetAsyncKeyState(VK_LBUTTON) & 0x8000) != 0;
    int ky = ((GetAsyncKeyState(g_spd_vk[0]) | GetAsyncKeyState(g_spd_vk[1]) | GetAsyncKeyState(g_spd_vk[2])) & 0x8000) != 0;
    if (lmbp && !l) { lmb_up = GetTickCount(); ++g_spd_clicks; g_spd_peak_click = fs; }
    if ((lmbp && !l) || (!keyp && ky)) g_spd_peak_input = fs;
    if (ky || l || (lmb_up && GetTickCount() - lmb_up < 3000)) { if (fs > g_spd_peak_input) g_spd_peak_input = fs; }
    lmbp = l; keyp = ky;
    DWORD since = lmb_up ? GetTickCount() - lmb_up : 0xFFFFFFFFu;
    if (since < 3000 && fs > g_spd_peak_click) g_spd_peak_click = fs;
    if (fs != g_spd_last) {
        ++g_spd_changes;
        if (logs < 400) { ++logs; logline("[speed] frameSpeedMult %.2f -> %.2f (frame %.3f s, %lu ms after LMB up)",
                                          g_spd_last, fs, time, (unsigned long)since); }
        g_spd_last = fs;
    }
    if (time > 0.25f) {
        ++g_spd_long_frames;
        if (logs < 400) { ++logs; logline("[speed] long frame %.3f s at x%.2f (%lu ms after LMB up)", time, fs, (unsigned long)since); }
    }
}
static void hooked_mainloop(void *gw, float time)
{
    InterlockedIncrement(&g_heartbeat);   /* watchdog: proves the hook is live */
    g_gw_cache = gw;               /* CameraClass::update fires inside the frame */
    g_frame_dt = time;             /* stutter diag */
    if (gw) fp_speed_guard(gw, 0);      /* PT23: RE_Kenshi custom speed vs vanilla held-key speed */
    g_mainloop_orig(gw, time);     /* run the game's frame first */
    if (gw) fp_speed_guard(gw, 1);
    if (gw) fp_speed_watch(gw, time);   /* PT05 evidence */

    poll_input();                  /* every frame: catch toggle edges */
    if (gw) fp_control_tick(gw);   /* pin control independently from inspected selection */
    fp_view_input();               /* wheel zoom never changes direct-control owner */
    if (gw) fp_jump_pause_guard(gw); /* every frame: space -> jump + pause swallow */
    if (gw) camera_lock(gw);       /* every frame: assert/release the lock */
    /* Camera now runs mid-frame via the CameraClass::update hook (consistent
     * camera for shadows/LOD/foliage/render); this is only a fallback if that
     * hook failed to install. */
    if (gw && !g_cam_update_orig) fp_camera_override(gw);
    if (gw) fp_movement(gw, time); /* every frame: WASD -> custom motion drive */
    if (gw) fp_controls_tick(gw, time);      /* MMB select / RMB menu+block / LMB attack / R draw */
    if (gw) fp_manual_combat_tick(gw, time); /* own native actions after movement */
    if (gw) fp_combat_tick(gw, time); /* independent passive trace */
    if (gw) fp_load_nearby_interiors(gw); /* ~1 Hz: preload nearby building interiors */
    if (gw) fp_sync_floor(gw);            /* reveal the character's building floor in FP */
    if (gw) fp_head_visibility(gw);       /* hide head while fast-forwarding (>1x) */
    fp_gui_update();                      /* post-frame: all MyGUI widget work */

    DWORD now = GetTickCount();
    if (KFP_DEBUG_LOG && gw && (now - g_last_tick_ms) >= 1000) {   /* 1 Hz observation log */
        g_last_tick_ms = now;
        fp_tick(gw);
    }

    ini_hot_reload();             /* apply KenshiFP.ini edits without restart */
    fps_cap_wait();               /* optional user-configured frame limiter */
}

/* Hook re-arm watchdog. Other mods that hook the game late (notably RE_Kenshi,
 * whose KenshiLib installs many detours during game-data init) can leave our
 * per-frame hook installed-but-not-firing. This thread watches the heartbeat:
 * if it isn't advancing, it re-installs the per-frame hook so we land on top of
 * whatever the other mod did. RE_Kenshi does NOT hook mainLoop itself, so
 * remove+recreate here restores the true original bytes -- it won't disturb
 * its hooks. Once the heartbeat flows, the watchdog goes quiet. */
static DWORD WINAPI hook_watchdog(void *unused)
{
    (void)unused;
    LONG last_main = 0, last_cam = 0;
    int rearms = 0, main_ok = 0, cam_ok = 0;
    for (;;) {
        Sleep(2000);
        LONG hm = g_heartbeat, hc = g_cam_heartbeat;
        int main_flow = (hm != last_main), cam_flow = (hc != last_cam);
        last_main = hm; last_cam = hc;
        if (main_flow && !main_ok) { main_ok = 1; logline("watchdog: per-frame hook LIVE"); }
        if (cam_flow && !cam_ok)   { cam_ok = 1;  logline("watchdog: camera-update hook LIVE"); }
        if (main_flow) continue;                 /* healthy */
        /* Per-frame hook not firing. DIAGNOSTIC ONLY -- do NOT re-arm: a
         * non-firing hook never starts firing on re-install (wrong address or
         * diverted call), and re-arming churned MinHook state for no gain.
         * Report a few times, then stay quiet. */
        if (rearms < 3) {
            rearms++;
            logline("watchdog: mainloop SILENT (main hb=%ld cam hb=%ld) -- cam %s",
                    (long)hm, (long)hc, cam_flow ? "FIRING" : "silent");
        }
    }
}

/* NOTE: no WH_MOUSE_LL / WH_KEYBOARD_LL global hooks anymore. The FP toggle and
 * mouse wheel are polled on the DirectInput thread instead (di_poll_thread) --
 * a background thread running a global keyboard hook trips antivirus keylogger
 * heuristics, and passive GetAsyncKeyState / DirectInput reads do not. */

/* Install one hook through the active backend. Returns 1 on success.
 * KenshiLib.AddHook does create+enable in one call (SUCCESS==0). */
/* The FP aim point: 80m along the camera look direction from the head, in game
 * coords. Shared by the ranged free-aim hooks. Returns 0 if unavailable. */
static int fp_aim_point(Vec3 *out)
{
    if (!g_fp_control_actor || !g_get_bone_world) return 0;
    Vec3 head;
    g_get_bone_world(g_fp_control_actor, &head, g_head_bone);       /* game coords */
    float cp = cosf(g_pitch);
    out->x = head.x + sinf(g_yaw) * cp * 80.0f;
    out->y = head.y - sinf(g_pitch)     * 80.0f;
    out->z = head.z + cosf(g_yaw) * cp * 80.0f;
    return 1;
}

/* Ranged free-aim: RangedCombatClass::animationUpdate(this, frameTime, aimpos&,
 * target) is fed the auto-target's position each frame; for the PLAYER in FP
 * mode we substitute the point the camera is looking at, so the arm pose
 * follows the crosshair. Non-player characters pass through. */
static int fp_combat_own_animupd(void *rc);   /* kfp_combat_native.inc */
static void hooked_ranged_animupd(void *rc, float ft, Vec3 *aimpos, void *target)
{
    if (fp_combat_own_animupd(rc)) return;   /* manual ranged adapter drives this actor's aim anim */
    fp_combat_probe_animation(rc, target);
    Vec3 aim;
    if (g_fp_mode && g_cfg_freeaim && rc
        && readable((void *)((uintptr_t)rc + RC_ME), 8)
        && *(void **)((uintptr_t)rc + RC_ME) == g_fp_control_actor
        && readable(aimpos, sizeof(Vec3))
        && fp_aim_point(&aim)) {
        /* Pass the crosshair point as OUR OWN vector. aimpos is a const reference to
         * a local in the caller's stack frame (logged 0x10deff700 next to rc/me) and
         * the caller keeps using it after this call: writing the game-coordinate
         * crosshair point through it moved the camera centre by exactly that point
         * (the "[weld] world-scale centre jump tx-54127 tz+6879" = aim x/z), the world
         * rebased on it, and ~4 s later the NavMesh thread crashed in Havok A*
         * (garbage instance face map; m50 5090 K/M/N, 4080 b42). Repro
         * tests/ingame/fp-navcrash-repro.sh: write-through crashed on the first try
         * of every launch, the local copy ran clean. */
        if (readable((void *)((uintptr_t)rc + RC_AIMPOS), sizeof(Vec3)))
            *(Vec3 *)((uintptr_t)rc + RC_AIMPOS) = aim;
        static int logged;
        if (!logged) { logged = 1; logline("[freeaim] pose override LIVE (own aim vector)"); }
        if (g_aim_mode) {                     /* R-aim diagnostics: is this even called? */
            static int cnt;
            if ((++cnt % 120) == 1) logline("[aim] animationUpdate running (call %d)", cnt);
        }
        g_ranged_animupd_orig(rc, ft, &aim, target);
        return;
    }
    g_ranged_animupd_orig(rc, ft, aimpos, target);
}

/* GunClass::shoot(this, me, target, stat, aimpos&) -- the projectile spawn.
 * Direction = getAimDir(aimpos) + skill-based randomDeviant, so overriding
 * aimpos here makes the bolt fly at the crosshair while target attribution
 * and the accuracy spread stay vanilla. */
typedef void (*gun_shoot_t)(void *gun, void *me, void *target, int stat, const Vec3 *aimpos);
static gun_shoot_t g_gun_shoot_orig;
static void hooked_gun_shoot(void *gun, void *me, void *target, int stat, const Vec3 *aimpos)
{
    if (fp_combat_suppress_shot(gun,me)) return;
    if (me && me == g_fp_control_actor) ++g_fp_ctl_shoot_calls;
    Vec3 aim;
    if (g_fp_mode && g_cfg_freeaim && !g_aim_mode && me && me == g_fp_control_actor && !(g_tur_pc && me == g_tur_pc) && fp_aim_point(&aim)) {   /* T4: the turret module aims its own shots */
        aimpos = &aim;
        static int logged;
        if (!logged) { logged = 1; logline("[freeaim] projectile override LIVE"); }
    }
    if (stat==11) fp_turret_shot_diag(gun,me,target,stat,aimpos,"shoot");   /* T4: native vs FP turret shot */
    fp_combat_probe_shot(gun, me, target, stat, KFP_EV_SHOT_BEFORE);
    g_gun_shoot_orig(gun, me, target, stat, aimpos);
    fp_combat_probe_shot(gun, me, target, stat, KFP_EV_SHOT_AFTER);
}

/* CharMovement::faceDirection hook: while the player is in RANGED combat mode
 * in FP, the combat AI's auto-face (toward its target, during aim/reload) is
 * redirected to the camera look direction -- the body tracks the crosshair and
 * orient-to-control stays in charge. Melee and everyone else pass through. */
typedef void (*face_dir_t)(void *mv, const Vec3 *dir);
static face_dir_t g_face_dir_orig;
static void hooked_face_direction(void *mv, const Vec3 *dir)
{
    if (g_fp_mode && g_fp_control_actor
        && readable((void *)((uintptr_t)g_fp_control_actor + CHAR_MOVEMENT), 8)
        && *(void **)((uintptr_t)g_fp_control_actor + CHAR_MOVEMENT) == mv) {
        if (g_cfg_freeaim) {
            void *rc = readable((void *)((uintptr_t)g_fp_control_actor + CHAR_RANGEDCOMBAT), 8)
                ? *(void **)((uintptr_t)g_fp_control_actor + CHAR_RANGEDCOMBAT) : NULL;
            if (readable((void *)((uintptr_t)rc + RC_COMBATMODE), 1)
                && *(unsigned char *)((uintptr_t)rc + RC_COMBATMODE)) {
                Vec3 look = { sinf(g_yaw), 0.0f, cosf(g_yaw) };
                static int logged;
                if (!logged) { logged = 1; logline("[freeaim] facing override LIVE"); }
                g_face_dir_orig(mv, &look);
                return;
            }
        }
        /* True-FP facing lock: EVERY engine facing request for the player (incl.
         * MOVE_DIRECTION's internal turn-toward-motion each update) is redirected to
         * the commanded body yaw from the TIP state machine -- this is what makes
         * strafe/backpedal movement possible: the engine cannot turn the body toward
         * the travel direction because its own facing entry point now points at us. */
        if (g_loco_ready && g_cfg_loco_facelock && g_face_have) {
            Vec3 look = { sinf(g_face_yaw), 0.0f, cosf(g_face_yaw) };
            static int logged2;
            if (!logged2) { logged2 = 1; logline("[loco] facing lock LIVE (faceDirection redirected)"); }
            g_face_dir_orig(mv, &look);
            return;
        }
    }
    g_face_dir_orig(mv, dir);
}

/* Manual ranged trigger: on a left-click edge (FP, cursor captured, weapon
 * drawn, gun loaded) call GunClass::shoot directly at the crosshair point.
 * target=NULL is explicitly handled by shoot (verified in decomp); ammo,
 * visibility, and tracer bookkeeping all run inside the game's own code. */
/* Bug 100: FP has no right-click menu, so a carried NPC could not be put
 * down. G (edge, FP, cursor captured, Kenshi focused) calls the game's own
 * Character::dropCarriedObject(ragdoll, removeOnly) under the crash guard. */
#define KLIB_DROPCARRIED_SYM "?dropCarriedObject@Character@@QEAAX_N0@Z"
typedef void (*chr_dropcarried_t)(void *, unsigned char, unsigned char);
static void fp_putdown_update(void *pcx)
{
    static int prev, dead;
    static chr_dropcarried_t fn;
    int k = (GetAsyncKeyState('G') & 0x8000) != 0;
    int injected = InterlockedExchange(&g_kah_inject_putdown, 0) != 0; /* harness fp_putdown */
    int edge = (k && !prev) || injected;
    prev = k;
    if (!edge || dead || !g_fp_mode || g_ui_open || !pcx) return;
    if (!injected && (!g_cursor_hidden || !game_has_focus())) return;
    if (!fn) {
        HMODULE kl = GetModuleHandleA("KenshiLib.dll");
        if (kl) fn = (chr_dropcarried_t)GetProcAddress(kl, KLIB_DROPCARRIED_SYM);
        if (!fn) { dead = 1; logline("[fp] put down: export missing -- disabled"); return; }
    }
    if (setjmp(g_guard_jb)) { g_guard_armed = 0; dead = 1; logline("[fp] put down FAULTED -- disabled"); return; }
    guard_arm();
    fn(pcx, 1, 0);
    g_guard_armed = 0;
    logline("[fp] put down: dropCarriedObject called (bug 100)");
}

static void manual_fire_update(void *pcx)
{
    static int lmb_prev;
    int lmb = (GetAsyncKeyState(VK_LBUTTON) & 0x8000) != 0;
    int edge = lmb && !lmb_prev;
    lmb_prev = lmb;
    if (!edge || !g_fp_mode || g_ui_open || !pcx || !g_gun_shoot_orig) return;
    void *wih = readable((void *)((uintptr_t)pcx + CHAR_WEAPON_IN_HANDS), 8)
        ? *(void **)((uintptr_t)pcx + CHAR_WEAPON_IN_HANDS) : NULL;
    if (!wih) return;                            /* nothing drawn */
    void *rc = readable((void *)((uintptr_t)pcx + CHAR_RANGEDCOMBAT), 8)
        ? *(void **)((uintptr_t)pcx + CHAR_RANGEDCOMBAT) : NULL;
    void *gun = (rc && readable((void *)((uintptr_t)rc + RC_GUN), 8))
        ? *(void **)((uintptr_t)rc + RC_GUN) : NULL;
    if (!gun || !readable((void *)((uintptr_t)gun + GUN_AMMO), 4)) return;
    int ammo = *(int *)((uintptr_t)gun + GUN_AMMO);
    if (ammo <= 0) { logline("[fire] click: gun empty/reloading (ammo=%d)", ammo); return; }
    int stat = readable((void *)((uintptr_t)rc + RC_STAT), 4)
        ? *(int *)((uintptr_t)rc + RC_STAT) : 0;
    Vec3 aim;
    if (!fp_aim_point(&aim)) return;
    if (setjmp(g_guard_jb)) { g_guard_armed = 0; logline("[fire] shoot FAULTED"); return; }
    guard_arm();
    g_gun_shoot_orig(gun, pcx, NULL, stat, &aim);
    g_guard_armed = 0;
    logline("[fire] manual shot (ammo %d -> %d)", ammo, ammo - 1);
}

/* sheatheWeapon suppressor: while manual aim (R) is on, the idle AI re-sheathes
 * our drawn weapon within ~20ms (the draw/sheathe flicker). Swallow the call
 * for the player during aim mode; everyone else (and normal play) unaffected. */
typedef void (*sheathe_t)(void *pc);
static sheathe_t g_sheathe_orig;
static void hooked_sheathe(void *pc)
{
    /* PT18 (m69): our own R sheathe passes; aim + R holsters */
    if (g_aim_mode && pc && pc == g_fp_control_actor && !g_fpc_own_sheathe) {
        static int cnt;
        if ((++cnt % 60) == 1) logline("[aim] suppressed AI sheathe (x%d)", cnt);
        return;
    }
    if (fpc_suppress_sheathe(pc)) return;   /* R-drawn weapon stays out (not fighting) */
    g_sheathe_orig(pc);
}

#include "kfp_combat_native.inc"
#include "kfp_melee_observe.inc"
#include "kfp_combat_melee.inc"
#include "kfp_controls.inc"
#include "kfp_turret.inc"

/* CharMovement::update hook: re-assert the player's direct-drive intent
 * IMMEDIATELY BEFORE the engine consumes movement state -- combat AI (and the
 * order system) rewrite movementMode inside/around this update, and applying
 * here means our write is always the last one standing. WASD therefore works
 * in combat: the fight's locomotion suggestions lose the race every frame. */
typedef void (*charmove_update_t)(void *mv, float t);
static charmove_update_t g_charmove_update_orig;
#define MV_ANIMOVERRIDE 0x37C           /* CharMovement::animationOverride (bool) */
#define CHAR_VISNEAR   0x1A8            /* Character::isVisibleAndNear */
#define CHAR_ONSCREEN  0x1A9            /* Character::isOnScreen */

/* Force MOVE_DIRECTION + our WASD motion onto the player's CharMovement. Called
 * both BEFORE and AFTER the original update: the original re-enables combat
 * locomotion (animationOverride + movementMode) INSIDE itself when the char is
 * combat-engaged, so a pre-override write alone loses the race every frame (log
 * showed movementMode flickering 2->1->0). Re-asserting after the original is
 * what makes WASD beat combat -- exactly what Kenshi-Direct-Control does. */
static void mv_force_direct(void *mv)
{
    if (readable((void *)((uintptr_t)mv + MV_ANIMOVERRIDE), 1))
        *(unsigned char *)((uintptr_t)mv + MV_ANIMOVERRIDE) = 0;
    if (readable((void *)((uintptr_t)mv + MV_SPEEDORDERS), 4))
        *(int *)((uintptr_t)mv + MV_SPEEDORDERS) = g_dm_speed;
    if (readable((void *)((uintptr_t)mv + MV_MOVEMODE), 4))
        *(int *)((uintptr_t)mv + MV_MOVEMODE) = 2;              /* MOVE_DIRECTION */
    ((void (*)(void *, const Vec3 *, float))(g_base + RVA_SET_DIRECT_MOVE))(mv, &g_dm_dir, 99.0f);
}

static void hooked_charmove_update(void *mv, float t)
{
    int drive = (g_dm_active && mv == g_dm_mv);
    if (KFP_DEBUG_LOG && g_fp_mode && mv == g_dm_mv) {
        static int el;
        if ((++el % 30) == 0) {
            int mode = readable((void *)((uintptr_t)mv + MV_MOVEMODE), 4)
                       ? *(int *)((uintptr_t)mv + MV_MOVEMODE) : -1;   /* mode combat left */
            logline("[enf] dm_active=%ld mode(pre-override)=%d dir=(%.2f,%.2f)",
                    g_dm_active, mode, g_dm_dir.x, g_dm_dir.z);
        }
    }
    /* C05-KO: never force standing direct drive into a KO/crippled/down actor. */
    void *dpc = (drive && readable((void *)((uintptr_t)mv + MV_CHARACTER), 8))
        ? *(void **)((uintptr_t)mv + MV_CHARACTER) : NULL;
    int dko = dpc && fp_body_down(dpc);   /* KO flag / ragdoll bits lead the prone state */
    if (drive && !fp_drive_gate(mv, 1, dpc ? char_prone_state(dpc) : PS_NORMAL, dko,
                                MV_MOVEMODE, MV_DESIREDMOTION, MV_CURRENT_MOTION)) {
        drive = 0;
        static int kol; if (kol++ < 8) logline("[control] direct drive stood down: actor down (prone=%d is_down=%d)",
                                               dpc ? char_prone_state(dpc) : -1, g_is_down);
    }
    if (drive) {
        /* Halt clears any combat chase motion the AI queued, then force our
         * direction. (halt = CharMovement vtable +0x98.) */
        void **vt = *(void ***)mv;
        if (in_module(vt)) ((void (*)(void *))vt[MV_HALT_SLOT])(mv);
        mv_force_direct(mv);
    } else fp_melee_hold_ground(mv);   /* manual melee: no AI combat locomotion while the player isn't driving (M06) */
    /* FP camera weld depends on a LIVE skeleton, but Kenshi culls animation
     * for characters it deems off-screen -- and in FP the camera sits inside
     * the head, so looking level/up culls your own body and freezes the head
     * bone (camera detaches). Force the visibility flags for the FP character
     * right before its update, every frame. */
    if (g_fp_mode && g_fp_control_actor
        && readable((void *)((uintptr_t)mv + MV_CHARACTER), 8)
        && *(void **)((uintptr_t)mv + MV_CHARACTER) == g_fp_control_actor
        && readable((void *)((uintptr_t)g_fp_control_actor + CHAR_VISNEAR), 2)) {
        *(unsigned char *)((uintptr_t)g_fp_control_actor + CHAR_VISNEAR)  = 1;
        *(unsigned char *)((uintptr_t)g_fp_control_actor + CHAR_ONSCREEN) = 1;
    }
    /* FALL LAUNCH HOLD: while a ragdoll-fall request is queued, keep the launch
     * velocity parked in currentMotion(+0xA8) across the WHOLE frame -- we're
     * stalled at the lip, so the engine recomputes it to ~zero, and setRagdoll
     * copies +0xA8 into the ragdoll whenever the queue pump applies (before OR
     * after this update). Without this the body crumples in place on the ledge
     * instead of diving off it. Small +y so the body arcs clear of the lip. */
#define FALL_LAUNCH_HOLD(mvp) \
    if (g_fall_rd == FALLRD_QUEUED && g_fp_control_actor \
        && readable((void *)((uintptr_t)(mvp) + MV_CHARACTER), 8) \
        && *(void **)((uintptr_t)(mvp) + MV_CHARACTER) == g_fp_control_actor \
        && readable((void *)((uintptr_t)(mvp) + MV_CURRENT_MOTION), 12)) { \
        Vec3 *cmh = (Vec3 *)((uintptr_t)(mvp) + MV_CURRENT_MOTION); \
        cmh->x = g_fall_hx; cmh->y = g_fall_launch_y; cmh->z = g_fall_hz; \
        if (readable((void *)((uintptr_t)(mvp) + MV_CURRENT_SPEED), 4)) \
            *(float *)((uintptr_t)(mvp) + MV_CURRENT_SPEED) = \
                sqrtf(g_fall_hx * g_fall_hx + g_fall_hz * g_fall_hz); \
    }
    FALL_LAUNCH_HOLD(mv)
    g_charmove_update_orig(mv, t);
    FALL_LAUNCH_HOLD(mv)
    if (drive && dpc && !dko && fp_body_down(dpc)) {   /* C05-KO trace: the KO landed inside this update */
        static int kil;
        if (kil++ < 8 && readable((void *)((uintptr_t)mv + MV_CURRENT_MOTION), 12)) {
            Vec3 cmk = *(Vec3 *)((uintptr_t)mv + MV_CURRENT_MOTION);
            logline("[down] KO inside CharMovement::update: cm=%.2f,%.2f,%.2f mask=0x%x prone=%d (post gate clears)",
                    cmk.x, cmk.y, cmk.z, fall_ragdoll_mask(dpc), char_prone_state(dpc));
        }
    }
    /* Re-assert AFTER: the original just re-enabled combat locomotion mid-call.
     * This post-write is the one that actually wins the race -- unless the actor
     * went down INSIDE the update (C05-KO): then clear instead of forcing. */
    if (drive && fp_drive_gate(mv, 1, dpc ? char_prone_state(dpc) : PS_NORMAL,
                               dpc && fp_body_down(dpc),
                               MV_MOVEMODE, MV_DESIREDMOTION, MV_CURRENT_MOTION))
        mv_force_direct(mv);
    /* facing lock: the original update turned the body toward the motion direction by
     * feeding facing(+0xD0)=velocity-dir to AnimationClass::setPositionAndDirection --
     * NOT via faceDirection (which is why redirecting that never worked). Re-feed the
     * same call with the CAMERA direction; last feed wins, so WASD strafes/backpedals
     * while the body faces the camera. Armed independently of `drive` so the MOMENTUM
     * GLIDE after key release stays camera-faced too (the auto-face otherwise turns
     * the sliding body toward the residual velocity). */
    /* WALK-OFF FALL (task #19 v4). Keeps the character ON THEIR FEET through a
     * real gravity arc:
     *  - position state is OURS (g_fall_pos): the engine teleport GROUND-CLAMPS
     *    (a mid-air teleport snaps straight to the floor below -- the "no
     *    gravity, instant drop" bug) and mv+0xC4 re-syncs from the mover each
     *    tick, so neither can hold a mid-air point;
     *  - the arc is rendered via ANIM_SETPOSDIR after the engine update (last
     *    feed wins, same as the facing lock), animations keep playing, the head
     *    bone carries the camera;
     *  - ONE teleport at the landing point commits character + mover (clamping
     *    there is exactly right); NO ragdoll, NO get-up;
     *  - past fall_air seconds airborne, escalate to the full ragdoll with the
     *    current fall velocity ("ragdoll strength grows with fall time"). */
    if (g_fall_active && g_fp_control_actor && combat_char_unconscious(g_fp_control_actor)) {
        g_fall_active = 0;   /* C05-KO: a KO mid-arc hands the body to the native ragdoll */
        fp_down_note("fall arc", g_fp_control_actor);
    }
    if (g_fall_active && RVA_CHAR_SETDEST && RVA_GROUND_AT && g_fp_control_actor
        && readable((void *)((uintptr_t)mv + MV_CHARACTER), 8)
        && *(void **)((uintptr_t)mv + MV_CHARACTER) == g_fp_control_actor
        && readable((void *)((uintptr_t)mv + MV_ANIMATION), 8)
        && readable((void *)((uintptr_t)mv + 0xC4), 12)) {
        float fdt = (g_frame_dt > 0.0f && g_frame_dt < 0.25f) ? g_frame_dt : 0.016f;
        if (fdt > 0.05f) fdt = 0.05f;                       /* clamp hitches */
        g_fall_t  += fdt;
        g_fall_vy -= g_cfg_fall_gravity * fdt;
        if (g_fall_vy < -g_cfg_fall_maxvel) g_fall_vy = -g_cfg_fall_maxvel;
        /* air drag on the horizontal carry -- but only AFTER the first stretch
         * of the arc: the launch must push you CLEAR of the ledge face first
         * (immediate drag dropped you straight down the wall and you landed
         * stuck against the thing you fell off). No wall collision, so still
         * bleed it off before long. */
        if (g_fall_t > 0.6f) {
            float drag = expf(-1.5f * fdt);
            g_fall_hx *= drag; g_fall_hz *= drag;
        }
        Vec3 np = g_fall_pos;
        np.x += g_fall_hx * fdt;
        np.z += g_fall_hz * fdt;
        np.y += g_fall_vy * fdt;
        /* ---- ARC COLLISION (task #21): the arc used to fly through walls,
         * rocks and whole buildings -- nothing lateral was ever queried. The
         * engine's general raycast (RVA_RAYCAST -- the SAME collision world
         * the ground query reads, so building shells/interiors/props are all
         * in it) sweeps the horizontal motion at shin+chest height each tick;
         * on a block, an axis-decomposed slide keeps whichever axis is free
         * (graze a wall -> slide along it; head-on -> stop and drop). While
         * rising, an up-ray bonks vy to 0 under a ceiling/overhang. */
        if (RVA_RAYCAST) {
            float bh = (g_head_above > 4.0f && g_head_above < 40.0f)
                     ? g_head_above : 16.0f;              /* body height, live-measured */
            float mdx = np.x - g_fall_pos.x, mdz = np.z - g_fall_pos.z;
            float mlen = sqrtf(mdx * mdx + mdz * mdz);
            if (mlen > 1e-5f) {
                Vec3 dirh = { mdx / mlen, 0.0f, mdz / mlen };
                float reach = mlen + 2.5f;                /* + capsule-radius margin
                    * (1.2 was ~13cm at this scale: the ray origin could end up
                    * INSIDE a convex hull before the sweep tripped, and interior
                    * rays see nothing -- the residual phase-through) */
                {   /* [rdbg] approach telemetry, mask A/B: distance to the nearest
                     * chest-height hit along the motion under OUR mask vs an
                     * everything-mask -- separates "shape not in 0x88204" from
                     * "sweep logic" at the exact moment of a phase-through */
                    static float swdbg;
                    swdbg += fdt;
                    if (KFP_DEBUG_LOG && swdbg > 0.2f) {
                        swdbg = 0.0f;
                        Vec3 fromc = { g_fall_pos.x, g_fall_pos.y + bh * 0.5f, g_fall_pos.z };
                        Vec3 h1, h2;
                        float d1 = -1.0f, d2 = -1.0f;
                        if (fall_ray(&fromc, &dirh, &h1)) {
                            float ax = h1.x - fromc.x, az = h1.z - fromc.z;
                            d1 = sqrtf(ax*ax + az*az);
                        }
                        if (fall_ray_m(&fromc, &dirh, &h2, 0xffffffffu)) {
                            float ax = h2.x - fromc.x, az = h2.z - fromc.z;
                            d2 = sqrtf(ax*ax + az*az);
                        }
                        if (d1 < 40.0f || (d2 >= 0.0f && d2 < 40.0f))
                            logline("[rdbg] sweep d88=%.1f dALL=%.1f mlen=%.2f", d1, d2, mlen);
                        /* [rdbg] channel probe: a NEAR obstacle that only the wide
                         * mask sees -- cast every single bit and report which ones
                         * carry it, so the sweep mask can be made precise */
                        if (d2 >= 0.0f && d2 < 12.0f && (d1 < 0.0f || d1 > d2 + 4.0f)) {
                            unsigned nb = 0;
                            for (int b = 0; b < 32; b++) {
                                Vec3 hb;
                                if (fall_ray_m(&fromc, &dirh, &hb, 1u << b)) {
                                    float bx2 = hb.x - fromc.x, bz2 = hb.z - fromc.z;
                                    if (bx2*bx2 + bz2*bz2 < (d2 + 2.0f) * (d2 + 2.0f))
                                        nb |= 1u << b;
                                }
                            }
                            logline("[rdbg] nearbits=0x%08x at d=%.1f", nb, d2);
                        }
                    }
                }
                float wd = -1.0f;
                int wb = fall_sweep_blocked(&g_fall_pos, &dirh, reach, bh, &wd);
                if (wb) {
                    Vec3 dx1 = { mdx >= 0 ? 1.0f : -1.0f, 0.0f, 0.0f };
                    Vec3 dz1 = { 0.0f, 0.0f, mdz >= 0 ? 1.0f : -1.0f };
                    int bx = fabsf(mdx) < 1e-5f
                          || fall_sweep_blocked(&g_fall_pos, &dx1, fabsf(mdx) + 2.5f, bh, NULL);
                    int bz = fabsf(mdz) < 1e-5f
                          || fall_sweep_blocked(&g_fall_pos, &dz1, fabsf(mdz) + 2.5f, bh, NULL);
                    if (bx) { np.x = g_fall_pos.x; g_fall_hx = 0.0f; }
                    if (bz) { np.z = g_fall_pos.z; g_fall_hz = 0.0f; }
                    if (bx && bz) { g_fall_hx = g_fall_hz = 0.0f; }
                    /* log EVERY block, capped per arc. The old 0.5s-of-blocked-
                     * frames accumulator was why NO wall hit was ever logged:
                     * a block zeroes the motion, mlen drops to 0, and the sweep
                     * stops evaluating -- one silent frame per jump. We were
                     * debugging the block path completely blind. */
                    static int wlog; static float wlog_t;
                    if (g_fall_t < wlog_t) wlog = 0;       /* new arc -> reset cap */
                    wlog_t = g_fall_t;
                    if (wlog < 6) { wlog++;
                        logline("[fall] wall hit h%d d=%.2f (bx=%d bz=%d) -> %s",
                                wb, wd, bx, bz, (bx && bz) ? "stop" : "slide"); }
                }
            }
            if (g_fall_vy > 0.0f) {                       /* ceiling bonk */
                /* Ray from the FEET, demanding full body-height clearance: the
                 * old head-height origin sat ABOVE a low overhang's underside,
                 * so the interior ray saw nothing and the head passed through
                 * BOTTOM faces (the "top and bottom faces" report). */
                Vec3 up = { 0.0f, 1.0f, 0.0f };
                Vec3 fromc = { g_fall_pos.x, g_fall_pos.y + 0.5f, g_fall_pos.z };
                Vec3 hitc;
                if (fall_ray_m(&fromc, &up, &hitc, 0xfffffffeu)) {
                    float clr = hitc.y - fromc.y;
                    /* GENUINE overhead only: above the chest but too low for
                     * the head after this tick's rise. Hits BELOW chest are
                     * the slope surface around an embedded takeoff (on any
                     * uphill the feet sit under the local terrain read, and
                     * the up-ray hits the slope from beneath at ~0 range) --
                     * clamping on those buried the arc a body-height under
                     * the ground ("most jumps phase through the ground"). */
                    if (clr > bh * 0.55f && clr < bh + g_fall_vy * fdt + 0.3f) {
                        float maxy = hitc.y - bh - 0.3f;
                        if (np.y > maxy && maxy > g_fall_pos.y - 1.0f)
                            np.y = maxy;                 /* stop the RISE only --
                                * the clamp must never pull the arc downward */
                        g_fall_vy = 0.0f;
                        logline("[fall] ceiling bonk under y=%.1f (clr %.1f)",
                                hitc.y, clr);
                    }
                }
            }
        }
        /* ground under the new point. The ray must cover the WHOLE segment
         * swept this tick, so its origin sits just above the PRE-STEP feet
         * (old y + 0.8), not the new point: at terminal velocity a tick moves
         * 3+ units -- more than any fixed lift -- and a ray from the new point
         * starts UNDER a surface crossed mid-step and no-hits (02:01 log:
         * y stepped 1570.6 -> 1567.7 across gnd=1569.8, both rays went blind,
         * fell 575 units through the world). Surfaces inside the sweep are
         * floors we genuinely crossed, so reading them is exactly right; the
         * origin still hugs the old feet (+0.8) so a next-storey ceiling slab
         * above the head stays invisible (the old wrong-floor bug). The +1.2
         * extra ray remains as a fallback for steep-terrain crossings where
         * even the swept origin starts underground. */
        float nohit = RVA_GROUND_NOHIT ? *(float *)(g_base + RVA_GROUND_NOHIT) : 0.0f;
        float lift2 = (g_fall_pos.y - np.y) + 0.8f;
        if (lift2 < 0.8f) lift2 = 0.8f;
        Vec3 gpl = { np.x, np.y + lift2, np.z };
        float gnd = fall_ground(&gpl);
        if (gnd == nohit) {
            Vec3 gp = { np.x, np.y + lift2 + 1.2f, np.z };
            gnd = fall_ground(&gp);
        }
        /* LANDING SURFACES COME FROM THE ENGINE GROUND QUERY ONLY. A wide-mask
         * landing was tried and CORRUPTED the world state (21:53 log): landing
         * teleport-commits the character, and committing onto a surface the
         * engine does not consider standable (rock tops, prop shapes) leaves
         * the mover resolved under/inside the mesh -- every later ground query
         * then starts underground and the next arc free-falls through the
         * world for 13+ seconds. Wide mask is for BLOCKING only (sweep +
         * ceiling); rocks block horizontally but their tops are not landable. */
        /* SLOPE ANTICIPATION (engine-ground only): on a steep face the center
         * down-ray reads ~radius*tan(slope) BELOW the capsule's contact point
         * (the "dip into the landscape" report). Probe one capsule radius
         * AHEAD along the motion; a higher near-foot ENGINE-ground reading
         * lands us at the face instead of inside it. */
        {
            float hl2 = g_fall_hx * g_fall_hx + g_fall_hz * g_fall_hz;
            if (hl2 > 1e-6f) {
                float hl = sqrtf(hl2);
                Vec3 ap = { np.x + g_fall_hx / hl * 2.5f, np.y + lift2,
                            np.z + g_fall_hz / hl * 2.5f };
                float ga = fall_ground(&ap);
                if (ga != nohit && ga <= np.y + 2.0f    /* near-foot only: a wall
                        * top far above must not read as landable ground */
                    && (gnd == nohit || ga > gnd))
                    gnd = ga;
            }
        }
        /* TERRAIN-WALL / RAY-BLIND HORIZONTAL VETO -- the actual stop for the
         * unwalkable-slope dip-through: on steep faces the capsule rides up to
         * ~14 units ABOVE the ray surface, so one tick of uphill motion put
         * the arc BELOW the next column's surface -- instantly blind to every
         * ray (sweeps read -1 from inside the mesh; 22:01 log). Veto the
         * horizontal advance when the moved-to column's engine ground reads
         * ABOVE the feet (moved into a hillside) or reads NOTHING while the
         * previous column was readable (entered a mesh volume); fall straight
         * down the readable column instead. Gap jumps are unaffected: over a
         * void the ray still reads the floor far below (valid, lower). */
        if ((gnd != nohit && gnd > np.y + 2.5f)
            || (gnd == nohit && g_fall_gnd_ok)) {
            np.x = g_fall_pos.x; np.z = g_fall_pos.z;
            g_fall_hx = 0.0f; g_fall_hz = 0.0f;
            Vec3 gr = { np.x, np.y + lift2, np.z };
            gnd = fall_ground(&gr);
            if (gnd == nohit) {
                Vec3 gr2 = { np.x, np.y + lift2 + 1.2f, np.z };
                gnd = fall_ground(&gr2);
            }
            static float vetodbg;
            vetodbg += fdt;
            if (vetodbg > 0.5f) {
                vetodbg = 0.0f;
                logline("[fall] hillside veto (gnd=%.1f y=%.1f) -> vertical",
                        gnd == nohit ? -9999.0f : gnd, np.y);
            }
        }
        g_fall_gnd_ok = (gnd != nohit);
        /* TUNNEL ABORT: an arc that has fallen far with NO readable ground
         * below has almost certainly slipped inside collision (legit falls
         * read the floor beneath them the whole way down) -- return to the
         * takeoff point instead of free-falling through the world. */
        if (gnd == nohit && g_fall_t > 0.6f && g_fall_y0 - np.y > 80.0f) {
            Vec3 back = { g_fall_startx, g_fall_y0 + 0.5f, g_fall_startz };
            float q[4] = { g_fall_qw, 0.0f, g_fall_qy, 0.0f };
            g_char_setdest(g_fp_control_actor, &back, q);
            fall_restore_mover(g_fp_control_actor);
            g_fall_active = 0; g_fall_jump = 0; g_fall_perched = 0; g_fall_cd_t = 0.5f;
            g_have_last_feet = 0; g_move_speed = 0.0f; g_have_prevraw = 0;
            g_rebase_hold_t = 1.0f; g_loco_reassert_t = 0.7f;
            logline("[fall] TUNNEL ABORT after %.1f units of no-ground -- returned to takeoff",
                    g_fall_y0 - np.y);
            g_guard_armed = 0;
            return;
        }
        /* Landing doesn't count while we're still horizontally over the START
         * ledge (ground under us ~= start height) -- the first arc frames would
         * otherwise "land" instantly at the lip and inchworm off the edge. Past
         * a short grace, same-height ground is a real landing (gap hops). */
        /* ROCK-TOP REST & SLIDE (the "top faces" phase): the descent crossing a
         * wide-mask surface that sits ABOVE the engine ground = a mesh top the
         * engine won't let anyone stand on (landing-committing there corrupts
         * the mover -- proven regression). The arc RESTS on it kinematically
         * (no commit) and slides toward the lowest neighboring point until the
         * column below is engine ground again -- you slide off the boulder and
         * land on real ground. Airtime re-arms while resting so surfing a top
         * never banks fall_air KO time. */
        if (RVA_RAYCAST && g_fall_vy <= 0.0f) {
            Vec3 dnw = { 0.0f, -1.0f, 0.0f }, hw;
            Vec3 fromw = { np.x, g_fall_pos.y + 0.8f, np.z };
            if (fall_ray_m(&fromw, &dnw, &hw, 0xfffffffeu)
                && hw.y <= fromw.y
                && (gnd == nohit || hw.y > gnd + 1.2f)   /* above engine ground --
                    * threshold ABOVE the wide-vs-engine terrain disagreement on
                    * slopes, so walkable hillsides never read as "mesh tops" */
                && np.y <= hw.y + 0.3f) {
                /* TRUE-GEOMETRY refinement (task #22): the hull top floats
                 * above the visible rock -- re-cast this column against the
                 * entity's actual .mesh triangles and stand on THAT surface.
                 * Cosmetic-only path: any fault permanently disables it. */
                if (g_mr_ready && !g_mr_dead && g_have_t) {
                    if (setjmp(g_guard_jb)) { g_guard_armed = 0; g_mr_dead = 1;
                        logline("[cmesh] refine FAULTED -- true-mesh queries disabled"); }
                    else {
                        guard_arm();
                        Vec3 dn2 = { 0.0f, -1.0f, 0.0f }, tru;
                        Vec3 from2 = { np.x, g_fall_pos.y + 2.0f, np.z };
                        if (meshray_refine(&from2, &dn2, 40.0f, &tru)
                            && tru.y < hw.y + 0.5f && tru.y > hw.y - 8.0f) {
                            static int cd2;
                            if (cd2 < 12) { cd2++;
                                logline("[cmesh] hull=%.2f true=%.2f (gap %.2f)",
                                        hw.y, tru.y, hw.y - tru.y); }
                            hw.y = tru.y;
                        }
                        g_guard_armed = 0;
                    }
                }
                {   /* SMOOTHED rest height: the refine occasionally misses a
                     * tick (scene-query blink) and the raw hull top is 1-3u
                     * above the true surface -- without smoothing the body
                     * POPPED between the two ("blendspace stutters"). Clamp
                     * the per-tick change while the perch persists. */
                    float resty = hw.y + 0.3f;
                    if (g_fall_perched) {
                        float dyp = resty - g_fall_perch_y;
                        if (dyp > 0.4f)       resty = g_fall_perch_y + 0.4f;
                        else if (dyp < -0.4f) resty = g_fall_perch_y - 0.4f;
                    }
                    np.y = resty; g_fall_perch_y = resty;
                }
                g_fall_perch_grace = 0.15f;
                g_fall_vy = 0.0f;
                g_fall_t  = 0.2f;
                g_fall_jump = 1;   /* step-off landings use the descending grace */
                /* steepness scan, MEASURED slope only: a missing neighbor probe
                 * means "edge nearby", which is NOT a reason to slide (standing
                 * 2 units from a rock edge is fine; walking off is the detect's
                 * job) -- the old miss=downhill rule flapped PERCHED<->slide
                 * every tick on narrow rocks and near edges, overwriting the
                 * walk velocity with slide velocity in bursts (the stutter). */
                float best = hw.y;
                float sx = 0.0f, sz = 0.0f;
                for (int nb = 0; nb < 4; nb++) {
                    Vec3 npb = { np.x + (nb == 0 ? 2.0f : nb == 1 ? -2.0f : 0.0f),
                                 g_fall_pos.y + 0.8f,
                                 np.z + (nb == 2 ? 2.0f : nb == 3 ? -2.0f : 0.0f) };
                    Vec3 hn;
                    if (!fall_ray_m(&npb, &dnw, &hn, 0xfffffffeu) || hn.y > npb.y)
                        continue;                        /* miss = edge, treat flat */
                    /* a neighbor at TERRAIN level is a walkable step-down, not
                     * a cliff: LOW meshes (slabs/mounds ~2u tall) read "steep"
                     * against the ground beside them and slid forever, never
                     * perching -- airborne loco while walking = the stutter.
                     * Steep = a big drop while STILL ON the mesh, or a huge
                     * drop onto anything. */
                    int on_mesh = (gnd == nohit) || (hn.y > gnd + 1.2f);
                    float ndrop = hw.y - hn.y;
                    if (!((on_mesh && ndrop > 1.6f) || ndrop > 4.0f)) continue;
                    if (hn.y < best) { best = hn.y; sx = npb.x - np.x; sz = npb.z - np.z; }
                }
                /* switch hysteresis: only a SUSTAINED steep reading sheds an
                 * established perch (single-tick classifier flips are visible
                 * as animation stutter) */
                static int steepticks;
                int steepnow = (hw.y - best > 1.6f) && !(sx == 0.0f && sz == 0.0f);
                steepticks = steepnow ? steepticks + 1 : 0;
                if (steepnow && (!g_fall_perched || steepticks >= 4)) {
                    /* STEEP top: shed off toward the low side (can't stand here) */
                    float sl = sqrtf(sx * sx + sz * sz);
                    g_fall_hx = sx / sl * 8.0f;
                    g_fall_hz = sz / sl * 8.0f;
                    g_fall_perched = 0;
                } else {
                    /* PERCHED: this surface is standable -- WASD walks it
                     * kinematically (sweeps still block walls), releasing keys
                     * stands still, walking off an edge resumes the fall, and
                     * fp_fall_update allows a re-jump from here. */
                    g_fall_perched = 1;
                    int pw = (GetAsyncKeyState(g_cfg_key_w) & 0x8000) != 0;
                    int pa = (GetAsyncKeyState(g_cfg_key_a) & 0x8000) != 0;
                    int ps = (GetAsyncKeyState(g_cfg_key_s) & 0x8000) != 0;
                    int pd = (GetAsyncKeyState(g_cfg_key_d) & 0x8000) != 0;
                    int pmf = pw - ps, pms = pd - pa;
                    if (pmf || pms) {
                        float ph = g_yaw + atan2f(-(float)pms, (float)pmf);
                        int spr = g_cfg_key_sprint
                               && (GetAsyncKeyState(g_cfg_key_sprint) & 0x8000);
                        float pspd = (spr ? 60.0f : 38.0f) * g_speed_scale;
                        /* same tiers as ground movement -- the fixed 14 made
                         * mesh-top travel feel half speed */
                        g_fall_hx = sinf(ph) * pspd;
                        g_fall_hz = cosf(ph) * pspd;
                    } else { g_fall_hx = 0.0f; g_fall_hz = 0.0f; }
                }
                static int restdbg;
                if (restdbg < 10) { restdbg++;
                    logline("[fall] mesh top y=%.1f (gnd %.1f) -> %s",
                            hw.y, gnd == nohit ? -9999.0f : gnd,
                            g_fall_perched ? "PERCHED" : "sliding"); }
            } else if (g_fall_perched) {
                /* HYSTERESIS: a single missed detect tick used to drop the
                 * perch for one frame -- g_loco_in_air flipped, the air tuck
                 * flickered, TIP locks reset (the stutter report). Hold the
                 * perch briefly; only a sustained miss is a real step-off. */
                g_fall_perch_grace -= fdt;
                if (g_fall_perch_grace > 0.0f) {
                    np.y = g_fall_perch_y;
                    g_fall_vy = 0.0f;
                    g_fall_t  = 0.2f;
                } else
                    g_fall_perched = 0;   /* stepped off: normal fall resumes */
            }
        }
        int landed = 0;
        if (gnd != nohit && np.y <= gnd && g_fall_pos.y >= gnd - 1.2f
            && (gnd < g_fall_y0 - 0.5f || g_fall_t > 0.5f
                || (g_fall_jump && g_fall_vy < 0.0f)))   /* a flat hop lands back on
                    * START-height ground while descending -- the lip grace (which
                    * exists to stop inchworm landings AT the lip) must not hold a
                    * finished jump in the air */
            { np.y = gnd; landed = 1; }
        if (np.y < g_fall_y0 - 4000.0f) landed = 1;         /* runaway guard */
        g_fall_pos = np;
        if (landed) {
            float q[4] = { g_fall_qw, 0.0f, g_fall_qy, 0.0f };   /* Ogre w,x,y,z */
            g_char_setdest(g_fp_control_actor, &np, q);                 /* commit char + mover */
            fall_restore_mover(g_fp_control_actor);   /* if the teleport left the mover torn down,
                                                * CharMovement::update early-returns and the
                                                * character freezes in place -- rebuild NOW */
            g_fall_active = 0; g_fall_perched = 0;
            g_fall_trace_t = 1.0f;                           /* [ftrc] post-landing diag */
            g_have_last_feet = 0; g_move_speed = 0.0f; g_have_prevraw = 0; g_rebase_hold_t = 1.0f;       /* landing jump: don't let the
                                                              * eye-lead tracker sample it */
            /* "Ragdoll strength grows with the fall", applied AT the landing and
             * judged by IMPACT VELOCITY (airtime broke when gravity changed): a
             * soft landing stays on the feet -- with a knee-bend absorb dip
             * scaled by the impact (Destreza landing port, loco layer) -- while
             * a hard one crumples into the KO ragdoll AT THE IMPACT POINT with
             * the impact velocity (the hold macro feeds it in), so the tumble,
             * fall damage and wake-up all happen where you actually hit. */
            float impact = -g_fall_vy;
            /* a jump self-funds ~2*vel/g of airtime BEFORE any drop begins --
             * don't bill that against the fall_air KO budget, or hopping off a
             * porch crumples where walking off it wouldn't. Impact-velocity KO
             * stays as-is (physics-true either way). */
            float jair = g_fall_jump ? (2.0f * g_cfg_jump_vel / g_cfg_fall_gravity) : 0.0f;
            if ((impact > g_cfg_fall_ko || g_fall_t > g_cfg_fall_air + jair)
                && (RVA_SET_UNCON || RVA_RAGDOLL_QUEUED)) {
                /* lie-down time scales with overshoot past the KO threshold */
                float over = (impact - g_cfg_fall_ko) / 80.0f;
                if (over < 0.0f) over = 0.0f;
                if (over > 1.0f) over = 1.0f;
                g_fall_settle_goal = g_cfg_fall_settle * (0.12f + 0.55f * over);
                g_fall_launch_y = g_fall_vy;
                if (RVA_SET_UNCON)
                    ((void (*)(void *, char))(g_base + RVA_SET_UNCON))(g_fp_control_actor, 1);
                else
                    ((void (*)(void *, char, int))(g_base + RVA_RAGDOLL_QUEUED))(g_fp_control_actor, 1, 1);
                g_fall_rd = FALLRD_QUEUED; g_fall_rd_t = 0.0f; g_fall_rd_landed = 1;
                logline("[fall] hard landing after %.1f units (%.2fs, vy=%.1f, state=%d) -> crumple (KO)",
                        g_fall_y0 - np.y, g_fall_t, g_fall_vy,
                        readable((void *)((uintptr_t)g_fp_control_actor + 0x2F8), 4)
                            ? *(int *)((uintptr_t)g_fp_control_actor + 0x2F8) : -1);
            } else {
                /* soft landing: knee-bend absorb scaled by impact (loco layer
                 * dips the pelvis; leg IK plants the feet; camera dips) */
                float amt = (impact - 18.0f) / 60.0f;
                if (amt < 0.0f) amt = 0.0f;
                if (amt > 1.0f) amt = 1.0f;
                if (amt > g_land_amt) { g_land_amt = amt; g_land_age = 0.0f; }
                logline("[fall] stepped down %.1f units on foot (%.2fs, impact=%.0f absorb=%.2f)",
                        g_fall_y0 - np.y, g_fall_t, impact, amt);
                g_fall_cd_t = g_fall_jump ? 0.05f : 0.8f;    /* re-arm delay: jumps
                    * re-arm essentially instantly (Counter-Strike has no landing
                    * lockout -- 0.05s is one debounce frame); edge falls keep the
                    * longer guard against inchworm re-fires at the lip */
                /* HAND-BACK GAP: fp_movement re-arms the drive only on the NEXT
                 * mainloop pass -- on THIS tick (and until then) the orig update's
                 * combat auto-face wins and the body snaps toward whoever is
                 * targeting you for a frame ("jump while fleeing = brief turn to
                 * fight"). g_face_dir still holds our facing (set at fire and fed
                 * all arc long), so re-arming the facing lock HERE lets the
                 * post-orig re-feed win every frame of the gap. */
                if (g_fp_mode) InterlockedExchange(&g_face_active, 1);
                g_loco_reassert_t = 0.7f; /* the teleport's render update re-registers
                                           * the game's anim layers -- hold the re-claim */
            }
            g_fall_jump = 0;              /* arc finished (either branch) */
        } else {
            /* airborne: fly the rendered body along the arc; keep +0xC4 in sync
             * so position readers (camera weld, feet tracker) see the fall too */
            /* [fdbg] arc trace, EVERY call (jitter diagnosis): the logline
             * timestamp gives the wall-clock cadence of this hook; edt is the
             * dt the ENGINE passed to CharMovement::update, fdt the mainloop
             * frame dt we integrate with. Uneven timestamps, or edt far from
             * fdt, means the arc advances at a different cadence than the
             * camera samples -- the descent stutter. */
            if (KFP_DEBUG_LOG)
            logline("[fdbg] arc t=%.2f y=%.2f gnd=%.2f vy=%.1f edt=%.4f fdt=%.4f",
                    g_fall_t, np.y, gnd == nohit ? -9999.0f : gnd, g_fall_vy,
                    t, fdt);
            /* landing anticipation for the loco layer (pre-plant / squash blend):
             * 0 -> 1 across the last 0.25s of the descent, 0 when rising or the
             * ground is unreadable */
            if (gnd != nohit && g_fall_vy < -1.0f) {
                float tti = (np.y - gnd) / -g_fall_vy;
                g_fall_airland = tti < 0.25f ? 1.0f - tti / 0.25f : 0.0f;
                if (g_fall_airland > 1.0f) g_fall_airland = 1.0f;
            } else g_fall_airland = 0.0f;
            /* MID-AIR BODY TURN: FP controllers rotate the body with the camera
             * in flight. Glue the facing to the camera yaw each tick (same as
             * the facelock's moving mode) and keep every consumer in sync: the
             * arc render feed (g_face_dir), the landing teleport quat (qw/qy),
             * the loco body yaw (g_face_yaw -> blendspace/aim/tuck frame), and
             * the landing hand-back (re-arms g_face_active on g_face_dir). */
            if (g_fp_mode) {
                if (g_fall_perched) {
                    /* PACED facing while standing on a mesh (fp_movement's TIP
                     * pacing, which stands down during arcs): the hard camera
                     * glue left the loco TIP counter-rotation with a residual
                     * twist when the turn stopped ("TIP stuck"). Same consts
                     * as the ground path: start past tip_start_deg, step at
                     * tip_turn_deg/s, disengage under ~1.7deg. */
                    float fdev = loco_wrap_pi(g_yaw - g_face_yaw);
                    float startA = g_cfg_tip_start_deg * 0.0174533f;
                    if (!g_face_turning && fabsf(fdev) > startA) g_face_turning = 1;
                    if (g_face_turning) {
                        float fcap = g_cfg_tip_turn_deg * 0.0174533f * fdt;
                        float stepv = fdev < -fcap ? -fcap : fdev > fcap ? fcap : fdev;
                        g_face_yaw = loco_wrap_pi(g_face_yaw + stepv);
                        if (fabsf(loco_wrap_pi(g_yaw - g_face_yaw)) < 0.03f)
                            g_face_turning = 0;
                    }
                    g_face_have = 1;
                } else {
                    g_face_yaw = g_yaw; g_face_have = 1; g_face_turning = 0;
                }
                g_face_dir.x = sinf(g_face_yaw); g_face_dir.y = 0.0f;
                g_face_dir.z = cosf(g_face_yaw);
                g_fall_qw = cosf(g_face_yaw * 0.5f);
                g_fall_qy = sinf(g_face_yaw * 0.5f);
            }
            *(Vec3 *)((uintptr_t)mv + 0xC4) = np;
            void *anim = *(void **)((uintptr_t)mv + MV_ANIMATION);
            if (readable(anim, 8) && RVA_ANIM_SETPOSDIR)
                ((void (*)(void *, const Vec3 *, const Vec3 *))(g_base + RVA_ANIM_SETPOSDIR))
                    (anim, &np, &g_face_dir);
        }
    }
    /* [ftrc] post-landing freeze diagnosis: is the mover alive and consuming
     * velocity? (mover null -> update early-returns -> frozen in place while
     * the animation keeps playing -- the "stuck after landing" symptom) */
    if (g_fall_trace_t > 0.0f && g_fp_control_actor
        && readable((void *)((uintptr_t)mv + MV_CHARACTER), 8)
        && *(void **)((uintptr_t)mv + MV_CHARACTER) == g_fp_control_actor
        && readable((void *)((uintptr_t)mv + 0xC4), 12)
        && readable((void *)((uintptr_t)mv + MV_CURRENT_MOTION), 12)) {
        float fdt2 = (g_frame_dt > 0.0f && g_frame_dt < 0.25f) ? g_frame_dt : 0.016f;
        g_fall_trace_t -= fdt2;
        static float ftacc; ftacc += fdt2;
        if (ftacc >= 0.1f) {
            ftacc = 0.0f;
            void *mover = readable((void *)((uintptr_t)mv + MV_MOVER), 8)
                ? *(void **)((uintptr_t)mv + MV_MOVER) : NULL;
            Vec3 *tp = (Vec3 *)((uintptr_t)mv + 0xC4);
            Vec3 *tc = (Vec3 *)((uintptr_t)mv + MV_CURRENT_MOTION);
            int tmode = readable((void *)((uintptr_t)mv + MV_MOVEMODE), 4)
                ? *(int *)((uintptr_t)mv + MV_MOVEMODE) : -1;
            int tso = readable((void *)((uintptr_t)mv + MV_SPEEDORDERS), 4)
                ? *(int *)((uintptr_t)mv + MV_SPEEDORDERS) : -1;
            int tkey = (g_cfg_key_sprint && (GetAsyncKeyState(g_cfg_key_sprint) & 0x8000)) ? 1 : 0;
            logline("[ftrc] mover=%p mode=%d pos=(%.1f,%.1f) cm=(%.1f,%.1f) spd=%.1f dm=%ld so=%d dmspd=%d scale=%.2f sk=%d",
                    mover, tmode, tp->x, tp->z, tc->x, tc->z,
                    readable((void *)((uintptr_t)mv + MV_CURRENT_SPEED), 4)
                        ? *(float *)((uintptr_t)mv + MV_CURRENT_SPEED) : -1.0f,
                    g_dm_active, tso, g_dm_speed, g_speed_scale, tkey);
        }
    }
    int face_down = g_face_active && g_fp_control_actor
        && readable((void *)((uintptr_t)mv + MV_CHARACTER), 8)
        && *(void **)((uintptr_t)mv + MV_CHARACTER) == g_fp_control_actor
        && fp_body_down(g_fp_control_actor);
    if (face_down) fp_down_note("facing setPositionAndDirection", g_fp_control_actor);
    if (g_face_active && !face_down && RVA_ANIM_SETPOSDIR && g_fp_control_actor
        && readable((void *)((uintptr_t)mv + MV_CHARACTER), 8)
        && *(void **)((uintptr_t)mv + MV_CHARACTER) == g_fp_control_actor
        && readable((void *)((uintptr_t)mv + MV_ANIMATION), 8)) {
        void *anim = *(void **)((uintptr_t)mv + MV_ANIMATION);
        if (readable(anim, 8) && readable((void *)((uintptr_t)mv + 0xC4), 12)) {
            if (readable((void *)((uintptr_t)mv + 0xD0), 12))   /* facing field too */
                *(Vec3 *)((uintptr_t)mv + 0xD0) = g_face_dir;
            ((void (*)(void *, const Vec3 *, const Vec3 *))(g_base + RVA_ANIM_SETPOSDIR))
                (anim, (const Vec3 *)((uintptr_t)mv + 0xC4), &g_face_dir);
        }
    }
}

#ifdef KFP_RE_PLUGIN
/* KenshiLib::AddHook(void* target, void* detour, void** original) -> HookStatus
 * (SUCCESS=0). Resolved by name from KenshiLib.dll at load (RE_Kenshi's dep). */
typedef int (*klib_addhook_t)(void *target, void *detour, void **original);
static klib_addhook_t g_klib_addhook;
#define KLIB_ADDHOOK_SYM "?AddHook@KenshiLib@@YA?AW4HookStatus@1@PEAX0PEAPEAX@Z"
#endif

static int install_hook(void *target, void *detour, void **original)
{
#ifdef KFP_RE_PLUGIN
    /* RE edition: hook through KenshiLib::AddHook -- RE_Kenshi's own hooking
     * service does the code patching inside KenshiLib.dll, so OUR binary carries
     * no inline-hook/trampoline machinery (which AV heuristics flag as an
     * injector). This is the way the RE_Kenshi author recommended. NO MinHook is
     * mixed in here (mixing backends is what crashed our earlier attempt), and
     * the addresses are the same signature-resolved targets we already validate.
     * HookStatus::SUCCESS == 0. */
    return g_klib_addhook && g_klib_addhook(target, detour, original) == 0;
#else
    /* Standalone edition: no KenshiLib available, so MinHook does the hooking. */
    if (MH_CreateHook(target, detour, original) != MH_OK) return 0;
    return MH_EnableHook(target) == MH_OK;
#endif
}

__declspec(dllexport) void dllStartPlugin(void)
{
    g_log = fopen("KenshiFP.log", "w");
    g_base = (uintptr_t)GetModuleHandleA(NULL);

    /* Select the address table by the mainLoop prologue signature. Steam 1.0.68
     * is the base target; RE_Kenshi downgrades to Steam 1.0.65 (its bundled exe),
     * so match both builds. Neither -> unsupported, disable. MUST run before any
     * RVA_* use (they now read the active table g_rva). */
#ifdef KFP_RE_PLUGIN
    /* Resolve g_rva. PREFER the built-in RVA tables, selected by a DIRECT
     * prologue check at the known MAINLOOP RVA (exactly what the standalone
     * does). base+RVA addressing is immune to the two failure modes that made
     * the pure signature scan disable KenshiFP on most users' RE_Kenshi setups:
     *   - false matches: kfp_sig returns the FIRST hit of a non-unique pattern,
     *     so a mainloop scan could land on the wrong function (seen: 0x7877a0
     *     instead of the real 0x787e70), and
     *   - misses: a co-loaded plugin's hook (or a scan-region quirk) leaves a
     *     pattern unmatched -> address 0 -> "core resolution FAILED".
     * The RE_Kenshi bundled exe is Steam 1.0.65; a direct install is 1.0.68.
     * Fall back to the signature scan ONLY for a build whose prologue we don't
     * recognise (e.g. an unknown GOG variant) -- no worse than before there. */
    {
        /* (0) PE-header fingerprint -- SizeOfImage + TimeDateStamp live in the
         * image header, which NO runtime code hook can touch. This identifies
         * the exact build even when other RE_Kenshi plugins have hooked (and so
         * clobbered) the very functions we would otherwise scan for -- including
         * mainLoop itself. Logged every launch so any unknown build self-reports
         * from a user's log and can be added here in one line. Known builds:
         *   Steam 1.0.68 (direct):        SizeOfImage 0x232d000, stamp 0x6602d59d
         *   Steam 1.0.65 (RE_Kenshi down): SizeOfImage 0x232c000, stamp 0x65d604d7 */
        unsigned long img = 0, tstamp = 0, entry = 0;
        {
            IMAGE_DOS_HEADER *dos = (IMAGE_DOS_HEADER *)g_base;
            if (readable(dos, sizeof *dos) && dos->e_magic == IMAGE_DOS_SIGNATURE) {
                IMAGE_NT_HEADERS *nt = (IMAGE_NT_HEADERS *)(g_base + dos->e_lfanew);
                if (readable(nt, sizeof *nt) && nt->Signature == IMAGE_NT_SIGNATURE) {
                    img    = (unsigned long)nt->OptionalHeader.SizeOfImage;
                    tstamp = (unsigned long)nt->FileHeader.TimeDateStamp;
                    entry  = (unsigned long)nt->OptionalHeader.AddressOfEntryPoint;
                }
            }
        }
        logline("exe fingerprint: SizeOfImage=0x%lx TimeDateStamp=0x%lx entry=0x%lx",
                img, tstamp, entry);

        static const unsigned char SIG_MAINLOOP[8] =
            { 0x48,0x8b,0xc4,0x56,0x57,0x41,0x54,0x48 };
        unsigned char *p68 = (unsigned char *)(g_base + T_1068.MAINLOOP);
        unsigned char *p65 = (unsigned char *)(g_base + T_1065.MAINLOOP);
        if (tstamp == 0x6602d59d || img == 0x232d000) {
            g_rva = T_1068; g_build = 68;
            logline("RE plugin: build 1.0.68 by PE fingerprint (hook-immune)");
        } else if (tstamp == 0x6602d5e3) {
            /* MUST precede the 1.0.65 branch: GOG 1.0.68's SizeOfImage is also
             * 0x232c000, so the img fallback there would misdetect it. */
            g_rva = T_GOG68; g_build = 68; g_gog = 1;
            logline("RE plugin: build GOG 1.0.68 by PE fingerprint (hook-immune)");
        } else if (tstamp == 0x65d604d7 || img == 0x232c000) {
            g_rva = T_1065; g_build = 65;
            logline("RE plugin: build 1.0.65 (RE_Kenshi downgrade) by PE fingerprint (hook-immune)");
        } else if (tstamp == 0x65d60519 || img == 0x232a000) {
            g_rva = T_GOG65; g_build = 65; g_gog = 1;
            logline("RE plugin: build GOG 1.0.65 (RE_Kenshi GOG downgrade) by PE fingerprint (hook-immune)");
        } else if (readable(p68, 8) && memcmp(p68, SIG_MAINLOOP, 8) == 0) {
            g_rva = T_1068; g_build = 68;
            logline("RE plugin: build 1.0.68 by mainLoop prologue");
        } else if (readable(p65, 8) && memcmp(p65, SIG_MAINLOOP, 8) == 0) {
            g_rva = T_1065; g_build = 65;
            logline("RE plugin: build 1.0.65 (RE_Kenshi downgrade) by mainLoop prologue");
        } else {
            /* Unrecognised build -> version-independent signature scan. */
            int r = kfp_resolve_all(g_base);
            int total = (int)(sizeof(KFP_RTAB) / sizeof(KFP_RTAB[0]));
            g_build = 0;                   /* not a fixed build */
            logline("RE plugin: unrecognised build, resolved %d/%d addresses by signature (base %p)",
                    r, total, (void *)g_base);
            if (!g_rva.MAINLOOP || !g_rva.CAM_INSTANCE || !g_rva.CAM_UPDATE) {
                g_wrong_build = 1;         /* core resolution failed -> disable */
                logline("*** core address resolution FAILED (mainloop=%p cam=%p camupd=%p)",
                        (void *)g_rva.MAINLOOP, (void *)g_rva.CAM_INSTANCE, (void *)g_rva.CAM_UPDATE);
            }
        }
        /* Recognised-build tables can still have gaps (the GOG tables' newer
         * fields were never transplanted -- no GOG exe on hand). Fill ONLY the
         * zeros by signature so GOG gets the same feature set as Steam; a
         * missed signature just leaves the 0 and its guards stand down. */
        if (g_build) {
            int gaps = kfp_resolve_missing(g_base);
            if (gaps) logline("sig-scan filled %d table gap(s) for this build", gaps);
        }

        /* Hook via RE_Kenshi's KenshiLib::AddHook (no in-binary inline hooking). */
        HMODULE klib = GetModuleHandleA("KenshiLib.dll");
        g_klib_addhook = klib ? (klib_addhook_t)GetProcAddress(klib, KLIB_ADDHOOK_SYM) : NULL;
        logline("KenshiLib.dll=%p AddHook=%p", (void *)klib, (void *)g_klib_addhook);
        if (!g_klib_addhook) {
            g_wrong_build = 1;             /* can't hook without it -> stand down cleanly */
            logline("*** KenshiLib::AddHook not found -- RE edition needs RE_Kenshi/KenshiLib loaded");
        }
    }
#else
    {
        static const unsigned char SIG_MAINLOOP[8] =
            { 0x48,0x8b,0xc4,0x56,0x57,0x41,0x54,0x48 };
        unsigned char *p68 = (unsigned char *)(g_base + T_1068.MAINLOOP);
        unsigned char *p65 = (unsigned char *)(g_base + T_1065.MAINLOOP);
        unsigned char *pgog = (unsigned char *)(g_base + T_GOG68.MAINLOOP);
        unsigned char *pgog65 = (unsigned char *)(g_base + T_GOG65.MAINLOOP);
        if (readable(p68, 8) && memcmp(p68, SIG_MAINLOOP, 8) == 0) { g_rva = T_1068; g_build = 68; }
        else if (readable(p65, 8) && memcmp(p65, SIG_MAINLOOP, 8) == 0) { g_rva = T_1065; g_build = 65; }
        else if (readable(pgog, 8) && memcmp(pgog, SIG_MAINLOOP, 8) == 0) { g_rva = T_GOG68; g_build = 68; g_gog = 1; }
        else if (readable(pgog65, 8) && memcmp(pgog65, SIG_MAINLOOP, 8) == 0) { g_rva = T_GOG65; g_build = 65; g_gog = 1; }
        else g_wrong_build = 1;
        if (!g_wrong_build) g_rva_gaps = kfp_resolve_missing(g_base);   /* GOG tables' newer
            * fields (setPause / keyPressed / raycast) were never transplanted:
            * resolve them by signature so every supported build behaves alike */
    }
#endif

    g_follow_object  = (follow_object_t)(g_base + RVA_FOLLOW_OBJECT);
    g_stop_following = (stop_follow_t)(g_base + RVA_STOP_FOLLOW);
    g_charmove_setdest = (charmove_setdest_t)(g_base + RVA_CHARMOVE_SETDEST);
    g_char_setdest     = (char_setdest_t)(g_base + RVA_CHAR_SETDEST);
    g_nearest_town     = (nearest_town_t)(g_base + RVA_NEAREST_TOWN);
    g_interior_load    = (interior_load_t)(g_base + RVA_INTERIOR_LOAD);
    g_hand2bld = RVA_HAND_TO_BUILDING ? (hand2bld_t)(g_base + RVA_HAND_TO_BUILDING) : NULL;
    g_get_town      = RVA_GET_TOWN      ? (get_town_t)(g_base + RVA_GET_TOWN) : NULL;
    g_set_floorbyte = RVA_SET_FLOORBYTE ? (set_floorbyte_t)(g_base + RVA_SET_FLOORBYTE) : NULL;
    {   /* PlayerInterface::startTrackCharacter -- signature-resolved (build-independent) */
        uintptr_t stc = kfp_text_scan(STC_SIG, STC_MASK, sizeof STC_SIG);
        g_start_track_char = (start_track_char_t)stc;
        logline("floor-track: startTrackCharacter=%p (%s)", (void *)stc,
                stc ? "ARMED" : "sig NOT FOUND");
    }
    AddVectoredExceptionHandler(1, veh_guard);   /* crash guard for game-fn calls */
    {
        HMODULE terr = GetModuleHandleA("Plugin_Terrain_x64.dll");
        if (terr) {
            g_terrain_getheight =
                (terrain_getheight_t)GetProcAddress(terr, TERRAIN_GETHEIGHT_SYM);
            g_terrain_intersect =
                (terrain_intersect_t)GetProcAddress(terr, TERRAIN_INTERSECT_SYM);
        }
        logline("Terrain getHeight=%s intersect=%s",
                g_terrain_getheight ? "ok" : "MISSING",
                g_terrain_intersect ? "ok" : "MISSING");
    }
    g_get_bone_world   = (get_bone_world_t)(g_base + RVA_GET_BONE_WORLD);
    /* CharStats::xpRunning -- only if resolved (0 on an unrecognised build). */
    g_xp_running = g_rva.XP_RUNNING ? (xprunning_t)(g_base + g_rva.XP_RUNNING) : NULL;
    logline("CharStats::xpRunning=%p (WASD athletics/strength XP %s)",
            (void *)g_xp_running, g_xp_running ? "armed" : "UNRESOLVED");

    /* Input capture is 100% POLLING -- NO global WH_MOUSE_LL / WH_KEYBOARD_LL
     * hooks (a background thread running a global keyboard hook reads as a
     * keylogger to antivirus). A ~1kHz thread polls the FP-toggle key via
     * GetAsyncKeyState and, once the DirectInput mouse is acquired, reads look
     * deltas + wheel from it. Started at load so the toggle works immediately;
     * off the frame loop, so no fps-dependent input stutter either. */
    if (!g_di_thread_on) {
        g_di_thread_on = 1;
        HANDLE ht = CreateThread(NULL, 0, di_poll_thread, NULL, 0, NULL);
        if (ht) CloseHandle(ht);
        logline(ht ? "input poll thread started (~1kHz; toggle + look + wheel, no OS hooks)"
                   : "input poll thread FAILED to start (err %lu)", GetLastError());
    }

    /* FP look deltas: DirectInput non-exclusive device, created lazily on the
     * first FP frame (the game window must exist). See ensure_dinput. */
    /* MSVC std::string SSO for the head bone name (size<=15 -> inline buffer). */
    memset(g_head_bone, 0, sizeof g_head_bone);
    memcpy(g_head_bone, HEAD_BONE_NAME, sizeof(HEAD_BONE_NAME) - 1);
    *(size_t *)(g_head_bone + 0x10) = sizeof(HEAD_BONE_NAME) - 1;  /* size */
    *(size_t *)(g_head_bone + 0x18) = 15;                          /* capacity */
    /* Spine/neck chain for procedural aim-pitch (Biped naming, all SSO). */
    make_mstr(g_bone_spine1, "Bip01 Spine1");
    make_mstr(g_bone_spine2, "Bip01 Spine2");
    make_mstr(g_bone_neck,   "Bip01 Neck");
    make_mstr(g_bone_rootspine, "Bip01 Spine");   /* readiness computed after Ogre resolves */
    logline("KenshiFP v0.6.1 loaded (FP + head-bone + FOV + WASD); module base %p", (void *)g_base);
    {   /* WHICH COPY IS THIS? Log our own DLL path: a stale Steam Workshop item
         * shadowing (or being shadowed by) a local mods/ copy is the single
         * most confusing support case -- testers reported fixed bugs as broken
         * because the Workshop was still serving an old build. One line here
         * answers "which build am I actually running" from any user's log. */
        wchar_t selfw[MAX_PATH];
        DWORD sn = GetModuleFileNameW(g_hinst, selfw, MAX_PATH);
        if (sn && sn < MAX_PATH) {
            char selfa[MAX_PATH];
            if (WideCharToMultiByte(CP_UTF8, 0, selfw, -1, selfa, sizeof selfa, NULL, NULL) > 0) {
                const char *kind = strstr(selfa, "workshop") ? "Steam Workshop"
                                 : strstr(selfa, "mods")     ? "local mods folder"
                                                             : "game root (standalone)";
                logline("loaded from: %s  [%s]", selfa, kind);
            }
        }
    }

    /* Report the detected build (selection already happened above). */
    {
        wchar_t exw[MAX_PATH]; char exa[MAX_PATH] = {0};
        if (GetModuleFileNameW(NULL, exw, MAX_PATH))
            WideCharToMultiByte(CP_UTF8, 0, exw, -1, exa, MAX_PATH, NULL, NULL);
        logline("running exe: %s", exa[0] ? exa : "(unknown)");
        if (g_wrong_build) {
            unsigned char *pm = (unsigned char *)(g_base + T_1068.MAINLOOP);
            if (readable(pm, 8))
                logline("bytes @0x%x: %02x %02x %02x %02x %02x %02x %02x %02x",
                        (unsigned)T_1068.MAINLOOP, pm[0],pm[1],pm[2],pm[3],pm[4],pm[5],pm[6],pm[7]);
            logline("*** UNSUPPORTED GAME BUILD -- KenshiFP is DISABLED. ***");
            logline("*** Supported: Steam Kenshi 1.0.68 / 1.0.65, GOG 1.0.68 / 1.0.65 (x64).");
            if (exa[0] && (strstr(exa, "RE_Kenshi") || strstr(exa, "re_kenshi")))
                logline("*** Running RE_Kenshi's bundled exe but its build signature "
                        "was not recognised -- report this log.");
        } else {
            logline("game build detected: %s 1.0.%d%s", g_gog ? "GOG" : "Steam",
                    g_build, g_build == 65 ? " (RE_Kenshi downgrade)" : "");
            if (g_rva_gaps)
                logline("sig-scan filled %d table gap(s) for this build", g_rva_gaps);
        }
    }

    /* Resolve Ogre node world-transform setters from OgreMain_x64.dll. */
    HMODULE ogre = GetModuleHandleA("OgreMain_x64.dll");
    meshray_init(ogre);        /* true-geometry query exports (task #22) */
    if (ogre) {
        g_node_set_pos  = (node_set_pos_t)GetProcAddress(ogre, OGRE_SETPOS_SYM);
        g_node_set_ori  = (node_set_ori_t)GetProcAddress(ogre, OGRE_SETORI_SYM);
        g_node_set_dori = (node_set_dori_t)GetProcAddress(ogre, OGRE_SETDORI_SYM);
        g_node_set_dpos = (node_set_dpos_t)GetProcAddress(ogre, OGRE_SETDPOS_SYM);
        g_node_get_dpos = (node_get_dpos_t)GetProcAddress(ogre, OGRE_GETDPOS_SYM);
        g_node_get_pos  = (node_get_pos_t)GetProcAddress(ogre, OGRE_GETPOS_SYM);
        g_ent_setvisible = (ent_setvisible_t)GetProcAddress(ogre, OGRE_SETVISIBLE_SYM);
        g_ent_getvisible = (ent_getvisible_t)GetProcAddress(ogre, OGRE_GETVISIBLE_SYM);
        g_disable_bone  = (disable_bone_t)GetProcAddress(ogre, OGRE_DISABLEBONE_SYM);
        g_skel_getbone  = (skel_getbone_t)GetProcAddress(ogre, OGRE_GETBONE_SYM);
        g_oldnode_getdori = (oldnode_getdori_t)GetProcAddress(ogre, OGRE_OLDNODE_GETDORI_SYM);
        g_oldnode_getdpos = (oldnode_getdpos_t)GetProcAddress(ogre, OGRE_OLDNODE_GETDPOS_SYM);
        g_node_getdpos_upd = (node_getdpos_upd_t)GetProcAddress(ogre, OGRE_GETDPOS_UPD_SYM);
        g_node_getdori_v = (node_getdori_t)GetProcAddress(ogre, "?_getDerivedOrientation@Node@Ogre@@QEBA?AVQuaternion@2@XZ");
        g_node_getdpos_v = (node_getdvec_t)GetProcAddress(ogre, "?_getDerivedPosition@Node@Ogre@@QEBA?AVVector3@2@XZ");
        g_node_getdscale_v = (node_getdvec_t)GetProcAddress(ogre, "?_getDerivedScale@Node@Ogre@@QEBA?AVVector3@2@XZ");
        g_oldnode_getori  = (oldnode_getori_t)GetProcAddress(ogre, OGRE_OLDNODE_GETORI_SYM);
        g_oldnode_setori  = (oldnode_setori_t)GetProcAddress(ogre, OGRE_OLDNODE_SETORI_SYM);
        g_oldnode_needupd = (oldnode_needupd_t)GetProcAddress(ogre, OGRE_OLDNODE_NEEDUPD_SYM);
        g_oldbone_setmanual = (oldbone_setmanual_t)GetProcAddress(ogre, OGRE_OLDBONE_SETMANUAL_SYM);
        g_oldnode_getinitori = (oldnode_getinitori_t)GetProcAddress(ogre, OGRE_OLDNODE_GETINITORI_SYM);
        g_oldnode_getinitpos = (oldnode_getinitpos_t)GetProcAddress(ogre, OGRE_OLDNODE_GETINITPOS_SYM);
        g_oldnode_getparent  = (oldnode_getparent_t)GetProcAddress(ogre, OGRE_OLDNODE_GETPARENT_SYM);
        g_oldnode_setpos     = (oldnode_setpos_t)GetProcAddress(ogre, OGRE_OLDNODE_SETPOS_SYM);
        g_oldnode_getpos     = (oldnode_getpos_t)GetProcAddress(ogre,   /* fp-eye-drift */
                                   "?getPosition@OldNode@Ogre@@UEBAAEBVVector3@2@XZ");
        g_oldnode_getdscale  = (oldnode_getdscale_t)GetProcAddress(ogre, OGRE_OLDNODE_GETDSCALE_SYM);
        g_oldnode_setscale = (oldnode_setscale_t)GetProcAddress(ogre, OGRE_OLDNODE_SETSCALE_SYM);
        g_mat_gettech    = (mat_gettech_t)GetProcAddress(ogre, OGRE_MAT_GETTECH_SYM);
        g_tech_getpass   = (tech_getpass_t)GetProcAddress(ogre, OGRE_TECH_GETPASS_SYM);
        g_pass_getvpp    = (pass_getvpp_t)GetProcAddress(ogre, OGRE_PASS_GETVPP_SYM);
        g_gpup_setnamedi = (gpup_setnamedi_t)GetProcAddress(ogre, OGRE_GPUP_SETNAMEDI_SYM);
        g_gpup_ignoremiss = (gpup_ignoremiss_t)GetProcAddress(ogre, OGRE_GPUP_IGNOREMISS_SYM);
        g_gpup_finddef   = (gpup_finddef_t)GetProcAddress(ogre, OGRE_GPUP_FINDDEF_SYM);
        g_mat_numtech    = (mat_numtech_t)GetProcAddress(ogre, OGRE_MAT_NUMTECH_SYM);
        g_tech_numpass   = (tech_numpass_t)GetProcAddress(ogre, OGRE_TECH_NUMPASS_SYM);
        g_get_parent_scenenode = (get_parent_scenenode_t)GetProcAddress(ogre, OGRE_GETPARENTSCENENODE_SYM);
        g_entity_updateanim = (entity_updateanim_t)GetProcAddress(ogre, OGRE_ENTITY_UPDATEANIM_SYM);
        g_entity_getskel = (entity_getskel_t)GetProcAddress(ogre, OGRE_ENTITY_GETSKEL_SYM);
        if (!g_entity_getskel)
            g_entity_getskel = (entity_getskel_t)GetProcAddress(ogre, OGRE_ENTITY_GETSKEL_SYM2);
        g_cam_set_fovy  = (cam_set_fovy_t)GetProcAddress(ogre, OGRE_SETFOVY_SYM);
        g_cam_get_fovy  = (cam_get_fovy_t)GetProcAddress(ogre, OGRE_GETFOVY_SYM);
        g_cam_set_nearclip = (cam_set_nearclip_t)GetProcAddress(ogre, OGRE_SETNEARCLIP_SYM);
        g_cam_get_nearclip = (cam_get_nearclip_t)GetProcAddress(ogre, OGRE_GETNEARCLIP_SYM);
        g_cam_get_farclip  = (cam_get_nearclip_t)GetProcAddress(ogre, OGRE_GETFARCLIP_SYM);
        g_ogre_ready = (g_node_set_dori && g_node_set_dpos && g_node_get_dpos);
        g_spine_ready = (g_oldnode_getori && g_oldnode_setori &&
                         g_oldnode_needupd && g_skel_getbone) ? 1 : 0;
        logline("Ogre FOV setters: set=%p get=%p", (void *)g_cam_set_fovy, (void *)g_cam_get_fovy);
        logline("spine-bend: getori=%p setori=%p needupd=%p -> %s",
                (void *)g_oldnode_getori, (void *)g_oldnode_setori,
                (void *)g_oldnode_needupd, g_spine_ready ? "ARMED" : "unavailable");
        vm_install(ogre);
        kfp_loco_load();   /* parse locomotion.kfa (inert until the retarget is wired) */
        logline("head-hide: hiddenMask set=%p find=%p -> %s (mask=0x%x)",
                (void *)g_gpup_setnamedi, (void *)g_gpup_finddef,
                (g_gpup_setnamedi && g_mat_gettech && g_tech_getpass && g_pass_getvpp
                 && g_gpup_finddef && g_mat_numtech && g_tech_numpass)
                    ? "ARMED" : "UNAVAILABLE", g_cfg_head_mask);
        /* Head-covering gear rides Ogre::MovableObject::setVisible. Log the resolved
         * pointer: this Ogre fork's decorated names drift from stock Ogre and
         * GetProcAddress just returns NULL on a mismatch, silently killing the feature. */
        logline("headgear-hide: MovableObject::setVisible=%p -> %s (slots=0x%x, enabled=%d)",
                (void *)g_ent_setvisible, g_ent_setvisible ? "ARMED" : "UNAVAILABLE",
                g_cfg_headgear_slots, g_cfg_hide_headgear);
    }
    logline(g_ogre_ready ? "Ogre node setters resolved (FP override armed)"
                         : "WARN: Ogre node setters NOT resolved (FP override disabled)");

    /* Hooking backend: KenshiLib::AddHook for the RE edition (already resolved),
     * MinHook for the standalone. */
#ifdef KFP_RE_PLUGIN
    int hook_ready = !g_wrong_build;   /* g_klib_addhook checked above */
#else
    MH_STATUS mh = g_wrong_build ? MH_ERROR_NOT_INITIALIZED : MH_Initialize();
    int hook_ready = !g_wrong_build && (mh == MH_OK || mh == MH_ERROR_ALREADY_INITIALIZED);
#endif
    int ok = 0;
    if (hook_ready) {
        void *target = (void *)(g_base + RVA_MAINLOOP);
        g_mainloop_target = target;
        ok = install_hook(target, (void *)hooked_mainloop, (void **)&g_mainloop_orig);
        logline(ok ? "per-frame hook installed (mainLoop_GPUSensitiveStuff)"
                   : "per-frame hook FAILED");
        /* re-arm watchdog: only meaningful on the MinHook path (KenshiLib
         * cooperates, nothing to re-arm). Still logs the heartbeat diagnostic. */
        if (ok) CloseHandle(CreateThread(NULL, 0, hook_watchdog, NULL, 0, NULL));

        /* CameraClass::update hook: mid-frame FP-eye re-assert (foliage/LOD fix). */
        {
            void *cu = (void *)(g_base + RVA_CAM_UPDATE);
            int mh2ok = install_hook(cu, (void *)hooked_cam_update,
                                     (void **)&g_cam_update_orig);
            logline(mh2ok ? "camera update hook installed (mid-frame eye)"
                          : "camera update hook FAILED");
        }

        /* Ranged free-aim hook (aim where the FP camera looks). */
        {
            void *ra = (void *)(g_base + RVA_RANGED_ANIMUPD);
            int raok = install_hook(ra, (void *)hooked_ranged_animupd,
                                    (void **)&g_ranged_animupd_orig);
            logline(raok ? "ranged free-aim hook installed (animationUpdate)"
                         : "ranged free-aim hook FAILED");
            void *gs = (void *)(g_base + RVA_GUN_SHOOT);
            int gsok = install_hook(gs, (void *)hooked_gun_shoot,
                                    (void **)&g_gun_shoot_orig);
            logline(gsok ? "projectile aim hook installed (GunClass::shoot)"
                         : "projectile aim hook FAILED");
            fp_combat_native_init();
            fp_melee_observe_init();
            fp_melee_manual_init();
            fp_controls_init();
            void *fd = (void *)(g_base + RVA_FACE_DIR);
            int fdok = install_hook(fd, (void *)hooked_face_direction,
                                    (void **)&g_face_dir_orig);
            logline(fdok ? "facing hook installed (CharMovement::faceDirection)"
                         : "facing hook FAILED");
            void *sh = (void *)(g_base + RVA_SHEATHE);
            int shok = install_hook(sh, (void *)hooked_sheathe,
                                    (void **)&g_sheathe_orig);
            logline(shok ? "sheathe suppressor installed (manual aim hold)"
                         : "sheathe suppressor FAILED");
            void *cu2 = (void *)(g_base + RVA_CHARMOVE_UPDATE);
            int cuok = install_hook(cu2, (void *)hooked_charmove_update,
                                    (void **)&g_charmove_update_orig);
            logline(cuok ? "movement update hook installed (WASD wins combat race)"
                         : "movement update hook FAILED");
            if (RVA_KEYPRESSED) {
                int kok = install_hook((void *)(g_base + RVA_KEYPRESSED),
                                       (void *)hooked_keypressed,
                                       (void **)&g_keypressed_orig);
                logline(kok ? "keyPressed hook installed (FP jump owns the space keydown)"
                            : "keyPressed hook FAILED (fallback: setPause revert only)");
            }
            if (RVA_IH_KEYDOWN) {
                int iok = install_hook((void *)(g_base + RVA_IH_KEYDOWN),
                                       (void *)hooked_ih_keydown,
                                       (void **)&g_ih_keydown_orig);
                logline(iok ? "InputHandler::keyDownEvent hook installed (FP-bound keys never reach vanilla commands)"
                            : "InputHandler::keyDownEvent hook FAILED (fallback: freecam revert only)");
            }
            /* updateHiddenParts detour: re-inject the head hide-bits the game clobbers. */
            uintptr_t uhp = kfp_text_scan(UHP_SIG, UHP_MASK, sizeof UHP_SIG);
            if (uhp) {
                int uok = install_hook((void *)uhp, (void *)hooked_update_hidden,
                                       (void **)&g_update_hidden_orig);
                logline(uok ? "updateHiddenParts hook installed (head-hide, cam-safe)"
                            : "updateHiddenParts hook FAILED");
            } else {
                logline("updateHiddenParts sig NOT FOUND -- head-hide per-frame only");
            }
            /* refreshInterior detour: reveal the floor-above's INTERIOR props (seamless up). */
            if (RVA_INTERIOR_LOAD) {
                void *ri = (void *)(g_base + RVA_INTERIOR_LOAD);
                int riok = install_hook(ri, (void *)hooked_refresh_interior,
                                        (void **)&g_refresh_interior_orig);
                logline(riok ? "refreshInterior hook installed (seamless-up interior reveal)"
                             : "refreshInterior hook FAILED");
            }
            /* shell-cull detour (FUN_1409fa670) stays OFF: its container objects all had
             * +0x188!=0 (the cull skips those) -- not the building's floor-cullable walls. */
            (void)g_shell_cull_orig; (void)g_resolve_shell_obj; (void)g_resolve_bld;
            /* wallcull detour: Object::updateVisibility (FUN_1405c94d0) is the per-object
             * floor-cull applier. For the char's building's floor-ABOVE structural objects
             * (walls/floor), force the interior flag +0xe5 and render flag +0x1a8 so going
             * UP shows the floor-above INTERIOR the same way descending shows the floor below. */
            if (RVA_WALLCULL) {
                void *wc = (void *)(g_base + RVA_WALLCULL);
                int wcok = install_hook(wc, (void *)hooked_wallcull,
                                        (void **)&g_wallcull_orig);
                logline(wcok ? "wallcull hook installed (seamless-up walls/floor reveal)"
                             : "wallcull hook FAILED");
            } else {
                logline("wallcull RVA unset for this build -- walls/floor reveal disabled");
            }
            /* Screen-label crosshair remap: pin the FP character's own floating
             * statuses ("Pick failed"/"Pick success!"/"*Thunk*"/...) and the
             * lockpick/job % bar near the crosshair. */
            if (g_rva.SLABEL_UPDATE) {
                void *sl = (void *)(g_base + g_rva.SLABEL_UPDATE);
                int slok = install_hook(sl, (void *)hooked_slabel_update,
                                        (void **)&g_slabel_update_orig);
                logline(slok ? "screen-label hook installed (status text at crosshair)"
                             : "screen-label hook FAILED");
            } else {
                logline("ScreenLabel::update RVA unset -- status text stays world-anchored");
            }
            if (g_rva.PBAR_UPDATE) {
                void *pb = (void *)(g_base + g_rva.PBAR_UPDATE);
                int pbok = install_hook(pb, (void *)hooked_pbar_update,
                                        (void **)&g_pbar_update_orig);
                logline(pbok ? "progress-bar hook installed (lockpick % at crosshair)"
                             : "progress-bar hook FAILED");
            } else {
                logline("FloatingProgressBar::update RVA unset -- % bar stays world-anchored");
            }
        }

        /* MyGUI cursor: resolve + hook setPointer to hide the default arrow. */
        HMODULE mygui = GetModuleHandleA(MYGUI_DLL);
        if (mygui) {
            g_pm_setvisible  = (pm_setvisible_t)GetProcAddress(mygui, MYGUI_SETVISIBLE_SYM);
            g_pm_getdefault  = (pm_getdefault_t)GetProcAddress(mygui, MYGUI_GETDEFAULT_SYM);
            g_pm_getinstance = (pm_getinstance_t)GetProcAddress(mygui, MYGUI_GETINSTANCE_SYM);
            g_gui_getinstance = (gui_getinstance_t)GetProcAddress(mygui, MYGUI_GUI_GETINSTANCE_SYM);
            g_gui_createwidget = (gui_createwidget_t)GetProcAddress(mygui, MYGUI_CREATEWIDGET_SYM);
            g_imgbox_setimage = (imgbox_setimage_t)GetProcAddress(mygui, MYGUI_SETIMAGETEX_SYM);
            g_imgbox_setres   = (imgbox_setres_t)GetProcAddress(mygui, MYGUI_SETITEMRES_SYM);
            g_imgbox_setgrp   = (imgbox_setgrp_t)GetProcAddress(mygui, MYGUI_SETITEMGRP_SYM);
            g_imgbox_setnm    = (imgbox_setnm_t)GetProcAddress(mygui, MYGUI_SETITEMNAME_SYM);
            g_widget_setcolour = (widget_setcolour_t)GetProcAddress(mygui, MYGUI_SETCOLOUR_SYM);
            g_widget_setpos    = (widget_setpos_t)GetProcAddress(mygui, MYGUI_SETPOS_SYM);
            g_gui_getsubmain   = (gui_getsubmain_t)GetProcAddress(mygui, MYGUI_GETSUBMAIN_SYM);
            g_gui_subsetcolour = (gui_subsetcolour_t)GetProcAddress(mygui, MYGUI_SUBSETCOLOUR_SYM);
            g_gui_findwidget     = (gui_findwidget_t)GetProcAddress(mygui, MYGUI_GUI_FINDWIDGET_SYM);
            g_widget_createwidget= (widget_createwidget_t)GetProcAddress(mygui, MYGUI_WIDGET_CREATEWIDGET_SYM);
            g_tabctrl_itemcount  = (tabctrl_itemcount_t)GetProcAddress(mygui, MYGUI_TABCTRL_ITEMCOUNT_SYM);
            g_tabctrl_itemat     = (tabctrl_itemat_t)GetProcAddress(mygui, MYGUI_TABCTRL_ITEMAT_SYM);
            g_input_getinst      = (input_getinst_t)GetProcAddress(mygui, MYGUI_INPUT_GETINST_SYM);
            g_mousefocus         = (mousefocus_t)GetProcAddress(mygui, MYGUI_MOUSEFOCUS_SYM);
            g_keyfocus           = (keyfocus_t)GetProcAddress(mygui, MYGUI_KEYFOCUS_SYM);
            g_widget_getparent   = (getparent_t)GetProcAddress(mygui, MYGUI_GETPARENT_SYM);
            g_scroll_setrange    = (scroll_setrange_t)GetProcAddress(mygui, MYGUI_SCROLL_SETRANGE_SYM);
            g_scroll_setpos      = (scroll_setpos_t)GetProcAddress(mygui, MYGUI_SCROLL_SETPOS_SYM);
            g_scroll_getpos      = (scroll_getpos_t)GetProcAddress(mygui, MYGUI_SCROLL_GETPOS_SYM);
            g_btn_getsel         = (btn_getsel_t)GetProcAddress(mygui, MYGUI_BTN_GETSEL_SYM);
            g_btn_setsel         = (btn_setsel_t)GetProcAddress(mygui, MYGUI_BTN_SETSEL_SYM);
            g_textbox_setcap     = (textbox_setcap_t)GetProcAddress(mygui, MYGUI_TEXTBOX_SETCAP_SYM);
            g_window_setcap      = (textbox_setcap_t)GetProcAddress(mygui, MYGUI_WINDOW_SETCAP_SYM);
            g_ustring_ctor       = (ustring_ctor_t)GetProcAddress(mygui, MYGUI_USTRING_CTOR_SYM);
            g_ustring_dtor       = (ustring_dtor_t)GetProcAddress(mygui, MYGUI_USTRING_DTOR_SYM);
            g_gui_getenum        = (getenum_t)GetProcAddress(mygui, MYGUI_GUI_GETENUM_SYM);
            g_widget_getenum     = (getenum_t)GetProcAddress(mygui, MYGUI_WIDGET_GETENUM_SYM);
            g_widget_getname     = (widget_getname_t)GetProcAddress(mygui, MYGUI_WIDGET_GETNAME_SYM);
            if (KFP_DEBUG_LOG)
                logline("[settings] syms: wcreate=%p focus(inst=%p,mouse=%p,key=%p,parent=%p) scroll(set=%p,get=%p) btn(get=%p,set=%p) cap=%p wcap=%p",
                    (void*)g_widget_createwidget,(void*)g_input_getinst,(void*)g_mousefocus,(void*)g_keyfocus,(void*)g_widget_getparent,
                    (void*)g_scroll_setpos,(void*)g_scroll_getpos,(void*)g_btn_getsel,(void*)g_btn_setsel,
                    (void*)g_textbox_setcap,(void*)g_window_setcap);
            g_widget_setvisible = (widget_setvisible_t)GetProcAddress(mygui, MYGUI_WIDGET_SETVIS_SYM);
            g_widget_inhvis = (widget_inhvis_t)GetProcAddress(mygui, MYGUI_WIDGET_INHVIS_SYM);
            HMODULE ogremod = GetModuleHandleA("OgreMain_x64.dll");
            if (ogremod) {
                g_rgm_getsingleton = (rgm_getsingleton_t)GetProcAddress(ogremod, OGRE_RGM_GETSINGLETON_SYM);
                g_rgm_addlocation  = (rgm_addlocation_t)GetProcAddress(ogremod, OGRE_RGM_ADDLOCATION_SYM);
                g_rgm_creategroup  = (rgm_creategroup_t)GetProcAddress(ogremod, OGRE_RGM_CREATEGROUP_SYM);
                g_rgm_initgroup    = (rgm_initgroup_t)GetProcAddress(ogremod, OGRE_RGM_INITGROUP_SYM);
            }
            void *sp = GetProcAddress(mygui, MYGUI_SETPOINTER_SYM);
            int spok = sp && install_hook(sp, (void *)hooked_setpointer,
                                          (void **)&g_pm_setpointer_orig);
            logline(spok ? "MyGUI setPointer hook installed (hide default cursor)"
                         : "MyGUI setPointer hook FAILED");
            fpc_gui_mouse_install(mygui);   /* PT23/PT26: FP look clicks never reach GUI buttons */
        } else {
            logline("MyGUIEngine_x64.dll not found — cursor hide disabled");
        }
    } else if (!g_wrong_build) {
        logline("hook backend init failed (no MinHook / KenshiLib::AddHook)");
    }

    load_ini();                    /* optional KenshiFP.ini (fps_cap=N, ...) */
    logline(ok ? "KenshiFP active: RIGHT ALT = first-person toggle; mouse = look; WASD = move; wheel = speed"
               : (g_wrong_build ? "KenshiFP inactive (unsupported game build)"
                                : "KenshiFP FAILED to install per-frame hook"));
}

__declspec(dllexport) void dllStopPlugin(void) { logline("dllStopPlugin"); }

#ifdef KFP_RE_PLUGIN
/* RE_Kenshi entry point. It LoadLibrary's this DLL and calls startPlugin()
 * (exported as ?startPlugin@@YAXXZ via plugin.def). Same init as the Ogre
 * dllStartPlugin, but g_rva is resolved by signature (see the KFP_RE_PLUGIN
 * branch above). */
void startPlugin(void) { dllStartPlugin(); }
#endif

BOOL WINAPI DllMain(HINSTANCE h, DWORD reason, LPVOID reserved)
{
    (void)reserved;
    if (reason == DLL_PROCESS_ATTACH) { g_hinst = h; DisableThreadLibraryCalls(h); }
    return TRUE;
}
