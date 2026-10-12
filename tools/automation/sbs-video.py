#!/usr/bin/env python3
"""sbs-video.py: side-by-side review video of two (or more) game takes, SR37 format (one swing each, full speed then 1/2).

usage (WSL python3; ffmpeg on PATH):
  sbs-video.py --out <x.mp4> --take <mp4>[@<ev.txt>]=<label> --take ... [--swing N] [--pre 0.35] [--post 0.6]
               [--width 800] [--crop-top 0] [--crop-bottom 0] [--title "<text>"] [--selftest]
  Each take's swing window comes from its fp-e6-strokes ev file (default <mp4 minus .mp4>.ev.txt): the Nth (1-based)
  run of `fp ui_state=swinging` lines, from pre s before the first swinging sample to post s after the last one. All
  panels get the same length (the longest window), are scaled to --width, labelled and stacked left to right; the clip
  plays at full speed, then again at 1/2 speed (labelled). h264_nvenc (GPU), libx264 fallback.
  Prints `RESULT SBS PASS <out> len=<s> windows=<t0-t1,...>` or `RESULT SBS FAIL <reason>`.
Built by keyframe-player 2026-10-11 (KEYFRAME-VS-TABLES video; the PT17-v2/v3 videos were cut by hand each time).
"""
import argparse, os, re, subprocess, sys, tempfile

FONT = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"


def swing_windows(ev_lines):
    """[(t_first_swinging, t_first_after)] per swing run of `fp ui_state=` samples (ev times are video seconds)."""
    runs, cur, last = [], None, None
    for ln in ev_lines:
        m = re.match(r"\s*([0-9.]+)\s+fp ui_state=(\S+)", ln)
        if not m:
            continue
        t, st = float(m.group(1)), m.group(2)
        if st == "swinging":
            if cur is None:
                cur = [t, t]
            cur[1] = t
        elif cur is not None:
            runs.append((cur[0], t))
            cur = None
        last = t
    if cur is not None:
        runs.append((cur[0], (last or cur[1]) + 0.3))
    return runs


def esc(s):
    return s.replace("\\", "\\\\").replace(":", "\\:").replace("'", "’").replace("%", "\\%")


def encoders():
    try:
        out = subprocess.run(["ffmpeg", "-hide_banner", "-encoders"], capture_output=True, text=True).stdout
    except OSError:
        return []
    return [e for e in ("h264_nvenc", "libx264") if e in out]


