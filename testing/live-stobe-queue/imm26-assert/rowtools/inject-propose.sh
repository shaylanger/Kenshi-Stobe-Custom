#!/usr/bin/env bash
# inject-propose.sh (imm26-sfO): arm a lane so the NEXT chat turn of an NPC becomes a REAL Hunt / ClearGroup PROPOSE, whatever the model says.
#   inject-propose.sh <lane|lane-root> <actor> <Hunt|ClearGroup> [target] [--row ID] [--ttl SEC] [--quantity N]   arm (one-shot marker)
#   inject-propose.sh <lane|lane-root> --status                                                                  marker, fired files, newest activity records
#   inject-propose.sh <lane|lane-root> --disarm                                                                  remove an unused marker
# <lane> = 5090-i3 5090-i4 5090-i5 4080-i3 4080-i4 (lane.sh) or that lane's root (/tmp/stobe-imm26-5090 ...). Anything else is refused.
# <actor> = the NPC's name as the game shows it (e.g. Cind; after a faction re-serial use the NAME), a numeric serial, or "any" (first activity turn of any NPC).
# [target] = optional filter on the candidate (sourceId / candidateId / targetSerial / resource name / ClearGroup target serial); default: first groundable one.
# What it does NOT do: it never writes a record, grants or consent itself. The marker is read by lib/activity/ActivityTestInject.php (server seam,
# gated to /tmp/stobe-*/site with a private DB socket) which, on the armed NPC's next chat turn, builds the intent from THAT turn's own native facts,
# runs it through the unchanged propose path (adapter grounding, willingness/availability gates, stobe_activity_record state proposed, product offer
# text) and consumes the marker. The player's own "Yes" then goes the normal way. Exit: 0 armed/ok, 2 usage/refused, 4 seam not deployed on the lane.
# Test switches: KAH_ROW_FAKE=1 (lane.sh fake transport), IP_DIRECT=1 (run in WSL against a local lane root; selftest only).
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
usage() { sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'; exit 2; }
[ $# -ge 2 ] || usage
LANE_ARG="$1"; shift
MODE=arm; ACTOR=""; KIND=""; TARGET=""; ROW=""; TTL=900; QTY=1
case "${1:-}" in
  --status) MODE=status; shift ;;
  --disarm) MODE=disarm; shift ;;
  *) ACTOR="${1:-}"; KIND="${2:-}"; shift 2 2>/dev/null || usage
     if [ $# -gt 0 ] && [ "${1#--}" = "$1" ]; then TARGET="$1"; shift; fi ;;
esac
while [ $# -gt 0 ]; do
  case "$1" in
    --row) ROW="${2:-}"; shift 2 ;;
    --ttl) TTL="${2:-}"; shift 2 ;;
    --quantity) QTY="${2:-}"; shift 2 ;;
    *) echo "REFUSED unknown argument '$1'"; exit 2 ;;
  esac
done
if [ "$MODE" = arm ]; then
  case "$KIND" in Hunt|ClearGroup) ;; *) echo "REFUSED kind '$KIND' (Hunt|ClearGroup)"; exit 2 ;; esac
  printf '%s\n' "$TTL" | grep -Eq '^[0-9]{1,5}$' && [ "$TTL" -ge 30 ] && [ "$TTL" -le 7200 ] || { echo "REFUSED --ttl 30..7200"; exit 2; }
  printf '%s\n' "$QTY" | grep -Eq '^[0-9]{1,3}$' && [ "$QTY" -ge 1 ] || { echo "REFUSED --quantity 1..999"; exit 2; }
  printf '%s\n' "$ROW" | grep -Eq '^[A-Za-z0-9._-]{0,24}$' || { echo "REFUSED --row"; exit 2; }
  printf '%s\n' "$TARGET" | grep -Eq '^[A-Za-z0-9 ._:#@()-]{0,80}$' || { echo "REFUSED target characters"; exit 2; }
  # NPC names: letters, digits, space, [ ] ( ) . - _ only (the game's own name shapes); no quotes/backslash that could break the JSON marker.
  printf '%s\n' "$ACTOR" | grep -Eq "^[][A-Za-z0-9 ._()-]{1,64}$" || { echo "REFUSED actor characters"; exit 2; }
