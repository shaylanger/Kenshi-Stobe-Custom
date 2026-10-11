#!/bin/bash
# row.sh (inside the dry-run sandbox, see sandbox.sh): prepare the row like run-batch.sh does, run its command, wait for
# detached children (4080 itrun jobs), print the exit code. Output -> /drout/out.txt
cd /root
# fork server (lib/forksrv.py + lib/forkcli.c, speed-scout 2026-10-11): every stobe-auto call forks a preloaded kahstub
# instead of starting python (~30 -> ~9 ms per call, ~3000 calls in a crossbow row); DR_NOFORK=1 or the file /root/.cache/kah-dryrun/nofork = off (DR_FORK=1 = on despite the file: selftest). Any failure =
# the plain python wrappers sandbox.sh wrote stay in place.
FSP=""
if [ -z "${DR_NOFORK:-}" ] && { [ -n "${DR_FORK:-}" ] || [ ! -e /root/.cache/kah-dryrun/nofork ]; } && [ -f /dryrun/lib/forksrv.py ] && [ -f /dryrun/lib/forkcli.c ]; then
  FC=/root/.cache/kah-dryrun/forkcli
  cmp -s /dryrun/lib/forkcli.c /root/.cache/kah-dryrun/forkcli.c && [ -x "$FC" ] || { FC=/drstate/forkcli; gcc -O2 -o "$FC" /dryrun/lib/forkcli.c 2>/dev/null || FC=""; }
  if [ -n "$FC" ]; then
    /usr/bin/python3 /dryrun/lib/forksrv.py /drstate/fork.sock /dryrun/lib/kahstub.py > /drstate/forksrv.out 2>&1 < /dev/null & FSP=$!
    for _ in $(seq 150); do grep -q READY /drstate/forksrv.out 2>/dev/null && break; /bin/sleep 0.02; done
    if grep -q READY /drstate/forksrv.out 2>/dev/null; then
      for w in /dryrun/bin/stobe-auto /usr/local/bin/stobe-auto; do printf '#!/bin/sh\nexec %s /dryrun/lib/kahstub.py "$@"\n' "$FC" > "$w"; done
    else kill "$FSP" 2>/dev/null; FSP=""; fi
  fi
fi
echo "forksrv: $([ -n "$FSP" ] && echo "on ($FC)" || echo off) $(head -c 200 /drstate/forksrv.out 2>/dev/null | grep -v READY)" > /drout/fork.txt
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
# dialog guard exactly like run-batch.sh (tools/automation/dialog-guard.sh): close an open conversation before the row
# (still open = setup FAIL), watch during it; DIALOG_GUARD=0 in the row = off. The watcher polls the stub every 2 s, so it
# only runs when the fixture has conversations (fixtures/dialog.json), else the check alone
DG=/mnt/c/KenshiModding/tools/automation/dialog-guard.sh; [ -f "$DG" ] || DG=/c/KenshiModding/tools/automation/dialog-guard.sh
dgw=""
if [[ " ${envs[*]} " != *" DIALOG_GUARD=0 "* ]] && [ -f "$DG" ]; then
  dg=$(bash "$DG" check 2>&1); dgr=$?; echo "dialog-guard check: $dg" >> /drout/prep.txt
  if [ $dgr != 0 ]; then echo "RESULT ${DR_NAME:-row} FAIL setup: dialog ${dg#DIALOG stuck } (before the row)" > "$O"; echo 1 > /drout/rc.txt; exit 0; fi
fi
RESULT_LOG=/drout/out.txt timeout "$DR_TO" "${run[@]}" > "$O" 2>&1 < /dev/null &
rp=$!
if [[ " ${envs[*]} " != *" DIALOG_GUARD=0 "* ]] && [ -f "$DG" ] && grep -q '"dialog"' "${DR_FIXTURE_JSON:-/dev/null}" 2>/dev/null; then
  bash "$DG" watch "$rp" /drout/dialogs.txt >/dev/null 2>&1 </dev/null & dgw=$!; fi
wait "$rp"; rc=$?
[ -n "$dgw" ] && { kill "$dgw" 2>/dev/null; wait "$dgw" 2>/dev/null; }
[ -s /drout/dialogs.txt ] && echo "dialog guard: $(paste -sd';' /drout/dialogs.txt | cut -c1-300)" >> /drout/prep.txt
# detached children (itrun): wait for them, their logs are part of the row
if [ -f /drstate/children.jsonl ]; then
  e=$((SECONDS + DR_TO))
  while [ $SECONDS -lt $e ] && python3 -c "import json,os,sys; sys.exit(0 if any(os.path.exists('/proc/%d' % json.loads(l)['pid']) for l in open('/drstate/children.jsonl')) else 1)"; do /bin/sleep 0.2; done
  python3 -c "import json; [print(json.loads(l)['log']) for l in open('/drstate/children.jsonl')]" | while IFS= read -r l; do
    echo "--- itrun child log $l"; cat "$l" 2>/dev/null; done >> "$O"
fi
echo "$rc" > /drout/rc.txt
[ -n "$FSP" ] && kill "$FSP" 2>/dev/null
