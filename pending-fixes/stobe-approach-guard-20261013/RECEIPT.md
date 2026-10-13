# Stobe approach guard candidate — 2026-10-13

## Scope and incident

The operator-preserved inner command was `stobe-auto walktime @player 206 +x walk`.
Its immediate preflight put Bark at `(54171.2,1146.5,-94214.6)` and exact
Matsuyo at raw distance `57.0`, already inside the `<=80` typed-context stop
radius. The ephemeral outer PowerShell/SSH command text was not preserved, so
this candidate does not claim to patch that wrapper byte-for-byte. It provides
a reusable, transport-agnostic guard for a future caller.

Incident source receipt:
`pending-fixes/rig4080-validation/approach-stale-leg-evidence-4080i3-20261013.md`
SHA-256 `4C2A26CD5A6F77F706AF8DBF2BC98CE4F9B6767B42E3530405BED24F2590C9E6`.

## Guard behavior

`guarded_approach` binds expected player and target identities. It obtains a
new 3D position snapshot before each single-axis x/z leg, rejects missing,
non-finite, stale, future-dated, or changed-identity snapshots, and compares
the fresh distance against 80 raw units. A distance `<=80` returns with no
movement callback. A distance above 80 yields at most one bounded leg (KAH
walktime limits: 2..500); the next leg requires new player and exact-target
reads and a new check. Each snapshot includes monotonic acquisition start and
completion times. The guard rejects a pair if the read interval exceeds two
seconds or if either endpoint is older than two seconds, preventing delayed
first-read coordinates from appearing fresh under a completion-only stamp.
`walktime_arguments` only returns argument tokens; it does not launch or
transport a command.

For `where` responses that lack their own timestamps, a future integration
must record monotonic acquisition start immediately before the first player /
target query, completion immediately after both responses, reject a pair whose
interval or endpoint age exceeds two seconds, and never reuse a precomputed
leg. No such live integration was performed.

## Verification

Command: `python -m unittest -v test_approach_guard.py`

Result: **PASS, 11 tests**. Coverage includes the reproduced 57-unit case,
79.9/80.0/80.1 boundaries, crossing into radius between legs, changed target
identity, stale and missing snapshots, delayed first-position acquisition, 3D
range, bounded per-leg revalidation, no horizontal vector, and safe walktime
token formatting.

`python -m py_compile approach_guard.py test_approach_guard.py` also passed.
No rig, game, save, inbox, config, or OS input was accessed. The helper remains
an isolated candidate pending exact-hash independent review and integration by
an authorized source owner.

## Frozen file hashes (SHA-256)

- `approach_guard.py`: `CEA035F00E326F703538C3FA1C31A9CF9E189A6ABF97D20FE27BE798C9FAC8DB`
- `test_approach_guard.py`: `5AA4D92D0243F24785C86595E1F79F83B0B719E011D17E79CE7F819289EF899E`
- `README.md`: `B090152D2AC27598419D936CFDD60C9684CA2AEA910CE922B2EFF59FB5358452`
