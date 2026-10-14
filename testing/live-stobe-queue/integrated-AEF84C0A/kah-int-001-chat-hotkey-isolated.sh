#!/usr/bin/env bash
# Immutable KAH-INT-001 operator packet. Prints instructions only.
cat <<'ROW'
ROW KAH-INT-001 — integrated candidate chat hotkey, textbox draft, untouched close
STATUS: BLOCKED until the authorized operator completes safe isolated staging and confirms loaded Stobe SHA256 AEF84C0A682DF036EB2CD0DC30A809E52E19956933F142C3A1D5877C4EB1907C, source manifest AD63A137D74CFE23DEFF8914B06C56B8DC51693E88FBDA55AE1E365EE7B0445C, and payload manifest 475B58A78C02377C3B67B1F7F6677F7E9AD912F018EC737CDE85807AB6D7FB0A. No shared-Steam install route. Run both rigs only where exact isolated staging exists.

Preflight: record rig/instance/PID/copied-save identity, DLL path+SHA, manifest receipts, and Stobe config path/hash; require configured `ChatHotkey=/`. Run `stobe-auto input_isolation on`, then `stobe-auto input_isolation status`; require `isolation=on focused=0`. Keep game unfocused throughout; recheck before/after input groups. If any pin or isolation gate fails, no input.

Only injected inputs: `stobe-auto key_inject / tap 120`; click textbox/cancel via screenshot-coordinate `stobe-auto mouse_inject at <x> <y>` then `stobe-auto mouse_inject left click 80`. Alternatively use documented isolated `kenshi-key.ps1`/`kenshi-click.ps1`. Never use physical input, focus, or foreground changes. After each transition retain `stobe-auto ui` output and `stobe-auto screenshot <unique-name>`; injection ACK is not behavioral evidence.

Sequence (complete within 5 minutes after preflight): (1) inject `/` once from fresh key state; prove chat opens in UI state/screenshot. (2) injected-click the message textbox; prove caret in that textbox in screenshot and visible message field through `ui`. (3) inject `/` once; prove chat remains open and exact single slash is present in draft through `ui` and screenshot; do not send. (4) discard the composed draft only through an injected click on the visible Cancel/close control. (5) inject `/` to open a separate fresh chat; leave it entirely untouched. (6) inject `/` a second time and prove that fresh untouched chat closes. No typing/clicking inside the fresh untouched session.

PASS: RESULT KAH-INT-001 PASS rig=<4080|5090> loaded_stobe=AEF84C0A682DF036EB2CD0DC30A809E52E19956933F142C3A1D5877C4EB1907C isolation=on focused=0 open=<ui+shot> caret=<shot> slash_draft=<ui+shot> fresh_untouched_close=<ui+shot>
Setup: RESULT KAH-INT-001 FAIL setup: <specific stage/hash/config/isolation/focus mismatch; no test input>
Evidence: RESULT KAH-INT-001 FAIL evidence: <specific unproven state or missing UI/shot evidence>
ROW
