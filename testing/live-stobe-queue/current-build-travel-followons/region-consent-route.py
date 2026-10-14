#!/usr/bin/env python3
"""Two-turn coarse-region consent row: endpoint proposal first, one region-level consent, then native travel proof."""
import hashlib
import json
import math
import os
from pathlib import Path
import re
import shlex
import subprocess
import sys
import time

ROW = "P0-TRAVEL-REGION-CONSENT-ROUTE-001"
NPC = os.environ.get("NPC", "")
SERIAL = os.environ.get("NPC_SERIAL", "")
INDEX = os.environ.get("NPC_INDEX", "")
SPEAKER = os.environ.get("PLAYER_SPEAKER", "")
REGION = os.environ.get("OBSERVED_REGION", "")
OUT = Path(os.environ.get("OUT", ""))
NATIVE = Path(os.environ.get("NATIVE_LOG", ""))
BACKEND = Path(os.environ.get("BACKEND_LOG", ""))
WAIT = int(os.environ.get("WAIT_SECONDS", "240"))
POLL = float(os.environ.get("POLL_SECONDS", "2"))
MAX_AGE = int(os.environ.get("RECEIPT_MAX_AGE_SECONDS", "600"))
PROPOSAL = ""
ACCEPTANCE = ""
integration_endpoint_source = ""
initial_position = None
trip_scope_expected = None


class Stop(Exception):
    def __init__(self, kind, why):
        self.kind, self.why = kind, why


def stop(kind, why):
    raise Stop(kind, why)


def sha256(path):
    h = hashlib.sha256()
    with Path(path).open("rb") as f:
        for block in iter(lambda: f.read(1024 * 1024), b""):
            h.update(block)
    return h.hexdigest().upper()


def read_json(path, label):
    try:
        value = json.loads(Path(path).read_text(encoding="utf-8"))
    except Exception as exc:
        stop("setup", f"{label} missing/invalid JSON: {exc}")
    if not isinstance(value, dict):
        stop("setup", f"{label} must be an object")
    return value


def freshness(obj, label):
    stamp = obj.get("captured_utc")
    if not isinstance(stamp, (int, float)) or abs(time.time() - stamp) > MAX_AGE:
        stop("setup", f"{label} is missing/stale (max age {MAX_AGE}s)")


def run(args, label, timeout=25):
    try:
        proc = subprocess.run([os.environ.get("TRAVEL_DRIVER_BASH", "bash"), "-c",
                               shlex.join(["stobe-auto", *args])], capture_output=True,
                              text=True, timeout=timeout)
    except Exception as exc:
        stop("setup" if label.endswith(".before") else "evidence", f"{label} handler error: {exc}")
    (OUT / f"{label}.txt").write_text(proc.stdout + proc.stderr, encoding="utf-8")
    if proc.returncode:
        stop("setup" if label.endswith(".before") else "evidence", f"{label} exit={proc.returncode}")
    return proc.stdout.strip()


def normpath(value):
    return str(value).replace("\\", "/").rstrip("/").casefold()


def shared(expected, label):
    for key, value in expected.items():
        if label.get(key) != value:
            stop("setup", f"receipt binding mismatch for {key}")


