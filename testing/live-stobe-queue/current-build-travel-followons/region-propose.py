#!/usr/bin/env python3
"""One isolated P0 check: explicit coarse-region request, PROPOSE, no native dispatch."""
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

ROW = "P0-TRAVEL-REGION-PROPOSE-001"
START_ROW = "P0-TRAVEL-START-MOVE-001"
START_DRIVER_SHA256 = "EB0BA4C4F3B3F7091D1A8ED79E7CCD356823B23850B6B6885172C6B366213C70"
NPC = os.environ.get("NPC", "")
SERIAL = os.environ.get("NPC_SERIAL", "")
INDEX = os.environ.get("NPC_INDEX", "")
SPEAKER = os.environ.get("PLAYER_SPEAKER", "")
REGION = os.environ.get("OBSERVED_REGION", "")
OUT = Path(os.environ.get("OUT", ""))
NATIVE_LOG = Path(os.environ.get("NATIVE_LOG", ""))
BACKEND_LOG = Path(os.environ.get("BACKEND_LOG", ""))
WAIT = int(os.environ.get("WAIT_SECONDS", "300"))
POLL = float(os.environ.get("POLL_SECONDS", "2"))
MAX_AGE = int(os.environ.get("RECEIPT_MAX_AGE_SECONDS", "600"))
MESSAGE = ""


class Stop(Exception):
    def __init__(self, kind, why):
        self.kind, self.why = kind, why


def stop(kind, why):
    raise Stop(kind, why)


def read_json_path(path, label):
    try:
        value = json.loads(Path(path).read_text(encoding="utf-8"))
    except Exception as e:
        stop("setup", f"{label} unreadable/invalid JSON: {e}")
    if not isinstance(value, dict):
        stop("setup", f"{label} must be a JSON object")
    return value


def read_json_env(key):
    return read_json_path(os.environ.get(key, ""), key)


def sha256(path):
    h = hashlib.sha256()
    with Path(path).open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest().upper()


def run(args, label, timeout=25):
    try:
        command = shlex.join(["stobe-auto", *args])
        p = subprocess.run([os.environ.get("TRAVEL_DRIVER_BASH", "bash"), "-c", command],
                           capture_output=True, text=True, timeout=timeout)
    except Exception as e:
        stop("setup" if label.endswith(".before") else "evidence", f"{label} handler error: {e}")
    (OUT / f"{label}.txt").write_text(p.stdout + p.stderr, encoding="utf-8")
    if p.returncode:
        stop("setup" if label.endswith(".before") else "evidence", f"{label} exit={p.returncode}")
    return p.stdout.strip()


def freshness(receipt, label):
    ts = receipt.get("captured_utc")
    if not isinstance(ts, (int, float)) or abs(time.time() - ts) > MAX_AGE:
        stop("setup", f"{label} receipt is missing/stale (maximum age {MAX_AGE}s)")


def shared_bindings(rig):
    return {"rig": rig, "instance": "3", "npc_name": NPC, "npc_serial": int(SERIAL),
            "npc_index": int(INDEX), "player_speaker": SPEAKER}


def assert_bindings(receipt, expected, label):
    for key, value in expected.items():
        if receipt.get(key) != value:
            stop("setup", f"{label} binding mismatch for {key}")


