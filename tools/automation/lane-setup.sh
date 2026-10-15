#!/usr/bin/env bash
# lane-setup.sh: ONE-COMMAND reset of an isolated imm26 game lane to a testable state (imm26 speed item 3, 2026-10-15).
#
#   lane-setup.sh <5090|4080> <instance 3..9> <save|-> [options]
#
# Sequence (all through that lane's own harness: RIG/KAH_INSTANCE + rig-env.sh, same route as the *-imm26-lib.sh helpers):
#   1 route + inbox check, `status`                     (lane must answer; harness inbox must not be pending)
#   2 load <save>, speed 0 hold, wait-world 180, +5 s    (skipped when <save> is `-` or --no-load; save must be a kah-* copy)
#   3 speed 0 hold again (authoritative), verify paused/speed 0
#   4 squad = every live character of --player's faction (+ every --with NAME): wake if KO, health 100, hunger 300, protect on; select <player>
#   5 teleport the player to --teleport x y z (default The Hub -50978 1533 2960), the others spread +8 x / +5 z each; retry on moved=0
#   6 clear hostile outlaws (default faction "Holy Nation Outlaws"): `relation` +20 (ends the game's enemy flag, so they stop
#     KO-ing the player) and teleport them to --away x y z (default -53200 957 4893, the spot the op2b operator used)
#   7 speed 0.5 hold (the game runs ~25x real time otherwise), wait 10 s, clear outlaws again
#   8 verify real state: phase=world, speed=0.5, loaded save, player conscious and within 150 units of the target,
#     protect list contains the squad; prints exactly one line:
#       RESULT lane-setup <rig> i<n> PASS|FAIL <evidence>
#
# Options: --teleport X Y Z | --away X Y Z | --player NAME (default Shay) | --with NAME (repeatable, e.g. Cind) |
#          --clear-faction NAME (repeatable; default "Holy Nation Outlaws"; use --clear-faction none to skip) |
#          --speed V (default 0.5) | --no-load | --dry-run [--probe] | --selftest
#   --dry-run  prints the route, the executor command and the planned commands; sends NOTHING to the game.
#              --probe adds ONE read-only `status` + `where <player>` through the real route (proves the lane answers).
#   --selftest offline checks (arg parsing, body syntax, chars parser, route table, guards); no game, no ssh.
# Run it from the 5090 Git Bash or WSL (4080 lanes go over `ssh 4080`), or from the 4080 Git Bash for 4080 lanes.
# Log: C:\KenshiTestRuns\lane-setup\<rig>-i<n>-<time>.log. Never run on a lane an operator is using for a row (it reloads the save).
# Isolation: instance >= 3 only (instance 1 = the main install, 2 = older lane); never touches the live server or DB.

LS_SELF=$(readlink -f "${BASH_SOURCE[0]}" 2>/dev/null || echo "${BASH_SOURCE[0]}")

