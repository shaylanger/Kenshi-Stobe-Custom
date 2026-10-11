#!/bin/bash
# wsl-cache-trim.sh: keep WSL's page cache small so vmmem gives RAM back to Windows (Shay 2026-10-10).
# Linux caches every file it reads (take videos, corpus, lab data); WSL's autoMemoryReclaim=gradual returns it
# only slowly, so vmmem sat near its 8 GB cap with ~1.3 GB really used. Every 120 s, if the page cache is over
# 1.5 GB, drop CLEAN cached pages (drop_caches=1: page cache only, never process memory or dirty data).
# Files re-read from NVMe; no program loses memory. Usage (WSL root): start | stop | status
PIDF=/run/wsl-cache-trim.pid
LIMIT_KB=${CACHE_TRIM_LIMIT_KB:-1572864}
case "${1:-status}" in
  start)
    if [ -f $PIDF ] && kill -0 "$(cat $PIDF)" 2>/dev/null; then echo "cache-trim running pid $(cat $PIDF)"; exit 0; fi
    setsid nohup bash -c "while :; do c=\$(awk '/^Cached:/{print \$2}' /proc/meminfo); if [ \"\$c\" -gt $LIMIT_KB ]; then sync; echo 1 > /proc/sys/vm/drop_caches; fi; sleep 120; done" >/dev/null 2>&1 &
    echo $! > $PIDF; echo "cache-trim started pid $!";;
  stop) [ -f $PIDF ] && kill "$(cat $PIDF)" 2>/dev/null; rm -f $PIDF; echo "cache-trim stopped";;
  status) if [ -f $PIDF ] && kill -0 "$(cat $PIDF)" 2>/dev/null; then echo "cache-trim running pid $(cat $PIDF)"; else echo "cache-trim not running"; fi
          grep -E "^Cached:" /proc/meminfo;;
esac