def validate_start_proof(start):
    freshness(start, "START_DRIVER")
    if start.get("row_id") != START_ROW or start.get("result") != "PASS-START-MOVE":
        stop("setup", "frozen start-driver receipt is not the matching PASS-START-MOVE row")
    if start.get("driver_sha256", "").upper() != START_DRIVER_SHA256:
        stop("setup", "start-driver source hash is not the frozen reviewed driver")
    driver_path = Path(__file__).resolve().parent.parent / "current-build-travel-driver" / "driver.py"
    if not driver_path.is_file() or sha256(driver_path) != START_DRIVER_SHA256:
        stop("setup", "local frozen start-driver bytes do not match the reviewed source pin")
    out = Path(str(start.get("out_dir", "")))
    result_file = Path(str(start.get("result_file", "")))
    required = {
        "accept.native.delta.log": start.get("accept_native_delta_sha256"),
        "endpoint.json": start.get("endpoint_json_sha256"),
        "progress.json": start.get("progress_json_sha256"),
    }
    if not out.is_dir() or not result_file.is_file():
        stop("setup", "start-driver output/result files are unavailable")
    result_text = result_file.read_text(encoding="utf-8", errors="replace")
    if len(re.findall(rf"^RESULT\s+{re.escape(START_ROW)}\s+PASS-START-MOVE\b", result_text, re.M)) != 1:
        stop("setup", "start-driver result artifact lacks exactly one PASS-START-MOVE line")
    if start.get("result_file_sha256", "").upper() != sha256(result_file):
        stop("setup", "start-driver result-file hash mismatch")
    for name, expected_hash in required.items():
        file_path = out / name
        if not file_path.is_file() or not re.fullmatch(r"[A-Fa-f0-9]{64}", str(expected_hash or "")):
            stop("setup", f"start-driver proof is missing exact {name} hash")
        if sha256(file_path) != str(expected_hash).upper():
            stop("setup", f"start-driver proof hash mismatch for {name}")
    endpoint = read_json_path(out / "endpoint.json", "start-driver endpoint")
    xyz = endpoint.get("xyz")
    if not isinstance(xyz, list) or len(xyz) != 3:
        stop("evidence", "start-driver endpoint lacks exact native coordinates")
    try:
        endpoint_xyz = tuple(float(x) for x in xyz)
    except (ValueError, TypeError):
        stop("evidence", "start-driver endpoint coordinates are malformed")
    action_lines = [line for line in (out / "accept.native.delta.log").read_text(encoding="utf-8", errors="replace").splitlines()
                    if "ACTION_EXEC: TRAVEL_LOCATION" in line and re.search(rf"\bserial\s*=\s*{SERIAL}\b", line, re.I)]
    if len(action_lines) != 1:
        stop("evidence", "start-driver output does not contain exactly one actor-scoped TRAVEL_LOCATION event")
    xyz_match = re.search(r"\bx=([-+\d.eE]+)\s+y=([-+\d.eE]+)\s+z=([-+\d.eE]+)", action_lines[0])
    if not xyz_match or math.dist(tuple(float(v) for v in xyz_match.groups()), endpoint_xyz) > 2.0:
        stop("evidence", "native start event endpoint is missing or differs from the driver's catalog endpoint")
    start["_endpoint_xyz"] = endpoint_xyz
    start["_start_action_line"] = action_lines[0]


def exact_receipt_bindings(pre, start, region, model):
    for item, label in ((pre, "PREFLIGHT"), (region, "REGION"), (model, "MODEL_READINESS")):
        freshness(item, label)
    expected = shared_bindings(os.environ.get("RIG"))
    for item, label in ((pre, "PREFLIGHT"), (start, "START_DRIVER"), (region, "REGION"), (model, "MODEL_READINESS")):
        assert_bindings(item, expected, label)
    for key in ("save_id", "session_generation", "build_sha256"):
        value = pre.get(key)
        if not value:
            stop("setup", f"PREFLIGHT missing {key}")
        for item, label in ((start, "START_DRIVER"), (region, "REGION"), (model, "MODEL_READINESS")):
            if item.get(key) != value:
                stop("setup", f"{label} {key} does not match preflight")
    if pre.get("phase") != "world" or pre.get("paused") is not False or pre.get("input_isolation") != "ON":
        stop("setup", "preflight must prove unpaused world and input isolation ON")
    if pre.get("native_log") != str(NATIVE_LOG) or pre.get("backend_log") != str(BACKEND_LOG):
        stop("setup", "log paths differ from preflight pins")
    if model.get("review_status") != "CLEAR" or model.get("model_status") != "READY":
        stop("setup", "model readiness receipt is not reviewed CLEAR/READY")
    if not region.get("region_name") or not region.get("region_source") or region.get("region_name") != REGION:
        stop("setup", "observed-region receipt does not bind the requested current region")


def load_model_receipt(pre):
    path = Path(str(pre.get("model_readiness_receipt_path", "")))
    expected = str(pre.get("model_readiness_receipt_sha256", "")).upper()
    if not path.is_file() or not re.fullmatch(r"[A-F0-9]{64}", expected):
        stop("setup", "preflight does not pin a readable model-readiness receipt and SHA-256")
    if sha256(path) != expected:
        stop("setup", "model-readiness receipt file hash mismatch")
    return read_json_path(path, "model-readiness receipt")


