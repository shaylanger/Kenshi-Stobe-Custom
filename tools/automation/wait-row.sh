#!/usr/bin/env bash
# wait-row.sh <out-file|batch-dir> [max_s=110]    EXPERIMENTAL (imm26-ctxfix PROPOSAL D; untested in a live operator window).
# Blocks up to max_s (<= 110: the PreToolUse hook denies sleeps > 120 s) and prints exactly ONE line, so a poll costs ~60 tokens instead of a tail dump:
#   file (a row script's captured stdout):  RESULT ... (the whole RESULT/ROW-NEEDS-FIXER line, never shortened below 400 chars)   exit 0 PASS, 1 FAIL, 2 SETUP-FAIL, 3 GATED, 4 NEEDS-FIXER
#                                           RUNNING stage=<last non-empty line, 120 chars> age=<s since last write>              exit 10
#                                           WAITING no output file yet                                                            exit 12
#   batch dir (go-batch.sh results dir):    DONE <summary.txt one line> results=<path>   exit 11     |   RUNNING rows=<n> last=<last result line, 120 chars>   exit 10
# Use it as the foreground wait of a row you started with run_in_background; one call per ~110 s.
T="${1:-}"; M="${2:-110}"; [ -n "$T" ] || { sed -n 2,3p "$0" | cut -c1-200; exit 2; }
[ "$M" -gt 110 ] 2>/dev/null && M=110
one() { printf '%s' "$1" | tr '\n\r\t' '   ' | tr -s ' '; }
end=$((SECONDS+M))
while :; do
  if [ -d "$T" ]; then
    if [ -f "$T/DONE" ]; then s=""; [ -f "$T/summary.txt" ] && s="$(head -c 300 "$T/summary.txt" | tr '\n' ' ')"; echo "DONE $(one "$s" | sed "s/ *$//") results=$T/results.txt"; exit 11; fi
    n=0; last=""; [ -f "$T/results.txt" ] && { n=$(grep -c . "$T/results.txt"); last="$(tail -n 1 "$T/results.txt")"; }
    [ $SECONDS -ge $end ] && { echo "RUNNING rows=$n last=$(one "$last" | cut -c1-120)"; exit 10; }
  elif [ -f "$T" ]; then
    r="$(grep -aE '^(RESULT |ROW-NEEDS-FIXER )' "$T" | tail -n 1)"
    if [ -n "$r" ]; then echo "$(one "$r" | cut -c1-400)"
      case "$r" in "RESULT "*" PASS"*) exit 0;; "RESULT "*" SETUP-FAIL"*) exit 2;; "RESULT "*" GATED"*) exit 3;; "RESULT "*) exit 1;; *) exit 4;; esac; fi
    if [ $SECONDS -ge $end ]; then
      last="$(grep -a . "$T" | tail -n 1)"; age=$(( $(date +%s) - $(stat -c %Y "$T" 2>/dev/null || echo 0) ))
      echo "RUNNING stage=$(one "$last" | cut -c1-120) age=${age}s"; exit 10; fi
  else
    [ $SECONDS -ge $end ] && { echo "WAITING no output file yet: $T"; exit 12; }
  fi
  sleep 3
done