fi

# ---- lane resolution (the marker may only ever be written inside a known private lane root under /tmp/stobe-*)
if [ "${IP_DIRECT:-}" = 1 ]; then
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
wbody() { if [ "${IP_DIRECT:-}" = 1 ]; then bash -s; else lt_w; fi; }   # bash body on stdin, run where the lane root lives (WSL)

if [ "$MODE" = status ]; then
  wbody <<EOF
R=$ROOT
echo "lane $LANE_NAME root \$R"
if [ -f "\$R/test-inject-activity.json" ]; then echo "MARKER armed: \$(cat \$R/test-inject-activity.json)"; else echo "MARKER none"; fi
ls -1t "\$R"/test-inject-activity.fired-*.json 2>/dev/null | head -3 | while read f; do echo "FIRED \$f: \$(head -c 600 \$f)"; done
if grep -q 'imm26-sfO TEST SEAM' "\$R/site/lib/activity/ActivityChat.php" 2>/dev/null && [ -f "\$R/site/lib/activity/ActivityTestInject.php" ]; then echo "SEAM deployed"; else echo "SEAM MISSING"; fi
EOF
  if [ "${IP_DIRECT:-}" != 1 ]; then
    lt_sql "select actor||' '||record->>'status'||' '||(record->'agreement'->>'kind')||' rev '||revision||' '||id from stobe_activity_record order by (record->>'lastNow')::bigint desc limit 4" | sed 's/^/RECORD /'
  fi
  exit 0
fi

if [ "$MODE" = disarm ]; then
  wbody <<EOF
rm -f "$ROOT/test-inject-activity.json" && echo "DISARMED $LANE_NAME"
EOF
  exit 0
fi

# ---- arm
ACT_JSON="0"; NPC_JSON=""
if printf '%s\n' "$ACTOR" | grep -Eq '^[0-9]+$'; then ACT_JSON="$ACTOR"
elif [ "$ACTOR" != any ]; then NPC_JSON="$ACTOR"; fi
out=$(wbody <<EOF
R=$ROOT
if ! grep -q 'imm26-sfO TEST SEAM' "\$R/site/lib/activity/ActivityChat.php" 2>/dev/null || [ ! -f "\$R/site/lib/activity/ActivityTestInject.php" ]; then
  echo "SEAM-MISSING \$R: deploy with python3 pending-fixes/imm26-sfO/apply.py \$R/site (see inbox/operators/sfO.txt)"; exit 4; fi
exp=\$(( \$(date +%s) + $TTL ))
tmp="\$R/test-inject-activity.json.tmp\$\$"
printf '{"schema":"STOBE_TEST_ACTIVITY_INJECT_V1","kind":"%s","actor":%s,"npc":"%s","target":"%s","quantity":%s,"row":"%s","expires_at":%s}\n' \
  '$KIND' '$ACT_JSON' '$NPC_JSON' '$TARGET' '$QTY' '$ROW' "\$exp" > "\$tmp" && chmod 644 "\$tmp" && mv -f "\$tmp" "\$R/test-inject-activity.json" \
  && echo "ARMED lane=$LANE_NAME kind=$KIND actor=$ACTOR target=$TARGET row=$ROW expires_in=${TTL}s marker=\$R/test-inject-activity.json"
EOF
)
rc=$?
printf '%s\n' "$out"
case "$out" in SEAM-MISSING*) exit 4 ;; ARMED*) exit 0 ;; *) [ "${KAH_ROW_FAKE:-}" = 1 ] && exit 0; exit $((rc?rc:2)) ;; esac
