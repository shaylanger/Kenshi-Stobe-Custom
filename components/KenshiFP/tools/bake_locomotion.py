#!/usr/bin/env python3
"""Bake Destreza's Humanoid_ locomotion clips into a compact binary KenshiFP loads at runtime.

Source (Destreza, the ANIMATION SOURCE -- not Kenshi):
  - skeleton.json : the Humanoid_ source rest pose (73 bones {name,parent,pos,rot}, Z-up, cm)
  - anims.json    : {clips:[{name,fps,keys,length,tracks:{bone:{rot:[k*4 xyzw],pos:[k*3]}}}]}

Output: locomotion.kfa -- little-endian, self-describing by bone NAME so the C mod maps
Humanoid_ -> Kenshi Bip01 with its own pair table. We do NO coordinate conversion here: the
retarget (direction-transfer, ported from EliteAnimator.cs) consumes the raw source data and
resolves the Z-up/Y-up + scale difference itself. This baker is pure, faithful data conversion.

Binary layout (all LE):
  magic  'KFA1'                     (4 bytes)
  u32 numBones
  u32 numClips
  bones[numBones]:
     u16 nameLen; char name[nameLen]
     i32 parent                     (-1 = root)
     f32 restPos[3]                 (x,y,z, as authored: cm, Z-up)
     f32 restRot[4]                 (x,y,z,w)
  clips[numClips]:
     u16 nameLen; char name[nameLen]
     f32 fps
     u32 numKeys
     f32 length                     (seconds)
     per bone (numBones, bone order):
       u8 hasTrack (0/1)
       if hasTrack:
         f32 rot[numKeys*4]         (xyzw per key)
         f32 pos[numKeys*3]         (xyz  per key)
"""
import json, struct, sys, os

SRC = "/media/jit/ByteGlyph/Destreza/godot/game/assets/elite"
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                   "..", "re_plugin", "mod", "locomotion.kfa")

def main():
    skel = json.load(open(os.path.join(SRC, "skeleton.json")))
    anim = json.load(open(os.path.join(SRC, "anims.json")))
    bones = skel["bones"]
    clips = anim["clips"]
    print(f"skeleton: {len(bones)} bones, {skel.get('up')}-up {skel.get('unit')}; {len(clips)} clips")

    buf = bytearray()
    def u8(v):  buf.extend(struct.pack("<B", v))
    def u16(v): buf.extend(struct.pack("<H", v))
    def u32(v): buf.extend(struct.pack("<I", v))
    def i32(v): buf.extend(struct.pack("<i", v))
    def f32(v): buf.extend(struct.pack("<f", v))
    def s(v):   b=v.encode("utf-8"); u16(len(b)); buf.extend(b)
    def farr(a):
        buf.extend(struct.pack("<%df" % len(a), *[float(x) for x in a]))

    buf.extend(b"KFA1")
    u32(len(bones)); u32(len(clips))

    for b in bones:
        s(b["name"]); i32(int(b["parent"]))
        p=b["pos"]; r=b["rot"]
        f32(p[0]); f32(p[1]); f32(p[2])
        f32(r[0]); f32(r[1]); f32(r[2]); f32(r[3])

    for c in clips:
        name=c["name"]; fps=float(c["fps"]); keys=int(c["keys"]); length=float(c["length"])
        tracks=c["tracks"]
        s(name); f32(fps); u32(keys); f32(length)
        miss_r=miss_p=0
        for b in bones:
            t=tracks.get(b["name"])
            if not t:
                u8(0); continue
            rot=t.get("rot"); pos=t.get("pos")
            # tracks store k*4 rot / k*3 pos; tolerate a single (static) key by tiling
            if rot is None or pos is None:
                u8(0); continue
            if len(rot)!=keys*4:
                if len(rot)==4: rot=rot*keys; miss_r+=1
                else: rot=(rot+[0,0,0,1]*keys)[:keys*4]
            if len(pos)!=keys*3:
                if len(pos)==3: pos=pos*keys; miss_p+=1
                else: pos=(pos+[0,0,0]*keys)[:keys*3]
            u8(1); farr(rot); farr(pos)
        print(f"  clip {name:32s} keys={keys:3d} fps={fps:.1f} len={length:.2f}"
              + (f"  [tiled rot:{miss_r} pos:{miss_p}]" if (miss_r or miss_p) else ""))

    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with open(OUT, "wb") as f:
        f.write(buf)
    print(f"\nwrote {OUT}  ({len(buf)} bytes)")

if __name__ == "__main__":
    main()
