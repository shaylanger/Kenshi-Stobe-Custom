import json
import statistics
import sys
from pathlib import Path

ROOT = Path(r"C:\KenshiModding\training-data\live")

def load():
    turns = {}
    for path in sorted(ROOT.glob("*/events.jsonl")):
        with path.open("r", encoding="utf-8") as fh:
            for line in fh:
                try:
                    row = json.loads(line)
                except json.JSONDecodeError:
                    continue
                rid = str(row.get("request_id", ""))
                if not rid:
                    continue
                event = str(row.get("event_type", ""))
                turns.setdefault(rid, {}).setdefault(event, []).append(row.get("payload", {}))
    return turns

def n(v):
    try:
        return int(v)
    except (TypeError, ValueError):
        return 0

def cloud_metrics(events):
    vals = events.get("llm_exchange", [])
    if not vals:
        return None
    p = vals[-1]
    result = p.get("result") if isinstance(p.get("result"), dict) else {}
    return {
        "model": p.get("model", ""),
        "ttft": n(result.get("llm_ttft_ms")),
        "total": n(p.get("duration_ms")),
    }

def shadow_metrics(events):
    vals = events.get("shadow_llm_exchange", [])
    if not vals:
        return None
    p = vals[-1]
    return {
        "model": p.get("shadow_model", ""),
        "ttft": n(p.get("ttft_ms")),
        "total": n(p.get("total_generation_ms")),
        "queue": n(p.get("queue_delay_ms")),
        "vram": n((p.get("gpu_after") or {}).get("vram_used_mib")),
    }

def tts_metrics(events):
    vals = events.get("tts_output", [])
    if not vals:
        return None
    p = min(vals, key=lambda x: n(x.get("request_elapsed_ms")) or 10**12)
    return {
        "synth": n(p.get("tts_duration_ms")),
        "request_elapsed": n(p.get("request_elapsed_ms")),
    }

def avg(xs):
    return round(statistics.mean(xs), 1) if xs else 0

turns = load()
rows = []
for rid, events in turns.items():
    cloud = cloud_metrics(events)
    shadow = shadow_metrics(events)
    if not cloud or not shadow:
        continue
    tts = tts_metrics(events) or {}
    rows.append((rid, cloud, shadow, tts))

print(f"Paired shadow turns: {len(rows)}")
if not rows:
    sys.exit(0)

print("request_id | cloud_ttft | local_ttft | cloud_total | local_total | first_tts_elapsed | tts_synth | vram")
for rid, c, s, t in rows[-30:]:
    print(
        f"{rid} | {c['ttft']} | {s['ttft']} | {c['total']} | {s['total']} | "
        f"{t.get('request_elapsed',0)} | {t.get('synth',0)} | {s['vram']}"
    )

print()
print("Averages (ms)")
print(f"Cloud TTFT: {avg([x[1]['ttft'] for x in rows])}")
print(f"Local TTFT: {avg([x[2]['ttft'] for x in rows])}")
print(f"Cloud total: {avg([x[1]['total'] for x in rows])}")
print(f"Local total: {avg([x[2]['total'] for x in rows])}")
print(f"First TTS request elapsed: {avg([x[3].get('request_elapsed',0) for x in rows if x[3].get('request_elapsed')])}")
print(f"TTS synth: {avg([x[3].get('synth',0) for x in rows if x[3].get('synth')])}")
