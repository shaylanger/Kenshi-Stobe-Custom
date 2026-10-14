#!/usr/bin/env bash
# Immutable KAH-INT-002 operator packet. Prints instructions only.
cat <<'ROW'
ROW KAH-INT-002 — NPC Info panel follows selection changes across two humans
STATUS: BLOCKED until exact candidate is safely staged and loaded: Stobe SHA256 AEF84C0A682DF036EB2CD0DC30A809E52E19956933F142C3A1D5877C4EB1907C; source manifest AD63A137D74CFE23DEFF8914B06C56B8DC51693E88FBDA55AE1E365EE7B0445C; payload manifest 475B58A78C02377C3B67B1F7F6677F7E9AD912F018EC737CDE85807AB6D7FB0A. Run on both rigs where exact isolated stage exists.

Use a verified isolated copied save and record rig/instance/PID/save/DLL+manifest hashes. Select two distinct alive human NPC targets A and B already available; do not spawn or teleport. Capture `stobe-auto where "<A>"`, `where "<B>"`, and `where "<speaker>"`; record distinct handles and human races. If either target is missing, dead/KO, non-human, or ambiguous, stop setup. The selection changes below use the KAH command only; no OS input or focus action.

Within 5 minutes: `stobe-auto stobe_npcinfo open "<A>" "<speaker>"`, then read `stobe-auto stobe_npcinfo read` and capture `stobe-auto screenshot <A-shot>`. Record `key=<A serial>|<speaker>` and generation. Then `stobe-auto select "<B>"`; bounded poll read-only `stobe-auto stobe_npcinfo read` for up to 10 seconds and capture screenshot. Require `key=<B serial>|<speaker>` and a newer generation, with panel text/portrait coherent for B (no A text/image). Repeat selection A and require the inverse transition with a newer generation. Do not call a timeout or unchanged key a pass.

PASS: RESULT KAH-INT-002 PASS rig=<4080|5090> loaded_stobe=AEF84C0A682DF036EB2CD0DC30A809E52E19956933F142C3A1D5877C4EB1907C targets=<A handle/human,B handle/human> A_to_B=<read+shot+new gen> B_to_A=<read+shot+new gen> coherent_text_portrait=1
Setup: RESULT KAH-INT-002 FAIL setup: <specific stage/save/target/speaker gate and receipt>
Evidence: RESULT KAH-INT-002 FAIL evidence: <panel did not follow selection, stale/mixed content, no newer gen, or missing read/shot>
ROW
