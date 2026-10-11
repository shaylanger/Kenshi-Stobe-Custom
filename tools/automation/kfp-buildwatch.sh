#!/bin/bash
# kfp-buildwatch.sh -- the ONE KenshiFP build line on autopilot (WSL root, detached): reruns `kfp-pipeline.sh --combined`
# whenever the pending KenshiFP patches (pending-fixes/kfp-*.py|.patch) or the live source /root/KenshiFP (HEAD + working
# tree of client/ re_plugin/ tests/) change, once they have been quiet for QUIET s (default 90: no half-saved edits),
# so a new or updated patch reaches both rigs (staged + KenshiFP-latest.txt) within ~15 min without anyone asking.
# A change made while a run is going starts the next run as soon as that run ends (re-checked at once, no extra poll).
# A fingerprint is built at most once per state (a FAIL is not retried until something changes). Never runs two
# pipelines at once: waits while any kfp-pipeline run holds an inflight marker (C:\KenshiTestRuns\inflight\kfp-pipeline-*).
#
# Start (once; it refuses a second copy):
#   wsl -d DwemerAI4Skyrim3 -u root -- setsid nohup nice -n 15 bash /mnt/c/KenshiModding/tools/automation/kfp-buildwatch.sh > /dev/null 2>&1 &
# Seed: kfp-buildwatch.sh --seed  (the current state counts as built: after a manual --combined run of it)
# Stop: touch /root/kfp-pipeline/buildwatch.stop  (or kill the pid in /root/kfp-pipeline/buildwatch.pid)
# Status: tail /root/kfp-pipeline/buildwatch.log (one line per decision; each build ends with its PIPELINE line);
#         the newest PIPELINE line is also written to C:\KenshiTestRuns\staged\KenshiFP-pipeline.last
# Env: QUIET (90) POLL (30)   (Shay 2026-10-10: was 600/120, a patch written mid-run waited a whole extra cycle)
set -u
PR=/root/kfp-pipeline; PF=/mnt/c/KenshiModding/pending-fixes; LIVE=/root/KenshiFP; IFD=/mnt/c/KenshiTestRuns/inflight
LOG=$PR/buildwatch.log; QUIET=${QUIET:-90}; POLL=${POLL:-30}; ME=/mnt/c/KenshiModding/tools/automation
mkdir -p "$PR"
log() { echo "$(date '+%F %T') $*" >> "$LOG"; }
# fingerprint of everything that goes into the combined DLL; newest mtime for the quiet check
fp() { { ls "$PF"/kfp-*.py "$PF"/kfp-*.patch 2>/dev/null | LC_ALL=C sort | xargs -r sha256sum
         git -C "$LIVE" rev-parse HEAD 2>/dev/null; git -C "$LIVE" diff HEAD -- client re_plugin tests 2>/dev/null | sha256sum
         git -C "$LIVE" ls-files -o --exclude-standard -- client re_plugin tests 2>/dev/null | LC_ALL=C sort | xargs -r -I{} sha256sum "$LIVE/{}"; } | sha256sum | cut -c1-16; }
newest() { { stat -c %Y "$PF"/kfp-*.py "$PF"/kfp-*.patch 2>/dev/null; find "$LIVE/client" "$LIVE/re_plugin" "$LIVE/tests" -type f \
             ! -name '*.o' ! -name '*.dll' ! -name '*.log' -printf '%T@\n' 2>/dev/null | cut -d. -f1; } | sort -n | tail -1; }
# Carried exclusions (2026-10-11: every watch run re-found the same breakers with a ~25 min recency round each): after a
# run, the patches its last rerun left out are recorded with their sha256 + the live HEAD (buildwatch.excl); the next run
# starts with --exclude for those still unchanged (an edited patch or a new live HEAD = tried again).
pfile() { ls "$PF/$1.py" "$PF/$1.patch" 2>/dev/null | head -1; }
remember() { local last ex n p h; last=$(ls -d "$1" "$1"-x* 2>/dev/null | sort -V | tail -1); ex=$(cat "$last/exclude.list" 2>/dev/null)
  h=$(git -C "$LIVE" rev-parse HEAD 2>/dev/null); : > "$PR/buildwatch.excl"
  for n in ${ex//,/ }; do p=$(pfile "$n"); [ -n "$p" ] && echo "$n $(sha256sum "$p" | cut -c1-16) $h" >> "$PR/buildwatch.excl"; done; }
carried() { local n s h p hh; hh=$(git -C "$LIVE" rev-parse HEAD 2>/dev/null)
  [ -f "$PR/buildwatch.excl" ] || return 0
  while read -r n s h; do p=$(pfile "$n"); [ -n "$p" ] && [ "$h" = "$hh" ] && [ "$(sha256sum "$p" | cut -c1-16)" = "$s" ] && echo "$n"; done < "$PR/buildwatch.excl" | paste -sd,; }
[ "${1:-}" = --remember ] && { remember "${2:?run dir}"; cat "$PR/buildwatch.excl"; exit 0; }
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
    elif pgrep -f 'kfp-pipeline\.sh --' > /dev/null; then :   # a run still waiting for lab slots has no marker yet (2026-10-11 race: 3 pipelines at once)
    else
      R=$PR/run-watch-$(date +%m%d-%H%M); ex=$(carried); log "change $last -> $f (quiet ${age}s): kfp-pipeline --combined${ex:+ --exclude $ex (carried)} -> $R"
      KFP_EXCL_NOTE=$(for n in ${ex//,/ }; do printf '%s:carried (patch + live HEAD unchanged since it broke);' "$n"; done | sed 's/;$//') \
        bash "$ME/labnice.sh" -p -s 3 bash "$ME/kfp-pipeline.sh" --combined ${ex:+--exclude "$ex"} --out "$R" > "$PR/buildwatch.run.log" 2>&1 < /dev/null 8>&-
      res=$(grep -h '^PIPELINE ' "$PR/buildwatch.run.log" | tail -1); log "${res:-PIPELINE ? no final line (log $PR/buildwatch.run.log)}"
      remember "$R"
      echo "$(date '+%F %T') ${res:-PIPELINE ? no final line}" > /mnt/c/KenshiTestRuns/staged/KenshiFP-pipeline.last
      last=$f; echo "$f" > "$PR/buildwatch.fp"   # the state that was built (fp before the run: a change during it rebuilds)
      continue   # re-check at once: a change made during the run starts the next run now (if quiet), not one poll later
    fi
  fi
  sleep "$POLL" 8>&-   # children must not inherit the lock fd (an orphaned sleep kept it after a kill)
done
log "stop (buildwatch.stop)"; rm -f "$PR/buildwatch.stop" "$PR/buildwatch.pid"
