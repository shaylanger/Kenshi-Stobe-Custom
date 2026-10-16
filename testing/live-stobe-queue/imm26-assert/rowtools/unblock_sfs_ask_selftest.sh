#!/usr/bin/env bash
# unblock_sfs_ask_selftest.sh (imm26-fix08d3): OFFLINE selftest of the 08-d ask-window fix (sfs_quiet_wait / mark before tick 2 in unblockdefs_sfs.sh[.candidate]).
#   SFS_DEFS=<defs file> (default: unblockdefs_sfs.sh.candidate if it exists, else unblockdefs_sfs.sh).   Run in WSL or Git Bash:  bash rowtools/unblock_sfs_ask_selftest.sh
# Unit part: lt_h runs the script on this host against a synthetic stobe.log that a background writer extends over time (shape of the 4080-i3 op25 log: tick 1's speech arrives LATE,
#   a Cind/bystander chat that contains the word Squin).  Then the REAL checker (unblockcheck_sfs.py) is run on evidence whose logs are the real windows.  Ends with the unchanged
#   unblock_sfs_selftest.sh against the same defs.
# Prints `SELFTEST sfs-ask-<name> PASS|FAIL` and `SELFTEST SFS-ASK ALL PASS|FAIL n/m`.
ST_HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -z "${SFS_DEFS:-}" ]; then
  if [ -f "$ST_HERE/unblockdefs_sfs.sh.candidate" ]; then SFS_DEFS="$ST_HERE/unblockdefs_sfs.sh.candidate"; else SFS_DEFS="$ST_HERE/unblockdefs_sfs.sh"; fi
