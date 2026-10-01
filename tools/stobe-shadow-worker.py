import hashlib
import json
import os
import subprocess
import time
import urllib.error
import urllib.request
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(r"C:\KenshiModding\training-data")
PENDING = ROOT / "shadow-queue" / "pending"
PROCESSING = ROOT / "shadow-queue" / "processing"
ENABLED = ROOT / "shadow-enabled.flag"
LIVE = ROOT / "live"
URL = "http://127.0.0.1:8091/v1/chat/completions"
MODEL = "qwen3.5-9b-q4_k_m"
API_KEY = "local"

def now_iso():
    return datetime.now(timezone.utc).astimezone().isoformat()

def unix_ms():
    return int(time.time() * 1000)

def gpu_snapshot():
    try:
        out = subprocess.check_output([
            "nvidia-smi",
            "--query-gpu=memory.used,memory.total,utilization.gpu,utilization.memory",
            "--format=csv,noheader,nounits",
        ], text=True, timeout=3).strip().splitlines()[0]
        vals = [int(x.strip()) for x in out.split(",")]
        return {
            "vram_used_mib": vals[0],
            "vram_total_mib": vals[1],
            "gpu_util_pct": vals[2],
            "memory_util_pct": vals[3],
        }
    except Exception as exc:
        return {"error": str(exc)}

def append_event(event_type, request_id, payload):
    day = datetime.now().strftime("%Y-%m-%d")
    directory = LIVE / day
    directory.mkdir(parents=True, exist_ok=True)
    record = {
        "capture_version": 1,
        "captured_at": now_iso(),
        "unix_ms": unix_ms(),
        "event_type": event_type,
        "request_id": request_id,
        "payload": payload,
    }
    with (directory / "events.jsonl").open("a", encoding="utf-8") as fh:
        fh.write(json.dumps(record, ensure_ascii=False, separators=(",", ":")) + "\n")

def build_request(task):
    source = task.get("payload", {})
    body = {
        "model": MODEL,
        "messages": source.get("messages", []),
        "stream": True,
        "stream_options": {"include_usage": True},
        "max_tokens": max(1, int(source.get("max_tokens", 750) or 750)),
        "temperature": float(source.get("temperature", 0.8) or 0.8),
        "chat_template_kwargs": {"enable_thinking": False},
    }
    response_format = source.get("response_format")
    if response_format:
        body["response_format"] = response_format
    return body

def run_shadow(task):
    source = task.get("payload", {})
    request_id = str(task.get("request_id") or source.get("request_id") or "")
    body = build_request(task)
    raw_body = json.dumps(body, ensure_ascii=False).encode("utf-8")
    req = urllib.request.Request(
        URL,
        data=raw_body,
        method="POST",
        headers={
            "Content-Type": "application/json",
            "Authorization": "Bearer " + API_KEY,
        },
    )
    queued_ms = int(task.get("queued_unix_ms", 0) or 0)
    started = time.perf_counter()
    started_unix_ms = unix_ms()
    before_gpu = gpu_snapshot()
    first_text_at = None
    response_text = ""
    usage = {}
    finish_reason = ""
    with urllib.request.urlopen(req, timeout=180) as resp:
        http_code = int(resp.status)
        for raw_line in resp:
            line = raw_line.decode("utf-8", errors="replace").strip()
            if not line.startswith("data: "):
                continue
            data = line[6:]
            if data == "[DONE]":
                break
            try:
                chunk = json.loads(data)
            except json.JSONDecodeError:
                continue
            if isinstance(chunk.get("usage"), dict):
                usage = chunk["usage"]
            choices = chunk.get("choices") or []
            if not choices:
                continue
            choice = choices[0] or {}
            if choice.get("finish_reason"):
                finish_reason = str(choice.get("finish_reason"))
            delta = choice.get("delta") or {}
            content = delta.get("content")
            if isinstance(content, str) and content:
                if first_text_at is None:
                    first_text_at = time.perf_counter()
                response_text += content

    ended = time.perf_counter()
    after_gpu = gpu_snapshot()
    ttft_ms = int((first_text_at - started) * 1000) if first_text_at else 0
    total_ms = int((ended - started) * 1000)
    parsed_json = None
    structured_valid = False
    try:
        parsed_json = json.loads(response_text)
        structured_valid = isinstance(parsed_json, dict)
    except (json.JSONDecodeError, TypeError):
        pass
    payload = {
        "shadow_model": MODEL,
        "authoritative_model": str(source.get("authoritative_model", "")),
        "target_npc": str(source.get("target_npc", "")),
        "speaker": str(source.get("speaker", "")),
        "gamets": int(source.get("gamets", 0) or 0),
        "status": "ok",
        "http_code": http_code,
        "queue_delay_ms": max(0, started_unix_ms - queued_ms) if queued_ms else 0,
        "ttft_ms": ttft_ms,
        "total_generation_ms": total_ms,
        "after_first_text_ms": max(0, total_ms - ttft_ms) if ttft_ms else 0,
        "response_text": response_text,
        "parsed_json": parsed_json,
        "structured_valid": structured_valid,
        "finish_reason": finish_reason,
        "usage": usage,
        "gpu_before": before_gpu,
        "gpu_after": after_gpu,
        "messages_sha1": hashlib.sha1(json.dumps(body.get("messages", []), ensure_ascii=False, separators=(",", ":")).encode("utf-8")).hexdigest(),
        "request_payload": body,
    }
    append_event("shadow_llm_exchange", request_id, payload)
    return payload

def process_one(path):
    PROCESSING.mkdir(parents=True, exist_ok=True)
    working = PROCESSING / path.name
    try:
        os.replace(path, working)
        with working.open("r", encoding="utf-8-sig") as fh:
            task = json.load(fh)
        result = run_shadow(task)
        print(
            f"{result['target_npc']} request={task.get('request_id','')} "
            f"ttft={result['ttft_ms']}ms total={result['total_generation_ms']}ms "
            f"vram={result['gpu_after'].get('vram_used_mib','?')}MiB",
            flush=True,
        )
        working.unlink(missing_ok=True)
    except (urllib.error.URLError, TimeoutError, ConnectionError) as exc:
        try:
            os.replace(working, PENDING / path.name)
        except OSError:
            pass
        time.sleep(2)
    except Exception as exc:
        request_id = ""
        try:
            request_id = str(task.get("request_id", ""))
        except Exception:
            pass
        append_event("shadow_llm_error", request_id, {
            "shadow_model": MODEL,
            "error": repr(exc),
            "file": path.name,
            "gpu": gpu_snapshot(),
        })
        working.unlink(missing_ok=True)

def main():
    PENDING.mkdir(parents=True, exist_ok=True)
    PROCESSING.mkdir(parents=True, exist_ok=True)
    print("STOBE shadow worker ready", flush=True)
    while True:
        if not ENABLED.exists():
            time.sleep(1)
            continue
        files = sorted(PENDING.glob("*.json"), key=lambda p: p.stat().st_mtime)
        if not files:
            time.sleep(0.1)
            continue
        process_one(files[0])

if __name__ == "__main__":
    main()
