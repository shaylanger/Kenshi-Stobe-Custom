#!/usr/bin/env python3
"""Stobe.dll round 17 (test inbox): `speed <x>` command.

speed 0      -> pause (userPause(true))
speed 0.5-10 -> unpause and set the game speed (setGameSpeed, then the frame-speed
                multiplier if Kenshi clamped it, so 5x/10x work)
Reply: "speed <before> -> <after> paused=<0|1>".

Usage: patch_dll_round17.py <STOBE-src root>
"""
import sys, pathlib

root = pathlib.Path(sys.argv[1])
f = root / "src" / "main.cpp"
s = f.read_text()
anchor = '  if (cmd == "give_cats") {\n    int amount = f.size() >= 3 ? atoi(f[2].c_str()) : 0;\n'
assert s.count(anchor) == 1, "anchor"
assert 'cmd == "speed"' not in s, "already applied"
new = r'''  if (cmd == "speed") {
    if (f.size() < 3 || !world)
      return "usage: speed <0|0.5..10>";
    float v = (float)atof(f[2].c_str());
    if (!(v == 0.0f || (v >= 0.5f && v <= 10.0f)))
      return "usage: speed <0|0.5..10>";
    float before = 0.0f, after = 0.0f;
    bool paused = false;
    try {
      before = world->getFrameSpeedMultiplier();
      if (v == 0.0f) {
        world->userPause(true);
      } else {
        world->userPause(false);
        world->setGameSpeed(v, false);
        if (world->getFrameSpeedMultiplier() < v - 0.01f ||
            world->getFrameSpeedMultiplier() > v + 0.01f)
          world->setFrameSpeedMultiplier(v);
      }
      after = world->getFrameSpeedMultiplier();
      paused = world->isPaused();
    } catch (...) {
      return "speed change failed";
    }
    Log("TEST_INBOX: speed id=" + f[0] + " requested=" + f[2] +
        " before=" + ToString(before) + " after=" + ToString(after) +
        " paused=" + (paused ? "1" : "0"));
    ok = true;
    return "speed " + ToString(before) + " -> " + ToString(after) +
           " paused=" + (paused ? "1" : "0");
  }
'''
s = s.replace(anchor, new + anchor)
f.write_text(s)
print("patched", f)
