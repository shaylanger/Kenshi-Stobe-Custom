KenshiFP (RE_Kenshi edition) - First-Person Mode for Kenshi
============================================================
This edition runs as an RE_Kenshi PLUGIN and works on ALL Kenshi builds that
RE_Kenshi supports -- Steam (any version) AND GOG -- with no version-specific
setup. If you are on standard Steam Kenshi and don't use RE_Kenshi, use the
standalone edition instead.

REQUIREMENTS
  - Kenshi (Steam or GOG)
  - RE_Kenshi (https://www.nexusmods.com/kenshi/mods/2063)

INSTALL
  1. Copy the whole "KenshiFP" folder into your Kenshi "mods" folder:
        <Kenshi install>/mods/KenshiFP/
     After copying you should have these files:
        mods/KenshiFP/KenshiFP.dll
        mods/KenshiFP/KenshiFP.mod      <-- makes "KenshiFP" appear in the mod list
        mods/KenshiFP/_KenshiFP.info
        mods/KenshiFP/RE_Kenshi.json    <-- tells RE_Kenshi to load the plugin
        mods/KenshiFP/character/        <-- head-hide part maps (see step 3)
     The UI images and the animation pack are built INTO KenshiFP.dll -- there
     is nothing else to keep together. The DLL writes a "kenshifp" image folder
     next to itself on first run; you can ignore it, or drop your own PNGs in
     there to reskin the crosshair (your files are never overwritten).
  2. Launch Kenshi. In the mod list, ENABLE "KenshiFP" (tick it), then start.
     RE_Kenshi loads the plugin automatically for enabled mods.
     If "KenshiFP" does NOT appear in the mod list, the KenshiFP.mod file is
     missing from the folder -- re-extract the zip so all the files are present.
  3. HEAD-HIDE: nothing to do -- it works out of the box. The part-map textures
     ship inside this mod folder (character/skins/masks/), so Kenshi loads them
     for you. You do NOT need to merge the zip's "data" folder: that is only for
     the standalone edition, which has no mod folder to load them from.
  4. Select a character and press RIGHT ALT to toggle first person.

  Do NOT also add a "Plugin=KenshiFP_x64" line to Plugins_x64.cfg -- that is
  only for the standalone edition. Running both at once conflicts.

LOCOMOTION
  Full-body custom first-person locomotion (8-way movement, turn-in-place,
  foot IK, aim-follow) is ON by default. The animation pack is embedded in the
  DLL, so there is no file to lose. Set locomotion=0 in KenshiFP.ini for vanilla
  animations -- or just untick "Custom anims" in the F10 panel, no restart
  needed. Everything else in the mod keeps working either way.
  (Advanced: a locomotion.kfa file placed next to the DLL overrides the
  built-in pack -- for custom bakes from tools/retarget_locomotion.py.)

CONTROLS
  Right Alt = first person | Mouse = look | WASD = move | Wheel = walk/run speed
  Left Shift = sprint | F10 = settings panel | Left Alt = free the cursor
  Space = jump and P = pause -- ONLY while "Jump (Space)" is enabled (below)

OPTIONAL MOVEMENT FEATURES (both OFF by default -- F10 panel, or the ini)
  "Falling"       walking off a cliff/roof/stair edge drops you (real gravity
                  arc, fall damage and KO on hard landings) instead of the
                  vanilla stall at the lip.
  "Jump (Space)"  Space jumps. While it is on, Space no longer pauses -- pause
                  moves to P (key_pause in the ini); everywhere outside first
                  person, and with any menu open, Space still pauses as normal.
                  Independent of "Falling": you can jump with falling off.

CONFIG (optional, hot-reloaded in-game)
  Edit "KenshiFP.ini" IN THIS MOD FOLDER (next to KenshiFP.dll) -- changes apply
  within a second, no restart. Settings: fps_cap, fov, near_clip, sensitivity,
  aim_lean, ranged_freeaim, wheel_speed, ko_vignette, key rebinds, and more.
  You can also change everything live from the in-game panel (F10).

A log "KenshiFP.log" is written in your Kenshi install root -- attach it to any
bug report.

Source (GPL-3.0): github.com/linguine2552/KenshiFP
