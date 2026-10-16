# Codex frozen investigation comparison

This is a prepared suite definition, not evidence of any model execution or
grading. It reuses the frozen 14 Oct world and the two fully testable original
requests, prompt 2 (Tengu identity/job reply) and prompt 3 (Mouse location and
travel loop). Prompt numbers and the 14 existing anchor-report paths are kept
so the blinded comparison remains aligned with the earlier suite.

## Matrix and order

There are 31 Standard configurations and 13 additional Fast configurations.
Each configuration runs once for each prompt: 44 configurations × 2 prompts =
88 runs. `order.txt` lists Standard cells first, followed by the additional
Fast cells, preserving model and effort order from `suite.json`; within each
configuration, p2 precedes p3.

The Standard effort set is low, medium, high, xhigh, ultra, subject to these
exclusions: GPT-6 Astra omits xhigh and ultra; GPT-6 Luna and GPT-5.6 Luna
omit ultra. The Fast additions are high and xhigh for both Luna models, and
high, xhigh, and ultra for GPT-6.1 Sol, GPT-6 Sol, and GPT-5.6 Sol. There are
no Fast Astra or Fast Terra configurations. The suite never uses max effort.

The runner uses `python tools/model-test/codex_bench.py` with `prepare`,
`preflight`, `run`, `status`, `record`, and `recheck` commands. `run` accepts
either `<run-id>` or `--all`, requires `--execute`, and supports
`--concurrency 1..4` and `--timeout SECONDS`. A single run ID also accepts
`--attempt N`; `--all` does not accept a retry attempt. The default attempt is
1 and the default timeout is 1800 seconds. `status --metrics` adds current
usage metrics.
The suite's default launch mode is sequential (one active launch); the named
`limited-concurrent` mode defaults to cap 2 and is bounded by the hard cap of 4.
An explicit `--concurrency 1..4` works with either mode, while sequential mode
rejects values above 1. With `--mode` omitted, no override stays sequential;
legacy `--concurrency` values above 1 infer limited-concurrent mode. The `--all`
command submits runs in `order.txt` order, though concurrency above 1 can change
completion order. Batch sidecars and run/attempt receipts record mode and cap;
status displays both, outside the unchanged participant prompt and report TSV.
Other host processes can still affect sequential wall times, so speed comparisons
are most useful while the host is quiet. There is no automatic CPU-load gate or
unrelated-process shutdown. Retries use the next explicit attempt number and
never overwrite previous attempt evidence. Each run is one independent task
with no delegation, including at ultra effort.

## Evidence and grading

The frozen copy is a reconstruction described in its README, not an exact
reproduction. Every investigation and every claim check must stay within the
frozen files and `stobe_frozen` database. Graders must verify at least five
load-bearing claims per report against that frozen evidence, mark unsupported
claims unverifiable, and never inspect the live system. The rubric's score
criteria are unchanged; its prompt-specific completeness requirements remain
the ones written before the original suite.

The prices file cites OpenAI's Codex/Work token rate card checked on
2026-10-16. It contains Standard and Fast token rates plus the long-context
threshold/multipliers; Astra has the documented Codex long-context exception
and no additional multiplier. The source has no separate cache-write rate.
The published USD rates apply to eligible token-based Enterprise agreements;
they are reference rates, not this account's actual subscription charge.
Actual billing may use another plan or credit system. Do not infer the account's
bill from those rates. If a delivered service tier cannot be established, mark
it `UNKNOWN`; do not infer the requested tier was delivered.

The recorder leaves `token_usd` blank and marks pricing unavailable when its
token data or rate is unavailable. It leaves audit state as `UNKNOWN` when
provenance is incomplete; `mt.py report` counts these separately from runs
with actual violation flags. Neither unknown pricing nor unknown audit state
is a pass or a zero value.

The original 12 model × effort reports and two suite-1 cascade reports remain
in `extra_reports` as anchors. This file contains no run reports, grades, keys,
findings, or conclusions.

No Codex model cells have been executed and no reports have been graded.

