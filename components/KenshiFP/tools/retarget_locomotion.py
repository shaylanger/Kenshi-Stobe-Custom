#!/usr/bin/env python3
"""Offline retarget: Destreza Humanoid_ clips -> Kenshi Bip01 LOCAL rotation tracks (KFA2).

This replaces the in-game retarget math entirely. Existing Kenshi animation mods (dissected:
SWG rifle anims 2840444811, COMBAT overhaul 1691422256) all ship animations authored DIRECTLY
against the vanilla Bip01 bind pose as bind-relative, rotation-only, in-place tracks -- nobody
retargets at runtime. We do the same: the direction-transfer (re/LOCOMOTION_SPEC.md, ported
from EliteAnimator.cs) runs HERE, against the real male_skeleton.skeleton bind pose, and the
result is baked as ready-to-play Bip01-local quaternions. The KenshiFP runtime just samples
and writes locals onto manuallyControlled bones.

Also emits validation renders (matplotlib stick figures, source vs retargeted target) so the
retarget is verified VISUALLY before ever launching the game.

KFA2 layout (little-endian):
  magic 'KFA2'
  u32 numBones                      (target Bip01 bones, parent-before-child order)
  u32 numClips
  bones[numBones]:
     u16 nameLen; char name[]
     u8  flags                      (1 = hold: park at bind local, never tracked
                                     2 = optional-hips: runtime plays track only if loco_hips=1)
     f32 bindLocalRot[4] (xyzw)     (informational / offline debug)
  clips[numClips]:
     u16 nameLen; char name[]
     f32 fps; u32 numKeys; f32 length
     per bone: u8 hasTrack; if: f32 rot[numKeys*4] (xyzw, LOCAL bone rotation per key)
"""
import json, struct, sys, os, math
import numpy as np

KENSHI_SKEL = os.path.expanduser(
    "~/.steam/debian-installation/steamapps/common/Kenshi/data/character/meshes/"
    "male_skeleton/male_skeleton.skeleton")
SRC = "/media/jit/ByteGlyph/Destreza/godot/game/assets/elite"
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "re_plugin", "mod", "locomotion.kfa")

# ---------------- quaternion helpers (w,x,y,z), numpy ----------------
def qmul(a, b):
    aw, ax, ay, az = a; bw, bx, by, bz = b
    return np.array([aw*bw - ax*bx - ay*by - az*bz,
                     aw*bx + ax*bw + ay*bz - az*by,
                     aw*by - ax*bz + ay*bw + az*bx,
                     aw*bz + ax*by - ay*bx + az*bw])
def qconj(q): return np.array([q[0], -q[1], -q[2], -q[3]])
def qnorm(q):
    n = np.linalg.norm(q)
    return q / n if n > 1e-12 else np.array([1.0, 0, 0, 0])
def qrot(q, v):
    w = q[0]; u = q[1:]
    uv = np.cross(u, v); uuv = np.cross(u, uv)
    return v + 2.0 * (w * uv + uuv)
def qslerp(a, b, t):
    d = float(np.dot(a, b))
    if d < 0: b = -b; d = -d
    if d > 0.9995: return qnorm(a + (b - a) * t)
    th = math.acos(min(1.0, d)); s = math.sin(th)
    return qnorm(a * (math.sin((1 - t) * th) / s) + b * (math.sin(t * th) / s))
def q_shortest_arc(a, b):
    d = float(np.dot(a, b))
    if d > 0.999999: return np.array([1.0, 0, 0, 0])
    if d < -0.999999:
        ax = np.cross([1.0, 0, 0], a)
        if np.dot(ax, ax) < 1e-12: ax = np.cross([0, 1.0, 0], a)
        ax = ax / np.linalg.norm(ax)
        return np.array([0.0, ax[0], ax[1], ax[2]])
    ax = np.cross(a, b); h = math.acos(max(-1.0, min(1.0, d))) * 0.5
    ax = ax / np.linalg.norm(ax) * math.sin(h)
    return qnorm(np.array([math.cos(h), ax[0], ax[1], ax[2]]))

