#!/usr/bin/env python3
"""Bounded read-only snapshot of one actor's current native movement state."""
import datetime as dt
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

ROW = os.environ.get("ROW_ID", "P0-NATIVE-STATE-SNAPSHOT-001")
NPC = os.environ.get("NPC", "")
HANDLE = os.environ.get("ACTOR_HANDLE", "")
RECEIPT = Path(os.environ.get("CURRENT_CONTEXT_RECEIPT", ""))
OUT = Path(os.environ.get("OUT", ""))
NATIVE_LOG = Path(os.environ.get("NATIVE_LOG", ""))
WAIT = float(os.environ.get("WAIT_SECONDS", "60"))
POLL = float(os.environ.get("POLL_SECONDS", "2"))
DEST_TOLERANCE = 5.0
REQUIRED_STABLE = 2


class Stop(Exception):
    def __init__(self, kind, reason):
        self.kind, self.reason = kind, reason


def stop(kind, why):
    raise Stop(kind, why)


def run(args, label, timeout=20):
    try:
        bash = os.environ.get("TRAVEL_DRIVER_BASH", "bash")
        command = shlex.join(["stobe-auto", *args])
        p = subprocess.run([bash, "-c", command], capture_output=True, text=True, timeout=timeout)
    except Exception as e:
        stop("evidence", f"{label} handler failed: {e}")
    (OUT / f"{label}.txt").write_text(p.stdout + p.stderr, encoding="utf-8")
    if p.returncode:
        stop("evidence", f"{label} handler exit={p.returncode}")
    return p.stdout.strip()


def xyz(value, field):
    try:
        point = tuple(float(v) for v in value)
        if len(point) != 3 or not all(math.isfinite(v) for v in point):
            raise ValueError("must be three finite numbers")
        return point
    except Exception as e:
        stop("setup", f"{field} invalid: {e}")


def required_text(value, field):
    if not isinstance(value, str) or not value.strip():
        stop("setup", f"{field} must be a nonempty string")
    return value