def exact_receipts():
    rig = os.environ.get("RIG", "")
    if (rig, os.environ.get("KAH_INSTANCE")) not in (("4080", "3"), ("5090", "3")):
        stop("setup", "only isolated 4080/5090 instance 3 is allowed")
    game = "/c/KenshiInst/3" if rig == "4080" else "/mnt/d/KenshiInst/3"
    harness = r"C:\KenshiInst\3\mods\AutomationHarness" if rig == "4080" else r"D:\KenshiInst\3\mods\AutomationHarness"
    if os.environ.get("KENSHI_DIR") != game or os.environ.get("KAH_DIR") != harness:
        stop("setup", "route paths do not match isolated i3")
    if normpath(NATIVE) != normpath(game + "/RE_Kenshi/mods/Stobe/stobe.log"):
        stop("setup", "NATIVE_LOG is not selected isolated i3 native log")
    if not OUT.parent.is_dir():
        stop("setup", "OUT parent must exist")
    if not all((NPC, SPEAKER, REGION, re.fullmatch(r"\d+", SERIAL), re.fullmatch(r"\d+", INDEX),
                NATIVE.is_file(), BACKEND.is_file())):
        stop("setup", "exact actor/speaker/region and existing native/backend logs are required")

    pre = read_json(os.environ.get("PREFLIGHT_RECEIPT", ""), "PREFLIGHT_RECEIPT")
    reg = read_json(os.environ.get("REGION_RECEIPT", ""), "REGION_RECEIPT")
    integration = read_json(os.environ.get("INTEGRATION_RECEIPT", ""), "INTEGRATION_RECEIPT")
    for item, name in ((pre, "PREFLIGHT"), (reg, "REGION"), (integration, "INTEGRATION")):
        freshness(item, name)
    expect = {"rig": rig, "instance": "3", "npc_name": NPC, "npc_serial": int(SERIAL),
              "npc_index": int(INDEX), "player_speaker": SPEAKER}
    for item in (pre, reg, integration):
        shared(expect, item)
    for key in ("save_id", "session_generation", "build_sha256"):
        if not pre.get(key):
            stop("setup", f"preflight lacks {key}")
        for item in (reg, integration):
            if item.get(key) != pre[key]:
                stop("setup", f"{key} mismatch across current receipts")
    if pre.get("phase") != "world" or pre.get("paused") is not False or pre.get("input_isolation") != "ON":
        stop("setup", "preflight must prove live unpaused world and input isolation ON")
    if pre.get("native_log") != str(NATIVE) or pre.get("backend_log") != str(BACKEND):
        stop("setup", "log paths differ from fresh preflight")
    if reg.get("region_name") != REGION or not reg.get("region_source"):
        stop("setup", "region receipt does not prove the exact observed coarse region")
    if not re.fullmatch(r"[A-F0-9]{64}", str(pre.get("build_sha256", "")).upper()):
        stop("setup", "preflight build SHA-256 is invalid")

    validate_integration_contract(integration, pre["build_sha256"], os.environ.get("INTEGRATION_SHA256", ""))

    campaign_id = pre.get("campaign_id")
    speaker_id = pre.get("player_speaker_serial")
    if campaign_id in (None, "") or speaker_id in (None, ""):
        stop("setup", "preflight lacks campaign_id/player_speaker_serial required for exact trip-read scope")
    global trip_scope_expected
    campaign_id = int(campaign_id) if str(campaign_id).isdigit() else campaign_id
    speaker_id = int(speaker_id) if str(speaker_id).isdigit() else speaker_id
    trip_scope_expected = {"campaign_id": campaign_id, "actor_id": int(SERIAL), "speaker_id": speaker_id}

    model_path = Path(str(pre.get("model_readiness_receipt_path", "")))
    model_sha = str(pre.get("model_readiness_receipt_sha256", "")).upper()
    if not model_path.is_file() or not re.fullmatch(r"[A-F0-9]{64}", model_sha) or sha256(model_path) != model_sha:
        stop("setup", "preflight-pinned model readiness receipt missing or hash mismatch")
    model = read_json(model_path, "MODEL_READINESS")
    freshness(model, "MODEL_READINESS")
    shared(expect, model)
    for key in ("save_id", "session_generation", "build_sha256"):
        if model.get(key) != pre[key]:
            stop("setup", f"model-readiness {key} mismatch")
    if model.get("review_status") != "CLEAR" or model.get("model_status") != "READY":
        stop("setup", "model readiness must be opened, fresh, reviewed CLEAR and READY")
    return pre, reg, integration, model


def validate_integration_contract(integration, loaded_build_sha, exact_pin):
    pin = str(exact_pin).upper()
    if not re.fullmatch(r"[A-F0-9]{64}", pin) or str(integration.get("candidate_sha256", "")).upper() != pin:
        stop("setup", "independent exact integration SHA pin is absent or mismatched")
    if integration.get("review_status") != "CLEAR" or integration.get("installed") is not True or integration.get("served") is not True:
        stop("setup", "integration is not exact-reviewed and proven installed/served")
    if integration.get("integration_build_sha256") != loaded_build_sha:
        stop("setup", "integration is not bound to the exact loaded current build")
    if integration.get("movement_consent_contract") != "one_coarse_region_acceptance":
        stop("setup", "selected source does not prove one region-level consent authorizes the exact internal waypoint")
    if integration.get("endpoint_requires_separate_consent") is not False:
        stop("setup", "selected source still requires endpoint-specific consent")
    if integration.get("preconsent_proposal_only") is not True:
        stop("setup", "integration receipt does not certify no dispatch before coarse consent")
    if integration.get("endpoint_proof_source") not in ("current_actor_scoped_native_candidate", "reviewed_server_receipt"):
        stop("setup", "integration receipt does not identify a reviewed native endpoint provenance source")


