#!/usr/bin/env python3
"""Inspect a Kenshi character .mesh: vertex declaration + partData (TEXCOORD1) values.

Kenshi's character shader (data/materials/deferred/skin.hlsl) hides body parts per-vertex:
    uint2 partData : TEXCOORD1;   // x = part index (blood), y = part BITMASK (hide)
    oWet.z = (partData.y & hiddenMask) ? 1 : 0;
Head vertices were baked with partData.y == 0, so no hiddenMask can hide them. This tool
verifies the layout and shows the distribution of partData.y (+ Y-position stats per value)
so we can identify head vertices and patch an unused bit onto them.

Ogre 1.8 binary .mesh chunks: u16 id + u32 len.
  M_MESH 0x3000 > M_SUBMESH 0x4000 / M_GEOMETRY 0x5000
  M_GEOMETRY_VERTEX_DECLARATION 0x5100 > M_GEOMETRY_VERTEX_ELEMENT 0x5110
     (u16 source, u16 type, u16 semantic, u16 offset, u16 index)
  M_GEOMETRY_VERTEX_BUFFER 0x5200 (u16 bindIndex, u16 vertexSize) > DATA 0x5210
Semantics: 1=POSITION 2=BLENDWEIGHTS 3=BLENDINDICES 4=NORMAL 5=DIFFUSE 6=SPECULAR
           7=TEXCOORD 8=BINORMAL 9=TANGENT
Types: 0=FLOAT1 1=FLOAT2 2=FLOAT3 3=FLOAT4 4=COLOUR 5=SHORT1 6=SHORT2 7=SHORT3 8=SHORT4
       9=UBYTE4 10=COLOUR_ARGB 11=COLOUR_ABGR  (Kenshi may use SHORT2/UBYTE4 for partData)
"""
import struct, sys, collections

def u16(b,o): return struct.unpack_from('<H',b,o)[0]
def u32(b,o): return struct.unpack_from('<I',b,o)[0]

SEM={1:'POSITION',2:'BLENDW',3:'BLENDIDX',4:'NORMAL',5:'DIFFUSE',6:'SPECULAR',7:'TEXCOORD',8:'BINORMAL',9:'TANGENT'}
TYP={0:'FLOAT1',1:'FLOAT2',2:'FLOAT3',3:'FLOAT4',4:'COLOUR',5:'SHORT1',6:'SHORT2',7:'SHORT3',8:'SHORT4',9:'UBYTE4',10:'COL_ARGB',11:'COL_ABGR',12:'USHORT1',13:'USHORT2',14:'USHORT4',15:'INT1',16:'INT2',17:'INT3',18:'INT4',19:'UINT1',20:'UINT2',21:'UINT3',22:'UINT4'}
TYPSIZE={0:4,1:8,2:12,3:16,4:4,5:2,6:4,7:6,8:8,9:4,10:4,11:4,12:2,13:4,14:8,15:4,16:8,17:12,18:16,19:4,20:8,21:12,22:16}

def inspect(path):
    b=open(path,'rb').read()
    print(f"== {path} ({len(b)} bytes)")
    # header: u16 id(0x1000) + version string '\n'-terminated
    assert u16(b,0)==0x1000, "not an Ogre mesh"
    o=b.index(b'\n',2)+1
    elements=[]; buffers={}; vcount=None
    depth_end=[len(b)]
    while o+6<=len(b):
        cid=u16(b,o); ln=u32(b,o+2)
        if cid==0x5000:  # M_GEOMETRY (shared): u32 vertexCount, then children
            vcount=u32(b,o+6)
            print(f"  GEOMETRY vertexCount={vcount}")
            o+=10; continue
        if cid==0x5100: o+=6; continue           # decl: descend
        if cid==0x5110:                           # element
            src,typ,sem,off,idx = struct.unpack_from('<5H',b,o+6)
            elements.append((src,typ,sem,off,idx))
            print(f"    elem src={src} type={TYP.get(typ,typ)} sem={SEM.get(sem,sem)} off={off} idx={idx}")
            o+=6+10; continue
        if cid==0x5200:                           # vertex buffer header
            bind,vsz = struct.unpack_from('<2H',b,o+6)
            # child must be 0x5210 DATA
            do=o+10
            did=u16(b,do); dln=u32(b,do+2)
            assert did==0x5210
            buffers[bind]=(vsz, b[do+6:do+6+(vsz*vcount)])
            print(f"  VBUF bind={bind} vsize={vsz} bytes={vsz*vcount}")
            o=do+6+vsz*vcount; continue
        if cid in (0x3000,):
            o+=6; continue
        o+=ln if ln>6 else 6                      # skip other chunks wholesale
        if ln<=6: break
    # find partData: TEXCOORD idx=1
    pe=[e for e in elements if e[2]==7 and e[4]==1]
    pos=[e for e in elements if e[2]==1]
    if not pe: print("  !! no TEXCOORD1 element found"); return
    src,typ,sem,off,idx = pe[0]
    vsz,data = buffers[src]
    print(f"  partData: buffer {src} offset {off} type {TYP.get(typ,typ)}")
    # read y component of partData (second uint of uint2 => offset+size/2)
    esz=TYPSIZE.get(typ,8)
    comp = esz//2
    fmt = {1:'<f',4:'<I',2:'<H'}.get(comp) or '<I'
    ys=collections.Counter()
    ypos_by=collections.defaultdict(list)
    # position element for Y stats
    ppos=pos[0] if pos else None
    for v in range(vcount):
        base=v*vsz+off
        if comp==4: py=struct.unpack_from('<I',data,base+4)[0]
        elif comp==2: py=struct.unpack_from('<H',data,base+2)[0]
        else: py=struct.unpack_from('<f',data,base+4)[0]
        ys[py]+=1
        if ppos is not None:
            psrc,ptyp,_,poff,_=ppos
            pvsz,pdata=buffers[psrc]
            z=struct.unpack_from('<f',pdata,v*pvsz+poff+8)[0]  # z (up in max?) try all later
            y=struct.unpack_from('<f',pdata,v*pvsz+poff+4)[0]
            ypos_by[py].append((y,z))
    print(f"  partData.y distribution ({vcount} verts):")
    for val,cnt in sorted(ys.items()):
        arr=ypos_by.get(val,[])
        if arr:
            ay=sum(a[0] for a in arr)/len(arr); az=sum(a[1] for a in arr)/len(arr)
            miny=min(a[0] for a in arr); maxy=max(a[0] for a in arr)
            minz=min(a[1] for a in arr); maxz=max(a[1] for a in arr)
            print(f"    y=0x{val:08x} n={cnt:6d}  posY avg={ay:8.2f} [{miny:7.2f},{maxy:7.2f}]  posZ avg={az:8.2f} [{minz:7.2f},{maxz:7.2f}]")
        else:
            print(f"    y=0x{val:08x} n={cnt}")

for p in sys.argv[1:]:
    inspect(p)
