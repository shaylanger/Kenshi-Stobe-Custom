#!/usr/bin/env bash
set -euo pipefail
export PROVIDER_RELEASE_RECEIPT=/mnt/c/KenshiModding/testing/live-stobe-queue/5090-i3-p0-provider-release-20261014.txt
export CURRENT_BUILD_RECEIPT=/mnt/c/KenshiModding/testing/live-stobe-queue/5090-i3-p0-build-preflight-20261014.txt
export CURRENT_AUTH_RECEIPT=/mnt/c/KenshiModding/testing/live-stobe-queue/5090-i3-p0-auth-preflight-20261014.txt
exec bash /mnt/c/KenshiModding/testing/live-stobe-queue/5090-i3-p0-ready-dispatch-20261014.sh