def complete(delta):
    marks = list(re.finditer(r"CHAT_THREAD:\s*Queued\s+(\d+)\s+streamed chat lines and\s+(\d+) action lines\.?", delta, re.I))
    if not marks:
        return None
    return int(marks[-1].group(1)), int(marks[-1].group(2))


def speech(delta, name, serial):
    out = []
    for line in delta.splitlines():
        if "NPC_SAY:" not in line:
            continue
        m = re.search(r"NPC_SAY:\s*([^|:]+)\|(\d+):\s*(.*)", line, re.I)
        if not m or m.group(1).strip().casefold() != name.casefold() or int(m.group(2)) != serial:
            stop("evidence", "stream includes NPC_SAY not bound to exact actor serial")
        out.append(m.group(3).strip())
    return out


def request_id(delta, speaker, target, message):
    ids = []
    for line in delta.splitlines():
        m = re.search(r"TEST_INBOX:\s*say\s+id=(k\d+_\d+_\d+)\s+mode=\S+\s+speaker=(.*?)\s+target=(.*?)\s+text=(.*)$", line)
        if m and m.group(2).strip() == speaker and m.group(3).strip() == target and m.group(4) == message:
            ids.append(m.group(1))
    return ids[0] if len(ids) == 1 else None


def json_records(raw):
    decoder = json.JSONDecoder()
    for line in raw.splitlines():
        for i, char in enumerate(line):
            if char != "{":
                continue
            try:
                obj, _ = decoder.raw_decode(line[i:])
            except Exception:
                continue
            if isinstance(obj, dict):
                yield obj


def flatten(obj, out):
    if isinstance(obj, dict):
        for k, v in obj.items():
            out.setdefault(str(k).casefold(), []).append(v)
            flatten(v, out)
    elif isinstance(obj, list):
        for v in obj:
            flatten(v, out)


def val(fields, *keys):
    for key in keys:
        values = fields.get(key.casefold(), [])
        if values:
            return values[0]
    return None


def finite_vector(value, label):
    if not isinstance(value, (list, tuple)) or len(value) != 3:
        stop("evidence", f"{label} is missing/malformed")
    try:
        result = tuple(float(v) for v in value)
    except (TypeError, ValueError, OverflowError):
        stop("evidence", f"{label} contains a non-numeric coordinate")
    if not all(math.isfinite(v) for v in result):
        stop("evidence", f"{label} contains a non-finite coordinate")
    return result


def correlated(raw, reqid, expected_decision):
    found = []
    for rec in json_records(raw):
        fields = {}
        flatten(rec, fields)
        if (val(fields, "native_request_id", "kah_request_id") == reqid
                and val(fields, "row_id", "row") == ROW
                and val(fields, "npc_name", "target_npc") == NPC
                and val(fields, "npc_serial", "actor_serial") in (int(SERIAL), SERIAL)
                and val(fields, "speaker", "player_speaker") == SPEAKER
                and val(fields, "player_message", "user_message") == expected_decision["message"]):
            found.append((rec, val(fields, "travel_decision")))
    return found


def no_active_trip_proof(rec, serial, speaker):
    fields = {}
    flatten(rec, fields)
    read_ok = val(fields, "preexisting_trip_read_succeeded", "current_trip_read_succeeded", "trip_read_succeeded")
    # This is a separate read scope, not the enclosing chat record's actor/speaker.
    actor = val(fields, "trip_read_actor_serial", "preexisting_trip_actor_serial", "current_trip_actor_serial")
    trip_speaker = val(fields, "trip_read_speaker_serial", "preexisting_trip_speaker_serial", "current_trip_speaker_serial")
    status = val(fields, "prior_trip_status", "preexisting_trip_status", "trip_before_status")
    scope_hash = val(fields, "trip_read_scope_hash", "preexisting_trip_scope_hash")
    scope = val(fields, "trip_read_scope", "preexisting_trip_scope")
    expected = trip_scope_expected
    scope_ok = (isinstance(scope, dict) and isinstance(expected, dict)
                and scope == expected
                and actor in (serial, str(serial))
                and trip_speaker == expected.get("speaker_id"))
    if scope_ok:
        encoded = json.dumps(scope, ensure_ascii=False, separators=(",", ":"))
        scope_ok = hashlib.sha256(encoded.encode("utf-8")).hexdigest().casefold() == str(scope_hash).casefold()
    return (read_ok is True and actor in (serial, str(serial))
            and scope_ok and isinstance(scope_hash, str) and re.fullmatch(r"[a-fA-F0-9]{64}", scope_hash)
            and isinstance(status, str) and status.upper() in ("NONE", "NO_ACTIVE_TRIP"))


