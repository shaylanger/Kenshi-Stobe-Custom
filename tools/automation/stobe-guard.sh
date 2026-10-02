#!/usr/bin/env bash
# stobe-guard.sh (Git Bash): safety checks for automated runs, by stobe.log LINE
# number (never by clock: WSL and Windows clocks differ by an hour).
#   stobe-guard.sh mark                 print the current line count (use as <base>)
#   stobe-guard.sh check <base>         print combat/knockout toward Shay|Malzin since
#                                       <base>; on a hit pause the game, exit 2
#   stobe-guard.sh watch <base> <secs>  check every 5 s for <secs>; exit 2 on a hit
#   stobe-guard.sh since <base> [regex] stobe.log lines after <base> (optional filter)
L=/d/Steam/steamapps/common/Kenshi/RE_Kenshi/mods/Stobe/stobe.log
WHO='(Shay|Malzin)'
ALERT="\[EVENT\] (combat[^]]*-> $WHO \(|knockout: $WHO |death: $WHO )"

check() {
  local hit
  hit=$(tail -n +"$(( $1 + 1 ))" "$L" | grep -a -E "$ALERT" | head -3)
  if [ -n "$hit" ]; then
    echo "ALERT:"; echo "$hit" | cut -c1-200
    MSYS_NO_PATHCONV=1 wsl.exe -d DwemerAI4Skyrim3 -u root --cd / -- stobe-say speed 0 >/dev/null
    return 2
  fi
  return 0
}

case "$1" in
  mark) grep -a -c "" "$L" ;;
  check) check "$2"; exit $? ;;
  watch)
    end=$(( $(date +%s) + $3 ))
    while [ "$(date +%s)" -lt "$end" ]; do check "$2" || exit 2; sleep 5; done ;;
  since) if [ -n "$3" ]; then tail -n +"$(( $2 + 1 ))" "$L" | grep -a -E "$3"; else tail -n +"$(( $2 + 1 ))" "$L"; fi ;;
  *) sed -n '2,8p' "$0"; exit 1 ;;
esac
