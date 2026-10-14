#!/usr/bin/env python3
"""Mocked-handler checks for the changed-plan row; does not connect to a rig."""
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import tempfile
from unittest.mock import patch

HERE = Path(__file__).resolve().parent
SPEC = importlib.util.spec_from_file_location("changed_plan", HERE / "changed-plan.py")
MOD = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MOD)


def case(mode):
    with tempfile.TemporaryDirectory(prefix="changed-plan-mock-") as td:
        root = Path(td)
        out, active = root / "out", root / "active"
        active.mkdir()
        (active / "endpoint.json").write_text(json.dumps({"destination": "Heft", "xyz": [10, 0, 0]}))
        (active / "progress.json").write_text(json.dumps([{"eligible": True}]))
        (active / "state.final.txt").write_text(json.dumps({"name": "Cind [Hungry Bandit]", "serial": 123,
            "ai": {"destination": [10, 0, 0], "moving": True, "destination_reached": False, "path_failed": False}}))
        prior_actor = "Other NPC" if mode == "prior_wrong_actor" else "Cind [Hungry Bandit]"
        prior_dest = "Heftside" if mode == "prior_wrong_dest" else "Heft"
        (active / "accept.native.delta.log").write_text(
            f"ACTION_EXEC: TRAVEL_LOCATION actor={prior_actor} destination='{prior_dest}' x=10 y=0 z=0 serial=123 hold_cleared=1\n")
        preflight = root / "preflight.txt"
        native_log_id = "/mnt/d/KenshiInst/3/RE_Kenshi/mods/Stobe/stobe.log"
        active_id = str(active)
        session_value = "different-session" if mode == "bad_session_binding" else "sess-9"
        def binding_lines():
            return (f"build_sha=abc\nsave_id=copied-1\nsession_id={session_value}\nrig=5090\n" \
                    f"kah_instance=3\nnative_log={native_log_id}\nactive_travel_out={active_id}\n" \
                    "actor=Cind [Hungry Bandit]\nserial=123\n")
        preflight.write_text("build save session private backend input isolation PASS inbox clear\n" + binding_lines())
        active_receipt = root / "active-start.txt"
        active_receipt.write_text(binding_lines())
        receipts = {}
        for name, key, value in (("build", "build_sha", "abc"), ("save", "save_id", "copied-1"),
                                 ("session", "session_id", "sess-9")):
            receipts[name] = root / f"{name}.txt"
            receipts[name].write_text(f"{key}={value}\n")
        log = root / "native.log"
        log.write_text("existing log\n")
        npc = "Cind [Hungry Bandit]"
        env = {"ROW_ID": "MOCK-CHANGED", "NPC": npc, "ACTIVE_DESTINATION": "Heft", "NEW_DESTINATION": "Stack",
               "OUT": str(out), "NATIVE_LOG": native_log_id, "ACTIVE_TRAVEL_OUT": str(active), "PREFLIGHT_RECEIPT": str(preflight),
               "BUILD_RECEIPT": str(receipts["build"]), "SAVE_RECEIPT": str(receipts["save"]),
               "SESSION_RECEIPT": str(receipts["session"]), "ACTIVE_START_RECEIPT": str(active_receipt),
               "BUILD_SHA": "abc", "SAVE_ID": "copied-1", "SESSION_ID": "sess-9",
               "RIG": "5090", "KAH_INSTANCE": "3", "KENSHI_DIR": "/mnt/d/KenshiInst/3",
               "KAH_DIR": r"D:\KenshiInst\3\mods\AutomationHarness", "WAIT_SECONDS": "1", "POLL_SECONDS": "0.001",
               "SETTLE_SECONDS": "0.02"}
        with patch.dict(os.environ, env, clear=False):
            MOD.ROW, MOD.NPC, MOD.OLD, MOD.NEW = env["ROW_ID"], npc, "Heft", "Stack"
            MOD.OUT, MOD.LOG, MOD.LOG_ID, MOD.ACTIVE_OUT, MOD.PREFLIGHT = out, log, native_log_id, active, preflight
            MOD.BUILD_RECEIPT, MOD.SAVE_RECEIPT, MOD.SESSION_RECEIPT = receipts["build"], receipts["save"], receipts["session"]
            MOD.ACTIVE_START_RECEIPT = active_receipt
            MOD.WAIT, MOD.POLL, MOD.TOL = 1, 0.001, 5.0

            def handler(argv, **kwargs):
                cmd = argv[-1].split()
                if cmd[:2] == ["stobe-auto", "where"]:
                    return subprocess.CompletedProcess(argv, 0, f"{npc} #123/2 pos=0,0,0 dist=4\n", "")
                if cmd[:2] == ["stobe-auto", "stobe_state"]:
                    changed = mode.startswith("accept") and bool(list(out.glob("state.observe.*")))
                    d = [30, 0, 0] if changed and mode == "accept_mismatch" else ([20, 0, 0] if changed else [10, 0, 0])
                    body = {"name": npc, "serial": 123, "ai": {"destination": d, "moving": True,
                            "destination_reached": False, "path_failed": False}}
                    return subprocess.CompletedProcess(argv, 0, json.dumps(body), "")
                if cmd[:2] == ["stobe-auto", "stobe_say"]:
                    if mode.startswith("refuse"):
                        say = ("I can not change the trip to Stack; we will continue to Heft."
                               if mode == "refuse_can_not" else "I cannot change the trip to Stack; we will continue to Heft.")
                    elif mode == "conditional":
                        say = "I could change the trip and take you to Stack."
                    else:
                        say = "I will change the trip and take you to Stack."
                    addition = f"CHAT_THREAD: Queued 1 streamed chat lines and 0 action lines.\nNPC_SAY: {npc}|123: {say}\n"
                    if mode in ("refuse_dispatch", "accept", "accept_duplicate", "accept_mismatch", "accept_wrong_actor", "accept_wrong_dest"):
                        action_actor = "Other NPC" if mode == "accept_wrong_actor" else npc
                        action_dest = "Stackside" if mode == "accept_wrong_dest" else "Stack"
                        addition += f"ACTION_EXEC: TRAVEL_LOCATION actor={action_actor} destination='{action_dest}' x=20 y=0 z=0 serial=123\n"
                    if mode == "accept_duplicate":
                        addition += "ACTION_EXEC: TRAVEL_LOCATION actor=Cind destination='Stack' x=20 y=0 z=0 serial=123\n"
                    with log.open("a", encoding="utf-8") as f:
                        f.write(addition)
                    return subprocess.CompletedProcess(argv, 0, "sent\n", "")
                raise AssertionError(f"unexpected handler command: {cmd}")

            with patch.object(MOD.subprocess, "run", side_effect=handler):
                try:
                    MOD.main()
                    return "PASS"
                except MOD.Stop as exc:
                    return f"FAIL-{exc.kind}"


