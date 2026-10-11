#!/usr/bin/env bash
# lab-recpause.sh            (WSL, singleton daemon) pause every offline lab job while a 5090 take records
# lab-recpause.sh --status   one line: daemon running?, recording?, paused pids
# lab-recpause.sh --recording   exit 0 while a 5090 take records (labnice.sh then takes only slots <= LABNICE_REC_SLOTS)
# Why (Shay 2026-10-10): T6 turret takes tur-b-2/tur-c FAILed only on recording checks (1.1 s sampler gap, short video,
# label lag) at WSL load 60 from lab jobs; nice 15 alone does not keep the take's sampler/recorder on time.
# Recording = a fresh marker C:\KenshiTestRuns\recording\5090* (< 30 min old; take scripts may touch/remove one) or a
# running ffmpeg.exe gdigrab (< 30 min running; older = stale, ignored) started from WSL (every 5090 take recorder, pf_open clips included; dry-run shims are not
# ffmpeg.exe). The 4080 records on its own CPU: its takes don't pause the 5090 lab.
# While recording: SIGSTOP every process in every labnice.sh job tree (kfp-pipeline, gate, regress, climbers, ...) that
# holds a slot above the recording budget; when it ends: SIGCONT. One lab CPU budget (Shay 2026-10-10, CLAUDE.md speed
# plan 7): LABNICE_SLOTS (16) workers otherwise, LABNICE_REC_SLOTS (12) while a take records: a job whose slots
# (/tmp/labnice/held.<labnice pid>, written by labnice.sh) are all <= 12 keeps running; a job holding slot 13..16, or
# with no held file (older labnice), is paused. LABNICE_REC_SLOTS=0 = pause every lab job (the old behaviour). Never stopped: Windows .exe proxies and anything under a `timeout` (short ssh/scp/staging
# steps whose wall-clock timer would fire on resume). A pause lasting > MAXPAUSE (30 min, stuck recorder) is lifted.
# Started (detached, setsid) by labnice.sh; exits after 10 min without any labnice job, resuming whatever it stopped.
# Log: /tmp/labnice/recpause.log (PAUSE/RESUME lines).
set -u
D=${LAB_D:-/tmp/labnice}; mkdir -p "$D"; LOG=$D/recpause.log; ST=$D/recpause.stopped
REC=${LAB_RECDIR:-/mnt/c/KenshiTestRuns/recording}; MAXPAUSE=${LAB_MAXPAUSE:-1800}; TICK=${LAB_TICK:-2}; RD=12; [ -e /mnt/c/KenshiTestRuns/uncapped.on ] && RD=20; RECS=${LABNICE_REC_SLOTS:-$RD}   # uncapped.on (Shay 2026-10-11): 20 while recording
RECMAX=${LAB_RECMAX:-1800}; GPAT=${LAB_GDIGRAB_PAT:-gdigrab|kahcap-}   # kahcap-: ffmpeg reading wgccap's pipe (ffx-cap.sh, wgc capture)   # LAB_*: selftest overrides (labnice-selftest.sh)

recording() {
  # stale flags never count (fix 2026-10-11): a marker older than RECMAX s or an ffmpeg gdigrab running longer than
  # RECMAX s (a take records minutes; an orphaned/stuck recorder is not a recording) is ignored
  find "$REC" -maxdepth 1 -name '5090*' -newermt "-$RECMAX seconds" 2>/dev/null | grep -q . && return 0
  local p a0 age
  for p in $(pgrep -f -- "$GPAT"); do
    a0=$(tr '\0' '\n' < /proc/$p/cmdline 2>/dev/null | head -1)
    case "${a0,,}" in *ffmpeg.exe)
      age=$(ps -o etimes= -p "$p" 2>/dev/null | tr -d ' '); [ -n "$age" ] && [ "$age" -le "$RECMAX" ] && return 0 ;;
    esac
  done
  return 1
}

