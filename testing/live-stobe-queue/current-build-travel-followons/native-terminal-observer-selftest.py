#!/usr/bin/env python3
"""Deterministic mocked-handler and context-pin tests for the native snapshot row."""
import contextlib
import hashlib
import importlib.util
import io
import json
import os
from pathlib import Path
import tempfile
from unittest.mock import patch
from datetime import datetime, timezone

HERE = Path(__file__).resolve().parent
SPEC = importlib.util.spec_from_file_location("native_snapshot", HERE / "native-terminal-observer.py")
OBSERVER = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(OBSERVER)
BASE = {
    "RIG": "5090", "KAH_INSTANCE": "3", "KENSHI_DIR": "/mnt/d/KenshiInst/3",
    "KAH_DIR": r"D:\KenshiInst\3\mods\AutomationHarness", "NPC": "Cind [Hungry Bandit]",
    "ACTOR_HANDLE": "123456/2", "EXPECTED_BUILD_SHA256": "A" * 64,
    "EXPECTED_SOURCE_MANIFEST_SHA256": "B" * 64, "EXPECTED_SAVE_ID": "copied-save-17",
    "EXPECTED_WORLD_ID": "world-99", "EXPECTED_SESSION_GENERATION": "session-gen-8",
    "EXPECTED_NATIVE_DESTINATION": "100,0,0", "WAIT_SECONDS": "0.05", "POLL_SECONDS": "0.01"
}


def case(mode="arrival", mismatch=None, wrong_serial=False, live_destination=None, occupied=False):
    with tempfile.TemporaryDirectory(prefix="native-snapshot-mock-", dir=HERE) as td:
        root = Path(td)
        receipts = {}
        for key in ("PREFLIGHT_RECEIPT", "BUILD_RECEIPT", "SESSION_RECEIPT", "DESTINATION_RECEIPT"):
            p = root / f"{key}.md"
            p.write_text(f"fixture {key}\n", encoding="utf-8")
            receipts[key] = str(p)
        native_log = root / "stobe.log"
        native_log.write_text("fixture native log\n", encoding="utf-8")
        context = {
            "schema": 1, "kind": "native-state-snapshot-context",
            "captured_utc": datetime.now(timezone.utc).isoformat(),
            "rig": "5090", "instance": 3, "kenshi_dir": "/mnt/d/KenshiInst/3",
            "kah_dir": r"D:\KenshiInst\3\mods\AutomationHarness",
            "build_sha256": "A" * 64, "source_manifest_sha256": "B" * 64,
            "save_id": "copied-save-17", "world_id": "world-99", "session_generation": "session-gen-8",
            "actor_name": "Cind [Hungry Bandit]", "actor_serial": 123456, "actor_index": 2,
            "native_destination": [100, 0, 0], "native_log_path": str(native_log),
            "evidence_sha256": {name: hashlib.sha256(Path(path).read_bytes()).hexdigest().upper()
                                for name, path in (("preflight", receipts["PREFLIGHT_RECEIPT"]),
                                                   ("build", receipts["BUILD_RECEIPT"]),
                                                   ("session", receipts["SESSION_RECEIPT"]),
                                                   ("destination", receipts["DESTINATION_RECEIPT"]))}
        }
        if mismatch == "receipt_rig": context["rig"] = "4080"
        if mismatch == "receipt_instance": context["instance"] = 2
        if mismatch == "receipt_build": context["build_sha256"] = "C" * 64
        if mismatch == "receipt_save": context["save_id"] = "other-save"
        if mismatch == "receipt_save_null": context["save_id"] = None
        if mismatch == "receipt_world": context["world_id"] = "other-world"
        if mismatch == "receipt_world_null": context["world_id"] = None
        if mismatch == "receipt_session": context["session_generation"] = "other-session"
        if mismatch == "receipt_session_null": context["session_generation"] = None
        if mismatch == "receipt_actor": context["actor_serial"] = 777
        if mismatch == "receipt_destination": context["native_destination"] = [999, 0, 0]
        receipt_path = root / "current-context.json"
        receipt_path.write_text(json.dumps(context), encoding="utf-8")
        out = root / "out"
        if occupied:
            out.mkdir()
        env = {**BASE, **receipts, "CURRENT_CONTEXT_RECEIPT": str(receipt_path),
               "NATIVE_LOG": str(native_log), "OUT": str(out)}
        state_serial = 999 if wrong_serial else 123456
        reached, failed, moving, x = {"arrival": (True, False, False, 100),
            "pathfail": (False, True, False, 100), "stationary": (False, False, False, 100)}[mode]
        if live_destination is not None:
            x = live_destination
        state_json = json.dumps({"name": "Cind [Hungry Bandit]", "serial": state_serial,
            "ai": {"moving": moving, "destination_reached": reached, "path_failed": failed,
                   "destination": [x, 0, 0], "has_orders": False, "has_player_orders": False}})
        calls = []

        def mock_run(args, label, timeout=20):
            calls.append(tuple(args))
            content = "phase=world paused=0 speed=1.0" if args == ["status"] else state_json
            (OBSERVER.OUT / f"{label}.txt").write_text(content + "\n", encoding="utf-8")
            return content

        overrides = dict(env)
        if mismatch == "expected_build": overrides["EXPECTED_BUILD_SHA256"] = "D" * 64
        if mismatch == "expected_save": overrides["EXPECTED_SAVE_ID"] = "other-save"
        if mismatch == "expected_save_missing": overrides.pop("EXPECTED_SAVE_ID")
        if mismatch == "expected_world": overrides["EXPECTED_WORLD_ID"] = "other-world"
        if mismatch == "expected_world_missing": overrides.pop("EXPECTED_WORLD_ID")
        if mismatch == "expected_session": overrides["EXPECTED_SESSION_GENERATION"] = "other-session"
        if mismatch == "expected_session_missing": overrides.pop("EXPECTED_SESSION_GENERATION")
        if mismatch == "expected_destination": overrides["EXPECTED_NATIVE_DESTINATION"] = "200,0,0"
        tick = [0.0]
        def monotonic():
            value = tick[0]
            tick[0] += 0.01
            return value

        OBSERVER.NPC = env["NPC"]
        OBSERVER.HANDLE = env["ACTOR_HANDLE"]
        OBSERVER.RECEIPT = Path(env["CURRENT_CONTEXT_RECEIPT"])
        OBSERVER.OUT = Path(env["OUT"])
        OBSERVER.NATIVE_LOG = Path(env["NATIVE_LOG"])
        OBSERVER.WAIT = float(env["WAIT_SECONDS"])
        OBSERVER.POLL = float(env["POLL_SECONDS"])
        output = io.StringIO()
        with patch.dict(os.environ, overrides, clear=False), patch.object(OBSERVER, "run", mock_run), \
                patch.object(OBSERVER.time, "monotonic", monotonic), patch.object(OBSERVER.time, "sleep", lambda _: None), \
                contextlib.redirect_stdout(output):
            try:
                OBSERVER.main()
                code = 0
            except OBSERVER.Stop as e:
                print(f"RESULT {OBSERVER.ROW} FAIL {e.kind}: {e.reason}")
                code = 2 if e.kind == "setup" else 3
        saved = json.loads((out / "observer-result.json").read_text(encoding="utf-8")) if (out / "observer-result.json").is_file() else None
        return code, output.getvalue(), saved, calls


