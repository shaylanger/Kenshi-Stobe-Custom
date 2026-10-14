#!/usr/bin/env python3
"""Render an isolated, self-contained 4080 i3 P0 body with source-compatible auth gate with pinned driver bytes."""
from __future__ import annotations

import argparse
import base64
import hashlib
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[3]
SOURCES = REPO / "testing/live-stobe-queue/current-build-travel-driver"
PINS = {
    "driver.py": "EB0BA4C4F3B3F7091D1A8ED79E7CCD356823B23850B6B6885172C6B366213C70",
    "driver.sh": "A0A8B8846FCA898483CE7206D992AD164082181AAD8219E916594A9F292F91E3",
}
SESSION_READER = HERE / "auth-session-read-once-v2.py"
HISTORICAL = {
    "preflight-historical.md": REPO / "testing/live-stobe-queue/4080-final-full-readiness-pass-20261014.receipt.md",
    "destination-historical.md": REPO / "testing/live-stobe-queue/4080-P0-destination-feasibility-20261014.receipt.md",
}
DESTINATION_LINE = "NATIVE_DESTINATION name=The Hub catalog_row=1/378 xyz=-50978.8,1533.1,2932.5"
ACTOR_LINE = "NATIVE_ACTOR name=Cind [Hungry Bandit] serial=2529907200/2 player=Shay"
ACCEPTANCE = "I explicitly accept your offer to lead me to The Hub. Please start that exact trip now."


