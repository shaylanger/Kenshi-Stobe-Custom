#!/usr/bin/env bash
# waker-persist.sh (PI-51, Shay 2026-10-16)   WSL.   ONE persistent waker: no more "wake, read output, restart waker".
#   waker-persist.sh watch  [--me coordinator] [--batch <out-dir>] [--backstop s] [--poll s] [--no-health] [--replay N]
#       THE command to hand to the Monitor tool (or Bash run_in_background): makes sure the daemon runs (idempotent: a second call
#       never starts a second one) and then streams the events file (`tail -F`), one actionable event per line. Each line is one notification.
#       Restarting it is harmless (the daemon keeps running; --replay N shows the last N old lines first, default 0).
#   waker-persist.sh start  [same options]   ensure the daemon runs, print one status line, return
#   waker-persist.sh status [--me x]         one line: RUNNING pid=.. hb_age=..s events=.. | NOT-RUNNING
#   waker-persist.sh set-batch <out-dir|none> [--me x]   point the batch health check at another batch (the daemon restarts its inner wait)
#   waker-persist.sh stop   [--me x]         ask the daemon to end (stop flag), then kill it if it does not
#   waker-persist.sh run    [same options]   the daemon in the foreground (what `start` launches with setsid; do not use by hand)
# What it does: loops event-wait.sh (UNCHANGED, all detection / digest / quiet-filter / backstop semantics live there; EW_* env is passed on) and appends
# every event it prints to $KAH_RUNS/waker/events.log (for --me coordinator; events-<me>.log otherwise) as '<iso time> EVENT ...'. The digest's
# '  - kind: text' lines are folded into the DIGEST line. A backstop wake whose sweep is clean ('SWEEP CLEAN') is not an event: it goes to waker/quiet.log.
# Liveness (what kenshi-waker-guard.ps1 checks): waker/<me>.hb is rewritten every ~2 s by the daemon loop itself ('pid=.. epoch=.. me=.. child=..'),
# so a fresh heartbeat (< 150 s) proves the loop is alive. Single instance: flock on waker/<me>.lock (+ waker/<me>.pid); a second daemon exits at once.
# Refuses to start while a stand-alone `event-wait.sh` for the same inbox runs (two wakers would eat each other's inbox messages) unless WP_FORCE=1.
# Test seams: KAH_RUNS (root), WP_EVENTWAIT (script to loop instead of event-wait.sh), WP_HB_EVERY (s, default 2), WP_MAX_HOURS (default 12).
set -u
CMD=${1:-}; [ $# -gt 0 ] && shift
ME=coordinator; BATCH=""; EWARGS=(); REPLAY=0; EXTRA=()
while [ $# -gt 0 ]; do
  case "$1" in
    --me) ME="$2"; shift 2;;
    --batch) BATCH="$2"; shift 2;;
    --backstop|--poll) EWARGS+=("$1" "$2"); shift 2;;
    --no-health) EWARGS+=("$1"); shift;;
    --replay) REPLAY="$2"; shift 2;;
    *) EXTRA+=("$1"); shift;;
  esac
done
R=${KAH_RUNS:-/mnt/c/KenshiTestRuns}
HERE=$(cd "$(dirname "$0")" && pwd)
W="$R/waker"; mkdir -p "$W"
HB="$W/$ME.hb"; PIDF="$W/$ME.pid"; LOCK="$W/$ME.lock"; BATCHF="$W/$ME.batch"; STOPF="$W/$ME.stop"; OUT="$W/$ME.out"
if [ "$ME" = coordinator ]; then EV="$W/events.log"; else EV="$W/events-$ME.log"; fi
EW=${WP_EVENTWAIT:-$HERE/event-wait.sh}
iso() { date +%Y-%m-%dT%H:%M:%S; }
hb_age() { [ -f "$HB" ] || { echo 99999; return; }; local e; e=$(sed -n 's/.*epoch=\([0-9]*\).*/\1/p' "$HB" | head -1); [ -n "$e" ] && echo $(( $(date +%s) - e )) || echo 99999; }
is_running() { local a; a=$(hb_age); [ "$a" -lt 150 ]; }
emit() { printf '%s %s\n' "$(iso)" "$*" >> "$EV"; }   # one line = one event (O_APPEND: whole short lines are atomic)

