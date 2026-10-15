#!/usr/bin/env bash
# lane.sh: lane table + transport for the imm26 row tools (go-row.sh / go-batch.sh / preflight.sh). Source it, then `lt_load <lane>`.
# Lanes: 5090-i3 5090-i4 5090-i5 4080-i3 4080-i4 (rig-iN). Transport reuses the routes of the *-imm26-lib.sh helpers:
#   lt_h   <<'EOF'  bash body on the lane's HARNESS route (stobe-auto = this lane; WSL on the 5090, Git Bash over ssh on the 4080)
#   lt_w   <<'EOF'  bash body in WSL root with the lane's private-backend env (psql, php)
#   lt_sql "select ..."  read SQL (psql -At -F '|') on the lane DB; lt_sqlx "stmt" = write statement
# Test switches (never touch a real lane): KAH_ROW_FAKE=1 -> no wsl/ssh; bodies are appended to $KAH_ROW_FAKE_LOG and answered by
# the shell function lt_fake <h|w|sql> "<body>" (defined by the caller; selftest.sh has a simulator). KAH_ROW_DRY=1 implies FAKE and
# makes go-row.sh print `RESULT <ROW> DRY-RUN ...` instead of a verdict. KAH_ROWS_BASE overrides C:/KenshiTestRuns for evidence dirs.
LT_DEFAULT_BASE=/c/KenshiTestRuns
lt_lanes() { echo "5090-i3 5090-i4 5090-i5 4080-i3 4080-i4"; }
lt_load() {
  LT_LANE="$1"
  case "$1" in
    5090-i3) LT_RIG=5090 LT_N=3 LT_ROOT=/tmp/stobe-imm26-5090    LT_PG=15437 LT_DB=stobe_imm26_5090    LT_PORT=18086 LT_DIR=imm26-5090-i3 ;;
    5090-i4) LT_RIG=5090 LT_N=4 LT_ROOT=/tmp/stobe-imm26-5090-i4 LT_PG=15438 LT_DB=stobe_imm26_5090_i4 LT_PORT=18087 LT_DIR=imm26-5090-i4 ;;
    5090-i5) LT_RIG=5090 LT_N=5 LT_ROOT=/tmp/stobe-imm26-5090-i5 LT_PG=15439 LT_DB=stobe_imm26_5090_i5 LT_PORT=18088 LT_DIR=imm26-5090-i5 ;;
    4080-i3) LT_RIG=4080 LT_N=3 LT_ROOT=/tmp/stobe-standalone4080    LT_PG=15434 LT_DB=stobe_standalone4080_test    LT_PORT=18084 LT_DIR=imm26-4080 ;;
    4080-i4) LT_RIG=4080 LT_N=4 LT_ROOT=/tmp/stobe-standalone4080-i4 LT_PG=15435 LT_DB=stobe_standalone4080_i4_test LT_PORT=18085 LT_DIR=imm26-4080-i4 ;;
    *) echo "PREFLIGHT-FAIL unknown lane '$1' (use: $(lt_lanes))"; return 2 ;;
  esac
  if [ "$LT_RIG" = 5090 ]; then LT_STOBELOG="/mnt/d/KenshiInst/$LT_N/RE_Kenshi/mods/Stobe/stobe.log"   # path as seen by the harness body (WSL)
  else LT_STOBELOG="/c/KenshiInst/$LT_N/RE_Kenshi/mods/Stobe/stobe.log"; fi                           # 4080 harness body = Git Bash
  LT_PROMPTLOG="$LT_ROOT/site/log/context_sent_to_llm.log"; LT_SRVLOG="$LT_ROOT/site/log/stobeserver.log"
  LT_BASE="${KAH_ROWS_BASE:-$LT_DEFAULT_BASE}"; LT_OUT="$LT_BASE/$LT_DIR/rows"
  [ -n "${KAH_ROW_DRY:-}" ] && KAH_ROW_FAKE=1
  return 0
}
lt_pre() {  # harness preamble (the body must start on its OWN line, see the *-imm26-lib.sh notes)
  if [ "$LT_RIG" = 5090 ]; then
    printf 'export RIG=5090 KAH_INSTANCE=%s\n. /mnt/c/KenshiModding/tools/automation/rig-env.sh\nif [ -e "$KDIR/mods/AutomationHarness/inbox.txt" ] || [ -e "$KDIR/mods/AutomationHarness/inbox.txt.lock" ]; then echo "STOP lane i%s harness inbox pending or locked" >&2; exit 3; fi\n' "$LT_N" "$LT_N"
  elif [ "$LT_N" = 3 ]; then
    printf 'export RIG=4080 KAH_INSTANCE=3\n. /c/KenshiModding/tools/automation/rig-env.sh\nrig4080_i3_preflight >/dev/null || exit $?\n'
  else
    printf 'export RIG=4080 KAH_INSTANCE=4\n. /c/KenshiModding/tools/automation/rig-env.sh\n[ "$KDIR" = /c/KenshiInst/4 ] || { echo "ROUTE-FAIL KDIR=$KDIR"; exit 2; }\n{ [ -e "$KDIR/mods/AutomationHarness/inbox.txt" ] || [ -e "$KDIR/mods/AutomationHarness/inbox.txt.lock" ]; } && { echo "STOP inbox pending or locked"; exit 3; }\n'
  fi
}
_lt_run() {  # _lt_run <h|w> : body on stdin
  local kind="$1" body; body=$(cat)
  if [ -n "${KAH_ROW_FAKE:-}" ]; then
    printf '### %s %s\n%s\n' "$kind" "$LT_LANE" "$body" >> "${KAH_ROW_FAKE_LOG:-/dev/null}"
    declare -F lt_fake >/dev/null && lt_fake "$kind" "$body"; return 0
  fi
  local tmo="${LT_TMO:-420}"
  if [ "$LT_RIG" = 5090 ]; then
    if [ "$kind" = h ]; then { lt_pre; printf '%s\n' "$body"; } | MSYS_NO_PATHCONV=1 timeout "$tmo" wsl.exe -d DwemerAI4Skyrim3 -u root --cd / -- bash -s
    else { printf 'source %s/env.sh\n%s\n' "$LT_ROOT" "$body"; } | MSYS_NO_PATHCONV=1 timeout "$tmo" wsl.exe -d DwemerAI4Skyrim3 -u root --cd / -- bash -s; fi
  else
    if [ "$kind" = h ]; then { lt_pre; printf '%s\n' "$body"; } | timeout "$tmo" ssh -o BatchMode=yes 4080 '"C:\Program Files\Git\bin\bash.exe" -l -s'
    else { printf 'source %s/env.sh >/dev/null 2>&1\n%s\n' "$LT_ROOT" "$body"; } | timeout "$tmo" ssh -o BatchMode=yes 4080 'wsl.exe -d DwemerAI4Skyrim3 -u root --cd / -- bash -s'; fi
  fi
}
lt_h() { _lt_run h; }
lt_w() { _lt_run w; }
_lt_psql() { printf "runuser -u postgres -- psql -h %s/socket -p %s -d %s -At -F '|' <<'EOQSQL'
%s
EOQSQL
" "$LT_ROOT" "$LT_PG" "$LT_DB" "$1"; }
lt_sql() {  # read (or write: output is the psql command tag) a statement; any quoting; sent as a heredoc
  if [ -n "${KAH_ROW_FAKE:-}" ]; then
    printf '### sql %s\n%s\n' "$LT_LANE" "$1" >> "${KAH_ROW_FAKE_LOG:-/dev/null}"
    declare -F lt_fake >/dev/null && lt_fake sql "$1"; return 0
  fi
  _lt_psql "$1" | _lt_run w
}
lt_sqlx() { lt_sql "$1"; }
lt_json() {  # extract JSON field by python from stdin: lt_json <key>   (first match)
  python3 -c 'import sys,re,json;t=sys.stdin.read();m=re.search(r"\"%s\": ?(\"[^\"]*\"|[-0-9.]+|true|false|null)"%sys.argv[1],t);print(json.loads(m.group(1)) if m else "")' "$1"
}