def digest(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest().upper()


def b64_file(path: Path, marker: str) -> str:
    encoded = base64.b64encode(path.read_bytes()).decode("ascii")
    lines = [encoded[i:i + 76] for i in range(0, len(encoded), 76)]
    return f"base64 -d >\"$PARENT/{path.name}\" <<'{marker}'\n" + "\n".join(lines) + f"\n{marker}\n"


def b64_bytes(data: bytes, output: str, marker: str) -> str:
    encoded = base64.b64encode(data).decode("ascii")
    lines = [encoded[i:i + 76] for i in range(0, len(encoded), 76)]
    return f"base64 -d >\"$RECEIPTS/{output}\" <<'{marker}'\n" + "\n".join(lines) + f"\n{marker}\n"


def body_text(driver_py: bytes, driver_sh: bytes, session_reader: bytes, histories: dict[str, bytes]) -> str:
    payloads = []
    for filename, data, marker in [
        ("driver.py", driver_py, "EMBED_DRIVER_PY"),
        ("driver.sh", driver_sh, "EMBED_DRIVER_SH"),
        ("session-reader.py", session_reader, "EMBED_SESSION_READER"),
    ]:
        encoded = base64.b64encode(data).decode("ascii")
        folded = "\n".join(encoded[i:i + 76] for i in range(0, len(encoded), 76))
        output = filename
        payloads.append(f"base64 -d >\"$PARENT/{output}\" <<'{marker}'\n{folded}\n{marker}\n")
    for name, data in histories.items():
        encoded = base64.b64encode(data).decode("ascii")
        folded = "\n".join(encoded[i:i + 76] for i in range(0, len(encoded), 76))
        marker = "EMBED_" + name.upper().replace(".", "_").replace("-", "_")
        payloads.append(f"base64 -d >\"$RECEIPTS/{name}\" <<'{marker}'\n{folded}\n{marker}\n")

    prefix = r'''export RIG=4080 KAH_INSTANCE=3
export KENSHI_DIR=/c/KenshiInst/3 KDIR=/c/KenshiInst/3
export KAH_DIR='C:\KenshiInst\3\mods\AutomationHarness'
. /c/KenshiModding/tools/automation/rig-env.sh
set -euo pipefail
rig4080_i3_preflight

# Unique receipt parent is atomically claimed. This body never creates OUT/run.
PARENT="/c/KenshiTestRuns/stobe-validation/4080-p0-current-driver-20261014-$(date +%Y%m%d-%H%M%S)-$$"
mkdir -p /c/KenshiTestRuns/stobe-validation
mkdir "$PARENT"
RECEIPTS="$PARENT/receipts"
mkdir "$RECEIPTS"
'''
    capture = r'''
capture_native() {
  local label="$1" limit="$2"
  shift 2
  local raw="$RECEIPTS/$label.raw.txt"
  printf '\n=== FRESH NATIVE %s ===\n' "$label" | tee -a "$RECEIPTS/preflight.receipt.md"
  if ! timeout "$limit" "$@" </dev/null >"$raw" 2>&1; then
    cat "$raw"
    printf 'RESULT P0-TRAVEL-START-MOVE-4080-001 FAIL setup: native capture %s failed\n' "$label"
    exit 2
  fi
  cat "$raw" | tee -a "$RECEIPTS/preflight.receipt.md"
}

printf '# Fresh 4080 i3 native/session preflight (generated immediately before P0)\n' >"$RECEIPTS/preflight.receipt.md"
printf 'captured_at=%s test_rig=4080 instance=3 player_expected=Shay\n' "$(date -Is)" >>"$RECEIPTS/preflight.receipt.md"
capture_native world 15 stobe-auto status
capture_native game-time 15 stobe-auto time
capture_native isolation 15 stobe-auto input_isolation status
capture_native fp-state 15 stobe-auto fp_state
capture_native speaker 15 stobe-auto stobe_ping
capture_native actor-state 15 stobe-auto stobe_state '#2529907200/2'
capture_native actor-where 15 stobe-auto where '#2529907200/2'
capture_native roster 20 stobe-auto chars 300
capture_native game-time-after 15 stobe-auto time

grep -Fq 'phase=world' "$RECEIPTS/world.raw.txt"
grep -Fq 'player=Shay' "$RECEIPTS/world.raw.txt"
grep -Fq 'paused=0' "$RECEIPTS/world.raw.txt"
grep -Eq 'paused[=: ]+0' "$RECEIPTS/game-time.raw.txt"
grep -Eq 'paused[=: ]+0' "$RECEIPTS/game-time-after.raw.txt"
grep -Fq 'isolation=on' "$RECEIPTS/isolation.raw.txt"
grep -Fq 'mode=chat speaker=Shay nearest=Cind [Hungry Bandit]' "$RECEIPTS/speaker.raw.txt"
grep -Fq 'Cind [Hungry Bandit]' "$RECEIPTS/actor-state.raw.txt"
grep -Fq '2529907200' "$RECEIPTS/actor-state.raw.txt"
grep -Fq 'Cind [Hungry Bandit] #2529907200/2' "$RECEIPTS/actor-where.raw.txt"
hours_before="$(sed -nE 's/.*game_hours[=: ]+([0-9]+([.][0-9]+)?).*/\1/p' "$RECEIPTS/game-time.raw.txt" | head -n 1)"
hours_after="$(sed -nE 's/.*game_hours[=: ]+([0-9]+([.][0-9]+)?).*/\1/p' "$RECEIPTS/game-time-after.raw.txt" | head -n 1)"
if [[ -z "$hours_before" || -z "$hours_after" ]] || ! python3 -c 'import sys; sys.exit(0 if float(sys.argv[2]) > float(sys.argv[1]) else 3)' "$hours_before" "$hours_after"; then
  printf 'RESULT P0-TRAVEL-START-MOVE-4080-001 FAIL setup: game time did not advance in fresh preflight\n'
  exit 2
fi
printf '%s\n' 'NATIVE_ACTOR name=Cind [Hungry Bandit] serial=2529907200/2 player=Shay' >>"$RECEIPTS/preflight.receipt.md"

# Current native town catalog: The Hub is row 1 of 378 at these coordinates.
capture_native destination 20 stobe-auto towns 'The Hub' max 5
grep -Eiq '1 of ?378' "$RECEIPTS/destination.raw.txt"
grep -Fq -- '-50978.8,1533.1,2932.5' "$RECEIPTS/destination.raw.txt"
printf '%s\n' 'NATIVE_DESTINATION name=The Hub catalog_row=1/378 xyz=-50978.8,1533.1,2932.5' >>"$RECEIPTS/destination.receipt.md"
'''
    session = r'''
# Sanitized session reader returns only allowlisted readiness fields; no token/load ID is emitted.
if ! MSYS_NO_PATHCONV=1 wsl.exe -d DwemerAI4Skyrim3 -- python3 - <"$PARENT/session-reader.py" >"$RECEIPTS/session.json"; then
  printf 'RESULT P0-TRAVEL-START-MOVE-4080-001 FAIL setup: sanitized session capture failed\n'
  exit 2
fi
cat "$RECEIPTS/session.json" | tee -a "$RECEIPTS/preflight.receipt.md"
# Exact EAC727 hash identifies the audited legacy interface: no pas_receipt_valid() helper exists there.
# Keep raw auth diagnostics in the receipt, gate supported state, and never infer native header use.
printf '%s\n' 'NATIVE_HEADER_AUTH=NOT_YET_PROVEN; requires a correlated native HTTP/chat outcome' >>"$RECEIPTS/preflight.receipt.md"
if ! cat "$RECEIPTS/session.json" | python3 -c 'import json,sys; x=json.load(sys.stdin); legacy="EAC727F650A9A22C1E5361D7C6A69B977EE9BB66D0E1F7A5278BADC9FD71C488"; src_hash=str(x.get("switching_source_sha256","")).upper(); supported=(x.get("session_present") is True and x.get("status")=="ready" and all(x.get(k) is True for k in ("generation_present","manager_ready_matches","auth_token_valid","auth_character_valid","campaign_identity_matches"))); proof=(src_hash==legacy) or (x.get("auth_function_present") is True and x.get("stored_receipt_valid") is True); sys.exit(0 if supported and proof else 3)'; then
  printf 'RESULT P0-TRAVEL-START-MOVE-4080-001 FAIL setup: fresh session/legacy-interface authorization gate failed\n'
  exit 2
fi

capture_native backend-health 10 curl.exe -fsS --max-time 5 http://127.0.0.1:18084/health.php
capture_native loaded-modules 30 powershell.exe -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File 'C:\KenshiModding\tools\automation\loaded-module-probe.ps1' -ExpectedExecutablePath 'C:\KenshiInst\3\RE_Kenshi\kenshi_x64.exe'
capture_native on-disk-mod-hashes 10 sha256sum /c/KenshiInst/3/mods/Stobe/Stobe.dll /c/KenshiInst/3/mods/AutomationHarness/AutomationHarness.dll
capture_native server-config 10 powershell.exe -NoLogo -NoProfile -NonInteractive -Command "Get-Content 'C:\KenshiInst\3\RE_Kenshi\mods\Stobe\StobeCustom.ini' | Select-String '^(ServerHost|ServerPort)'"

test "$(command -v python3)" = '/c/KAH/bin/python3'
test ! -e "$PARENT/run"  # driver owns the atomic creation of OUT
test "$(sha256sum "$PARENT/driver.py" | cut -d ' ' -f 1 | tr '[:lower:]' '[:upper:]')" = 'EB0BA4C4F3B3F7091D1A8ED79E7CCD356823B23850B6B6885172C6B366213C70'
test "$(sha256sum "$PARENT/driver.sh" | cut -d ' ' -f 1 | tr '[:lower:]' '[:upper:]')" = 'A0A8B8846FCA898483CE7206D992AD164082181AAD8219E916594A9F292F91E3'
PARENT_WIN="$(cygpath -w "$PARENT")"
export NPC='Cind [Hungry Bandit]' TRAVEL_DESTINATION='The Hub'
export OUT="$PARENT_WIN/run"
export NATIVE_LOG='C:/KenshiInst/3/RE_Kenshi/mods/Stobe/stobe.log'
export PREFLIGHT_RECEIPT="$PARENT_WIN/receipts/preflight.receipt.md"
export DESTINATION_RECEIPT="$PARENT_WIN/receipts/destination.receipt.md"
export ROW_ID='P0-TRAVEL-START-MOVE-4080-001'
export TRAVEL_DRIVER_BASH='C:/Program Files/Git/bin/bash.exe'
export WAIT_SECONDS=300 POLL_SECONDS=5
"$TRAVEL_DRIVER_BASH" "$(cygpath -w "$PARENT/driver.sh")"
'''
    return prefix + "\n".join(payloads) + capture + session


def build(parent: Path) -> Path:
    parent = parent.resolve()
    parent.mkdir(exist_ok=False)
    (parent / "receipts").mkdir()
    driver_py = (SOURCES / "driver.py").read_bytes()
    driver_sh = (SOURCES / "driver.sh").read_bytes()
    session_reader = SESSION_READER.read_bytes()
    histories = {name: path.read_bytes() for name, path in HISTORICAL.items()}
    actual = {"driver.py": digest(driver_py), "driver.sh": digest(driver_sh)}
    if actual != PINS:
        raise ValueError(f"current driver pin mismatch: {actual}")
    for name, data in [("driver.py", driver_py), ("driver.sh", driver_sh)]:
        (parent / name).write_bytes(data)
    for name, data in histories.items():
        (parent / "receipts" / name).write_bytes(data)
    (parent / "body.sh").write_text(body_text(driver_py, driver_sh, session_reader, histories), encoding="utf-8", newline="\n")
    (parent / "README.md").write_text(
        "# Self-contained 4080 i3 P0 invocation r5 (legacy-source auth gate)\n\n"
        "`body.sh` embeds the exact current driver, its shell entrypoint, sanitized session reader, and historical receipts. "
        "It needs no files from the author workspace at runtime beyond the standard `/c/KenshiModding/tools/automation/rig-env.sh` route layer and its existing native/tool entrypoints. "
        "Before the driver starts, it captures fresh native world/session/actor/destination evidence into a unique atomic receipt parent. "
        "The Hub must resolve as catalog row 1 of 378 at `[-50978.8,1533.1,2932.5]`; actor must be Cind [Hungry Bandit] #2529907200/2 with player Shay. "
        "The body does not create `run/`; the pinned driver claims that path atomically. For the exact EAC727 legacy source hash, it uses supported ready/token/character/campaign/generation checks without requiring the absent helper; other hashes require both supported helper proof flags. It retains both auth diagnostics in the receipt and labels native header authentication NOT_YET_PROVEN until a correlated HTTP/chat outcome. The exact acceptance text remains unchanged despite the known parser product bug.\n\n"
        f"- driver.py SHA-256 `{actual['driver.py']}`\n- driver.sh SHA-256 `{actual['driver.sh']}`\n"
        f"- session reader SHA-256 `{digest(session_reader)}`\n"
        f"- acceptance text `I explicitly accept your offer to lead me to The Hub. Please start that exact trip now.`\n",
        encoding="utf-8",
    )
    return parent


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("parent", type=Path)
    args = parser.parse_args()
    print(build(args.parent))


if __name__ == "__main__":
    main()
