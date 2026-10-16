#!/usr/bin/env python3
"""logwin.py: filtered, capped window into a game/server/harness log (imm26-ctxfix, 2026-10-16). Wrapped by logwin.sh.
  logwin.sh <log> <pattern> [maxchars=2500]          lines matching the regex (python/ERE syntax), noise filtered, each cut to 220 chars
  logwin.sh <log> since:<regex> [maxchars]           from the LAST line matching <regex> to the end of the log
  logwin.sh <log> at:HH:MM:SS[+SEC] [maxchars]       lines from that time of day (window of SEC seconds, default to the end)
  Optional env: LOGWIN_AND=<regex> (since:/at: modes: keep only lines that also match), LOGWIN_KEEP_NOISE=1 (no noise filter),
  LOGWIN_I=1 (case-insensitive), LOGWIN_CUT=220 (line cut), LOGWIN_SCAN_MB=128 (only the last N MB of the log are scanned).
NOISE (dropped unless the pattern itself names the tag, or LOGWIN_KEEP_NOISE=1): the high-volume stobe.log / harness.log tags that operators used to
  retype into every command: TOWNS_DIAG CAMP_DIAG SIGHT_DIAG CHAT_SEND_STAGE HOOK_MSG HOOK_DIAG HOOK_LOAD_PROBE EVENT_STREAM SOCIAL_CAPTURE TIMING_META ACTION_TIMING
  CHAT_TIMING RECHAT_TIMING PORTRAIT_SYNC PROFILE_PORTRAIT PLAYER_BASE_DEBUG TTS_PLAYBACK INV_SYNC SQUAD_SYNC CATS_SYNC FACTION_REL_SYNC TOWN_KNOWLEDGE_SYNC
  CONTEXT_ROUTE, and "KAH: fps|register|protect".
NEVER HIDDEN (kept whole, up to 600 chars, immune to the noise filter and the cap): lines with RESULT, SETUP-FAIL, PREFLIGHT-FAIL, ROW-NEEDS-FIXER. Lines with
  FAIL/FAILED/ERROR/EXCEPTION/Traceback/CRASH/ASSERT are immune to the noise filter and are preferred when the cap bites.
When the output is cut by the cap the footer gives the number of omitted lines/chars, the FULL filtered output file and the source log path.
Exit 0 = window printed, 1 = no match / marker not found, 2 = usage / unreadable log.
"""
import sys, os, re, io, time, tempfile

NOISE_TAGS = ("TOWNS_DIAG CAMP_DIAG SIGHT_DIAG CHAT_SEND_STAGE HOOK_MSG HOOK_DIAG HOOK_LOAD_PROBE EVENT_STREAM SOCIAL_CAPTURE TIMING_META ACTION_TIMING "
              "CHAT_TIMING RECHAT_TIMING PORTRAIT_SYNC PROFILE_PORTRAIT PLAYER_BASE_DEBUG TTS_PLAYBACK INV_SYNC SQUAD_SYNC CATS_SYNC FACTION_REL_SYNC "
              "TOWN_KNOWLEDGE_SYNC CONTEXT_ROUTE").split()
NOISE_EXTRA = [r"KAH: fps", r"KAH: register", r"KAH: protect"]
MUST = re.compile(r"RESULT |SETUP-FAIL|PREFLIGHT-FAIL|ROW-NEEDS-FIXER")
HIGH = re.compile(r"\bFAIL(ED)?\b|\bERROR\b|EXCEPTION|Traceback|CRASH|ASSERT", re.I)
TS = re.compile(r"\[(?:\d{4}-\d\d-\d\d )?(\d\d):(\d\d):(\d\d)")


def read_lines(path, scan_mb):
    size = os.path.getsize(path)
    lim = scan_mb * 1024 * 1024
    with open(path, "rb") as f:
        if size > lim:
            f.seek(size - lim)
            f.readline()  # drop the partial line
        data = f.read()
    return data.decode("utf-8", errors="replace").split("\n")


def noise_re(pattern):
    tags = [t for t in NOISE_TAGS if t not in pattern]
    parts = list(tags) + [p for p in NOISE_EXTRA if p.split(": ")[1] not in pattern]
    return re.compile("|".join(re.escape(t) if re.fullmatch(r"[A-Z_]+", t) else t for t in parts)) if parts else None


def tod(line):
    m = TS.search(line[:40])
    return (int(m.group(1)) * 3600 + int(m.group(2)) * 60 + int(m.group(3))) if m else None


