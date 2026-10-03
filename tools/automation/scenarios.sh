#!/usr/bin/env bash
# scenarios.sh (WSL): reusable test situations built with stobe-auto.
#   (extra squad members are sent 3000 away, not killed: corpses with the same generic
#    name next to the fight took deals and payments in run 12, plan items 47/48)
#   scenarios.sh raid [size]     bandit raid squad on Shay; every raider ordered to attack
#   scenarios.sh bodies <n> [near] [faction]   n neutral bandits killed next to <near> (Malzin);
#                                prints the corpse serials
#   scenarios.sh surrender [template]   (default Dust Bandit raiders; "Hungry Bandit" = tier 0)
#   scenarios.sh raiders         serials of Starving Bandits within 150
#   scenarios.sh fresh           reload auto-home, wait, pause, feed squad, reset Malzin
set -e
# Squad names (env; default the old fixtures' Shay + Malzin). The 4080 fixtures: Full-Base PLAYER=Beaks MATE=Avarek,
# Squin PLAYER=Beak MATE=Kint, Enslaved PLAYER=Izumi MATE=Daphnilis.
PLAYER="${PLAYER:-Shay}"; MATE="${MATE:-Malzin}"
SELF="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"  # works however the script is called (bash scenarios.sh, ./scenarios.sh)
cmd="$1"; shift || true
case "$cmd" in
  raid)
    stobe-auto spawn "Bandit Raiders (weakened) 1" "Starving Bandits" near ${PLAYER} dist 30 count 1 target ${PLAYER} size "${1:-0.1}" >/dev/null
    sleep 1
    for s in $(bash "$SELF" raiders); do stobe-auto attack "$s" ${PLAYER} >/dev/null; done
    echo "raiders: $(bash "$SELF" raiders | wc -l)"
    ;;
  duel)
    # one squad-AI raider against Shay + Malzin (the rest of the raid is killed at once)
    stobe-auto spawn "Bandit Raiders (weakened) 1" "Starving Bandits" near ${PLAYER} dist 4 count 1 target ${PLAYER} size 0.1 >/dev/null
    sleep 1
    keep=""
    for s in $(bash "$SELF" raiders); do
      if [ -z "$keep" ]; then keep="$s"; else stobe-auto teleport "$s" ${PLAYER} dist 3000 >/dev/null; fi
    done
    stobe-auto teleport "$keep" ${PLAYER} dist 3 >/dev/null # inside the outpost walls (else path_failed)
    stobe-auto attack "$keep" ${PLAYER} >/dev/null
    stobe-auto attack ${PLAYER} "$keep" >/dev/null # squad AI may ignore its order; ${PLAYER} starting it works
    stobe-auto attack ${MATE} "$keep" >/dev/null
    echo "$keep"
    ;;
  gang)
    # n squad-AI raiders (default 3) next to Shay, fight started; prints their serials
    n="${1:-3}"
    stobe-auto spawn "Bandit Raiders (weakened) 1" "Starving Bandits" near ${PLAYER} dist 4 count 1 target ${PLAYER} size 0.1 >/dev/null
    sleep 1
    k=0
    for s in $(bash "$SELF" raiders); do
      if [ "$k" -lt "$n" ]; then
        stobe-auto teleport "$s" ${PLAYER} dist 3 >/dev/null
        stobe-auto attack "$s" ${PLAYER} >/dev/null
        echo "$s"; k=$((k+1))
      else
        stobe-auto teleport "$s" ${PLAYER} dist 3000 >/dev/null
      fi
    done
    ;;
  surrender)
    # duel, let them engage, drop the raider to 25 %, wait for his surrender offer;
    # prints "<serial> <name> <deal id>" (deal id empty if none came)
    # Malzin stays out (knocked out 40 m away in camp for 150 s): she defends Shay
    # and knocks him out before his health event goes out.
    L=/mnt/d/Steam/steamapps/common/Kenshi/RE_Kenshi/mods/Stobe/stobe.log
    base=$(grep -a -c "" "$L")
    if stobe-auto where ${PLAYER} | grep -q " KO"; then echo "${PLAYER} is knocked out: run '$0 fresh' first" >&2; exit 1; fi
    # Item 87: Stobe guards a personal fight for 180 s and stands down every other member of that
    # faction who targets the same victim (run m8: Dust King spawned 160 s after Skarven's fight was
    # stood down, no encounter, no health event, no offer). Wait until no guard is active.
    for i in $(seq 1 40); do
      last_reg=$(grep -a -n "PERSONAL_FIGHT: registered" "$L" | tail -1 | cut -d: -f1)
      last_end=$(grep -a -n "PERSONAL_FIGHT: ended" "$L" | tail -1 | cut -d: -f1)
      [ -z "$last_reg" ] && break
      [ -n "$last_end" ] && [ "$last_end" -gt "$last_reg" ] && break
      [ "$i" = 1 ] && echo "waiting for the last personal fight guard to end (max 200 s)" >&2
      stobe-say speed 1 >/dev/null; sleep 5
    done
    # parked 300 away she landed among wild bandits twice (runs 10, m1): keep her in camp, knocked out
    stobe-auto teleport ${MATE} ${PLAYER} dist 40 >/dev/null; stobe-auto ko ${MATE} 150 >/dev/null
    T="${1:-Bandit Raiders (weakened) 1}"  # optional: another squad/character template (e.g. "Hungry Bandit", tier 0)
    if [ "$T" = "Bandit Raiders (weakened) 1" ]; then stobe-auto spawn "$T" "Starving Bandits" near ${PLAYER} dist 4 count 1 target ${PLAYER} size 0.1 >/dev/null
    else stobe-auto spawn "$T" "Starving Bandits" near ${PLAYER} dist 4 count 1 >/dev/null; fi
    sleep 1
    r=""
    for s in $(bash "$SELF" raiders); do
      if [ -z "$r" ]; then r="$s"; else stobe-auto teleport "$s" ${PLAYER} dist 3000 >/dev/null; fi
    done
    [ -n "$r" ] || { stobe-auto speed 0 >/dev/null; echo "no raider found: paused" >&2; exit 1; }
    stobe-auto teleport "$r" ${PLAYER} dist 3 >/dev/null
    name=$(stobe-auto where "$r" | sed -E 's/ #[0-9].*//')
    stobe-say speed 1 >/dev/null
    for i in $(seq 1 15); do # until he really swings at ${PLAYER} (squad AI ignores some orders)
      stobe-auto attack "$r" ${PLAYER} >/dev/null; stobe-auto attack ${PLAYER} "$r" >/dev/null
      sleep 4
      tail -n +"$base" "$L" | grep -a -F "[EVENT] combat: $name" | grep -a -q -- "-> ${PLAYER}" && break
    done
    for i in $(seq 1 10); do # the encounter must exist, else no health event goes out
      tail -n +"$base" "$L" | grep -a -F "[EVENT] combat_start" | grep -a -q -F "$name" && break
      sleep 2
    done
    stobe-auto health "$r" 25 >/dev/null
    name=$(stobe-auto where "$r" | sed -E 's/ #[0-9].*//') # he may have been named meanwhile
    deal=""
    for i in $(seq 1 12); do
      sleep 5
      deal=$(cd /tmp && sudo -u www-data php /var/www/html/StobeServer/tools/negotiation_admin.php deals 3 2>/dev/null \
             | grep -F "$name" | grep -E "PROPOSED|COUNTERED" | awk '{print $1}' | head -1)
      [ -n "$deal" ] && break
    done
    stobe-say speed 0 >/dev/null
    # bring Malzin back next to Shay (she was knocked out 40 m away)
    stobe-auto teleport ${MATE} ${PLAYER} dist 6 >/dev/null
    tail -n +"$base" "$L" | grep -a -q -E "\[EVENT\] combat.*${MATE}" && echo "WARNING: ${MATE} fought while away" >&2
    echo "$r|$name|$deal"
    ;;
  trust)
    # trust <npc name> <aff> [tier] [type]: set the NPC's relationship to Shay (test data).
    # jsonb_set on a missing 'relationships' key silently does nothing, so merge.
    name="$1"; aff="${2:-60}"; tier="${3:-Fond}"; rtype="${4:-friend}"
    cd /tmp && sudo -u postgres psql -d stobe -At -c "UPDATE core_npc_master SET extended_data =
      jsonb_set(coalesce(extended_data,'{}'::jsonb), '{relationships}',
        coalesce(extended_data->'relationships','{}'::jsonb) || jsonb_build_object('${PLAYER}',
          jsonb_build_object('aff',$aff,'tier','$tier','type','$rtype','note','test','updated_at',extract(epoch from now())::int)))
      WHERE lower(name)=lower('$name') RETURNING extended_data->'relationships'->'${PLAYER}'->>'aff'"
    stobe-rel-stamp "$name" || true  # item 59: stamp the edit with the current game time
    ;;
  raiders)
    stobe-auto chars 150 | tr '|' '\n' | grep 'Starving Bandits' | grep -v -e ' DEAD' -e ' KO' | grep -oE '#[0-9]+/[0-9]+' || true
    ;;
  bodies)
    n="${1:-2}"; near="${2:-${MATE}}"; faction="${3:-Drifters}"
    out=$(stobe-auto spawn "Hungry Bandit" "$faction" near "$near" dist 5 count "$n")
    for s in $(echo "$out" | grep -oE '#[0-9]+/[0-9]+'); do stobe-auto kill "$s" >/dev/null; echo "$s"; done
    ;;
  fresh)
    stobe-auto load auto-home >/dev/null; sleep 12; stobe-auto wait-world 180 >/dev/null; sleep 5
    stobe-say speed 0 >/dev/null
    stobe-auto hunger ${MATE} 250 >/dev/null; stobe-auto hunger ${PLAYER} 250 >/dev/null
    stobe-reset-npc ${MATE} >/dev/null
    echo "fresh: $(stobe-auto status)"
    ;;
  *) sed -n '2,8p' "$0"; exit 1 ;;
esac
