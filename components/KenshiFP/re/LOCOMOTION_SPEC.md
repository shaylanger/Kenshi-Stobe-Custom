# KenshiFP custom locomotion — retarget + blendspace spec

Extracted 2026-07-28 from Destreza's `EliteAnimator.cs` (Godot, authoritative) + `eliteRig.ts`
(three.js original). This is the algorithm we port to C to play Destreza's Humanoid_ clips on
Kenshi's Bip01 skeleton. Source data baked by `tools/bake_locomotion.py` → `locomotion.kfa`.
See [[kenshifp-custom-locomotion]] memory. **NOTE**: the AIM/IK target bone names below are
base.glb's *rigify* names — for Kenshi we remap the TARGET column to Bip01 (source Humanoid_
column is unchanged). Milestone 0 only needs §0,A,B,C.

## 0. Coordinate frames (THREE)
- Source raw (Humanoid_/skeleton.json): +Z up, cm, left-handed. Not rotated wholesale; handedness
  fixed per-vector at aim time by mirroring one axis.
- Target model (rigify base.glb): +Z up, m, X lateral / Y fwd / Z up. All target FK here.
- World (engine): +Y up. Only for ground queries/leans/hand-IK.
Conversions (applied only when a SOURCE quantity is consumed):
- `ConvDir(d) = (d.x, -d.y, d.z)`   (mirror Y of a direction)
- `ConvQ(q)  = normalize(-q.x, q.y, -q.z, q.w)`  (negate X,Z)
A full Z-up→Y-up basis change was REJECTED (it mirrored the whole anim). Single-axis mirror instead.
**KENSHI conversion — RESOLVED 2026-07-30** (tools/dump_ogre_skeleton.py on male_skeleton.skeleton
+ skeleton.json, corroborated by the open-source kenshi_io_blender exporter conventions):
- Kenshi Bip01 skeleton space: up=+Y, fwd=+Z, right=−X. Bones are X-along-bone.
  `Bip01` root carries a −90° Y bind rotation; Kenshi YAWS THE ROOT BONE for facing.
- Destreza Humanoid_ source:   up=+Z, fwd=+Y, right=−X (cm). [r,f,u] basis det −1 vs Kenshi +1
  → conversion is a REFLECTION (det −1), ConvQ via the det rule (w, det·M·v).
- M ≈ (x,z,y) swap + ~5° tilt correction; measured at runtime (loco_conv=8) as
  M = B_target·B_sourceᵀ from bind positions — never guessed.