def read_context_receipt():
    if not RECEIPT.is_file():
        stop("setup", "CURRENT_CONTEXT_RECEIPT JSON is required")
    try:
        receipt = json.loads(RECEIPT.read_text(encoding="utf-8"))
        if receipt.get("schema") != 1 or receipt.get("kind") != "native-state-snapshot-context":
            raise ValueError("schema/kind mismatch")
        captured = dt.datetime.fromisoformat(str(receipt["captured_utc"]).replace("Z", "+00:00"))
        if captured.tzinfo is None:
            raise ValueError("captured_utc needs timezone")
        age = (dt.datetime.now(dt.timezone.utc) - captured.astimezone(dt.timezone.utc)).total_seconds()
        if age < -60 or age > 21600:
            raise ValueError(f"captured_utc stale or future-dated age={age:.0f}s")
        for env_key in ("EXPECTED_SAVE_ID", "EXPECTED_WORLD_ID", "EXPECTED_SESSION_GENERATION"):
            required_text(os.environ.get(env_key), env_key)
        expected_fields = {
            "rig": os.environ.get("RIG"),
            "instance": int(os.environ.get("KAH_INSTANCE", "0")),
            "kenshi_dir": os.environ.get("KENSHI_DIR"),
            "kah_dir": os.environ.get("KAH_DIR"),
            "build_sha256": os.environ.get("EXPECTED_BUILD_SHA256", "").upper(),
            "source_manifest_sha256": os.environ.get("EXPECTED_SOURCE_MANIFEST_SHA256", "").upper(),
            "save_id": os.environ.get("EXPECTED_SAVE_ID"),
            "world_id": os.environ.get("EXPECTED_WORLD_ID"),
            "session_generation": os.environ.get("EXPECTED_SESSION_GENERATION"),
            "actor_name": NPC,
            "actor_serial": int(HANDLE.split("/", 1)[0]),
            "actor_index": int(HANDLE.split("/", 1)[1]),
            "native_log_path": str(NATIVE_LOG),
        }
        for key, expected in expected_fields.items():
            actual = receipt.get(key)
            if key in ("save_id", "world_id", "session_generation"):
                required_text(expected, f"EXPECTED_{key.upper()}")
                required_text(actual, f"receipt {key}")
            if key in ("build_sha256", "source_manifest_sha256") and isinstance(actual, str):
                actual = actual.upper()
            if actual != expected:
                stop("setup", f"current context receipt mismatch for {key}: expected={expected!r} actual={actual!r}")
        if not re.fullmatch(r"[0-9A-F]{64}", str(receipt["build_sha256"]).upper()):
            stop("setup", "build_sha256 must be a full SHA-256")
        if not re.fullmatch(r"[0-9A-F]{64}", str(receipt["source_manifest_sha256"]).upper()):
            stop("setup", "source_manifest_sha256 must be a full SHA-256")
        destination = xyz(receipt["native_destination"], "receipt native_destination")
        expected_destination = xyz(os.environ.get("EXPECTED_NATIVE_DESTINATION", "").split(","), "EXPECTED_NATIVE_DESTINATION")
        if math.dist(destination, expected_destination) > 0.001:
            stop("setup", "current context receipt native destination differs from EXPECTED_NATIVE_DESTINATION")
        evidence = receipt.get("evidence_sha256")
        if not isinstance(evidence, dict):
            raise ValueError("evidence_sha256 map missing")
        paths = {
            "preflight": os.environ.get("PREFLIGHT_RECEIPT", ""),
            "build": os.environ.get("BUILD_RECEIPT", ""),
            "session": os.environ.get("SESSION_RECEIPT", ""),
            "destination": os.environ.get("DESTINATION_RECEIPT", ""),
        }
        for name, raw_path in paths.items():
            path = Path(raw_path)
            if not raw_path or not path.is_file():
                stop("setup", f"fresh {name} source receipt missing")
            digest = hashlib.sha256(path.read_bytes()).hexdigest().upper()
            if evidence.get(name) != digest:
                stop("setup", f"{name} source receipt hash differs from CURRENT_CONTEXT_RECEIPT")
        return receipt, destination
    except Stop:
        raise
    except Exception as e:
        stop("evidence", f"malformed CURRENT_CONTEXT_RECEIPT: {e}")


def parse_state(raw, serial, label):
    try:
        obj = json.loads(raw)
        ai = obj["ai"]
        if not isinstance(ai, dict) or obj.get("name") != NPC or int(obj.get("serial")) != serial:
            raise ValueError("returned actor display name or serial differs")
        dest = xyz(ai["destination"], f"{label} ai.destination")
        for key in ("moving", "destination_reached", "path_failed"):
            if not isinstance(ai.get(key), bool):
                raise ValueError(f"native ai.{key} missing or malformed")
        return {"name": obj["name"], "serial": serial, "ai": {
            "destination": dest, "moving": ai["moving"],
            "destination_reached": ai["destination_reached"], "path_failed": ai["path_failed"],
            "dead": ai.get("dead"), "unconscious": ai.get("unconscious"),
            "has_orders": ai.get("has_orders"), "has_player_orders": ai.get("has_player_orders"),
            "first_order": ai.get("first_order"), "current_goal": ai.get("current_goal")}}
    except Exception as e:
        stop("evidence", f"{label} malformed or wrong exact actor/native fields: {e}")