def endpoint_from_proposal(rec, speech_text):
    fields = {}
    flatten(rec, fields)
    point = val(fields, "destination_point")
    regional = val(fields, "regional_goal")
    if not isinstance(point, dict) or not isinstance(regional, dict):
        stop("evidence", "accepted record lacks structured destination_point and regional_goal receipts")
    endpoint_id = point.get("id")
    label = point.get("label")
    region = regional.get("region")
    serial = point.get("actor_serial")
    source = regional.get("endpoint_source")
    xyz = tuple(point.get(axis) for axis in ("x", "y", "z"))
    try:
        xyz = tuple(float(v) for v in xyz)
    except (TypeError, ValueError):
        xyz = ()
    if not endpoint_id or not label or region != REGION or serial not in (int(SERIAL), SERIAL):
        stop("evidence", "proposal record lacks exact actor/region-bound native endpoint identity")
    if (regional.get("endpoint_id") != endpoint_id or regional.get("endpoint_label") != label
            or regional.get("endpoint_actor_serial") not in (int(SERIAL), SERIAL)
            or point.get("source") != "native_local"):
        stop("evidence", "destination_point and regional_goal disagree on candidate identity/provenance")
    if regional.get("endpoint_region_evidence") not in ("native_spatial_region", "npc_known_town_region"):
        stop("evidence", "regional endpoint lacks an explicit spatial or known-town region proof")
    if regional.get("ordinary_order_validation") != "passed" or not isinstance(regional.get("order_validation_gamets"), (int, float)):
        stop("evidence", "ordinary travel-order validation result is absent or unbound to game time")
    if not isinstance(regional.get("trip_read_gamets"), (int, float)):
        stop("evidence", "no-active-trip read lacks its exact game-time marker")
    if len(xyz) != 3 or not all(math.isfinite(v) for v in xyz):
        stop("evidence", "proposal record lacks finite XYZ from the scoped native endpoint receipt")
    if not source:
        stop("evidence", "proposal record lacks native endpoint provenance")
    if source != integration_endpoint_source:
        stop("evidence", "runtime endpoint provenance differs from reviewed source pin")
    # The spoken record must identify the same exact endpoint, while retaining coarse-route uncertainty.
    if not re.search(rf"(?<!\w){re.escape(str(label))}(?!\w)", speech_text, re.I):
        stop("product", "complete NPC proposal does not name the backend's grounded endpoint")
    return {"id": str(endpoint_id), "label": str(label), "region": str(region), "source": str(source), "xyz": xyz}


def record_endpoint_id(rec):
    fields = {}
    flatten(rec, fields)
    return val(fields, "travel_destination_id", "destination_point_id", "native_endpoint_id", "travel_destination")


def chat(message, label, native_base, backend_base):
    run(["stobe_say", f"#{SERIAL}/{INDEX}", message], label + ".send", timeout=45)
    deadline = time.monotonic() + WAIT
    delta = ""
    mark = None
    reqid = None
    lines = []
    while time.monotonic() < deadline:
        delta = NATIVE.read_bytes()[native_base:].decode("utf-8", "replace")
        reqid = request_id(delta, SPEAKER, NPC, message)
        mark = complete(delta)
        lines = speech(delta, NPC, int(SERIAL))
        if reqid and mark and len(lines) == mark[0]:
            break
        time.sleep(POLL)
    else:
        stop("evidence", f"{label} did not complete with exact request ID and full native stream")
    if mark[0] < 1 or not reqid:
        stop("evidence", f"{label} lacks a unique exact submission ID or complete target reply")
    bdelta = BACKEND.read_bytes()[backend_base:].decode("utf-8", "replace")
    (OUT / f"{label}.native.delta.log").write_text(delta, encoding="utf-8")
    (OUT / f"{label}.backend.delta.log").write_text(bdelta, encoding="utf-8")
    (OUT / f"{label}.speech.txt").write_text("\n".join(lines) + "\n", encoding="utf-8")
    return delta, bdelta, reqid, mark, lines


