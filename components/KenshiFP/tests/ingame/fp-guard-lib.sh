# fp-guard-lib.sh: raider / knockout guard for long viewmodel captures (sourced by fp-viewmodel.sh and capture scripts).
# Why: world raids (Dust / Starving / Hungry Bandits) attack Axima on the open-ground capture spot outside the base; a
# knocked-out Axima made whole sweeps invalid (2026-10-09 opt blk sweep: Axima KO, every block number void).
#  guard_setup            pacify every raider faction near the spot (GUARD_FACTIONS, plus attackers seen in stobe.log)
#                         with `relation <member> 100` (also clears the game's "enemies" flag), `health <c> 100`, wake
#                         a knocked-out guarded char (harness `wake` clears a KO), then check conscious; 1 = still down
#  guard_start / guard_stop   background guard, one guard_tick every GUARD_EVERY (5) s
#  guard_tick             one pass: a non-squad attacker on a guarded char (stobe.log `[EVENT] combat: X (F) -> <c> (`)
#                         OR a guarded char KO/down (also with no attacker: starving, recovery coma) -> pacify the
#                         attacker factions + GUARD_FACTIONS, `health <c> 100`, `wake <c>`, record a hit for the
#                         current segment, log "GUARD: <factions> pacified, <c> restored, segment <x> rerun (<why>)"
#  guard_seg <name> cmd.. run a segment; after a guard hit during it, GUARD_RERUN_HOOK (if set) undoes its partial output
#                         and the segment runs again; 3 hits in one segment (GUARD_MAX_HITS) -> return 2 (caller: setup
#                         fail). A synchronous guard_tick after each attempt catches a hit in its last seconds.
# Inputs: GUARD_CHARS (guarded chars, live names, default "$SH"), GUARD_SQUAD (extra own names never treated as
# attackers), GUARD_KEEP (attacker names to ignore, e.g. the fixture hostile), GUARD_SPOT "x z" (pacify radius around
# it, else around the player), GUARD_LOG (log file), SLOG (stobe.log), GUARD_DIR (state dir).
GUARD_FACTIONS=${GUARD_FACTIONS:-Starving Bandits|Hungry Bandits|Dust Bandits|Band of Bones|Kral.s Chosen|Hill Marauders|Black Dragon Ninjas|Berserkers|Cannibals|Fogmen}
GUARD_EVERY=${GUARD_EVERY:-5}; GUARD_MAX_HITS=${GUARD_MAX_HITS:-3}; GUARD_R=${GUARD_R:-4000}
SLOG=${SLOG:-/mnt/d/Steam/steamapps/common/Kenshi/RE_Kenshi/mods/Stobe/stobe.log}
GUARD_DIR=${GUARD_DIR:-/tmp/fp-guard.$$}; mkdir -p "$GUARD_DIR"
_ga() { stobe-auto "$@" 2>&1 | tr -d '\r'; }
_glog() { echo "$(date +%H:%M:%S) $*" >> "${GUARD_LOG:-$GUARD_DIR/guard.log}"; }
_gslog_n() { [ -r "$SLOG" ] && wc -l < "$SLOG" | tr -d ' ' || echo 0; }
_gdown() { _ga where "$1" | grep -qE ' (KO|DEAD)( |$)'; }
# _gpacify "<faction|faction>": relation 100 with one live member of each faction found within GUARD_R; prints the
# factions it pacified (comma list)
_gpacify() { local re=$1 lines l f h done="" out=""
  lines=$(_ga chars "$GUARD_R" "$(tr 'A-Z' 'a-z' <<<"$re" | sed 's/[^|][^|]*/[&]/g; s/\.s/\x27s/g')" | sed 's/^[0-9]* within [0-9.]*: //' | tr '|' '\n' | sed 's/^ *//')
  while IFS= read -r l; do f=$(sed -n 's/^.*#[0-9]*\/[0-9]* \[\([^]]*\)\] pos=.*/\1/p' <<<"$l")
    [ -n "$f" ] || continue; case ",$done," in *",$f,"*) continue;; esac
    h=$(grep -oE '#[0-9]+/[0-9]+' <<<"$l" | head -1); [ -n "$h" ] || continue
    _ga relation "$h" 100 | grep -q -- '-> 100' && { done+="${done:+,}$f"; out+="${out:+,}$f"; }
  done <<<"$lines"; echo "$out"; }
# _grestore <char>: health 100, wake if down, wait up to 8 s conscious; 0 = up
_grestore() { local c=$1 e=$((SECONDS+8)); _ga health "$c" 100 >/dev/null
  _gdown "$c" && _ga wake "$c" >/dev/null
  while [ $SECONDS -lt $e ]; do _gdown "$c" || return 0; sleep 0.5; _ga wake "$c" >/dev/null; done; return 1; }
