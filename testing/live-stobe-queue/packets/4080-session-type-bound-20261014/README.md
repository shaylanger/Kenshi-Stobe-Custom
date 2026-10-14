# 4080 session type diagnostic bound to the private listener

Local-only candidate; not executed or authorized for remote execution yet. Wrapper: `tools/automation/remote-bash-stdin-4080.ps1`, SHA256 `138460C012FEBA82314D39013B60D1ADD6B060ACAB561A31C2DB045E894E7354`. Body `body.sh`, SHA256 `32F77C786C112C51CF11D2A47891EC14CB76C35B34FC0C8A89D7FC65C5B7EC6D`. Standard escalation/default config would be needed for an independently cleared call; no route/config/ACL changes.

Body derives from the existing type diagnostic candidate (`0E3527D5C9EADE65BC3C16A3C492B1926CAABEFDE9409C39BD45A8BF62D81EA3`) with local changes: exact exported wrapper preamble; PHP stdin without the invalid trailing `-`; Linux listener/root verification executed within the existing WSL distro before the PHP read; MSYS_NO_PATHCONV=1 follows the working stream route. The root stream preflight and its pins are unchanged.

Listener gate requires exactly one localhost18084 socket line with at least one owning PID. Every owning PID must have the exact fixed private PHP server argv for `/tmp/stobe-standalone4080/site`. Multiple legitimate workers sharing that listener are accepted; no argv is printed. Canonical root must equal that fixed root. PHP loads the fixed switching library, hashes ReflectionFunction ptr_query's file and runs only ptr_read PLAYTHROUGH_SESSION. It emits the previously defined one-line schema: PHP version, source hash, coarse argument role/index/type enums, result enum. It suppresses raw PHP output and exception messages. No game/actor/input/chat/save/install/queue/service action.

Fresh underlying readiness attempt receipt: `testing/live-stobe-queue/KAH-CHAT-007-4080-escalated-preflight-20261014.receipt.md`. It showed private18084 healthy and five server processes, then sanitized PHP subprocess failure; world/roster gates remain unknown.

Local `bash -n body.sh` passed. Runtime/PHP behavior is unverified; exact independent review and new Validator clearance remain required. The JSON stdout is the sole runtime payload; listener service-root evidence is enforced internally by the fail-closed fixed-root gate, not emitted as a separate metadata field.

Proposed exact invocation:

`powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File C:\KenshiModding\tools\automation\remote-bash-stdin-4080.ps1 -BodyPath C:\KenshiModding\testing\live-stobe-queue\packets\4080-session-type-bound-20261014\body.sh`

## Full transport guard repair

The previous body was rejected before SSH because its literal extra dot-source env.sh command matched the unchanged wrapper tail assertion. This revision does not source or evaluate env.sh; Python shlex parses only exported assignments and passes the five allowlisted STOBE_DB keys to the sudo PHP child via an explicit preserve list. HOST/PORT/NAME/USER are required; PASSWORD is optional as in the provisioning recipe. Unknown keys are ignored without execution. Selected values containing shell substitution, control characters, duplicates or unsupported syntax fail closed. The provisioned multi-assignment export line and unrelated activity-secret command substitution are covered by synthetic fixtures. Names derive from basic-ingame-smoke/standalone4080-provision.sh and current-archive-baseline/lib/playthrough_preferences.php.

This explicit DB environment differs from the earlier root stream reader, whose sudo call did not explicitly preserve the sourced DB environment. A successful read proves the corrected diagnostic environment works, not that the original reader was already correct.

Permanent local gate: `powershell.exe -NoProfile -ExecutionPolicy Bypass -File preflight-local.ps1` extracts and evaluates ONLY the exact pinned wrapper Assert-IsolatedI3Body function over the entire body, including tail; no wrapper entry point or transport. It reports PASS. `bash -n body.sh` passes. `python test-driver-local.py` runs three synthetic tests (provision shape, shell expression rejection, duplicate rejection); all pass, with subprocess fully mocked. Runtime PHP remains unverified.
