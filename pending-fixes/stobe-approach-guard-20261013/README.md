# Stobe approach distance guard (offline candidate)

The reported `+x` incident came from an ephemeral operator command. This
candidate is a transport-agnostic reusable guard, not a replacement game or
rig script. It contains no KAH invocation, shell execution, network access, or
game/rig integration.

`guarded_approach(read_snapshot, issue_leg, ...)` requires the caller to bind
the expected player and target identities. Before each one-axis leg it obtains
a new player/target coordinate snapshot, rejects missing, stale, future-dated,
non-finite, or mismatched data, and compares 3D raw world-unit distance to 80.
An in-range target returns without calling `issue_leg`. Each proposed x/z leg
is bounded to KAH's 2..500 unit command limits; the next leg cannot be
considered until a new snapshot passes all checks. Use `walktime_arguments`
to get argument tokens such as `walktime @player 206 +x walk`; it formats but
does not execute or transport a command. Do not concatenate untrusted input
into shell text.

For KAH, record a monotonic `started_at` immediately before the first read,
then read `where @player` and `where <exact target handle>` and record
`captured_at` immediately after the second response. Keep the intended target
handle fixed across reads; reject a changed handle or missing position. The
guard requires the acquisition interval and the age of its start and completion
to each be at most two seconds, so a slow first read cannot be made to look
fresh by stamping only after the second response. Call the guard before issuing
one leg. The next leg requires a new pair of reads. Never reuse a cached leg.

Run the synthetic regression from this directory with:

```powershell
python -m unittest -v test_approach_guard.py
```

The fixture models the stale-script reproduction (target at 57 raw units) and
proves zero movement callbacks. It also checks 79.9/80/80.1, the target
entering range between legs, identity drift, missing/stale snapshots, and
bounded revalidation.