def state(label):
    raw = run(["stobe_state", f"#{SERIAL}/{INDEX}"], label)
    try:
        obj = json.loads(raw)
        ai = obj["ai"]
        if obj.get("name") != NPC or int(obj.get("serial", -1)) != int(SERIAL) or not isinstance(ai, dict):
            raise ValueError("wrong identity or missing nested ai")
        return obj, ai
    except Exception as exc:
        stop("evidence", f"{label} exact stobe_state invalid: {exc}")


def where(label):
    raw = run(["where", f"#{SERIAL}/{INDEX}"], label)
    m = re.search(rf"^\s*{re.escape(NPC)}\s+#?{SERIAL}/{INDEX}\b.*?pos=([-+\d.eE]+),\s*([-+\d.eE]+),\s*([-+\d.eE]+)", raw, re.M)
    if not m:
        stop("evidence", f"{label} lacks exact actor position")
    return finite_vector(m.groups(), f"{label} position")


def action_events(delta):
    return [line for line in delta.splitlines() if "ACTION_EXEC: TRAVEL_LOCATION" in line]


def actions_follow_exact_request(delta, reqid):
    lines = delta.splitlines()
    request_lines = [i for i, line in enumerate(lines)
                     if re.search(rf"TEST_INBOX:\s*say\s+id={re.escape(reqid)}\b", line)]
    action_lines = [i for i, line in enumerate(lines) if re.search(r"ACTION_EXEC:", line, re.I)]
    return len(request_lines) == 1 and all(i > request_lines[0] for i in action_lines)


def exec_events(delta):
    return [line for line in delta.splitlines() if re.search(r"ACTION_EXEC:", line, re.I)]


def preconsent_no_action(delta, action_count):
    return action_count == 0 and not action_events(delta) and not re.search(r"ACTION_EXEC:", delta, re.I)


def require_proposal_none(decision):
    if not isinstance(decision, str) or not decision.strip():
        stop("evidence", "proposal record lacks explicit travel_decision=NONE")
    if decision.strip().upper() != "NONE":
        stop("product", f"conceptual region proposal entered travel decision {decision!r}")


def event_matches(line, endpoint):
    actor = re.search(r"\bactor=(.*?)\s+destination=['\"]([^'\"]+)['\"]", line, re.I)
    xyz = re.search(r"\bx=([-+\d.eE]+)\s+y=([-+\d.eE]+)\s+z=([-+\d.eE]+)", line, re.I)
    serial_ok = re.search(rf"\bserial\s*=\s*{SERIAL}\b", line, re.I)
    if not actor or actor.group(1).strip().casefold() != NPC.casefold() or actor.group(2).strip().casefold() != endpoint["label"].casefold() or not serial_ok:
        return None
    if not xyz and re.search(r"\b[xyz]\s*=", line, re.I):
        return None
    if not xyz:
        return None
    try:
        coords = tuple(float(v) for v in xyz.groups())
    except (TypeError, ValueError, OverflowError):
        return None
    if not all(math.isfinite(v) for v in coords):
        return None
    # TRAVEL_LOCATION coordinates must match the endpoint coordinates returned by
    # the current scoped native candidate (or reviewed server receipt), within 1m.
    if math.dist(coords, endpoint["xyz"]) > 1.0:
        return None
    return coords


def native_progress(endpoint, baseline_position):
    samples = []
    deadline = time.monotonic() + max(10.0, float(os.environ.get("PROGRESS_SECONDS", "90")))
    while time.monotonic() < deadline and len(samples) < 8:
        doc, ai = state(f"state.progress.{len(samples)+1:02d}")
        pos = where(f"where.progress.{len(samples)+1:02d}")
        dest = finite_vector(ai.get("destination"), "native ai.destination")
        samples.append({"pos": pos, "destination": dest, "moving": ai.get("moving"),
                        "reached": ai.get("destination_reached"), "failed": ai.get("path_failed"),
                        "name": doc.get("name"), "serial": int(doc.get("serial"))})
        (OUT / "progress.samples.json").write_text(json.dumps(samples, indent=2), encoding="utf-8")
        if len(samples) >= 4 and any(samples[i+1]["moving"] is True for i in range(1, len(samples)-1)):
            break
        time.sleep(POLL)
    if len(samples) < 3:
        stop("evidence", "fewer than three bounded native destination/progress samples")
    validate_progress_samples(samples, endpoint, baseline_position)
    return samples