# ---- the lane-side body: runs where stobe-auto lives (WSL on the 5090, Git Bash on the 4080) ----
# PRELUDE = pure functions (selftested offline); MAIN = the game commands.
ls_prelude() { cat <<'EOS'
A() { stobe-auto "$@" </dev/null 2>&1; }
# chars/where output -> "#serial/idx|faction|name" per character (entries are separated by " | ", the first has a "N within R: " prefix)
ls_parse() { sed -e 's/ | /\n/g' | sed -E -e 's/^[0-9]+ within [0-9.]+: //' -e 's/ race=.*$//' \
  | sed -nE 's/^(.*) (#[0-9]+\/[0-9]+) \[([^]]*)\] pos=.*$/\2|\3|\1/p'; }
ls_pos() { sed -nE 's/.* pos=(-?[0-9.]+),(-?[0-9.]+),(-?[0-9.]+).*/\1 \2 \3/p' | head -1; }
ls_speed() { sed -nE 's/.* speed=(-?[0-9.]+).*/\1/p' | head -1; }
ls_num_eq() { awk -v a="$1" -v b="$2" 'BEGIN{d=a-b; if(d<0)d=-d; exit !(d<0.01)}'; }
ls_dist2d() { awk -v x1="$1" -v z1="$2" -v x2="$3" -v z2="$4" 'BEGIN{dx=x1-x2; dz=z1-z2; printf "%d", sqrt(dx*dx+dz*dz)}'; }
EOS
}
ls_main() { cat <<'EOS'
fail() { echo "RESULT lane-setup $RIG i$KAH_INSTANCE FAIL $*"; exit 1; }
step() { echo "STEP $*"; }
EXP=/mnt/d/KenshiInst/$KAH_INSTANCE; [ "$RIG" = 4080 ] && EXP=/c/KenshiInst/$KAH_INSTANCE
[ "$KDIR" = "$EXP" ] || fail "route: KDIR=$KDIR expected $EXP"
HD="$KDIR/mods/AutomationHarness"; [ -d "$HD" ] || fail "route: no harness dir $HD"
for i in 1 2 3 4 5; do { [ -e "$HD/inbox.txt" ] || [ -e "$HD/inbox.txt.lock" ]; } || break; sleep 3; done
{ [ -e "$HD/inbox.txt" ] || [ -e "$HD/inbox.txt.lock" ]; } && fail "inbox pending or locked (another operator is driving this lane?)"
step "1 status"; ST=$(A status); echo "$ST"
echo "$ST" | grep -q 'phase=' || fail "status: lane does not answer: $ST"
if [ "$NOLOAD" != 1 ]; then
  [ -d "$KDIR/save/$SAVE" ] || fail "save not found: $KDIR/save/$SAVE"
  step "2 load $SAVE"; A load "$SAVE" | head -2
  A speed 0 hold >/dev/null  # best effort while the world is still loading (the authoritative one follows wait-world)
  sleep 12
  W=$(A wait-world 180); echo "$W" | tail -1
  echo "$W" | grep -qiE 'error|timeout|timed out' && fail "wait-world: $W"
  sleep 5
fi
step "3 speed 0 hold"; A speed 0 hold | head -1
ST=$(A status); echo "$ST"
echo "$ST" | grep -q 'phase=world' || fail "not in world after load: $ST"
if [ "$NOLOAD" != 1 ]; then echo "$ST" | grep -Eq "save=$SAVE( |\$)" || fail "loaded save is not $SAVE: $ST"; fi
ls_num_eq "$(echo "$ST" | ls_speed)" 0 || fail "speed is not 0 after hold: $ST"
step "4 squad: wake/heal/protect"
WP=$(A where "$PLAYER"); echo "$WP"
echo "$WP" | grep -q '^ERROR' && fail "player $PLAYER not found: $WP"
PF=$(echo "$WP" | ls_parse | head -1 | cut -d'|' -f2); [ -n "$PF" ] || fail "cannot parse player faction: $WP"
SQ=$(A chars 1000000 "[$PF]|!dead" | ls_parse | awk -F'|' -v f="$PF" '$2==f{print $1"|"$3}')
WITHIDS=""
while IFS= read -r w; do [ -n "$w" ] || continue
  r=$(A where "$w"); echo "$r" | grep -q '^ERROR' && fail "--with $w not found: $r"
  id=$(echo "$r" | ls_parse | head -1 | cut -d'|' -f1); SQ="$SQ"$'\n'"$id|$w"
done <<< "$WITH"
SQ=$(echo "$SQ" | sed '/^$/d' | awk -F'|' '!s[$1]++')
NSQ=$(echo "$SQ" | grep -c .); [ "$NSQ" -ge 1 ] || fail "empty squad for faction $PF"
echo "squad ($NSQ):"; echo "$SQ"
PR=0; WOKE=0
while IFS='|' read -r id nm; do [ -n "$id" ] || continue
  if A where "$id" | grep -Eq ' KO( |$)'; then A wake "$id" | head -1; WOKE=$((WOKE+1)); sleep 1; fi
  A health "$id" 100 | head -1 >/dev/null; A hunger "$id" 300 | head -1 >/dev/null
  A protect "$id" on | head -1; PR=$((PR+1))
done <<< "$SQ"
A select "$PLAYER" | head -1
step "5 teleport -> $TX $TY $TZ"
k=0; TPFAIL=0
while IFS='|' read -r id nm; do [ -n "$id" ] || continue
  if [ "$nm" = "$PLAYER" ]; then x=$TX; z=$TZ; else k=$((k+1)); x=$((TX+8*k)); z=$((TZ+5*k)); fi
  ok=0; for t in 1 2 3; do r=$(A teleport "$id" "$x" "$TY" "$z"); echo "$r" | grep -q 'moved=1' && { ok=1; break; }; sleep 3; done
  [ $ok = 1 ] || { TPFAIL=$((TPFAIL+1)); echo "teleport $nm not moved: $r"; }
done <<< "$SQ"
sleep 6
clear_outlaws() {  # clear_outlaws <label>: relation +20 on each faction, teleport members to AWAY; sets CLEARED
  local f ids n=0 first
  while IFS= read -r f; do [ -n "$f" ] || continue; [ "$f" = none ] && continue
    for rd in 1 2 3 4; do  # chars lists at most 40, so repeat until none is left
      ids=$(A chars 1500 "[$f]|!dead" | ls_parse | awk -F'|' -v f="$f" '$2==f{print $1}')
      [ -n "$ids" ] || break
      first=$(echo "$ids" | head -1); [ $rd = 1 ] && A relation "$first" 20 | head -1
      for id in $ids; do A teleport "$id" "$AX" "$AY" "$AZ" | grep -q 'moved=1' && n=$((n+1)); done
      sleep 2
    done
  done <<< "$CLEAR"
  CLEARED=$((CLEARED+n)); echo "outlaws $1: moved $n"
}
CLEARED=0
step "6 clear hostile outlaws"; clear_outlaws pass1
step "7 speed $SPEEDF hold"; A speed "$SPEEDF" hold | head -1
sleep 10; clear_outlaws after-unpause
step "8 verify"
ST=$(A status); echo "$ST"
SPD=$(echo "$ST" | ls_speed)
WP=$(A where "$PLAYER"); echo "$WP"
PP=$(echo "$WP" | ls_pos); KO=0; echo "$WP" | grep -Eq ' KO( |$)' && KO=1
DEAD=0; echo "$WP" | grep -Eq ' DEAD( |$)' && DEAD=1
OFF=-1; if [ -n "$PP" ]; then set -- $PP; OFF=$(ls_dist2d "$1" "$3" "$TX" "$TZ"); fi
PL=$(A protect); NPROT=0; while IFS='|' read -r id nm; do [ -n "$id" ] || continue; echo "$PL" | grep -qF "${nm%% \[*}" && NPROT=$((NPROT+1)); done <<< "$SQ"
HP=$(A hp "$PLAYER" | head -1 | sed -nE 's/.*worst=([0-9.]+)%.*/\1/p')
LEFT=0; while IFS= read -r f; do [ -n "$f" ] && [ "$f" != none ] || continue; n=$(A chars 600 "[$f]|!dead|!ko" | ls_parse | awk -F'|' -v f="$f" '$2==f' | wc -l); LEFT=$((LEFT+n)); done <<< "$CLEAR"
EV="save=${SAVE} phase=$(echo "$ST" | sed -nE 's/.*phase=([a-z]+).*/\1/p') speed=$SPD paused=$(echo "$ST" | sed -nE 's/.*paused=([0-9]).*/\1/p') player=$PLAYER ko=$KO dead=$DEAD pos=${PP// /,} off_target=$OFF hp_worst=${HP:-?} squad=$NSQ protected=$NPROT woke=$WOKE tp_fail=$TPFAIL outlaws_moved=$CLEARED outlaws_still_near_600=$LEFT"
echo "$ST" | grep -q 'phase=world' || fail "$EV (not in world)"
ls_num_eq "$SPD" "$SPEEDF" || fail "$EV (speed != $SPEEDF)"
[ "$KO" = 0 ] && [ "$DEAD" = 0 ] || fail "$EV (player KO/dead)"
[ "$OFF" -ge 0 ] && [ "$OFF" -le 150 ] || fail "$EV (player not at target)"
[ "$NPROT" -ge 1 ] || fail "$EV (protect list does not contain the squad)"
echo "RESULT lane-setup $RIG i$KAH_INSTANCE PASS $EV"
EOS
}

