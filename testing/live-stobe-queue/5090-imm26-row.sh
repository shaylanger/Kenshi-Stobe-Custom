#!/usr/bin/env bash
# 5090-imm26-row.sh: evidence bundle per imm26 row on the isolated 5090 lane (needs 5090-imm26-lib.sh sourced first).
#   source .../5090-imm26-lib.sh; source .../5090-imm26-row.sh
#   r_mark                         -> "<eventlog max rowid> <prompt log bytes> <social_effect count>"
#   r_say <ROW> "<mark>" <target> "<utterance>" [wait_s]   say + wait + bundle
#   r_bundle <ROW> "<mark>" [note] events.txt (eventlog since mark, noise removed), prompt.txt (prompt bytes since mark), effects.txt, reply.txt
# Output dir C:\KenshiTestRuns\imm26-5090\rows\<ROW>\ (git bash /c/KenshiTestRuns/imm26-5090/rows/<ROW>/)
I5OUT=/c/KenshiTestRuns/imm26-5090/rows
r_mark() {
  local e b s; e=$(i3_sql "select coalesce(max(rowid),0) from eventlog"); s=$(i3_sql "select count(*) from social_effect")
  b=$(i3w <<<'stat -c %s /tmp/stobe-imm26-5090/site/log/context_sent_to_llm.log')
  echo "$e $b $s $(i3 <<<'wc -l < /mnt/d/KenshiInst/3/RE_Kenshi/mods/Stobe/stobe.log')"
}
r_bundle() {
  local row="$1" mk="$2" note="${3:-}" d="$I5OUT/$1"; mkdir -p "$d"; set -- $mk; local e=$1 b=$2 s=$3 l=$4
  i3_sql "select rowid,type,left(data,500),coalesce(delivery_state,'') from eventlog where rowid>$e and type not in ('combat','carry','healing','infonpc') order by rowid" | tr '|' '|' > "$d/events.txt"
  i3w <<<"tail -c +$((b+1)) /tmp/stobe-imm26-5090/site/log/context_sent_to_llm.log | head -c 400000" > "$d/prompt.txt"
  i3_sql "select count(*)-$s from social_effect" > "$d/effects.txt"; i3_sql "select * from social_effect order by 1 desc limit 6" >> "$d/effects.txt"
  i3 <<<"tail -n +$((l+1)) /mnt/d/KenshiInst/3/RE_Kenshi/mods/Stobe/stobe.log | grep -E 'ACTION_EXEC|resolved_speaker|ERROR|REJECT|rejected|ACTIVITY_|TRAVEL' | cut -c1-400 | head -60" > "$d/reply.txt"
  { echo "row=$row mark=$mk note=$note"; date; } > "$d/meta.txt"
  echo "== $row events"; grep -v -E "\|(inputtext|action|infoaction|travel_order_owner)\|" "$d/events.txt" | cut -c1-330 | head -12
  echo "== $row reply"; grep -E "\(NPC\)|ERROR|REJECT|rejected|ACTIVITY_" "$d/reply.txt" | cut -c1-420 | head -8
}
r_say() {  # r_say ROW "<mark>" "#serial/idx" "text" [wait]
  i3_say "$3" "$4" "${5:-120}" >/dev/null 2>&1; sleep 4; r_bundle "$1" "$2"
}
