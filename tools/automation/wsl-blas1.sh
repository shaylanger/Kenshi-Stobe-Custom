#!/bin/bash
# wsl-blas1.sh [install|remove|status]  (WSL root; gpu-lab 2026-10-11)
# Every WSL python3 that imports numpy started an OpenBLAS thread pool of nproc (32) threads, or LABNICE_J threads
# under labnice.sh, that busy-spin on import and on every small matmul: measured `python3 -c "import numpy"` 1.35 s CPU
# for 0.14 s wall (unset) / 0.37 s (=6) vs 0.07 s at 1 thread; pasweep.py per variant 2.26 -> 0.94 s CPU, same output.
# Lab work is many small single-process jobs run in parallel (xargs -P, labnice slots), so BLAS threads only burn CPU.
# install = append a marked block to the system sitecustomize.py of every python3.x here that forces
# OPENBLAS_NUM_THREADS=$KAH_BLAS_THREADS (default 1) before any import; KAH_BLAS_THREADS=keep leaves the env alone.
# Only OPENBLAS_* is touched (OMP_NUM_THREADS stays: torch/Parakeet use OMP). Idempotent; status prints the state.
set -e
MODE=${1:-install}
for f in /usr/lib/python3*/sitecustomize.py; do
  [ -f "$f" ] || continue
  case $MODE in
    install)
      grep -q 'kah-blas1' "$f" && { echo "ok $f (already)"; continue; }
      cat >> "$f" <<'PY'
# kah-blas1 (C:\KenshiModding\tools\automation\wsl-blas1.sh): 1 OpenBLAS thread per process unless KAH_BLAS_THREADS
import os as _kah_os
if _kah_os.environ.get('KAH_BLAS_THREADS', '1') != 'keep':
    _kah_os.environ['OPENBLAS_NUM_THREADS'] = _kah_os.environ.get('KAH_BLAS_THREADS', '1')
del _kah_os
# /kah-blas1
PY
      echo "installed $f";;
    remove) sed -i '/^# kah-blas1 /,/^# \/kah-blas1$/d' "$f"; echo "removed $f";;
    status) grep -q 'kah-blas1' "$f" && echo "on $f" || echo "off $f";;
  esac
done
[ "$MODE" = status ] && python3 -c "import os; print('python3 OPENBLAS_NUM_THREADS=' + os.environ.get('OPENBLAS_NUM_THREADS', '-'))"
exit 0
