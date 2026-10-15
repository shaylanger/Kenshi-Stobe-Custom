#!/usr/bin/env bash
# 4080-imm26-row.sh: one-call evidence capture for an imm26 baseline row on the isolated 4080 lane.
#   source /c/KenshiModding/testing/live-stobe-queue/4080-imm26-lib.sh
#   source /c/KenshiModding/testing/live-stobe-queue/4080-imm26-row.sh
#   i3_row <ROW-ID> <target #serial/idx> "<utterance>" [wait_s]    snapshot -> say -> bundle in C:\KenshiTestRuns\imm26-4080\<ROW-ID>\
#   i3_mark                      prints the snapshot marker "<eventlog max rowid> <prompt log bytes> <social_effect count>"
#   i3_bundle <ROW-ID> "<marker>" [note]   write the evidence files for everything since the marker (use after a manual action)
# Bundle files: reply.txt (stobe.log lines), events.txt (eventlog since marker, combat/carry/healing noise removed),
# prompt.txt (context_sent_to_llm.log bytes appended since marker), effects.txt (social_effect last 10 + count delta), meta.txt.
I3ROW_OUT=/c/KenshiTestRuns/imm26-4080
i3_mark() {
  i3w <<'EOF'
source /tmp/stobe-standalone4080/env.sh >/dev/null 2>&1
P="runuser -u postgres -- psql -h /tmp/stobe-standalone4080/socket -p 15434 -d stobe_standalone4080_test -At -c"
r=$($P "select coalesce(max(rowid),0) from eventlog"); e=$($P "select count(*) from social_effect")
b=$(stat -c %s /tmp/stobe-standalone4080/site/log/context_sent_to_llm.log)
echo "$r $b $e"
EOF
}
i3_bundle() {  # i3_bundle ROW "<rowid bytes effcount>" [note]
  local row="$1" mk="$2" note="${3:-}" d="$I3ROW_OUT/$1"; mkdir -p "$d"
  set -- $mk; local r="$1" b="$2" e="$3"
  i3w >"$d/events.txt" <<EOF
runuser -u postgres -- psql -h /tmp/stobe-standalone4080/socket -p 15434 -d stobe_standalone4080_test -At -F ' | ' -c "select rowid,type,left(data,400),delivery_state from eventlog where rowid>$r and type not in ('combat','carry','healing','major_damage','knockout','recovered','infonpc','limb_loss','combat_start','combat_end','item_pickup') order by rowid"
EOF
  i3w >"$d/prompt.txt" <<EOF
tail -c +$((b+1)) /tmp/stobe-standalone4080/site/log/context_sent_to_llm.log | head -c 400000
EOF
  i3w >"$d/effects.txt" <<EOF
P="runuser -u postgres -- psql -h /tmp/stobe-standalone4080/socket -p 15434 -d stobe_standalone4080_test -At -F '|' -c"
echo "count_before=$e count_after=\$(\$P 'select count(*) from social_effect')"
\$P "select observer_key,culprit_key,component,game_ts,delta,applied,left(detail::text,200) from social_effect order by game_ts desc limit 10"
EOF
  { echo "row=$row marker=$mk note=$note"; date; i3_sql "select count(*) from eventlog where rowid>$r"; } >"$d/meta.txt" 2>&1
  echo "bundle $d: events=$(wc -l <"$d/events.txt") prompt_bytes=$(wc -c <"$d/prompt.txt")"
}
i3_prep() {  # setup check: Shay must be conscious and selected (else replies come from Malzin 2.6 km away = invalid row)
  i3 <<'EOF3'
if stobe-auto stobe_state Shay | grep -q '"unconscious":true'; then stobe-auto wake Shay | head -1; sleep 2; fi
stobe-auto select Shay >/dev/null; stobe-auto stobe_state Shay | grep -o '"unconscious":[a-z]*' | head -1
EOF3
}
i3_row() {  # i3_row ROW target text [wait]
  local row="$1" d="$I3ROW_OUT/$1"; mkdir -p "$d"
  i3_prep | grep -q 'unconscious":false' || { echo "RESULT $row SETUP-FAIL Shay not conscious/selected"; return 3; }
  local mk; mk=$(i3_mark | tail -1)
  i3_say "$2" "$3" "${4:-150}" | tee "$d/reply.txt"
  grep -q "resolved_speaker=Shay" "$d/reply.txt" || echo "RESULT $row SETUP-FAIL resolved_speaker is not Shay (see $d/reply.txt)"
  i3_bundle "$row" "$mk" "say: $3"
  grep -aoE '"?(Current conversational stance|Grounded referrals|personal_boundaries|attention_limits|Conversation discretion|Personal preferences)[^\n]{0,40}' "$d/prompt.txt" | sort | uniq -c | head
}
i3_aff() {  # i3_aff "<observer>" "<target>" <value>  (H-AFF on the private DB; prints the stored entry)
  i3w <<EOF2
source /tmp/stobe-standalone4080/env.sh >/dev/null 2>&1; cd /tmp/stobe-standalone4080/site
php tools/social_relationship_inspect.php --set-relation "$1" "$2" $3 >/dev/null 2>&1
php tools/social_relationship_inspect.php --relation "$1" "$2" 2>&1 | grep -A8 '"entry"' | tr -d '\n '
EOF2
  echo
}
# NEG_TEST_INJECT on the private backend (mechanical rows: the model reply is overridden BEFORE the logic under test).
#   i3_inject <row> "<npc>" '<steps json array>'   chat context; one step per turn   |  i3_inject_off
#   Fired check: grep "NEG_TEST_INJECT fired (test switch, row <row>)" in /tmp/stobe-standalone4080/site/log/stobeserver.log
i3_inject_off() { i3_sql "DELETE FROM general_settings WHERE id='NEG_TEST_INJECT'" ; }
i3_fired() { echo "grep -a -c 'NEG_TEST_INJECT fired (test switch, row $1)' /tmp/stobe-standalone4080/site/log/stobeserver.log" | i3w; }
i3_inject() {
  local j; j=$(printf '{"row":"%s","npc":"%s","context":"chat","steps":%s}' "$1" "$2" "$3")
  { printf '%s\n' "cat > /tmp/inj.sql <<'EOS'" "DELETE FROM general_settings WHERE id='NEG_TEST_INJECT';" "INSERT INTO general_settings (id,value) VALUES ('NEG_TEST_INJECT', \$q\$$j\$q\$);" "EOS" \
      "chmod 644 /tmp/inj.sql; runuser -u postgres -- psql -h /tmp/stobe-standalone4080/socket -p 15434 -d stobe_standalone4080_test -q -f /tmp/inj.sql"; } | i3w
}
