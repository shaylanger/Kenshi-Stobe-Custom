#!/usr/bin/env python3
"""One-turn changed-plan follow-on for an already accepted current-build trip."""
import json
import math
import os
from pathlib import Path
import re
import shlex
import subprocess
import sys
import time

ROW = os.environ.get("ROW_ID", "P0-TRAVEL-CHANGED-PLAN-001")
NPC = os.environ.get("NPC", "")
OLD = os.environ.get("ACTIVE_DESTINATION", "")
NEW = os.environ.get("NEW_DESTINATION", "")
OUT = Path(os.environ.get("OUT", ""))
LOG = Path(os.environ.get("NATIVE_LOG", ""))
LOG_ID = os.environ.get("NATIVE_LOG", "")
ACTIVE_OUT = Path(os.environ.get("ACTIVE_TRAVEL_OUT", ""))
PREFLIGHT = Path(os.environ.get("PREFLIGHT_RECEIPT", ""))
BUILD_RECEIPT = Path(os.environ.get("BUILD_RECEIPT", ""))
SAVE_RECEIPT = Path(os.environ.get("SAVE_RECEIPT", ""))
SESSION_RECEIPT = Path(os.environ.get("SESSION_RECEIPT", ""))
ACTIVE_START_RECEIPT = Path(os.environ.get("ACTIVE_START_RECEIPT", ""))
WAIT = int(os.environ.get("WAIT_SECONDS", "180"))
POLL = float(os.environ.get("POLL_SECONDS", "3"))
TOL = 5.0


class Stop(Exception):
    def __init__(self, kind, reason):
        self.kind, self.reason = kind, reason


def stop(kind, reason):
    raise Stop(kind, reason)


def run(args, label, timeout=25):
    try:
        p = subprocess.run([os.environ.get("TRAVEL_DRIVER_BASH", "bash"), "-c",
                            shlex.join(["stobe-auto", *args])], capture_output=True,
                            text=True, timeout=timeout)
    except Exception as exc:
        stop("evidence", f"{label} handler exception: {exc}")
    (OUT / f"{label}.txt").write_text(p.stdout + p.stderr, encoding="utf-8")
    if p.returncode:
        stop("setup" if label.endswith("before") else "evidence",
             f"{label} handler exit={p.returncode}")
    return p.stdout.strip()


def state(name, serial, label):
    raw = run(["stobe_state", name], label)
    try:
        doc = json.loads(raw)
    except Exception:
        stop("evidence", f"{label} is not native stobe_state JSON")
    if doc.get("name") != name or int(doc.get("serial", -1)) != serial:
        stop("evidence", f"{label} actor name/serial changed")
    ai = doc.get("ai")
    if not isinstance(ai, dict):
        stop("evidence", f"{label} missing nested native ai state")
    dest = ai.get("destination")
    if not isinstance(dest, list) or len(dest) != 3:
        stop("evidence", f"{label} missing native ai.destination")
    try:
        dest = tuple(float(x) for x in dest)
    except (ValueError, TypeError):
        stop("evidence", f"{label} malformed native ai.destination")
    return ai, dest, doc


def exact_lines(blob, name, serial):
    found = []
    for line in blob.splitlines():
        m = re.search(r"NPC_SAY:\s*([^|:]+)\|(\d+):\s*(.*)", line, re.I)
        if m and m.group(1).strip().casefold() == name.casefold() and int(m.group(2)) == serial:
            found.append(m.group(3).strip())
    return found


def complete_stream(blob, name, serial):
    markers = list(re.finditer(r"CHAT_THREAD:\s*Queued\s+(\d+)\s+streamed chat lines and\s+\d+\s+action lines\.?", blob, re.I))
    if not markers:
        return None
    count = int(markers[-1].group(1))
    # Handler emissions are after the baseline log offset; count all queued lines,
    # while only exact-name/serial speech is eligible to decide the outcome.
    all_say = len(re.findall(r"\bNPC_SAY:", blob, re.I))
    return (count, exact_lines(blob, name, serial)) if all_say >= count else None


def travel_events(blob, serial):
    return [line for line in blob.splitlines()
            if "ACTION_EXEC: TRAVEL_LOCATION" in line and
            re.search(rf"\bserial\s*=\s*{serial}\b", line, re.I)]


def event_identity_matches(line, name, serial, destination):
    actor = re.search(r"\bactor=(.*?)\s+destination=['\"]([^'\"]+)['\"]", line, re.I)
    return bool(actor and actor.group(1).strip().casefold() == name.casefold()
                and actor.group(2).strip().casefold() == destination.casefold()
                and re.search(rf"\bserial\s*=\s*{serial}\b", line, re.I))