def validate_progress_samples(samples, endpoint, baseline_position):
    for s in samples:
        s["destination"] = finite_vector(s.get("destination"), "native ai.destination")
        s["pos"] = finite_vector(s.get("pos"), "native actor position")
        if any(type(s.get(key)) is not bool for key in ("moving", "reached", "failed")):
            stop("evidence", "native movement/reached/path_failed state is missing or non-boolean")
        if math.dist(s["destination"], endpoint["xyz"]) > 1.0:
            stop("product", "same actor native ai.destination differs from accepted endpoint")
        if s["failed"] is not False:
            stop("product", "same actor native path_failed after region consent")
    if not any(s["moving"] is True and s["reached"] is False for s in samples):
        stop("evidence", "no native same-actor moving/not-reached sample")
    progressed = False
    baseline_position = tuple(float(x) for x in baseline_position)
    for i in range(len(samples)-1):
        p0 = baseline_position if i == 0 else samples[i-1]["pos"]
        p1, p2 = samples[i]["pos"], samples[i+1]["pos"]
        d0 = math.dist(p0, endpoint["xyz"])
        d1 = math.dist(p1, endpoint["xyz"])
        d2 = math.dist(p2, endpoint["xyz"])
        net = math.dist(baseline_position, p2)
        if d0-d1 >= 0.5 and d1-d2 >= 0.5 and net >= 5.0:
            progressed = True
            break
    if not progressed:
        stop("evidence", "movement samples do not show two consecutive >=0.5m closer intervals and >=5m net progress")


