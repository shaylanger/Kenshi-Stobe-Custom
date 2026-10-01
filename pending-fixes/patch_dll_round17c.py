#!/usr/bin/env python3
"""Stobe.dll round 17c (test inbox): `speed` accepts up to 50x.

Shay asked for 10x-50x to get slow goals (farm growth) tested faster.
Usage: patch_dll_round17c.py <STOBE-src root>
"""
import sys, pathlib

f = pathlib.Path(sys.argv[1]) / "src" / "main.cpp"
s = f.read_text()
pairs = [
    ('      return "usage: speed <0|0.5..10>";\n    float v', '      return "usage: speed <0|0.5..50>";\n    float v'),
    ('    if (!(v == 0.0f || (v >= 0.5f && v <= 10.0f)))\n      return "usage: speed <0|0.5..10>";',
     '    if (!(v == 0.0f || (v >= 0.5f && v <= 50.0f)))\n      return "usage: speed <0|0.5..50>";'),
]
for old, new in pairs:
    assert s.count(old) == 1, f"anchor: {old[:50]!r}"
    s = s.replace(old, new)
f.write_text(s)
print("patched", f)
