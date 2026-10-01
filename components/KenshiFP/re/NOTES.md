# KenshiFP RE notes — Kenshi 1.0.68 "Newland" x64

Ghidra project is SHARED with KenshiMP: `../KenshiMP/re/KenshiMP.gpr`
(already fully analyzed). Run queries like:

```sh
~/.local/opt/ghidra_12.1.2_PUBLIC/support/analyzeHeadless ../KenshiMP/re KenshiMP \
  -process kenshi_x64.exe -noanalysis \
  -scriptPath re/scripts -postScript <Script>.java
```

ImageBase 0x140000000. RVAs below are for 1.0.68 unless marked otherwise.

## Offset table

### CONFIRMED (inherited from KenshiMP, proven in-game on 1.0.68)
| What | Value |
|---|---|
| GameWorld::mainLoop_GPUSensitiveStuff (per-frame, main thread, GameWorld* this) | RVA 0x788a00 |
| GameWorld::player (PlayerInterface*) | +0x580 |
| PlayerInterface::playerCharacters (lektor<Character*>) | +0x2B0 |
| PlayerInterface::participant (Faction*) | +0x2A0 |
| lektor: count / stuff | +0x8 u32 / +0x10 T* |
| Character::getPosition | vtable slot 8 (+0x40), ABI `Vec3* (this RCX, Vec3* out RDX)` |
| setPause(GameWorld*, char) | RVA 0x787fb0 |
| setSpeed(uiCtx, float, char) | RVA 0x787e40 |

### FROM KENSHILIB HEADERS — field offsets (plausible, need one in-game sanity read)
CameraClass: yaw +0x18, pitch +0x1C, objectCurrentlyFollowing (hand) +0x28,
center SceneNode* +0x58, altitude +0x60, camera Ogre::Camera* +0x68,
node SceneNode* +0x70, inBuilding +0x80, currentFloor +0xBE,
freeCameraMode +0xBF.

InputHandler: controlEnabled +0xD0, ctrl/shift/alt +0xD8..0xDA,
up/down/left/right +0xDB..0xDE (WASD default-binds pan camera through these),
space +0xDF, mLeft/mRight +0xF3/0xF4, mPos Vec2 +0xFC, mPosAbs +0x104,
mSpeed Vec3 +0x10C, mWheel int +0x118. keyboard OIS::Keyboard* +0xA0.

Character: destination-state cluster ~+0x420 (_destinationInsideBuilding).

### STALE HEADER RVAs — need 1.0.68 derivation before ANY use
(KenshiLib RVAs proven wrong for this build in KenshiMP; listed only as
relative-layout hints — functions that were neighbors likely still cluster.)
- CameraClass::update(bool) [hdr 0x6B05E0], rotate(f,f) [0x6AF940],
  followObject [0x6ADDA0], stopFollowing [0x6ADDE0], teleport [0x6AF190],
  setZoomDist [0x6ADF40], move(Vec3) [0x6ADE30], setFreeCameraMode [0x6AF1E0]
- InputHandler::initialise [0x363210], addCommand [0x362F90/0x363130],
  keyDownEvent [0x360680]
- Character::setDestination(Vec3&, bool) [hdr 0x5C8E30]

## Anchor strategies (M0 work)
1. `strings` the exe for keybinding command names + camera option strings →
   exact needles.
2. Xref needles in Ghidra → InputHandler::addCommand call cluster (gives the
   InputHandler global) and options-read sites (gives CameraClass:
   updateOptionSettings neighborhood).
3. CameraClass::update identified by: reads InputHandler pan bools, reads/
   writes yaw(+0x18)/pitch(+0x1C), called once per frame from the main loop.
   Its caller yields the live CameraClass pointer (likely a GameWorld field or
   global).
4. setDestination: from the right-click order path, or decompile around the
   destination-state field writes (+0x420 cluster), or live-vtable dump from a
   Character* at runtime (KenshiMP pattern).

## Findings log

### 2026-07-17 — M0 recon (headless, shared KenshiMP Ghidra project)
Scripts: re/scripts/FindCameraAnchors.java, FindGlobals.java, DumpFns.java,
FindRefsToGlobal.java (all read-only, run against ../KenshiMP/re).

**Camera command strings (exact needles, verified in 1.0.68 exe via `strings`):**
`camera_forward` @RVA 0x16c3248, `camera_back` 0x16c3238, `camera_left`
0x16c3228, `camera_right` 0x16c3218, `camera_rotate_left` 0x16c31e0,
`camera_rotate_right` 0x16c31c8, `camera_zoom_in` 0x16c2e18, `camera_zoom_out`
0x16c2e00. Vanilla WASD default-binds camera_forward/back/left/right → these
set InputHandler.up/down/left/right (+0xDB..0xDE). Also `Camera Rotate Speed X`
@0x16cf050, `Camera Zoom Speed` @0x16cf018, `camera speed` @0x16ce428.

**Command-registration / config cluster:** FUN_140362430 (RVA 0x362430) — an
InputHandler method (`this`=param_1) that references controls.cfg and the camera
command strings; the addCommand/bind neighborhood (KenshiLib put
InputHandler::initialise 0x363210, addCommand 0x362F90/0x363130 nearby — cluster
confirmed present). Also FUN_1403636c0 (0x3636c0), FUN_1403f0260 (0x3f0260)
reference the same strings; FUN_1403eca90/1403e84f0 reference the option strings.
No direct call-xrefs to FUN_140362430 (likely vtable/initializer-dispatched), so
the InputHandler `key` global was NOT pinned this pass — TODO.

