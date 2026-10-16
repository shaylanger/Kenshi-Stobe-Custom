# fix26f11b: two row-tooling candidates (imm26-fix26f11b, from op15 imm26-4080-i4)

Candidates are `.candidate` files next to the originals (operators may be running the originals; never edited in place). Swap = `cp X.candidate X` then SHA256 check.

## 11-b: u_state_combat returned in_combat=unknown on every poll (`unblockdefs_a.sh.candidate`)
Cause (code evidence): `stobe_state` JSON has no `in_combat` key (ai.* only). The old fallback did ONE `stobe_ctxpush`, slept 2 s, read `core_npc_master.metadata.native_ai.combat.in_combat`;
the ordinary NPC snapshot upsert (data_functions.php `metadata = $8::jsonb`) rewrites metadata WITHOUT native_ai, so a read that lands after the next snapshot is empty. op15 saved no raw reply, so the exact miss is unproven.
Fix: (1) stobe_state key, (2) up to U_SNAP_TRIES (3) x [ctxpush, 1.5 s, read, lower(name) match, `updated_at desc`], (3) newest `eventlog type='combat'` row naming the NPC (`...ended` => false, else true).
Output stays `in_combat=true|false|unknown|gone`, with ` (source=native_snapshot|eventlog|stobe_state)` appended (checker matches substrings). Every raw reply goes to `$EV/combat_probe.txt` (lines `snapN`, `evt`, `state`), so a remaining unknown shows why.
Test: `bash rowtools/fix26f11b-selftest.sh` (stubs only; 10 checks).
One call (unchanged): the existing 11-b row command (`unblockrun_sfk.sh 11-b <lane> ...`); no new env needed. Optional: `U_SNAP_TRIES`.

## 26-f: Cind sees 0 of 4 pinned bandits (`reloaddefs_sfe.sh.candidate`, function `rs_scene_clear`)
Evidence: op15 4080-i4 scene.txt: two `no answer within 20s` after the 58 k-unit teleport, then both senses polls (about 6 s after the spawn) had `entry=0 fov=-1 last_seen_s=-1` for all 4 (no perception entries yet).
5090-i5 scene.txt: 3 of 4 seen at poll 1, 0 of 4 four seconds later (`sees=0`, last_seen_s growing) = Cind's cone not refreshed after the single `face`.
Fix: wait until `where Shay` answers (RW_SCENE_READY_TRIES 12 x 5 s), settle 6 s (RW_SCENE_SETTLE), then up to RW_SCENE_POLLS (14) polls RW_SCENE_GAP (5 s) apart, `face` Cind to bandit 1 before each poll;
a poll counts at >= 3 sees; SCENE-OK after RW_SCENE_NEED (2) counting polls; when all bandits are blind (fov=-1) every 4th poll Cind is re-seated and the bandits re-placed (`settle-kick`).
Test: `bash rowtools/fix26f-selftest.sh` (6 stub scenarios; run against the old file it fails 3). One call (unchanged): `bash rowtools/reload-run-sfe.sh 26-f <lane> --save <S>`.
