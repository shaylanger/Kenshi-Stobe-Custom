#!/usr/bin/env python3
"""Dump an Ogre v1 binary .skeleton (Kenshi) — bone tree, bind pose, animation list.

Purpose: ground-truth Kenshi's Bip01 bind conventions for the KenshiFP retarget
(kfp_locomotion.h). Prints local bind (pos, rot) per bone plus FK'd GLOBAL bind
positions/rotations so we can measure skeleton-space axes (up / fwd / right)
empirically instead of guessing coordinate conversions.

NOTE: chunk lengths lie (Ogre's calcBoneSize excludes the name string), so we
parse the stream SEQUENTIALLY by structure, like Ogre's own deserializer:
  0x1000 header: ver str    0x1010 blendmode: u16
  0x2000 bone: str name, u16 handle, vec3 pos, quat(x,y,z,w) [+vec3 scale if len==48]
  0x3000 bone parent: u16 child, u16 parent
  0x4000 animation: str name, f32 len   0x4010 baseinfo: str, f32
  0x4100 track: u16 bone    0x4110 keyframe: f32 t, quat, vec3 [+vec3 scale if len==50]
strings are newline(0x0A)-terminated; all little-endian
"""
import struct, sys

def q_mul(a, b):
    aw, ax, ay, az = a; bw, bx, by, bz = b
    return (aw*bw - ax*bx - ay*by - az*bz,
            aw*bx + ax*bw + ay*bz - az*by,
            aw*by - ax*bz + ay*bw + az*bx,
            aw*bz + ax*by - ay*bx + az*bw)

def q_rot(q, v):
    w, x, y, z = q
    u = (x, y, z)
    uv = (u[1]*v[2]-u[2]*v[1], u[2]*v[0]-u[0]*v[2], u[0]*v[1]-u[1]*v[0])
    uuv = (u[1]*uv[2]-u[2]*uv[1], u[2]*uv[0]-u[0]*uv[2], u[0]*uv[1]-u[1]*uv[0])
    return tuple(v[i] + 2.0*(w*uv[i] + uuv[i]) for i in range(3))

class R:
    def __init__(self, b): self.b, self.o = b, 0
    def u16(self): v, = struct.unpack_from("<H", self.b, self.o); self.o += 2; return v
    def u32(self): v, = struct.unpack_from("<I", self.b, self.o); self.o += 4; return v
    def f32(self): v, = struct.unpack_from("<f", self.b, self.o); self.o += 4; return v
    def s(self):
        e = self.b.index(b"\n", self.o)
        v = self.b[self.o:e].decode("utf-8", "replace"); self.o = e + 1; return v
    def vec3(self): v = struct.unpack_from("<3f", self.b, self.o); self.o += 12; return v
    def quat(self):
        x, y, z, w = struct.unpack_from("<4f", self.b, self.o); self.o += 16
        return (w, x, y, z)
    def done(self): return self.o + 6 > len(self.b)

def main(path):
    r = R(open(path, "rb").read())
    assert r.u16() == 0x1000, "no header"
    ver = r.s()
    print(f"# {path}\n# serializer {ver}, {len(r.b)} bytes")

    bones, parents, anims = {}, {}, []
    ntracks = nkeys = 0
    while not r.done():
        at = r.o
        cid, ln = r.u16(), r.u32()
        if cid == 0x1010:
            r.u16()
        elif cid == 0x2000:
            name = r.s(); h = r.u16(); pos = r.vec3(); rot = r.quat()
            if ln == 48: r.vec3()
            bones[h] = dict(name=name, pos=pos, rot=rot)
        elif cid == 0x3000:
            c = r.u16(); parents[c] = r.u16()
        elif cid == 0x4000:
            anims.append((r.s(), r.f32()))
        elif cid == 0x4010:
            r.s(); r.f32()
        elif cid == 0x4100:
            r.u16(); ntracks += 1
        elif cid == 0x4110:
            r.f32(); r.quat(); r.vec3()
            if ln == 50: r.vec3()
            nkeys += 1
        elif cid == 0x5000:
            r.s(); r.f32()
        else:
            print(f"# !! unknown chunk {cid:#06x} len={ln} @{at} -- stopping")
            break

    # FK to global bind
    glob = {}
    def fk(h):
        if h in glob: return glob[h]
        bn = bones[h]
        if h in parents:
            pp, pr = fk(parents[h])
            rp = q_rot(pr, bn["pos"])
            glob[h] = (tuple(pp[i] + rp[i] for i in range(3)), q_mul(pr, bn["rot"]))
        else:
            glob[h] = (bn["pos"], bn["rot"])
        return glob[h]

    print(f"\n{len(bones)} bones, {len(anims)} animations ({ntracks} tracks, {nkeys} keys)\n")
    print(f"{'h':>3} {'bone':<24} {'parent':<24} "
          f"{'local pos':<27} {'local rot (w,x,y,z)':<31} {'GLOBAL pos':<27}")
    for h in sorted(bones):
        bn = bones[h]
        par = bones[parents[h]]["name"] if h in parents else "-"
        wp, wr = fk(h)
        lp = "({:7.3f},{:7.3f},{:7.3f})".format(*bn["pos"])
        lr = "({:6.3f},{:6.3f},{:6.3f},{:6.3f})".format(*bn["rot"])
        gp = "({:7.3f},{:7.3f},{:7.3f})".format(*wp)
        print(f"{h:>3} {bn['name']:<24} {par:<24} {lp:<27} {lr:<31} {gp:<27}")

    # measure skeleton-space axes (spec §0): fwd = foot->toe, right = handL->handR
    by = {bn["name"]: h for h, bn in bones.items()}
    def gpos(nm): return fk(by[nm])[0] if nm in by else None
    print("\n# measured skeleton-space axes (bind):")
    for a, c in (("Bip01 L Foot", "Bip01 L Toe0"), ("Bip01 R Foot", "Bip01 R Toe0")):
        pa, pc = gpos(a), gpos(c)
        if pa and pc:
            d = tuple(pc[i] - pa[i] for i in range(3))
            print(f"#   {a} -> {c}: ({d[0]:.4f}, {d[1]:.4f}, {d[2]:.4f})")
    lh, rh = gpos("Bip01 L Hand"), gpos("Bip01 R Hand")
    if lh and rh:
        d = tuple(rh[i] - lh[i] for i in range(3))
        print(f"#   L Hand -> R Hand: ({d[0]:.4f}, {d[1]:.4f}, {d[2]:.4f})")
    hd, pel = gpos("Bip01 Head"), gpos("Bip01 Pelvis")
    if hd and pel:
        d = tuple(hd[i] - pel[i] for i in range(3))
        print(f"#   Pelvis -> Head:   ({d[0]:.4f}, {d[1]:.4f}, {d[2]:.4f})")

    if anims:
        print("\n# animations:")
        for nm, ln in anims:
            print(f"#   {nm:<48} {ln:7.2f}s")

if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else
         "/home/jit/.steam/debian-installation/steamapps/common/Kenshi/data/character/meshes/male_skeleton/male_skeleton.skeleton")