ls_usage() { sed -n '2,/^# Isolation/p' "$LS_SELF" | sed 's/^# \{0,1\}//'; }

# ---- argument parsing -> LS_* variables (shared by run / dry-run / selftest) ----
ls_parse_args() {
  LS_TX=-50978 LS_TY=1533 LS_TZ=2960; LS_AX=-53200 LS_AY=957 LS_AZ=4893
  LS_PLAYER=Shay LS_WITH=""; LS_CLEAR=""; LS_SPEED=0.5; LS_NOLOAD=0; LS_DRY=0; LS_PROBE=0; LS_SELFTEST=0
  local pos=() num='^-?[0-9]+(\.[0-9]+)?$'
  while [ $# -gt 0 ]; do
    case "$1" in
      --teleport) [[ "$2" =~ $num && "$3" =~ $num && "$4" =~ $num ]] || { echo "bad --teleport x y z" >&2; return 2; }; LS_TX=$2 LS_TY=$3 LS_TZ=$4; shift 4;;
      --away)     [[ "$2" =~ $num && "$3" =~ $num && "$4" =~ $num ]] || { echo "bad --away x y z" >&2; return 2; }; LS_AX=$2 LS_AY=$3 LS_AZ=$4; shift 4;;
      --player)   LS_PLAYER=$2; shift 2;;
      --with)     LS_WITH+="$2"$'\n'; shift 2;;
      --clear-faction) LS_CLEAR+="$2"$'\n'; shift 2;;
      --speed)    [[ "$2" =~ $num ]] || { echo "bad --speed" >&2; return 2; }; LS_SPEED=$2; shift 2;;
      --no-load)  LS_NOLOAD=1; shift;;
      --dry-run)  LS_DRY=1; shift;;
      --probe)    LS_PROBE=1; shift;;
      --selftest) LS_SELFTEST=1; shift;;
      -h|--help)  ls_usage; return 64;;
      --*)        echo "unknown option $1" >&2; return 2;;
      *)          pos+=("$1"); shift;;
    esac
  done
  [ -n "$LS_CLEAR" ] || LS_CLEAR=$'Holy Nation Outlaws\n'
  [ "$LS_SELFTEST" = 1 ] && return 0
  [ ${#pos[@]} -eq 3 ] || { echo "usage: lane-setup.sh <5090|4080> <instance 3..9> <save|-> [options]  (--help)" >&2; return 2; }
  LS_RIG=${pos[0]} LS_INST=${pos[1]} LS_SAVE=${pos[2]}
  case "$LS_RIG" in 5090|4080) ;; *) echo "rig must be 5090 or 4080" >&2; return 2;; esac
  [[ "$LS_INST" =~ ^[3-9]$ ]] || { echo "instance must be 3..9 (1 = main install, 2 = older lane: refused)" >&2; return 2; }
  if [ "$LS_SAVE" = "-" ]; then LS_NOLOAD=1; LS_SAVE=""; fi
  if [ "$LS_NOLOAD" != 1 ]; then [[ "$LS_SAVE" =~ ^kah-[A-Za-z0-9._-]+$ ]] || { echo "save must be a kah-* copy (got '$LS_SAVE')" >&2; return 2; }; fi
  [[ "$LS_PLAYER" =~ ^[A-Za-z0-9._\ -]+$ ]] || { echo "bad --player" >&2; return 2; }
  return 0
}

