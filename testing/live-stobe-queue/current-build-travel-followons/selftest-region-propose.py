#!/usr/bin/env python3
"""Mocked-handler regressions for the coarse-region proposal row; no rig calls."""
import contextlib
import importlib.util
import io
import json
import os
from pathlib import Path
import subprocess
import tempfile
import time

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("region_propose", HERE / "region-propose.py")
driver = importlib.util.module_from_spec(spec)
spec.loader.exec_module(driver)
REAL_SUBPROCESS_RUN = subprocess.run

checks = 0
def check(name, cond):
    global checks
    checks += 1
    if not cond:
        raise AssertionError(name)


def write_json(path, obj):
    path.write_text(json.dumps(obj, separators=(",", ":")) + "\n", encoding="utf-8")


def case(root, name, mutate=None, preexisting=False, fixture_mode=False):
    case_dir = root / name
    case_dir.mkdir()
    native = case_dir / "native.log"
    backend = case_dir / "backend.log"
    native.write_text("baseline\n", encoding="utf-8")
    backend.write_text("baseline\n", encoding="utf-8")
    out = case_dir / "row-out"
    if preexisting:
        out.mkdir()
    now = int(time.time())
    common = {"rig":"4080", "instance":"3", "npc_name":"Test Actor [Outlaw]", "npc_serial":1234,
              "npc_index":2, "player_speaker":"Shay", "save_id":"copy-a", "session_generation":"gen-1",
              "build_sha256":"b" * 64}
    # Start-driver proof files mirror its stable output names and correlated native event.
    start_out = case_dir / "start-driver-out"
    start_out.mkdir()
    endpoint = {"destination":"Squin", "xyz":[100.0, 200.0, 300.0]}
    write_json(start_out / "endpoint.json", endpoint)
    write_json(start_out / "progress.json", [{"position":[105,200,300],"eligible":True}])
    action = "ACTION_EXEC: TRAVEL_LOCATION actor=Test Actor serial=1234 destination='Squin' x=100 y=200 z=300 hold_cleared=1 passive_cleared=1"
    (start_out / "accept.native.delta.log").write_text("TEST_INBOX: say id=k1699999999999_1_1 mode=chat speaker=Shay target=Test Actor [Outlaw] text=accept\n" + action + "\n", encoding="utf-8")
    start_result = case_dir / "start-result.txt"
    start_result.write_text("RESULT P0-TRAVEL-START-MOVE-001 PASS-START-MOVE actor=Test Actor [Outlaw]#1234/2 destination=Squin\n", encoding="utf-8")
    model_receipt_path = case_dir / "model-readiness.json"
    model = dict(common, captured_utc=now, review_status="CLEAR", model_status="READY", request_id="model-ready-9")
    write_json(model_receipt_path, model)
    pre = dict(common, captured_utc=now, phase="world", paused=False, input_isolation="ON",
               native_log=str(native), backend_log=str(backend),
               model_readiness_receipt_path=str(model_receipt_path),
               model_readiness_receipt_sha256=driver.sha256(model_receipt_path))
    start = dict(common, captured_utc=now, row_id=driver.START_ROW, result="PASS-START-MOVE",
                 driver_sha256=driver.START_DRIVER_SHA256, out_dir=str(start_out), result_file=str(start_result),
                 result_file_sha256=driver.sha256(start_result),
                 accept_native_delta_sha256=driver.sha256(start_out / "accept.native.delta.log"),
                 endpoint_json_sha256=driver.sha256(start_out / "endpoint.json"),
                 progress_json_sha256=driver.sha256(start_out / "progress.json"),
                 durable_trip_ledger="UNSUPPORTED")
    region = dict(common, captured_utc=now, region_name="The Hub", region_source="native location receipt:zone-map")
    files = {}
    for key, data in (("PREFLIGHT_RECEIPT", pre), ("START_DRIVER_RECEIPT", start), ("REGION_RECEIPT", region)):
        path = case_dir / f"{key}.json"
        write_json(path, data)
        files[key] = path
    message = f"Would you lead me to the broad area of The Hub? This is only a question about a possible regional plan; I am not accepting or changing our current trip."
    fixture = None
    if fixture_mode:
        fixture = dict(common, captured_utc=now, row_id=driver.ROW, npc_name=common["npc_name"],
                       player_speaker="Shay", player_message=message, region_name="The Hub",
                       fixture_id="region-fixture-1", provider_fixture_id="region-fixture-1",
                       fixture_sha256="f" * 64, review_status="CLEAR", provider_fixture_source_in_manifest=True,
                       served_manifest_sha256="c" * 64, provider_fixture_source_sha256="d" * 64,
                       loaded_build_sha256=common["build_sha256"])
        path = case_dir / "fixture-scope.json"
        write_json(path, fixture)
        files["FIXTURE_SCOPE_RECEIPT"] = path
    if mutate:
        mutate(pre, start, region, model, fixture)
        write_json(files["PREFLIGHT_RECEIPT"], pre)
        write_json(files["START_DRIVER_RECEIPT"], start)
        write_json(files["REGION_RECEIPT"], region)
        write_json(model_receipt_path, model)
        pre["model_readiness_receipt_sha256"] = driver.sha256(model_receipt_path)
        write_json(files["PREFLIGHT_RECEIPT"], pre)
        if fixture:
            write_json(files["FIXTURE_SCOPE_RECEIPT"], fixture)

    env = {"RIG":"4080", "KAH_INSTANCE":"3", "KENSHI_DIR":"/c/KenshiInst/3",
           "KAH_DIR":r"C:\KenshiInst\3\mods\AutomationHarness", "NPC":common["npc_name"],
           "NPC_SERIAL":"1234", "NPC_INDEX":"2", "PLAYER_SPEAKER":"Shay", "OBSERVED_REGION":"The Hub",
           "OUT":str(out), "NATIVE_LOG":str(native), "BACKEND_LOG":str(backend),
           "WAIT_SECONDS":"1", "POLL_SECONDS":"0.001", "TRAVEL_DRIVER_BASH":"bash",
           **{key: str(path) for key, path in files.items()}}
    old = {k: os.environ.get(k) for k in set(env) | {"FIXTURE_SCOPE_RECEIPT"}}
    os.environ.update(env)
    if not fixture_mode:
        os.environ.pop("FIXTURE_SCOPE_RECEIPT", None)
    driver.NPC, driver.SERIAL, driver.INDEX = env["NPC"], env["NPC_SERIAL"], env["NPC_INDEX"]
    driver.SPEAKER, driver.REGION = env["PLAYER_SPEAKER"], env["OBSERVED_REGION"]
    driver.OUT, driver.NATIVE_LOG, driver.BACKEND_LOG = out, native, backend
    driver.WAIT, driver.POLL, driver.MAX_AGE = 1, 0.001, 600
    calls = []
    behavior = {"extra":"", "decision":"PROPOSE", "scope":True, "stream":True, "fixture_fire":True}
    if name == "native-action": behavior["extra"] = "ACTION_EXEC: TRAVEL_LOCATION actor=Test Actor serial=1234\n"
    if name == "wrong-decision": behavior["decision"] = "NONE"
    if name == "unrelated-request": behavior["request_id"] = "k1700000000000_99_1"
    if name == "missing-scope": behavior["scope"] = False
    if name == "incomplete-stream": behavior["stream"] = False
    if name == "fixture-no-fire": behavior["fixture_fire"] = False

    def fake_run(argv, **kwargs):
        command = argv[-1]
        parts = command.split()
        calls.append(parts)
        if "status" in parts:
            stdout = "phase=world paused=0 speed=1"
        elif "stobe_ping" in parts:
            stdout = "mode=chat speaker=Shay nearest=Test Actor"
        elif "where" in parts:
            stdout = "Test Actor [Outlaw] #1234/2 pos=1,2,3 dist=10"
        elif "stobe_state" in parts:
            stdout = json.dumps({"name":common["npc_name"], "serial":1234, "ai":{"dead":False,"unconscious":False,
                "moving":True,"destination_reached":False,"path_failed":False,"destination":[100.0,200.0,300.0]}})
        elif "stobe_say" in parts:
            request_id = "k1700000000000_42_1"
            text = driver.MESSAGE
            line = f"TEST_INBOX: say id={request_id} mode=chat speaker=Shay target={common['npc_name']} text={text}\n"
            if behavior["stream"]:
                line += (f"NPC_SAY: {common['npc_name']}|1234: I can take you to The Hub as a rough area; the exact waypoint is uncertain.\n" +
                         "CHAT_THREAD: Queued 1 streamed chat lines and 0 action lines.\n")
            if fixture and behavior["fixture_fire"]:
                line += (f"STOBE_TEST_PROVIDER_REPLY fired row={driver.ROW} fixture_id={fixture['fixture_id']} "
                         f"fixture_sha256={fixture['fixture_sha256']} request_id={request_id} "
                         f"npc={common['npc_name']} speaker=Shay\n")
            native.write_text(native.read_text(encoding="utf-8") + line + behavior["extra"], encoding="utf-8")
            bound_id = behavior.get("request_id", request_id)
            record = {"native_request_id":bound_id, "travel_decision":behavior["decision"]}
            if behavior["scope"]:
                record.update({"row_id":driver.ROW,"npc_name":common["npc_name"],"speaker":"Shay","player_message":text})
            backend.write_text(backend.read_text(encoding="utf-8") + json.dumps(record) + "\n", encoding="utf-8")
            stdout = f"target={common['npc_name']} serial=1234/2 mode=chat"
        else:
            raise AssertionError("unexpected mocked KAH handler: " + command)
        return subprocess.CompletedProcess(argv, 0, stdout, "")

    driver.subprocess.run = fake_run
    output = io.StringIO()
    try:
        with contextlib.redirect_stdout(output):
            try:
                driver.main()
            except driver.Stop as e:
                print(f"RESULT {driver.ROW} FAIL {e.kind}: {e.why}")
    finally:
        driver.subprocess.run = REAL_SUBPROCESS_RUN
        for k, value in old.items():
            if value is None: os.environ.pop(k, None)
            else: os.environ[k] = value
    return output.getvalue(), calls


