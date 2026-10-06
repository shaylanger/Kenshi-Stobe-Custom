# fp-ui-guard.sh: shared setup guard for the manual-combat wrappers (sourced; needs A() and LOG from the wrapper).
# An NPC conversation (5090 batch 6: a Hungry Bandit's demand, dialogue window = KenshiFP ui mask 0x020) opens the
# dialogue window; KenshiFP then reports ui_open=1 why=ui_open and refuses every manual shot (not_ready).
# ui_guard_setup: fill the hunger of the Hungry Bandits around (cuts the food demands they start).
# ui_clear: before a shot, when KenshiFP sees an open UI: close an open dialogue with the harness `dialog close`
#   (harness 2995EE5E+), else (older harness, no `dialog`) wait up to 30 s for it to close on its own.
#   Counts UI_CLEARED (closed by us) / UI_WAITED (closed on its own) / UI_STUCK (still open); returns 1 when still open.
UI_CLEARED=0; UI_WAITED=0; UI_STUCK=0
ui_guard_setup() { local s
  for s in $(A chars 3000 "hungry bandit|!dead" | grep -o '#[0-9]*/[0-9]*'); do A hunger "$s" 300 >/dev/null; done; }
ui_is_open() { A fp_state | grep -q '\bui_open=1\b'; }
ui_clear() { local d end
  ui_is_open || return 0
  d=$(A dialog)
  if grep -q '^open=1' <<<"$d"; then
    echo "UI GUARD: dialogue open ($d): closing" >> "$LOG"; A dialog close >/dev/null
    end=$((SECONDS+5)); while [ $SECONDS -lt $end ]; do sleep 0.3; grep -q '^open=0' <<<"$(A dialog)" && ! ui_is_open && { UI_CLEARED=$((UI_CLEARED+1)); return 0; }; done
  fi
  # no dialogue (another panel) or no `dialog` command: wait for it to close on its own
  echo "UI GUARD: ui_open=1 ($(A fp_state | grep -o 'ui_why=[^ ]* .*panels=[^ ]*')) dialog='$(cut -c1-80 <<<"$d")': waiting" >> "$LOG"
  end=$((SECONDS+30)); while [ $SECONDS -lt $end ]; do sleep 0.5; ui_is_open || { UI_WAITED=$((UI_WAITED+1)); return 0; }; done
  UI_STUCK=$((UI_STUCK+1)); return 1; }
ui_summary() { echo "ui_cleared=$UI_CLEARED ui_waited=$UI_WAITED ui_stuck=$UI_STUCK"; }