# Assemble the full body for the lane. $1 = rig-env path as seen on the lane host.
ls_body() {
  local rigenv=$1
  printf 'export RIG=%q KAH_INSTANCE=%q\n. %q\n' "$LS_RIG" "$LS_INST" "$rigenv"
  printf 'SAVE=%q PLAYER=%q NOLOAD=%q SPEEDF=%q TX=%q TY=%q TZ=%q AX=%q AY=%q AZ=%q\n' \
    "$LS_SAVE" "$LS_PLAYER" "$LS_NOLOAD" "$LS_SPEED" "$LS_TX" "$LS_TY" "$LS_TZ" "$LS_AX" "$LS_AY" "$LS_AZ"
  printf 'WITH=%q\nCLEAR=%q\n' "$LS_WITH" "$LS_CLEAR"
  ls_prelude; ls_main
}

# Where this script runs and how to reach the lane. Sets LS_EXEC (array) and LS_RIGENV.
ls_route() {
  local here=git5090
  if grep -qi microsoft /proc/version 2>/dev/null; then here=wsl
  elif [ "$(hostname 2>/dev/null)" = DESKTOP-NQQPA73 ]; then here=host4080; fi
  if [ "$LS_RIG" = 4080 ]; then
    LS_RIGENV=/c/KenshiModding/tools/automation/rig-env.sh
    if [ $here = host4080 ]; then LS_EXEC=(bash -l -s); else LS_EXEC=(ssh -o BatchMode=yes 4080 '"C:\Program Files\Git\bin\bash.exe" -l -s'); fi
  else
    LS_RIGENV=/mnt/c/KenshiModding/tools/automation/rig-env.sh
    [ $here = host4080 ] && { echo "5090 lanes cannot be driven from the 4080" >&2; return 2; }
    if [ $here = wsl ]; then LS_EXEC=(bash -s); else LS_EXEC=(env MSYS_NO_PATHCONV=1 wsl.exe -d DwemerAI4Skyrim3 -u root --cd / -- bash -s); fi
  fi
}

