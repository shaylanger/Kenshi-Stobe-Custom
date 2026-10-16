#!/usr/bin/env bash
# inject-travel.sh (imm26-sfTrav): arm a lane so the NEXT travel-consent chat turn of an NPC becomes a REAL travel PROPOSE (stored PROPOSED travel_agreement), whatever the model says.
#   inject-travel.sh <lane|lane-root> <npc|any> [destination] [--kind same_route|detour|guide] [--leader npc|player] [--row ID] [--ttl SEC] [--keep-text]   arm (one-shot marker)
#   inject-travel.sh <lane|lane-root> --status                                                                                                     marker, fired files, newest travel_agreement rows
#   inject-travel.sh <lane|lane-root> --disarm                                                                                                     remove an unused marker
# <lane> = 5090-i3 5090-i4 5090-i5 4080-i3 4080-i4 (lane.sh) or that lane's root (/tmp/stobe-imm26-5090 ...). Anything else is refused.
# <npc> = the NPC's name as the game shows it (e.g. Cind) or "any" (first travel turn of any NPC). [destination] = candidate id / label / known place (default Squin; "" = first that grounds).
# What it does NOT do: it never writes a travel row, consent or grant itself. The marker is read by lib/imm26_travel_test_inject.php (server seam, gated to /tmp/stobe-*/site with a private
# DB socket) which, on the armed NPC's next chat turn, feeds a synthetic travel_decision=PROPOSE through the unchanged stobeTravelCapture() (policy refusal, availability gate, destination
# grounding, plan hash, stobeTravelWrite; the product's own refusal text if it refuses) and consumes the marker. The player's own "Yes" then goes the normal way (the model must ACCEPT with an
# exact quote). Sibling of inject-propose.sh (Hunt/ClearGroup); the two seams are independent. Needs inject-travel-deploy.sh on the lane (lane-deploy.sh removes it: rerun after every lane-deploy).
# Exit: 0 armed/ok, 2 usage/refused, 4 seam not deployed on the lane.
# Test switches: KAH_ROW_FAKE=1 (lane.sh fake transport), IT_DIRECT=1 (run in WSL against a local lane root; selftest only).
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
usage() { sed -n '2,5p' "$0" | sed 's/^# \{0,1\}//'; exit 2; }
[ $# -ge 2 ] || usage
LANE_ARG="$1"; shift
MODE=arm; NPC=""; DEST="Squin"; KIND="same_route"; LEADER="npc"; ROW=""; TTL=900; KEEP=false
case "${1:-}" in
  --status) MODE=status; shift ;;
  --disarm) MODE=disarm; shift ;;
  *) NPC="${1:-}"; shift
     if [ $# -gt 0 ] && [ "${1#--}" = "$1" ]; then DEST="$1"; shift; fi ;;
esac
while [ $# -gt 0 ]; do
  case "$1" in
    --kind) KIND="${2:-}"; shift 2 ;;
    --leader) LEADER="${2:-}"; shift 2 ;;
    --row) ROW="${2:-}"; shift 2 ;;
    --ttl) TTL="${2:-}"; shift 2 ;;
    --keep-text) KEEP=true; shift ;;
    *) echo "REFUSED unknown argument '$1'"; exit 2 ;;
  esac
done
if [ "$MODE" = arm ]; then
  case "$KIND" in same_route|detour|guide) ;; *) echo "REFUSED --kind '$KIND' (same_route|detour|guide)"; exit 2 ;; esac
  case "$LEADER" in npc|player) ;; *) echo "REFUSED --leader '$LEADER' (npc|player)"; exit 2 ;; esac
  printf '%s\n' "$TTL" | grep -Eq '^[0-9]{1,5}$' && [ "$TTL" -ge 30 ] && [ "$TTL" -le 7200 ] || { echo "REFUSED --ttl 30..7200"; exit 2; }
  printf '%s\n' "$ROW" | grep -Eq '^[A-Za-z0-9._-]{0,24}$' || { echo "REFUSED --row"; exit 2; }
  printf '%s\n' "$DEST" | grep -Eq '^[A-Za-z0-9 ._:#@()-]{0,80}$' || { echo "REFUSED destination characters"; exit 2; }
  # NPC names: letters, digits, space, [ ] ( ) . - _ only (the game's own name shapes); no quotes/backslash that could break the JSON marker.
  printf '%s\n' "$NPC" | grep -Eq "^[][A-Za-z0-9 ._()-]{1,64}$" || { echo "REFUSED npc characters"; exit 2; }
