#!/bin/bash
# fp-weapon-sweep-ref.sh <out dir> <list> [name] [vmset key] [value]: fp-weapon-sweep.sh with VMSET="<key> <value>"
# (default "twomask 0" = old one-handed look) for side-by-side reference takes. Batch lists word-split their commands,
# so a VMSET value with a space can't be passed inline; this wrapper does it.
VMSET="${4:-twomask} ${5:-0}" exec bash "$(dirname "$0")/fp-weapon-sweep.sh" "$1" "$2" "${3:-}"