ls_dryrun() {
  echo "lane-setup DRY RUN rig=$LS_RIG instance=$LS_INST save=${LS_SAVE:--} noload=$LS_NOLOAD player=$LS_PLAYER speed_final=$LS_SPEED"
  echo "teleport target: $LS_TX $LS_TY $LS_TZ | outlaws away: $LS_AX $LS_AY $LS_AZ | with: $(echo "$LS_WITH" | tr '\n' ',') | clear factions: $(echo "$LS_CLEAR" | tr '\n' ',')"
  echo "executor: ${LS_EXEC[*]}   rig-env: $LS_RIGENV"
  echo "commands the lane would run, in order:"
  echo "  status | load $LS_SAVE | speed 0 hold | wait-world 180 | speed 0 hold | status | where $LS_PLAYER | chars 1000000 [faction]"
  echo "  per squad member: [wake if KO] health 100, hunger 300, protect on | select $LS_PLAYER"
  echo "  teleport <member> x y z (player $LS_TX $LS_TY $LS_TZ, others +8 x / +5 z each) | per clear faction: chars 1500, relation <one> 20, teleport <each> $LS_AX $LS_AY $LS_AZ"
  echo "  speed $LS_SPEED hold | wait 10 s | clear again | status | where $LS_PLAYER | protect | hp $LS_PLAYER"
  ls_body "$LS_RIGENV" | bash -n && echo "body syntax OK ($(ls_body "$LS_RIGENV" | wc -l) lines)" || { echo "RESULT lane-setup $LS_RIG i$LS_INST FAIL body syntax"; return 1; }
  if [ "$LS_PROBE" = 1 ]; then
    echo "probe (read-only status + where through the real route):"
    { printf 'export RIG=%q KAH_INSTANCE=%q\n. %q\n' "$LS_RIG" "$LS_INST" "$LS_RIGENV"; ls_prelude
      printf 'echo "KDIR=$KDIR"; A status; A where %q\n' "$LS_PLAYER"; } | "${LS_EXEC[@]}"
  fi
  echo "RESULT lane-setup $LS_RIG i$LS_INST DRY-RUN OK (nothing was sent to the game$([ "$LS_PROBE" = 1 ] && echo ' except the read-only probe'))"
}