def parse_state(raw):
    try:
        obj = json.loads(raw)
        ai = obj["ai"]
        if not isinstance(ai, dict) or str(obj["name"]) != NPC or int(obj["serial"]) != int(SERIAL):
            raise ValueError("wrong actor identity or missing nested ai")
        return obj, ai
    except Exception as e:
        stop("evidence", f"malformed exact-handle stobe_state: {e}")


def validate_active_native_destination(ai, endpoint):
    raw = ai.get("destination")
    if not isinstance(raw, list) or len(raw) != 3:
        stop("setup", "fresh actor state lacks native destination vector")
    try:
        current = tuple(float(v) for v in raw)
    except (ValueError, TypeError):
        stop("setup", "fresh native destination vector is malformed")
    if math.dist(current, endpoint) > 5.0 or ai.get("moving") is not True:
        stop("setup", "frozen start destination is no longer active for this actor")
    if ai.get("destination_reached") is not False or ai.get("path_failed") is not False:
        stop("setup", "native active-leg state is terminal or failed")


def complete_stream(delta):
    m = re.search(r"CHAT_THREAD:\s*Queued\s+(\d+)\s+streamed chat lines and\s+(\d+) action lines\.?", delta, re.I)
    return (int(m.group(1)), int(m.group(2))) if m else None


def speech_lines(delta):
    return [line for line in delta.splitlines() if re.search(r"NPC_SAY:", line, re.I)]


def exact_target_speech(delta):
    lines = []
    for line in speech_lines(delta):
        m = re.search(r"NPC_SAY:\s*([^|:]+)\|(\d+):\s*(.*)", line, re.I)
        if not m or m.group(1).strip().casefold() != NPC.casefold() or int(m.group(2)) != int(SERIAL):
            stop("evidence", "stream contains an NPC_SAY record not bound to the exact actor")
        lines.append(m.group(3).strip())
    return lines


def exact_submission_id(delta):
    expected = None
    count = 0
    for line in delta.splitlines():
        m = re.search(r"TEST_INBOX:\s*say\s+id=(k\d+_\d+_\d+)\s+mode=\S+\s+speaker=(.*?)\s+target=(.*?)\s+text=(.*)$", line)
        if not m:
            continue
        if m.group(2).strip() == SPEAKER and m.group(3).strip() == NPC and m.group(4) == MESSAGE:
            expected = m.group(1)
            count += 1
    return expected if count == 1 else None


def flatten(obj, into):
    if isinstance(obj, dict):
        for key, value in obj.items():
            into.setdefault(str(key).casefold(), []).append(value)
            flatten(value, into)
    elif isinstance(obj, list):
        for value in obj:
            flatten(value, into)
    elif isinstance(obj, str) and obj.lstrip().startswith("{"):
        try:
            flatten(json.loads(obj), into)
        except Exception:
            pass


def json_records(text):
    decoder = json.JSONDecoder()
    for line in text.splitlines():
        for start in (i for i, char in enumerate(line) if char == "{"):
            try:
                value, _ = decoder.raw_decode(line[start:])
            except Exception:
                continue
            if isinstance(value, dict):
                yield value


def one_value(fields, keys):
    for key in keys:
        values = fields.get(key, [])
        if values:
            return values[0]
    return None


def correlated_backend_decision(raw, request_id):
    """Return the decision from a structured record bound to submitted KAH ID and the full exact chat scope."""
    for record in json_records(raw):
        fields = {}
        flatten(record, fields)
        bound = (
            (one_value(fields, ("native_request_id", "kah_request_id")) == request_id),
            (one_value(fields, ("row_id", "row")) == ROW),
            (one_value(fields, ("npc_name", "target_npc")) == NPC),
            (one_value(fields, ("speaker", "player_speaker")) == SPEAKER),
            (one_value(fields, ("player_message", "user_message")) == MESSAGE),
        )
        decision = one_value(fields, ("travel_decision",))
        if all(bound) and isinstance(decision, str) and decision.strip():
            return decision.strip().upper()
    return None


