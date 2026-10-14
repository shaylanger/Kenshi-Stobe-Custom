#!/usr/bin/env bash
# Immutable row emitter KAH-UI-002. Prints instructions only; never controls a rig.
cat <<'ROW'
ROW KAH-UI-002 — KenshiFP configurable toggle key, persistence, reset, and guards
Candidate KenshiFP.dll SHA-256: 50C1698688D65E2A548C43E7C38F694BD28383FEEA36C1F269D990F2B574D270
This exact candidate is not installed. This row is blocked until the rig operator confirms isolated install path, process/load identity, and loaded DLL SHA on each rig. Run on both 4080 and 5090 where setup permits; earlier Right Alt evidence on another binary does not validate this candidate.

Setup gates (each rig, before UI input): isolated test instance and copied save verified; candidate SHA above matches the loaded install; KenshiFP.ini path and current `key_toggle_fp` value recorded; stable world with a selected character; no modal dialog. Choose a new key that the operator verifies is unused by the game, harness, and current UI for this run (suggested F9 only if confirmed unused); record that choice. Record rig, instance, PID, save identity, DLL path/hash, INI path/hash, and evidence capture path. Any mismatch stops before binding changes.

Exact operator sequence:
1. Press F10 and verify the settings window opens and shows the `FP on / off` binding.
2. Click `FP on / off`, release the mouse button, and press the chosen new key once. Verify the displayed binding changes. Immediately read the same install's KenshiFP.ini and record `key_toggle_fp` with timestamp; it must match the chosen key's virtual-key value.
3. Close settings with F10, reopen with F10, and verify the chosen binding is still displayed. Toggle first-person off and on using the chosen key, recording both observed states.
4. Enter binding capture again, release the click, then press Escape. Verify capture cancels and the chosen binding remains unchanged in the UI and INI.
5. Use `Reset to Defaults`; verify the binding is Right Alt (`0xA5`) in the UI and in KenshiFP.ini immediately. Close/reopen settings and verify Right Alt persists. Toggle first-person off and on with Right Alt.
6. Verify guards: while an ordinary text-entry field has keyboard focus, press the configured FP toggle and confirm mode does not change; verify the typed key remains ordinary text where the field accepts it. While the settings window is open outside active binding capture, press the configured toggle and confirm mode does not change. With Kenshi unfocused, press the configured toggle and confirm mode does not change. During a fresh binding-capture session, presses that are not the selected capture action must not switch FP mode. Record the UI/focus state and mode before/after each guard check.

Do not edit the INI to simulate a successful binding. The INI check is read-only evidence of the UI's immediate save. Leave defaults restored at row end.
Evidence bundle: timestamp-correlated UI capture of capture/cancel, chosen binding and both mode transitions, reset and Right Alt transitions, plus before/after INI copies or exact line/hash/time receipts and the loaded DLL SHA. If an input focus or mode transition is ambiguous, mark evidence incomplete.
Expected RESULT PASS form (one per rig):
  RESULT KAH-UI-002 PASS rig=<4080|5090> instance=<n> loaded_kfp=50C1698688D65E2A548C43E7C38F694BD28383FEEA36C1F269D990F2B574D270 captured_key=<key/vk> ini_immediate=<receipt> reopen=<receipt> escape_cancel=<receipt> reset_right_alt_0xA5=<receipt> rebound_toggle=<off/on receipt> focus_ui_guards=<receipt>
Setup stop form (no binding test performed):
  RESULT KAH-UI-002 FAIL setup: <specific observed install/hash/INI/save/process/world mismatch>
Evidence stop form (test may be partial; do not call setup failure):
  RESULT KAH-UI-002 FAIL evidence: <specific unproven UI state, persistence value, mode transition, guard, or missing capture>
ROW