def main():
    code, output, result, calls = case("arrival")
    assert code == 0 and "PASS-SNAPSHOT" in output and "trip_relation=UNSUPPORTED" in output, output
    assert all(marker in output for marker in ("arrival=UNSUPPORTED", "ledger=UNSUPPORTED", "cleanup=UNSUPPORTED")), output
    assert result["snapshot_only"] and result["trip_relation"] == "UNSUPPORTED"
    assert len(calls) == 3 and calls[0] == ("status",) and all(c[0] == "stobe_state" for c in calls[1:])

    code, output, _, _ = case("pathfail")
    assert code == 0 and "path_failed_flag_stationary" in output, output
    code, output, _, _ = case("stationary")
    assert code == 3 and "no repeated native terminal state" in output, output
    code, output, _, _ = case("arrival", wrong_serial=True)
    assert code == 3 and "returned actor display name or serial differs" in output, output
    code, output, _, _ = case("arrival", live_destination=999)
    assert code == 3 and "ai.destination differs from current context snapshot" in output, output
    for mismatch in ("receipt_rig", "receipt_instance", "receipt_build", "receipt_save", "receipt_save_null",
                     "receipt_world", "receipt_world_null", "receipt_session", "receipt_session_null", "receipt_actor", "receipt_destination",
                     "expected_build", "expected_save", "expected_save_missing", "expected_world", "expected_world_missing",
                     "expected_session", "expected_session_missing", "expected_destination"):
        code, output, _, _ = case("arrival", mismatch=mismatch)
        assert code in (2, 3) and any(marker in output for marker in ("mismatch", "differs", "nonempty")), f"{mismatch}: {output}"
    code, output, _, calls = case("arrival", occupied=True)
    assert code == 2 and "output directory already exists" in output and not calls, output
    print("SELFTEST PASS mocked_cases=25 deterministic_clock=1 snapshot_only=1 mismatched_rig_instance_build_save_world_session_actor_destination_and_missing_pins=rejected trip_relation=UNSUPPORTED")


if __name__ == "__main__":
    main()
