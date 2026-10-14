#!/usr/bin/env python3
"""One isolated, conversation-driven P0 native travel-start/progress row."""
import json
import math
import os
from pathlib import Path
import re
import shlex
import subprocess
import sys
import time

ROW = os.environ.get("ROW_ID", "P0-ROLE-CLARIFICATION-4080-001")
NPC = os.environ.get("NPC", "")
DEST = os.environ.get("TRAVEL_DESTINATION", "")
OUT = Path(os.environ.get("OUT", ""))
LOG = Path(os.environ.get("NATIVE_LOG", ""))
WAIT = int(os.environ.get("WAIT_SECONDS", "300"))
POLL = float(os.environ.get("POLL_SECONDS", "5"))
START_SETTLE = float(os.environ.get("START_SETTLE_SECONDS", "1"))
TALK_RADIUS = 80.0
DESTINATION_TOLERANCE = 5.0
MIN_INTERVAL_PROGRESS = 0.5
MIN_TOTAL_PROGRESS = 5.0


class Stop(Exception):
    def __init__(self, kind, reason):
        self.kind, self.reason = kind, reason


def stop(kind, why):
    raise Stop(kind, why)


def run(args, label, timeout=20):
    try:
        # Invoke the documented Bash shims (both rigs expose stobe-auto there).
        bash = os.environ.get("TRAVEL_DRIVER_BASH", "bash")
        command = shlex.join(["stobe-auto", *args])
        p = subprocess.run([bash, "-c", command], capture_output=True, text=True, timeout=timeout)
    except Exception as e:
        stop("setup" if label.endswith("before") else "evidence", f"{label} handler failed: {e}")
    (OUT / f"{label}.txt").write_text(p.stdout + p.stderr, encoding="utf-8")
    if p.returncode:
        stop("setup" if label.endswith("before") else "evidence", f"{label} handler exit={p.returncode}")
    return p.stdout.strip()


def where(name, label):
    raw = run(["where", name], label)
    identity = re.search(r"^\s*(.*?)\s+#(\d+)/(\d+)", raw, re.M)
    pm = re.search(r"pos=([-+\d.eE]+),\s*([-+\d.eE]+),\s*([-+\d.eE]+)", raw)
    dm = re.search(r"\bdist=([-+\d.eE]+)", raw, re.I)
    if not identity or identity.group(1).strip() != name or not pm or not dm:
        setup_point = label.endswith("before") or "before-accept" in label
        stop("setup" if setup_point else "evidence", f"{label} lacks exact actor/serial/position/native player distance")
    return (int(identity.group(2)), int(identity.group(3))), tuple(map(float, pm.groups())), float(dm.group(1))


def state(name, handle, label, initial=False):
    raw = run(["stobe_state", f"#{handle[0]}/{handle[1]}"], label)
    try:
        obj = json.loads(raw)
        ai = obj["ai"]
        assert isinstance(ai, dict)
        assert obj.get("name") == name
        assert int(obj.get("serial")) == handle[0]
    except Exception as e:
        stop("setup" if initial else "evidence", f"{label} malformed/wrong native identity or missing nested ai state: {e}")
    fields = {k: ai.get(k) for k in ("dead", "unconscious", "can_take_orders", "has_orders", "has_player_orders", "first_order", "current_goal", "moving", "destination_reached", "path_failed", "destination")}
    if initial:
        if fields["dead"] is not False or fields["unconscious"] is not False or fields["can_take_orders"] is not True:
            stop("setup", "actor dead/KO/unavailable for orders")
        if fields["has_orders"] is not False or fields["has_player_orders"] is not False:
            stop("setup", "actor already has native/player orders")
    return fields


def target_speech(delta, name, serial):
    # Native format: NPC_SAY: <display name>|<serial>: <text> ...
    out = []
    for line in delta.splitlines():
        match = re.search(r"NPC_SAY:\s*([^|:]+)\|(\d+):\s*(.*)", line, re.I)
        if match and match.group(1).strip().casefold() == name.casefold() and int(match.group(2)) == serial:
            out.append(line)
    return out