fi

# ---- lane resolution (the marker may only ever be written inside a known private lane root under /tmp/stobe-*)
if [ "${IT_DIRECT:-}" = 1 ]; then
  ROOT="$LANE_ARG"; case "$ROOT" in /tmp/stobe-*) ;; *) echo "REFUSED root '$ROOT' (needs /tmp/stobe-*)"; exit 2 ;; esac
  LANE_NAME="direct"
else
  . "$HERE/lane.sh"
  if lt_load "$LANE_ARG" >/dev/null 2>&1; then :; else
    found=""; for l in $(lt_lanes); do lt_load "$l" >/dev/null; [ "$LT_ROOT" = "$LANE_ARG" ] && found="$l" && break; done
    [ -n "$found" ] || { echo "REFUSED '$LANE_ARG' is not a known lane or lane root ($(lt_lanes))"; exit 2; }
    lt_load "$found" >/dev/null
  fi
  ROOT="$LT_ROOT"; LANE_NAME="$LT_LANE"
fi
case "$ROOT" in /var/www/*|*..*) echo "REFUSED root"; exit 2 ;; esac
wbody() { if [ "${IT_DIRECT:-}" = 1 ]; then bash -s; else lt_w; fi; }   # bash body on stdin, run where the lane root lives (WSL)

if [ "$MODE" = status ]; then
  wbody <<EOF
R=$ROOT
echo "lane $LANE_NAME root \$R"
if [ -f "\$R/test-inject-travel.json" ]; then echo "MARKER armed: \$(cat \$R/test-inject-travel.json)"; else echo "MARKER none"; fi
ls -1t "\$R"/test-inject-travel.fired-*.json 2>/dev/null | head -3 | while read f; do echo "FIRED \$f: \$(head -c 600 \$f)"; done
if grep -q 'imm26-sfTrav TEST SEAM' "\$R/site/processor/chat.php" 2>/dev/null && [ -f "\$R/site/lib/imm26_travel_test_inject.php" ]; then echo "SEAM deployed"; else echo "SEAM MISSING"; fi
EOF
  if [ "${IT_DIRECT:-}" != 1 ]; then
    lt_sql "select rowid||' '||left(data, 260) from eventlog where type='travel_agreement' order by rowid desc limit 3" | sed 's/^/RECORD /'
  fi
  exit 0
fi

if [ "$MODE" = disarm ]; then
  wbody <<EOF
rm -f "$ROOT/test-inject-travel.json" && echo "DISARMED $LANE_NAME"
EOF
  exit 0
fi

# ---- arm
out=$(wbody <<EOF
R=$ROOT
if ! grep -q 'imm26-sfTrav TEST SEAM' "\$R/site/processor/chat.php" 2>/dev/null || [ ! -f "\$R/site/lib/imm26_travel_test_inject.php" ]; then
  echo "SEAM-MISSING \$R: deploy with inject-travel-deploy.sh $LANE_NAME (lane-deploy.sh removes the seam: rerun it after every lane-deploy)"; exit 4; fi
exp=\$(( \$(date +%s) + $TTL ))
tmp="\$R/test-inject-travel.json.tmp\$\$"
printf '{"schema":"STOBE_TEST_TRAVEL_INJECT_V1","npc":"%s","destination":"%s","kind":"%s","leader":"%s","row":"%s","keep_text":%s,"expires_at":%s}\n' \
  '$NPC' '$DEST' '$KIND' '$LEADER' '$ROW' '$KEEP' "\$exp" > "\$tmp" && chmod 644 "\$tmp" && mv -f "\$tmp" "\$R/test-inject-travel.json" \
  && echo "ARMED lane=$LANE_NAME npc=$NPC dest=$DEST kind=$KIND leader=$LEADER row=$ROW expires_in=${TTL}s marker=\$R/test-inject-travel.json"
EOF
)
rc=$?
printf '%s\n' "$out"
case "$out" in SEAM-MISSING*) exit 4 ;; ARMED*) exit 0 ;; *) [ "${KAH_ROW_FAKE:-}" = 1 ] && exit 0; exit $((rc?rc:2)) ;; esac