fi
export SFS_DEFS
REAL_PY=$(command -v python3 || command -v python)
T=$(mktemp -d); n=0; ok=0
chk() { n=$((n+1)); if [ "$2" = ok ]; then ok=$((ok+1)); echo "SELFTEST sfs-ask-$1 PASS ${3:-}"; else echo "SELFTEST sfs-ask-$1 FAIL ${3:-}"; fi; }
unset KAH_ROW_FAKE KAH_ROW_DRY
. "$ST_HERE/../go-row.sh"; . "$ST_HERE/reloaddefs_a.sh"; . "$ST_HERE/unblockdefs_a.sh"; . "$SFS_DEFS"
export LT_STOBELOG="$T/stobe.log" EV="$T/ev"; mkdir -p "$EV"
eval "$(declare -f lt_h | sed '1s/^lt_h/lt_h_orig/')"   # keep the fake-lane aware original for part 3
lt_h() { bash; }                      # the "host" is this machine; the body arrives on stdin (printf '..' | lt_h)
export U08D_POLL=1 U08D_QUIET=2 U08D_QUIETMAX=12 U08D_SAYWAIT=6
L() { echo "[2026-10-16 14:5$1] [Stobe] $2" >> "$LT_STOBELOG"; }
SAYA='ACTION_EXEC: SAY [Cind [Hungry Bandit]]: Well. Squin. We made it, then. I will say this for you - you keep your word. (NPC)'
SAYB="ACTION_EXEC: SAY [Krev [Pacifier Flog]]: Squin's walls are the only promise worth trusting. (NPC)"
SAYC='ACTION_EXEC: SAY [Cind [Hungry Bandit]]: Safe roads to you, Krev. (NPC)'
ASK='ACTION_EXEC: SAY [Cind [Hungry Bandit]]: Did you sell your furs in Squin yet? (NPC)'
grepcmd() { printf 'tail -n +%s %s | grep -E "BORED_EVENT|ACTION_EXEC: SAY|FOLLOWUP|followup" | cut -c1-300 | head -40\n' "$(( $1 + 1 ))" "$LT_STOBELOG" | lt_h; }
reset() { : > "$LT_STOBELOG"; for i in $(seq 1 30); do L 5:00 "SOCIAL_FOCUS: focus=2 resolved=2"; done; }
# --- 1 late tick-1 speech (starts 2 s after the quiet wait begins, 3 SAY lines over ~3 s): the wait must outlast it, the window must be free of it
reset; n0=$(sfs_stobelog_lines)
( sleep 2; L 8:59 "BORED_EVENT: dispatched speaker=Cind [Hungry Bandit] listener=Krev mode=autochat"; L 9:02 "$SAYA"; sleep 1; L 9:13 "$SAYB"; sleep 2; L 9:25 "$SAYA" ) &
bg=$!
t0=$SECONDS; sfs_quiet_wait "$n0" 1; dt=$((SECONDS - t0)); wait $bg
m=$(sfs_stobelog_lines)
if [ "$(sfs_say_count "$n0")" = 3 ] && [ "$dt" -ge 7 ]; then chk quiet-wait-outlasts-late-speech ok "waited ${dt}s"; else chk quiet-wait-outlasts-late-speech bad "dt=$dt says=$(sfs_say_count "$n0")"; fi
L 9:33 "BORED_EVENT: dispatched speaker=Cind [Hungry Bandit] listener=Shay mode=director"; L 9:40 "$SAYC"
w=$(grepcmd "$m")
if echo "$w" | grep -qi 'squin\|fur'; then chk window-free-of-tick1-speech bad "$w"; else chk window-free-of-tick1-speech ok; fi
full=$(grepcmd "$n0")
if echo "$full" | grep -qi 'squin'; then chk full-log-would-trip-v1-regex ok; else chk full-log-would-trip-v1-regex bad; fi
# --- 2 quiet wait ends at once when no speech is expected (tick 1 nothing_claimable) and at U08D_SAYWAIT when speech was expected but never comes
reset; n0=$(sfs_stobelog_lines); t0=$SECONDS; sfs_quiet_wait "$n0" 0; dt=$((SECONDS - t0))
if [ "$dt" -le 2 ]; then chk no-speech-expected-returns-at-once ok "${dt}s"; else chk no-speech-expected-returns-at-once bad "${dt}s"; fi
t0=$SECONDS; sfs_quiet_wait "$n0" 1; dt=$((SECONDS - t0))
if [ "$dt" -ge 5 ] && [ "$dt" -le 9 ]; then chk expected-speech-never-comes-bounded ok "${dt}s"; else chk expected-speech-never-comes-bounded bad "${dt}s"; fi
# --- 3 verdicts of the REAL checker on evidence whose logs are the windows above.  Base evidence = the fake-lane run of scenario sfs-pass (topic closed, no claim rows).
bad_set() {  # bad_set <ev> : comma-joined failing check names of the real 08-d verdict on <ev>
  "$REAL_PY" -I -c '
import sys
sys.path.insert(0, sys.argv[1])
import unblockcheck_sfs as c
c.rc.V.emit = lambda s, e: print("BAD", ",".join(sorted(b.split("=")[0] for b in s.bad))) or 0
c.main(["x", "08-d", sys.argv[2]])' "$ST_HERE" "$1" 2>&1 | sed -n 's/^BAD //p'
}
export KAH_ROWS_BASE="$T/runs" KAH_ROW_FAKE=1 KAH_ROW_FAKE_LOG="$T/fake.log" KAH_PF_ISOLATION=0 FAKE_STATE="$T/state.json" ROW_SETTLE=0 ROW_WAIT=1 TRIP_SE_TRIES=2 RW_SAY_WAIT=0 TRIP_WALK_TRIES=2
mkdir -p "$KAH_ROWS_BASE"; export FAKE_SCEN="$T/scen.json"; "$REAL_PY" "$ST_HERE/unblockscen_sfs.py" sfs-pass > "$FAKE_SCEN"
lt_fake() { "$REAL_PY" "$ST_HERE/unblockfake_sfs.py" "$@"; }
eval "$(declare -f lt_h_orig | sed '1s/^lt_h_orig/lt_h/')"
gr_main --allow-retry selftest 08-d 4080-i4 >/dev/null 2>&1
EVD="$KAH_ROWS_BASE/imm26-4080-i4/rows/08-d"
[ -s "$EVD/fu_after.txt" ] || chk evidence-built bad "no $EVD/fu_after.txt"
printf '%s\n' "$full" > "$EVD/bored_log.txt"
printf '%s\n' "$w" > "$EVD/bored_log_after1.txt"
r=$(bad_set "$EVD"); if [ -z "$r" ]; then chk real-timeline-no-false-fail ok "tick-1 chat before the mark, nothing failing"; else chk real-timeline-no-false-fail bad "failing='$r'"; fi
printf '%s\n%s\n' "$w" "[2026-10-16 15:00:10] [Stobe] $ASK" > "$EVD/bored_log_after1.txt"
r=$(bad_set "$EVD"); if [ "$r" = no_npc_ask_about_the_topic ]; then chk NEGATIVE-real-ask-after-mark-fails ok; else chk NEGATIVE-real-ask-after-mark-fails bad "failing='$r'"; fi
printf '%s\n%s\n' "$w" "[2026-10-16 15:00:10] [Stobe] ACTION_EXEC: SAY [Cind [Hungry Bandit]]: Where are you headed now, Shay? (NPC)" > "$EVD/bored_log_after1.txt"
r=$(bad_set "$EVD"); if [ -z "$r" ]; then chk unrelated-line-after-mark-passes ok; else chk unrelated-line-after-mark-passes bad "failing='$r'"; fi
printf '%s\n' "$full" > "$EVD/bored_log_after1.txt"   # the old early-mark window (everything): the defect this fix removes
r=$(bad_set "$EVD"); if [ "$r" = no_npc_ask_about_the_topic ]; then chk early-mark-window-trips-regex ok "(defect reproduced)"; else chk early-mark-window-trips-regex bad "failing='$r'"; fi
# --- 4 the unchanged full 08-d selftest on the same defs (the loop edit must not break any recipe statement)
o=$(bash "$ST_HERE/unblock_sfs_selftest.sh" 2>&1)
if echo "$o" | tail -1 | grep -q 'SELFTEST SFS ALL PASS'; then chk full-sfs-selftest-same-defs ok "$(echo "$o" | tail -1)"; else chk full-sfs-selftest-same-defs bad; echo "$o" | grep FAIL | head -5; fi
rm -rf "$T"
if [ $ok = $n ]; then echo "SELFTEST SFS-ASK ALL PASS $ok/$n"; exit 0; else echo "SELFTEST SFS-ASK ALL FAIL $ok/$n"; exit 1; fi
