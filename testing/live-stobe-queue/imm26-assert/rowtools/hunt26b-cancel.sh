#!/usr/bin/env bash
# hunt26b-cancel.sh (imm26-sf26bd): row 26-b CANCEL step on ANY lane (5090-i5, 4080-i4, ...), after an ACCEPTED Hunt (hunt26b-run.sh on 5090-i5, or any accept).
#   bash rowtools/hunt26b-cancel.sh <lane> [--wait S] [--text "Cancel that."]      ROW_NPC defaults to Malzin
# What it does (imm26-inv26 fixes): waits --wait (default 12 s: the accept reply must be delivered), teleports Shay next to the NPC INSIDE the say body right before the say, says the literal
#   "Cancel that." (cancel grammar, ActivityService.php:44; 'Cancel the hunt.' is outside it), PEOPLE GUARD: the NPC must be in people= of the dispatched inputtext or the row is
#   SETUP-FAIL 'test artefact: NPC outside TalkRadius, see imm26-inv26'. Then dumps stobe_activity_record + the ACTIVITY log lines.
# Prints ONE line:  HUNT26B-CANCEL <lane> PASS|FAIL|SETUP-FAIL <detail> [evidence=<dir>]   exit 0 / 1 / 2.   PASS = newest Hunt record status cancelled and a cancelled/cleanupComplete log line.
HB_HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$HB_HERE/../go-row.sh"; . "$HB_HERE/reloaddefs_a.sh"; . "$HB_HERE/reloaddefs_sfp.sh"; . "$HB_HERE/reloaddefs_sf26bd.sh"
LANE="${1:-}"; [ -n "$LANE" ] || { echo "usage: hunt26b-cancel.sh <lane: $(lt_lanes)> [--wait S] [--text T]" >&2; exit 2; }
shift; WAIT=12; TXT="Cancel that."
while [ $# -gt 0 ]; do case "$1" in --wait) WAIT="$2"; shift 2;; --text) TXT="$2"; shift 2;; *) echo "unexpected argument '$1'" >&2; exit 2;; esac; done
lt_load "$LANE" >/dev/null || { echo "HUNT26B-CANCEL $LANE SETUP-FAIL unknown lane"; exit 2; }
export ROW_NPC="${ROW_NPC:-Malzin}"; tr_cfg; rl_begin 26b-cancel >/dev/null
rw_sleep "$WAIT"
rl_resolve "$ROW_NPC" >/dev/null 2>&1 || { echo "HUNT26B-CANCEL $LANE SETUP-FAIL cannot resolve $ROW_NPC [evidence=$EV]"; exit 2; }
echo "$RL_NPC_FULL" > "$EV/npc.txt"; echo "before cancel: $RL_NPC_FULL dist=${RL_DIST:-?}" >> "$EV/distance.txt"
rw_act_dump act_pre_cancel.txt
n0=$(rw_logn)
ROW_NATIVE=1
rl_say 2c "$TXT" || { echo "HUNT26B-CANCEL $LANE SETUP-FAIL ${RL_REASON:-cancel say failed} [evidence=$EV]"; exit 2; }
rw_sleep 8
rw_act_dump act_post_cancel.txt; rw_log act_log_cancel.txt "${n0:-0}"
st=$(awk -F'|' '$7=="Hunt"{s=$6} END{print s}' "$EV/act_post_cancel.txt" 2>/dev/null)
if [ "$st" = cancelled ] && grep -aqE 'cleanupComplete=1|cancelled' "$EV/act_log_cancel.txt" 2>/dev/null; then
  echo "HUNT26B-CANCEL $LANE PASS Hunt record status=cancelled after '$TXT' (people= guard ok, dist before teleport ${RL_DIST:-?}) [evidence=$EV]"; exit 0
fi
echo "HUNT26B-CANCEL $LANE FAIL newest Hunt record status='${st:-none}' after '$TXT' (people= guard passed: the server saw the NPC) [evidence=$EV]"; exit 1
