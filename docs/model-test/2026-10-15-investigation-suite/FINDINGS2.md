# Suite 2 findings: 3 models x 4 effort levels x 3 prompts, single agent each, no cascade

36 runs (Haiku 5.5, Sonnet 5.5, Opus 5.5; low, medium, high, xhigh = "extra"; Fable never used), same prompt text and wrapper as suite 1, run in the order haiku, sonnet, opus / low to xhigh / prompt 1 to 3. Quality = rubric score out of 25 (5 criteria), averaged over two blind judges (Sonnet high and Opus high; both scored all 14 anonymous reports per prompt = the 12 new + suite 1's A and B, and checked claims against live code, logs and database). Judges agree (r = 0.92) and neither favoured its own family (each was a little harsher on its own).

| Config | Quality /25 | Cost per task | Time per task | False claims per task |
|---|---|---|---|---|
| haiku-low | 14.7 | $0.03 | 1.4 min | 0.8 |
| haiku-medium | 15.3 | $0.10 | 3.0 min | 1.2 |
| haiku-high | 19.0 | $0.27 | 4.8 min | 1.2 |
| haiku-xhigh | 22.3 | $0.74 | 10.7 min | 0.5 |
| sonnet-low | 14.3 | $0.26 | 1.2 min | 0.8 |
| sonnet-medium | 17.3 | $0.36 | 2.5 min | 1.0 |
| sonnet-high | 21.3 | $0.66 | 4.4 min | 0.7 |
| sonnet-xhigh | 24.7 | $1.39 | 9.4 min | 0.0 |
| opus-low | 18.2 | $0.70 | 2.6 min | 0.8 |
| opus-medium | 22.7 | $1.09 | 4.1 min | 0.7 |
| opus-high | 22.0 | $1.49 | 5.5 min | 0.7 |
| opus-xhigh | 22.8 | $3.78 | 13.8 min | 0.7 |
| suite 1 B (sonnet medium solo) | 17.3 | $0.43 | 2.2 min | |
| suite 1 A (cascade: Haiku investigate + Sonnet verify) | 21.5 | $1.11 | 19.0 min | |

Totals: 36 runs cost $32.67 (token cost at official prices, graders and coordinator excluded) and 190 agent-minutes. By model: Haiku 17.8, Sonnet 19.4, Opus 21.4. By effort: low 15.7, medium 18.4, high 20.8, xhigh 23.3. Effort moves quality more than model does.

Best per prompt (average of both judges): prompt 1 sonnet-xhigh 25.0, opus-xhigh 24.5; prompt 2 sonnet-xhigh 24.5, opus-high 24.0; prompt 3 sonnet-xhigh 24.5, opus-medium 24.0. Reports: `runs\<config>-p<n>\report.md`; scores in `grades\`.

Recommendation: opus-medium for a fast strong answer (22.7, $1.09, 4 min); sonnet-xhigh for the best answer (24.7, 0 false claims, $1.39, 9 min); haiku-high ($0.27, 19.0) or haiku-xhigh ($0.74, 22.3) for cheap. Avoid low effort and sonnet-medium (14 to 17). The cascade (21.5, $1.11, 19 min) was no better than a single opus-medium or haiku-xhigh run. Raising Opus above medium bought nothing (22.0 and 22.8 at 1.4x and 3.5x the cost).

Caveats: 3 prompts, one run per cell, so per-config means carry roughly +/-3 points (single prompts swing up to 10: haiku-high 12.5 vs 22.5). Quality is judged on evidence and fix specificity, not by applying the fixes in game. Whole-percent quota readings are too coarse per run (5-hour window 0% to 9% over the suite including coordinator overhead; weekly 2% to 4%). 17 of 36 runs tripped the mutating-command heuristic; the ones I saw were reads or scratch files in /tmp. Sonnet-medium reproduced its suite-1 score exactly (17.3 both times).
