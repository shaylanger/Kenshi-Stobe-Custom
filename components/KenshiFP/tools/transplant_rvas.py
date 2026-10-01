#!/usr/bin/env python3
"""Sig-transplant Kenshi RVAs from a known build to an unknown sibling build.

Usage: transplant_rvas.py <src_exe> <dst_exe>

For each field of the client's addr_table_t (source RVAs = the T_1065 table,
kenshi_1065.exe):
  FUNC: disassemble the prologue at the source RVA with capstone, wildcard every
        rip-relative disp32 and every rel32 call/jcc/jmp target (those bytes
        encode build-specific distances), extend instruction by instruction
        until the masked pattern is UNIQUE in BOTH binaries and matches the
        source at the expected RVA, then report the destination hit.
  DATA: find every .text site whose rip-relative disp32 resolves to the global
        (numpy scan: u32(i)+i == g-4, gated on a modrm rip byte at i-1), match
        each site's context (disp wildcarded) uniquely in the destination,
        rip-follow there, and take the CONSENSUS destination RVA across sites.

Prints per-field results + a ready-to-paste C table body. Exit 1 if any field
fails (zeros in the emitted table)."""
import re
import struct
import sys
from collections import Counter

import numpy as np
from capstone import Cs, CS_ARCH_X86, CS_MODE_64, CS_GRP_CALL, CS_GRP_JUMP
from capstone.x86 import X86_OP_MEM, X86_REG_RIP

# ---- addr_table_t fields: (name, kind, steam-1.0.65 RVA) ------------------
# Values = T_1065 in client/kenshifp_client.c. 0/absent = skip (unused there).
FIELDS = [
    ("MAINLOOP",            "F", 0x787e70),
    ("SET_PAUSE",           "F", 0x787470),
    ("KEYPRESSED",          "F", 0x82a460),
    ("RAYCAST",             "F", 0x9b2b00),
    ("CAM_INSTANCE",        "D", 0x21322c0),
    ("INPUT_CONTROLENABLED","D", 0x21323f0),
    ("SCENE_CTX",           "D", 0x21322b8),
    ("FOLLOW_OBJECT",       "F", 0x6aed00),
    ("STOP_FOLLOW",         "F", 0x6aed40),
    ("CHARMOVE_SETDEST",    "F", 0x6607e0),
    ("CHAR_SETDEST",        "F", 0x5c7a50),
    ("GUI_INV_COUNT",       "D", 0x2132810),
    ("GUI_STATS_BEG",       "D", 0x2132918),
    ("GUI_STATS_END",       "D", 0x2132920),
    ("GUI_WINSTACK",        "D", 0x2132960),
    ("GUI_DLGWND",          "D", 0x2132770),
    ("DLG_GETVIS",          "F", 0x721390),
    ("ESCMENU_PTR",         "D", 0x212e4a8),
    ("ESC_GETVIS",          "F", 0x912170),
    ("OVERVIEW_PTR",        "D", 0x212e4e8),
    ("OVW_GETVIS",          "F", 0x48b0e0),
    ("OPTIONS_PTR",         "D", 0x212e080),
    ("OPT_GETVIS",          "F", 0x3e7100),
    ("PROSPECT_PTR",        "D", 0x212da50),
    ("PRO_GETVIS",          "F", 0x48b4c0),
    ("SAVELOAD_PTR",        "D", 0x212dbc8),
    ("MSGBOX_COUNT",        "D", 0x1f28a20),
    ("PLAYER_IFACE",        "D", 0x2133630),
    ("CTXMENU_VISIBLE",     "D", 0x2132280),
    ("CAM_UPDATE",          "F", 0x6b1540),
    ("TERRAIN_PTR",         "D", 0x21322c8),
    ("TOWNMGR_PTR",         "D", 0x21330a0),
    ("NEAREST_TOWN",        "F", 0x9279c0),
    ("INTERIOR_LOAD",       "F", 0x561ab0),
    ("GET_BONE_WORLD",      "F", 0x43ffc0),
    ("RANGED_ANIMUPD",      "F", 0x51da50),
    ("GUN_SHOOT",           "F", 0x43a390),
    ("FACE_DIR",            "F", 0x6647c0),
    ("GUN_RELOAD",          "F", 0x436c10),
    ("SHEATHE",             "F", 0x5cbd90),
    ("GUN_CREATEPHYS",      "F", 0x4366b0),
    ("RC_GETGUN",           "F", 0x434220),
    ("CAM_MANUAL_SETOZ",    "F", 0x6af0c0),
    ("SET_DIRECT_MOVE",     "F", 0x3332c0),
    ("CHARMOVE_UPDATE",     "F", 0x65f510),
    ("XP_RUNNING",          "F", 0x8c5790),
    ("HANDMAP_PTR",         "D", 0x2132f50),
    ("HAND_TO_BUILDING",    "F", 0x9f8050),
    ("WALLCULL",            "F", 0x5c94d0),
    ("GET_TOWN",            "F", 0xf6be0),
    ("SET_FLOORBYTE",       "F", 0x92b0f0),
    ("MANUAL_MOVE",         "F", 0x65d370),
    ("INVALIDATE_PATH",     "F", 0x65f3b0),
    ("ANIM_SETPOSDIR",      "F", 0x5b0e60),
    ("GROUND_HEIGHT",       "F", 0x9b3010),
    ("GROUND_NOHIT",        "D", 0x168ada0),
    ("RAGDOLL_QUEUED",      "F", 0x5cb2d0),
    ("STOP_RAGDOLL",        "F", 0x5d2290),
    ("CREATE_MOVER",        "F", 0x661500),
    ("SET_UNCON",           "F", 0x5cdf30),
    ("GROUND_AT",           "F", 0x9b3010),   # same fn as GROUND_HEIGHT
]