def build(a):
    takes = []
    for spec in a.take:
        if "=" not in spec:
            return "take spec without =label: " + spec
        src, label = spec.split("=", 1)
        mp4, ev = (src.split("@", 1) + [None])[:2]
        ev = ev or re.sub(r"\.mp4$", "", mp4) + ".ev.txt"
        if not os.path.isfile(mp4) or not os.path.isfile(ev):
            return "missing %s or %s" % (mp4, ev)
        w = swing_windows(open(ev, errors="replace").read().splitlines())
        if len(w) < a.swing:
            return "%s: %d swings in ev, want #%d" % (ev, len(w), a.swing)
        s0, s1 = w[a.swing - 1]
        takes.append((mp4, label, max(0.0, s0 - a.pre), s1 + a.post))
    dur = max(t[3] - t[2] for t in takes)
    fc, ins = [], []
    for i, (mp4, label, t0, _) in enumerate(takes):
        ins += ["-ss", "%.3f" % t0, "-t", "%.3f" % dur, "-i", mp4]
        crop = "crop=iw:ih-%d-%d:0:%d," % (a.crop_top, a.crop_bottom, a.crop_top) if (a.crop_top or a.crop_bottom) else ""
        fc.append("[%d:v]%ssetpts=PTS-STARTPTS,fps=30,scale=%d:-2,drawtext=fontfile=%s:text='%s':x=(w-tw)/2:y=10:fontsize=24:"
                  "fontcolor=white:box=1:boxcolor=black@0.6[p%d]" % (i, crop, a.width, FONT, esc(label), i))
    n = len(takes)
    fc.append("".join("[p%d]" % i for i in range(n)) + ("hstack=inputs=%d[h]" % n if n > 1 else "null[h]"))
    fc.append("[h]split[ha][hb]")
    lab = "drawtext=fontfile=%s:text='%s':x=(w-tw)/2:y=h-40:fontsize=26:fontcolor=yellow:box=1:boxcolor=black@0.6"
    title = (esc(a.title) + "  -  ") if a.title else ""
    fc.append("[ha]" + lab % (FONT, title + "FULL SPEED") + "[fa]")
    fc.append("[hb]setpts=2*PTS," + lab % (FONT, title + "1/2 SPEED") + "[fb]")
    fc.append("[fa][fb]concat=n=2:v=1:a=0[o]")
    encs = encoders()
    if not encs:
        return "ffmpeg missing"
    err = ""
    for enc in encs:
        q = ["-cq", "23"] if enc == "h264_nvenc" else ["-crf", "20", "-preset", "fast"]
        cmd = ["ffmpeg", "-y", "-loglevel", "error"] + ins + ["-filter_complex", ";".join(fc), "-map", "[o]", "-an",
                                                                "-c:v", enc] + q + ["-pix_fmt", "yuv420p", a.out]
        r = subprocess.run(cmd, capture_output=True, text=True)
        if r.returncode == 0 and os.path.getsize(a.out) > 0:
            print("RESULT SBS PASS %s len=%.1f enc=%s windows=%s" % (a.out, 3 * dur, enc,
                  ",".join("%.2f-%.2f" % (t[2], t[2] + dur) for t in takes)))
            return None
        err = r.stderr.strip().splitlines()[-1:] or ["rc=%d" % r.returncode]
        err = "%s: %s" % (enc, err[0])
    return "ffmpeg " + err


def selftest():
    ev = ["0.01 mark sync=0", "1.0 fp ui_state=ready", "1.3 fp ui_state=swinging", "1.6 fp ui_state=swinging",
          "1.9 fp ui_state=ready", "2.2 fp ui_state=ready", "2.5 fp ui_state=swinging", "2.8 fp ui_state=recover"]
    w = swing_windows(ev)
    assert w == [(1.3, 1.9), (2.5, 2.8)], w
    assert swing_windows(["1 fp ui_state=swinging"]) == [(1.0, 1.3)]
    if encoders():
        d = tempfile.mkdtemp(prefix="sbs-st-")
        for k in ("a", "b"):
            subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-f", "lavfi", "-i", "testsrc=size=320x180:rate=30",
                            "-t", "4", "-pix_fmt", "yuv420p", "%s/%s.mp4" % (d, k)], check=True)
            open("%s/%s.ev.txt" % (d, k), "w").write("\n".join(ev) + "\n")
        a = argparse.Namespace(out=d + "/o.mp4", take=[d + "/a.mp4=left", d + "/b.mp4=right: x"], swing=2, pre=0.3,
                               post=0.5, width=320, crop_top=0, crop_bottom=0, title="t")
        e = build(a)
        assert e is None, e
        for f in os.listdir(d):
            os.remove(os.path.join(d, f))
        os.rmdir(d)
    print("RESULT SBS-SELFTEST PASS")


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--out"); p.add_argument("--take", action="append", default=[])
    p.add_argument("--swing", type=int, default=1); p.add_argument("--pre", type=float, default=0.35)
    p.add_argument("--post", type=float, default=0.6); p.add_argument("--width", type=int, default=800)
    p.add_argument("--crop-top", type=int, default=0); p.add_argument("--crop-bottom", type=int, default=0)
    p.add_argument("--title", default=""); p.add_argument("--selftest", action="store_true")
    a = p.parse_args()
    if a.selftest:
        return selftest()
    if not a.out or not a.take:
        p.error("--out and --take needed")
    e = build(a)
    if e:
        print("RESULT SBS FAIL " + e)
        sys.exit(1)


if __name__ == "__main__":
    main()
