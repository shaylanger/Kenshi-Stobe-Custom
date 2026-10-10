#!/usr/bin/env bash
# stobe-server.sh off|on|status   (WSL root: wsl.exe -d DwemerAI4Skyrim3 -u root --cd / -- bash /mnt/c/KenshiModding/tools/automation/stobe-server.sh off)
# Shay 2026-10-10: animation/combat (KenshiFP) work doesn't need STOBE, but the Stobe mod in the running game kept sending
# NPC events (mostly "combat") to the server, which called the LLM (DeepInfra/OpenRouter) ~2x per minute = wasted credits.
#   off: stop apache2 (the game's Stobe.dll requests then fail quietly with NETWORK_ERROR) and the background
#        processor loop (service/start.sh -> manager.php: memory/diary/relationship cycles). WSL keeps running
#        (builds, animlab, pipeline). Note: apache2 also serves the other vhosts (Dialectic/Herika) while off.
#   on:  start apache2 + the processor loop as /etc/start_env does (user dwemer).
# STOBE test batches need it ON; KenshiFP/harness/animlab batches run with it OFF.
set -u
S=/var/www/html/StobeServer/service/start.sh
case "${1:-status}" in
  off) service apache2 stop >/dev/null 2>&1; pkill -f "StobeServer/service/start.sh"; pkill -f "StobeServer/service/manager.php"; sleep 1 ;;
  on)  service apache2 start >/dev/null 2>&1
       pgrep -f "StobeServer/service/start.sh" >/dev/null || su dwemer -c "nohup bash '$S' >/dev/null 2>&1 </dev/null &"; sleep 1 ;;
  status) ;;
  *) echo "usage: stobe-server.sh off|on|status"; exit 2 ;;
esac
a=$(pgrep -c apache2); p=$(pgrep -fc "StobeServer/service/start.sh")
[ "$a" -gt 0 ] || [ "$p" -gt 0 ] && echo "STOBE-SERVER ON apache2=$a processor=$p" || echo "STOBE-SERVER OFF (no LLM calls)"