guard_setup() { local p c bad=""
  echo "$(_gslog_n)" > "$GUARD_DIR/slpos"; : > "$GUARD_DIR/hits"; rm -f "$GUARD_DIR/busy"; echo setup > "$GUARD_DIR/seg"
  p=$(_gpacify "$GUARD_FACTIONS")
  for c in ${GUARD_CHARS:-$SH}; do _grestore "$c" || bad+=" $c"; done
  _glog "GUARD setup: pacified ${p:-none} (within $GUARD_R), restored ${GUARD_CHARS:-$SH}${bad:+, STILL DOWN:$bad}"
  [ -z "$bad" ]; }
guard_tick() { local seg n0 n lines att="" fac="" why="" c p bad="" own
  seg=$(cat "$GUARD_DIR/seg" 2>/dev/null); n0=$(cat "$GUARD_DIR/slpos" 2>/dev/null || echo 0); n=$(_gslog_n)
  [ "$n" -lt "$n0" ] 2>/dev/null && n0=0; echo "$n" > "$GUARD_DIR/slpos"
  if [ "$n" -gt "$n0" ] 2>/dev/null; then
    lines=$(sed -n "$((n0+1)),${n}p" "$SLOG" | tr -d '\r' | grep -a 'EVENT\] combat: ' | sed 's/.*EVENT\] combat: //')
    for c in ${GUARD_CHARS:-$SH}; do
      while IFS= read -r l; do [ -n "$l" ] || continue
        own=0; for o in ${GUARD_CHARS:-$SH} $GUARD_SQUAD $GUARD_KEEP; do case "$l" in "$o "*) own=1;; esac; done; [ $own = 1 ] && continue
        att+="${att:+; }${l%% -> *}"; p=$(sed 's/^.*(\([^()]*\)) -> .*/\1/' <<<"$l"); case "|$fac|" in *"|$p|"*) ;; *) fac+="${fac:+|}$p";; esac
      done < <(grep -a -F -- "-> $c (" <<<"$lines"); done; fi
  for c in ${GUARD_CHARS:-$SH}; do _gdown "$c" && why+=" $c down"; done
  [ -z "$att$why" ] && return 0
  echo "$seg" >> "$GUARD_DIR/hits"; : > "$GUARD_DIR/busy"
  for c in ${GUARD_CHARS:-$SH}; do _grestore "$c" || bad+=" $c"; done
  p=$(_gpacify "${fac:+$fac|}$GUARD_FACTIONS")
  _glog "GUARD: ${p:-no faction found} pacified, ${GUARD_CHARS:-$SH} restored${bad:+ (STILL DOWN:$bad)}, segment ${seg:-?} rerun (${why# }${att:+ attackers: $att})"; rm -f "$GUARD_DIR/busy"; }
guard_start() { guard_stop; ( while sleep "$GUARD_EVERY"; do [ -n "$GUARD_PARENT" ] && ! kill -0 "$GUARD_PARENT" 2>/dev/null && exit 0; guard_tick; done ) </dev/null >/dev/null 2>&1 &
  GUARD_PID=$!; echo "$GUARD_PID" > "$GUARD_DIR/pid"; }
guard_stop() { local e=$((SECONDS+20)); while [ -e "$GUARD_DIR/busy" ] && [ $SECONDS -lt $e ]; do sleep 0.5; done; [ -s "$GUARD_DIR/pid" ] && kill "$(cat "$GUARD_DIR/pid")" 2>/dev/null; rm -f "$GUARD_DIR/pid"; }
guard_hits() { local n; n=$(grep -cxF -- "$1" "$GUARD_DIR/hits" 2>/dev/null); echo "${n:-0}"; }
guard_seg() { local name=$1 h0 h; shift
  while :; do h0=$(guard_hits "$name"); echo "$name" > "$GUARD_DIR/seg"
    "$@"; guard_tick; local e=$((SECONDS+30)); while [ -e "$GUARD_DIR/busy" ] && [ $SECONDS -lt $e ]; do sleep 0.5; done; h=$(guard_hits "$name"); echo idle > "$GUARD_DIR/seg"
    [ "$h" -gt "$h0" ] || return 0
    [ "$h" -ge "$GUARD_MAX_HITS" ] && { _glog "GUARD: segment $name hit $h times, giving up"; return 2; }
    [ -n "$GUARD_RERUN_HOOK" ] && $GUARD_RERUN_HOOK "$name"; done; }
