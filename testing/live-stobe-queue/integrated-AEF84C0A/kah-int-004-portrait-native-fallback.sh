#!/usr/bin/env bash
# Immutable KAH-INT-004 operator packet. Prints instructions only.
cat <<'ROW'
ROW KAH-INT-004 — private portrait render failure falls back to native atlas
STATUS: BLOCKED until exact Stobe candidate SHA256 AEF84C0A682DF036EB2CD0DC30A809E52E19956933F142C3A1D5877C4EB1907C is staged/loaded and a candidate-documented safe private-render fault-injection hook is explicitly identified and reviewed.

Before any input, inspect only the exact staged candidate's own docs/help and record the supported hook name, invocation, and bounded reset. If no supported fault injection hook exists, stop immediately without changing actor, renderer, texture, manager, save, or equipment and emit exactly:
  RESULT KAH-INT-004 FAIL setup: exact candidate has no documented safe private-render failure test hook; no state changed

If a supported hook is present and verified, use a copied save on both rigs where staged. First capture normal render evidence for one target, then trigger only the documented private-render failure through that hook. Capture the native atlas fallback image and `stobe_npcinfo read`, target key/generation, log, and screenshot; verify the image belongs to the selected target and no previous target image leaks. Restore the hook to normal before ending. No direct renderer/resource/texture destruction or unsafe memory manipulation.
Bound 5 minutes. Any hook that alters game world, inventory, or another actor is not supported for this row; stop setup.
PASS: RESULT KAH-INT-004 PASS rig=<4080|5090> loaded_stobe=AEF84C0A682DF036EB2CD0DC30A809E52E19956933F142C3A1D5877C4EB1907C safe_hook=<documented identity> injected_failure=<receipt> fallback=native_atlas target=<handle/read+shot> stale_previous=0 hook_restored=1
Setup: RESULT KAH-INT-004 FAIL setup: <no safe hook or exact staged-candidate mismatch; no fault triggered>
Evidence: RESULT KAH-INT-004 FAIL evidence: <hook/fallback/target/reset evidence missing or fallback incorrect>
ROW