labpids() {   # every process below a labnice.sh root over the recording budget, minus .exe proxies and `timeout` subtrees
  # budget: only roots whose held file (/tmp/labnice/held.<pid>) names a slot above RECS; no held file / "acquiring" =
  # never paused (fix 2026-10-11: a just-started job had no held file yet, was paused as an "older labnice" and sat
  # SIGSTOPped at 0/16 slots for the whole filming session). RECS=0: every root (old rule). No arg: every root (resume).
  local roots r s over=""; roots=$(pgrep -f '(^|/)labnice\.sh( |$)' | tr '\n' ' ')
  [ -n "$roots" ] || return 0
  if [ "${1:-}" = budget ] && [ "$RECS" -gt 0 ]; then
    for r in $roots; do [ -s "$D/held.$r" ] || continue
      for s in $(cat "$D/held.$r" 2>/dev/null); do [ "$s" -gt "$RECS" ] 2>/dev/null && { over="$over $r"; break; }; done
    done
    [ -n "$over" ] || return 0
  else over=$roots; fi
  ps -eo pid=,ppid=,comm=,args= | awk -v roots="$over" -v self=$$ '
    { pid[NR]=$1; pp[$1]=$2; cm[$1]=$3; a0[$1]=$4; full[$1]=$0 }
    END { n=split(roots, r, " "); for (i=1;i<=n;i++) isroot[r[i]]=1
      for (k in pp) { p=k; keep=0; skip=0
        if (k==self) continue
        while (p!="" && p+0>1) { if (cm[p]=="timeout") skip=1; if (isroot[p]) { keep=1; break } p=pp[p] }
        if (keep && !skip && tolower(a0[k]) !~ /\.exe$/ && full[k] !~ /lab-recpause/) print k } }'
}

resume() {
  [ -s "$ST" ] || { : > "$ST"; return 0; }
  local n; n=$(wc -l < "$ST"); xargs -r kill -CONT < "$ST" 2>/dev/null
  # anything stopped by us that we lost track of: CONT the current lab trees too (harmless on running processes)
  labpids | xargs -r kill -CONT 2>/dev/null
  echo "$(date '+%F %T') RESUME $n pids ($1)" >> "$LOG"; : > "$ST"
}

case "${1:-}" in
  --recording) recording; exit $? ;;
  --which) labpids budget; exit 0 ;;   # pids a recording would pause now (over-budget lab job trees)
  --status)
    exec 9>"$D/recpause.lock"; if flock -n 9; then d=no; else d=yes; fi
    r=no; recording && r=yes
    echo "lab-recpause: daemon=$d recording=$r paused=$( [ -s "$ST" ] && wc -l < "$ST" || echo 0) log=$LOG"; exit 0 ;;
esac

# close inherited fds (a caller's slot/lock fds would stay held as long as the daemon lives)
for fd in /proc/$$/fd/*; do n=${fd##*/}; [ "$n" -gt 2 ] 2>/dev/null && eval "exec $n>&-" 2>/dev/null; done
exec 9>"$D/recpause.lock"; flock -n 9 || exit 0   # one daemon
trap 'resume "daemon exit"; exit 0' EXIT INT TERM
resume "daemon start"
since=0; idle=0
while :; do
  if recording; then
    now=$(date +%s); [ "$since" = 0 ] && since=$now
    if [ $((now - since)) -gt "$MAXPAUSE" ]; then
      [ -s "$ST" ] && resume "paused > ${MAXPAUSE}s: recorder stuck? lab resumed until the recording ends"
    else
      want=$(labpids budget | sort -u)
      new=$(comm -23 <(echo "$want" | sed '/^$/d') <(sort -u "$ST" 2>/dev/null))
      # stopped pids no longer over budget (slots given back, dead): resume now, not at the end of the recording
      old=$(comm -13 <(echo "$want" | sed '/^$/d') <(sort -u "$ST" 2>/dev/null))
      if [ -n "$old" ]; then
        echo "$old" | xargs -r kill -CONT 2>/dev/null; comm -12 <(echo "$want" | sed '/^$/d') <(sort -u "$ST") > "$ST.tmp"; mv -f "$ST.tmp" "$ST"
        echo "$(date '+%F %T') RESUME $(echo "$old" | wc -l) pids (no longer over budget)" >> "$LOG"
      fi
      if [ -n "$new" ]; then
        echo "$new" | xargs -r kill -STOP 2>/dev/null; echo "$new" >> "$ST"
        echo "$(date '+%F %T') PAUSE $(echo "$new" | wc -l) pids (recording)" >> "$LOG"
      fi
    fi
  else
    since=0; [ -s "$ST" ] && resume "recording ended"
  fi
  if pgrep -f '(^|/)labnice\.sh( |$)' >/dev/null; then idle=0; else idle=$((idle + TICK)); [ $idle -ge 600 ] && exit 0; fi
  sleep $TICK
done