**GameWorld::mainLoop_GPUSensitiveStuff (RVA 0x788a00) decompiled — confirms:**
- param_1 = GameWorld*; `param_1 + 0x700` = frameSpeedMult (matches KenshiMP),
  `+0x580` = player (matches), `+0x8b9` = paused bool (header value; distinct
  from KenshiMP's other pause flag at +0x3D4 — both exist).
- Speed globals written here: DAT_142133798 (= dt * frameSpeedMult),
  DAT_142133794, DAT_142133790 (= raw dt).

**CAMERA GLOBAL — key M0 finding: `DAT_142133308` (RVA 0x2133308).**
Every frame mainLoop does `Ogre::Camera::getViewMatrix(*(Camera**)
(DAT_142133308 + 0x58), true)` → **+0x58 is the live Ogre::Camera***. The global
is a core singleton (100+ read xrefs), and one of its referrers, FUN_1406afbf0
(RVA 0x6afbf0), sits squarely in the CameraClass method cluster (KenshiLib
CameraClass RVAs were 0x6ADxxx–0x6B0xxx) → DAT_142133308 is very likely the
global `CameraClass*` (Kenshi's camera brain), not merely a raw Ogre camera.
CameraClass field offsets to validate against it in-game (KenshiLib header):
yaw +0x18, pitch +0x1C, objectCurrentlyFollowing(hand) +0x28, center +0x58(!),
altitude +0x60, camera(Ogre::Camera*) +0x68, node +0x70, freeCameraMode +0xBF.
NOTE conflict: header says Ogre::Camera at +0x68 but mainLoop reads +0x58 for
getViewMatrix, and +0x58 is header `center`(SceneNode*). Either 1.0.68 layout
shifted or DAT_142133308 is a different (camera-holder) type. **Stage-0 client
logs all these to resolve it empirically before we write anything.**

### 2026-07-17 (cont.) — CameraClass instance + layout NAILED
Chased the CameraClass ctor to its storage site:
- **CameraClass ctor = FUN_1406afbf0, RVA 0x6afbf0** (KenshiLib header 0x6AF410,
  stale). Decompile proves the header field layout is VALID for 1.0.68: it
  stores the Ogre::Camera* arg at this+0x68, builds SceneNode "camera_center"
  at this+0x58 and "camera_node" at this+0x70, and sets hand::vftable at
  this+0x28 (objectCurrentlyFollowing) and +0x80 (inBuilding). So yaw+0x18,
  pitch+0x1C, altitude+0x60, camera+0x68, center+0x58, node+0x70,
  freeCameraMode+0xBF are all trustworthy.
- Caller chain: FUN_140745490 calls setup FUN_14086cf90(&DAT_142133300); the
  setup fn stores scene ctx at holder+0x8 and the **CameraClass* at
  holder+0x10**. holder = 0x142133300, so:
  **CameraClass INSTANCE pointer = *(CameraClass**)(base + 0x2133310).**
- Resolves the earlier +0x58 conflict: DAT_142133308 (RVA 0x2133308) is NOT the
  CameraClass — it's the scene/render context (holder+0x8); its +0x58 is the
  Ogre::Camera used for getViewMatrix, its +0x60 a SceneManager. The real
  CameraClass is a distinct object at holder+0x10.
- Stage-0 client UPDATED to read the true instance (0x2133310) and cross-check
  that CameraClass.camera(+0x68) == sceneCtx.camera(+0x58). Rebuilt.

### 2026-07-17 — STAGE-0 VERIFIED IN-GAME (clean sweep, no crash, 70s+ stable)
Ran isolated (KenshiMP plugins temporarily disabled). Log:
scratchpad/KenshiFP_stage0_pass.log. All anchors confirmed:
- CameraClass instance @ RVA 0x2133310 = LIVE (cam=0x2108b80, stable). Decisive
  cross-check PASSED: CameraClass.camera(+0x68)==sceneCtx.camera(+0x58)
  (ogreCam 0x331c3c0 "MATCH" every tick) -> instance + field layout CONFIRMED.
  center(+0x58)=0x331a710, node(+0x70)=0x3324c90 both valid SceneNodes.
- Player char path: pc=0 in menu/loading, then pc=0x6d66c450 pos
  (-50978.8,1533.5,2932.5) after save load, via getPosition slot 8. CONFIRMED.
- **WASD via Win32 GetAsyncKeyState WORKS under Proton** (digits flip exactly
  with keys: A=0100, W+A=1100, W+D=1001, ...). So the engine `key` global is
  NOT needed for input reading — big simplification.
- F toggle works (FP ON/OFF per press). speedMult pinned 1.0. Hook stable.
- INCIDENTAL: gw fixed at 0x142134110 -> GameWorld object is statically located
  (RVA 0x2134110; this is what the `ou` global points to).
- OPEN (non-blocking): yaw(+0x18)/pitch(+0x1C)/altitude(+0x60) all read 0.000.
  Camera identity is proven via MATCH, so either the camera wasn't rotated or
  these rotation fields live/update elsewhere. Resolve during M2 (mouse-look):
  probe by rotating the camera in-game and watching which offsets change, or
  decompile CameraClass::rotate/rotationUpdate for the real field indices.

### 2026-07-17 — M1 camera-lock functions found (cluster enum before ctor)
Enumerated CameraClass methods in [0x6ad800,0x6af000) via ListAndDumpRange.java;
identified two by field-access signature:
- **followObject(const hand&) = RVA 0x6ae520.** ABI followObject(this /RCX/,
  const hand* /RDX/). Body copies the hand's 5 id dwords (arg+0x8..+0x18) into
  this->objectCurrentlyFollowing ids (this+0x30..+0x40) and zeroes the follow
  offset (this+0x48). Leaf setter, no alloc.
- **stopFollowing() = RVA 0x6ae560.** Resets this+0x30..+0x40 to the null-hand
  constants DAT_141e3a600.. (same ones the ctor used) and clears +0x48.
Character hand = Character+0x58 (ids at +0x60.. == hand+0x8), so
followObject(cam, char+0x58) locks the camera to that character. No separate
"isFollowing" bool exists — a valid followed hand == following; vanilla pan
likely calls stopFollowing, so M1 RE-ASSERTS followObject every frame while FP
on. (Nearby: FUN_1406ae960 @0x6ae960 calls Ogre::Camera vtable+0x108 with a
scaled global — a zoom/FOV setter, unused for now.)
M1 client writes followId to the log ([tick] followId=) to confirm the write.

### 2026-07-17 — M1 VERIFIED + M2 first-person built
M1 verified in-game: followId flips 0000000b (null-hand type=0xb) <-> 00000001
(followed) on F; camera locks onto/tracks the character; no crash. Confirms
followObject/stopFollowing and the whole write path.

CameraClass::update = **RVA 0x6b0f90** (found by branch on follow-hand type at
+0x30: ==0xb null, ==1 following, ==0x5b). Model learned:
- if freeCameraMode(+0xbf): delegates to FUN_1406b0960 (free/orbit) and returns.
- accumulates WASD-pan + rotate/tilt from DAT_142133xxx input flags.
- when following: resolves the object, getPosition, setPosition(center node
  +0x58) = character pos (+ offset). center = the look-at point.
- writes yaw(+0x18)=rot-delta, pitch(+0x1C)=rot-delta  <-- these are PER-FRAME
  DELTAS, ~0 at rest (explains the earlier 0.000 reading; NOT absolute angles).
- FUN_1406afee0 (0x6afee0) applies yaw/pitch to the camera NODE (+0x70) via
  Ogre::Node::yaw/pitch + DegreesToRadians (the tilt/orbit placement).
- cursor: GetCursorPos/SetCursorPos while rotating (drag-rotate).

M2 approach (built, awaiting test): Ogre is a SEPARATE DLL (OgreMain_x64.dll)
whose transform methods are EXPORTS — resolve by mangled name, no RVA needed:
  Node::_setDerivedPosition  ?_setDerivedPosition@Node@Ogre@@QEAAXAEBVVector3@2@@Z
  Node::_setDerivedOrientation ?_setDerivedOrientation@Node@Ogre@@QEAAXAEBVQuaternion@2@@Z
Each frame, AFTER the game's mainLoop (so after update() positioned the camera),
override the camera node (+0x70) WORLD transform: derived pos = charPos +
(0,EYE_HEIGHT,0); derived orientation = quat from mouse-look (v1: absolute
cursor pos -> yaw/pitch, read-only, no recenter). Ogre::Camera(+0x68) is
attached to that node so this drives the view. EYE_HEIGHT=1.7 provisional (tune).
OPEN for the test: does render pick up the override (timing vs update())? is the
look direction/handedness right? is EYE_HEIGHT sane? If the mainLoop-hook
timing loses to update(), escalate to a MinHook trampoline on update() 0x6b0f90.

### 2026-07-17 — M2 test #1: "camera teleports far away" + inverted yaw → FIXED
Cause of teleport: used Node::_setDerivedPosition(WORLD) with the char's GLOBAL
coords (-50978,...). But the camera node is a CHILD of `center` (which update()
already puts at the character), and/or Kenshi rebases the scene origin for its
huge world — so a global derived position flung the camera ~scene-away. FIX:
use LOCAL setters and a small offset relative to center:
  Node::setPosition   ?setPosition@Node@Ogre@@QEAAXAEBVVector3@2@@Z   (local)
  Node::setOrientation ?setOrientation@Node@Ogre@@QEAAXVQuaternion@2@@Z (local,
    16B Quaternion by value -> passed by pointer in MS x64, so (node,Quat*) ABI)
Camera node local pos = (0, EYE_HEIGHT, 0) above center = eye; no world coords.
Also user reported inverted left/right → negated the yaw mapping. Rebuilt.
Note _getDerivedPosition@Node returns Vector3 BY VALUE (?AV...) → ABI is
(retbuf RCX, this RDX); skipped it as a diagnostic to avoid ABI slips.

### 2026-07-17 — M2 polish + M3 WASD movement
M2 fixes shipped: yaw-roll (use Ogre Node::_setDerivedOrientation WORLD for the
look so parent center's orientation can't induce roll; position stays local),
relative mouse-look w/ SetCursorPos recenter + ShowCursor hide, EYE_HEIGHT 2.6.
Ogre get* accessors return BY VALUE and CRASH across our ABI — never call them;
only setters (void return) are safe.

M3: **Character::setDestination = RVA 0x5c84e0** (the PLAYER move-order path).
Found via KenshiCoop (g_charSetDestFn = KenshiLib::GetRealAddress(&Character::
setDestination), sig `void(Character* self, const Ogre::Vector3* pos, bool
shift)`); in 1.0.68 it's the only (this,Vec3*,bool) fn in the Character cluster
that is called from the right-click-move GUI handlers (FUN_140347950,
FUN_140358040) + AI (0x5f03c0/0x5f16a0/0x5f5d10). It writes dest Vec3 to
Character+0x48 and notifies the goal obj at Character+0x640 (vtable+0xc0) then
the movement path (Character+0x448). Sibling FUN_1405c8540 (0x5c8540) is the
bare movement-only variant (a player char ignores it — matches KenshiCoop).
WASD breadcrumbs setDestination(char, charPos + heading*MOVE_STEP, 0) at ~10Hz;
halt = setDestination(char, charPos) on release. Heading from mouse-look yaw.
Character::movement offset (per KenshiCoop c->movement) not needed — we use the
player path only. AWAITING test (movement works? forward/strafe sign correct?).

### Still TODO (find after boot-test confirms the instance)
- CameraClass::update RVA: instance global 0x2133310 has many readers; update
  takes `this` in RCX so update itself doesn't read the global — its per-frame
  CALLER does. Identify the caller among the 0x2133310 readers, or find
  followObject/rotate/teleport in the 0x6ADxxx–0x6B0xxx cluster (ctor moved
  header 0x6AF410 -> 0x6afbf0, ~+0x7e0, so the cluster shifted; not uniform).
  M1 camera lock can use CameraClass::followObject(hand) or write center-node
  pos each frame — both need the instance (have it) + one RVA.
- InputHandler `key` global: config method FUN_140362430 (0x362430) is
  vtable-dispatched (no call-xrefs). Best next anchor: whichever 0x2133310
  reader is CameraClass::update's caller also derefs `key` for the pan bools
  (+0xDB..0xDE). Only needed if Win32 GetAsyncKeyState proves unreliable under
  Proton — the stage-0 log's WASD field answers that.
- Character::setDestination RVA: no clean string (movement is Havok task-based:
  MoveTo_Addon, Task_MoveToDoor RTTI). Find via the right-click order path or
  by runtime-probing the Character vtable/methods once we have a live Character.

### 2026-07-17 late — 0x5c84e0 CORRECTED + real order machinery (agent digs)
**0x5c84e0 is NOT Character::setDestination.** Full decompile: 3 unconditional
stmts — copy pos to char+0x48; call CharMovement(char+0x640) vt+0xC0 =
_setPositionDirectionAndTeleport(pos, dir); update render obj (char+0x448) via
thunk_FUN_1405b1a30. 3rd arg = Ogre::Quaternion* FACING (w,x,y,z floats; NULL
crashes = 16B read; zeroed = degenerate quat). It ALWAYS teleports (that's its
job: placement). Its "handler" callers 0x347950/0x358040 are begin-callbacks of
play-anim-at-position orders (bed/furniture snap; order+0x78 anim name string,
+0xa4 snap pos, +0xb0 facing quat), registered in an .rdata order-descriptor
table (0x192ebd0..). KenshiCoop's ID was wrong for 1.0.68.
**Real order injection**: Character+0x650 -> +0x20 = order queue.
FUN_1405c8da0(char, int orderType, hand* tgt, u8, char, x) wraps
FUN_1405086d0(queue, orderType, hand* tgt, Vec3* pos, char asJob) -> looks up
descriptor map DAT_141ce90f0, creates order via FUN_14032ebd0(factory@
queue[0x37]+0x2a8, type, tgt, 3, 1.0f, pos, 0, 100), appends to current-orders
or jobs. Missing: plain move-to-point orderType id (0x1f/0x2d are the anim-jobs;
0x1f remaps 0x121 when char->vt+0x248 non-null). Dig in flight.
**Terrain (Plugin_Terrain_x64.dll)**: Terrain* singleton = *(exeBase+0x2133318).
Exports: ?getHeight@Terrain@@QEBA?AUHit@1@AEBVVector3@Ogre@@@Z (DLL RVA
0x132b0), ?intersect@...Ray... (0x134e0), getApproximateHeight (0x133f0). Hit
struct 0x1C: +0 u8 hit, +4 Vec3 position, +0x10 Vec3 normal. ABI this=RCX,
retbuf=RDX, arg=R8. Pure const queries, main-thread. Right-click pick flow:
FUN_140800250 (0x800250, per-frame mouse pick) builds cursor ray ->
Terrain::intersect -> hit.position -> event 0x1d to selected chars (writes
order+0xa4); no persistent cursor-world-pos global.
**Ghidra toolchain**: project DB upgraded to format 75 — use
~/.local/opt/ghidra_12.1.2_PUBLIC (11.3.2 can no longer open it). New scripts in
../KenshiMP/re/scripts: Dump/Callers/Strs/PtrScan/Ptr4/RdData/HexDmp.java.

### Move order SOLVED: Character::moveToPosition = RVA 0x5d22b0 (vt +0x318)
Signature: void(Character* ch, void* clickedObj, void* targetObj, Vec3* pos);
(NULL,NULL,pos) = plain ground walk. Issues Task_Move (orderType 0x1d) via
FUN_1405d20d0 -> queue append; if current task already Task_Move it LIVE-UPDATES
task+0x58 dest Vec3 (the drag-move path) — per-frame calls are exactly "hold
right-click". Never refused by the order validator (no 0x1d case). Right-click
GUI dispatcher = FUN_1407f9e20 (0x7f9e20; scatter for multi-select there, not in
moveToPosition). Chains: mind=*(ch+0x650); queue=*(mind+0x20); dest cache
mind+0x2c0. Cancel: FUN_1405074a0(queue) abort in-flight + clear queued;
FUN_140507530(queue) clear + reset target hand. Replace-vs-queue global shift
flag byte @0x2133449 (0=replace). Main thread only. CLIENT: try_move_to_pos()
(VEH-guarded) is now the primary WASD drive; raw CharMovement setdest = fallback.

### RE_Kenshi incompatibility ROOT CAUSE (2026-07-18, user Claviberg)
RE_Kenshi 0.3.4 does NOT hook our functions and canNOT collide with our MinHook
(module-private state, disjoint targets -- confirmed by source analysis). The
real cause: RE_Kenshi's dllStartPlugin does a VERSION-GATED _P_OVERLAY process
restart (dllmain.cpp:1971-1994) into its BUNDLED exe `./RE_Kenshi/kenshi_x64.exe`
when KenshiLib doesn't recognise the installed version. So with RE_Kenshi on,
the running process is a DIFFERENT (older, bundled) Kenshi build -> our hardcoded
1.0.68 RVAs point at the wrong bytes. PROVEN by Claviberg's diagnostic:
running exe = ...\Kenshi\RE_Kenshi\kenshi_x64.exe; bytes @0x788a00 = CC CC CC...
(INT3 PADDING, not a function) vs real 1.0.68 = 48 8b c4 56 57 41 54 48.
Real 1.0.68 signatures: mainLoop@0x788a00 = 48 8b c4 56 57 41 54 48;
CameraClass::update@0x6b0f90 = 40 55 53 57 48 8b ec 48.
FIX shipped: prologue-signature check at load; on mismatch, DISABLE cleanly with
a clear log message (no dead hooks, no watchdog spam). True coexistence would
need version-independent addressing (signature-scan every fn + globals) OR
RE_Kenshi supporting 1.0.68 natively (no downgrade). RE_Kenshi's own per-frame
anchor = MyGUI::Gui::eventFrameStart (additive delegate, no byte patching).

### 2026-07-31 — FALLING SOLVED: the real ragdoll machinery (1.0.65 RVAs, 1.0.68 twins)
The old "ragdollMode" (1.0.65 0x5cb500, once tabled as RAGDOLL_MODE) is NOT the
ragdoll switch — full decompile shows it only drops carried items (weapon/shield
slot strings) + pokes the physics wake queue. The REAL machinery:
- **Character::setRagdoll = 0x5d0320 (1.0.68: 0x5d0db0)** — virtual (vtable slot in
  .data @0x2185fe0). Sig: `(Character* this, struct{char on; u32 partsMask}* req)`.
  On enter (mask bit0 | bit11): drops weapons, halts movement, cancels orders,
  **INVALIDATE_PATH (0x65f3b0) destroys the +0x320 mover**, picks the
  "male ragdoll"/"female ragdoll" template by AppearanceHuman+0x140, then calls
  AnimationClass vt+0x50(anim, on, &vel, mask, template, character) where
  **vel = CharMovement currentMotion(+0xA8)** — the ragdoll inherits the mover's
  velocity (that's how combat knock-offs carry momentum) — and wakes physics
  (FUN_14052b110(anim+0xE8)).
- **Character::ragdollQueued = 0x5cb2d0 (1.0.68: 0x5cbd60)** — the gameplay API:
  `(this, char on, int mask)`; dedups + queues {on,mask} into the request deque at
  **char+0x3E0** (count +0x400), pumped by Character::update via 0x5d21a0.
  mask 1 = whole body (plays "VO_Creature_Die" for creatures), **0x800 = knockout**.
- **Character::stopRagdoll = 0x5d2290 (1.0.68: 0x5d2d20)** — `(this, char immediate)`:
  {off, 0x8000 = all parts}, applied or queued.
- **Character::setUnconscious = 0x5cdf30 (1.0.68: 0x5ce9c0)** — `(this, char on)`:
  KO enter (queue {1,0x800} + full stand-down) / exit (queue off + get-up anim
  0x5c7b00 + **CharMovement::createMover**).
- **CharMovement::createMover = 0x661500 (1.0.68: 0x661f90)** — rebuilds the +0x320
  physics mover at the char's current pos (_aligned_malloc(400) + "pathfind
  footprint radius"/"pathfind acceleration" gamedata); idempotent (+0x320==0 check).
  NOTE: plain setRagdoll(off) does NOT rebuild the mover — only the KO-exit does;
  the client restores it after a fall if the game didn't.
- **Auto get-up**: ScytheRagdollPhysicsT (vtable 0x1717298, 16 slots, fns
  0x7d0c20..0x7e9a70) slot 15 = 0x7d2a20 is the SETTLE callback — when the body
  comes to rest it calls stopRagdoll itself. Char+0x2f8 (int) = down/life state.
- **GROUND_NOHIT 1.0.68 = 0x168bda0** (DAT_14168bda0; no-hit branch of the inner
  groundAt raycast FUN_1409b39d0; 1.0.65 twin 0x168ada0 @site 0x9b2420).
- anim ragdoll-parts mask stays anim+0x2F8 (u32, !=0 = down) — matches the client.
Client (task #19 v2): fp_fall_update edge-probe -> seed currentMotion with the
launch velocity -> ragdollQueued(pc,1,1) -> monitor mask -> settle -> stopRagdoll
(queued) -> restore mover if missing. Kinematic integrator kept as fallback for
builds where the ragdoll sigs don't resolve. All five new sigs verified UNIQUE in
both 1.0.65 and 1.0.68 (see re_plugin/rva_sigs.h).

### 2026-07-31 (cont.) — tiered falling: walk-off vs ragdoll dive
User feedback: full ragdoll + get-up on every small drop feels wrong. v3 tiers:
- **Walk-off tier** (drop < fall_soft): integrate the gravity arc ourselves and move
  the character each frame through **CHAR_SETDEST = the teleport+facing placement
  (1.0.68 0x5c84e0 -> 1.0.65 0x5c7a50, unique sig match)** — it moves the LOGICAL
  position AND the physics mover (CharMovement vt+0xC0 _setPositionDirectionAndTeleport),
  so nothing snaps back to the lip. No ragdoll -> animations keep playing, NO get-up.
  ABI: (Character*, Vec3* pos, Quaternion* facing[w,x,y,z], non-NULL).
- **Ragdoll tier** (drop >= fall_soft, or a walk-off airborne > fall_air seconds ->
  mid-air escalation with the current fall velocity): full vanilla ragdoll as before.
- FALL_LAUNCH_HOLD in the charmove hook: while a ragdoll request is QUEUED, re-assert
  the launch velocity in currentMotion(+0xA8) before AND after the original update —
  stalled-at-the-lip state otherwise zeroes it before the queue pump copies it into
  the ragdoll (symptom: body crumples in place on the ledge instead of diving).

### 2026-07-31 — head-covering GEAR hide (companion to the head-mesh hide)
Hiding the head mesh (hiddenMask bit 9) leaves worn head gear floating where the head
was. Worn items are separate Ogre entities on the AppearanceHuman; hide them too.

Ground truth = **1.0.65 FUN_140537200** (vanilla "a hat hides your hair/beard"),
decompiled. It walks the worn-item map and calls
`Ogre::MovableObject::setVisible(*(MovableObject**)(item+0x80), vis)` — so entity
setVisible IS the working lever for worn ITEMS (unlike the BODY entity at app+0xd8,
which ignores it).

Container layout (custom Ogre-allocator hash map; ONE intrusive node list whose head
lives in the sentinel bucket slot `buckets[bucketCount]`):
```
app+0x28 = bucketCount   app+0x30 = elementCount   app+0x48 = void** buckets
head = buckets[bucketCount]      (only valid when elementCount != 0)
node+0x00 next | node+0x10 key std::string (MSVC SSO; len +0x20, cap +0x28)
node+0x38 value            (Item* here; int in the GameData int-map)
item+0x78 = GameData*      item+0x80 = Ogre::MovableObject* (NULL = game destroyed it,
                                       which is how vanilla hides hair/beard under a hat)
gd+0xf8  = GameData BOOL map ("hide hair", "hide beard")
gd+0x178 = GameData INT  map ("attach slot")
app+0x181 = vanilla "headwear is hidden" flag (FUN_140537200 writes it)
```
AttachSlot (fcs_enums.def): WEAPON 0, BACK 1, HAIR 2, HAT 3, EYES 4, BODY 5, LEGS 6,
NONE 7, SHIRT 8, BOOTS 9, GLOVES 10, NECK 11, BACKPACK 12, BEARD 13, BELT 14.

Map lookup: vanilla uses the map's `operator[]` — **1.0.65 0x6cef0 / 1.0.68 0x6cf30**
(reached via a jmp thunk; Ghidra shows `thunk_FUN_14006cef0`). RVAs verified: the
prologue byte-matches at exactly 7 sites in each build, in the same order and at a
uniform +0x40 1.0.65->1.0.68 delta (0x6c780/0x6c7c0 is the sibling BOOL-map operator[]
used for "hide hair"). **The client does NOT call it**: (a) operator[] INSERTS on a
miss (allocates a 0x40 node through Ogre's pooling allocator and mutates the map),
(b) the 7 instantiations are byte-identical so it can never be signature-scanned for
the RE_Kenshi build. `gd_int_field()` walks the node list read-only instead — no
build-specific address needed, no state perturbation.

Client: `headgear_set_hidden()` / `headgear_apply()` (own VEH guard + `g_gear_dead`
latch), driven from `set_head_disabled()` and re-asserted in `hooked_update_hidden`.
ini: `hide_headgear` (default 1), `headgear_slots` (default 0x201C = HAIR|HAT|EYES|BEARD).

### 2026-08-01 — floating status UI (ScreenLabel / FloatingProgressBar) → crosshair
The overhead "Failed"/"Success"/lockpick-% UI is NOT world-space 3D: it's 2D MyGUI
widgets that a per-frame sweep positions by projecting a tracked world position.
Class family (RTTI, all `ScreenLabelInterface` subclasses; 1.0.68 RVAs):

```
ScreenLabelInterface  vft 0x1703920  (ctor 0x6f0ce0)
ScreenLabel           vft 0x1703d28  ctor 0x6e3a10  update vt[1] -> 0x6ea9f0
ScreenLabelDebug      (ScreenLabel subclass, ctor 0x6e3b90, "debug_marker")
FloatingProgressBar   vft 0x1703de0  ctor 0x6eaf00  update vt[1] -> 0x6e87c0
CharacterNameTag      vft 0x1703950  ctor 0x6eadc0  update vt[1] -> 0x6e8100
InfoText              vft 0x1703f00  ctor 0x6e88c0  (singleton DAT_142132a70; Ogre
                      FrameListener multi-line rising text panel — NOT the statuses)
```

Global label lektor `DAT_142133a20` {cap+0xC count+0x8 data+0x10} under mutex
`DAT_1421339e8`; expiry pushes onto a DEAD lektor `DAT_142133a38` + flag label+0x9c
(deferred free -> post-orig hook access is safe). Shared world->screen projection
helper `FUN_1409b33f0(&DAT_142135b70, Vec3*, float* outX, float* outY)`.

**ScreenLabel** (0xa0 bytes): ctor(text, ColourValue*, u32, int styleIdx).
+0x08 visible | +0x0C Vec3 anchor (absolute, or offset when hand valid) | +0x18
textChanged | +0x20 std::string text (size +0x30, cap +0x38) | +0x50 ColourValue |
+0x60 rise speed (from DAT_141f1fb48[styleIdx]) | +0x64 age | +0x68 font-colour idx
(DAT_141f29a40 + idx*0x28) | +0x70 hand (type dword +0x78; 0xb = none -> absolute
anchor) | +0x48 TextBox* (lazy; skin Kenshi_TextboxStandardText, layer "Dialog").
Factory FUN_14073faf0 (thunk 0x3073d). Spawn sites incl. FUN_140359160 ("Pick
failed"/"Pick success!"), FUN_14034cd80 ("Failed!"/"*Thunk*"/" (No XP)"),
FUN_1403567a0 ("Shackles broken!"/"*Crunck*"), FUN_140680560 ("Free!"), damage
floaters (digit-leading text).

**FloatingProgressBar** (0x58 bytes): +0x08 visible (ANDed with global
DAT_142133ae0) | +0x0C Vec3 anchor (task->getPosition(), set via vt+0x18) | +0x20
std::string label ("Lockpicking (Chance {1}%)" @1.0.65 str 0x16bf500) | +0x48 int
progress (MyGUI::ProgressBar::setProgressPosition) | +0x50 widget wrapper (0xb0
bytes; real Widget* at +0x8, ProgressBar sub at +0xa0). Factory FUN_14073fab0;
SINGLE creation site FUN_140331ca0 (job-task start).

**Client**: `hooked_slabel_update` / `hooked_pbar_update` (post-orig re-pin near the
crosshair, hand-match or 2.5m-proximity gate, digit-leading text excluded), fields
SLABEL_UPDATE / PBAR_UPDATE. 1.0.65 RVAs via RTTI walk on the exe file
(re/scripts + scratch rtti_walk.py): update = 0x6ea250 / 0x6e8020. Sigs verified
unique in BOTH builds (SigCount.java); rip disps wildcarded -> GOG-safe.

### 2026-08-01 — PRISONER CAGE facing lock SOLVED (why you're stuck facing backwards)
Symptom: caged in FP, body frozen at an arbitrary yaw ("backwards"), TIP can't turn
it. Root cause chain (all decomp-verified, 1.0.68):
- **Character::putInCage = 0x330600** `(Character*, char on, Cage*)`. ON path: sets
  inSomething(+0x2F8)=2, reads cage gamedata bool **"restrains movement"** -> mind
  lock FUN_14060e840(mind, restrains?0x10:4), stopRagdoll, teleports via CharMovement
  **vt+0xB8 (pos, 0xffffffff) — position only, NO facing** — and does NOT rebuild the
  +0x320 mover. OFF path clears the locks and calls **createMover(0x661f90)**: the
  engine deliberately runs caged characters MOVER-LESS (the KO that preceded caging
  destroyed the mover via INVALIDATE_PATH and nothing rebuilds it until release).
- **Facing pipeline**: faceDirection(0x665250) only stores+normalises mv+0xD0. Its ONLY
  consumer is CharMovement::update(0x65ffa0) -> AnimationClass::setPositionAndDirection
  (0x5b18f0), which rebuilds **anim+0x78 desiredOrientation** (gated on anim+0x88
  isActivated && anim+0xA8 body != NULL — KenshiLib field names). The node is applied by
  **AnimationClass::rotationUpdate = 0x5b24e0** (vt+0x40, from AnimationClass::update
  0x5b68c0): slerps node(+0xB0) toward desiredOrientation at a capped rate; SNAPS
  instantly when ragdolled or char inSomething==1 (bed).
- **Mover NULL -> update returns on line 1 -> +0xD0 never reaches desiredOrientation ->
  facing frozen forever** (same trap as "destroying the mover froze facing").
- RVA mapping trick that found rotationUpdate: KenshiLib header RVA − 0x310 ≈ 1.0.65,
  + 0xA90 ≈ 1.0.68 (AnimationClass region).
Client fix v1 (direct ANIM_SETPOSDIR feed, REVERTED): fed the facing straight into
setPositionAndDirection each idle frame. IN-GAME TEST (1.0.65 RE build) NEGATIVE:
the feed ran ([cage] LIVE in the log, TIP turning fired) but the body still did not
rotate — the cage anim-job holds orientation deeper than desiredOrientation (either
the 1.0.65 rotationUpdate gates differ or the job re-snaps the node after anim
update). Not worth fighting.
Client fix v2 (full stand-down: fp_movement early-return + loco gate on
inSomething==2) ALSO REVERTED same day: with the flag still 2 after the cage
session (and/or user confusion with loco disabled via F10 meanwhile), locomotion +
turn-in-place appeared broken in normal play. ALL cage-specific client code is
removed again — behavior is back to pre-investigation (frozen facing while caged).
If revisited: verify when the engine actually clears inSomething after release,
and gate ONLY the WASD/order spam, never the loco system.

### 2026-08-24 — own hair/facial hair in FP + bone-scale head-hide attempt (REVERTED)
Bone-scale head hide (smokefoo Direct-Control recipe: OldBone::setManuallyControlled(1)
+ setScale 0.001, latch once, skeleton-rebuild re-latch) was implemented, field-tested,
and judged WORSE than the hiddenMask method by the user — reverted the same day. The
hiddenMask shader-constant method (+ painted part-map textures) stays the shipping one.
Do not retry bone scaling without new evidence; this is the SECOND rejected bone-side
approach (disableBone froze the welded camera; scale+manual tested worse in play).

Why hair/beard survived the head hide: the worn-item map on AppearanceHuman also holds
the character's OWN hair and facial-hair entities, but hairstyles are appearance picks
(hair/beard GameData), NOT items — their GameData has no "attach slot" int field, so
headgear_set_hidden skipped them (log: `NO "attach slot" field (skipped)` — exactly the
meshes left floating at the camera). Fix: a live-mesh map entry WITHOUT "attach slot"
is now classified as own hair/beard and hidden with the gear (restored from g_gear_hid
as usual); the one-shot log now prints the map-node KEY for each hide so the next field
log can verify what the no-slot entries actually are.

### 2026-08-24 (later) — no-slot heuristic WRONG; facial hair survives entity hide
Field log falsified the previous entry: the worn-item map is keyed by attachment-slot
NAME, and the no-slot entries were key="legs" and key="hip" (clothing — the heuristic
hid the character's pants in FP). Meanwhile key="hair" (slot 2) and key="beard"
(slot 13) WERE setVisible(0)'d in the same pass — yet the user still sees facial
hair. So the visible facial hair is NOT (only) the map's "beard" entity: either the
game re-shows/re-creates it through a path that never calls updateHiddenParts, or a
second renderable draws it (hair/beard meshes ship with own .skeleton + .phs physics
— a physics-driven renderable may not respect the entity's mVisible).
Current build (diagnostic + self-healing):
- classification by map KEY (hair/beard/hat/eyes/face) only when the GameData has no
  "attach slot"; slotted entries still follow headgear_slots. legs/hip never hidden.
- gear hide re-asserted EVERY FRAME while head-hidden (walk is ~4 nodes);
- MovableObject::getVisible diffed against the previous pass's hidden list; up to 12
  "[head] REASSERT key=... knownMesh=%d visible=%d" lines show WHAT the game undid.
Next-log reading: REASSERT lines with visible=1 => game flips mVisible back (per-frame
re-assert cures it). No REASSERT lines but beard still visible => a different
renderable draws it (RE hunt: hair physics / .phs object, not item+0x80).

### 2026-08-24 — near-field grass flicker in FP: near_clip, not camera churn
Symptom: near grass blinking in/out every frame in FP while moving the camera.
Camera-oscillation theory DISPROVED by a 600-frame per-frame trace ([fol2], since
removed): the game's pre-override camera, our eye, and the center node all march
smoothly (gap 3-13u, zero direction flips) — no per-frame position churn reaches
the foliage system.
Root cause (user-found, field-verified): the FP near-clip setting. At the old F10
slider minimum 0.05 (displays as "0") the near plane degenerates against Kenshi's
huge far plane and the terrain plugin's grass culling/LOD becomes unstable ->
per-frame blink. near_clip=1.0 is clean. Fix: floor raised to 0.5 in BOTH the F10
slider min and the ini clamp (sub-0.5 ini values are rejected -> default 1.0).
If grass flicker ever reports again, check the effective near clip FIRST.

### 2026-08-24 — FP JUMP (task #20): spacebar jump + vanilla-pause swallow
- **setPause(GameWorld*, char) decomp-confirmed as the pause mechanism**: it
  stashes/restores frameSpeedMult(gw+0x700) through a saved-speed global (+ a
  "saved" bit). So paused == framespeed 0.0 exactly -- pause DETECTION needs no
  new offsets, just the existing GW_FRAMESPEED read.
- **RVA transplant**: setPause 1.0.68 0x787fb0 -> 1.0.65 **0x787470** (26-byte
  masked prologue `48 89 5C 24 10 48 89 6C 24 18 48 89 74 24 20 57 48 83 EC 30
  8B 05 ?? ?? ?? ?? 0F 29 74 24 20`, unique in BOTH exes; script preserved as
  scratchpad transplant_setpause.py, field added to tools/transplant_rvas.py).
  GOG tables: 0 (no GOG exes on hand) -- jump works there, only the pause
  swallow degrades; regenerate via transplant_rvas.py when a GOG exe is around.
- **Jump = walk-off arc with upward launch**: fp_fall_update consumes a
  space-press posted by the mainloop hook (g_jump_fire_req, 4-frame expiry so a
  mid-air tap can't queue a takeoff), fires g_fall_active with vy=+jump_vel and
  WASD momentum carry. Landing grace gets `g_fall_jump && vy<0` (flat hops land
  on START-height ground, which the lip grace would hold airborne); jumps
  self-fund 2*vel/g of fall_air budget so hopping off a porch doesn't KO; jump
  landings re-arm in 0.25s (vs 0.8s for edge falls).
- **Pause swallow** (fp_jump_pause_guard, mainloop hook): on every FP space
  press (no UI open) arm a 0.4s window; if framespeed reads 0.0 inside it,
  setPause(gw,0) restores the stashed speed -- the pause lives <1 frame.
  Presses with UI open, or while already paused (vanilla toggle UNpauses,
  which a jump wants anyway), are left alone. ini: jump/jump_vel/key_jump.
- **Amendment (same day)**: pause is a REBIND, not a removal -- key_pause
  (default P, ini-configurable, 0=off) toggles pause in FP via the same
  setPause; the space-swallow window tightened 0.4s -> 0.15s and the P toggle
  cancels it, so deliberate pauses can never be eaten. Outside FP the vanilla
  spacebar pause is untouched.
- **Amendment 2 (pause SOUND)**: the after-the-fact setPause revert could not
  silence the pause toggle's UI click. Solved at the SOURCE: RTTI walk found
  **.?AVMainListener@@** (the game's OIS listener; FrameListener primary +
  Key/Mouse/JoyStick sub-vtables at +0x8..+0x20). KeyListener sub-vtable =
  +0x20 (3 slots: dtor thunk, keyPressed, keyReleased). **keyPressed =
  1.0.68 0x82b010 / 1.0.65 0x82a460** (transplant AND vtable-slot resolve
  agree; keycode read at evt+0x10, DIK codes; keyReleased 0x82b6e0-family
  /0x82a580). Command registration decomped: "pause" default-binds KC_SPACE
  0x39 (fn ~0x364540, addCommand(name, id 0x12, key 0x39)). Hook swallows the
  jump key's keydown (VK->DIK via MapVirtualKeyA) in FP before dispatch: no
  pause, no sound, mirrors untouched for releases. setPause revert kept as a
  backstop; the paused-frame fire race also disappears with the event gone.
- **Amendment 3 (jump facing + air pose)**: (a) jump fire now derives the arc's
  render facing AND the landing quat from **g_face_yaw** (the TIP state
  machine's committed body yaw; g_face_dir refreshed at fire) -- previously the
  arc rendered a STALE g_face_dir (only written while moving), so an idle
  turn-in-place then jump faced the old direction; movement heading is still
  used only for the momentum carry (a backpedal jump must not land facing away).
  (b) **Destreza AirPose ported** into kfp_locomotion.h: while g_fall_active,
  ground foot-IK is off and each leg two-bone-solves its ankle UP toward the
  body by tuck * 0.40 * (thigh+calf), tuck = 0.85*max(0,1-|vy|/jump_vel)
  (client-fed via g_loco_in_air/g_loco_in_airtuck): zero at takeoff, peak at
  apex, zero into the landing so the legs extend to meet the ground and the
  existing landing absorb takes over. Airborne also claims legs+core ownership
  and blocks new TIP steps. No jump clips exist in the Destreza export (checked
  anims.json/anims_combat.json: 26 loco + 50 combat clips) -- Destreza's own
  jump is exactly this procedural pose, so this IS the faithful port.
- **Amendment 4 (three fixes from the 07:4x field log)**:
  (1) air tuck never ran on jumps ([air] fired exactly once/session): the
  fp_movement fall standdown cleared **g_face_have** every arc frame ->
  g_loco_in_havebody died -> airActive died. Facing state is now cleared only
  for the RAGDOLL tiers (tumble = yaw unknown); walk-off/jump arcs keep it.
  (2) jump landing re-arm 0.25s -> **0.05s** (CS-style: effectively no lockout).
  (3) "camera flies away after unwalkable-slope landings" ROOT-CAUSED: the
  landing teleport makes the vanilla center node snap-catch-up over SEVERAL
  frames at 200-300u each (log 07:44:53: tx +285,+283,+70 right after a
  19-unit slope landing = T corrupted by ~+638; eye then ~640u off the body
  for the whole 8s downhill slide, idle recalibration never ran while
  sliding). The 1-frame prevraw reset only skipped the first snap frame. Fix:
  **g_rebase_hold_t = 1.0s** post-landing holdoff on the rebase detector (all
  6 fall-end sites + char swap); real rebases missed in the window repair at
  the next idle recalibration as ever; rebase shifts now logged ([weld]).
- **Amendment 5 (landing squash/pre-plant + hand-back gap)**:
  (a) NEW landing-anticipation channel g_fall_airland/g_loco_in_airland: 0->1
  over the last 0.25s of a descent (time-to-impact from the integrator). It
  re-engages the plant IK while STILL AIRBORNE -- targets are ground-relative
  by design (gRef cancellation), so the legs pre-SHAPE to the landing surface
  (slope stance, per-foot deltas) at neutral extension rather than stretching;
  g_ik_w warms during the approach, so touchdown lands planted instead of
  neutral-then-correct one tick later. The air tuck fades across airland
  0..0.5 and hands the legs over at 0.5; the pelvis straddle drop stays 0
  while airborne (both feet read as floating -> would deep-squat pre-contact)
  and forms at touchdown UNDER the impact dip = the squash.
  (b) landing HAND-BACK GAP: fp_movement re-arms only next mainloop pass; on
  the landing tick the orig update's combat auto-face won ("jump while fleeing
  = 1-frame turn toward attackers"). Fixed: the soft-landing branch re-arms
  g_face_active immediately (g_face_dir still holds the arc facing), so the
  post-orig facing re-feed wins every gap frame.
- **Amendment 6 (surf-slope jumps)**: on unwalkable slopes the capsule rides
  7-14 units ABOVE the down-ray's surface reading (11:23 log: y-gh up to 13.9
  while in sliding contact), so the jump's ground gate (y-gh < 2.5) refused
  every slide jump. Widened to 18: ray-blind platform towns (the gate's real
  target) read 100s of units of air below, so the separation is clean. Slide
  jumps ("surf hops") now fire.

### 2026-08-24 — grass system RE (near-field flicker, reproduces in VANILLA at ground level)
User-confirmed: the flicker is NOT ours — vanilla Kenshi with the RTS camera zoomed
to ground level shows the same near-field grass blinking. Camera height/pitch is the
only variable. RE of the grass stack (1.0.68 RVAs, shared KenshiMP Ghidra project):
- Kenshi grass/trees = **PagedGeometry (namespace Forests), statically linked in the
  main exe**; a custom FoliageSystem manages layers ("grass" vs "meshes"; impostors
  under data/impostors/). Setup: FUN_1406d3e30 (reads GameData "grass"/"meshes"/
  "visibility range"; global range scale DAT_1421334bc).
- PagedGeometry::update = **FUN_140a2ad10** (getMilliseconds, camera-node
  _getDerivedPosition, camSpeed, per-manager FUN_140a2c100, then Kenshi extra:
  Camera::getDerivedDirection -> FUN_140a4fb40 = "preRotatedQuad[0..3]"/"uScroll"
  sprite-billboard shader params, gated on DAT_142136014).
- Per-frame glue: **FUN_1406cc470** loops PagedGeometry* array (+0x18, count +0x10).
- GeometryPageManager::update = FUN_140a2c100: STOCK logic, scrolling page grid
  (FUN_140a2ead0), pure 2D X/Z distances, no camera-Y use, no frustum tests;
  setVisible/setFade only on state TRANSITIONS (cached) -> cannot blink per frame.
- GrassLoader vtable 0x174dcd8: loadPage 0xa3b6b0, unloadPage 0xa3bc90,
  frameUpdate 0xa3b1d0 (wind "time"/"frequency" per layer). GrassPage vtable
  0x1702778: **setFade (vt5=0x6e0120) and update (vt7=0x6cb3f0) are EMPTY Kenshi
  stubs** — no page-level fade exists; setVisible = 0xa44640 (forwards to
  contained objects' vt+0xC0).
- The actual "fade" = **data/materials/deferred/foliage.hlsl grass_vs**: blades
  SINK INTO THE GROUND by `position.y -= grassHeight * clamp(5*dist/(fadeRange*20)
  - 4, 0, 1)` with `dist = distance(camPos.xz, iPosition.xz)`; camPos =
  param_named_auto **camera_position_object_space** (per-batch object space — a
  batch re-anchor makes the input jump), fadeRange from layer "visibility range".
DIAGNOSTIC deployed: growth line commented out in foliage.hlsl (backup:
foliage.hlsl.kfp-bak) + RE_Kenshi/shader_cache.sc set aside (.kfp-bak) so the edit
actually compiles. Flicker gone with growth off => sink mechanic/camPos input is
the culprit (fix candidates: clamp the sink for near dist in shader — shippable as
a data override; or stabilize what camPos sees). Flicker persists => batch-level
culling next (hook GrassPage::setVisible 0xa44640 + grid scroll 0xa2ead0; NB
1.0.68 RVAs — resolve 1.0.65/GOG equivalents via kenshi_1065.exe in the project).
- **Amendment 7 (mid-air body turn)**: the arc facing was frozen at fire time.
  Now every airborne tick (FP on) glues facing to the camera yaw and updates
  ALL consumers together: g_face_dir (render feed), g_fall_qw/qy (landing
  teleport quat), g_face_yaw/g_face_have (loco body yaw -> blendspace/aim/tuck
  frame + TIP locks), so the body rotates with the camera in flight like a
  standard FP controller and lands facing where you look.
- **Amendment 8 (legs vs mid-air turn)**: the TIP counter-rotation held the leg
  bones at the old WORLD yaw while the body turned with the camera in flight
  (its job when standing -- planted feet must not swivel). Airborne now:
  tipActive off, locks glued to bodyYaw each frame (fade unwinds toward zero
  error, not a stale lock), stepping cancelled -- legs rotate with the body;
  landing starts with feet aligned to the new facing.

### 2026-08-24 — GENERAL ENGINE RAYCAST FOUND (task #21: arc collision)
**RVA_RAYCAST = 1.0.68 0x9b39d0 / 1.0.65 0x9b2b00** (sig-transplant, identical
prologue, matches the region's -0xED0 delta). Decomp: GROUND_AT (0x9b3ee0) is a
thin wrapper: mask = 0x200 or 0x88200 (flag3), |4 (inclObjects), dir = STATIC
DOWN vec3 global, then calls this. Signature:
  raycast(Vec3* outHit, const Vec3* origin, const Vec3* dir, u32 mask)
- normalizes dir internally; scene = [rip global]+0xE8, virtual castRay vt+0x380
  (r8d=3, huge baked max-dist, filter -1);
- outHit = hit POINT; on miss ALL THREE components = the GROUND_NOHIT sentinel
  (the miss constant literally resolves to DAT_GROUND_NOHIT).
- 0x88200 is a SUPERSET of 0x200, so mask 0x88204 covers the fall system's
  whole two-channel union in ONE call.
Client: fall_ray()/fall_sweep_blocked() + arc collision in the integrator:
per-tick horizontal sweep at shin+chest height (body height live from
g_head_above), axis-decomposed slide on block (graze = slide along wall,
head-on = stop + drop), up-ray ceiling bonk (vy->0) while rising. GOG: 0 (no
exe to transplant; arc collision off there). This raycast is THE primitive for
any future line-of-sight / projectile / camera-collision work.
- **Amendment 9 (rock/landscape phasing ROOT-CAUSED by dual-mask telemetry)**:
  rocks/props ARE in the ray scene but OUTSIDE mask 0x88204 (log: d88=204.8
  while dALL=2.2 at a rock face). The everything-mask 0xffffffff does NOT
  self-hit (dALL=-1 in open air) so it is safe. Changes: sweep + ceiling rays
  now wide-mask; the landing gnd merges a wide-mask down sample (arcs land ON
  rock tops instead of through them); NEW slope-anticipation probe one capsule
  radius (2.5u) ahead along the motion -- the center down-ray reads
  ~r*tan(slope) BELOW the capsule contact on steep faces (= "dip into the
  landscape then phase" on unwalkable slopes). [rdbg] nearbits channel probe
  logs which single mask bits carry a near obstacle, to later replace
  0xffffffff with a precise mask.
- **Amendment 10 (REGRESSION + hard rule)**: the wide-mask LANDING merge from
  amendment 9 corrupted world state (21:53 log): landing teleport-commits the
  char, and committing onto a surface the ENGINE doesn't consider standable
  (rock tops / prop shapes) leaves the mover resolved under/inside the mesh --
  ground queries then start underground and the next arc free-fell 13+ seconds
  through the world. **RULE: wide-mask raycasts are for BLOCKING only (sweep +
  ceiling); LANDING surfaces must come from the engine ground query (GROUND_AT
  masks), full stop.** Landing reverted to engine-ground; slope-anticipation
  ahead-probe kept but fall_ground-only (terrain slopes ARE engine ground).
  NEW tunnel-abort: >80 units fallen with gnd nohit for >0.6s = inside
  collision -> teleport back to the takeoff point (g_fall_startx/z), never
  free-fall through the world again.
- **Amendment 11 (self-hit + hillside veto)**: (a) "jumps restricted / not in
  facing direction" = the wide sweep SELF-HIT: nearbits probe showed mask bit
  0x1 returns a surface at d=0.0 (own character / dynamic channel) -- blocking
  rays now use 0xfffffffe. (b) The unwalkable-slope dip-through mechanism
  finally pinned: the capsule rides up to ~14u above the ray surface there, so
  ONE uphill tick puts the arc BELOW the next column's surface = blind to all
  rays (sweeps read -1 from inside the mesh; the sweep cannot see interior
  faces). Fix = TERRAIN-WALL / RAY-BLIND HORIZONTAL VETO: refuse the
  horizontal advance whenever the destination column's engine ground reads
  above the feet (+2.5) OR reads nothing while the previous column was
  readable; fall the readable column instead ([fall] hillside veto log). Gap
  jumps unaffected (void columns still read the floor far below). Tunnel-abort
  remains the last-resort net.

### 2026-08-24 (cont.) — grass flicker: isolation matrix + static-bounds experiment
Field isolation (decisive): flicker triggers on MOUSE-LOOK ONLY. Perfectly still =
clean; W-only translation = clean; rotation = flicker. Mid+far field affected too.
EXONERATED so far: FP camera (vanilla ground repro), near-clip/FOV values AND
their per-frame writes, grass growth shader (sink line compiled out, no change),
screen-space interiorClip mask (neutralized keeping register allocation -- NB the
v1 edit that commented the clip out dead-coded the sampler, shifted texture
registers, and rendered black quads: never remove a sampler use from these
shaders, force the clip argument positive instead), page-level setVisible/scroll
(hooks quiet during visible blink), StaticBillboardSet::updateAll preRotatedQuad
rewrite (8-deg hysteresis hook ON, no change), shadows (user runs shadows OFF).
KEY ENGINE FACT: the fork is Ogre 2.x-family (Ogre::Aabb, ObjectMemoryManager in
the PagedGeometry ctor export) => culling uses CACHED world-bound arrays, and
GrassLoader::loadPage creates batch entities SCENE_STATIC (createEntity(...,1),
imm at 0xa3bb26 `41 B9 01 00 00 00`) on STATIC child nodes (GrassPage::addEntity
createChildSceneNode(1,...), imm at 0xa44301 `BA 01 00 00 00`). Stale cached
static bounds would cull mid-screen grass by phantom box positions -- flickering
exactly and only when the frustum ROTATES. Deployed experiment: byte-patch both
immediates to 0 (SCENE_DYNAMIC, bounds recomputed per frame), verify-before-write,
1.0.68 only. Flicker gone => ship as targeted patch (+ sig-based site resolution
for other builds, and check the BatchPage/impostor creation sites for mesh-foliage
layers too). Flicker persists => instrument the fork's cull pass next.
- **Amendment 12 (block path was BLIND + rock channel identified)**: the
  wall-hit log used an accumulator that only advanced during BLOCKED frames
  and printed after 0.5s of them -- but a block zeroes the motion, mlen drops
  to 0, the sweep stops evaluating: ONE silent frame per jump, so no block was
  EVER logged and the whole block path was debugged blind (the "restricted
  jumps" eras included). Now every block logs immediately (capped 6/arc), the
  sweep returns the blocking height + distance, and a third ANKLE ray (0.08bh)
  catches small boulders the shin ray flew over. Rock channel = **bit 0x40**
  (nearbits at the rock face); self = bit 0x1 (excluded).
- **Amendment 13 (top/bottom faces)**: side collision confirmed working; the
  two residual faces fixed WITHOUT mesh-landing commits: (a) BOTTOM = ceiling
  ray moved to a FEET origin demanding full body-height clearance (the old
  head-height origin sat above low overhang undersides -> interior ray saw
  nothing); (b) TOP = REST & SLIDE: a descent crossing a wide-mask surface
  above engine ground rests on it kinematically (vy=0, np clamped, airtime
  re-armed to 0.2s) and steers 8 u/s toward the lowest of 4 neighbor probes
  (open edge counts as strongly downhill) until the column reads engine ground
  again -- slide off the boulder, land on real ground. No landing commit on
  mesh tops, ever (mover-corruption rule).

### 2026-08-25 — TEST RIG EXE MISMATCH (why fixed-RVA patches silently no-op)
The RUNNING game reports "Kenshi 1.0.65 - x64 (Newland)" (kenshi.log window title)
while the Steam dir's kenshi_x64.exe ON DISK is 1.0.68 (embedded version strings;
mtime Jul 18) -- the process is a 1.0.65-family sibling binary; in the PagedGeometry
region its layout sits ~0xED0 BELOW the 1.0.68 disk layout (both runtime byte dumps
matched disk content at exactly +0xED0). Logs/mods/CWD are the Steam dir, so
everything LOOKS like the disk exe is running -- it is not. CONSEQUENCE: NEVER
hard-code RVAs derived from the dir's exe or the Ghidra kenshi_x64.exe for runtime
patches on this rig; ALWAYS kfp_text_scan signatures (rip-disp bytes wildcarded).
The static->dynamic grass patch is now sig-resolved (CE_SIG/CN_SIG in the client).
- **Amendment 14 (REGRESSION: feet-origin ceiling ray buried jumps)**: on any
  uphill slope the feet sit BELOW the local terrain read, so the amendment-13
  up-ray from feet+0.5 hit the slope surface from beneath at ~0 range and the
  "bonk" clamped the arc to hit-bh = a BODY HEIGHT UNDERGROUND with vy=0
  ("most jumps phase through the ground; can't jump on walkable slopes").
  Fixes: ceiling bonk requires clearance > 0.55*bh (genuinely overhead, not
  the surrounding slope) and the clamp may only stop the RISE (never below
  prev y - 1); rest&slide threshold 0.5 -> 1.2 over engine gnd (above the
  wide-vs-engine terrain disagreement on slopes). LESSON: any ray originating
  at the FEET must assume the origin may be inside the local surface on
  slopes -- gate by clearance band, never clamp downward.
- **Amendment 15 (slope filters + PERCH MODE)**: (a) sweep gained a WALKING-
  SURFACE filter -- a hit lying within 1.2u of the engine ground at ITS OWN
  column is the slope underfoot, not a wall (the ankle ray was blocking slope
  jumps at d=0.04); (b) takeoff gate upper bound +1.5 -> +4 (downhill stances
  read terrain ~2u above the embedded feet); (c) rest&slide became PERCH MODE:
  a mesh top whose 4-neighbor scan is within 2.5u is STANDABLE -- the arc
  stays alive with vy=0 as a kinematic floor, WASD walks the surface at 14u/s
  (sweeps still block), releasing keys stands still, walking off resumes the
  fall, and fp_fall_update supports re-JUMP from the perch (launch from
  g_fall_pos, NOT char_position -- the engine char is parked at the original
  commit). Steep tops still shed at 8u/s. Perch cannot land-commit (mover
  corruption rule) -- the engine char stays parked until a real landing.

### 2026-08-25 — TRUE-GEOMETRY MESH RAYCASTS (task #22, kfp_meshray.h)
Visual .mesh triangle queries, closing the hull-vs-visual gap (perched chars
floated on the fat collision hull in third person). Architecture:
- Ogre RaySceneQuery via OgreMain_x64.dll exports (ALL mangled names harvested
  from the SHIPPED dll -- Kenshi runs a PATCHED Ogre: HardwareBuffer::lock has
  an extra UploadOptions param, sig in the header). SceneManager obtained via
  MovableObject::_getManager on the Ogre::Camera (CameraClass+0x68).
- Entity filter: getMovableType()=="Entity", hasSkeleton() excluded (skips all
  characters INCLUDING our own body).
- Triangle extraction (GetMeshInformation walk, render-thread-only): per
  SubMesh {useSharedVertices@0, vertexData@8, indexData@16}; VertexData field
  base ADAPTIVE (+8 with 1.8's mMgr first, +0 fallback -- validated via
  findElementBySemantic accepting the decl); VertexElement raw {src@0,off@8,
  type@16}, POSITION must be VET_FLOAT3; buffers locked HBL_READ_ONLY via the
  patched full lock; 16/32-bit indices; cached LOCAL-space (max 80k tris/mesh,
  48 meshes). Shared-vertex submeshes skipped in v1 (logged).
- Query: ray -> mesh-local via node derived pos/ori/scale (by-value getters
  called (this, out) -- MSVC hidden-retptr in RDX works from mingw), Moller-
  Trumbore, nearest world hit. GAME<->OGRE coords via the weld's g_tx/g_tz.
- v1 integration: PERCH surface height refined to the true triangle surface
  ([cmesh] hull=/true= logs the gap). Self-disables on first fault (guarded).
- **Amendment 16 (perch = grounded + cmesh probe)**: perched arcs now feed the
  loco layer as GROUNDED (g_loco_in_air excludes g_fall_perched) -- the air
  tuck was bending the legs and TIP was gated off while standing on meshes;
  perch also feeds the kinematic walk speed/velocity/position to the
  blendspace (the engine feet tracker reads the PARKED char = 0). meshray
  refine gained a vtable-validated camera resolve (+0x68 with +0x58 fallback,
  vtable must live in OgreMain -- the NOTES header conflict) and a one-shot
  [cmesh] pipeline probe (entries + types) since the first field run resolved
  exports but never reached extraction.
- **Amendment 17 (perch polish)**: (a) perched facing now uses fp_movement's
  TIP PACING (start > tip_start_deg, step tip_turn_deg/s, disengage < ~1.7deg)
  instead of the hard camera glue -- the glue drove bodyYaw with zero lag so
  the loco TIP counter-rotation kept a residual twist on stop ("TIP stuck");
  the arc render/landing quat now follow g_face_yaw. (b) perch move speed =
  ground tiers ((sprint?60:38) * g_speed_scale) -- fixed 14 was half speed.
  (c) FOOT IK ON MESHES: loco gained g_loco_in_groundfn (all 6 GROUND_AT call
  sites rewired through loco_gnd_q); while perched it resolves against the
  perch entity's TRUE triangles via meshray_perch_column (snapshot of the
  last-refined node+cache -- ONE mesh, no scene query, falls through to the
  engine query past the rock's edge). Feet plant on the visible rock surface.
- **Amendment 18 (perch stability)**: the perch detect re-evaluates per tick;
  a single missed tick (edge-grazing ray / refine blink) dropped the perch for
  ONE frame -- g_loco_in_air flipped, air tuck flickered, TIP locks reset, and
  the rest height popped between hull and true surface = the "blendspace
  stutters and resets" report. Fix: 0.15s detect-miss HYSTERESIS (hold height,
  vy=0) + rest-height smoothing (per-tick change clamped to +/-0.4u while the
  perch persists). RULE: any per-tick re-evaluated STATE that gates animation
  layers needs hysteresis -- single-frame flips are always visible.

### 2026-08-25 — FOLIAGE FLICKER: ROOT CAUSE FOUND = z-buffer precision vs near_clip
The rotation-only foliage/rock flicker (buried bases popping through the terrain
every frame while the camera turns) is **depth-buffer precision z-fighting**:
Kenshi runs near=vanilla-small, far=50000 (logged live: near 0.5 / far 50000,
rock-steady per frame -- no clip refitting). Z precision ~ d^2/(near * 2^24):
sub-mm close up, ~3cm @500u, ~0.5m @2000u. Planted foliage has ZERO depth margin
at its burial seam, so beyond mid-range the seam z-test is under the precision
floor -- pure noise, re-rolled per frame by rasterization when the view ROTATES
(translation barely moves distant screen positions: parallax ~ 1/d -- exactly the
field isolation: still=clean, W=clean, mouse-look=flicker). Same artifact in
vanilla at ground-level zoom; invisible from the high RTS camera.
FIELD-VERIFIED: near_clip 0.05..1.0 all flicker identically (all catastrophic
ratios -- why the early tests misled); **near_clip=3.0 removes it entirely**;
view-distance (far) minimum = no effect (far contributes ~nothing to z
distribution). FIX SHIPPED: FP near_clip default 3.0 (F10 range 0.5-5.0), ini
template + comments updated. Cost: geometry closer than ~0.3m clips (fine in FP).
All 2026-08-24/25 diagnostic code removed (grass page hooks, billboard hysteresis,
static->dynamic patch, zclip trace); shaders restored pristine (.kfp-bak files
kept in data/materials/deferred as originals).
Exonerated along the way (keep for posterity): FP camera itself, per-frame
FOV/nearclip writes (write-on-change kept anyway -- correct), grass growth shader,
interiorClip cutaway mask (all 5 shader sites), page manager setVisible/scroll,
StaticBillboardSet preRotatedQuad updates, shadows, terrain LOD morph, static
scene-memory cached bounds, camera position churn (fol2 trace), clip refitting.
- **Amendment 19 (stutter root causes from field log)**: (a) the true-mesh
  pipeline was DEAD all along: the vtable-in-OgreMain camera validation cannot
  tell a Camera from a SceneNode, and MovableObject::_getManager on the center
  NODE read a null field ("[cmesh] _getManager unreadable (0)" per perch tick).
  SceneManager now comes from SceneNode::getCreator on the proven-live CENTER
  node (export harvested), camera path kept as fallback. (b) the perch steep
  classifier treated a MISSING neighbor probe as strongly-downhill -- near
  edges/on narrow rocks it flapped PERCHED<->slide per tick, bursting slide
  velocity over the walk velocity (the residual stutter). Now: measured slope
  only (miss = flat; walking off is the detect's job), probes at +/-2u, steep
  = drop > 1.6u, and an ESTABLISHED perch only sheds after 4 consecutive steep
  ticks.
- **Amendment 20 (low-mesh classifier + extraction xdiag)**: field log showed
  the "steep" classifier sliding FOREVER on a LOW mesh (~2.2u above terrain):
  neighbor probes just off its edge hit the ground 2u below -> "steep" every
  tick -> never perched -> airborne loco while walking = the persistent
  stutter. Rule now: a neighbor at terrain level (<= gnd+1.2) is a walkable
  step-down, NOT a cliff -- steep needs a >1.6u drop while STILL ON the mesh,
  or a >4u drop onto anything. Triangle extraction still yields 0 on this
  build's SubMesh/VertexData layouts -- added [cmesh] xdiag raw byte dumps
  (SubMesh first 0x40 + every pointer field's first 0x40) to derive the real
  offsets from the next field log.
- **Amendment 21 (smooth sneak transitions)**: the sneak toggle hard-switched
  the blendspace's clip arrays and crossfaded through a FROZEN pose snapshot
  (g_loco_fade) -- mid-stride toggles hitched. Now an EASED sneak weight
  (g_sneak_w, ~0.25s, smoothstepped) MIXES the crouch set with the stand set
  per bone (dual sampling only while 0<w<1) and eases the stride length
  (effLen) between the sets -- the air-tuck handover pattern. The snapshot
  fade on the sneak edge is gone; the toggle ownership re-assert + 0.6s
  passive-claim window stay (the game still needs its stance change applied
  to non-owned bones). TOOLING LESSON: `sh build.sh | tail` masks build
  failures (pipe status) -- one stale-DLL deploy shipped that way; deploy
  chains must gate on unmasked build status.
- **Amendment 22 (sneak-toggle IK correction frame)**: the frame-after stutter
  on sneak toggles = the passive claim release with a pelvis IK drop still
  applied -- core release bind-restores the pelvis position IN ONE FRAME.
  Fixes: (a) ikActive gains `g_sneak_cool <= 0` (stop solving on the toggle so
  the drop eases out via the IK-inactive unwind instead of re-solving against
  the half-changed stance); (b) DROP UNWIND HOLD: wantGroup keeps legs+core
  owned while |g_ik_drop| > 0.02, so release always happens FROM the bind
  pose. RULE: never release a bone group while a positional offset is still
  applied to it -- ease offsets to zero first, then release.
- **Amendment 23 (the REAL sneak-toggle snap + stance trace)**: the frame-after
  correction was the IDLE-AIM SPINE, not the pelvis: aimOn hard-gates on
  g_sneak_cool, so the toggle forced mag=0 and RELEASED the spine bones the
  same frame with the full look-pitch bend still applied -- the game snapped
  the spine straight in one frame and the head-welded camera popped. Fix: the
  aim offsets now carry an eased gate weight (aimw_e, ~0.15s); the mag<0.02
  release fires only after the spine has straightened (release rule, rotational
  case). Added a [stance] per-frame trace (50 frames after every toggle: sneak
  weight, ik weight/drop/dip, ownership, idleaim, TIP, moveblend, cool) so the
  next report can be verified against data instead of theory.
- **Amendment 24 (OWN THE TRANSITION -- the [stance] trace verdict)**: the
  egregious sneak snap was STRUCTURAL: ownership releases are instant (only
  claims fade), and mid-stance-change the game's target pose is the OTHER
  stance -- the trace showed own 111->100 mid-cool (upper+core snapped to the
  crouch idle in one frame) followed by a re-engage cluster (idle-aim reclaim,
  ikw 0->0.97 + drop dive, TIP steps) after cool expiry. The eased clip mix
  couldn't help: the IDLE pose comes from the frozen acquire snapshot, not the
  blendspace. Redesign: g_stancemix_w holds ALL groups for the whole
  transition and bridges the idle base with blend(idle clip 16, crouch idle
  25, sneak weight) -- the held idle MORPHS between the game's own (retargeted)
  stance idles; on the transition's falling edge the acquire base is refreshed
  to the live output so the mix eases out as a no-op and release happens from
  the exact displayed pose.
- **Amendment 25 (loco fault = clip name mismatch)**: "8D locomotion gone,
  body rotates with WASD" = the loco layer FAULTED on the first real sneak
  ([loco] retarget FAULTED): the stance bridge sampled g_loco_crouchidle = -1
  -- the KFA's crouch idle is MOB1_Crouch_Idle_V2_IPC (bake log clip 25), the
  lookup asked for the V2-less name, and crouch_ok only validates the 8 walk
  clips. Fixes: correct name (+fallback), bridge guards crouchidle >= 0, and
  loco_sample() now BOUNDS-CHECKS clipIdx (invalid = bind park, never a
  fault). RULE: every loco_find_clip result used at sample time must be
  validated or the sampler must be total.
- **Amendment 26 (sneak T-pose flash)**: full-body T-pose on toggles after
  own-the-transition. KFA idle-track sparsity DISPROVEN offline (both idles
  20/20 tracks; KFA2 bone record = name+flag+4 rest-rot floats -- NO rest pos,
  a parser that assumes pos+rot misaligns). Cause: the game's sneak-edge layer
  re-registration lands ASYNC (frames after the toggle) and clears bone flags;
  the single edge re-assert was too early, leaving held bones un-animated at
  BIND = T-pose -- exposed full-body now that the transition holds all groups.
  Fix: re-assert ownership EVERY frame while g_sneak_cool > 0. Also: stance
  bridge simplified to slerp(acqpose -> crouch idle clip, snw*smw) -- never
  samples the stand idle clip (acqpose IS the live stand idle).
- **Amendment 27 (stuck-in-crouch on uncrouch -- SELF-SUSTAINING LOOP)**: the
  stance bridge blended acqpose -> crouch idle by snw, so snw->0 returned to
  ACQPOSE = the game pose snapshotted when we claimed the bones = the stance
  being LEFT. Uncrouching therefore blended back INTO the crouch. The stuck
  crouch then read as floating feet to the plant IK, which dove the pelvis
  (trace: ikw 0->0.91, drop -0.6), and drop_unwind held the groups on that
  drop -- the hold sustained the very condition it waited for. Fixes: (a)
  bridge stand end = the STAND IDLE CLIP (both idles verified 20/20 tracks in
  the .kfa; the old T-pose was the async re-registration, already fixed), so
  the bridge is stance-correct at BOTH ends; (b) drop_unwind now requires
  !ik_was_active -- a hold must never be able to sustain its own trigger.
- **Amendment 28 (feet float in sneak = LOST PELVIS TRANSLATION)**: KFA2 bakes
  ROTATIONS ONLY (write_kfa2: u8 hasTrack + rot[keys*4], no pos), so a crouch
  clip's pelvis LOWERING is discarded -- the legs fold but the hips stay at
  standing height and the feet ride up. The plant IK could not cover it: its
  wantDrop is clamped to -0.85 (a crouch needs ~2-3 units at leg length 9) and
  it is near-idle only, so moving crouch had no correction at all. Fix: NEW
  g_stance_drop -- FK the ankles from the composed pose with the pelvis at
  bind, lower the pelvis until the LOWEST ankle returns to the bind sole
  (g_ik_ankle0), scaled by the sneak weight, eased 8/s, bounded to
  -0.45*(thigh+calf). Applied in ALL pelvis paths (plant-IK active, plant-IK
  inactive, and as the IK's pass-1 baseline so ground correction stacks on top
  of the stance instead of re-deriving it). Gated on g_lower_owned (released
  legs = the game's own crouch anims already handle the hips) and holds the
  CORE group while non-zero (the pelvis write needs it). [crouch] logs it.
- **Amendment 29 (falling + jumping OFF by default, F10-toggleable)**:
  g_cfg_falling and g_cfg_jump now default 0 (and the F10 tset defaults are 0,
  so Reset also turns them off). NEW F10 toggle "Jump (Space)" beside
  "Falling" (panel layout is computed from FN(g_tsets), so the extra row needs
  no layout work). The two features were DECOUPLED: they share the arc
  integrator but gate separately -- fp_fall_update runs if EITHER is on, the
  walk-off EDGE SCAN is gated on falling, the space rebind/pause-swallow on
  jump. So jump-with-falling-off works (including taking the fall when you
  jump off a ledge) and edges keep their vanilla stall.
  DEPLOY NOTE: the live inis already had falling=1/jump=1, so they were
  updated with TARGETED sed key edits (never template-copy: deploy-ini-clobber
  rule). The mod-folder ini is CRLF (save_ini through Proton msvcrt), so
  targeted edits must tolerate a trailing \r -- a plain '^key=1$' silently
  no-ops there.