case "$CMD" in
  status)
    if is_running; then echo "WAKER RUNNING me=$ME $(tr -d '\n' < "$HB") hb_age=$(hb_age)s events=$EV lines=$(wc -l < "$EV" 2>/dev/null || echo 0)"; exit 0
    else echo "WAKER NOT-RUNNING me=$ME (hb_age=$(hb_age)s)"; exit 1; fi;;
  set-batch)
    b=${EXTRA[0]:-}; [ -n "$b" ] || { echo "usage: waker-persist.sh set-batch <out-dir|none> [--me x]" >&2; exit 2; }
    if [ "$b" = none ]; then rm -f "$BATCHF"; else printf '%s\n' "$b" > "$BATCHF"; fi
    echo "WAKER batch for $ME set to $b (the daemon restarts its inner wait within ~2 s)"; exit 0;;
  stop)
    : > "$STOPF"
    dp=$(cat "$PIDF" 2>/dev/null)
    for _ in $(seq 1 20); do { [ -n "$dp" ] && kill -0 "$dp" 2>/dev/null; } || break; sleep 0.5; done
    if [ -n "$dp" ] && kill -0 "$dp" 2>/dev/null; then kill "$dp" 2>/dev/null; sleep 1; kill -9 "$dp" 2>/dev/null; fi
    rm -f "$STOPF" "$HB" "$PIDF"; echo "WAKER stopped me=$ME"; exit 0;;
  start|watch)
    [ -n "$BATCH" ] && printf '%s\n' "$BATCH" > "$BATCHF"
    if is_running; then
      echo "WAKER already running (no second one started): $(tr -d '\n' < "$HB")" >&2
    else
      # a stand-alone legacy waker for the same inbox would race the daemon for inbox files
      if [ "${WP_FORCE:-0}" != 1 ] && pgrep -f 'bash .*event-wait\.sh' >/dev/null 2>&1; then
        legacy=$(pgrep -f 'bash .*event-wait\.sh' | tr '\n' ' ')
        if [ -z "${WP_EVENTWAIT:-}" ]; then
          echo "WAKER REFUSED: a stand-alone event-wait.sh is running (pid $legacy). Let it end (it wakes on the next event) or kill it, then start again. WP_FORCE=1 overrides." >&2
          exit 3
        fi
      fi
      rm -f "$STOPF"
      setsid nohup bash "$0" run --me "$ME" ${EWARGS[@]+"${EWARGS[@]}"} >> "$OUT" 2>&1 < /dev/null &
      for _ in $(seq 1 20); do sleep 0.5; is_running && break; done
      is_running || { echo "WAKER FAILED to start (see $OUT)" >&2; tail -3 "$OUT" >&2; exit 4; }
      echo "WAKER started: $(tr -d '\n' < "$HB")" >&2
    fi
    if [ "$CMD" = start ]; then echo "WAKER RUNNING events=$EV"; exit 0; fi
    touch "$EV"
    exec tail -n "$REPLAY" -F "$EV";;
  run) ;;
  *) echo "usage: waker-persist.sh watch|start|status|set-batch|stop [--me name] [--batch dir] [--backstop s] [--poll s] [--no-health] [--replay N]" >&2; exit 2;;
esac