def final_speech_records(delta):
    """Return unique final NPC_SAY records, excluding provisional lines without an utterance ID."""
    utterance_id = re.compile(r"\[UTTERANCEID:([A-Za-z0-9_-]{1,80})\]", re.I)
    seen = {}
    records = []
    conflict = False
    for line in delta.splitlines():
        if not re.search(r"\bNPC_SAY:", line, re.I):
            continue
        match = utterance_id.search(line)
        if not match:
            continue
        key = match.group(1)
        visible = re.sub(r"\s+\[(?:TALKTARGET|UTTERANCEID|TTSHASH|TTSDUR):[^\]]*\]", "", line, flags=re.I).strip()
        if key in seen:
            if seen[key] != visible:
                conflict = True
            continue
        seen[key] = visible
        records.append(line)
    return records, conflict


def has_destination(text):
    return bool(re.search(rf"(?<!\w){re.escape(DEST)}(?!\w)", text, re.I))


def extract_offer(lines):
    # Fail closed: accept only a first-person, explicit commitment to lead/guide/take/walk to this endpoint.
    for line in lines:
        positive = re.search(r"\b(?:I can|I will|I'll) (?:lead|guide|take you|walk with you)\b", line, re.I)
        refusal_or_condition = re.search(r"\b(?:can't|cannot|won't|will not|don't|do not|would never|never|no,? I|if|unless|maybe|perhaps|could|would|might|should|not|but)\b", line, re.I)
        if positive and not refusal_or_condition and has_destination(line):
            return True, line
    return False, "\n".join(lines)


def explicit_refusal(lines):
    return any(re.search(r"\b(?:I (?:can't|cannot|won't|will not|don't|do not|would never|never)|no,? I)\b", line, re.I)
               for line in lines)


def response_complete(delta):
    match = re.search(r"CHAT_THREAD:\s*Queued\s+(\d+)\s+streamed chat lines and\s+\d+\s+action lines\.?", delta, re.I)
    if not match:
        return None
    return int(match.group(1))


def streamed_speech_count(delta):
    return len(final_speech_records(delta)[0])


def has_offer_conflict(lines):
    cue = re.compile(r"\b(?:can't|cannot|won't|will not|don't|do not|would never|never|no,? I|if|unless|maybe|perhaps|could|would|might|should|not|but)\b", re.I)
    return any(cue.search(line) for line in lines)


def action_matches(line, handle, endpoint):
    if "TRAVEL_LOCATION" not in line.upper() or not re.search(rf"\bserial\s*=\s*{handle[0]}\b", line, re.I):
        return False
    if has_destination(line):
        return True
    for match in re.finditer(r"([-+\d.eE]+)[,; ]+([-+\d.eE]+)[,; ]+([-+\d.eE]+)", line):
        try:
            point = tuple(map(float, match.groups()))
            if math.dist(point, endpoint) <= 2.0:
                return True
        except ValueError:
            pass
    return False


def tick_matches(line, handle):
    if "TRAVEL_TICK" not in line.upper():
        return False
    match = re.search(r"\bactor=(.*?)\s+destination=['\"]([^'\"]+)['\"]", line, re.I)
    return bool(match and match.group(1).strip().casefold() == NPC.casefold()
                and match.group(2).strip().casefold() == DEST.casefold())


def distance_xz(a, b):
    return math.hypot(a[0] - b[0], a[2] - b[2])


def state_destination(fields):
    raw = fields.get("destination")
    if not isinstance(raw, (list, tuple)) or len(raw) != 3:
        return None
    try:
        return tuple(float(value) for value in raw)
    except (TypeError, ValueError):
        return None


