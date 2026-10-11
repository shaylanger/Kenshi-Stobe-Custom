#!/usr/bin/env bash
# labnice.sh [-s N] <command...>      (WSL) run an OFFLINE lab job at low priority with capped parallelism
# labnice.sh --renice <pgrep -f pattern>   move already running jobs (and their children) to nice 15 / ionice idle
# labnice.sh --status                       slots in use
# Why (Shay 2026-10-10): WSL load 60 on 32 cores from lab jobs (gate/regress/climbers/twohand) while a take's checks
# crawled and the game sat idle. Rule: offline lab jobs (climb, gate, regress, pool, kfp-pipeline, builds, backfill,
# mutation) run through this wrapper; take scripts and their own analysis run at normal priority (no wrapper).
#   - nice 15 + ionice idle class
#   - holds N (-s, default 1) of LABNICE_SLOTS slots (default nproc/2, all lab jobs together); waits for free slots
#     (flock on /tmp/labnice/slot.<i>). A job with internal parallelism takes as many slots as workers it starts
#     (e.g. labnice.sh -s 4 make -j4) and gets LABNICE_J=N to size its pool.
#   - nested calls (LABNICE_SLOT already set, e.g. gate.sh inside kfp-pipeline.sh) just run: no second slot, no deadlock
#   - thread caps for numpy/BLAS (OMP/OPENBLAS/MKL/NUMEXPR_NUM_THREADS=N) unless already set
#   - one lab CPU budget (Shay 2026-10-10, speed plan 7): LABNICE_SLOTS (default nproc/2 = 16) workers, LABNICE_REC_SLOTS
#     (default 12) while a 5090 take records: then new jobs take only slots 1..12 (a job wanting more starts at once with
#     12, LABNICE_J=12) and lab-recpause.sh SIGSTOPs only job trees holding a slot above 12 (held slots in
#     /tmp/labnice/held.<pid>), SIGCONT when the recording ends. LABNICE_REC_SLOTS=0 = old rule: every job pauses/waits.
#   - slots are taken all-or-nothing (no partial holds: deadlock fix), after 300 s whatever is free (>= 1)
#   - while recording a request above LABNICE_REC_SLOTS starts at once with that many (LABNICE_J sized down)
#   - -p (priority, the ONE KenshiFP build line only: kfp-pipeline/kfp-buildwatch): may also take the reserve slots
#     LABNICE_SLOTS+1..+LABNICE_RESERVE (default 6), tried first, so staging never queues behind climbers/sweeps holding
#     16/16 (2026-10-11: run-bl-1011-1838 waited with WSL load 16/32); while a take records it gets the normal budget
#   - selftest: labnice-selftest.sh (WSL, private LAB_D/LAB_RECDIR; recording flag, stale flags, no pause before held file)
set -u
if [ -e /mnt/c/KenshiTestRuns/uncapped.on ]; then RD=20; SD=$(( $(nproc --all) - 4 )); else RD=12; SD=$(( $(nproc --all) / 2 )); fi   # uncapped.on (Shay 2026-10-11: PC free, use it fully): 28/20 slots, else 16/12
D=${LAB_D:-/tmp/labnice}; mkdir -p "$D"; RECS=${LABNICE_REC_SLOTS:-$RD}; SLOTS=${LABNICE_SLOTS:-$SD}; [ "$SLOTS" -ge 1 ] || SLOTS=1   # --all: nproc honours OMP_NUM_THREADS
if [ "${1:-}" = --status ]; then
  n=0; for i in $(seq 1 "$SLOTS"); do exec {f}>"$D/slot.$i"; flock -n "$f" || n=$((n + 1)); exec {f}>&-; done
  echo "labnice: $n/$SLOTS slots in use"; exit 0
fi
if [ "${1:-}" = --renice ]; then
  pat=${2:?usage: labnice.sh --renice <pgrep -f pattern>}
  for p in $(pgrep -f "$pat"); do [ "$p" = $$ ] && continue
    for q in $p $(pgrep -P "$p"); do renice -n 15 -p "$q" >/dev/null 2>&1; ionice -c 3 -p "$q" >/dev/null 2>&1; done; echo "reniced $p"
  done; exit 0
