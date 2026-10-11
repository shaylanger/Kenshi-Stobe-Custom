#!/bin/bash
# live-tune.sh: closed-loop pose tuning in the running game (one launch, dozens of candidates, no video).
# The take script lives with the other take scripts (synced to both rigs): components/KenshiFP/tests/ingame/live-tune.sh
# (usage, spec format, outputs in its header; driver live_tune.py next to it). This is a shortcut to it.
exec bash "$(cd "$(dirname "$0")/../.." && pwd)/components/KenshiFP/tests/ingame/live-tune.sh" "$@"