def main():
    if not NPC or not DEST or not os.environ.get("OUT") or not os.environ.get("NATIVE_LOG"):
        stop("setup", "set exact NPC, TRAVEL_DESTINATION, OUT, and NATIVE_LOG")
    rig, instance = os.environ.get("RIG"), os.environ.get("KAH_INSTANCE")
    if not ((rig, instance) in (("4080", "3"), ("5090", "3"))):
        stop("setup", "only isolated 4080 i3 or 5090 i3 is authorized")
    want_game = "/c/KenshiInst/3" if rig == "4080" else "/mnt/d/KenshiInst/3"
    want_harness = r"C:\KenshiInst\3\mods\AutomationHarness" if rig == "4080" else r"D:\KenshiInst\3\mods\AutomationHarness"
    if os.environ.get("KENSHI_DIR") != want_game or os.environ.get("KAH_DIR") != want_harness:
        stop("setup", f"game/harness paths do not match isolated instance 3: KENSHI_DIR={os.environ.get('KENSHI_DIR')!r}, KAH_DIR={os.environ.get('KAH_DIR')!r}")
    if not LOG.is_file():
        stop("setup", f"native log unavailable: {LOG}")
    for var in ("DESTINATION_RECEIPT", "PREFLIGHT_RECEIPT"):
        if not os.environ.get(var) or not Path(os.environ[var]).is_file():
            stop("setup", f"fresh {var.lower()} is required")
    try:
        OUT.mkdir(exist_ok=False)
    except FileExistsError:
        stop("setup", f"output directory already exists; refusing to overwrite prior row evidence: {OUT}")
    except OSError as e:
        stop("setup", f"could not atomically claim output directory {OUT}: {e}")

    status = run(["status"], "status.before")
    if "phase=world" not in status:
        stop("setup", "game is not in world phase")
    catalog = run(["towns", DEST, "max", "5"], "towns.before")
    if not has_destination(catalog):
        stop("setup", "destination absent from current native town catalog")
    town_line = next((x for x in catalog.splitlines() if DEST.casefold() in x.casefold()), "")
    tm = re.search(r"([-+\d.eE]+)\s*,\s*([-+\d.eE]+)\s*,\s*([-+\d.eE]+)", town_line)
    if not tm:
        stop("setup", "town result has no native endpoint coordinates")
    endpoint = tuple(map(float, tm.groups()))
    handle, start_pos, start_range = where(NPC, "where.before")
    if start_range > TALK_RADIUS:
        stop("setup", f"actor outside native chat radius: dist={start_range:g} > {TALK_RADIUS:g}")
    before = state(NPC, handle, "state.before", initial=True)
    (OUT / "endpoint.json").write_text(json.dumps({"destination": DEST, "xyz": endpoint}), encoding="utf-8")
    offset = LOG.stat().st_size
    (OUT / "native-log-offset.txt").write_text(str(offset), encoding="ascii")

    proposal = f"I meant you would lead me to {DEST} and I would follow you. Are you offering to guide me there? Please wait for my acceptance before starting."
    (OUT / "proposal.txt").write_text(proposal, encoding="utf-8")
    run(["stobe_say", f"#{handle[0]}/{handle[1]}", proposal], "proposal.send")
    deadline = time.monotonic() + WAIT
    offer_lines = []
    completion_count = None
    while time.monotonic() < deadline:
        delta = LOG.read_bytes()[offset:].decode("utf-8", "replace")
        (OUT / "proposal.native.delta.log").write_text(delta, encoding="utf-8")
        if any(action_matches(line, handle, endpoint) for line in delta.splitlines()):
            stop("product", "native TRAVEL_LOCATION appeared before player acceptance; acceptance not sent")
        observed_completion = response_complete(delta)
        if observed_completion is not None:
            completion_count = observed_completion
        final_lines, conflicting_utterance = final_speech_records(delta)
        if completion_count is not None and len(final_lines) >= completion_count:
            if conflicting_utterance:
                stop("evidence", "one final utterance ID carried conflicting speech text; no acceptance sent")
            offer_lines = target_speech("\n".join(final_lines), NPC, handle[0])
            offered, _ = extract_offer(offer_lines)
            conflicted = has_offer_conflict(offer_lines)
            if offered and not conflicted:
                break
            if offer_lines and explicit_refusal(offer_lines) and not offered:
                print(f"RESULT {ROW} PASS-DECLINED actor={NPC}#{handle[0]}/{handle[1]} destination={DEST} acceptance=not_sent native_travel=not_observed lifecycle_coverage=excluded")
                return
            if offer_lines:
                stop("evidence", "completed target response was ambiguous or lacked a narrow affirmative offer; no acceptance sent")
            stop("evidence", "completed streamed response contained no exact target-speaker reply; no acceptance sent")
        time.sleep(POLL)
    else:
        stop("evidence", "bounded wait ended without a CHAT_THREAD streamed-response completion marker and all queued NPC_SAY records")

    # Recheck immediately before acceptance so an automatic or late preaccept start cannot be legitimized.
    latest = LOG.read_bytes()[offset:].decode("utf-8", "replace")
    if any(action_matches(line, handle, endpoint) for line in latest.splitlines()):
        stop("product", "native TRAVEL_LOCATION appeared before player acceptance; acceptance not sent")
    accept_handle, accept_pos, accept_range = where(NPC, "where.before-accept")
    if accept_handle != handle:
        stop("evidence", "target identity changed before acceptance")
    if accept_range > TALK_RADIUS:
        stop("setup", f"actor wandered outside native chat radius before acceptance: dist={accept_range:g} > {TALK_RADIUS:g}; acceptance not sent")
    accept_state = state(NPC, handle, "state.before-accept")
    if accept_state["has_orders"] is True or accept_state["has_player_orders"] is True:
        stop("setup", "actor acquired an order before acceptance; acceptance not sent")
    (OUT / "acceptance-baseline.json").write_text(json.dumps({"position": accept_pos, "dist_to_player": accept_range}), encoding="utf-8")
    accept = f"I explicitly accept your offer to lead me to {DEST}. Please start that exact trip now."
    accept_offset = LOG.stat().st_size
    (OUT / "accept.txt").write_text(accept, encoding="utf-8")
    run(["stobe_say", f"#{handle[0]}/{handle[1]}", accept], "accept.send")
    deadline = time.monotonic() + WAIT
    action_line = None
    action_end_offset = -1
    while time.monotonic() < deadline:
        delta_bytes = LOG.read_bytes()[accept_offset:]
        delta = delta_bytes.decode("utf-8", "replace")
        (OUT / "accept.native.delta.log").write_text(delta, encoding="utf-8")
        encoded_lines = delta_bytes.splitlines(keepends=True)
        cursor = 0
        for record in encoded_lines:
            line = record.decode("utf-8", "replace").rstrip("\r\n")
            if action_matches(line, handle, endpoint):
                action_line = line
                action_end_offset = accept_offset + cursor + len(record)
                break
            cursor += len(record)
        if action_line:
            all_starts = [line for line in delta.splitlines() if action_matches(line, handle, endpoint)]
            if len(all_starts) != 1:
                stop("product", f"expected exactly one matching native TRAVEL_LOCATION start, observed {len(all_starts)}")
            break
        time.sleep(POLL)
    if not action_line:
        stop("evidence", "no native TRAVEL_LOCATION line matching actor serial and exact endpoint")

    settle_until = time.monotonic() + START_SETTLE
    while time.monotonic() < settle_until:
        current = LOG.read_bytes()[accept_offset:].decode("utf-8", "replace")
        starts = [line for line in current.splitlines() if action_matches(line, handle, endpoint)]
        if len(starts) > 1:
            stop("product", f"duplicate matching native TRAVEL_LOCATION start, observed {len(starts)}")
        time.sleep(min(0.1, max(0.0, settle_until - time.monotonic())))
    accepted_bytes = LOG.read_bytes()[accept_offset:]
    accepted_lines = accepted_bytes.splitlines(keepends=True)
    starts = []
    cursor = 0
    action_end_offset = -1
    for record in accepted_lines:
        line = record.decode("utf-8", "replace").rstrip("\r\n")
        if action_matches(line, handle, endpoint):
            starts.append(line)
            action_end_offset = accept_offset + cursor + len(record)
        cursor += len(record)
    if len(starts) != 1:
        stop("product", f"expected exactly one matching native TRAVEL_LOCATION start, observed {len(starts)}")

    movement_deadline = time.monotonic() + WAIT
    tick_line = None
    progress = []
    while time.monotonic() < movement_deadline:
        accepted_now = LOG.read_bytes()[accept_offset:].decode("utf-8", "replace")
        start_count = sum(1 for line in accepted_now.splitlines() if action_matches(line, handle, endpoint))
        if start_count != 1:
            stop("product", f"native TRAVEL_LOCATION start count changed during movement, observed {start_count}")
        raw = LOG.read_bytes()[action_end_offset:].decode("utf-8", "replace")
        tick_line = next((line for line in raw.splitlines() if tick_matches(line, handle)), None)
        current_handle, pos, dist_to_player = where(NPC, f"where.progress.{len(progress)+1:02d}")
        snap = state(NPC, handle, f"state.progress.{len(progress)+1:02d}")
        if current_handle != handle:
            stop("evidence", "actor handle changed during native travel")
        native_destination = state_destination(snap)
        if native_destination is None or math.dist(native_destination, endpoint) > DESTINATION_TOLERANCE:
            stop("evidence", f"native ai.destination is missing or differs from the accepted endpoint by more than {DESTINATION_TOLERANCE:g}m")
        if snap.get("path_failed") is not False or snap.get("dead") is True or snap.get("unconscious") is True:
            stop("evidence", "native actor state contradicts successful movement (path_failed/dead/unconscious)")
        reached = snap.get("destination_reached") is True
        if snap.get("destination_reached") is not False and not reached:
            stop("evidence", "native destination_reached status is missing or malformed")
        moving = snap.get("moving") is True
        progress.append({"position": pos, "distance_xz": distance_xz(pos, endpoint), "dist_to_player": dist_to_player,
                         "eligible": moving and not reached, "ai": snap})
        (OUT / "progress.json").write_text(json.dumps(progress, indent=2), encoding="utf-8")
        if reached:
            stop("evidence", "native destination_reached before repeated initial movement proof; arrival is a follow-on row")
        eligible = [sample for sample in progress if sample["eligible"]]
        interval_progress = [distance_xz(eligible[i - 1]["position"], endpoint) - distance_xz(eligible[i]["position"], endpoint)
                             for i in range(1, len(eligible))]
        total_progress = distance_xz(accept_pos, endpoint) - distance_xz(pos, endpoint)
        if (moving and len(interval_progress) >= 2
                and interval_progress[-1] >= MIN_INTERVAL_PROGRESS
                and interval_progress[-2] >= MIN_INTERVAL_PROGRESS
                and total_progress >= MIN_TOTAL_PROGRESS):
            break
        time.sleep(POLL)
    else:
        stop("evidence", f"no repeated directional movement proof: require two intervals >= {MIN_INTERVAL_PROGRESS:g}m and net progress >= {MIN_TOTAL_PROGRESS:g}m")
    # One final state/position receipt. Arrival is a separate row.
    final_handle, final_pos, final_range = where(NPC, "where.final")
    final_state = state(NPC, handle, "state.final")
    final_destination = state_destination(final_state)
    if final_destination is None or math.dist(final_destination, endpoint) > DESTINATION_TOLERANCE or final_state.get("path_failed") is not False:
        stop("evidence", "terminal native state lost the accepted destination or reports path failure")
    if final_handle != handle or distance_xz(final_pos, endpoint) >= distance_xz(accept_pos, endpoint) - MIN_TOTAL_PROGRESS:
        stop("evidence", "final native actor identity/position does not prove progress toward endpoint")
    print(f"RESULT {ROW} PASS-START-MOVE actor={NPC}#{handle[0]}/{handle[1]} destination={DEST} native_start=matched movement_tick={'observed' if tick_line else 'unavailable_optional'} position_at_acceptance={accept_pos} position_final={final_pos} dist_to_player_at_acceptance={accept_range:g} terminal_state={OUT/'state.final.txt'} trip_ledger=EXTERNAL_READONLY_REQUIRED arrival=FOLLOWON")


if __name__ == "__main__":
    try:
        main()
    except Stop as e:
        print(f"RESULT {ROW} FAIL {e.kind}: {e.reason}")
        sys.exit(2 if e.kind == "setup" else 3 if e.kind == "evidence" else 4)
