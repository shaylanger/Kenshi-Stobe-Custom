#!/bin/bash
# dialog-guard.sh check | watch <pid> <log>   (WSL or 4080 Git Bash; needs stobe-auto on PATH)
# An NPC conversation (a bandit's food/toll demand, a raid leader's talk) opens the game's dialogue window; KenshiFP then
# reports ui_open=1 (ui_why=panels/ui_open) and refuses every manual click / shot, and the row stalls silently
# (5090 2026-10-10 batch 20-rg04-melee-rerun row M08: "Dust Bandit" talked to Shay; M08-CROWD/M08-ACTOR FAILed with
# gate[ui_open=1], the window stayed open until the coordinator closed it by hand). Setup misses list: harness
# docs/animlab/STATUS.md "Setup misses" (dialog-open).
#   check   before a row (run-batch.sh after the load; dryrun row.sh the same): close an open conversation with the
#           harness `dialog close` (Dialogue::endDialogue, as when the talk runs out) and poll until open=0 (5 s).
#           Prints one line: `DIALOG none` | `DIALOG closed speaker=<npc> player=<who>` | `DIALOG n/a <reply>` (harness
#           without `dialog`) | `DIALOG stuck speaker=<npc> ...` (exit 1: the row must stop with
#           `RESULT <row> FAIL setup: dialog <speaker>`).
#   watch   during a row: every DIALOG_POLL s (default 2) while <pid> lives, the same close; each event is one line in
#           <log> (`<time> DIALOG GUARD: closed|stuck speaker=<npc> player=<who>`); run-batch.sh turns them into a NOTE.
# A row that opens a conversation on purpose sets DIALOG_GUARD=0 in its list command (run-batch.sh then skips both).
DA(){ stobe-auto dialog "$@" </dev/null 2>&1 | tr -d '\r'; }
spk(){ sed -n 's/.* speaker=\(.*\) player=\(.*\) ended=.*/speaker=\1 player=\2/p' <<<"$1" | head -1; }
# one pass: 0 = nothing open / closed (line on stdout), 1 = still open after close, 2 = no dialog command
dg_once(){ local d e who
  d=$(DA)
  grep -q '^open=' <<<"$d" || { echo "DIALOG n/a $(head -1 <<<"$d" | cut -c1-80)"; return 2; }
  grep -q '^open=1' <<<"$d" || { echo "DIALOG none"; return 0; }
  who=$(spk "$d"); [ -n "$who" ] || who="speaker=? $(cut -c1-80 <<<"$d")"
  DA close >/dev/null
  e=$((SECONDS + 5))
  while [ $SECONDS -lt $e ]; do sleep 0.3; grep -q '^open=0' <<<"$(DA)" && { echo "DIALOG closed $who"; return 0; }; done
  echo "DIALOG stuck $who (still open 5 s after dialog close)"; return 1; }
case "${1:-}" in
  check) dg_once; r=$?; [ $r = 1 ] && exit 1; exit 0 ;;
  watch) p=${2:?watch <pid> <log>}; lg=${3:?watch <pid> <log>}
    while kill -0 "$p" 2>/dev/null; do
      sleep "${DIALOG_POLL:-2}"; kill -0 "$p" 2>/dev/null || break
      l=$(dg_once); r=$?
      [ $r = 2 ] && break                                   # old harness: nothing to watch with
      [ "$l" = "DIALOG none" ] || echo "$(date +%H:%M:%S) DIALOG GUARD: ${l#DIALOG }" >> "$lg"
    done ;;
  *) sed -n '2,18p' "$0"; exit 2 ;;
esac
