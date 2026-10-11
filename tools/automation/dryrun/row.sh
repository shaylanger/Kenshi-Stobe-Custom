#!/bin/bash
# row.sh (inside the dry-run sandbox, see sandbox.sh): prepare the row like run-batch.sh does, run its command, wait for
# detached children (4080 itrun jobs), print the exit code. Output -> /drout/out.txt
cd /root
echo "$(date +%s.%N)" > /drstate/t0; export DR_T0=$(cat /drstate/t0)
O=/drout/out.txt
{
  case "$DR_SAVEARG" in
    -|'') ;;
    home) stobe-auto load auto-home >/dev/null; stobe-auto select Shay >/dev/null ;;
    *) stobe-auto load "$DR_SAVEARG" | head -1; stobe-auto wait-world >/dev/null; stobe-auto select "$PLAYER" >/dev/null ;;
  esac
} > /drout/prep.txt 2>&1
# the row's words exactly like run-batch.sh's row_split (dryrun.sh already refused shell operators / bad quotes):
# quotes group a value with spaces (FIST_SPOT="1 2 3"), no expansion; then VAR=value words, a script (+ args)
set -f; eval "words=($DR_CMD)"; set +f; envs=(); i=0
while [ $i -lt ${#words[@]} ] && [[ "${words[$i]}" =~ ^[A-Za-z_][A-Za-z0-9_]*= ]]; do envs+=("${words[$i]}"); i=$((i + 1)); done
script="${words[$i]:-}"; args=("${words[@]:$((i + 1))}")
if [ "$DR_RIG" = 4080 ]; then
  # 4080 rows run like C:\KAH\itrun.ps1 + run-batch.sh run them: a fresh Git Bash login shell, rig-env.sh sourced, stdin
  # /dev/null; Git Bash runs a script file without an exec bit (the sandbox C: is noexec): same here through an explicit bash
  case "$script" in *.sh) set -- bash "$script" "${args[@]}" ;; *) set -- "$script" "${args[@]}" ;; esac
  run=(/bin/bash -c '. /c/KenshiModding/tools/automation/rig-env.sh; exec env "$@"' _ "${envs[@]}" "$@")
else
  # 5090 rows: relative = tests/ingame/stobe
  T=/mnt/c/KenshiModding/tests/ingame/stobe
  case "$script" in /*) ;; *) [ -e "$T/$script" ] && script="$T/$script" ;; esac
  case "$script" in
    *.sh) run=(env "${envs[@]}" bash "$script" "${args[@]}") ;;
    *) run=(env "${envs[@]}" "$script" "${args[@]}") ;;
  esac
fi
RESULT_LOG=/drout/out.txt timeout "$DR_TO" "${run[@]}" > "$O" 2>&1 < /dev/null
rc=$?
# detached children (itrun): wait for them, their logs are part of the row
if [ -f /drstate/children.jsonl ]; then
  e=$((SECONDS + DR_TO))
  while [ $SECONDS -lt $e ] && python3 -c "import json,os,sys; sys.exit(0 if any(os.path.exists('/proc/%d' % json.loads(l)['pid']) for l in open('/drstate/children.jsonl')) else 1)"; do /bin/sleep 0.2; done
  python3 -c "import json; [print(json.loads(l)['log']) for l in open('/drstate/children.jsonl')]" | while IFS= read -r l; do
    echo "--- itrun child log $l"; cat "$l" 2>/dev/null; done >> "$O"
fi
echo "$rc" > /drout/rc.txt