ls_selftest() {
  local fails=0 t; t() { if eval "$2"; then echo "ok   $1"; else echo "FAIL $1"; fails=$((fails+1)); fi; }
  t "args ok" '( ls_parse_args 5090 3 kah-imm26-5090-hub --teleport 1 2 3 --with Cind >/dev/null 2>&1 && [ "$LS_TX$LS_TY$LS_TZ" = 123 ] && [ "$LS_WITH" = $'"'"'Cind\n'"'"' ] )'
  t "default hub" '( ls_parse_args 4080 4 kah-x && [ "$LS_TX $LS_TY $LS_TZ" = "-50978 1533 2960" ] && [ "$LS_CLEAR" = $'"'"'Holy Nation Outlaws\n'"'"' ] )'
  t "refuse instance 1" '! ( ls_parse_args 5090 1 kah-x ) 2>/dev/null'
  t "refuse instance 2" '! ( ls_parse_args 5090 2 kah-x ) 2>/dev/null'
  t "refuse non-kah save" '! ( ls_parse_args 5090 3 auto-home ) 2>/dev/null'
  t "refuse injection save" '! ( ls_parse_args 5090 3 "kah-x;rm" ) 2>/dev/null'
  t "refuse bad rig" '! ( ls_parse_args 5080 3 kah-x ) 2>/dev/null'
  t "refuse bad teleport" '! ( ls_parse_args 5090 3 kah-x --teleport a b c ) 2>/dev/null'
  t "save dash = no load" '( ls_parse_args 5090 3 - && [ "$LS_NOLOAD" = 1 ] )'
  local r
  for r in "5090 3" "5090 5" "4080 3" "4080 4"; do
    t "body syntax $r" "( ls_parse_args ${r% *} ${r#* } kah-x --with Cind >/dev/null 2>&1; ls_route 2>/dev/null; ls_body \"\$LS_RIGENV\" | bash -n )"
  done
  # chars parser on a canned real reply (5090 i3, 2026-10-15) incl. a bracketed title and a PosX prefix
  local sample='4 within 120.0: Fenn [Captain Grolf] #1091918976/1 [Holy Nation Outlaws] pos=-53200.0,957.0,4893.0 dist=2.0 race=Greenlander | Kint #1295043968/1 [Nameless] pos=-62010.3,328.8,16285.5 dist=0.0 race=Greenlander | Pack Beast #1490966784/14 [Traders Guild] pos=-62110.3,326.0,16271.1 dist=101.1 race=Garru (darker) | Cind [Hungry Bandit] #2529907200/2 [Traders Guild] pos=-50970.0,1533.0,2965.0 dist=9.0 race=Greenlander'
  local out; out=$( { ls_prelude; echo 'printf "%s\n" "$SAMPLE" | ls_parse'; } | SAMPLE="$sample" bash )
  t "parser entries" '[ "$(echo "$out" | wc -l)" = 4 ]'
  t "parser fields" '[ "$(echo "$out" | sed -n 1p)" = "#1091918976/1|Holy Nation Outlaws|Fenn [Captain Grolf]" ] && [ "$(echo "$out" | sed -n 4p)" = "#2529907200/2|Traders Guild|Cind [Hungry Bandit]" ]'
  out=$( { ls_prelude; echo 'echo "Kint #1295043968/1 [Nameless] pos=-62010.3,328.8,16285.5 dist=0.0" | ls_pos; echo "phase=world save=x paused=0 speed=0.5 squad=2" | ls_speed; ls_num_eq 0.5 0.5 && echo eq; ls_num_eq 0 0.5 || echo ne; ls_dist2d 0 0 3 4'; } | bash | tr '\n' ' ')
  t "helpers" '[ "$out" = "-62010.3 328.8 16285.5 0.5 eq ne 5" ]'
  echo "SELFTEST $([ $fails = 0 ] && echo PASS || echo "FAIL ($fails)") lane-setup"
  return $fails
}

ls_run() {
  ls_parse_args "$@"; local rc=$?; [ $rc -eq 64 ] && return 0; [ $rc -ne 0 ] && return $rc
  [ "$LS_SELFTEST" = 1 ] && { ls_selftest; return $?; }
  ls_route || return 2
  [ "$LS_DRY" = 1 ] && { ls_dryrun; return $?; }
  local d=/c/KenshiTestRuns/lane-setup; [ -d /mnt/c ] && [ ! -d /c ] && d=/mnt/c/KenshiTestRuns/lane-setup
  mkdir -p "$d" 2>/dev/null; local log="$d/$LS_RIG-i$LS_INST-$(date +%Y%m%d-%H%M%S).log"
  echo "lane-setup $LS_RIG i$LS_INST save=${LS_SAVE:--} log=$log"
  ls_body "$LS_RIGENV" | "${LS_EXEC[@]}" 2>&1 | tee "$log"
  local res; res=$(grep -a '^RESULT lane-setup ' "$log" | tail -1)
  [ -n "$res" ] || { echo "RESULT lane-setup $LS_RIG i$LS_INST FAIL no RESULT line from the lane (see $log)"; return 1; }
  case "$res" in *" PASS "*) return 0;; *) return 1;; esac
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then ls_run "$@"; exit $?; fi
