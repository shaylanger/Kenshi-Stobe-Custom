#!/usr/bin/env bash
# 5090-imm26-lanes-lib.sh: drive the ISOLATED 5090 imm26 lanes i4 and i5 (D:\KenshiInst\4 / \5) from the 5090 Git Bash.
#   source /c/KenshiModding/testing/live-stobe-queue/5090-imm26-lanes-lib.sh
# Same helper set as 5090-imm26-lib.sh (i3): i4 i4w i4_sql i4_say i4_ready i4_mark i4_since and i5 ... (thin wrappers over lane_* <n> functions).
# Lane facts (registry C:\KenshiTestRuns\lanes\lanes-5090.json): i4 = instance 4, backend 127.0.0.1:18087, PG 15438, DB stobe_imm26_5090_i4,
# root /tmp/stobe-imm26-5090-i4, save kah-imm26-i4; i5 = instance 5, 18088, 15439, stobe_imm26_5090_i5, /tmp/stobe-imm26-5090-i5, kah-imm26-i5.
# Never touches instance 1/2/3, the Steam install, /var/www/html/StobeServer or the live DB (5432). Selftest: lanes_selftest.
LANES_WSL='wsl.exe -d DwemerAI4Skyrim3 -u root --cd / -- bash -s'
lane_root() { echo "/tmp/stobe-imm26-5090-i$1"; }
lane_port() { echo $((18086 + $1 - 3)); }
lane_pg()   { echo $((15437 + $1 - 3)); }
lane_db()   { echo "stobe_imm26_5090_i$1"; }
lane_pre() {  # preamble text (ends with a newline; the body goes on its own line)
  printf 'export RIG=5090 KAH_INSTANCE=%s\n. /mnt/c/KenshiModding/tools/automation/rig-env.sh\nif [ -e "$KDIR/mods/AutomationHarness/inbox.txt" ] || [ -e "$KDIR/mods/AutomationHarness/inbox.txt.lock" ]; then echo "STOP lane i%s harness inbox pending or locked" >&2; exit 3; fi\n' "$1" "$1"
}
lane_run()  { local n=$1; { lane_pre "$n"; cat; } | MSYS_NO_PATHCONV=1 $LANES_WSL; }                       # stdin body in WSL, harness = lane n
lane_runw() { local n=$1; { printf 'source %s/env.sh\n' "$(lane_root "$n")"; cat; } | MSYS_NO_PATHCONV=1 $LANES_WSL; }  # + private backend env
lane_sql()  { local n=$1; printf 'runuser -u postgres -- psql -h %s/socket -p %s -d %s -At -c "%s"\n' "$(lane_root "$n")" "$(lane_pg "$n")" "$(lane_db "$n")" "$2" | MSYS_NO_PATHCONV=1 $LANES_WSL; }
lane_say() {  # lane_say <n> "#serial/idx" "text" [wait_s]
  local n=$1 target="$2" text="$3" wait_s="${4:-150}"
  lane_run "$n" <<EOT
L="/mnt/d/KenshiInst/$n/RE_Kenshi/mods/Stobe/stobe.log"; n0=\$(wc -l < "\$L")
stobe-auto stobe_say "$target" "$text" 2>&1 | head -2
end=\$((SECONDS+$wait_s))
while [ \$SECONDS -lt \$end ]; do sleep 2; tail -n +\$((n0+1)) "\$L" | grep -qE "ACTION_EXEC: SAY \[[^]]*\](.*)\(NPC\)" && { sleep 3; break; }; done
tail -n +\$((n0+1)) "\$L" | grep -E "resolved_speaker|ERROR|Empty stream|ACTION_EXEC: SAY|ACTION_EXEC: Setting task" | cut -c1-300
EOT
}
lane_ready() {
  lane_run "$1" <<EOT
stobe-auto status; stobe-auto stobe_ping; stobe-auto time
curl -s http://127.0.0.1:$(lane_port "$1")/health.php | head -c 200; echo
EOT
}
lane_mark() {  # prints "ctxlines stobelines eventrow"
  local n=$1 c s e
  c=$(lane_runw "$n" <<<"wc -l < $(lane_root "$n")/site/log/context_sent_to_llm.log"); s=$(lane_run "$n" <<<"wc -l < /mnt/d/KenshiInst/$n/RE_Kenshi/mods/Stobe/stobe.log"); e=$(lane_sql "$n" "select coalesce(max(rowid),0) from eventlog")
  echo "$c $s $e"
}
lane_since() {  # lane_since <n> "c s e" [regex]
  local n=$1; set -- $2 "${3:-}"; local c=$1 s=$2 e=$3 pat="${4:-}"
  lane_sql "$n" "select rowid,type,left(data,140),coalesce(delivery_state,'') from eventlog where rowid>$e and type<>'combat' order by rowid" | head -20
  lane_run "$n" <<EOT
tail -n +$((s+1)) /mnt/d/KenshiInst/$n/RE_Kenshi/mods/Stobe/stobe.log | grep -E "ACTION_EXEC|resolved_speaker" | cut -c1-260 | head -12
EOT
  [ -n "$pat" ] && lane_runw "$n" <<EOT
tail -n +$((c+1)) $(lane_root "$n")/site/log/context_sent_to_llm.log | grep -n -i -E "$pat" | cut -c1-260 | head -12
EOT
}
for _n in 4 5; do
  eval "i$_n() { lane_run $_n; }; i${_n}w() { lane_runw $_n; }; i${_n}_sql() { lane_sql $_n \"\$1\"; }; i${_n}_say() { lane_say $_n \"\$@\"; }; i${_n}_ready() { lane_ready $_n; }; i${_n}_mark() { lane_mark $_n; }; i${_n}_since() { lane_since $_n \"\$@\"; }"
done
unset _n
lanes_selftest() {
  local bad=0 n out
  for n in 4 5; do
    out=$(lane_pre $n; echo 'echo BODY')
    [ "$(printf '%s\n' "$out" | sed -n 4p)" = 'echo BODY' ] || { echo "SELFTEST FAIL i$n body not on its own line"; bad=1; }
    printf '%s\n' "$out" | grep -q "KAH_INSTANCE=$n" || { echo "SELFTEST FAIL i$n instance"; bad=1; }
    declare -F i$n i${n}w i${n}_sql i${n}_say i${n}_ready i${n}_mark i${n}_since >/dev/null || { echo "SELFTEST FAIL i$n functions"; bad=1; }
    [ "$(lane_port $n)" = "$((18083 + n))" ] || { echo "SELFTEST FAIL i$n port"; bad=1; }
  done
  [ $bad = 0 ] && echo 'SELFTEST PASS 5090-imm26-lanes-lib (i4,i5)'
  return $bad
}