fi
N=1; PRIO=0; RES=${LABNICE_RESERVE:-6}
while :; do case "${1:-}" in -s) N=$2; shift 2;; -p) PRIO=1; shift;; *) break;; esac; done
[ $# -ge 1 ] || { sed -n '2,15p' "$0"; exit 2; }
[ "$N" -gt "$SLOTS" ] && N=$SLOTS
# held slots for lab-recpause.sh (recording budget): written FIRST, before anything else can run (fix 2026-10-11: a job
# whose held file did not exist yet was paused by the daemon as an "older labnice" and stayed SIGSTOPped for the whole
# filming session: 8 min at 0/16 slots). "acquiring" = waiting for slots (never paused), then the slots held.
echo "${LABNICE_SLOT:-acquiring}" > "$D/held.$$"; trap 'rm -f "$D/held.$$"' EXIT
# stale files of dead jobs are dropped here
for h in "$D"/held.*; do [ -e "$h" ] && ! kill -0 "${h##*.}" 2>/dev/null && rm -f "$h"; done
# Recording pause (Shay 2026-10-10, speed-takes): while a 5090 take records, lab-recpause.sh (singleton, started here,
# detached) SIGSTOPs job trees holding a slot above the recording budget and SIGCONTs them after.
ME=$(dirname "$(readlink -f "$0")")
if [ -z "${LABNICE_SLOT:-}" ] && [ -f "$ME/lab-recpause.sh" ]; then
  # setsid -f: the daemon is not left below a forked labnice subshell (2026-10-11: that subshell outlived its job, looked
  # like a live labnice root and kept the daemon from ever idling out)
  [ -n "${LAB_NODAEMON:-}" ] || setsid -f nohup bash "$ME/lab-recpause.sh" >/dev/null 2>&1 </dev/null   # LAB_NODAEMON=1: tests
  rw=0; while [ "$RECS" -le 0 ] && bash "$ME/lab-recpause.sh" --recording && [ $rw -lt 1800 ]; do sleep 3; rw=$((rw + 3)); done
  [ $rw -gt 0 ] && echo "labnice: waited ${rw}s for a take recording to end" >&2
fi
if [ -z "${LABNICE_SLOT:-}" ]; then
  # all-or-nothing under one acquisition lock (deadlock 2026-10-10: 3 jobs each wanting -s 8 grabbed slots one by one and
  # held 16/16 between them, none ever complete). After LABNICE_PARTIAL s (300) a job takes what is free (>= 1 slot) and
  # sizes its pool to that (LABNICE_J), so a big job can't starve behind a stream of small ones. While a take records
  # the request is capped at the recording budget at once (no 300 s wait for slots that are off limits).
  got=(); t0=$(date +%s); PART=${LABNICE_PARTIAL:-300}
  while :; do
    exec {a}>"$D/acquire.lock"; flock "$a"
    fds=(); LIM=$SLOTS
    [ "$RECS" -gt 0 ] && [ "$RECS" -lt "$SLOTS" ] && [ -f "$ME/lab-recpause.sh" ] && bash "$ME/lab-recpause.sh" --recording && LIM=$RECS
    NW=$N; [ "$NW" -gt "$LIM" ] && NW=$LIM
    ord=$(seq 1 "$LIM"); [ $PRIO = 1 ] && [ "$LIM" = "$SLOTS" ] && [ "$RES" -gt 0 ] && ord="$(seq $((SLOTS + 1)) $((SLOTS + RES))) $ord"
    for i in $ord; do
      [ ${#got[@]} -ge "$NW" ] && break
      exec {f}>"$D/slot.$i"; if flock -n "$f"; then got+=("$i"); fds+=("$f"); else exec {f}>&-; fi
    done
    if [ ${#got[@]} -ge "$NW" ] || { [ ${#got[@]} -ge 1 ] && [ $(( $(date +%s) - t0 )) -ge "$PART" ]; }; then exec {a}>&-; break; fi
    for f in "${fds[@]}"; do exec {f}>&-; done; got=()   # not enough: give every slot back, retry
    exec {a}>&-; sleep 3
  done
  [ ${#got[@]} -lt "$N" ] && { echo "labnice: took ${#got[@]} of $N slot(s) (recording budget or ${PART}s wait; pool sized down)" >&2; N=${#got[@]}; }
  w=$(( $(date +%s) - t0 )); [ $w -gt 5 ] && echo "labnice: waited ${w}s for $N slot(s)" >&2
  export LABNICE_SLOT="${got[*]}"
fi
echo "$LABNICE_SLOT" > "$D/held.$$"
export LABNICE_J=$N
for v in OMP_NUM_THREADS OPENBLAS_NUM_THREADS MKL_NUM_THREADS NUMEXPR_NUM_THREADS; do [ -n "${!v:-}" ] || export "$v=$N"; done
nice -n 15 ionice -c 3 "$@"   # no exec: lab-recpause.sh finds the job tree by this labnice.sh parent