def fixture_scope_if_supplied(expected):
    path = os.environ.get("FIXTURE_SCOPE_RECEIPT", "")
    if not path:
        return None
    obj = read_json_path(path, "FIXTURE_SCOPE_RECEIPT")
    freshness(obj, "FIXTURE_SCOPE")
    for k, v in expected.items():
        if obj.get(k) != v:
            stop("setup", f"provider fixture receipt mismatch for {k}")
    if not obj.get("fixture_id") or obj.get("provider_fixture_id") != obj.get("fixture_id"):
        stop("setup", "provider fixture ID is missing or not the armed one-shot ID")
    if not re.fullmatch(r"[a-fA-F0-9]{64}", str(obj.get("fixture_sha256", ""))):
        stop("setup", "provider fixture SHA-256 is missing")
    if obj.get("review_status") != "CLEAR" or obj.get("provider_fixture_source_in_manifest") is not True:
        stop("setup", "fixture lacks exact review CLEAR/current-served-manifest source membership")
    if not re.fullmatch(r"[A-Fa-f0-9]{64}", str(obj.get("served_manifest_sha256", ""))) or not re.fullmatch(r"[A-Fa-f0-9]{64}", str(obj.get("provider_fixture_source_sha256", ""))):
        stop("setup", "fixture membership manifest/source hashes are missing")
    if obj.get("loaded_build_sha256") != read_json_env("PREFLIGHT_RECEIPT").get("build_sha256"):
        stop("setup", "fixture loaded build does not match fresh preflight build pin")
    return obj


def fixture_fired(delta, fixture, request_id):
    if not fixture:
        return True
    # Runtime log format carries the fields as one structured warning record.
    for line in delta.splitlines():
        if "STOBE_TEST_PROVIDER_REPLY fired" not in line:
            continue
        required = (ROW, str(fixture["fixture_id"]), str(fixture["fixture_sha256"]), request_id, NPC, SPEAKER)
        if all(value in line for value in required):
            return True
    return False


