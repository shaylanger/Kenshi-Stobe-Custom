#!/bin/bash
# kfp-buildwatch.sh -- the ONE KenshiFP build line on autopilot (WSL root, detached): reruns `kfp-pipeline.sh --combined`
# whenever the pending KenshiFP patches (pending-fixes/kfp-*.py|.patch) or the live source /root/KenshiFP (HEAD + working
# tree of client/ re_plugin/ tests/) change, once they have been quiet for QUIET s (default 600: no half-saved edits),
# so a new or updated patch reaches both rigs (staged + KenshiFP-latest.txt) within the hour without anyone asking.
# A fingerprint is built at most once per state (a FAIL is not retried until something changes). Never runs two
# pipelines at once: waits while any kfp-pipeline run holds an inflight marker (C:\KenshiTestRuns\inflight\kfp-pipeline-*).
#
# Start (once; it refuses a second copy):
#   wsl -d DwemerAI4Skyrim3 -u root -- setsid nohup bash /mnt/c/KenshiModding/tools/automation/kfp-buildwatch.sh > /dev/null 2>&1 &
# Seed: kfp-buildwatch.sh --seed  (the current state counts as built: after a manual --combined run of it)
# Stop: touch /root/kfp-pipeline/buildwatch.stop  (or kill the pid in /root/kfp-pipeline/buildwatch.pid)
# Status: tail /root/kfp-pipeline/buildwatch.log (one line per decision; each build ends with its PIPELINE line);
#         the newest PIPELINE line is also written to C:\KenshiTestRuns\staged\KenshiFP-pipeline.last
# Env: QUIET (600) POLL (120)
set -u
PR=/root/kfp-pipeline; PF=/mnt/c/KenshiModding/pending-fixes; LIVE=/root/KenshiFP; IFD=/mnt/c/KenshiTestRuns/inflight
LOG=$PR/buildwatch.log; QUIET=${QUIET:-600}; POLL=${POLL:-120}; ME=/mnt/c/KenshiModding/tools/automation
mkdir -p "$PR"
log() { echo "$(date '+%F %T') $*" >> "$LOG"; }
# fingerprint of everything that goes into the combined DLL; newest mtime for the quiet check
fp() { { ls "$PF"/kfp-*.py "$PF"/kfp-*.patch 2>/dev/null | LC_ALL=C sort | xargs -r sha256sum
         git -C "$LIVE" rev-parse HEAD 2>/dev/null; git -C "$LIVE" diff HEAD -- client re_plugin tests 2>/dev/null | sha256sum
         git -C "$LIVE" ls-files -o --exclude-standard -- client re_plugin tests 2>/dev/null | LC_ALL=C sort | xargs -r -I{} sha256sum "$LIVE/{}"; } | sha256sum | cut -c1-16; }
newest() { { stat -c %Y "$PF"/kfp-*.py "$PF"/kfp-*.patch 2>/dev/null; find "$LIVE/client" "$LIVE/re_plugin" "$LIVE/tests" -type f \
             ! -name '*.o' ! -name '*.dll' ! -name '*.log' -printf '%T@\n' 2>/dev/null | cut -d. -f1; } | sort -n | tail -1; }
# --seed: record the current state as built (e.g. right after a manual --combined run of it) and exit
[ "${1:-}" = --seed ] && { fp > "$PR/buildwatch.fp"; log "seeded fp $(cat "$PR/buildwatch.fp")"; exit 0; }
mkdir -p "$PR"; exec 8> "$PR/buildwatch.lock"; flock -n 8 || { echo "kfp-buildwatch: already running (pid $(cat "$PR/buildwatch.pid" 2>/dev/null))"; exit 0; }
echo $$ > "$PR/buildwatch.pid"; rm -f "$PR/buildwatch.stop"
log "start pid $$ quiet=${QUIET}s poll=${POLL}s"
last=$(cat "$PR/buildwatch.fp" 2>/dev/null)
while [ ! -e "$PR/buildwatch.stop" ]; do
  f=$(fp)
  if [ "$f" != "$last" ]; then
    age=$(( $(date +%s) - $(newest) ))
    if [ $age -lt $QUIET ]; then :   # still being edited: wait for quiet
    elif [ -n "$(find "$IFD" -maxdepth 1 -name 'kfp-pipeline-*' -mmin -180 2>/dev/null)" ]; then :   # a run is in flight (markers > 3 h = dead run, ignored)
    else
      R=$PR/run-watch-$(date +%m%d-%H%M); log "change $last -> $f (quiet ${age}s): kfp-pipeline --combined -> $R"
      bash "$ME/kfp-pipeline.sh" --combined --out "$R" > "$PR/buildwatch.run.log" 2>&1 < /dev/null
      res=$(grep -h '^PIPELINE ' "$PR/buildwatch.run.log" | tail -1); log "${res:-PIPELINE ? no final line (log $PR/buildwatch.run.log)}"
      echo "$(date '+%F %T') ${res:-PIPELINE ? no final line}" > /mnt/c/KenshiTestRuns/staged/KenshiFP-pipeline.last
      last=$f; echo "$f" > "$PR/buildwatch.fp"   # the state that was built (fp before the run: a change during it rebuilds)
    fi
  fi
  sleep "$POLL"
done
log "stop (buildwatch.stop)"; rm -f "$PR/buildwatch.stop" "$PR/buildwatch.pid"