def receipt_has(path, key, value):
    raw = path.read_text(encoding="utf-8", errors="replace")
    return bool(re.search(rf"(?im)^\s*{re.escape(key)}\s*[:=]\s*{re.escape(value)}\s*$", raw))


def normpath(value):
    return value.replace("\\", "/").rstrip("/").casefold()


def response_kind(lines):
    refusal = re.compile(r"\b(?:I can(?: not|not|['’]t)|I cannot|I won't|I will not|I don't|I do not|I would never|no,? I)\b", re.I)
    affirmative = re.compile(r"\b(?:I can|I will|I'll)\b.*\b(?:change|switch|take you|lead|guide|walk with you)\b", re.I)
    negated = re.compile(r"\b(?:I can not|I cannot|I can't|I won['’]t|I will not|I do not|I don't|never|no)\b", re.I)
    condition = re.compile(r"\b(?:if|unless|maybe|perhaps|could|would|might|should|but|not today|only if)\b", re.I)
    mentions_new = lambda s: bool(re.search(rf"(?<!\w){re.escape(NEW)}(?!\w)", s, re.I))
    refusals = [s for s in lines if refusal.search(s) and mentions_new(s) and
                re.search(r"\b(?:change|switch|instead|trip|route|destination)\b", s, re.I)]
    accepts = [s for s in lines if affirmative.search(s) and mentions_new(s) and not condition.search(s) and not negated.search(s)]
    if len(refusals) == 1 and not accepts:
        return "refusal", refusals[0]
    if len(accepts) == 1 and not refusals:
        return "acceptance", accepts[0]
    return "ambiguous", "\n".join(lines)


def _fresh_file(path, max_age):
    if not path.is_file():
        return False
    return 0 <= time.time() - path.stat().st_mtime <= max_age


