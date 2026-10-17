#!/usr/bin/env bash
# fix14dtool_selftest.sh (imm26-fix14dtool, 2026-10-16): OFFLINE self-test of the F2 reply-capture fix (inv14d): rowcheck.first_reply and the rowlib.sh rl_say reply wait pick the NPC by
# speaker NAME (say.txt "target=<full name>"), not by the log tag. The tag is isPlayerCharacter() of the speaker: a Nameless-faction NPC (row 14-d) logs "(PC)" and the player's own echo
# was logged "[Orix]: Hunt 5 bandits. (NPC)". Fixtures = the real 14-d / 14-d.prev evidence of 5090-i5 (fix14dtool_fixtures/). No game, ssh, WSL or DB.
# Usage: bash rowtools/fix14dtool_selftest.sh   -> `SELFTEST f14-<name> PASS|FAIL` lines and `SELFTEST FIX14DTOOL ALL PASS|FAIL n/m`.
ST_HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; A="$ST_HERE/.."
P=$(command -v python3 || command -v python)
T=$(mktemp -d); export KAH_ROWS_BASE="$T/runs" KAH_ROW_FAKE=1 KAH_ROW_FAKE_LOG="$T/fake.log" KAH_PF_ISOLATION=1 FAKE_STATE="$T/state.json"
export ROW_SETTLE=0 ROW_WAIT=1
unset KAH_AGENT_NAME KAH_ROW_DRY
mkdir -p "$KAH_ROWS_BASE"
n=0; ok=0
chk() { n=$((n+1)); if [ "$2" = ok ]; then ok=$((ok+1)); echo "SELFTEST f14-$1 PASS ${3:-}"; else echo "SELFTEST f14-$1 FAIL ${3:-}"; fi; }
FX="$ST_HERE/fix14dtool_fixtures"
fr() {  # fr <evdir> <step> : rowcheck.first_reply
  "$P" -I -c "import sys;sys.path.insert(0,sys.argv[1]);import rowcheck as rc;print(rc.first_reply(sys.argv[2],sys.argv[3]))" "$ST_HERE" "$1" "$2"; }

# ---- 1. rowcheck.first_reply on the real replays
r=$(fr "$FX/pc-npc-echo" s1)
[ "$r" = "We can discuss what we might do together. What did you have in mind?" ] && chk firstreply-cind-pc-and-player-echo-npc ok || chk firstreply-cind-pc-and-player-echo-npc bad "$r"
r=$(fr "$FX/prev" s1)
[ "$r" = "Five against six, and they've got clubs and a bow between them." ] && chk firstreply-prev-run-cind-pc ok || chk firstreply-prev-run-cind-pc bad "$r"
# legacy: without a target= line in say.txt the first "(NPC)" line still counts (fake lanes, older evidence)
mkdir -p "$T/leg/s1"; printf 'ok\n' > "$T/leg/s1/say.txt"
printf '[t] [Stobe] ACTION_EXEC: SAY [Cind]: Fine, take it. (NPC)\n[t] [Stobe] ACTION_EXEC: SAY [Cind]: later (NPC)\n' > "$T/leg/s1/reply.txt"
r=$(fr "$T/leg" s1); [ "$r" = "Fine, take it." ] && chk firstreply-legacy-npc-tag-without-target ok || chk firstreply-legacy-npc-tag-without-target bad "$r"
# Traders Guild NPC (tag NPC) with a named target still works, and the first line of that speaker wins
mkdir -p "$T/tg/s1"; printf 'target=Cind [Hungry Bandit] serial=5 mode=chat\n' > "$T/tg/s1/say.txt"
printf '[t] [Stobe] ACTION_EXEC: SAY [Cind [Hungry Bandit]]: Aye. (NPC)\n[t] [Stobe] ACTION_EXEC: SAY [Cind [Hungry Bandit]]: Second. (NPC)\n' > "$T/tg/s1/reply.txt"
r=$(fr "$T/tg" s1); [ "$r" = "Aye." ] && chk firstreply-named-target-npc-tag ok || chk firstreply-named-target-npc-tag bad "$r"
# the NPC stayed silent: only the player echo (tagged NPC) is in the log -> NO reply (the old code returned the player's own line)
mkdir -p "$T/sil/s1"; printf 'target=Cind [Hungry Bandit] serial=5 mode=chat\n' > "$T/sil/s1/say.txt"
printf '[t] [Stobe] ACTION_EXEC: SAY [Orix]: Hunt 5 bandits. (NPC)\n' > "$T/sil/s1/reply.txt"
r=$(fr "$T/sil" s1); [ -z "$r" ] && chk firstreply-silent-npc-never-returns-player-echo ok || chk firstreply-silent-npc-never-returns-player-echo bad "$r"
# the OLD regex on the real replay returned the player echo (proves the fixture reproduces the bug)
old=$("$P" -I -c "import re,sys;t=open(sys.argv[1],encoding='utf-8').read();m=re.findall(r'ACTION_EXEC: SAY \[.+?\]: (.*?) \(NPC\)',t);print(m[0] if m else '')" "$FX/pc-npc-echo/s1/reply.txt")
[ "$old" = "Hunt 5 bandits." ] && chk fixture-reproduces-the-old-player-echo ok || chk fixture-reproduces-the-old-player-echo bad "$old"

