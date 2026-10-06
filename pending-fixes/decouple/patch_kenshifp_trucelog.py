#!/usr/bin/env python3
"""KenshiFP: log once when the Stobe truce export resolves, and on each truce on/off edge
(test evidence that the cross-DLL bridge works). Usage: patch_kenshifp_trucelog.py <KenshiFP root>"""
import sys, pathlib
p = pathlib.Path(sys.argv[1]) / "client" / "kenshifp_client.c"
s = p.read_text(encoding="utf-8", errors="surrogateescape")
old = """        if (mod) fn = (stobe_truce_active_t)(void *)GetProcAddress(mod, "StobeFightTruceActive");
        if (!fn) return 0;
    }
    return fn() != 0;
}"""
new = """        if (mod) fn = (stobe_truce_active_t)(void *)GetProcAddress(mod, "StobeFightTruceActive");
        if (!fn) return 0;
        logline("[stobe] truce bridge: StobeFightTruceActive resolved");
    }
    static int last = -1;
    int on = fn() != 0;
    if (on != last) { if (last >= 0 || on) logline("[stobe] truce bridge: active=%d", on); last = on; }
    return on;
}"""
if new in s:
    print("already applied"); sys.exit(0)
assert s.count(old) == 1, "anchor not found"
p.write_text(s.replace(old, new), encoding="utf-8", errors="surrogateescape")
print("patched", p)