# ---------------- Kenshi .skeleton parse (sequential; chunk lens lie for strings) ----------------
def parse_kenshi_skeleton(path):
    b = open(path, "rb").read(); o = [0]
    def u16(): v, = struct.unpack_from("<H", b, o[0]); o[0] += 2; return v
    def u32(): v, = struct.unpack_from("<I", b, o[0]); o[0] += 4; return v
    def f32(): v, = struct.unpack_from("<f", b, o[0]); o[0] += 4; return v
    def rs():
        e = b.index(b"\n", o[0]); v = b[o[0]:e].decode("utf-8", "replace"); o[0] = e + 1; return v
    assert u16() == 0x1000; rs()
    bones, parents = {}, {}
    while o[0] + 6 <= len(b):
        cid = u16(); ln = u32()
        if cid == 0x1010: u16()
        elif cid == 0x2000:
            nm = rs(); h = u16()
            px, py, pz = f32(), f32(), f32(); qx, qy, qz, qw = f32(), f32(), f32(), f32()
            if ln == 48: f32(); f32(); f32()
            bones[h] = dict(name=nm, pos=np.array([px, py, pz]), rot=qnorm(np.array([qw, qx, qy, qz])))
        elif cid == 0x3000:
            c = u16(); parents[c] = u16()
        else:
            break   # animations start; bind topology is fully read
    order = sorted(bones)
    byname, plist = {}, {}
    for h in order:
        byname[bones[h]["name"]] = h
        plist[h] = parents.get(h, -1)
    # bind global FK
    G = {}
    for h in order:   # handles are parent-ordered in Kenshi files
        p = plist[h]
        if p < 0: G[h] = (bones[h]["pos"].copy(), bones[h]["rot"].copy())
        else:
            pp, pr = G[p]
            G[h] = (pp + qrot(pr, bones[h]["pos"]), qnorm(qmul(pr, bones[h]["rot"])))
    return dict(bones=bones, parents=plist, byname=byname, glob=G)

# ---------------- source (Destreza) ----------------
def load_source():
    skel = json.load(open(os.path.join(SRC, "skeleton.json")))
    anim = json.load(open(os.path.join(SRC, "anims.json")))
    bones = skel["bones"]
    byname = {b["name"]: i for i, b in enumerate(bones)}
    rest_wrot = [None] * len(bones); rest_wpos = [None] * len(bones)
    for i, b in enumerate(bones):
        r = b["rot"]; q = qnorm(np.array([r[3], r[0], r[1], r[2]])); p = np.array(b["pos"]) * 0.01
        par = b["parent"]
        if par < 0: rest_wrot[i] = q; rest_wpos[i] = p
        else:
            rest_wrot[i] = qnorm(qmul(rest_wrot[par], q))
            rest_wpos[i] = rest_wpos[par] + qrot(rest_wrot[par], p)
    return bones, byname, rest_wrot, rest_wpos, anim["clips"]

