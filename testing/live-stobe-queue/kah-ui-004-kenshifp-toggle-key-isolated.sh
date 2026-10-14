#!/usr/bin/env bash
# Immutable replacement row emitter KAH-UI-004. Prints instructions only.
cat <<'ROW'
ROW KAH-UI-004 — isolated KenshiFP toggle binding, persistence, reset, and guards
Replaces KAH-UI-002 for execution. Candidate KenshiFP.dll SHA-256: 50C1698688D65E2A548C43E7C38F694BD28383FEEA36C1F269D990F2B574D270.
This exact candidate is not installed. Run only after the operator confirms isolated install path, active process, and loaded DLL SHA on each rig. Run on both 4080 and 5090 where setup permits; old Right Alt results on another binary do not validate this candidate.

Setup and input rules:
- Use a verified isolated instance and copied save. Record rig, instance, PID, save identity, loaded DLL path/hash, KenshiFP.ini path/hash, original `key_toggle_fp`, and evidence paths. Choose a key confirmed unused by the game/harness/UI for this run (F9 only if verified unused).
- Before any key or click, send `stobe-auto input_isolation on`, then `stobe-auto input_isolation status`; require `isolation=on` and `focused=0`. Keep Kenshi unfocused for the entire row; recheck before each interaction group and after it. Any isolation/focus mismatch stops input.
- Every key/click must use only `stobe-auto key_inject ...` / `stobe-auto mouse_inject ...` or documented isolated `kenshi-key.ps1` / `kenshi-click.ps1`. Never use physical keyboard/mouse, AppActivate, focus helpers, or foreground changes. Injection ACK only proves transport.
- For each state transition, collect read-only `stobe-auto ui`, `stobe-auto screenshot <unique-name>`, and `stobe-auto fp_keys state` where applicable. Read the same install's KenshiFP.ini without editing it to verify immediate persistence. Screenshots and read state, not ACKs, prove behavior.

Exact operator sequence (all clicks/keys below are injected):
1. Open settings with `stobe-auto key_inject f10 tap 120`; read `ui`, screenshot, and `fp_keys state`. Verify the `FP on / off` binding is present.
2. From the screenshot, target the binding with `stobe-auto mouse_inject at <x> <y>` then `stobe-auto mouse_inject left click 80`. Inject the verified unused key (example only if confirmed: `stobe-auto key_inject f9 tap 120`). Read `ui`, screenshot, and the INI immediately. Verify `key_toggle_fp` equals the chosen key's VK value.
3. Close/reopen settings using injected F10. Read `ui`/screenshot and verify the chosen binding persisted. Toggle FP off then on using injected chosen-key taps; after each, read `fp_keys state` and screenshot proving the state transition.
4. Re-enter binding capture with injected mouse targeting/click, then inject `stobe-auto key_inject esc tap 120`. Read `ui` and INI; prove capture cancelled and the chosen binding stayed unchanged.
5. From the screenshot, target `Reset to Defaults` by injected mouse move/click. Read `ui` and the INI immediately; prove `key_toggle_fp=0xA5` (Right Alt). Close/reopen settings via injected F10 and prove Right Alt remains. Inject `ralt` off/on and read `fp_keys state` + screenshot after each transition.
6. Focus guard: using injected mouse only, focus a visible ordinary text-entry field. Read `ui` and capture a screenshot showing its caret. Inject the configured toggle key and prove `fp_keys state` is unchanged; where the field accepts text, verify its text behavior through `ui`/screenshot. UI guard: with settings open but no active binding capture, inject the configured toggle and prove FP state is unchanged. Capture guard: while binding capture is active, inject Escape to cancel and prove FP state did not change. No-foreground guard: leave Kenshi unfocused, require `input_isolation status` to show `focused=0` immediately before/after an injected configured-toggle attempt, and prove through `fp_keys state`/screenshot that no unexpected toggle occurred. Never switch foreground to establish this check.
7. Leave defaults restored (`key_toggle_fp=0xA5`) and verify by read-only INI read at row end.

Expected RESULT PASS form (one per rig):
  RESULT KAH-UI-004 PASS rig=<4080|5090> instance=<n> isolation=on focused=0 loaded_kfp=50C1698688D65E2A548C43E7C38F694BD28383FEEA36C1F269D990F2B574D270 captured_key=<key/vk> ini_immediate=<read receipt> reopen=<ui+screenshot> escape_cancel=<ui+ini receipt> rebound_toggle=<fp_keys+screenshot off/on> reset_right_alt_0xA5=<ui+ini+reopen receipt> focus_ui_guards=<ui+fp_keys+screenshot receipts> defaults_restored=<ini receipt>
Setup stop form (no binding input after gate mismatch):
  RESULT KAH-UI-004 FAIL setup: <specific observed install/hash/INI/save/isolation/focus mismatch>
Evidence stop form (input may have occurred; injection ACK is not a pass):
  RESULT KAH-UI-004 FAIL evidence: <specific unproven UI, INI persistence, state transition, guard, or missing screenshot/read state>
ROW