def main(a):
    if len(a) < 2:
        print(__doc__)
        return 2
    path, spec = a[0], a[1]
    try:
        cap = int(a[2]) if len(a) > 2 else int(os.environ.get("LOGWIN_MAX", "2500"))
    except ValueError:
        print("maxchars must be a number")
        return 2
    cut = int(os.environ.get("LOGWIN_CUT", "220"))
    scan = int(os.environ.get("LOGWIN_SCAN_MB", "128"))
    flags = re.I if os.environ.get("LOGWIN_I") else 0
    if not os.path.isfile(path):
        print("logwin: no such log: %s" % path)
        return 2
    lines = read_lines(path, scan)
    mode = "pattern"
    sel = []
    try:
        if spec.startswith("since:"):
            mode = "since"
            mk = re.compile(spec[6:], flags)
            last = None
            for i, l in enumerate(lines):
                if mk.search(l):
                    last = i
            if last is None:
                print("logwin: marker /%s/ not found in the last %d MB of %s" % (spec[6:], scan, path))
                return 1
            sel = lines[last:]
            pat_for_noise = spec[6:] + " " + os.environ.get("LOGWIN_AND", "")
        elif spec.startswith("at:"):
            mode = "at"
            m = re.fullmatch(r"at:(\d\d):(\d\d):(\d\d)(?:\+(\d+))?", spec)
            if not m:
                print("logwin: at:HH:MM:SS[+SEC]")
                return 2
            t0 = int(m.group(1)) * 3600 + int(m.group(2)) * 60 + int(m.group(3))
            t1 = t0 + int(m.group(4)) if m.group(4) else None
            for l in lines:
                t = tod(l)
                if t is not None and t >= t0 and (t1 is None or t <= t1):
                    sel.append(l)
            pat_for_noise = os.environ.get("LOGWIN_AND", "")
        else:
            rx = re.compile(spec, flags)
            sel = [l for l in lines if rx.search(l)]
            pat_for_noise = spec
        andre = re.compile(os.environ["LOGWIN_AND"], flags) if os.environ.get("LOGWIN_AND") and mode != "pattern" else None
    except re.error as e:
        print("logwin: bad regex: %s" % e)
        return 2
    if andre:
        sel = [l for l in sel if andre.search(l) or MUST.search(l)]
    total_match = len([l for l in sel if l.strip()])
    nz = None if os.environ.get("LOGWIN_KEEP_NOISE") else noise_re(pat_for_noise)
    kept = []
    dropped = 0
    for l in sel:
        l = l.rstrip("\r")
        if not l.strip():
            continue
        if nz and nz.search(l) and not MUST.search(l) and not HIGH.search(l):
            dropped += 1
            continue
        c = 600 if MUST.search(l) else cut
        kept.append(l if len(l) <= c else l[: c - 3] + "...")
    if not kept:
        print("logwin: %s %s: %d line(s) matched, %d dropped as noise, nothing left (LOGWIN_KEEP_NOISE=1 to see them)" % (os.path.basename(path), mode, total_match, dropped))
        return 1
    head = "[logwin %s %s: %d matched, %d noise dropped, %d shown]" % (os.path.basename(path), mode, total_match, dropped, len(kept))
    body_len = sum(len(l) + 1 for l in kept)
    if body_len <= cap:
        print(head)
        print("\n".join(kept))
        return 0
    # cap bites: MUST lines always; HIGH lines (newest first) up to 60% of the budget; first 2 lines; then fill with the newest lines
    n = len(kept)
    chosen = set(i for i, l in enumerate(kept) if MUST.search(l))
    used = sum(len(kept[i]) + 1 for i in chosen)
    for i in range(n - 1, -1, -1):
        if i not in chosen and HIGH.search(kept[i]) and used + len(kept[i]) + 1 <= cap * 0.6:
            chosen.add(i)
            used += len(kept[i]) + 1
    for i in (0, 1):
        if i < n and i not in chosen and used + len(kept[i]) + 1 <= cap:
            chosen.add(i)
            used += len(kept[i]) + 1
    for i in range(n - 1, -1, -1):
        if i in chosen:
            continue
        if used + len(kept[i]) + 1 > cap:
            break
        chosen.add(i)
        used += len(kept[i]) + 1
    out = []
    prev = -1
    for i in sorted(chosen):
        if i - prev > 1:
            out.append("[... %d line(s) omitted ...]" % (i - prev - 1))
        out.append(kept[i])
        prev = i
    if prev < n - 1:
        out.append("[... %d later line(s) omitted ...]" % (n - 1 - prev))
    d = os.path.join(tempfile.gettempdir(), "kah-logwin")
    os.makedirs(d, exist_ok=True)
    now = time.time()
    for f in os.listdir(d):  # prune > 24 h
        try:
            if now - os.path.getmtime(os.path.join(d, f)) > 86400:
                os.remove(os.path.join(d, f))
        except OSError:
            pass
    full = os.path.join(d, "%s-%d.txt" % (re.sub(r"[^A-Za-z0-9_.-]", "_", os.path.basename(path)), int(now)))
    with io.open(full, "w", encoding="utf-8") as f:
        f.write("\n".join(kept) + "\n")
    print(head)
    print("\n".join(out))
    print("[TRUNCATED to ~%d chars: %d of %d lines shown, +%d chars omitted. FULL filtered output: %s | source log: %s]" % (cap, len(chosen), n, body_len - used, full.replace("\\", "/"), path))
    return 0


if __name__ == "__main__":
    try:
        sys.stdout.reconfigure(newline=chr(10), encoding="utf-8")
    except Exception:
        pass
    sys.exit(main(sys.argv[1:]))