def sample_src(clip, bones, byname, i, key):
    b = bones[i]
    tr = clip["tracks"].get(b["name"])
    r = b["rot"]; q = qnorm(np.array([r[3], r[0], r[1], r[2]])); p = np.array(b["pos"])
    if tr:
        rot = tr.get("rot"); pos = tr.get("pos")
        if rot:
            if len(rot) == 4: k = 0
            else: k = min(key, len(rot)//4 - 1)
            q = qnorm(np.array([rot[k*4+3], rot[k*4], rot[k*4+1], rot[k*4+2]]))
        if pos:
            if len(pos) == 3: k = 0
            else: k = min(key, len(pos)//3 - 1)
            p = np.array(pos[k*3:k*3+3])
    return q, p * 0.01

# ---------------- retarget table (mirrors kfp_locomotion.h LOCO_MAP) ----------------
# (target, targetChild(dir), source, sourceChild, mode)
# mode: aim    = direction-transfer (bone->child matched to source)
#       hips   = full source orientation delta (pelvis)
#       orient = full source orientation delta, written as a normal track (hands: no
#                stable child to aim, and leaving them game-animated under OUR forearms
#                gave mismatched wrists)
#       hold   = parked at bind (clavicles: aiming thrusts shoulders; toes: flat at bind
#                beats the game blending an unrelated clip's toe pose under our feet)
MAP = [
    ("Bip01 Pelvis",     "Bip01 Spine",     "Humanoid_-Pelvis",     "Humanoid_-Spine",     "hips"),
    ("Bip01 Spine",      "Bip01 Spine1",    "Humanoid_-Spine",      "Humanoid_-Spine1",    "aim"),
    ("Bip01 Spine1",     "Bip01 Spine2",    "Humanoid_-Spine1",     "Humanoid_-Spine2",    "aim"),
    ("Bip01 Spine2",     "Bip01 Neck",      "Humanoid_-Spine2",     "Humanoid_-Neck",      "aim"),
    ("Bip01 L Clavicle", None,              None,                   None,                  "hold"),
    ("Bip01 R Clavicle", None,              None,                   None,                  "hold"),
    ("Bip01 L UpperArm", "Bip01 L Forearm", "Humanoid_-L-UpperArm", "Humanoid_-L-Forearm", "aim"),
    ("Bip01 L Forearm",  "Bip01 L Hand",    "Humanoid_-L-Forearm",  "Humanoid_-L-Hand",    "aim"),
    ("Bip01 L Hand",     None,              "Humanoid_-L-Hand",     None,                  "orient"),
    ("Bip01 R UpperArm", "Bip01 R Forearm", "Humanoid_-R-UpperArm", "Humanoid_-R-Forearm", "aim"),
    ("Bip01 R Forearm",  "Bip01 R Hand",    "Humanoid_-R-Forearm",  "Humanoid_-R-Hand",    "aim"),
    ("Bip01 R Hand",     None,              "Humanoid_-R-Hand",     None,                  "orient"),
    ("Bip01 L Thigh",    "Bip01 L Calf",    "Humanoid_-L-Thigh",    "Humanoid_-L-Calf",    "aim"),
    ("Bip01 L Calf",     "Bip01 L Foot",    "Humanoid_-L-Calf",     "Humanoid_-L-Foot",    "aim"),
    ("Bip01 L Foot",     "Bip01 L Toe0",    "Humanoid_-L-Foot",     "Humanoid_-L-Toe0",    "aim"),
    ("Bip01 L Toe0",     None,              None,                   None,                  "hold"),
    ("Bip01 R Thigh",    "Bip01 R Calf",    "Humanoid_-R-Thigh",    "Humanoid_-R-Calf",    "aim"),
    ("Bip01 R Calf",     "Bip01 R Foot",    "Humanoid_-R-Calf",     "Humanoid_-R-Foot",    "aim"),
    ("Bip01 R Foot",     "Bip01 R Toe0",    "Humanoid_-R-Foot",     "Humanoid_-R-Toe0",    "aim"),
    ("Bip01 R Toe0",     None,              None,                   None,                  "hold"),
]
UPRIGHT_SPINE = 0.5   # spec §C step 2: lerp spine aim dirs toward model-up
FOOT_MAX_PITCH = True # clamp foot toe-down pitch at the bind pitch (spec §F foot-flatten,
                      # simplified): the source rig's ankle geometry aims Kenshi feet ~45deg
                      # down, sinking toes ~0.4 units underground
ARM_SPLAY = 0.14      # lateral push (tan ~8deg) added to the upper-arm aim away from the
                      # body midline -- raw retarget hugs the arms against the ribs at jog
                      # (spec §F arm-mod stack, minimal version)
HAND_SOFTEN = 0.65      # hands: blend weight of the source hand orientation over bind (1 =
                        # full source; lower = calmer wrists, fixes inward wrist curl)
HAND_SOFTEN_JOG = 0.35  # jog clips map the source hand twist worse (hands curled upward
                        # at sprint) -- keep the wrists much closer to bind there

def ortho_basis(r, f, u):
    u = u / np.linalg.norm(u)
    f = f - u * np.dot(f, u); f = f / np.linalg.norm(f)
    r = r - u * np.dot(r, u) - f * np.dot(r, f); r = r / np.linalg.norm(r)
    return r, f, u

def build_conv(tk, s_byname, s_wpos):
    g = lambda n: tk["glob"][tk["byname"][n]][0]
    f_t = (g("Bip01 L Toe0") - g("Bip01 L Foot")) + (g("Bip01 R Toe0") - g("Bip01 R Foot"))
    r_t = g("Bip01 R Hand") - g("Bip01 L Hand")
    u_t = g("Bip01 Head") - g("Bip01 Pelvis")
    sp = lambda n: s_wpos[s_byname[n]]
    f_s = (sp("Humanoid_-L-Toe0") - sp("Humanoid_-L-Foot")) + (sp("Humanoid_-R-Toe0") - sp("Humanoid_-R-Foot"))
    r_s = sp("Humanoid_-R-Hand") - sp("Humanoid_-L-Hand")
    u_s = sp("Humanoid_-Head") - sp("Humanoid_-Pelvis")
    r_t, f_t, u_t = ortho_basis(r_t, f_t, u_t)
    r_s, f_s, u_s = ortho_basis(r_s, f_s, u_s)
    Bt = np.column_stack([r_t, f_t, u_t]); Bs = np.column_stack([r_s, f_s, u_s])
    M = Bt @ Bs.T
    det = float(np.linalg.det(M))
    upT = u_t   # target model-up for spine uprighting
    return M, det, upT

def conv_dir(M, d): return M @ d
def conv_q(M, det, q):
    v = M @ q[1:]
    return qnorm(np.array([q[0], det*v[0], det*v[1], det*v[2]]))

def retarget_clip(clip, s_bones, s_byname, s_rest_wrot, tk, M, det, upT):
    """-> dict target bone name -> [numKeys][4 wxyz] LOCAL rotations (+ same for pelvis)"""
    nkeys = int(clip["keys"])
    parents = tk["parents"]; byname = tk["byname"]; bones = tk["bones"]
    # slot setup
    slots = []
    for (tb, tc, sb, sc, mode) in MAP:
        h = byname[tb]
        bindL = bones[h]["rot"]
        bindG = tk["glob"][h][1]
        parentG = qnorm(qmul(bindG, qconj(bindL)))
        childOff = None
        if tc is not None:
            co = bones[byname[tc]]["pos"]
            childOff = co / np.linalg.norm(co)
        bindDir = None
        if tc is not None:
            d = tk["glob"][byname[tc]][0] - tk["glob"][h][0]
            bindDir = d / np.linalg.norm(d)
        slots.append(dict(tb=tb, h=h, mode=mode, bindL=bindL, bindG=bindG,
                          parentG0=parentG, childOff=childOff, bindDir=bindDir,
                          src=s_byname.get(sb, -1) if sb else -1,
                          srcChild=s_byname.get(sc, -1) if sc else -1,
                          parentSlot=None))
    index = {s["tb"]: i for i, s in enumerate(slots)}
    for s in slots:
        ph = parents[s["h"]]
        pname = bones[ph]["name"] if ph >= 0 else None
        s["parentSlot"] = index.get(pname)   # None -> anchor at bind parent (root)
    spine_slots = {"Bip01 Spine", "Bip01 Spine1", "Bip01 Spine2"}

    out = {s["tb"]: np.zeros((nkeys, 4)) for s in slots}
    nb = len(s_bones)
    for k in range(nkeys):
        # source FK at key k
        wrot = [None]*nb; wpos = [None]*nb
        for i, b in enumerate(s_bones):
            q, p = sample_src(clip, s_bones, s_byname, i, k)
            par = b["parent"]
            if par < 0: wrot[i] = q; wpos[i] = p
            else:
                wrot[i] = qnorm(qmul(wrot[par], q))
                wpos[i] = wpos[par] + qrot(wrot[par], p)
        # direction transfer, parent before child
        glob = [None]*len(slots)
        for si, s in enumerate(slots):
            parentG = glob[s["parentSlot"]] if s["parentSlot"] is not None else s["parentG0"]
            if s["mode"] == "hold":
                glob[si] = qnorm(qmul(parentG, s["bindL"]))
                out[s["tb"]][k] = s["bindL"]
                continue
            if s["mode"] in ("hips", "orient"):
                restG = qnorm(qmul(parentG, s["bindL"]))
                delta = qnorm(qmul(conv_q(M, det, wrot[s["src"]]),
                                   qconj(conv_q(M, det, s_rest_wrot[s["src"]]))))
                qF = qnorm(qmul(delta, restG))
                glob[si] = qF
                lq = qnorm(qmul(qconj(parentG), qF))
                if s["mode"] == "orient" and "Hand" in s["tb"]:
                    soften = HAND_SOFTEN_JOG if "Jog" in clip["name"] else HAND_SOFTEN
                    lq = qslerp(s["bindL"], lq, soften)   # calmer wrists
                out[s["tb"]][k] = lq
                continue
            want = conv_dir(M, wpos[s["srcChild"]] - wpos[s["src"]])
            n = np.linalg.norm(want)
            if n < 1e-6:
                glob[si] = qnorm(qmul(parentG, s["bindL"]))
                out[s["tb"]][k] = s["bindL"]
                continue
            want = want / n
            if s["tb"] in spine_slots:
                want = want + (upT - want) * UPRIGHT_SPINE
                want = want / np.linalg.norm(want)
            if "UpperArm" in s["tb"]:
                # splay the arm away from the body midline (Kenshi left = +X)
                lat = 1.0 if " L " in s["tb"] else -1.0
                want = want + np.array([lat * ARM_SPLAY, 0.0, 0.0])
                want = want / np.linalg.norm(want)
            if FOOT_MAX_PITCH and s["tb"].endswith("Foot") and s["bindDir"] is not None:
                ny = s["bindDir"][1]          # bind toe-dir up-component (max toe-down pitch)
                if want[1] < ny:
                    hw = math.sqrt(want[0]*want[0] + want[2]*want[2])
                    h = math.sqrt(max(0.0, 1.0 - ny*ny))
                    if hw > 1e-6:
                        want = np.array([want[0]/hw*h, ny, want[2]/hw*h])
            qCand = qnorm(qmul(qmul(conv_q(M, det, wrot[s["src"]]),
                                    qconj(conv_q(M, det, s_rest_wrot[s["src"]]))),
                               s["bindG"]))
            fwd = qrot(qCand, s["childOff"]); fwd = fwd / np.linalg.norm(fwd)
            qF = qnorm(qmul(q_shortest_arc(fwd, want), qCand))
            glob[si] = qF
            out[s["tb"]][k] = qnorm(qmul(qconj(parentG), qF))
    return out

# ---------------- validation render ----------------
def fk_with_locals(tk, local_over):
    """FK the Kenshi skeleton with slot locals overridden -> {handle: global pos}"""
    bones = tk["bones"]; parents = tk["parents"]
    G = {}
    for h in sorted(bones):
        p = parents[h]
        lq = local_over.get(bones[h]["name"], bones[h]["rot"])
        lp = bones[h]["pos"]
        if p < 0: G[h] = (lp.copy(), qnorm(np.array(lq)))
        else:
            pp, pr = G[p]
            G[h] = (pp + qrot(pr, lp), qnorm(qmul(pr, np.array(lq))))
    return G

def render_check(tk, s_bones, s_byname, clip, tracks, path):
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    nkeys = int(clip["keys"])
    phases = [0.0, 0.25, 0.5, 0.75]
    fig, axes = plt.subplots(2, len(phases), figsize=(4*len(phases), 9))
    for col, ph in enumerate(phases):
        k = min(nkeys - 1, int(ph * nkeys))
        # source stick figure (view: source fwd=+Y so plot X vs Z front view)
        wrot = [None]*len(s_bones); wpos = [None]*len(s_bones)
        for i, b in enumerate(s_bones):
            q, p = sample_src(clip, s_bones, s_byname, i, k)
            par = b["parent"]
            if par < 0: wrot[i] = q; wpos[i] = p
            else:
                wrot[i] = qnorm(qmul(wrot[par], q))
                wpos[i] = wpos[par] + qrot(wrot[par], p)
        ax = axes[0][col]
        for i, b in enumerate(s_bones):
            par = b["parent"]
            if par < 0: continue
            xs = [wpos[par][1], wpos[i][1]]; zs = [wpos[par][2], wpos[i][2]]
            ax.plot(xs, zs, "o-", ms=2, lw=1, color="tab:blue")
        ax.set_title(f"source  phase={ph:.2f} (side: +Y fwd, +Z up)")
        ax.set_aspect("equal"); ax.grid(True, alpha=0.3)
        # target stick figure with retargeted locals (side view: +Z fwd, +Y up)
        over = {tb: tracks[tb][k] for tb in tracks}
        G = fk_with_locals(tk, over)
        ax = axes[1][col]
        for h in sorted(tk["bones"]):
            p = tk["parents"][h]
            if p < 0: continue
            zs = [G[p][0][2], G[h][0][2]]; ys = [G[p][0][1], G[h][0][1]]
            ax.plot(zs, ys, "o-", ms=2, lw=1, color="tab:red")
        ax.set_title(f"KENSHI retarget  phase={ph:.2f} (side: +Z fwd, +Y up)")
        ax.set_aspect("equal"); ax.grid(True, alpha=0.3)
    fig.suptitle(f"clip: {clip['name']}")
    fig.tight_layout()
    fig.savefig(path, dpi=90)
    plt.close(fig)
    print(f"render -> {path}")

# ---------------- KFA2 writer ----------------
def write_kfa2(tk, clip_tracks, clips, out_path):
    buf = bytearray()
    def u8(v):  buf.extend(struct.pack("<B", v))
    def u16(v): buf.extend(struct.pack("<H", v))
    def u32(v): buf.extend(struct.pack("<I", v))
    def f32(v): buf.extend(struct.pack("<f", float(v)))
    def s(v):   e = v.encode(); u16(len(e)); buf.extend(e)
    names = [m[0] for m in MAP]
    flags = {m[0]: (1 if m[4] == "hold" else 2 if m[4] == "hips" else 0) for m in MAP}  # orient/aim -> 0
    buf.extend(b"KFA2"); u32(len(names)); u32(len(clips))
    for nm in names:
        s(nm); u8(flags[nm])
        q = tk["bones"][tk["byname"][nm]]["rot"]
        f32(q[1]); f32(q[2]); f32(q[3]); f32(q[0])   # xyzw
    for clip, tracks in zip(clips, clip_tracks):
        s(clip["name"]); f32(clip["fps"]); u32(int(clip["keys"])); f32(clip["length"])
        for nm in names:
            tr = tracks.get(nm)
            if tr is None: u8(0); continue
            u8(1)
            for k in range(int(clip["keys"])):
                q = tr[k]
                f32(q[1]); f32(q[2]); f32(q[3]); f32(q[0])   # xyzw
    with open(out_path, "wb") as f:
        f.write(buf)
    print(f"wrote {out_path} ({len(buf)} bytes)")

# ---------------- main ----------------
s_rest_wrot_arr = None   # set in main; used by retarget_clip
def main():
    global s_rest_wrot_arr
    render_dir = sys.argv[1] if len(sys.argv) > 1 else "."
    tk = parse_kenshi_skeleton(KENSHI_SKEL)
    s_bones, s_byname, s_rest_wrot, s_rest_wpos, clips = load_source()
    s_rest_wrot_arr = s_rest_wrot
    M, det, upT = build_conv(tk, s_byname, s_rest_wpos)
    np.set_printoptions(precision=3, suppress=True)
    print(f"conv M=\n{M}\ndet={det:.3f}  upT={upT}")
    clip_tracks = []
    for c in clips:
        tr = retarget_clip(c, s_bones, s_byname, s_rest_wrot, tk, M, det, upT)
        clip_tracks.append(tr)
        print(f"  retargeted {c['name']:32s} keys={int(c['keys']):3d}")
    write_kfa2(tk, clip_tracks, clips, os.path.abspath(OUT))
    # validation renders: walk fwd + idle
    for want in ("MOB1_Walk_F", "ANIM_Humanoid_IdleUnarmed"):
        for c, tr in zip(clips, clip_tracks):
            if c["name"] == want:
                render_check(tk, s_bones, s_byname, c, tr,
                             os.path.join(render_dir, f"check_{want}.png"))
                break

if __name__ == "__main__":
    main()
