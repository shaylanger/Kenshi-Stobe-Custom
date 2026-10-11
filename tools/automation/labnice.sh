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
#   - pauses while a 5090 take records (lab-recpause.sh: SIGSTOP/SIGCONT of every labnice job tree; new jobs wait)
#   - slots are taken all-or-nothing (no partial holds: deadlock fix), after 300 s whatever is free (>= 1)
set -u
D=/tmp/labnice; mkdir -p "$D"; SLOTS=${LABNICE_SLOTS:-$(( $(nproc --all) / 2 ))}; [ "$SLOTS" -ge 1 ] || SLOTS=1   # --all: nproc honours OMP_NUM_THREADS
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
N=1; [ "${1:-}" = -s ] && { N=$2; shift 2; }
[ $# -ge 1 ] || { sed -n '2,15p' "$0"; exit 2; }
[ "$N" -gt "$SLOTS" ] && N=$SLOTS
# Recording pause (Shay 2026-10-10, speed-takes): while a 5090 take records, lab-recpause.sh (singleton, started here,
# detached) SIGSTOPs every labnice job tree and SIGCONTs it after; a new job also waits here before taking slots.
ME=$(dirname "$(readlink -f "$0")")
if [ -z "${LABNICE_SLOT:-}" ] && [ -f "$ME/lab-recpause.sh" ]; then
  setsid nohup bash "$ME/lab-recpause.sh" >/dev/null 2>&1 </dev/null &
  rw=0; while bash "$ME/lab-recpause.sh" --recording && [ $rw -lt 1800 ]; do sleep 3; rw=$((rw + 3)); done
  [ $rw -gt 0 ] && echo "labnice: waited ${rw}s for a take recording to end" >&2
fi
if [ -z "${LABNICE_SLOT:-}" ]; then
  # all-or-nothing under one acquisition lock (deadlock 2026-10-10: 3 jobs each wanting -s 8 grabbed slots one by one and
  # held 16/16 between them, none ever complete). After LABNICE_PARTIAL s (300) a job takes what is free (>= 1 slot) and
  # sizes its pool to that (LABNICE_J), so a big job can't starve behind a stream of small ones.
  got=(); t0=$(date +%s); PART=${LABNICE_PARTIAL:-300}
  while :; do
    exec {a}>"$D/acquire.lock"; flock "$a"
    fds=()
    for i in $(seq 1 "$SLOTS"); do
      [ ${#got[@]} -ge "$N" ] && break
      exec {f}>"$D/slot.$i"; if flock -n "$f"; then got+=("$i"); fds+=("$f"); else exec {f}>&-; fi
    done
    if [ ${#got[@]} -ge "$N" ] || { [ ${#got[@]} -ge 1 ] && [ $(( $(date +%s) - t0 )) -ge "$PART" ]; }; then exec {a}>&-; break; fi
    for f in "${fds[@]}"; do exec {f}>&-; done; got=()   # not enough: give every slot back, retry
    exec {a}>&-; sleep 3
  done
  [ ${#got[@]} -lt "$N" ] && { echo "labnice: took ${#got[@]} of $N slot(s) after ${PART}s (pool sized down)" >&2; N=${#got[@]}; }
  w=$(( $(date +%s) - t0 )); [ $w -gt 5 ] && echo "labnice: waited ${w}s for $N slot(s)" >&2
  export LABNICE_SLOT="${got[*]}"
fi
export LABNICE_J=$N
for v in OMP_NUM_THREADS OPENBLAS_NUM_THREADS MKL_NUM_THREADS NUMEXPR_NUM_THREADS; do [ -n "${!v:-}" ] || export "$v=$N"; done
nice -n 15 ionice -c 3 "$@"   # no exec: lab-recpause.sh finds the job tree by this labnice.sh parent
