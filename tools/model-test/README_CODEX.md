# Codex investigation-suite adapter

This adapter prepares and records Codex-only investigations from an existing
frozen-world `suite.json`. It does not launch work by default. Keep the
Codex-model suite's `concurrency.default` at 1, `auto_start` false, and
`concurrency.hard_cap` at 4 unless the operator intentionally changes them.

## Suite schema

Alongside the legacy `prompts`, `prompt_numbers`, `rubric`, `template`,
`frozen`, `judges`, and `extra_reports` keys, Codex suites use an ordered
`cells` array. Each cell has:

```json
{"slug":"gpt61sol-high-fast","model":"gpt-6.1-sol","effort":"high","speed":"fast"}
```

`model` is the exact runtime ID. `slug` is a unique path-safe identifier;
`speed` is `standard` or `fast`. Each cell expands in order to
`<slug>-pN`, using the matching `prompt_numbers` entry. Do not use a model ×
effort Cartesian product when the matrix has excluded combinations.

The investigation runner writes the final report to `runs/<run-id>/report.md`
and structured run metadata to the suite's `runs.tsv`. `mt.py blind` consumes
those reports and preserves `extra_reports` as grading anchors;
`mt.py report` uses the recorder's `run`, `token_usd`, `wall_s`, and
`violation_flags` columns. The recorder owns the full TSV schema and append
behavior. Do not run `mt.py rec` on Codex runs; it extracts Claude agent
transcripts. `mt.py report` accepts legacy numeric violation counts and
Codex `PASS`, `UNKNOWN`, or detailed flag strings. Unknown audit status is
reported separately from violations. Blank or unavailable cost/time remains
unavailable and is excluded from sums; it is never treated as zero.

## Launcher and lifecycle

The companion runner interface is:

```text
python tools/model-test/codex_bench.py prepare <suite-dir>
python tools/model-test/codex_bench.py preflight <suite-dir>
python tools/model-test/codex_bench.py run <suite-dir> <run-id> --execute [--concurrency 1..4] [--attempt N] [--timeout SECONDS]
python tools/model-test/codex_bench.py run <suite-dir> --all --execute [--concurrency 1..4] [--timeout SECONDS]
python tools/model-test/codex_bench.py status <suite-dir> [--metrics]
python tools/model-test/codex_bench.py record <suite-dir> <run-id>
python tools/model-test/codex_bench.py recheck <suite-dir> <run-id>
```

Only the explicit `run ... --execute` action launches a paid model task.
Preparation, preflight, and status are non-execution steps. Concurrency defaults
to 1, can be set from 1 to 4, and `auto_start` must remain false. The `--all`
form submits IDs in `order.txt` order; with concurrency above 1, completion
order can differ. `--attempt` applies to a single run ID only; retries must use
the next sequential attempt number. The default attempt is 1. The default
timeout is 1800 seconds. Preserve each
attempt under `runs/<run-id>/attempt-NN/`; a retry or recheck must not overwrite
earlier attempt evidence. `status --metrics` adds current usage metrics, while
plain `status` only reports saved run state. Before grading, confirm each
completed run has a canonical report and an appended ledger row; then use
`mt.py blind <suite-dir> --prompts 2,3` and `mt.py report <suite-dir> --prompts 2,3`.

## Prices

`codex_prices.json` records the published Codex/Work Enterprise token rates,
the source URL and check date, Fast multipliers, and the long-context
threshold. Astra has a Codex-specific exception: long-context use has no added
multiplier. The rate file marks cache-create pricing unavailable because the
source does not list a separate Codex rate. These are reference rates for
eligible token-based Enterprise agreements, not a statement of this account's
actual subscription charges. Reasoning effort does not change the per-token
price in the source rate card; it may change token use. A missing delivered
service tier is `UNKNOWN`, not inferred. A changed source rate must be
re-verified before updating this file.