MIN_PAT, MAX_PAT = 24, 160          # pattern growth bounds (bytes)
DATA_PRE, DATA_POST = 10, 6         # context around a disp32 field
MAX_SITES = 40                      # data: max referencing sites to try


class Pe:
    def __init__(self, path):
        self.data = open(path, "rb").read()
        d = self.data
        pe = struct.unpack_from("<I", d, 0x3C)[0]
        assert d[:2] == b"MZ" and d[pe:pe+4] == b"PE\0\0", path
        nsec = struct.unpack_from("<H", d, pe+6)[0]
        optsz = struct.unpack_from("<H", d, pe+20)[0]
        self.stamp = struct.unpack_from("<I", d, pe+8)[0]
        self.imgsize = struct.unpack_from("<I", d, pe+24+56)[0]
        so = pe + 24 + optsz
        self.secs = []
        for i in range(nsec):
            o = so + i*40
            name = d[o:o+8].rstrip(b"\0").decode()
            vsz, va, rsz, rp = struct.unpack_from("<IIII", d, o+8)
            self.secs.append((name, va, vsz, rp, rsz))
            if name == ".text":
                self.text_va, self.text_raw = va, rp
                self.text = d[rp:rp+min(vsz, rsz)]

    def off(self, rva):
        for _, va, vsz, rp, rsz in self.secs:
            if va <= rva < va + max(vsz, rsz):
                return rp + (rva - va)
        raise ValueError(f"rva 0x{rva:x} unmapped")


def build_masked_pattern(md, pe, rva, min_len):
    """(bytes, mask) prologue pattern at rva; mask 0 = wildcard."""
    code = pe.data[pe.off(rva):pe.off(rva)+MAX_PAT+16]
    pat, mask = bytearray(), bytearray()
    for insn in md.disasm(code, rva):
        b = bytearray(insn.bytes)
        m = bytearray([1]*len(b))
        enc = insn  # capstone x86 encoding info
        for op in insn.operands:
            if op.type == X86_OP_MEM and op.mem.base == X86_REG_RIP:
                for k in range(enc.disp_offset, enc.disp_offset+enc.disp_size):
                    m[k] = 0
        if insn.group(CS_GRP_CALL) or insn.group(CS_GRP_JUMP):
            # rel32 targets shift between builds; rel8 (intra-fn) stays
            if enc.imm_size >= 4:
                for k in range(enc.imm_offset, enc.imm_offset+enc.imm_size):
                    m[k] = 0
        pat += b
        mask += m
        if len(pat) >= min_len:
            yield bytes(pat), bytes(mask)
        if len(pat) >= MAX_PAT:
            return


def to_regex(pat, mask):
    out, i = b"", 0
    while i < len(pat):
        if mask[i]:
            out += re.escape(pat[i:i+1])
        else:
            out += b"."
        i += 1
    return re.compile(out, re.DOTALL)


def find_all(rx, hay, limit=3):
    hits, pos = [], 0
    while len(hits) < limit:
        m = rx.search(hay, pos)
        if not m:
            break
        hits.append(m.start())
        pos = m.start() + 1
    return hits


def transplant_func(md, src, dst, rva):
    rank_result = None
    for pat, mask in build_masked_pattern(md, src, rva, MIN_PAT):
        rx = to_regex(pat, mask)
        s_hits = find_all(rx, src.text, limit=4)
        if not s_hits or src.text_va + s_hits[0] > rva:
            continue
        d_hits = find_all(rx, dst.text, limit=4)
        if len(s_hits) == 1 and src.text_va + s_hits[0] == rva:
            if len(d_hits) == 1:
                return dst.text_va + d_hits[0], len(pat)
            if len(d_hits) == 0:
                continue                  # maybe a longer pattern anchors it
        # COMDAT-folded twins: N identical copies in both builds. Match by
        # rank -- the k-th source hit corresponds to the k-th dest hit.
        if (1 < len(s_hits) == len(d_hits) <= 3
                and rva in [src.text_va + h for h in s_hits]):
            k = [src.text_va + h for h in s_hits].index(rva)
            rank_result = (dst.text_va + d_hits[k], len(pat))
    return rank_result if rank_result else (0, 0)


