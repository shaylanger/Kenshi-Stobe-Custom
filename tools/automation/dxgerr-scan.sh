#!/bin/bash
# dxgerr-scan.sh [check|show|--selftest]: WSL GPU-PV allocation-failure watch (gpu-native 2026-10-11, tdr-cause handoff).
# WSL dmesg `dxgkio_create_allocation: Ioctl failed` / `establish_gpadl failed` bursts came in the same second as 3 of the
# 4 afternoon 5090 TDRs (and the 13:16 BSOD is in dxgkrnl's WSL GPU host code). A WARNING only, never an auto-stop:
#   check   new failures since the last check -> one line `DXG-WARN 5090 n=<k> secs=<s> first=<t> last=<t> ...` (nothing
#           when none); each failing second -> gpulog\dxgerr.tsv ("time<TAB>count<TAB>kinds") + a timeline.tsv line
#           ("time<TAB>5090<TAB>wsl<TAB>dxg-warn<TAB>n=<k> <kinds>"). State: /run/kah-dxgerr.last (kernel seconds already
#           reported; the first run after a WSL start logs the whole ring buffer once, its line says "(baseline ...)").
#   show    the last 20 dxgerr.tsv lines.
# Times = the 5090 clock (UTC-6) like timeline.tsv. Runs in WSL (root, dmesg) or from Git Bash (calls wsl.exe).
# Caller: rig-health.sh (every waker); its DXG-WARN line comes before the RIG line.
set -u
D=DwemerAI4Skyrim3
GL=${DXG_GPULOG:-/mnt/c/KenshiTestRuns/gpulog}; ST=${DXG_STATE:-/run/kah-dxgerr.last}
PAT='dxgkio_create_allocation: Ioctl failed|establish_gpadl failed'
# scan <dmesg text on stdin> <last kernel s> <boot epoch>: prints "<kernel s int>\t<epoch>\t<count>\t<kinds>" per second (pure)
scan() { awk -v last="$1" -v boot="$2" -v pat="$PAT" '
  $0 ~ pat { if (match($0, /^\[ *[0-9]+\.[0-9]+\]/)) { t = substr($0, 2, RLENGTH - 2) + 0; if (t <= last) next
      s = int(t); c[s]++; k = ($0 ~ /create_allocation/) ? "alloc" : "gpadl"; if (index(kk[s], k) == 0) kk[s] = kk[s] (kk[s] ? "+" : "") k
      if (!(s in seen)) { seen[s] = 1; ord[++n] = s } ; if (t > mx) mx = t } }
  END { for (i = 1; i <= n; i++) { s = ord[i]; printf "%d\t%d\t%d\t%s\n", s, boot + s, c[s], kk[s] } ; if (n) printf "LAST\t%.6f\n", mx }'; }
fmt() { date -u -d "@$(( $1 - 6 * 3600 ))" '+%F %T'; }
check() {
  local txt boot last out n secs first lastt
  if [ -r /dev/kmsg ] || grep -qi microsoft /proc/version 2>/dev/null; then
    txt=$(dmesg 2>/dev/null); boot=$(awk -v now="$(date +%s)" '{print int(now - $1)}' /proc/uptime); stv=$(cat "$ST" 2>/dev/null)
  else   # Git Bash: one wsl.exe call does all of it (the state file lives in WSL /run)
    txt=$(MSYS_NO_PATHCONV=1 wsl.exe -d $D -u root --cd / -- bash -c "echo BOOT \$(awk -v now=\$(date +%s) '{print int(now - \$1)}' /proc/uptime); echo STATE \$(cat $ST 2>/dev/null); dmesg" 2>/dev/null | tr -d '\r')
    boot=$(sed -n 's/^BOOT //p' <<<"$txt" | head -1); stv=$(sed -n 's/^STATE //p' <<<"$txt" | head -1)
  fi
  [ -n "$boot" ] || return 0
  last=${stv:-0}
  out=$(scan "$last" "$boot" <<<"$txt")
  [ -n "$out" ] || return 0
  lastt=$(sed -n 's/^LAST\t//p' <<<"$out"); out=$(grep -v '^LAST' <<<"$out")
  if [ -r /dev/kmsg ] || grep -qi microsoft /proc/version 2>/dev/null; then echo "$lastt" > "$ST"
  else MSYS_NO_PATHCONV=1 wsl.exe -d $D -u root --cd / -- bash -c "echo $lastt > $ST" </dev/null >/dev/null 2>&1; fi
  local gl=$GL; [ -d "$gl" ] || gl=/c/KenshiTestRuns/gpulog; mkdir -p "$gl" 2>/dev/null
  n=0; secs=0
  while IFS=$'\t' read -r ks ep c kinds; do
    [ -n "$ks" ] || continue
    t=$(fmt "$ep"); n=$((n + c)); secs=$((secs + 1)); [ -n "${first:-}" ] || first=$t
    printf '%s\t%s\t%s\n' "$t" "$c" "$kinds" >> "$gl/dxgerr.tsv"
    printf '%s\t5090\twsl\tdxg-warn\tn=%s %s\n' "$t" "$c" "$kinds" >> "$gl/timeline.tsv"
  done <<<"$out"
  local bl=''; [ -n "$stv" ] || bl='baseline: since WSL start; '
  echo "DXG-WARN 5090 n=$n secs=$secs first=$first last=$t (${bl}WSL GPU-PV allocation failures: TDR/BSOD precursor, tdr-cause handoff; warning only; gpulog/dxgerr.tsv)"
}
case "${1:-check}" in
  check) check ;;
  show) tail -20 "$GL/dxgerr.tsv" 2>/dev/null || tail -20 /c/KenshiTestRuns/gpulog/dxgerr.tsv ;;
  --selftest)
    fx=$'[  100.100000] misc dxg: dxgk: create_existing_sysmem: establish_gpadl failed: -122\n[  100.200000] misc dxg: dxgk: dxgkio_create_allocation: Ioctl failed: -12\n[  100.900000] misc dxg: dxgk: dxgkio_is_feature_enabled: Ioctl failed: -75\n[  102.000000] misc dxg: dxgk: dxgkio_create_allocation: Ioctl failed: -12\n[   99.000000] misc dxg: dxgk: dxgkio_create_allocation: Ioctl failed: -12'
    bad=0; n=0
    T() { n=$((n + 1)); if [ "$2" = "$3" ]; then echo "ok   $1"; else echo "FAIL $1: got '$2' want '$3'"; bad=$((bad + 1)); fi; }
    T 'per-second counts + kinds, feature_enabled ignored' "$(scan 99.5 1000 <<<"$fx" | paste -sd'|')" $'100\t1100\t2\tgpadl+alloc|102\t1102\t1\talloc|LAST\t102.000000'
    T 'already reported seconds are not new' "$(scan 102 1000 <<<"$fx")" ''
    T 'empty dmesg' "$(scan 0 1000 <<<'')" ''
    T 'clock = UTC-6' "$(fmt 21600)" '1970-01-01 00:00:00'
    d=$(mktemp -d); GL=$d ST=$d/st
    dmesg() { printf '%s\n' "$fx"; }
    l1=$(check); l2=$(check); fx2=$fx$'
[  103.000000] misc dxg: dxgk: dxgkio_create_allocation: Ioctl failed: -12'
    l3=$(fx=$fx2; check)
    T 'check: one DXG-WARN line' "$(cut -d' ' -f1-4 <<<"$l1") $(grep -c baseline <<<"$l1")" 'DXG-WARN 5090 n=4 secs=3 1'
    T 'check twice: nothing new' "$l2" ''
    T 'a later failure: new line, no baseline' "$(cut -d' ' -f1-4 <<<"$l3") $(grep -c baseline <<<"$l3")" 'DXG-WARN 5090 n=1 secs=1 0'
    T 'dxgerr.tsv rows' "$(wc -l < $d/dxgerr.tsv)" 4
    T 'timeline rows' "$(grep -c dxg-warn $d/timeline.tsv)" 4
    rm -rf "$d"
    echo "DXGERR-SELFTEST $([ $bad = 0 ] && echo PASS || echo "FAIL $bad") $n cases"; [ $bad = 0 ] ;;
  *) echo "usage: dxgerr-scan.sh check|show|--selftest"; exit 2 ;;
esac
