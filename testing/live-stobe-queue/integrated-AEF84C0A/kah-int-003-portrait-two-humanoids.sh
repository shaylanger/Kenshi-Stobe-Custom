#!/usr/bin/env bash
# Immutable KAH-INT-003 operator packet. Prints instructions only.
cat <<'ROW'
ROW KAH-INT-003 — live portraits on two humanoids: face, headgear, color, refresh
STATUS: BLOCKED until exact Stobe candidate SHA256 AEF84C0A682DF036EB2CD0DC30A809E52E19956933F142C3A1D5877C4EB1907C and source manifest AD63A137D74CFE23DEFF8914B06C56B8DC51693E88FBDA55AE1E365EE7B0445C are staged/loaded on the isolated rig. Run on both rigs where setup permits.

Use two distinct living humanoids already present in a copied save; prefer two different races and distinct equipped headgear. Do not alter equipment/save to manufacture a case. Record actor handles/races, current equipment using `stobe-auto inv`, speaker handle, copied-save and exact candidate receipts. If two suitable actors or a headgear case are unavailable, report setup FAIL for the uncovered case; do not imply all coverage.

For each target independently, open/refresh the NPC Info panel with the existing read-only panel path, then capture `stobe-auto stobe_npcinfo read`, the corresponding `PROFILE_PORTRAIT` log line for that exact handle, and a full screenshot. Compare the portrait with the simultaneously visible current target: frontal recognizable face, portrait free of headgear, natural non-dark color, correct target (no stale prior image). Confirm `applied=1`, `portrait=1`, portrait texture identity where available, and unchanged equipped inventory/native squad icon. Switch between A and B while panel remains open and capture refreshed target key/generation and matching portrait for each.

Bound 8 minutes including capture and review. PASS requires human visual review of both full-resolution screenshots in addition to read/log/inventory receipts; if visual review is not complete, report INCONCLUSIVE. Keep refresh-target validation separate from portrait appearance in the receipt.
PASS: RESULT KAH-INT-003 PASS rig=<4080|5090> loaded_stobe=AEF84C0A682DF036EB2CD0DC30A809E52E19956933F142C3A1D5877C4EB1907C actors=<A/B handles+races+gear> portrait_A=<read+log+shot+visual verdict> portrait_B=<read+log+shot+visual verdict> target_refresh=<A-B-A keys/gens> inventory_unchanged=1
Setup: RESULT KAH-INT-003 FAIL setup: <specific stage/save/actors/gear/log/capture gate>
Evidence: RESULT KAH-INT-003 FAIL evidence: <visual or read/log/refresh proof missing or defect observed>
ROW
