#!/usr/bin/env python3
"""Minimal Kenshi FCS (.base/.mod, file type 16) reader -> list of records.
Each record: type, id, name, sid, bools/floats/ints/vec3/vec4/strings/files dicts, refs {cat: [(sid, v0, v1, v2)]}."""
import struct, sys

class R:
    def __init__(s, b): s.b = b; s.p = 0
    def i(s): v = struct.unpack_from('<i', s.b, s.p)[0]; s.p += 4; return v
    def f(s): v = struct.unpack_from('<f', s.b, s.p)[0]; s.p += 4; return v
    def bo(s): v = s.b[s.p] != 0; s.p += 1; return v
    def st(s):
        n = s.i()
        v = s.b[s.p:s.p+n].decode('utf-8', 'replace'); s.p += n; return v

def read(path):
    r = R(open(path, 'rb').read())
    ft = r.i()
    assert ft in (16, 17), ft
    if ft == 17:
        hsize = r.i(); r.p += hsize          # length-prefixed header
    else:
        # type 16 header in this install: int version, str author, str description, str dependencies, str references
        version = r.i(); author = r.st(); desc = r.st(); deps = r.st(); refs = r.st()
    last_id = r.i()
    n = r.i()
    out = []
    for _ in range(n):
        rec = {}
        r.i()  # instance/dummy
        rec['type'] = r.i(); rec['id'] = r.i(); rec['name'] = r.st(); rec['sid'] = r.st()
        rec['flags'] = r.i()
        rec['bools'] = {r.st(): r.bo() for _ in range(r.i())}
        rec['floats'] = {r.st(): r.f() for _ in range(r.i())}
        rec['ints'] = {r.st(): r.i() for _ in range(r.i())}
        rec['vec3'] = {r.st(): (r.f(), r.f(), r.f()) for _ in range(r.i())}
        rec['vec4'] = {r.st(): (r.f(), r.f(), r.f(), r.f()) for _ in range(r.i())}
        rec['strings'] = {r.st(): r.st() for _ in range(r.i())}
        rec['files'] = {r.st(): r.st() for _ in range(r.i())}
        refs = {}
        for _ in range(r.i()):
            cat = r.st(); lst = []
            for _ in range(r.i()):
                lst.append((r.st(), r.i(), r.i(), r.i()))
            refs[cat] = lst
        rec['refs'] = refs
        inst = []
        for _ in range(r.i()):
            iid = r.st(); tgt = r.st()
            r.p += 7 * 4
            states = [r.st() for _ in range(r.i())]
            inst.append((iid, tgt, states))
        rec['inst'] = inst
        out.append(rec)
    return out

if __name__ == '__main__':
    recs = read(sys.argv[1])
    import collections
    c = collections.Counter(r['type'] for r in recs)
    print(len(recs), 'records'); print(sorted(c.items()))
