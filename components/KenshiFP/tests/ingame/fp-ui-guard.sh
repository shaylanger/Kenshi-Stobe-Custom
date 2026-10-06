# fp-ui-guard.sh: shared setup guard for the manual-combat wrappers (sourced; needs A() and LOG from the wrapper).
# An NPC conversation (5090 batch 6: a Hungry Bandit's demand, dialogue window = KenshiFP ui mask 0x020) opens the
# dialogue window; KenshiFP then reports ui_open=1 why=ui_open and refuses every manual shot (not_ready).
# ui_guard_setup: fill the hunger of the Hungry Bandits around (cuts the food demands they start).
# ui_clear: before a shot, when KenshiFP sees an open UI: close an open dialogue with the harness `dialog close`
#   (harness 2995EE5E+), else (older harness, no `dialog`) wait up to 30 s for it to close on its own.
#   Counts UI_CLEARED (closed by us) / UI_WAITED (closed on its own) / UI_STUCK (still open); returns 1 when still open.
# raid guard (started by ui_guard_setup): world raids reach the shooter mid-row (5090 b10: Dust Bandits attacked Axima
# during anatomy, targets ran 197 dm, aim on target 1/10). Every 10 s, knock out raider-faction NPCs within 1500 m
# (test NPCs are Drifters/squad, never matched); stops with the wrapper (parent pid check). Logged "RAID GUARD: ko".
UI_CLEARED=0; UI_WAITED=0; UI_STUCK=0
FP_RAID_RE='Band of Bones|Kral.s Chosen|Dust Bandits|Hungry Bandits|Starving Bandits|Bele.coz|Hill Marauders|Black Dragon Ninjas|Berserkers|Cannibals|Fogmen'
FP_RAID_FILTER='[band of bones]|[kral|[dust bandits]|[hungry bandits]|[starving bandits]|[bele|[hill marauders]|[black dragon ninjas]|[berserkers]|[cannibals]|[fogmen]'
raid_sweep() { local h
  for h in $(stobe-auto chars 1500 "$FP_RAID_FILTER" 2>/dev/null | sed 's/^[0-9]* within [0-9.]*: //' | tr '|' '\n' | sed 's/^ *//' \
      | grep -E "\[($FP_RAID_RE)\]" | grep -v -E ' (KO|DEAD)( |$)' | grep -oE '#[0-9]+/[0-9]+' | sort -u); do
    stobe-auto ko "$h" 21600 >/dev/null 2>&1 && echo "RAID GUARD: ko $h" >> "$LOG"; done; }
raid_guard_start() { local p=$$; raid_sweep; ( while kill -0 "$p" 2>/dev/null; do sleep 10; raid_sweep; done ) >/dev/null 2>&1 & }
ui_guard_setup() { local s
  for s in $(A chars 3000 "hungry bandit|!dead" | grep -o '#[0-9]*/[0-9]*'); do A hunger "$s" 300 >/dev/null; done
  raid_guard_start; }
ui_is_open() { A fp_state | grep -q '\bui_open=1\b'; }
ui_clear() { local d end
  ui_is_open || return 0
  # m49 (dec-5090-7): a Left Alt press (key_free_cursor toggle, e.g. an Alt-Tab on the test PC) left KenshiFP in free-cursor
  # mode (ui_why=free): no camera control, every fp_camera look failed for ~10 min. Drop the toggle (S03 recovery command)
  if A fp_state | grep -q '\bfree=1\b'; then echo "UI GUARD: free-cursor toggle on: fp_state free off" >> "$LOG"; A fp_state free off >/dev/null
    ui_is_open || { UI_CLEARED=$((UI_CLEARED+1)); return 0; }; fi
  d=$(A dialog)
  if grep -q '^open=1' <<<"$d"; then
    echo "UI GUARD: dialogue open ($d): closing" >> "$LOG"; A dialog close >/dev/null
    end=$((SECONDS+5)); while [ $SECONDS -lt $end ]; do sleep 0.3; grep -q '^open=0' <<<"$(A dialog)" && ! ui_is_open && { UI_CLEARED=$((UI_CLEARED+1)); return 0; }; done
  fi
  # no dialogue (another panel) or no `dialog` command: wait for it to close on its own
  echo "UI GUARD: ui_open=1 ($(A fp_state | grep -o 'ui_why=[^ ]* .*panels=[^ ]*')) dialog='$(cut -c1-80 <<<"$d")': waiting" >> "$LOG"
  end=$((SECONDS+30)); while [ $SECONDS -lt $end ]; do sleep 0.5; ui_is_open || { UI_WAITED=$((UI_WAITED+1)); return 0; }; done
  UI_STUCK=$((UI_STUCK+1)); return 1; }
ui_summary() { echo "ui_cleared=$UI_CLEARED ui_waited=$UI_WAITED ui_stuck=$UI_STUCK raid_ko=$(grep -c '^RAID GUARD: ko' "$LOG" 2>/dev/null)"; }
