# data/ manifest: what every file is, where it came from, how many

All of `data/` was COPIED (not linked) from the original run folders on 2026-10-16/17. Nothing was edited except where a row below says so.
Total size: about 8.9 MB (7.6 MB of the replay and context data plus the 1.3 MB replay2 grading copy). No logs, no secrets or API keys, nothing from the
live server tree or database. A pattern scan for keys/passwords over `data/` found nothing. Paths below are the ORIGINAL Windows locations on the machine
that ran the tests; they are given only so the provenance can be checked, you do not need them.

Terms used in this file are defined in `../README.md` section "Terms".

## replay/  (offline replay, the two baseline arms H = Haiku High and S = Sonnet High)
Original folder: `C:\KenshiTestRuns\shadow\replay\`. Method: `../02-offline-replay-suite.md`. Numbers: `../04-baselines.md`.
| path (under data/replay/) | count | what it is |
|---|---|---|
| `points/P001..P120.input.md` | 120 | the exact prompt each model saw for one decision point (preamble, output schema, handoff text, preceding conversation, event batch) |
| `points/P001..P120.truth.json` | 120 | the real coordinator's actual actions for that point, event class, outcome label (good/corrected/bad) |
| `INDEX.csv` | 1 | one row per point: id, session, class, estimated tokens, outcome label, timestamp, number and types of the real actions |
| `outputs/H/P###.json` | 120 | arm H (Haiku High) decision JSON per point (original: `runs\ra\`) |
| `outputs/S/P###.json` | 120 | arm S (Sonnet High) decision JSON per point (original: `runs\rb\`) |
| `runs.tsv` | 1 (240 rows) | token counts and USD per run, taken from the agent transcripts; the ONLY source for baseline cost figures (cannot be recomputed, see 04) |
| `mech.json`, `mech.csv` | 2 | scripted checks per candidate as run in the baseline (syntax, paths, forbidden targets, claims, briefs) |
| `grading/chunk-01..15.md` | 15 | the 15 blind grader packets (8 points each, candidates A/B). They contain the ORIGINAL absolute input paths `C:\KenshiTestRuns\shadow\replay\points\...`; the same files are in `points/` |
| `grading/out/chunk-01..15.json` | 15 | the grades the 15 graders returned (the record of the baseline grading) |
| `grading/key.json` | 1 | SECRET blind key: point -> which arm was A and which was B. Never show a grader. |
| `aggregate.md` | 1 | the baseline results (title says "Coordinator replay: aggregate") |
| `README.md`, `EXECUTOR_PROMPT.md` | 2 | the original Claude Code recipe and the prompt of the executor agent. Provenance only: they need Claude Code Agent calls. Use `../05-runbook-new-model.md` instead. |

## replay2/  (variants: Haiku pair, Draft-review, Guard rails)
Original folder: `C:\KenshiTestRuns\shadow\replay2\`. Method: `../03-replay2-variants.md`.
| path (under data/replay2/) | count | what it is |
|---|---|---|
| `final/pair/P###.json` | 120 | final decision of the Haiku pair arm |
| `final/dr/P###.json` | 120 | final decision of the Draft-review arm |
| `final/gr/P###.json` | 120 | final decision of the Guard rails arm (after the mechanical post-filter) |
| `grading/chunk-01..15.md`, `grading/out/chunk-01..15.json`, `grading/key.json` | 15 + 15 + 1 | blind packets with THREE candidates (A/B/C) per point, the grades, and the secret key. NOT scoreable with `score.py aggregate` (which handles two arms); shipped as the record. |
| `aggregate.md` | 1 | the five-arm comparison (baselines H and S copied in from `replay/aggregate.md`) |
| `cost.md`, `cost.json`, `cost-points.csv` | 3 | tokens and USD of the three new arms, per arm and per point |
| `runs2.tsv`, `graders.tsv` | 2 | per-call usage of the new arms; usage of the 15 graders |
| `mech.csv` | 1 | scripted checks of the new arms' finals |
| `guard-log.jsonl` | 1 | one line per action the guard-rails post-filter rejected (51 records) |
| `INTERIM.md`, `headless-test-report.txt` | 2 | notes of an aborted attempt to run the arms through a headless CLI; read only for history |

## live-shadow/  (38 batches of a LIVE coordinator session, H vs S in parallel, 2026-10-16 15:49-16:47)
Original folder: `C:\KenshiTestRuns\shadow\` (feed, ledgers and transcripts NOT copied: they hold unredacted session text). Pointers only in `../01-overview.md`.
| path | count | what it is |
|---|---|---|
| `live-shadow/README.md` | 1 | how the live feeder/shadow kit worked (Claude Code specific; provenance) |
| `live-shadow/LIVE_SHADOW_RESULTS.md` | 1 | the result write-up of that run (original file name `REPORT.md`, renamed on copy) |
| `live-shadow/live-grading/aggregate.md`, `cost.json`, `key.json` | 3 | aggregate table, cost, secret blind key |
| `live-shadow/live-grading/chunk-01..05.md`, `out/chunk-01..05.json` | 5 + 5 | blind packets (38 points) and their grades |
| `live-shadow/live-grading/points/L01..L38.input.md/.truth.json` | 76 | the 38 live points in the same format as the replay points |

## ab2/  (lane-operator pilot: Haiku High vs Sonnet High running the same game-test rows)
Original folder: `C:\KenshiTestRuns\pilot\ab2\`. Pointers only in `../01-overview.md`; it needs a running game lane and is not re-runnable from this package.
| path | what it is |
|---|---|
| `ab2/COMPARISON.md` | the result table and the INTERIM STATUS paragraph (source of truth for ab2 numbers) |
| `ab2/README.md`, `brief.md` | design and the operator brief template |
| `ab2/plan.json`, `state.json` | frozen plan (seed 20261016, order, baseline hashes) and the run states |

## context/
| path | what it is |
|---|---|
| `context/CLAUDE.md` | the project rules file the replay prompts refer to ("the standing project rules you already know (CLAUDE.md)"). This is the repo copy at git `dc307389` (2026-10-16 11:18), NOT the version of each original session. The baseline replay agents also had two further files auto-loaded that cannot be shipped (see `../04-baselines.md`, "fidelity differences"). |
| `context/prices-claude.json` | the Claude price table used for every cost figure (USD per million tokens; see `../05-runbook-new-model.md` section 8) |
| `context/workspace-paths.txt` | 1.1 MB list (lower-case, forward slashes) of files and folders that existed in the workspace when the package was built; `score.py mech --fs-list` uses it for the "invented path" check |

## investigation/  (templates of the investigation suite; the suite itself is in `../2026-10-15-investigation-suite/`)
| path | what it is |
|---|---|
| `investigation/task.tmpl` | wrapper for a read-only investigation run on the live world |
| `investigation/task-frozen.tmpl` | the same wrapper for the frozen world (Codex matrix) |
| `investigation/suite.json` | the example suite definition from `tools/model-test/templates/` |
Both templates mention a Claude agent definition file (`kenshi-debugger.md`) and workspace paths; for another tool, delete the "First read ..." line and keep the rest.

## Left out on purpose (and where it is)
| item | size | why |
|---|---|---|
| `shadow\replay\cands.jsonl`, replay2 `jobs\`, `runs\`, `plan\`, `headless\` | 22 MB + | generated job files and raw agent output, reproducible from `points/` and the scripts |
| `shadow\feed.jsonl`, `ledger-H/S.jsonl`, `real-actions.jsonl` (live shadow) | several MB | raw live session text, not reviewed for private content |
| frozen world `C:\KenshiTestRuns\invest\frozen-2026-10-14` | 1.3 GB (server 397 MB, logs 922 MB, native 6.3 MB, database `stobe_frozen` 453 MB inside the PostgreSQL instance) | needed only for the investigation suite; see `../01-overview.md` section "Frozen world" |
| Codex run transcripts `2026-10-15-investigation-suite/reports/codex/` (not in git) | about 290 MB | ignored by `.gitignore`; only the prepared suite files are tracked |
| Claude session transcripts (`C:\Users\<user>\.claude\projects\...`) | many | source of the points and of all token counts; private; not shipped |
