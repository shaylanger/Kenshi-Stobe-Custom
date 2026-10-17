"""One-shot no-inference check of the integrated private benchmark profile."""
from __future__ import annotations

import http.server
import json
import os
import shutil
import subprocess
import sys
import tempfile
import threading
import time
from datetime import datetime, timezone
from pathlib import Path
from http.server import BaseHTTPRequestHandler

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import codex_bench as bench
import codex_hostprobe


class StubState:
    def __init__(self) -> None:
        self.first_request_utc = None
        self.request_count = 0


class ProviderHandler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def do_POST(self) -> None:
        self.rfile.read(int(self.headers.get("Content-Length", "0")))
        state = self.server.state
        if state.first_request_utc is None:
            state.first_request_utc = datetime.now(timezone.utc).isoformat()
        state.request_count += 1
        body = codex_hostprobe._sse_final("resp-integrated-zero-tool")
        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream")
        self.send_header("Connection", "close")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)
        self.wfile.flush()

    def log_message(self, *_args) -> None:
        return


def run() -> dict:
    cli = Path(os.environ.get("CODEX_BENCH_CLI", str(bench.DEFAULT_CODEX)))
    if not cli.is_file():
        raise RuntimeError("installed pinned CLI not found")
    server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), ProviderHandler)
    state = StubState()
    server.state = state
    worker = threading.Thread(target=server.serve_forever, daemon=True)
    worker.start()
    temp = Path(tempfile.mkdtemp(prefix="codex-zero-tool-startup-integrated-"))
    final = {}
    try:
        run_dir = temp / "suite" / "runs" / "offline-probe"
        attempt = run_dir / "attempt-01"
        attempt.mkdir(parents=True)
        cell = {"model": "gpt-6-astra", "effort": "low", "speed": "standard"}
        codex_home, config = bench._make_config(run_dir, "offline-probe", cell,
                                                private_base=temp / "profiles")
        config_path = codex_home / "config.toml"
        text = config_path.read_text(encoding="utf-8")
        provider = (f'[model_providers.offline_probe]\n'
                    f'name = "Offline loopback test"\nbase_url = "http://127.0.0.1:{server.server_address[1]}/v1"\n'
                    'wire_api = "responses"\nenv_key = "OPENAI_API_KEY"\n\n')
        config_path.write_text('model_provider = "offline_probe"\n' +
                               text.replace("[features]", provider + "[features]", 1), encoding="utf-8")
        config["private_config_sha256"] = bench._sha(config_path.read_bytes())
        call_path = attempt / "frozen-mcp-receipts.jsonl"
        startup_path = attempt / "frozen-mcp-startup.jsonl"
        call_path.touch(exist_ok=False)
        startup_path.touch(exist_ok=False)
        nonce = os.urandom(32).hex()
        home = codex_home.parent
        env = bench._private_env(home, {
            "CODEX_HOME": str(codex_home), "OPENAI_API_KEY": "loopback-only-dummy-key",
            "CODEX_FROZEN_ROOT": str(temp / "frozen-unused"),
            "CODEX_FROZEN_RECEIPTS": str(call_path),
            "CODEX_BENCH_EXEC_NONCE": nonce,
            "CODEX_BENCH_ATTEMPT_ID": "offline-probe/attempt-01",
            "CODEX_BENCH_CONFIG_PATH": str(config_path),
        })
        started_utc = datetime.now(timezone.utc).isoformat()
        argv = [str(cli), "--dangerously-bypass-hook-trust", "exec", "--json", "--strict-config",
                "--sandbox", "read-only", "--cd", str(home / "neutral-cwd"),
                "--skip-git-repo-check", "--model", cell["model"], "--config",
                f"model_reasoning_effort={cell['effort']}", "--config", "service_tier=default", "-"]
        proc = subprocess.Popen(argv, cwd=home / "neutral-cwd", env=env,
                                stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        identity = bench._process_identity(proc.pid)
        event_path = attempt / "events.jsonl"
        stdin_pipe_error = None
        try:
            try:
                proc.stdin.write(b"Return the fixed loopback completion in one sentence.\n")
                proc.stdin.close()
            except OSError as exc:
                stdin_pipe_error = type(exc).__name__
                try:
                    proc.stdin.close()
                except OSError:
                    pass
            with event_path.open("w", encoding="utf-8") as event_log:
                for raw in proc.stdout:
                    try:
                        event = json.loads(raw)
                    except json.JSONDecodeError:
                        event_log.write("not-json\n")
                        continue
                    if not isinstance(event, dict):
                        event_log.write("null\n")
                        continue
                    safe = {key: event.get(key) for key in ("type", "thread_id", "turn_id") if key in event}
                    payload = event.get("payload")
                    if isinstance(payload, dict):
                        safe_payload = {key: payload.get(key) for key in ("type", "thread_id", "turn_id", "id") if key in payload}
                        item = payload.get("item")
                        if isinstance(item, dict):
                            safe_payload["item"] = {key: item.get(key) for key in
                                                     ("type", "server", "server_name", "name", "tool_name") if key in item}
                        safe["payload"] = safe_payload
                    item = event.get("item")
                    if isinstance(item, dict):
                        safe["item"] = {key: item.get(key) for key in
                                         ("type", "server", "server_name", "name", "tool_name") if key in item}
                    event_log.write(json.dumps(safe) + "\n")
            rc = proc.wait(timeout=10)
        except subprocess.TimeoutExpired:
            proc.kill(); proc.wait()
            rc = "TIMEOUT"
        error_bytes = proc.stderr.read(4096) if proc.stderr else b""
        error_text = error_bytes.decode("utf-8", errors="replace").casefold()
        stderr_diagnostics = [line.strip()[:220] for line in error_bytes.decode("utf-8", errors="replace").splitlines()
                              if any(word in line.casefold() for word in ("error", "invalid", "provider", "failed"))][:2]
        safe_error_codes = [label for needle, label in (
            ("invalid config", "invalid-config"), ("unknown field", "unknown-config-field"),
            ("api key", "auth-config"), ("provider", "provider-config"),
            ("not found", "resource-not-found"), ("connection refused", "loopback-connection-refused"),
            ("failed", "cli-failed")) if needle in error_text]
        ended_utc = datetime.now(timezone.utc).isoformat()
        launch = {"run": "offline-probe", "attempt": 1, "participant_cli_pid": proc.pid,
                  "participant_cli_identity": identity, "mcp_call_sink_primed": True,
                  "mcp_startup_nonce_sha256": bench._sha(nonce.encode()),
                  "mcp_startup_config_sha256": config["private_config_sha256"],
                  "mcp_startup_source_sha256": bench._sha((HERE / "codex_frozen_mcp.py").read_bytes()),
                  "requested_config": config, "started_utc": started_utc, "ended_utc": ended_utc}
        event_audit = bench._inspect_cli_event_stream(event_path)
        calls = event_audit.get("tool_call_count") if event_audit.get("status") == "PASS" else -1
        session_files = list((codex_home / "sessions").rglob("*.jsonl")) if (codex_home / "sessions").is_dir() else []
        root_matches = [item for item in session_files if bench._rollout_id(item) == event_audit.get("thread_id")]
        expected_thread = bench._rollout_id(root_matches[0]) if root_matches else None
        startup, health = bench._audit_mcp_receipts(attempt, launch, calls, event_audit, expected_thread)
        startup_rows = bench._jsonl(startup_path)
        safe_startup_rows = [{key: row.get(key) for key in
                              ("method", "utc", "attempt_id", "nonce_sha256", "config_sha256",
                               "source_sha256", "parent_pid", "parent_identity", "tools")}
                             for row in startup_rows]
        final = {"status": "PASS" if rc == 0 and state.request_count == 1 and
                 startup["status"] == health["status"] == "PASS" and health.get("usage") == "NOT_USED" else "FAIL",
                 "cli_rc": rc, "provider_requests": state.request_count,
                 "stdin_pipe_error": stdin_pipe_error,
                 "stderr_error_codes": safe_error_codes,
                 "stderr_diagnostics": stderr_diagnostics,
                 "provider_first_request_utc": state.first_request_utc,
                 "mcp_tools_list_utc": startup_rows[-1].get("utc") if startup_rows else None,
                 "startup_before_provider": bool(startup_rows and state.first_request_utc and
                                                   startup_rows[-1].get("utc") < datetime.fromisoformat(state.first_request_utc).timestamp()),
                 "startup_status": startup["status"], "mcp_status": health["status"],
                 "usage": health.get("usage"), "observed_structural_calls": calls,
                 "event_stream_status": event_audit.get("status"),
                 "event_stream_types": event_audit.get("event_types"),
                 "root_thread_match": bool(expected_thread and expected_thread == event_audit.get("thread_id")),
                 "event_proof": {"status": event_audit.get("status"),
                                 "reason": event_audit.get("reason"),
                                 "thread_id": event_audit.get("thread_id"),
                                 "root_thread_id": expected_thread,
                                 "malformed_line_count": event_audit.get("malformed_line_count"),
                                 "structural_frozen_call_count": event_audit.get("tool_call_count"),
                                 "event_types": event_audit.get("event_types")},
                 "startup_tools": startup.get("tool_names"), "parent_identity_matches":
                 bool(startup.get("parent_pid") == identity.get("pid")),
                 "profile_version": bench.PROFILE_VERSION,
                 "attempt_id": "offline-probe/attempt-01",
                 "execution_window_utc": {"started": started_utc, "ended": ended_utc},
                 "participant_cli_identity": identity,
                 "startup_rows": safe_startup_rows,
                 "integration_source_sha256": {
                     name: bench._sha((HERE / name).read_bytes()) for name in
                     ("codex_bench.py", "codex_frozen_mcp.py", "test_codex_bench.py",
                      "integrated_zero_tool_probe.py")},
                 "final_config_sha256": config["private_config_sha256"],
                 "startup_receipt_sha256": bench._sha(startup_path.read_bytes()),
                 "call_receipt_sha256": bench._sha(call_path.read_bytes())}
    finally:
        server.shutdown(); server.server_close(); worker.join(timeout=2)
        resolved = temp.resolve()
        if resolved.parent != Path(tempfile.gettempdir()).resolve() or not resolved.name.startswith("codex-zero-tool-startup-integrated-"):
            raise RuntimeError("temporary cleanup path guard failed")
        for attempt_no in range(9):
            try:
                shutil.rmtree(resolved)
                break
            except OSError:
                if attempt_no == 8:
                    final["cleanup_status"] = "FAIL_LOCKED_OR_IO"
                else:
                    time.sleep(0.5)
        final.setdefault("cleanup_status", "PASS")
    return final


if __name__ == "__main__":
    result = run()
    out = HERE.parents[1] / "docs" / "model-test" / "2026-10-15-investigation-suite" / "reports" / "codex" / "operator-runtime"
    out.mkdir(parents=True, exist_ok=True)
    target = out / ("integrated-zero-tool-" + datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S%fZ") + ".json")
    target.write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(result, sort_keys=True))
    raise SystemExit(0 if result.get("status") == "PASS" and result.get("cleanup_status") == "PASS" else 1)
