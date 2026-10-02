#!/usr/bin/env bash
# scenarios.sh (WSL): reusable test situations built with stobe-auto.
#   scenarios.sh raid [size]     bandit raid squad on Shay; every raider ordered to attack
#   scenarios.sh bodies <n> [near] [faction]   n neutral bandits killed next to <near> (Malzin);
#                                prints the corpse serials
#   scenarios.sh raiders         serials of Starving Bandits within 150
#   scenarios.sh fresh           reload auto-home, wait, pause, feed squad, reset Malzin
set -e
cmd="$1"; shift || true
case "$cmd" in
  raid)
    stobe-auto spawn "Bandit Raiders (weakened) 1" "Starving Bandits" near Shay dist 30 count 1 target Shay size "${1:-0.1}" >/dev/null
    sleep 1
    for s in $("$0" raiders); do stobe-auto attack "$s" @player >/dev/null; done
    echo "raiders: $("$0" raiders | wc -l)"
    ;;
  duel)
    # one squad-AI raider against Shay + Malzin (the rest of the raid is killed at once)
    stobe-auto spawn "Bandit Raiders (weakened) 1" "Starving Bandits" near Shay dist 4 count 1 target Shay size 0.1 >/dev/null
    sleep 1
    keep=""
    for s in $("$0" raiders); do
      if [ -z "$keep" ]; then keep="$s"; else stobe-auto kill "$s" >/dev/null; fi
    done
    stobe-auto teleport "$keep" Shay dist 3 >/dev/null # inside the outpost walls (else path_failed)
    stobe-auto attack "$keep" @player >/dev/null
    stobe-auto attack @player "$keep" >/dev/null # squad AI may ignore its order; Shay starting it works
    stobe-auto attack Malzin "$keep" >/dev/null
    echo "$keep"
    ;;
  surrender)
    # duel, let them engage, drop the raider to 25 %, wait for his surrender offer;
    # prints "<serial> <name> <deal id>" (deal id empty if none came)
    L=/mnt/d/Steam/steamapps/common/Kenshi/RE_Kenshi/mods/Stobe/stobe.log
    base=$(grep -a -c "" "$L")
    r=$("$0" duel)
    stobe-say speed 1 >/dev/null
    for i in $(seq 1 6); do # wait for the fight to really start, re-ordering the attack
      sleep 10
      tail -n +"$base" "$L" | grep -a -q "\[EVENT\] combat_start" && break
      stobe-auto attack "$r" @player >/dev/null; stobe-auto attack @player "$r" >/dev/null
    done
    sleep 5
    stobe-auto health "$r" 25 >/dev/null
    name=$(stobe-auto where "$r" | sed -E 's/ #[0-9]+ .*//')
    deal=""
    for i in $(seq 1 12); do
      sleep 5
      deal=$(cd /tmp && sudo -u www-data php /var/www/html/StobeServer/tools/negotiation_admin.php deals 3 2>/dev/null \
             | grep -F "$name" | grep -E "PROPOSED|COUNTERED" | awk '{print $1}' | head -1)
      [ -n "$deal" ] && break
    done
    stobe-say speed 0 >/dev/null
    echo "$r|$name|$deal"
    ;;
  raiders)
    stobe-auto chars 150 | tr '|' '\n' | grep 'Starving Bandits' | grep -v ' DEAD' | grep -o '#[0-9]*' || true
    ;;
  bodies)
    n="${1:-2}"; near="${2:-Malzin}"; faction="${3:-Drifters}"
    out=$(stobe-auto spawn "Hungry Bandit" "$faction" near "$near" dist 5 count "$n")
    for s in $(echo "$out" | grep -o '#[0-9]*'); do stobe-auto kill "$s" >/dev/null; echo "$s"; done
    ;;
  fresh)
    stobe-auto load auto-home >/dev/null; sleep 12; stobe-auto wait-world 180 >/dev/null; sleep 5
    stobe-say speed 0 >/dev/null
    stobe-auto hunger Malzin 250 >/dev/null; stobe-auto hunger Shay 250 >/dev/null
    stobe-reset-npc Malzin >/dev/null
    echo "fresh: $(stobe-auto status)"
    ;;
  *) sed -n '2,8p' "$0"; exit 1 ;;
esac