Measured model-frame axes (once at BIND — OldNode initial states, never live deriveds; live
capture bakes the playing animation + facing into "rest" → sideways-flipped, facing-skewed pose):
- `fwdSkel`  = normalize(Σ over feet (bindGlobalPos[toe]-bindGlobalPos[foot])), avg L+R.
- `rightSkel`= normalize(bindGlobalPos[hand.R]-bindGlobalPos[hand.L]).
- `upSkel`   = normalize(bindGlobalPos[head]-bindGlobalPos[pelvis]); orthonormalize preserving
  handedness (project, don't cross).
Chain rule: every ancestor of a written bone (except the facing-only root) must be a slot we
control — Kenshi's real hierarchy inserts CLAVICLES between Spine2 and the UpperArms, so the
clavicles are held manual at bind local (Destreza doesn't aim them either) and Spine2 is aimed
at the Neck. Writing bind-relative LOCALS makes the whole pose facing-invariant for free.

## A. Clip sampling
Shared normalized `phase∈[0,1)`. `effLen = A.length + (B.length-A.length)*gait` (A=walk,B=jog);
`phase = (phase + dt*clamp(LocoRate,0.1,1)/max(0.05,effLen)) % 1`.
`Sample(clip,time,bone)`, `time=phase*clip.length`:
```
if bone∉tracks: return (rest.pos, rest.rot)
t=length>0?(time mod length):0 ; f=t*fps
k0=clamp((int)f,0,keys-1); k1=min(k0+1,keys-1); u=clamp(f-k0,0,1)
rot=slerp(norm(quatAt(k0)),norm(quatAt(k1)),u)
pos=(has pos && len>=(k1+1)*3)?lerp(p0,p1,u):rest.pos
```
Use the fps form (not TS's p*(nR-1)).

## B. Source FK (raw source frame, cm→m ×0.01, NO handedness conv here)
Rest world rot once (parent-ordered): `srcRestWrot[i]=parent<0?norm(restRot):norm(srcRestWrot[par]*restRot)`.
Per frame:
```
for i: (lpos,lrot)=SampleBlended(bone[i],...)
  parent<0: world[i]=lpos*0.01 ; wrot[i]=lrot
  else:     world[i]=world[par]+wrot[par]*(lpos*0.01) ; wrot[i]=norm(wrot[par]*lrot)
```

## C. AIM table + direction-transfer
AIM (pre-IK, [targetBone,targetChild,sourceBone,sourceChild]) — TARGET col = rigify, remap→Bip01:
```
spine.001_02      spine.002_03      Humanoid_-Spine     Humanoid_-Spine1     → Bip01 Spine  / Spine1
spine.002_03      spine.003_04      Humanoid_-Spine1    Humanoid_-Spine2     → Bip01 Spine1 / Spine2
upper_arm.L_09    forearm.L_010     Humanoid_-L-UpperArm Humanoid_-L-Forearm → Bip01 L UpperArm/Forearm
forearm.L_010     forearm.L_end_062 Humanoid_-L-Forearm Humanoid_-L-Hand     → Bip01 L Forearm/Hand
upper_arm.R_012   forearm.R_013     Humanoid_-R-UpperArm Humanoid_-R-Forearm → Bip01 R UpperArm/Forearm
forearm.R_013     forearm.R_end_063 Humanoid_-R-Forearm Humanoid_-R-Hand     → Bip01 R Forearm/Hand
thigh.L_014       shin.L_015        Humanoid_-L-Thigh   Humanoid_-L-Calf     → Bip01 L Thigh/Calf
shin.L_015        shin.L_end_064    Humanoid_-L-Calf    Humanoid_-L-Foot     → Bip01 L Calf/Foot
thigh.R_016       shin.R_017        Humanoid_-R-Thigh   Humanoid_-R-Calf     → Bip01 R Thigh/Calf
shin.R_017        shin.R_end_065    Humanoid_-R-Calf    Humanoid_-R-Foot     → Bip01 R Calf/Foot
```
Clavicles NOT aimed (thrusts shoulders); arms adducted via arm-mod stack (§F).
AIM_POST (after IK parent placed): foot.L←Humanoid_-L-Foot/Toe0, foot.R←R-Foot/Toe0 (→ Bip01 L/R Foot & Toe0).
FULL_ORIENT (hips, full source orientation NOT aim): spine_01 ← Humanoid_-Pelvis (→ Bip01 Pelvis).
IK_END (control bone → chain end): ankles←shin ends, wrists←forearm ends.

### aimBoneToward (parent-before-child; keep a PRIVATE global[]/localRot[], never read engine mid-frame)
```
1. want=ConvDir(world[srcChild]-world[src]); if |want|²<1e-10 skip; want=norm(want)
2. spine: want=norm(lerp(want,(0,0,1),UPRIGHT_SPINE=0.5)); feet: plant/toe dir; arms: arm-mod stack
3. qCand=norm( ConvQ(wrot[src]) * inv(ConvQ(srcRestWrot[src])) * restGlobalRot[i] )   // twist/roll delta onto target bind
4. localFwd=rest[child].origin ; fwd=norm(qCand*norm(localFwd))
5. qFinal=norm( postRoll * shortestArc(fwd,want) * qCand )   // postRoll=id except planted foot cross-slope
6. localRot[i]=norm( inv(parentGlobalRot)*qFinal ); global[i]=parentG*T(basis(localRot[i]),rest[i].origin); WRITE localRot[i]
shortestArc(a,b): d=clamp(dot,-1,1); ax=cross(a,b); if|ax|²<1e-12 return d>0?id:quat(anyPerp(a),π); return norm(quat(norm(ax),acos(d)))
```
Hips full-orient (replaces aim): `deltaSkel=norm(ConvQ(wrot[pelvis])*inv(ConvQ(srcRestWrot[pelvis])))`;
`restGlobalRot=norm(parentG*rest[i].rot)`; `localRot[i]=norm(inv(parentG)*(deltaSkel*restGlobalRot))`.
Pelvis stride bob (hips local pos): `raw=ConvDir(world[pelvis]); pelvisLp=lerp(pelvisLp,raw,min(1,dt*1.5));
bob=clamp((raw-pelvisLp)*moveScale,±0.10/axis); hips.pos=rest.origin+bob`.

## D. Blendspace (8-way, F FR R BR B BL L FL = 0..315°; moveAngle 0=fwd,+=right)
Clips per dir: F=Walk_F/Jog_F_Loop, FR=Walk_FR_Loop/Jog_FR_Loop, R=Walk_R/Jog_R_Loop,
BR=Walk_BR_BkPd_Loop/Jog_BR_BkPd_Loop, B=Walk_B/Jog_B_Loop, BL=Walk_BL_BkPd_Loop/Jog_BL_BkPd_Loop,
L=Walk_L/Jog_L_Loop, FL=Walk_FL_Loop/Jog_FL_Loop. Idle=ANIM_Humanoid_IdleUnarmed. (prefix MOB1_).
Pose is a per-bone weighted mix sampled BEFORE FK. Directional: step=τ/8; a=((moveAngle%τ)+τ)%τ/step;
i0=floor(a)%8; i1=(i0+1)%8; f=frac(a); poseA=SampleDir(i0); if f>1e-3 pose=slerp(poseA,SampleDir(i1),f).
SampleDir=slerp(walk@(phase*wlen),jog@(phase*jlen),gait). Gait: gaitTarget=moving?clamp((speed-1.5)/2.5,0,1):0;
gait+=(gaitTarget-gait)*min(1,dt*6). Source crossfade (idle↔loco): blend+=dt/0.22, lerp prev→cur.
Move-angle ease + reversal latch, latStrafe/latFwd from TARGET (not eased angle): see spec §D. Use C#
branch (single rate-cap MOVE_TURN_RATE=5, direct source crossfade on held |dAng|>2.4 reversal).
Arm fold: arm bones sample fwd clip (angle 0) when foldClipW=max(|latStrafe|,armFoldW)>1e-3.
Eased scales (rate6): adductScale isIdle?1:0.1; adductUpperScale isIdle?1:0.55; droopScale isIdle?1:0.7;
moveScale isIdle?0:1; walkArmW=1-smoothstep(.35,.85,gait); moveFwdW=smoothstep(-1,0,latFwd); armFoldW=(1-moveFwdW)*(1-walkArmW).

## E. Turn-in-place (procedural, no clips; replaces leg IK when TurnLock)
TIP_STEP_ANGLE=0.30rad, TIP_STEP_TIME=0.18s, TIP_STEP_LIFT=0.11m. Each foot world-locks its XZ while
body twists; when |Δ(lockYaw,BodyYawFeed)|>ANGLE (or lock overstretches, >(shin+end)*0.93) and the other
foot isn't stepping, that foot steps to the animated ankle over TIME with sin lift; alternating, one at a
time. tipPlant feeds foot-flatten. TurnLock edge → Snapshot(TURN_BLEND=0.18). See spec §E.

## F. Post-retarget IK (constants) — see full spec section F
Foot-plant flatten+toe-drop; SolveLegIK (2-bone, SOLE=0.06, penetration/0.015); SolveLimbTo (law-of-cosines,
pole=poleHint+outward*kneeOut*bendFactor, AimAt each seg); IK-end snap (ikOff=inv(restGRot[end])*restGRot[ik]);
ApplyHandIK; LocoArmSecondary (lag30,trail0.08); WristOut(11°*walkArmW); AirPose(tuck0.85,raise0.34,kneeOut0.8);
arm-mod stack (ARM_DAMP0.68, per-bone adduct/droop, run/walk fwd, splay); ApplyAimOffset (spine→head weights
{.12,.15,.16,.17,.18,.22}); ApplyLeans (lumbar spine.001_02); PoseFists (ease14); Snapshot/BlendToSnapshot.

## G. Public inputs / per-frame order
SetLocomotion(speed, airborne=false, moveAngle=0, velY=0, moving=null); SetFists(l,r); fields AimPitch/AimYaw/
ClimbLock; TurnLock+BodyYawFeed (out TipStepCount); LocoRate; Swimming/SuppressLocoArms/Ragdolling; SetHandIK;
GroundHeight/WorldForward/OnStep/PlantL/PlantR injected.
Per-frame order: (1)guard+dt (2)TurnLock edge snapshot (3)weights+phase+blend+scales (4)SolveSourcePose
(5)build lookup (6)Pass1 SolveBone non-IK (hips+spine+limb aim+arm mods) (7)limb: swim/air/turnIP/legIK
(8)combat overlay (9)leans (10)aim offset+headYawLock (11)LocoArmSecondary (12)handIK (13)Pass2 IK-end snap
(14)WristOut (15)Pass3 SolveBone IK-subtree (feet toe, hands) (16)kick (17)PoseFists (18)BlendToSnapshot.

## Milestone 0 — DONE 2026-07-30, technique PROVEN in-game (walk_F plays correctly)
Architecture (matches how all shipped Kenshi anim mods work — dissected SWG/COMBAT workshop mods):
retarget runs OFFLINE in `tools/retarget_locomotion.py` (direction-transfer vs the real
male_skeleton bind, validated by stick-figure renders BEFORE any game test) → bakes Bip01-LOCAL
rotation tracks into locomotion.kfa (KFA2) → runtime (`client/kfp_locomotion.h`) just samples,
slerps, writes locals on controlled bones. Two engine flags are BOTH required per bone:
1. `OldBone::setManuallyControlled(1)` — stops Ogre-side animation application, and
2. Kenshi's custom `OldSkeletonInstance::disableBone(skel, name, 1)` — stops KENSHI's own
   animation system, which otherwise keeps blending per-bone-masked layers on top of manual
   bones (measured: few-degree/frame drift on most bones, full static override on the R arm
   weapon mask). Re-enable both on release (FP exit / knockdown / character swap).
Next milestones: §D blendspace (8-way + gait mix, offline-baked per-dir clips + runtime mix or
extra baked blends), phase from actual move speed, §E turn-in-place, §F IK/arm-mod polish.
