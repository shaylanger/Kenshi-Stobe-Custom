#!/usr/bin/env python3
"""Feature (Shay, run 8): U selectable as push-to-talk key in STOBE settings.
The parser (SetPushToTalkHotkeyFromString) already accepts A-Z; only the
settings dropdown offered V, B, N, M, C, X, Z.
Usage: patch_r19_feat_ptt_u.py <STOBE-src tree root>"""
import sys, pathlib
root = pathlib.Path(sys.argv[1])

def patch(rel, pairs):
    p = root / rel; s = p.read_text()
    for a, b in pairs:
        if b in s: continue
        assert s.count(a) == 1, f"{rel}: anchor not found: {a[:70]!r}"
        s = s.replace(a, b)
    p.write_text(s); print("patched", p)

patch("src/SettingsWindow.cpp", [
    ('const char *keys[] = {"V", "B", "N", "M", "C", "X", "Z"};',
     'const char *keys[] = {"V", "B", "N", "M", "C", "X", "Z", "U"};'),
])
