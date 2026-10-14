#!/usr/bin/env bash
# Immutable replacement row emitter KAH-UI-003. Prints instructions only.
cat <<'ROW'
ROW KAH-UI-003 — isolated Stobe chat hotkey focus, slash draft, and untouched close
Replaces KAH-UI-001 for execution. Candidate Stobe.dll SHA-256: EFE7B71C0B2D3A7A0F7A1F18033F88BF64F3BE6A3B055C506E913BA1D3CE61BA.
This exact candidate is not installed. Run only after the operator confirms isolated install path, active process, and loaded DLL SHA on each rig. Run on both 4080 and 5090 where setup permits; previous 5090 open/close observations on other hashes do not validate this candidate.

Setup and input rules:
- Use a verified isolated instance and copied save. Record rig, instance, PID, save identity, loaded DLL path/hash, Stobe config path/hash, and evidence paths. Verify configured `ChatHotkey=/`.
- Before any key or click, send `stobe-auto input_isolation on`, then `stobe-auto input_isolation status`; require `isolation=on` and `focused=0`. Keep Kenshi unfocused for the entire row. Recheck the status before each interaction group and after it. If isolation drops or `focused` is not 0, stop without input and report setup failure.
- Every click/key must use only `stobe-auto mouse_inject ...` / `stobe-auto key_inject ...` or the documented isolated `kenshi-click.ps1` / `kenshi-key.ps1` helpers. Never use physical keyboard/mouse, AppActivate, focus helpers, or foreground changes. An injection ACK is transport evidence only.
- After every visual transition, use read-only `stobe-auto ui` and `stobe-auto screenshot <unique-name>`; retain the screenshot. Use screenshot coordinates for injected mouse targeting. For textbox focus/draft, the screenshot must visibly show the caret and exact slash draft; the `ui` read must show the chat/textbox state where available. If either cannot be demonstrated, mark evidence incomplete.

Exact operator sequence (all keys/clicks below are injected):
1. Open from a fresh key state: `stobe-auto key_inject / tap 120`. Read `ui` and capture screenshot showing the chat opened.
2. From that screenshot, move the virtual cursor to the message textbox and click using `stobe-auto mouse_inject at <x> <y>` then `stobe-auto mouse_inject left click 80`. Read `ui` and capture screenshot proving the caret is in the message textbox.
3. Inject the literal configured key once: `stobe-auto key_inject / tap 120`. Read `ui` and capture screenshot proving chat remains open and the draft contains exactly one `/`. Do not send the draft.
4. Discard this composed draft using an ordinary visible Cancel/close control, targeted only with injected mouse commands. Read `ui` and capture that the chat is closed. Do not use the hotkey to close a composed session.
5. Open a fresh untouched chat: `stobe-auto key_inject / tap 120`. Confirm with `ui` and screenshot. Do not click, type, paste, edit any field, or move the virtual cursor within this newly opened chat.
6. Inject `/` once more with `stobe-auto key_inject / tap 120`. Read `ui` and capture screenshot showing the untouched chat closed. This is a separate fresh session from the literal-draft check.

Expected RESULT PASS form (one per rig):
  RESULT KAH-UI-003 PASS rig=<4080|5090> instance=<n> isolation=on focused=0 loaded_stobe=EFE7B71C0B2D3A7A0F7A1F18033F88BF64F3BE6A3B055C506E913BA1D3CE61BA fresh_open=<ui+screenshot> textbox_focus=<ui+screenshot+caret> literal_slash_draft=<ui+screenshot> untouched_second_slash_close=<ui+screenshot>
Setup stop form (no test input after gate mismatch):
  RESULT KAH-UI-003 FAIL setup: <specific observed install/hash/config/save/isolation/focus mismatch>
Evidence stop form (input may have occurred; injection ACK is not a pass):
  RESULT KAH-UI-003 FAIL evidence: <specific unproven UI state or missing ui/screenshot/caret evidence>
ROW