def main():
    build_sha, save_id, session_id = (os.environ.get("BUILD_SHA", ""), os.environ.get("SAVE_ID", ""),
                                      os.environ.get("SESSION_ID", ""))
    if not all([NPC, OLD, NEW, OUT.as_posix(), LOG.as_posix(), ACTIVE_OUT.as_posix(), PREFLIGHT.as_posix(),
                BUILD_RECEIPT.as_posix(), SAVE_RECEIPT.as_posix(), SESSION_RECEIPT.as_posix(),
                ACTIVE_START_RECEIPT.as_posix(), build_sha, save_id, session_id]):
        stop("setup", "set actor/destinations, output/log/active-start paths, and fresh preflight/build/save/session/active-start receipts plus exact build/save/session IDs")
    if OLD.casefold() == NEW.casefold():
        stop("setup", "new destination must differ from accepted destination")
    if (os.environ.get("RIG"), os.environ.get("KAH_INSTANCE")) not in (("5090", "3"), ("4080", "3")):
        stop("setup", "only isolated 5090/4080 instance 3 is authorized")
    want_game = "/mnt/d/KenshiInst/3" if os.environ["RIG"] == "5090" else "/c/KenshiInst/3"
    want_kah = r"D:\KenshiInst\3\mods\AutomationHarness" if os.environ["RIG"] == "5090" else r"C:\KenshiInst\3\mods\AutomationHarness"
    want_log = want_game + "/RE_Kenshi/mods/Stobe/stobe.log"
    if os.environ.get("KENSHI_DIR") != want_game or os.environ.get("KAH_DIR") != want_kah:
        stop("setup", "route does not match isolated i3 path for selected rig")
    if normpath(LOG_ID) != normpath(want_log):
        stop("setup", "NATIVE_LOG is not the selected rig's isolated i3 native log path")
    if not OUT.parent.is_dir():
        stop("setup", "OUT parent must already exist")
    try:
        OUT.mkdir()  # atomic claim before any KAH/native handler call
    except FileExistsError:
        stop("setup", "OUT already exists; no handler was called")
    except OSError as exc:
        stop("setup", f"cannot atomically claim OUT: {exc}")

    max_age = int(os.environ.get("MAX_RECEIPT_AGE_SECONDS", "3600"))
    receipt_paths = (PREFLIGHT, BUILD_RECEIPT, SAVE_RECEIPT, SESSION_RECEIPT, ACTIVE_START_RECEIPT)
    if not all(_fresh_file(p, max_age) for p in receipt_paths):
        stop("setup", "one or more preflight/build/save/session receipts are missing or stale")
    preflight = PREFLIGHT.read_text(encoding="utf-8", errors="replace").casefold()
    for token in ("build", "save", "session", "private", "input", "inbox"):
        if token not in preflight:
            stop("setup", f"preflight receipt does not attest {token}")
    for key, value in (("build_sha", build_sha), ("save_id", save_id), ("session_id", session_id),
                       ("rig", os.environ["RIG"]), ("kah_instance", "3"),
                       ("native_log", LOG_ID), ("active_travel_out", str(ACTIVE_OUT))):
        if not receipt_has(PREFLIGHT, key, value):
            stop("setup", f"preflight receipt does not bind exact {key}={value}")
    for path, key, value in ((BUILD_RECEIPT, "build_sha", build_sha), (SAVE_RECEIPT, "save_id", save_id),
                             (SESSION_RECEIPT, "session_id", session_id)):
        if not receipt_has(path, key, value):
            stop("setup", f"{path.name} does not pin exact {key}={value}")
    for key, value in (("build_sha", build_sha), ("save_id", save_id), ("session_id", session_id),
                       ("rig", os.environ["RIG"]), ("kah_instance", "3"),
                       ("native_log", LOG_ID), ("active_travel_out", str(ACTIVE_OUT))):
        if not receipt_has(ACTIVE_START_RECEIPT, key, value):
            stop("setup", f"active-start receipt does not bind exact {key}={value}")
    ep_file, progress_file, action_file, final_state_file = (ACTIVE_OUT / "endpoint.json", ACTIVE_OUT / "progress.json",
                                          ACTIVE_OUT / "accept.native.delta.log", ACTIVE_OUT / "state.final.txt")
    if not all(_fresh_file(p, max_age) for p in (ep_file, progress_file, action_file, final_state_file)):
        stop("setup", "active-start artifacts missing or stale; use a fresh PASS-START-MOVE output")
    try:
        endpoint_doc = json.loads(ep_file.read_text(encoding="utf-8"))
        progress = json.loads(progress_file.read_text(encoding="utf-8"))
        endpoint = tuple(float(x) for x in endpoint_doc["xyz"])
        if endpoint_doc.get("destination", "").casefold() != OLD.casefold() or not progress:
            stop("setup", "active-start artifacts do not match ACTIVE_DESTINATION or movement proof")
        startlog = action_file.read_text(encoding="utf-8", errors="replace")
        starts = [x for x in startlog.splitlines() if "ACTION_EXEC: TRAVEL_LOCATION" in x]
        if len(starts) != 1:
            stop("setup", "active-start receipt lacks exactly one accepted native destination dispatch")
    except Stop:
        raise
    except Exception as exc:
        stop("evidence", f"malformed prior start receipt: {exc}")
    if not LOG.is_file():
        stop("setup", "native log is missing")
    handle_text = run(["where", NPC], "where.before")
    ident = re.search(r"^\s*(.*?)\s+#(\d+)/(\d+)", handle_text, re.M)
    if not ident or ident.group(1).strip() != NPC:
        stop("setup", "where did not resolve exact current NPC display name and native handle")
    serial, index = int(ident.group(2)), int(ident.group(3))
    if (not receipt_has(PREFLIGHT, "actor", NPC) or not receipt_has(PREFLIGHT, "serial", str(serial))
            or not receipt_has(ACTIVE_START_RECEIPT, "actor", NPC)
            or not receipt_has(ACTIVE_START_RECEIPT, "serial", str(serial))):
        stop("setup", "fresh preflight receipt does not bind this exact current actor display name and serial")
    try:
        prior_state = json.loads(final_state_file.read_text(encoding="utf-8"))
    except Exception as exc:
        stop("evidence", f"active-start terminal state is not parseable stobe_state JSON: {exc}")
    if prior_state.get("name") != NPC or int(prior_state.get("serial", -1)) != serial:
        stop("setup", "current actor name/serial differs from the accepted-start receipt")
    serial_starts = [line for line in starts if event_identity_matches(line, NPC, serial, OLD)]
    if len(serial_starts) != 1:
        stop("setup", "accepted-start receipt does not prove one native dispatch for this exact actor serial and destination")
    ai0, dest0, doc0 = state(NPC, serial, "state.before")
    if math.dist(dest0, endpoint) > TOL or ai0.get("moving") is not True or ai0.get("destination_reached") is not False or ai0.get("path_failed") is not False:
        stop("setup", "native actor no longer shows active accepted travel toward the original endpoint")
    (OUT / "baseline.json").write_text(json.dumps({"name": NPC, "serial": serial, "index": index,
        "active_destination": OLD, "destination": dest0, "state": ai0}, indent=2), encoding="utf-8")
    baseline = LOG.stat().st_size
    message = (f"I need to change our trip from {OLD} to {NEW}. Will you agree to change the trip and take me to {NEW} instead? "
               f"If you do not agree, keep the existing trip to {OLD}.")
    (OUT / "request.txt").write_text(message, encoding="utf-8")
    run(["stobe_say", NPC, message], "stobe_say.changed-plan", timeout=45)
    deadline = time.monotonic() + WAIT
    streamed = None
    while time.monotonic() < deadline:
        delta = LOG.read_bytes()[baseline:].decode("utf-8", "replace")
        streamed = complete_stream(delta, NPC, serial)
        if streamed is not None:
            queued, speech = streamed
            if len(speech) >= queued:
                break
        time.sleep(POLL)
    else:
        stop("evidence", "no bounded CHAT_THREAD completion plus all queued NPC_SAY lines")
    delta = LOG.read_bytes()[baseline:].decode("utf-8", "replace")
    (OUT / "chat.native.delta.log").write_text(delta, encoding="utf-8")
    (OUT / "npc-say.txt").write_text("\n".join(speech) + "\n", encoding="utf-8")
    kind, chosen = response_kind(speech)
    if kind == "ambiguous":
        stop("evidence", "complete reply is not a single explicit, scoped acceptance or truthful refusal")

    # Observe the exact native action log and native ai.destination after the reply.
    # This ordinary chat path does not expose a durable trip ledger/status reader.
    settle = max(3.0, float(os.environ.get("SETTLE_SECONDS", "9")))
    until = time.monotonic() + settle
    samples = []
    while time.monotonic() < until:
        now = LOG.read_bytes()[baseline:].decode("utf-8", "replace")
        events = travel_events(now, serial)
        ai, dest, doc = state(NPC, serial, f"state.observe.{len(samples)+1:02d}")
        samples.append({"destination": dest, "moving": ai.get("moving"), "reached": ai.get("destination_reached"),
                        "path_failed": ai.get("path_failed"), "event_count": len(events)})
        time.sleep(min(POLL, max(0.05, until - time.monotonic())))
    after = LOG.read_bytes()[baseline:].decode("utf-8", "replace")
    events = travel_events(after, serial)
    (OUT / "native-travel-events.txt").write_text("\n".join(events) + ("\n" if events else ""), encoding="utf-8")
    (OUT / "observations.json").write_text(json.dumps(samples, indent=2), encoding="utf-8")
    stable_original = all(math.dist(tuple(s["destination"]), endpoint) <= TOL for s in samples)
    if kind == "refusal":
        if events:
            stop("product", f"NPC explicitly refused changed plan but native travel dispatch occurred ({len(events)} events)")
        if not stable_original or not samples or any(s["moving"] is not True or s["path_failed"] is not False for s in samples):
            stop("evidence", "refusal observed but original active native trip was not continuously confirmed")
        print(f"RESULT {ROW} PASS-REFUSED actor={NPC}#{serial}/{index} active={OLD} requested={NEW} refusal=explicit original_destination=retained native_replacements=0 durable_trip_ledger=UNSUPPORTED evidence={OUT}")
        return

    if len(events) != 1:
        stop("product", f"explicit accepted changed plan requires exactly one native TRAVEL_LOCATION dispatch; observed {len(events)}")
    event = events[0]
    if not event_identity_matches(event, NPC, serial, NEW):
        stop("product", "native changed-plan action actor display name or exact destination label differs from the accepted request")
    xyz = re.search(r"\bx=([-+\d.eE]+)\s+y=([-+\d.eE]+)\s+z=([-+\d.eE]+)", event, re.I)
    if not xyz:
        stop("evidence", "native changed-plan action lacks parseable exact XYZ endpoint")
    try:
        action_endpoint = tuple(float(x) for x in xyz.groups())
    except ValueError:
        stop("evidence", "native changed-plan action endpoint is malformed")
    matched = [i for i, sample in enumerate(samples) if math.dist(tuple(sample["destination"]), action_endpoint) <= TOL]
    if len(matched) < 2 or any(math.dist(tuple(s["destination"]), action_endpoint) > TOL for s in samples[matched[0]:]):
        stop("product", "native ai.destination did not converge to and remain at the single changed-plan action endpoint")
    if any(s["path_failed"] is not False for s in samples):
        stop("product", "native path_failed after accepted changed plan")
    if not any(s["moving"] is True and s["reached"] is False for s in samples[matched[0]:]):
        stop("evidence", "accepted changed plan lacks a native moving and not-reached observation")
    print(f"RESULT {ROW} PASS-CHANGED actor={NPC}#{serial}/{index} old={OLD} new={NEW} acceptance=explicit native_replacements=1 duplicate_dispatches=0 native_ai_destination=changed durable_trip_ledger=UNSUPPORTED evidence={OUT}")


if __name__ == "__main__":
    try:
        main()
    except Stop as exc:
        print(f"RESULT {ROW} FAIL {exc.kind}: {exc.reason}")
        sys.exit(2 if exc.kind == "setup" else 3 if exc.kind == "evidence" else 4)
