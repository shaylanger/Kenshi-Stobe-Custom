"""Metadata-only live token-cost projection for an owned Codex attempt.

This module accepts only the `event_msg` / `token_count` usage envelope from
the exact participant rollout bound to the attempt. It never stores event or
payload text.
"""
from __future__ import annotations

import json
import os
import threading
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

TOKENS = ("input_tokens", "cached_input_tokens", "cache_write_input_tokens",
          "output_tokens", "reasoning_output_tokens", "total_tokens")
MAX_METADATA_LINE_BYTES = 65536


def _utc_now() -> str:
    return datetime.now(timezone.utc).isoformat()


def _counts(value: Any) -> dict[str, int] | None:
    if not isinstance(value, dict):
        return None
    out: dict[str, int] = {}
    for key in TOKENS:
        count = value.get(key)
        if count is not None:
            if type(count) is not int or count < 0:
                return None
            out[key] = count
    return out if out else None


class LiveCostProjector:
    """Incrementally project token_count events to an atomic live-cost file."""

    def __init__(self, snapshot_path: Path, *, run_id: str, attempt: int,
                 batch_id: str, model: str, requested_tier: str,
                 prices: dict[str, Any], price_table_sha256: str,
                 started_monotonic: float):
        self.path = Path(snapshot_path)
        self.run_id = run_id
        self.attempt = attempt
        self.batch_id = batch_id
        self.model = model
        self.requested_tier = requested_tier
        self.prices = prices
        self.price_table_sha256 = price_table_sha256
        self.started_monotonic = started_monotonic
        self.offset = 0
        self.file_identity: tuple[int, int] | None = None
        self.pending = b""
        self.discarding_oversized_line = False
        self.previous: dict[str, int] | None = None
        self.latest: dict[str, int] | None = None
        self.requests: list[dict[str, int | str]] = []
        self.errors: list[str] = []
        self.snapshot_write_failed = False
        self.observed_tiers: set[str] = set()
        self.thread_id: str | None = None
        self.participant_cli_identity: dict[str, Any] | None = None
        self.last_event_monotonic: float | None = None
        self._lock = threading.Lock()

    def set_thread_id(self, thread_id: str | None) -> None:
        if isinstance(thread_id, str) and thread_id:
            with self._lock:
                if self.thread_id is None:
                    self.thread_id = thread_id

    def set_cli_identity(self, identity: dict[str, Any] | None) -> None:
        if isinstance(identity, dict):
            with self._lock:
                self.participant_cli_identity = dict(identity)

    def poll(self, event_path: Path, *, force: bool = False) -> dict[str, Any]:
        """Consume only bytes appended since the last poll; retain no raw lines."""
        with self._lock:
            try:
                source = Path(event_path)
                stat = source.stat()
                identity = (stat.st_dev, stat.st_ino)
                if self.file_identity is not None and identity != self.file_identity:
                    self.errors.append("owned rollout file identity changed")
                if stat.st_size < self.offset:
                    self.errors.append("owned rollout stream truncated/reset")
                self.file_identity = identity
                if stat.st_size < self.offset:
                    self.offset = stat.st_size
                    self.pending = b""
                    self.discarding_oversized_line = False
                with source.open("rb") as stream:
                    while True:
                        stream.seek(self.offset)
                        chunk = stream.read(65536)
                        self.offset = stream.tell()
                        if chunk:
                            self.last_event_monotonic = __import__("time").monotonic()
                            self._consume_chunk(chunk)
                        if not force or len(chunk) < 65536:
                            break
            except OSError as exc:
                if not self.errors:
                    self.errors.append(f"usage stream unavailable: {type(exc).__name__}")
                return self.write_snapshot(force=force)
            if force and self.pending and not self.discarding_oversized_line:
                pending, self.pending = self.pending, b""
                self._consume_line(pending)
            return self.write_snapshot(force=force)

    def _consume_chunk(self, chunk: bytes) -> None:
        data = self.pending + chunk
        self.pending = b""
        while True:
            boundary = data.find(b"\n")
            if boundary < 0:
                if not self.discarding_oversized_line:
                    if len(data) <= MAX_METADATA_LINE_BYTES:
                        self.pending = data
                    else:
                        self.discarding_oversized_line = True
                return
            line, data = data[:boundary], data[boundary + 1:]
            if not self.discarding_oversized_line and len(line) <= MAX_METADATA_LINE_BYTES:
                self._consume_line(line)
            self.discarding_oversized_line = False

    def _consume_line(self, raw: bytes) -> None:
        if not raw.strip():
            return
        try:
            event = json.loads(raw)
        except (UnicodeDecodeError, json.JSONDecodeError):
            # CLI status may briefly write an incomplete line. Do not treat
            # unrelated or malformed non-usage events as usage evidence.
            return
        if not isinstance(event, dict) or event.get("type") != "event_msg":
            return
        payload = event.get("payload")
        if not isinstance(payload, dict) or payload.get("type") != "token_count":
            return
        info = payload.get("info")
        if not isinstance(info, dict):
            self.errors.append("token_count info missing")
            return
        cumulative = _counts(info.get("total_token_usage"))
        if cumulative is None:
            self.errors.append("token_count cumulative usage missing or invalid")
            return
        tier = info.get("service_tier")
        if isinstance(tier, str) and tier:
            self.observed_tiers.add(tier)
        signature = tuple(cumulative.get(key) for key in TOKENS)
        if self.latest is not None and signature == tuple(self.latest.get(key) for key in TOKENS):
            return
        last = _counts(info.get("last_token_usage"))
        if self.previous is not None and any(
                cumulative.get(key, 0) < self.previous.get(key, 0) for key in TOKENS):
            self.errors.append("cumulative token counter reset/decreased")
            self.previous = cumulative
            self.latest = cumulative
            return
        delta = {key: cumulative.get(key, 0) - (self.previous.get(key, 0) if self.previous else 0)
                 for key in TOKENS if key in cumulative or self.previous and key in self.previous}
        if last is not None:
            if any(last.get(key) != delta.get(key) for key in last):
                self.errors.append("last_token_usage does not match cumulative delta")
            else:
                self.requests.append({**last, "request_id": f"request-{len(self.requests) + 1}"})
        elif delta.get("total_tokens", 0) > 0:
            self.requests.append({**delta, "request_id": f"request-{len(self.requests) + 1}"})
        self.previous = cumulative
        self.latest = cumulative

    def snapshot(self) -> dict[str, Any]:
        import time
        import codex_record

        usage: dict[str, Any] | None = None
        if self.latest is not None:
            usage = {**self.latest, "requests": list(self.requests)}
            if self.errors:
                usage["request_usage_errors"] = list(self.errors)
        observed = next(iter(self.observed_tiers)) if len(self.observed_tiers) == 1 else None
        calculated = codex_record.calculated_cost(
            usage, self.model, self.requested_tier, observed, self.prices)
        stale_s = None if self.last_event_monotonic is None else round(time.monotonic() - self.last_event_monotonic, 3)
        cached = (usage or {}).get("cached_input_tokens")
        input_count = (usage or {}).get("input_tokens")
        status = "RUNNING" if usage else "WAITING_FOR_USAGE"
        if self.snapshot_write_failed:
            status = "TELEMETRY_WRITE_ERROR"
        if self.errors:
            status = "USAGE_UNKNOWN"
        elif len(self.observed_tiers) > 1:
            status = "TIER_UNKNOWN"
        return {
            "schema_version": 1,
            "run_id": self.run_id,
            "attempt": self.attempt,
            "batch_id": self.batch_id,
            "thread_id": self.thread_id,
            "participant_cli_identity": self.participant_cli_identity,
            "status": status,
            "updated_utc": _utc_now(),
            "elapsed_s": round(time.monotonic() - self.started_monotonic, 3),
            "usage_age_s": stale_s,
            "usage": usage,
            "request_count": len(self.requests),
            "cache_read_share": (cached / input_count if isinstance(cached, int) and
                                 isinstance(input_count, int) and input_count > 0 else None),
            "cost": calculated,
            "rate_card_sha256": self.price_table_sha256,
            "price_table_date": self.prices.get("date", "UNKNOWN"),
            "requested_tier": calculated.get("requested_tier", "UNKNOWN"),
            "observed_tier": calculated.get("served_tier", "UNKNOWN"),
            "invoice_status": "UNKNOWN",
            "errors": list(self.errors),
        }

    def write_snapshot(self, *, force: bool = False) -> dict[str, Any]:
        value = self.snapshot()
        try:
            self.path.parent.mkdir(parents=True, exist_ok=True)
            temp = self.path.with_name(self.path.name + f".{os.getpid()}.{threading.get_ident()}.tmp")
            temp.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
            os.replace(temp, self.path)
        except OSError:
            self.snapshot_write_failed = True
            self.errors.append("live_cost_snapshot_write_failed")
            value = self.snapshot()
        return value


def read_snapshot(path: Path) -> dict[str, Any] | None:
    try:
        value = json.loads(Path(path).read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return None
    return value if isinstance(value, dict) else None
