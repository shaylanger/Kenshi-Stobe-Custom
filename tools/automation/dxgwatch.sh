#!/bin/bash
# dxgwatch.sh [start|stop|status|run|--selftest]: WSL GPU-job timeline (speed-scout 2026-10-11). Every 5 s it lists the WSL
# processes holding /dev/dxg (CUDA/CuPy/NVDEC/NVENC jobs reach the GPU through it) and appends start/exit lines to
# C:\KenshiTestRuns\gpulog\timeline.tsv ("time<TAB>5090<TAB>wsl<TAB>gpu-start|gpu-exit<TAB>pid=<n> <cmdline>"), so a TDR can
# be matched to the WSL GPU work running at that second (next to gpulog.ps1 csv/process lines and run-batch launch/row lines).
# Times are the 5090 clock (UTC-6, Windows Central with DST off; WSL itself runs CDT). One instance (/run/kah-dxgwatch.pid); `start` detaches it at nice 19 (gpulog-ensure.ps1 calls it). Cost: one find, ~10 ms.
TL=${DXG_TIMELINE:-/mnt/c/KenshiTestRuns/gpulog/timeline.tsv}; PF=/run/kah-dxgwatch.pid
dxg_pids() { find /proc/[0-9]*/fd -maxdepth 1 -lname /dev/dxg 2>/dev/null | cut -d/ -f3 | sort -u; }
# diff_lines <old pids file> <new pids file> <ts> <cmd-of fn>: pure apart from the cmd lookup
diff_lines() { local p
  for p in $(comm -13 "$1" "$2"); do printf '%s\t5090\twsl\tgpu-start\tpid=%s %s\n' "$3" "$p" "$($4 "$p")"; done
  for p in $(comm -23 "$1" "$2"); do printf '%s\t5090\twsl\tgpu-exit\tpid=%s %s\n' "$3" "$p" "$(grep -m1 "^$p " "$1.cmd" 2>/dev/null | cut -d' ' -f2-)"; done; }
cmd_of() { tr '\0' ' ' < "/proc/$1/cmdline" 2>/dev/null | tr '\t\r\n' '   ' | cut -c1-160; }
run() { local d o n; d=$(mktemp -d); o=$d/old; n=$d/new; : > "$o"; : > "$o.cmd"
  while :; do
    dxg_pids > "$n"
    # cmdline per pid, kept from the first sight (an exited pid has no /proc entry left to read at its gpu-exit line)
    for p in $(cat "$n"); do c=$(grep -m1 "^$p " "$o.cmd" | cut -d' ' -f2-); [ -n "$c" ] || c=$(cmd_of "$p"); echo "$p $c"; done > "$n.cmd"
    diff_lines "$o" "$n" "$(date -u -d '-6 hours' '+%F %T')" cmd_of >> "$TL" 2>/dev/null
    mv "$n" "$o"; mv "$n.cmd" "$o.cmd"; sleep 5
  done; }
case "${1:-status}" in
  start) if [ -s $PF ] && kill -0 "$(cat $PF)" 2>/dev/null; then echo "DXGWATCH RUNNING pid=$(cat $PF)"; exit 0; fi
         setsid nohup nice -n 19 bash "$0" run </dev/null >/dev/null 2>&1 & echo $! > $PF; echo "DXGWATCH STARTED pid=$!" ;;
  stop) [ -s $PF ] && kill "$(cat $PF)" 2>/dev/null; rm -f $PF; echo "DXGWATCH STOPPED" ;;
  status) if [ -s $PF ] && kill -0 "$(cat $PF)" 2>/dev/null; then echo "DXGWATCH RUNNING pid=$(cat $PF)"; else echo "DXGWATCH DOWN"; fi ;;
  run) run ;;
  --selftest) d=$(mktemp -d); printf '1\n2\n' > $d/o; printf '1 a\n2 job two\n' > $d/o.cmd; printf '1\n3\n' > $d/n
    fake() { echo "cmd$1"; }
    got=$(diff_lines $d/o $d/n T fake | paste -sd'|'); want=$(printf 'T\t5090\twsl\tgpu-start\tpid=3 cmd3|T\t5090\twsl\tgpu-exit\tpid=2 job two')
    rm -rf $d; if [ "$got" = "$want" ]; then echo "DXGWATCH-SELFTEST PASS 1 case"; else echo "DXGWATCH-SELFTEST FAIL got '$got'"; exit 1; fi ;;
  *) echo "usage: dxgwatch.sh start|stop|status|run|--selftest"; exit 2 ;;
esac
