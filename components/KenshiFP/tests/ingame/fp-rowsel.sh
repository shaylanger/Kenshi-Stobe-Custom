# fp-rowsel.sh: sourced by multi-row take scripts (fp-manual-hits-rows.sh, fp-manual-anatomy-rows.sh).
# (1) Row selector: rows_init "<all rows>" "<selection>" sets ROWS (selection: space/comma/| separated, empty or "all" =
#     every row; unknown names = setup FAIL) and SETUP_ROWS; `want <row>` is true for a selected row. One list row per
#     sub-row keeps every row short and independently rerunnable (Shay speed rule 5, 2026-10-11).
# (2) Dead-game abort: gd_note "<harness reply>" (call from A() after every stobe-auto call; works inside $(...) subshells)
#     counts consecutive "is Kenshi running?" / "inbox locked" replies in $OUT/.gd; at GD_MAX (6) it signals the main
#     shell, which prints the rows already judged plus `RESULT <row> FAIL setup: game not responding` for the rest and exits
#     at once (tdr-mix-5090b R11 2026-10-11: a hung game made eye_dist empty, `[: : integer expression expected`, and the
#     row looped on dead replies until the runner killed it, exit 137, no RESULT line).
# Needs: OUT, LOG, RESULTS (array, filled by row()), and the caller's cleanup trap on EXIT (skipped calls when GD_DEAD=1).
GD_MAX=${GD_MAX:-6}; GD_DEAD=""
rows_init() { local all="$1" sel r; sel=$(tr ',|' '  ' <<<"${2:-}" | xargs)
  [ -z "$sel" ] || [ "$sel" = all ] && sel=$all
  for r in $sel; do [[ " $all " == *" $r "* ]] || { echo "RESULT $r FAIL setup: unknown row (rows: $all)"; exit 1; }; done
  ROWS=$sel; SETUP_ROWS=$sel; : > "$OUT/.gd"; trap gd_abort USR1; }
want() { [[ " $ROWS " == *" $1 "* ]]; }
gd_note() { [ -n "$GD_DEAD" ] && return 0
  case "$1" in *"is Kenshi running?"*|*"inbox locked by another client"*)
      echo x >> "$OUT/.gd"; [ "$(wc -l < "$OUT/.gd")" -ge "$GD_MAX" ] && kill -USR1 $$ 2>/dev/null;;
    *) [ -s "$OUT/.gd" ] && : > "$OUT/.gd";; esac; return 0; }
gd_abort() { local r l done=" "; GD_DEAD=1; trap - USR1
  echo "GAME NOT RESPONDING: $GD_MAX harness calls in a row got no answer; last: $(tail -1 "$LOG" | cut -c1-200)" >> "$LOG"
  for l in "${RESULTS[@]}"; do r=$(cut -d' ' -f2 <<<"$l"); done+="$r "
    case "$l" in *FAIL*) echo "$l log=$LOG";; *) echo "$l";; esac; done
  for r in $ROWS; do [[ "$done" == *" $r "* ]] || echo "RESULT $r FAIL setup: game not responding (harness: $(tail -1 "$LOG" | sed 's/.*| //' | cut -c1-80)) log=$LOG"; done
  exit 1; }
