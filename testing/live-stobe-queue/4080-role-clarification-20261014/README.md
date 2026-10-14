# 4080 i3 P0 leader-role clarification row

This is a new, separate live row for the existing Cind [Hungry Bandit] to The Hub case. It asks plainly whether Cind will lead while Shay follows, and instructs Cind to wait for Shay's acceptance. It preserves the original conditional acceptance text and sends it only after a complete, exact-speaker final response passes the existing narrow affirmative offer grammar. An ambiguous reply, a conditional or refusal, incomplete stream, or conflicting text for one utterance ID sends no acceptance.

The driver retains the existing exact actor and serial checks, isolated 4080 instance-3 path checks, unique atomic `OUT` claim, destination catalog binding, pre-accept no-action/order checks, identity/range/state rechecks, exactly one matching native travel start, and repeated same-actor movement samples (two consecutive intervals of at least 0.5 m and at least 5 m total progress). It does not weaken refusal or positive assertions. Arrival remains outside this row.

The response gate counts distinct `NPC_SAY` lines carrying `[UTTERANCEID:...]`. Untagged provisional lines do not count; a repeated ID counts once; differing visible speech for one ID is an evidence failure. The selftest includes the observed protocol shape of two untagged provisional records followed by two tagged final records under `CHAT_THREAD: Queued 2 ...`, plus incomplete, duplicate, conflicting, positive, conditional, and refusal assertions.

`body.sh` is regenerated from the validated r6 invocation recipe. It retains the source-compatible EAC727 legacy authorization gate, fresh receipts, `test_rig=4080` metadata, private 4080 i3 route, and child launch scoped to `MSYS2_ENV_CONV_EXCL='KENSHI_DIR;KDIR'`. Native header use remains `NOT_YET_PROVEN` until a correlated native HTTP/chat outcome. The body owns a timestamp/PID-specific receipt parent; the driver atomically claims its `run` directory.

The original frozen driver and r6 packet were not edited. This directory contains an independent copy with only this proposal wording, row identity, and final-utterance completion gate changed.

## Frozen pins

- `driver.py` SHA-256: `3A6070921D0AC1C7FD43066F90598452FE157B0874A5AF9E5A830B55ADB581B8`
- `driver.sh` SHA-256: `A0A8B8846FCA898483CE7206D992AD164082181AAD8219E916594A9F292F91E3`
- `body.sh` SHA-256: `D73669E0EE02E83187B4D21A30C3EE9E14AF66284963E47B88B46988A3BA261C`
- `selftest.py` SHA-256: recorded in `MANIFEST.sha256`

Selftest result: `RESULT ROLE-CLARIFICATION-SELFTEST PASS cases=7 actual-format=2-provisional+2-final unique-final-id-count=2`. Python compile and Bash syntax checks passed. This package has not been run against either rig.
