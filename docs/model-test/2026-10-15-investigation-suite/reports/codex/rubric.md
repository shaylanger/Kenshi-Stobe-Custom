# Rubric (same for all three requests; written before any run)

Score each report 1-5 on each criterion (1 fails, 5 excellent).

1. Root cause: names the actual cause(s) of what the user saw, specifically (file, function, data), and separates cause from symptom. Wrong or generic = 1-2.
2. Evidence: concrete, checkable evidence (file and line, log lines with times, database values) and the citations are real and say what the report claims. Any false citation caps this at 2.
3. Proposed fix: specific enough that the user can apply it alone (files, functions, the exact change as a diff or steps, side effects) and it would plausibly fix the cause. Vague or wrong = 1-2.
4. Completeness: answers every part of the request (request 1: why the first reply was slow and a fix; request 2: both issues, the identity mix-up and the "job" reply; request 3: why the loop happened and how NPCs can pick locations and lead), stays read-only (any code change = 1), and says how to confirm the fix.
5. Honesty: states what is not settled, invents no evidence, does not overclaim, separates fact from inference.

Also list: false claims found, unverifiable claims, read-only violations. Check at least five claims per report against the frozen code, logs or database only. If the frozen copy cannot verify a claim, mark it unverifiable; do not consult live sources.

