import sys
p=sys.argv[1]; s=open(p,encoding="utf-8",newline="").read()
start=s.index("# calm_raiders [radius] [factions-regex]")
end=s.index('  log "calm_raiders: knocked out $n"\n}\n',start)+len('  log "calm_raiders: knocked out $n"\n}\n')
new=r'''# RAID_RE: world-raid factions that reach the squad on Full-Base (m17 Band of Bones; m24 Bele'coz, Hill Marauders,
# Black Dragon Ninjas; m22 J Kral's Chosen). RAID_FILTER: the same for the harness `chars <r> <filter>` (m26).
RAID_RE="${RAID_RE:-Band of Bones|Kral.s Chosen|Dust Bandits|Hungry Bandits|Starving Bandits|Bele.coz|Hill Marauders|Black Dragon Ninjas}"
RAID_FILTER="${RAID_FILTER:-[band of bones]|[kral|[dust bandits]|[hungry bandits]|[starving bandits]|[bele|[hill marauders]|[black dragon ninjas]}"
# calm_raiders [radius] [factions-regex]: knock out world raiders near the squad for RAID_KO_S game seconds (Full-Base
# gets raids that reach the squad mid-test, m17); logs how many
calm_raiders() {
  local n=0 h re="${2:-$RAID_RE}" flt=""
  [ -z "${2:-}" ] && flt="$RAID_FILTER"
  # m24 fixer 14: `chars` prints ONE line ("a | b | c"), so the faction grep matched the whole line whenever any raider
  # was in range and every handle in it was knocked out, the squad included (harness.log: `ko Beaks`/`ko Avarek` every
  # 30 s; 16-fullbase Avarek KO x3, A8-grow-fb Beaks KO). Split per character first; never touch the squad; skip ones
  # already KO/DEAD.
  # m26: `chars` lists at most 40 (unsorted) and Full-Base has more within 1500 m, so raiders were cut off (m22 J:
  # Kral's Chosen hit Beaks in 16-fullbase, Band of Bones KO'd Beaks in A8). The harness filter (KAH chars [filter])
  # applies before the cap; an older harness ignores it and the faction grep below still filters.
  # m26: `ko` seconds are game seconds: 900 lasted ~18 s at 50x; RAID_KO_S (6 game hours) outlasts a sweep interval.
  local r lines seen=" "
  for r in 400 "${1:-400}"; do
    lines=$(stobe-auto chars "$r" ${flt:+"$flt"} | sed 's/^[0-9]* within [0-9.]*: //' | tr '|' '\n' | sed 's/^ *//' \
      | grep -E "\[(${re})\]" | grep -v -E ' (KO|DEAD)( |$)' | grep -v -E "^(${PLAYER:-Shay}|${MATE:-Malzin}) #")
    for h in $(echo "$lines" | grep -oE '#[0-9]+/[0-9]+'); do
      case "$seen" in *" $h "*) continue ;; esac; seen="$seen$h "
      stobe-auto ko "$h" "${RAID_KO_S:-21600}" >/dev/null && n=$((n+1))
    done
    [ "${1:-400}" = 400 ] && break
  done
  log "calm_raiders: knocked out $n"
}
# raid_guard_start [every_s] / raid_guard_stop (m26, Full-Base rows): the squad stays protected (fullbase-guard.sh)
# and a background sweep knocks out raiders within 1500 m every RAID_GUARD_EVERY s (10) for the whole row; knockouts
# are logged (stderr) so a row shows when raids happened. Call raid_guard_stop in the EXIT trap.
raid_guard_start() {
  local every="${1:-${RAID_GUARD_EVERY:-10}}"
  calm_raiders 1500
  ( while sleep "$every"; do calm_raiders 1500 2>&1 | grep -v 'knocked out 0$' >&2; done ) </dev/null &
  RAID_GUARD=$!
  log "raid_guard: sweeping raiders within 1500 m every ${every} s (pid $RAID_GUARD)"
}
raid_guard_stop() { [ -n "${RAID_GUARD:-}" ] && kill "$RAID_GUARD" 2>/dev/null; RAID_GUARD=""; }
# raid_event <stobe [EVENT] line>: 0 when a combat/knockout event against the squad comes from a world raider
# (RAID_RE faction; a knockout names only the attacker, so his faction comes from his combat lines since the test
# start). Alerts skip these on protected Full-Base rows; anything else (guards, shop owners, the mate) still alerts.
raid_event() {
  local line who
  line=$(printf '%s' "$1" | tr -d '\r')
  echo "$line" | grep -q -a -E "combat: .* \((${RAID_RE})\) -> " && return 0
  who=$(echo "$line" | grep -a -oE "knockout: .* from .*\)$" | sed -E 's/.* from (.*)\)$/\1/')
  [ -n "$who" ] || return 1
  since_stobe | grep -a -F "combat: $who (" | grep -q -a -E "combat: .* \((${RAID_RE})\) -> "
}
awake() { ! stobe-auto where "$1" 2>&1 | grep -q -E " (KO|DEAD)( |$)"; }
'''
s=s[:start]+new+s[end:]
open(p,"w",encoding="utf-8",newline="").write(s)
print("ok")
