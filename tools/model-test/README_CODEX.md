# Codex investigation-suite adapter

This adapter prepares and records Codex-only investigations from an existing
frozen-world `suite.json`. It does not launch work by default. Keep the
Codex-model suite's `concurrency.default` at 1, `limited_concurrency` at 2,
`auto_start` false, and `concurrency.hard_cap` at 4 unless the operator
intentionally changes them.

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

### Isolated execution preflight

The runner uses the bundled Code Mode host because these catalog entries require
the `code_mode_only` execution transport. Its nested tool namespace excludes
`functions`, `clock`, Codex Apps, and plugins; the nested host inventory must
contain exactly the four frozen MCP tools (`list`, `read`, `search`, `sql`).
The outer `exec` transport is recorded separately from those nested calls.
The Code Mode host must expose no operating-system, network, or process globals,
and its agent APIs must be undefined. Native hooks are disabled because the
pinned CLI supplies hook stdin as a character device with no event payload;
hook enforcement is recorded as `UNAVAILABLE`, never as a pass. The independent
boundary is verified with an offline loopback-provider hostprobe: exact nested
frozen-tool inventory and callables, a successful frozen MCP call, rejection of
an unknown parameter, and no delegation APIs. Only the four enabled frozen MCP
tools use the server-scoped `approve` mode; global approval remains `never` and
the sandbox remains read-only. The probe uses a dummy
credential, never starts a paid model request, and records receipt hashes under
the ignored `operator-runtime/` directory. Each launch binds the proof hash to
its private config and then audits the root rollout and child-session scan.
Historical failed attempts remain unchanged; only untouched `PREPARED`
profiles may be refreshed.

The companion runner interface is:

```text
python tools/model-test/codex_bench.py prepare <suite-dir>
python tools/model-test/codex_bench.py preflight <suite-dir>
python tools/model-test/codex_bench.py run <suite-dir> <run-id> --execute [--mode sequential|limited-concurrent] [--concurrency 1..4] [--attempt N] [--timeout SECONDS]
python tools/model-test/codex_bench.py run <suite-dir> --all --execute [--mode sequential|limited-concurrent] [--concurrency 1..4] [--timeout SECONDS]
python tools/model-test/codex_bench.py status <suite-dir> [--metrics]
python tools/model-test/codex_bench.py record <suite-dir> <run-id>
python tools/model-test/codex_bench.py recheck <suite-dir> <run-id>
```

Only the explicit `run ... --execute` action launches a paid model task.
Preparation, preflight, and status are non-execution steps. `--mode sequential`
forces one active launch and rejects `--concurrency` above 1.
`--mode limited-concurrent` uses `limited_concurrency` (default 2), or an explicit
`--concurrency`, bounded by the suite hard cap (maximum 4). With no `--mode`,
the runner remains sequential unless a legacy `--concurrency` above 1 is given;
the legacy flag still opts into bounded concurrency. `auto_start` must remain
false. The `--all` form submits IDs in `order.txt` order; concurrent completion
order can differ. Each invocation writes a uniquely named batch launch-context
sidecar, and each run/attempt receipt records the selected mode, effective cap,
and batch ID, including failed attempts. `status` displays mode and cap. These
fields stay outside participant prompts and the 23-column report TSV. Sequential
runs reduce interference from this suite, but other host processes can still
affect wall times; speed comparisons are most useful while the host is quiet.
The runner does not automatically stop unrelated processes or gate on CPU load.
`--attempt` applies to a single run ID only; retries must use
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

