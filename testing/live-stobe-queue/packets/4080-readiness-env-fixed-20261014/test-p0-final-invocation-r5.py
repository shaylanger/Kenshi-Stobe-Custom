#!/usr/bin/env python3
"""Local packaging-only checks for the self-contained r4 invocation body."""
from __future__ import annotations

import base64
import importlib.util
import json
import re
import subprocess
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("p0_r5_builder", HERE / "build-p0-final-invocation-r5.py")
assert spec and spec.loader
builder = importlib.util.module_from_spec(spec)
spec.loader.exec_module(builder)


def payload(body: str, target: str, marker: str, section: str) -> bytes:
    pattern = rf"base64 -d >\"\$PARENT/{re.escape(target)}\" <<'{marker}'\n([A-Za-z0-9+/=\n]+?)\n{marker}\n"
    match = re.search(pattern, body)
    assert match, f"missing embedded payload {target}"
    return base64.b64decode("".join(match.group(1).split()), validate=True)


with tempfile.TemporaryDirectory(prefix="p0-r5-package-") as temp:
    parent = Path(temp) / "package"
    package = builder.build(parent)
    body = (package / "body.sh").read_text(encoding="utf-8")
    assert not (package / "run").exists()

    route_and_rig_env = (
        "export RIG=4080 KAH_INSTANCE=3\n"
        "export KENSHI_DIR=/c/KenshiInst/3 KDIR=/c/KenshiInst/3\n"
        "export KAH_DIR='C:\\KenshiInst\\3\\mods\\AutomationHarness'\n"
        ". /c/KenshiModding/tools/automation/rig-env.sh\n"
    )
    assert body.startswith(route_and_rig_env), "exact isolated-i3 preamble/rig-env order changed"
    tail = body[len(route_and_rig_env):]
    wrapper_tail_guards = (
        r"(?i)\b(?:RIG|KAH_INSTANCE|KENSHI_DIR|KDIR|KAH_DIR)\s*=",
        r"(?i)\bunset\s+(?:-v\s+)?(?:RIG|KAH_INSTANCE|KENSHI_DIR|KDIR|KAH_DIR)\b",
        r"(?im)(?:^|[;&|\s])(?:command\s+)?(?:env|eval|exec|source)\b",
        r"(?im)(?:^|[;&|\s])\.\s+",
    )
    assert not any(re.search(pattern, tail) for pattern in wrapper_tail_guards), "exact wrapper i3 tail guard rejected body"

    assert payload(body, "driver.py", "EMBED_DRIVER_PY", "driver") == (package / "driver.py").read_bytes()
    assert payload(body, "driver.sh", "EMBED_DRIVER_SH", "driver") == (package / "driver.sh").read_bytes()
    assert payload(body, "session-reader.py", "EMBED_SESSION_READER", "session") == builder.SESSION_READER.read_bytes()
    for name, source in builder.HISTORICAL.items():
        marker = "EMBED_" + name.upper().replace(".", "_").replace("-", "_")
        match = re.search(rf"base64 -d >\"\$RECEIPTS/{re.escape(name)}\" <<'{marker}'\n([A-Za-z0-9+/=\n]+?)\n{marker}\n", body)
        assert match, f"missing historical receipt payload {name}"
        assert base64.b64decode("".join(match.group(1).split()), validate=True) == source.read_bytes()

    assert "export RIG=4080 KAH_INSTANCE=3\nexport KENSHI_DIR=/c/KenshiInst/3 KDIR=/c/KenshiInst/3" in body
    assert ". /c/KenshiModding/tools/automation/rig-env.sh\nset -euo pipefail\nrig4080_i3_preflight" in body
    assert 'mkdir "$PARENT"' in body and 'mkdir "$RECEIPTS"' in body
    assert 'test ! -e "$PARENT/run"' in body and 'mkdir "$PARENT/run"' not in body
    assert "OUT=\"$PARENT_WIN/run\"" in body
    assert "C:/KenshiModding/testing/live-stobe-queue" not in body
    assert "FRESH_PREFLIGHT_RECEIPT" not in body and "FRESH_DESTINATION_RECEIPT" not in body
    assert "NATIVE_ACTOR name=Cind [Hungry Bandit] serial=2529907200/2 player=Shay" in body
    assert "NATIVE_DESTINATION name=The Hub catalog_row=1/378 xyz=-50978.8,1533.1,2932.5" in body
    assert "capture_native actor-state" in body and "capture_native actor-where" in body
    assert "capture_native destination" in body and "session-reader.py" in body
    assert "game time did not advance in fresh preflight" in body
    assert "EAC727F650A9A22C1E5361D7C6A69B977EE9BB66D0E1F7A5278BADC9FD71C488" in body
    assert "auth_function_present\\\":True" not in body
    assert "stored_receipt_valid\\\":True" not in body
    assert "NATIVE_HEADER_AUTH=NOT_YET_PROVEN" in body
    assert "fresh session/legacy-interface authorization gate failed" in body
    assert body.index("capture_native destination") < body.index('"$TRAVEL_DRIVER_BASH"')
    assert "I explicitly accept your offer to lead me to {DEST}. Please start that exact trip now." in (package / "driver.py").read_text(encoding="utf-8")
    assert "EB0BA4C4F3B3F7091D1A8ED79E7CCD356823B23850B6B6885172C6B366213C70" in body
    assert "A0A8B8846FCA898483CE7206D992AD164082181AAD8219E916594A9F292F91E3" in body
    gate = re.search(r"""if ! cat "\$RECEIPTS/session\.json" \| python3 -c '([^']+)'; then""", body)
    assert gate, "missing actual session gate expression"
    base = dict(session_present=True, status="ready", generation_present=True,
                manager_ready_matches=True, auth_token_valid=True,
                auth_character_valid=True, campaign_identity_matches=True,
                auth_function_present=False, stored_receipt_valid=False)
    def run_gate(sample):
        result = subprocess.run([sys.executable, "-c", gate.group(1)],
                                input=json.dumps(sample), text=True, capture_output=True)
        return result.returncode
    legacy = dict(base, switching_source_sha256="EAC727F650A9A22C1E5361D7C6A69B977EE9BB66D0E1F7A5278BADC9FD71C488")
    assert run_gate(legacy) == 0, "audited legacy source must not require absent helper flags"
    assert run_gate(dict(legacy, campaign_identity_matches=False)) != 0, "legacy path must retain supported state gates"
    other = dict(base, switching_source_sha256="0" * 64)
    assert run_gate(other) != 0, "other sources must fail closed without helper proof"
    assert run_gate(dict(other, auth_function_present=True, stored_receipt_valid=True)) == 0

    try:
        builder.build(parent)
    except FileExistsError:
        pass
    else:
        raise AssertionError("package parent was reused instead of exclusively claimed")

print("SELFTEST PASS cases=5 selfcontained_driver=2 historical_receipts=2 session_reader=1 fresh_native_actor_session_destination=1 unique_parent=1 run_absent=1 driver_atomic_OUT=1 no_author_workspace_paths=1")