# ---------------- daemon ----------------
exec 9> "$LOCK"
if ! flock -n 9; then echo "$(iso) another waker daemon holds $LOCK; exiting" >&2; exit 0; fi
echo $$ > "$PIDF"
STARTED=$(date +%s); MAXS=$(( ${WP_MAX_HOURS:-12} * 3600 )); HBE=${WP_HB_EVERY:-2}
CHILD=0; OUTF=$(mktemp)
beat() { printf 'pid=%s epoch=%s me=%s child=%s started=%s\n' "$$" "$(date +%s)" "$ME" "$CHILD" "$STARTED" > "$HB.tmp" && mv -f "$HB.tmp" "$HB"; }
cleanup() { [ "$CHILD" -gt 0 ] && kill "$CHILD" 2>/dev/null; rm -f "$OUTF"; [ "$(cat "$PIDF" 2>/dev/null)" = "$$" ] && rm -f "$HB" "$PIDF"; emit "WAKER stopped (pid $$)"; }
trap cleanup EXIT; trap 'exit 0' TERM INT
emit "WAKER started pid=$$ me=$ME"
rotate() { [ -f "$EV" ] && [ "$(stat -c %s "$EV")" -gt 1048576 ] && { mv -f "$EV" "$EV.1"; : > "$EV"; }; }
# process one event-wait output: fold digest items, drop a clean backstop
process_out() {
  local f=$1 txt
  [ -s "$f" ] || return 1
  txt=$(tr -d '\r' < "$f")
  if printf '%s\n' "$txt" | grep -q '^EVENT BACKSTOP' && printf '%s\n' "$txt" | grep -q 'SWEEP CLEAN' && ! printf '%s\n' "$txt" | grep '^SWEEP ' | grep -qv '^SWEEP CLEAN'; then
    printf '%s\t%s\n' "$(iso)" "clean backstop: $(printf '%s' "$txt" | tr '\n' ' ' | cut -c1-200)" >> "$W/quiet.log"; return 0
  fi
  printf '%s\n' "$txt" | awk '/^[ \t]+- /{sub(/^[ \t]+- /,""); buf = buf " ;; " $0; next} {if (have) print buf; buf=$0; have=1} END{if (have) print buf}' \
    | while IFS= read -r line; do [ -n "$line" ] && emit "$line"; done
  return 0
}
nap() { sleep "$1" 9>&- & wait $!; }   # interruptible by the TERM trap (a plain foreground sleep would delay it)
fails=0; lastb=""; nb=""
while :; do
  rotate
  [ -f "$STOPF" ] && { emit "WAKER stop flag seen"; rm -f "$STOPF"; exit 0; }
  [ $(( $(date +%s) - STARTED )) -ge "$MAXS" ] && { emit "WAKER max-hours reached, ended (restart: waker-persist.sh watch)"; exit 0; }
  b=""; [ -f "$BATCHF" ] && b=$(head -1 "$BATCHF" | tr -d '\r\n'); lastb=$b
  args=(${EWARGS[@]+"${EWARGS[@]}"}); [ -n "$b" ] && args+=(--batch "$b")
  : > "$OUTF"; t0=$(date +%s)
  bash "$EW" --me "$ME" ${args[@]+"${args[@]}"} > "$OUTF" 2>>"$OUT" 9>&- &
  CHILD=$!; beat
  restart_inner=0
  while kill -0 "$CHILD" 2>/dev/null; do
    nap "$HBE"; beat
    if [ -f "$STOPF" ]; then kill "$CHILD" 2>/dev/null; break; fi
    nb=""; [ -f "$BATCHF" ] && nb=$(head -1 "$BATCHF" | tr -d '\r\n')
    if [ "$nb" != "$lastb" ]; then restart_inner=1; kill "$CHILD" 2>/dev/null; break; fi
  done
  wait "$CHILD" 2>/dev/null; rc=$?; CHILD=0
  [ -f "$STOPF" ] && continue
  if [ "$restart_inner" = 1 ]; then emit "WAKER batch changed to '${nb:-none}', inner wait restarted"; continue; fi
  if process_out "$OUTF"; then fails=0
  else
    # no output: the inner wait crashed (a normal wake always prints). back off, and say so once it repeats
    fails=$((fails + 1))
    if [ "$fails" -ge 3 ]; then emit "EVENT WAKER-ERROR event-wait exited rc=$rc without output $fails times in a row (see $OUT); retrying every 30 s"; nap 28; fi
    nap 2
  fi
done