# ---- 2. rowlib.sh rl_say reply wait: the body sent to the lane breaks on the NPC's NAME, not on any "(NPC)" line
. "$A/go-row.sh"
body_save="$T/saybody.sh"
lt_fake() { if [ "$1" = h ] && [[ "$2" == *stobe_say* ]]; then printf '%s\n' "$2" > "$body_save"; fi; "$P" "$ST_HERE/fakelane.py" "$@"; }
export FAKE_SCEN="$T/scen.json"; echo '{"steps":[{"reply":"x"}]}' > "$FAKE_SCEN"
lt_load 5090-i5 >/dev/null; LT_STOBELOG="$T/stobe.log"; : > "$LT_STOBELOG"
rl_begin f14wait; rl_say 1 "Hunt 5 bandits." 1 >/dev/null 2>&1
[ -s "$body_save" ] && chk wait-body-captured ok || chk wait-body-captured bad
grep -qF "grep -qF 'ACTION_EXEC: SAY [Cind [Hungry Bandit]]:'" "$body_save" && chk wait-matches-the-speaker-name ok || chk wait-matches-the-speaker-name bad "$(grep -a 'while' "$body_save" | cut -c1-300)"
grep -qF '(NPC)' "$body_save" && chk wait-no-npc-tag-predicate bad || chk wait-no-npc-tag-predicate ok
runwait() {  # runwait "<log line appended 0.3 s after the start>" -> "break" when the wait ended early (the post-reply sleep 3 ran), else "timeout"
  : > "$LT_STOBELOG"; rm -f "$T/sleeps"
  ( command sleep 0.3; printf '%s\n' "$1" >> "$LT_STOBELOG" ) &
  SLEEPS="$T/sleeps" bash -c 'stobe-auto() { echo "target=Cind [Hungry Bandit] serial=1 mode=chat"; }; sleep() { command sleep 0.2; echo "$1" >> "$SLEEPS"; }; . "$1"' _ "$body_save" >/dev/null 2>&1
  wait; grep -qx 3 "$T/sleeps" 2>/dev/null && echo break || echo timeout
}
r=$(runwait '[t] [Stobe] ACTION_EXEC: SAY [Cind [Hungry Bandit]]: We can discuss. (PC)'); [ "$r" = break ] && chk wait-breaks-on-cind-pc-line ok || chk wait-breaks-on-cind-pc-line bad "$r"
r=$(runwait '[t] [Stobe] ACTION_EXEC: SAY [Cind [Hungry Bandit]]: Aye. (NPC)'); [ "$r" = break ] && chk wait-breaks-on-cind-npc-line ok || chk wait-breaks-on-cind-npc-line bad "$r"
r=$(runwait '[t] [Stobe] ACTION_EXEC: SAY [Orix]: Hunt 5 bandits. (NPC)'); [ "$r" = timeout ] && chk wait-ignores-player-echo-tagged-npc ok || chk wait-ignores-player-echo-tagged-npc bad "$r"
r=$(runwait '[t] [Stobe] ACTION_EXEC: SAY [Shay]: Hunt the 5 bandits. (PC)'); [ "$r" = timeout ] && chk wait-ignores-player-echo-tagged-pc ok || chk wait-ignores-player-echo-tagged-pc bad "$r"

bash -n "$ST_HERE/rowlib.sh" && "$P" -m py_compile "$ST_HERE/rowcheck.py" && chk syntax-rowlib-rowcheck ok || chk syntax-rowlib-rowcheck bad
if [ "$ok" = "$n" ]; then echo "SELFTEST FIX14DTOOL ALL PASS $ok/$n"; else echo "SELFTEST FIX14DTOOL ALL FAIL $ok/$n"; fi
rm -rf "$T"
