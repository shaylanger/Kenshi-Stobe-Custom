# KenshiFP viewmodel: coverage per weapon class

Read from `/root/KenshiFP/client/kfp_viewmodel.inc` at ad419c0 (2026-10-10, read only). Weapon list and dims:
`WEAPON_CATALOG.md` / `weapons.csv` here (regenerate: `python3 tools/animlab/animlab.py weapons --catalog -o <dir>` in the
harness). Lab matrix: `animlab.py weapons --run` (harness `tools/animlab/weapon_matrix.py`).

## How the viewmodel picks a path

`vm_frame` sets `cls = 1` when the weapon in hands is the character's ranged weapon, else `cls = 0`. There is no
per-skill-category or per-weapon branch anywhere in the viewmodel: **every melee weapon (katanas, sabres, blunt,
heavy weapons, hackers, polearms, every mod weapon) runs the one sword path tuned on the katana**; crossbows run the
ranged path; no weapon in hands + `fp_fists` runs the NA1 unarmed path.

| class (skill category) | FP path | status |
|---|---|---|
| 0 katanas | melee path (tuned: calibrated on katana05 / the mate's katana) | tuned |
| 1 sabre | melee path, katana numbers | generic fallback |
| 4 hackers | melee path, katana numbers | generic fallback |
| 2 blunt | melee path, katana numbers; edge rules applied to a round club | generic fallback |
| 3 heavy weapons | melee path, katana numbers, held ONE-handed | generic fallback, 2-hand grip missing |
| 8 polearm | melee path, katana numbers, held ONE-handed | generic fallback, 2-hand grip missing |
| 6 crossbow | ranged path (calibrated on the Oldworld Bow) | tuned; bolt geometry measured per gun (`vm_bolt_measure`) |
| 5 unarmed | NA1 fist path | tuned (fists rows) |

## Per-weapon parameters the viewmodel uses

| parameter | where | per weapon? |
|---|---|---|
| weapon pose per state (grip p, blade f, edge u) | `g_vm_pose[2][VM_NT]`, swing keys `g_vm_swk` + `g_vm_swk_alt` (4 strokes) | per class (melee/ranged) only |
| prop axes (which mesh axis is the blade / edge) | `g_vm_ax[2]` (melee +Y blade, +Z edge) | per class only: a mod mesh modelled along another axis is posed wrong |
| grip = prop bone origin = mesh origin | prop local `g_vm_pldq/pldp[2]` (katana native ready local, frozen by `plfix`) | per class only |
| grip slide along the blade | `g_vm_plsl[0] = 1.0 dm` (tuned so the katana handle end does not stick out past the fist into the near clip) | per class only; long handles (polearm 5-6 dm behind the grip) |
| grip roll | `g_vm_groll[0] = 60 deg` | per class only |
| edge rules (edge clamp S1, grip kappa, wrist fix PT17, E1 arc) | `g_vm_eclamp`, `wfix`, `hroll` | all melee, also round clubs/staffs (no edge) |
| off hand | melee: rest point out of view `g_vm_rest`; ranged aim: fore-stock support `g_vm_sup` | 2-handed native grips (`g_vm_off_near` 3.5 dm) are detected but only used for the ranged path |
| blade length | none in the solver; the lab used `BLADE = {0: 8.0, 1: 5.85}` | none |
| near clip | 3.0 dm melee, 1.5 dm ranged/fists (`g_vm_nc`) | per class |
| swing timing | progress = the native swing animation's own progress | follows each class's native technique (length differs per class/technique) |

## What this means (findings before any game run)

1. **Heavy weapons and polearms are held one-handed in FP** (off hand parked at the rest point out of view) although
   every native technique of these classes holds them with both hands. Lab check `twohand` (inferred rule): all 31
   heavy/polearm representatives FAIL, base and mod alike.
2. **Long weapons leave the view in ready/block**: the ready pose (blade up-forward right) and the block pose (blade
   across the view) are katana-sized. Nodachi, Plank, Naginata, Polearm and long mod weapons (Wafer Blade 24.6 dm,
   Crusher 18 dm, Mother's Lament 20 dm) have most of the blade off screen (`vis` FAIL); the block puts long blades
   off the left edge.
3. **Long handles behind the grip** (polearms 5.4-6 dm, Plank/Fragment Axe 4.4-4.9 dm vs katana 2.4 dm) reach toward
   the camera; `near` checks they are not cut by the 3 dm near clip on screen.
4. **Mesh-axis convention**: one mod weapon (UWE Crab Maul, `crab_hammer_sheathed.mesh`) is modelled along Z, not +Y:
   the viewmodel would hold it sideways (catalog flag `axis=Z`).
5. **Animation-class overrides**: 37 weapons (5 base) play another class's techniques (`skill category animation
   override`, e.g. Topper/Combat Cleaver -> sabre, Flesh/Moon/Short Cleaver -> blunt, Heavy Polearm/Naginata Katana ->
   sabre). The swing timing follows the played technique, not the item class.
6. **Animation mods change the native reference**: Great Anims Mod (e.g. katanas +15, sabre/blunt +19 techniques), More
   Combat Animation (katanas +28, other classes +8-12) and UWE (3 changed per class) add/replace combat techniques for
   every class; their animations come from mod skeleton
   files the lab's vanilla skeleton does not hold. Native-reference checks (`native.py`) currently judge against the
   vanilla set only.
7. Crossbows: one tuned path; bolt geometry is measured per gun in game, so the 7 crossbows mostly differ by size
   (Eagle's Cross 15.2 dm vs ~10 dm).
