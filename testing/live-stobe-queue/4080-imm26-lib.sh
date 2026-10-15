#!/usr/bin/env bash
# 4080-imm26-lib.sh: drive the ISOLATED 4080 instance-3 lane from the 5090's Git Bash. Source it:
#   source /c/KenshiModding/testing/live-stobe-queue/4080-imm26-lib.sh
# Bodies go over ssh STDIN (no quoting/base64 problems). Never touches the 5090 game or instances 1/2.
#   i3 <<'EOF' ... EOF          run a bash body on the 4080 i3 route (RIG=4080 KAH_INSTANCE=3, preflight first; stobe-auto = i3 harness)
#   i3w <<'EOF' ... EOF         same body in WSL root on the 4080 (private backend: psql, php, /tmp/stobe-standalone4080)
#   i3_say <target> <text>      stobe_say + wait for the NPC's reply line in stobe.log (default wait 150 s), prints the reply
#   i3_sql "<select ...>"       read-only SQL on the isolated DB stobe_standalone4080_test
#   i3_ready                    one-screen readiness receipt (PID, module hashes, health, session, status, ping)
#   i3_selftest                 offline check of the preamble (no ssh)
I3_PRE=$'export RIG=4080 KAH_INSTANCE=3\n. /c/KenshiModding/tools/automation/rig-env.sh\nrig4080_i3_preflight >/dev/null || exit $?\n'
# NOTE: the newline after the preflight line matters; gluing the body onto "exit $?" silently turns its first word into part of the line.
i3()  { { printf '%s' "$I3_PRE"; cat; } | ssh -o BatchMode=yes 4080 '"C:\Program Files\Git\bin\bash.exe" -l -s'; }
i3w() { cat | ssh -o BatchMode=yes 4080 'wsl.exe -d DwemerAI4Skyrim3 -u root --cd / -- bash -s'; }
i3_sql() {
  printf '%s\n' "runuser -u postgres -- psql -h /tmp/stobe-standalone4080/socket -p 15434 -d stobe_standalone4080_test -At -c \"$1\"" | i3w
}
i3_say() {  # i3_say "#2529907200/2" "Got any news?" [wait_s]
  local target="$1" text="$2" wait_s="${3:-150}"
  i3 <<EOF
L="/c/KenshiInst/3/RE_Kenshi/mods/Stobe/stobe.log"; n0=\$(wc -l < "\$L")
stobe-auto stobe_say "$target" "$text" 2>&1 | head -2
end=\$((SECONDS+$wait_s))
while [ \$SECONDS -lt \$end ]; do sleep 3; tail -n +\$((n0+1)) "\$L" | grep -qE "ACTION_EXEC: SAY \\[[^]]*\\](.*)\\(NPC\\)" && { sleep 4; break; }; done
tail -n +\$((n0+1)) "\$L" | grep -E "resolved_speaker|ERROR|Empty stream|ACTION_EXEC: SAY|ACTION_EXEC: Setting task" | cut -c1-300
EOF
}
i3_ready() {
  i3 <<'EOF'
stobe-auto status; stobe-auto stobe_ping; stobe-auto time
powershell.exe -NoProfile -Command "\$p=Get-Process kenshi_x64 -EA SilentlyContinue; if(\$p){'PID '+\$p.Id+' '+\$p.Path; \$p.Modules | ? {\$_.FileName -match 'Stobe|AutomationHarness'} | % {\$_.FileName+' '+(Get-FileHash \$_.FileName).Hash}} else {'NO KENSHI'}; try{(Invoke-WebRequest -UseBasicParsing http://127.0.0.1:18084/health.php -TimeoutSec 5).Content}catch{'BACKEND DOWN'}" | cut -c1-200
EOF
}
i3_selftest() {
  local out; out=$(printf '%s' "$I3_PRE"; echo 'echo BODY')
  [ "$(printf '%s\n' "$out" | sed -n 3p)" = 'rig4080_i3_preflight >/dev/null || exit $?' ] || { echo 'SELFTEST FAIL preamble line 3'; return 1; }
  [ "$(printf '%s\n' "$out" | sed -n 4p)" = 'echo BODY' ] || { echo 'SELFTEST FAIL body not on its own line'; return 1; }
  echo 'SELFTEST PASS 4080-imm26-lib preamble'
}