assert case("refuse") == "PASS", "truthful refusal preserving the active trip should pass"
assert case("refuse_dispatch") == "FAIL-product", "refusal plus replacement dispatch must be rejected"
assert case("accept") == "PASS", "one explicit accepted replacement must pass"
assert case("accept_duplicate") == "FAIL-product", "duplicate changed-plan dispatch must be rejected"
assert case("accept_mismatch") == "FAIL-product", "native destination not matching action XYZ must be rejected"
assert case("conditional") == "FAIL-evidence", "conditional language must not be counted as acceptance"
assert case("refuse_can_not") == "PASS", "negated 'I can not' must be classified as refusal"
assert case("prior_wrong_actor") == "FAIL-setup", "prior start from another actor must be rejected"
assert case("prior_wrong_dest") == "FAIL-setup", "prior start for another destination must be rejected"
assert case("accept_wrong_actor") == "FAIL-product", "changed action for wrong display name must be rejected"
assert case("accept_wrong_dest") == "FAIL-product", "changed action for wrong exact destination label must be rejected"
assert case("bad_session_binding") == "FAIL-setup", "preflight with wrong session binding must be rejected"
print("SELFTEST PASS mocked_cases=12 refusal_preserves_original=1 unauthorized_refusal_dispatch_rejected=1 accepted_single_dispatch=1 duplicate_dispatch_rejected=1 action_xyz_mismatch_rejected=1 conditional_acceptance_rejected=1 negated_acceptance_refusal=1 prior_actor_and_destination_exact=2 changed_actor_and_destination_exact=2 session_path_binding_rejected=1")
