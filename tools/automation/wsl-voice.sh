#!/usr/bin/env bash
# wsl-voice.sh <stt|tts|all> <start|stop|status>: Parakeet speech-to-text (~3 GB) and PocketTTS audiocpp_server
# (~1.4 GB) in the DwemerAI4Skyrim3 stack. RAM rule (CLAUDE.md): both stay stopped unless a batch tests voice
# input (stt) or audio/TTS (tts); /etc/start_env starts both, so run "all stop" after wsl-restart.ps1.
# Run as root inside WSL: wsl.exe -d DwemerAI4Skyrim3 -u root --cd / -- bash /mnt/c/KenshiModding/tools/automation/wsl-voice.sh all stop
set -u
what=${1:?stt|tts|all}; act=${2:?start|stop|status}; wait=0; [ "${3:-}" = --wait ] && wait=${4:-120}  # stop --wait N: first wait up to N s for start_env to launch it
dir_of() { case $1 in stt) echo /home/dwemer/parakeet-api-server ;; tts) echo /home/dwemer/audio.cpp ;; esac; }
pids_of() { local d; d=$(dir_of "$1"); for p in $(pgrep -f "python server.py|audiocpp_server|start_native.sh"); do [ "$(readlink /proc/$p/cwd 2>/dev/null)" = "$d" ] && echo "$p"; done; }
for s in $([ "$what" = all ] && echo "stt tts" || echo "$what"); do
  case $act in
    stop)   for i in $(seq 1 "$wait"); do [ -n "$(pids_of "$s")" ] && break; sleep 1; done
            p=$(pids_of "$s"); [ -n "$p" ] && kill $p; for i in 1 2 3 4 5 6 7 8 9 10; do [ -z "$(pids_of "$s")" ] && break; sleep 1; done
            p=$(pids_of "$s"); [ -n "$p" ] && kill -9 $p; echo "$s stopped" ;;
    start)  [ -n "$(pids_of "$s")" ] && { echo "$s already running"; continue; }; su dwemer -c "$(dir_of "$s")/start.sh" >/dev/null 2>&1; echo "$s started" ;;
    status) p=$(pids_of "$s"); if [ -n "$p" ]; then echo "$s running rss_mb=$(( $(ps -o rss= -p $p | awk '{s+=$1} END{print s}') / 1024 ))"; else echo "$s stopped"; fi ;;
  esac
done
