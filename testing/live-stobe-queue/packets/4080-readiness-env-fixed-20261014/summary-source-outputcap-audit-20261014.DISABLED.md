# DISABLED forensic reconstruction — 4080 source audit collector

State: DO NOT EXECUTE. Original runnable path was removed after the accidental raw-source emission; exact shell body is not preserved byte-for-byte. Original observed wrapper-body SHA-256: `2582AF0F378419E85FC20634124B2CC0DE2D4C4BDC67FB38EEC527615275797F`.

Fault: the Python collector assigned the source text extracted from `stobeRegularMemoryGenerateSummaryFromPacked()` to variable `summary`, built the intended sanitized object in `summary_call`, then ended with `print(json.dumps(summary, separators=(',', ':')))`. It therefore emitted the extracted PHP function body—including prompt-template source—instead of the sanitized metadata object. The safe fix is a dedicated, unambiguous name for source text and to serialize only the literal sanitized metadata mapping; no source-text variable may flow to stdout.

No model, service, database, or game call and no runtime write occurred. The collector read source files through the approved read-only 4080 route. The accidental output exposed static prompt-template source, not a captured user prompt, model reply, API key, or environment value. It must still be treated as sensitive and not copied or repeated.

Before any future use, create a new reviewed body, then run local-only capture tests with sentinel text embedded in fake source. Assert exact output schema and prove sentinels resembling prompt text, response text, credentials, and arbitrary PHP strings never appear in stdout, stderr, or receipt artifacts. Hash-review the exact new body before any remote read.

Relevant verified source facts from separate sanitized audits only: live-matched `memory_helper_functions.php` SHA-256 `F37F7BA74AC5DC72FA12CD9C2CB36F1932531361A9449459900692C32DCD25D9`; the helper’s lock uses `pg_try_advisory_lock(937463)` and has no application-level PID/holder metadata. The latest audit-log snapshot identified completed requests through 18:04:18 UTC but no pending lock holder.
