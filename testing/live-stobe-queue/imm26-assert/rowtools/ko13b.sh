#!/usr/bin/env bash
# ko13b.sh <lane> [trip-run options]   IMM-13-b one call: armed-KO abandon test with the healthy-partner control (see tripdefs.sh rd_13b).
#   Needs the NC6 DLL (3ADDE488) on the lane, a squad with Malzin and Cind, and does NOT order Cind IDLE. = trip-run.sh 13-b <lane> ...
exec bash "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/trip-run.sh" 13-b "$@"
