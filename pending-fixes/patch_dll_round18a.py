#!/usr/bin/env python3
"""Stobe.dll round 18a (feature 3): TTS no longer follows game speed by default.

With "Speed Dialogue" on, STOBE rewrote each TTS WAV's sample rate by the game
speed (up to 3x: faster, higher voice) and paced lines in game time. Shay wants
TTS at normal speed at any game speed. The existing toggle already does exactly
that when off (TTS at 1x, line pacing in real time), so the default becomes off
(Globals, ini reader default, shipped Stobe.ini). The toggle stays in STOBE's
Settings window for anyone who wants the old behaviour.

Usage: patch_dll_round18a.py <STOBE-src root>
"""
import sys, pathlib

root = pathlib.Path(sys.argv[1])

def patch(rel, pairs):
    f = root / rel
    s = f.read_text()
    for old, new in pairs:
        n = s.count(old)
        assert n == 1, f"{rel}: anchor count {n}: {old[:70]!r}"
        s = s.replace(old, new)
    f.write_text(s)
    print("patched", f)

patch("src/Globals.cpp", [("bool g_speedDialogue = true;", "bool g_speedDialogue = false; // TTS plays at 1x regardless of game speed (round 18a)")])
patch("src/Utils.cpp", [('"Speed Dialogue", 1) != 0;', '"Speed Dialogue", 0) != 0;')])
patch("mod/Stobe.ini", [("Speed Dialogue=1", "Speed Dialogue=0")])
