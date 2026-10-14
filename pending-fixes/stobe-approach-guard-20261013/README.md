# Stobe approach distance guard

This integration keeps the reviewed, transport-agnostic guard from commit
`912237a` and adds a KAH client wrapper. The wrapper calls KAH's existing
Python client in one process: for each decision it times `where @player`
followed by `where #serial/index` with `time.monotonic()`, verifies both exact
handles and finite 3D `pos=` values, and computes fresh distance in raw world
units. The pair must finish within two seconds. At `<=80` raw units it sends
zero `walktime` commands. Outside the radius it dispatches at most one
2..500-unit x/z leg, waits for that positional KAH command to finish, and then
starts a new timed pair before it can consider another leg. Missing, stale,
ambiguous, malformed, non-finite, or mismatched actor data fails closed.

KAH's `walktime` command sets/clears movement orders. The integration passes
the documented positional form `walktime @player <distance> <+x|-x|+z|-z>
walk`; it does not send a command when already in range. Do not insert an
operator wait between the reads and leg: run the wrapper as one remote
process/payload so the read pair, decision, and dispatch stay together.

## Offline selftest

From this directory:

```powershell
python -m unittest -v test_approach_guard.py test_kah_approach.py
python -m py_compile approach_guard.py kah_approach.py test_approach_guard.py test_kah_approach.py
```

The fake KAH client performs no game, rig, save, inbox, or input access. It
checks the 57-unit reproduction dispatches no movement; exact-handle and
finite-position parsing; mismatched identity rejection; the two-second pair
limit; a bounded leg followed by a fresh pair; KAH transport failure; and
stop-in-range behavior after that leg.

## Operator recipe (only for an explicitly authorized isolated test)

Copy `kah_approach.py` and `approach_guard.py` together to
`C:\KenshiTestRuns\approach-guard` on the isolated rig. Replace the two handle
placeholders below with current, independently confirmed handles. This is a
single foreground SSH/WSL payload for the verified 4080 instance-3 route:

```powershell
$remote = 'wsl.exe -d DwemerAI4Skyrim3 -u root --cd / -- bash -lc "python3 /mnt/c/KenshiTestRuns/approach-guard/kah_approach.py --kah-client /mnt/c/KenshiModding/Kenshi-Automation-Harness/client/kah.py --kah-dir C:/KenshiInst/3/mods/AutomationHarness --player \#PLAYER_SERIAL/INDEX --target \#TARGET_SERIAL/INDEX"'
ssh -F C:\Users\Shay\.ssh\config -o BatchMode=yes -o ConnectTimeout=8 4080 $remote
```

The wrapper obtains both fresh `where` responses before making any movement
decision. A successful terminal result is `RESULT APPROACH IN_RANGE ...`; any
invalid/stale state returns `RESULT APPROACH ABORT ...` and a nonzero exit
code. No rig was used to validate this source recipe.

## Reviewed helper provenance

The unchanged guard implementation is the exact helper in commit `912237a`.
Its original offline tests remain in `test_approach_guard.py`; this wrapper
and fake-client fixture are the integration addition. See
`INTEGRATION-RECEIPT.md` for exact file hashes, verification output, and the
independent review verdict.
