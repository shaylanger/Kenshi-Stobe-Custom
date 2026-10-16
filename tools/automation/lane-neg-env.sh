#!/usr/bin/env bash
# lane-neg-env.sh <env.sh> <stobe_log> <kfp_log> <action_request>     (WSL; idempotent)
# Makes a lane backend's env.sh export the three negotiation file paths of THAT LANE's own game instance, so
# lib/negotiation_engine.php (stobeNegStobeLogPath/KfpLogPath/ActionRequestPath, :426-431, :623) never falls back to
# Shay's live install (/mnt/d/Steam/.../Kenshi). Replaces any older STOBE_NEG_* export line. Read by php -S / manager.sh only at start.
set -eu
env=${1:?env.sh}; slog=${2:?stobe_log}; klog=${3:?kfp_log}; areq=${4:?action_request}
case "$slog$klog$areq" in */Steam/*|*/steamapps/*) echo "lane-neg-env: refusing a path in Shay's Steam install" >&2; exit 3;; esac
[ -f "$env" ] || { echo "lane-neg-env: $env missing" >&2; exit 1; }
tmp="$env.negtmp.$$"
grep -v 'STOBE_NEG_' "$env" > "$tmp" || true
printf 'export STOBE_NEG_STOBE_LOG=%q STOBE_NEG_KFP_LOG=%q STOBE_NEG_ACTION_REQUEST=%q # lane-neg-env\n' "$slog" "$klog" "$areq" >> "$tmp"
cat "$tmp" > "$env"; rm -f "$tmp"
echo "lane-neg-env: $env -> $slog"
