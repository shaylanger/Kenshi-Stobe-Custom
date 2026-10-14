#!/usr/bin/env bash
# Immutable KAH-INT-005 operator packet. Prints instructions only.
cat <<'ROW'
ROW KAH-INT-005 — both portrait render paths unavailable; target initials fallback
STATUS: BLOCKED until exact Stobe candidate SHA256 AEF84C0A682DF036EB2CD0DC30A809E52E19956933F142C3A1D5877C4EB1907C is staged/loaded and a candidate-documented safe private+native portrait failure hook is explicitly identified and reviewed.

Before any input, inspect only the exact staged candidate's own docs/help and record the supported hook name, invocation, and bounded reset. If no supported hook can safely force both paths unavailable, stop immediately without invalidating a portrait manager/texture, changing an actor/save, or altering renderer state and emit exactly:
  RESULT KAH-INT-005 FAIL setup: exact candidate has no documented safe dual-render failure hook; no state changed

If a safe supported hook exists, use a copied save and one live target. Capture normal panel/read/screenshot. Trigger only the documented dual-render failure hook. Verify read state reports no portrait image (`portrait=0` where that is the documented state) and the visible panel shows the selected target's initial, not a blank region or stale previous-target image. Capture target key/generation, log, screenshot, and reset/restore proof. Never destroy/disable native portrait manager or texture directly.
Bound 5 minutes; no world/inventory change allowed.
PASS: RESULT KAH-INT-005 PASS rig=<4080|5090> loaded_stobe=AEF84C0A682DF036EB2CD0DC30A809E52E19956933F142C3A1D5877C4EB1907C safe_hook=<documented identity> both_paths_unavailable=<receipt> portrait=0 initial=<target key+shot> stale_previous=0 hook_restored=1
Setup: RESULT KAH-INT-005 FAIL setup: <no safe hook or exact staged-candidate mismatch; no fault triggered>
Evidence: RESULT KAH-INT-005 FAIL evidence: <initials/portrait/read/log/reset evidence missing or incorrect>
ROW