def main():
    if not NPC or not HANDLE or not os.environ.get("OUT") or not os.environ.get("NATIVE_LOG"):
        stop("setup", "set exact NPC, ACTOR_HANDLE=serial/index, OUT, and NATIVE_LOG")
    if not re.fullmatch(r"\d+/\d+", HANDLE):
        stop("setup", "ACTOR_HANDLE must be exact serial/index")
    rig, instance = os.environ.get("RIG"), os.environ.get("KAH_INSTANCE")
    if (rig, instance) not in (("4080", "3"), ("5090", "3")):
        stop("setup", "only isolated 4080 i3 or 5090 i3 is authorized")
    want_game = "/c/KenshiInst/3" if rig == "4080" else "/mnt/d/KenshiInst/3"
    want_harness = r"C:\KenshiInst\3\mods\AutomationHarness" if rig == "4080" else r"D:\KenshiInst\3\mods\AutomationHarness"
    if os.environ.get("KENSHI_DIR") != want_game or os.environ.get("KAH_DIR") != want_harness:
        stop("setup", "game/harness paths do not match selected isolated i3 route")
    if not NATIVE_LOG.is_file():
        stop("setup", f"native log unavailable: {NATIVE_LOG}")
    if not (0 < WAIT <= 300 and 0 < POLL <= 30):
        stop("setup", "bounded observation requires 0<WAIT_SECONDS<=300 and 0<POLL_SECONDS<=30")
    try:
        OUT.mkdir(exist_ok=False)
    except FileExistsError:
        stop("setup", f"output directory already exists; refusing to overwrite evidence: {OUT}")
    except OSError as e:
        stop("setup", f"could not atomically claim output directory {OUT}: {e}")

    context, expected_destination = read_context_receipt()
    status = run(["status"], "status.snapshot")
    if "phase=world" not in status:
        stop("setup", "game is not in world phase")
    serial, index = int(context["actor_serial"]), int(context["actor_index"])
    (OUT / "snapshot-context.json").write_text(json.dumps({
        "rig": rig, "instance": int(instance), "build_sha256": context["build_sha256"],
        "source_manifest_sha256": context["source_manifest_sha256"], "save_id": context["save_id"],
        "world_id": context["world_id"], "session_generation": context["session_generation"],
        "actor_name": NPC, "actor_serial": serial, "actor_index": index,
        "expected_native_destination": expected_destination,
        "scope": "current native state snapshot only; no prior start row or trip relation",
        "trip_relation": "UNSUPPORTED", "arrival": "UNSUPPORTED", "ledger": "UNSUPPORTED", "cleanup": "UNSUPPORTED"
    }, indent=2), encoding="utf-8")

    deadline = time.monotonic() + WAIT
    samples, stable, terminal = [], 0, None
    while time.monotonic() < deadline:
        raw = run(["stobe_state", f"#{serial}/{index}"], f"state.{len(samples)+1:03d}")
        snap = parse_state(raw, serial, f"state.{len(samples)+1:03d}")
        ai = snap["ai"]
        if math.dist(ai["destination"], expected_destination) > DEST_TOLERANCE:
            stop("evidence", "exact actor native ai.destination differs from current context snapshot")
        kind = None
        if ai["path_failed"] and not ai["moving"]:
            kind = "path_failed_flag_stationary"
        elif ai["destination_reached"] and not ai["moving"]:
            kind = "destination_reached_flag_stationary"
        if kind == terminal and kind is not None:
            stable += 1
        else:
            terminal, stable = kind, (1 if kind else 0)
        samples.append({"sample": len(samples) + 1, "monotonic_s": round(time.monotonic(), 3), **snap})
        (OUT / "samples.json").write_text(json.dumps(samples, indent=2), encoding="utf-8")
        if stable >= REQUIRED_STABLE:
            break
        time.sleep(POLL)
    else:
        stop("evidence", f"no repeated native terminal state in bounded {WAIT:g}s snapshot")

    (OUT / "observer-result.json").write_text(json.dumps({
        "native_state_observed": terminal, "consecutive_samples": stable,
        "destination_match_tolerance_m": DEST_TOLERANCE,
        "snapshot_only": True, "trip_relation": "UNSUPPORTED", "arrival": "UNSUPPORTED",
        "durable_trip_ledger": "UNSUPPORTED", "owned_order_cleanup": "UNSUPPORTED",
        "no_proximity_inference": True, "no_mutating_handler_called": True
    }, indent=2), encoding="utf-8")
    print(f"RESULT {ROW} PASS-SNAPSHOT actor={NPC}#{serial}/{index} native_state={terminal} stable_samples={stable} trip_relation=UNSUPPORTED arrival=UNSUPPORTED ledger=UNSUPPORTED cleanup=UNSUPPORTED")


if __name__ == "__main__":
    try:
        main()
    except Stop as e:
        print(f"RESULT {ROW} FAIL {e.kind}: {e.reason}")
        sys.exit(2 if e.kind == "setup" else 3)