with tempfile.TemporaryDirectory(prefix="region-propose-selftest-") as tmp:
    root = Path(tmp)
    output, calls = case(root, "live-pass")
    check("scoped proposal/no native dispatch passes", "RESULT P0-TRAVEL-REGION-PROPOSE-001 PASS" in output and "action_lines=0" in output)
    check("exactly one ordinary chat request", sum("stobe_say" in c for c in calls) == 1)
    output, calls = case(root, "existing-out", preexisting=True)
    check("existing output rejected before any KAH call", "FAIL setup" in output and not calls)
    output, calls = case(root, "missing-start", lambda pre, start, region, model, fixture: start.update(result="FAIL"))
    check("nonpassing frozen start receipt rejected before handlers", "FAIL setup" in output and not calls)
    output, calls = case(root, "stale-model", lambda pre, start, region, model, fixture: model.update(captured_utc=1))
    check("stale model receipt rejected before handlers", "FAIL setup" in output and not calls)
    output, calls = case(root, "native-action", lambda *x: None)
    check("native action is product failure", "FAIL product" in output and "action execution" in output)
    output, calls = case(root, "wrong-decision")
    check("correlated wrong decision is product failure", "FAIL product" in output and "decision was NONE" in output)
    output, calls = case(root, "unrelated-request")
    check("unrelated backend request cannot correlate", "FAIL evidence" in output and "structured record" in output)
    output, calls = case(root, "missing-scope")
    check("backend response without row/actor/message scope fails evidence", "FAIL evidence" in output and "structured record" in output)
    output, calls = case(root, "incomplete-stream")
    check("incomplete stream fails evidence", "FAIL evidence" in output and "complete CHAT_THREAD" in output)
    output, calls = case(root, "fixture-pass", fixture_mode=True)
    check("exact reviewed one-shot fixture firing passes", "RESULT P0-TRAVEL-REGION-PROPOSE-001 PASS" in output)
    output, calls = case(root, "fixture-mismatch", lambda pre, start, region, model, fixture: fixture.update(player_message="wrong"), fixture_mode=True)
    check("fixture exact-message mismatch fails before chat", "FAIL setup" in output and not calls)
    output, calls = case(root, "fixture-no-fire", fixture_mode=True)
    check("fixture without exact firing receipt fails evidence", "FAIL evidence" in output and "one-shot provider-fixture" in output)

print(f"SELFTEST PASS mocked_cases={checks} row={driver.ROW}")