def main():
    global MESSAGE
    if not all((NPC, SERIAL, INDEX, SPEAKER, REGION, os.environ.get("OUT"),
                os.environ.get("NATIVE_LOG"), os.environ.get("BACKEND_LOG"))):
        stop("setup", "set exact actor/speaker/observed region, OUT, and native/backend log paths")
    rig, inst = os.environ.get("RIG"), os.environ.get("KAH_INSTANCE")
    if (rig, inst) not in (("4080", "3"), ("5090", "3")):
        stop("setup", "only isolated 4080/5090 instance 3 is allowed")
    want_game = "/c/KenshiInst/3" if rig == "4080" else "/mnt/d/KenshiInst/3"
    want_harness = r"C:\KenshiInst\3\mods\AutomationHarness" if rig == "4080" else r"D:\KenshiInst\3\mods\AutomationHarness"
    if os.environ.get("KENSHI_DIR") != want_game or os.environ.get("KAH_DIR") != want_harness:
        stop("setup", "KENSHI_DIR/KAH_DIR do not match the authorized isolated i3 route")
    if not NATIVE_LOG.is_file() or not BACKEND_LOG.is_file():
        stop("setup", "native and backend full-capture logs must already exist")
    if not re.fullmatch(r"\d+", SERIAL) or not re.fullmatch(r"\d+", INDEX):
        stop("setup", "serial/index must be decimal native handle fields")
    pre = read_json_env("PREFLIGHT_RECEIPT")
    start = read_json_env("START_DRIVER_RECEIPT")
    region = read_json_env("REGION_RECEIPT")
    model = load_model_receipt(pre)
    exact_receipt_bindings(pre, start, region, model)
    validate_start_proof(start)
    MESSAGE = (f"Would you lead me to the broad area of {REGION}? This is only a question about a possible "
               "regional plan; I am not accepting or changing our current trip.")
    fixture = fixture_scope_if_supplied({"row_id": ROW, "npc_name": NPC, "player_speaker": SPEAKER,
                                        "player_message": MESSAGE, "region_name": REGION})
    try:
        OUT.mkdir(parents=False, exist_ok=False)
    except FileExistsError:
        stop("setup", f"OUT already exists; refusing overwrite: {OUT}")
    except OSError as e:
        stop("setup", f"cannot atomically claim OUT: {e}")
    for label, receipt in (("preflight", pre), ("start-driver", start), ("observed-region", region), ("model-readiness", model)):
        (OUT / f"{label}.receipt.json").write_text(json.dumps(receipt, indent=2) + "\n", encoding="utf-8")
    (OUT / "scope.json").write_text(json.dumps({"row_id": ROW, "npc": NPC, "serial": int(SERIAL),
        "index": int(INDEX), "speaker": SPEAKER, "region": REGION, "message": MESSAGE,
        "start_endpoint": start["_endpoint_xyz"], "fixture": fixture}, indent=2) + "\n", encoding="utf-8")

    status = run(["status"], "status.before")
    if "phase=world" not in status:
        stop("setup", "KAH status is not in world phase")
    ping = run(["stobe_ping"], "ping.before")
    if not re.search(rf"\bspeaker={re.escape(SPEAKER)}\b", ping):
        stop("setup", "fresh stobe_ping speaker does not match receipt")
    where = run(["where", f"#{SERIAL}/{INDEX}"], "where.before")
    if not re.search(rf"^\s*{re.escape(NPC)}\s+#?{SERIAL}/{INDEX}\b", where, re.M):
        stop("setup", "fresh where does not resolve exact NPC/serial/index")
    _, before_ai = parse_state(run(["stobe_state", f"#{SERIAL}/{INDEX}"], "state.before"))
    validate_active_native_destination(before_ai, start["_endpoint_xyz"])

    native_offset, backend_offset = NATIVE_LOG.stat().st_size, BACKEND_LOG.stat().st_size
    (OUT / "offsets.json").write_text(json.dumps({"native": native_offset, "backend": backend_offset}), encoding="utf-8")
    send_output = run(["stobe_say", f"#{SERIAL}/{INDEX}", MESSAGE], "region-request.send", timeout=45)
    (OUT / "region-request.send.detail.txt").write_text(send_output, encoding="utf-8")
    deadline = time.monotonic() + WAIT
    native_delta = ""
    done = None
    request_id = None
    while time.monotonic() < deadline:
        native_delta = NATIVE_LOG.read_bytes()[native_offset:].decode("utf-8", "replace")
        (OUT / "native.delta.log").write_text(native_delta, encoding="utf-8")
        request_id = exact_submission_id(native_delta)
        done = complete_stream(native_delta)
        if request_id and done and len(speech_lines(native_delta)) == done[0]:
            break
        time.sleep(POLL)
    if not request_id:
        stop("evidence", "cannot bind a unique TEST_INBOX say request ID to the exact target, speaker and message")
    if not done or len(speech_lines(native_delta)) != done[0]:
        stop("evidence", "bounded wait ended before complete CHAT_THREAD stream and all queued NPC_SAY lines")
    if done[0] < 1:
        stop("evidence", "completed response contains no streamed NPC_SAY lines")
    target_lines = exact_target_speech(native_delta)
    backend_delta = BACKEND_LOG.read_bytes()[backend_offset:].decode("utf-8", "replace")
    (OUT / "backend.delta.log").write_text(backend_delta, encoding="utf-8")
    decision = correlated_backend_decision(backend_delta, request_id)
    if decision is None:
        stop("evidence", "backend does not expose one structured record binding this KAH ID, row, actor, speaker and exact message")
    if decision != "PROPOSE":
        stop("product", f"correlated backend decision was {decision}, expected PROPOSE")
    if done[1] != 0:
        stop("product", f"coarse-region request emitted {done[1]} native action lines; expected none")
    if re.search(r"ACTION_EXEC:", native_delta, re.I):
        stop("product", "native action execution appeared in the region-request delta")
    if not fixture_fired(native_delta, fixture, request_id):
        stop("evidence", "exact one-shot provider-fixture hash/scope/request receipt did not fire")
    spoken = " ".join(target_lines).casefold()
    if REGION.casefold() not in spoken:
        stop("product", "completed NPC speech does not identify the observed coarse region")
    uncertainty = re.search(r"\b(?:rough area|broad area|not sure (?:where|of) exactly|not an exact (?:place|spot)|no exact (?:place|spot)|waypoint(?: is| remains)? uncertain|uncertain waypoint|not a precise (?:place|spot))\b", spoken, re.I)
    if not uncertainty:
        stop("product", "coarse proposal speech does not disclose waypoint/location uncertainty")
    _, after_ai = parse_state(run(["stobe_state", f"#{SERIAL}/{INDEX}"], "state.after"))
    if after_ai.get("dead") is True or after_ai.get("unconscious") is True:
        stop("evidence", "actor changed life state during the row")
    (OUT / "stream.complete.txt").write_text(native_delta, encoding="utf-8")
    print(f"RESULT {ROW} PASS region={REGION!r} decision=PROPOSE action_lines=0 request={request_id} durable_trip_ledger=UNSUPPORTED active_leg_transition=UNSUPPORTED")


if __name__ == "__main__":
    try:
        main()
    except Stop as e:
        print(f"RESULT {ROW} FAIL {e.kind}: {e.why}")
        sys.exit(1)
