#!/usr/bin/env bash
# Immutable row emitter KAH-UI-001. Prints instructions only; never controls a rig.
cat <<'ROW'
ROW KAH-UI-001 — Stobe chat hotkey focus, literal slash, and untouched close
Candidate Stobe.dll SHA-256: EFE7B71C0B2D3A7A0F7A1F18033F88BF64F3BE6A3B055C506E913BA1D3CE61BA
This exact candidate is not installed. This row is blocked until the rig operator confirms isolated install path, process/load identity, and loaded DLL SHA on each rig. Run on both 4080 and 5090 where setup permits; old 5090 open/close evidence does not validate this candidate.

Setup gates (each rig, before UI input): isolated test instance and copied save verified; Stobe candidate SHA above matches the loaded install; chat key read from that install's Stobe config is `/`; game is running in a stable world; no other dialog/chat window is open. Record rig, instance, PID, save identity, DLL path/hash, config path/hash, and evidence capture path. Any mismatch stops before hotkey input.

Exact operator sequence:
1. Press `/` once from a fresh key state. Verify Stobe chat opens.
2. Click the message textbox. Prove focus by observing the caret in that textbox, then type `/` once. Verify the textbox remains open and its draft contains exactly one literal `/` (do not send it).
3. Discard that draft using the chat's ordinary Cancel/close control; do not use the hotkey to close this composed session.
4. With no Stobe chat open, press `/` once from a fresh key state to open a new untouched chat. Do not click, type, paste, edit any field, or move focus within the new chat.
5. Press `/` once more from a fresh press/release. Verify the untouched chat closes. This verifies the second-toggle rule separately from slash composition.

Evidence bundle: continuous or timestamp-correlated capture showing both opens, caret in the message textbox, the literal draft slash, draft discard, and untouched second-press close; record config and loaded DLL hash for the same rig/session. If focus or one state transition is not visibly provable, mark evidence incomplete.
Expected RESULT PASS form (one per rig):
  RESULT KAH-UI-001 PASS rig=<4080|5090> instance=<n> loaded_stobe=EFE7B71C0B2D3A7A0F7A1F18033F88BF64F3BE6A3B055C506E913BA1D3CE61BA fresh_open=<receipt> textbox_focus=<receipt> literal_slash_draft=<receipt> untouched_second_slash_close=<receipt>
Setup stop form (no hotkey test performed):
  RESULT KAH-UI-001 FAIL setup: <specific observed install/hash/config/save/process/world mismatch>
Evidence stop form (test may be partial; do not call setup failure):
  RESULT KAH-UI-001 FAIL evidence: <specific unproven UI state or missing capture>
ROW
