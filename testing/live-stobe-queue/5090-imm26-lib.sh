#!/usr/bin/env bash
# 5090-imm26-lib.sh: drive the ISOLATED 5090 instance-3 imm26 lane (D:\KenshiInst\3, private backend 127.0.0.1:18086) from the 5090 Git Bash.
#   source /c/KenshiModding/testing/live-stobe-queue/5090-imm26-lib.sh
# Same function names as 4080-imm26-lib.sh (i3, i3w, i3_say, i3_sql, i3_ready, i3_selftest); here they run in WSL root (stobe-auto lives in WSL).
# Never touches instance 1/2, Shay's Steam install, /var/www/html/StobeServer or the live DB (port 5432).
#   i3  <<'EOF' ... EOF   bash body in WSL with RIG=5090 KAH_INSTANCE=3 (stobe-auto = i3 harness); fails if the harness inbox is pending/locked
#   i3w <<'EOF' ... EOF   same body in WSL root with the private-backend env (source env.sh: PG* vars, php)
#   i3_say <target> <text> [wait_s]   stobe_say + wait for the NPC reply (ACTION_EXEC: SAY ... (NPC)) in stobe.log, print reply lines
#   i3_sql "<select>"     read-only SQL on stobe_imm26_5090 (private PG socket /tmp/stobe-imm26-5090/socket port 15437)
#   i3_ready              one-screen readiness (status, ping, time, PID + module hashes, backend health)
#   i3_selftest           offline preamble check
I3_PRE=$'export RIG=5090 KAH_INSTANCE=3\n. /mnt/c/KenshiModding/tools/automation/rig-env.sh\nif [ -e "$KDIR/mods/AutomationHarness/inbox.txt" ] || [ -e "$KDIR/mods/AutomationHarness/inbox.txt.lock" ]; then echo "STOP inbox pending or locked"; exit 3; fi\n'
# NOTE: keep the newline after the preflight line; gluing the body onto it breaks the first word.
I3_WSL='wsl.exe -d DwemerAI4Skyrim3 -u root --cd / -- bash -s'
i3()  { { printf '%s' "$I3_PRE"; cat; } | MSYS_NO_PATHCONV=1 $I3_WSL; }
i3w() { { printf '%s\n' 'source /tmp/stobe-imm26-5090/env.sh'; cat; } | MSYS_NO_PATHCONV=1 $I3_WSL; }
i3_sql() {
  printf '%s\n' "runuser -u postgres -- psql -h /tmp/stobe-imm26-5090/socket -p 15437 -d stobe_imm26_5090 -At -c \"$1\"" | MSYS_NO_PATHCONV=1 $I3_WSL
}
i3_say() {  # i3_say "#serial/idx" "text" [wait_s]
  local target="$1" text="$2" wait_s="${3:-150}"
  i3 <<EOT
L="/mnt/d/KenshiInst/3/RE_Kenshi/mods/Stobe/stobe.log"; n0=\$(wc -l < "\$L")
stobe-auto stobe_say "$target" "$text" 2>&1 | head -2
end=\$((SECONDS+$wait_s))
while [ \$SECONDS -lt \$end ]; do sleep 2; tail -n +\$((n0+1)) "\$L" | grep -qE "ACTION_EXEC: SAY \[[^]]*\](.*)\(NPC\)" && { sleep 3; break; }; done
tail -n +\$((n0+1)) "\$L" | grep -E "resolved_speaker|ERROR|Empty stream|ACTION_EXEC: SAY|ACTION_EXEC: Setting task" | cut -c1-300
EOT
}
i3_ready() {
  i3 <<'EOT'
stobe-auto status; stobe-auto stobe_ping; stobe-auto time
curl -s http://127.0.0.1:18086/health.php | head -c 200; echo
EOT
  powershell.exe -NoProfile -Command '$p=Get-Process kenshi_x64 -EA SilentlyContinue; if($p){"PID "+$p.Id+" "+$p.Path; $p.Modules | ? {$_.FileName -match "Stobe|AutomationHarness"} | % {$_.FileName+" "+(Get-FileHash $_.FileName).Hash}} else {"NO KENSHI"}'
}
i3_selftest() {
  local out; out=$(printf '%s' "$I3_PRE"; echo 'echo BODY')
  [ "$(printf '%s\n' "$out" | sed -n 4p)" = 'echo BODY' ] || { echo 'SELFTEST FAIL body not on its own line'; return 1; }
  echo 'SELFTEST PASS 5090-imm26-lib preamble'
}
# Row helpers. i3_mark prints "ctxlines stobelines eventrow"; i3_since <mark> [grep_pattern] prints new eventlog rows, new ACTION_EXEC lines and
# matching lines of the new PROMPT capture (context_sent_to_llm.log).
I3_SITELOG=/tmp/stobe-imm26-5090/site/log
i3_mark() {
  local c s e; c=$(i3w <<<"wc -l < $I3_SITELOG/context_sent_to_llm.log"); s=$(i3 <<<'wc -l < /mnt/d/KenshiInst/3/RE_Kenshi/mods/Stobe/stobe.log'); e=$(i3_sql "select coalesce(max(rowid),0) from eventlog")
  echo "$c $s $e"
}
i3_since() {  # i3_since "c s e" ["regex"]
  set -- $1 "${2:-}"; local c=$1 s=$2 e=$3 pat="${4:-}"
  i3_sql "select rowid,type,left(data,140),coalesce(delivery_state,'') from eventlog where rowid>$e and type<>'combat' order by rowid" | head -20
  i3 <<EOT
tail -n +$((s+1)) /mnt/d/KenshiInst/3/RE_Kenshi/mods/Stobe/stobe.log | grep -E "ACTION_EXEC|resolved_speaker" | cut -c1-260 | head -12
EOT
  [ -n "$pat" ] && i3w <<EOT
tail -n +$((c+1)) $I3_SITELOG/context_sent_to_llm.log | grep -n -i -E "$pat" | cut -c1-260 | head -12
EOT
}
# H-AFF: i3_haff "<npc>" "<counterpart>" <value> <type>   (type read = only print). Private DB only.
i3_haff() { i3w <<<"php /mnt/c/KenshiTestRuns/imm26-5090/haff.php \"$1\" \"$2\" ${3:-0} ${4:-read}"; }
# P-RECEIPT check: i3_receipt (playthrough session + manager_ready_matches on the private backend)
i3_receipt() { i3w <<<"php /mnt/c/KenshiTestRuns/imm26-5090/session-read.php"; }