def main():
    global PROPOSAL, ACCEPTANCE, integration_endpoint_source
    pre, region_receipt, integration, model = exact_receipts()
    integration_endpoint_source = integration["endpoint_proof_source"]
    try:
        OUT.mkdir(exist_ok=False)
    except FileExistsError:
        stop("setup", "OUT exists; no KAH handler was invoked")
    except OSError as exc:
        stop("setup", f"cannot atomically claim OUT: {exc}")
    for name, obj in (("preflight", pre), ("region", region_receipt), ("integration", integration), ("model-readiness", model)):
        (OUT / f"{name}.receipt.json").write_text(json.dumps(obj, indent=2) + "\n", encoding="utf-8")

    status = run(["status"], "status.before")
    if "phase=world" not in status:
        stop("setup", "KAH is not in active world phase")
    ping = run(["stobe_ping"], "ping.before")
    if not re.search(rf"\bspeaker={re.escape(SPEAKER)}\b", ping):
        stop("setup", "current native player speaker does not match receipt")
    where(NPC and "where.before")
    _, before_ai = state("state.before")
    if before_ai.get("dead") is True or before_ai.get("unconscious") is True or before_ai.get("can_take_orders") is False:
        stop("setup", "exact NPC unavailable for travel")
    if before_ai.get("moving") is True or before_ai.get("has_orders") is True or before_ai.get("has_player_orders") is True:
        stop("setup", "exact NPC already has active movement/orders; refusing to change existing state")

    # Ask for a proposal without consenting. Any action here is a safety violation.
    PROPOSAL = (f"Would you suggest {REGION} as a broad area for a trip? I am only asking whether you would offer that rough area; "
                "I am not agreeing to travel yet.")
    (OUT / "proposal.request.txt").write_text(PROPOSAL, encoding="utf-8")
    n0, b0 = NATIVE.stat().st_size, BACKEND.stat().st_size
    first, first_backend, first_id, first_mark, first_lines = chat(PROPOSAL, "region-proposal", n0, b0)
    first_actions = action_events(first)
    if not preconsent_no_action(first, first_mark[1]):
        stop("product", "pre-consent proposal turn dispatched a native action")
    joined = " ".join(first_lines)
    if REGION.casefold() not in joined.casefold():
        stop("product", "complete first reply does not identify the requested broad region")
    if not re.search(r"\b(?:rough|broad|area|region)\b", joined, re.I):
        stop("evidence", "first reply does not identify a coarse regional offer")
    first_records = correlated(first_backend, first_id, {"message": PROPOSAL})
    if len(first_records) != 1:
        stop("evidence", "first backend record is not uniquely correlated to the exact proposal question")
    first_fields = {}
    flatten(first_records[0][0], first_fields)
    if (str(val(first_fields, "region_plan_decision") or "").upper() != "SUGGEST"
            or str(val(first_fields, "proposed_region") or "").casefold() != REGION.casefold()):
        stop("product", "first turn did not create a same-region conceptual proposal")
    require_proposal_none(first_records[0][1])

    # One consent accepts the broad regional offer; exact waypoint is internal
    # navigation detail selected by the ordinary current-turn handler.
    ACCEPTANCE = f"I agree to go to {REGION} as a broad area."
    (OUT / "region-consent.request.txt").write_text(ACCEPTANCE, encoding="utf-8")
    # Capture the whole proposal-to-consent interval after the final pre-consent
    # state reads, so actions cannot slip between the check and the boundary.
    _, before_consent_ai = state("state.before-consent")
    if before_consent_ai.get("moving") is True or before_consent_ai.get("has_orders") is True or before_consent_ai.get("has_player_orders") is True:
        stop("setup", "same actor acquired movement/orders before coarse consent")
    initial_position = where("where.before-consent")
    n1, b1 = NATIVE.stat().st_size, BACKEND.stat().st_size
    between = NATIVE.read_bytes()[n0:n1].decode("utf-8", "replace")
    if not preconsent_no_action(between, 0):
        stop("product", "native action appeared anywhere before the exact coarse-region consent submission")
    second, second_backend, second_id, second_mark, second_lines = chat(ACCEPTANCE, "region-consent", n1, b1)
    if not actions_follow_exact_request(second, second_id):
        stop("evidence", "native action is not ordered after this exact accepted stobe_say request")
    second_records = correlated(second_backend, second_id, {"message": ACCEPTANCE})
    if len(second_records) != 1:
        stop("evidence", "second backend response lacks unique exact request/row/actor/speaker/message correlation")
    if str(second_records[0][1]).upper() not in ("ACCEPT", "ACCEPTED"):
        stop("product", f"explicit coarse-region consent did not reach acceptance path (decision={second_records[0][1]!r})")
    if not no_active_trip_proof(second_records[0][0], int(SERIAL), SPEAKER):
        stop("evidence", "consent record lacks a successful same-actor/speaker no-active-trip read")
    joined_second = " ".join(second_lines)
    endpoint = endpoint_from_proposal(second_records[0][0], joined_second)
    if endpoint["region"].casefold() != REGION.casefold():
        stop("product", "grounded endpoint region differs from the accepted coarse region")
    if not re.search(r"\brough (?:starting point|waypoint)\b|\bapproximate (?:starting point|waypoint)\b", joined_second, re.I):
        stop("product", "speech does not state that the selected waypoint is approximate")
    if not re.search(r"\b(?:cannot|can't|won't) promise\b.*\b(?:route|safe|safety|find|what we will find)\b", joined_second, re.I):
        stop("product", "speech overstates route safety or what will be found")
    (OUT / "endpoint.accepted.json").write_text(json.dumps(endpoint, indent=2) + "\n", encoding="utf-8")
    events = action_events(second)
    all_exec = exec_events(second)
    if second_mark[1] != 1 or len(events) != 1 or len(all_exec) != 1 or all_exec[0] != events[0]:
        stop("product", f"one coarse-region consent requires exactly one native travel action; action_lines={second_mark[1]} events={len(events)}")
    xyz = event_matches(events[0], endpoint)
    if xyz is None:
        stop("product", "native action actor, serial or exact endpoint label differs from the grounded proposal")
    if math.dist(xyz, endpoint["xyz"]) > 1.0:
        stop("evidence", "native action coordinates differ from the scoped endpoint receipt")
    (OUT / "native.travel.action.txt").write_text(events[0] + "\n", encoding="utf-8")
    samples = native_progress(endpoint, initial_position)
    print(f"RESULT {ROW} PASS actor={NPC}#{SERIAL}/{INDEX} region={REGION!r} first=PROPOSE preconsent_actions=0 coarse_consent=1 endpoint={endpoint['label']!r} native_dispatches=1 progress_samples={len(samples)} durable_trip_ledger=UNSUPPORTED evidence={OUT}")


if __name__ == "__main__":
    try:
        main()
    except Stop as exc:
        print(f"RESULT {ROW} FAIL {exc.kind}: {exc.why}")
        sys.exit(1)
    except Exception as exc:
        print(f"RESULT {ROW} FAIL evidence: unexpected row error {type(exc).__name__}: {exc}")
        sys.exit(1)