def ref_sites(pe, g_rva, gate):
    """File-text offsets of disp32 fields resolving to g_rva.
    gate 'rip' = rip-relative memory operand (modrm mod=00 rm=101);
    gate 'call' = E8 rel32 call to the address."""
    t = np.frombuffer(pe.text, dtype=np.uint8).astype(np.uint32)
    n = len(t) - 3
    u32 = t[0:n] | (t[1:n+1] << 8) | (t[2:n+2] << 16) | (t[3:n+3] << 24)
    idx = np.arange(n, dtype=np.uint32)
    want = np.uint32((g_rva - pe.text_va - 4) & 0xFFFFFFFF)
    cand = np.nonzero((u32 + idx) == want)[0]
    if gate == "rip":
        return [int(i) for i in cand if i >= 1 and (pe.text[i-1] & 0xC7) == 0x05]
    return [int(i) for i in cand if i >= 1 and pe.text[i-1] == 0xE8]


# (pre, post) context-window shapes tried per site; every unique match = a vote.
# Small shapes cover sites hemmed in by neighboring disp32 fields (which shift
# between builds and would poison a wider window).
WIN_SHAPES = [(10, 6), (14, 4), (7, 9), (12, 8), (6, 5), (3, 5), (3, 4), (2, 5)]


def transplant_ref(src, dst, g_rva, gate):
    votes = Counter()
    for i in ref_sites(src, g_rva, gate)[:MAX_SITES]:
        for prelen, postlen in WIN_SHAPES:
            pre = src.text[max(0, i-prelen):i]
            post = src.text[i+4:i+4+postlen]
            if len(pre) < prelen:
                continue
            rx = re.compile(re.escape(pre) + b"...." + re.escape(post),
                            re.DOTALL)
            d_hits = find_all(rx, dst.text)
            if len(d_hits) != 1:
                continue
            f = d_hits[0] + len(pre)      # disp field offset in dst text
            disp = struct.unpack_from("<i", dst.text, f)[0]
            votes[(dst.text_va + f + 4 + disp) & 0xFFFFFFFF] += 1
    if not votes:
        return 0, 0
    rva, n = votes.most_common(1)[0]
    others = sum(votes.values()) - n
    return (rva, n) if n > others else (0, 0)   # require strict majority


def transplant_data(src, dst, g_rva):
    return transplant_ref(src, dst, g_rva, "rip")


def main():
    src, dst = Pe(sys.argv[1]), Pe(sys.argv[2])
    print(f"src: stamp=0x{src.stamp:x} img=0x{src.imgsize:x}  "
          f"dst: stamp=0x{dst.stamp:x} img=0x{dst.imgsize:x}")
    md = Cs(CS_ARCH_X86, CS_MODE_64)
    md.detail = True
    results, fails = {}, []
    for name, kind, rva in FIELDS:
        if name == "GROUND_AT" and "GROUND_HEIGHT" in results:
            results[name] = results["GROUND_HEIGHT"]     # same function
            continue
        if kind == "F":
            got, quality = transplant_func(md, src, dst, rva)
            how = f"pat {quality}B"
            if not got:                   # fallback: consensus of call sites
                got, quality = transplant_ref(src, dst, rva, "call")
                how = f"{quality} call site(s)"
        else:
            got, quality = transplant_data(src, dst, rva)
            how = f"{quality} site(s)"
        results[name] = got
        tag = "ok " if got else "FAIL"
        shift = f"{got - rva:+#x}" if got else "-"
        print(f"  {tag} {name:<22} src=0x{rva:07x} dst=0x{got:07x} "
              f"shift={shift:<8} ({how})")
        if not got:
            fails.append(name)

    # GUI_* are fields of ONE gui object (struct-internal offsets, exact by
    # layout): INV_COUNT = STATS_BEG-0x108, STATS_END = +8, WINSTACK = +0x48.
    if results.get("GUI_STATS_BEG"):
        beg = results["GUI_STATS_BEG"]
        for name, delta in (("GUI_INV_COUNT", -0x108), ("GUI_STATS_END", 8),
                            ("GUI_WINSTACK", 0x48)):
            if not results.get(name):
                results[name] = beg + delta
                if name in fails:
                    fails.remove(name)
                print(f"  ok  {name:<22} derived = GUI_STATS_BEG{delta:+#x} "
                      f"-> 0x{results[name]:07x}")

    print("\n/* ---- transplanted table (paste values) ---- */")
    for name, kind, rva in FIELDS:
        print(f"    0x{results[name]:x},\t/* {name} */")
    if fails:
        print(f"\n{len(fails)} FAILED: {', '.join(fails)}", file=sys.stderr)
        sys.exit(1)
    print("\nall fields resolved")


if __name__ == "__main__":
    main()
