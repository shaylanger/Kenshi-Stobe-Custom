#!/bin/sh
set -eu
here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
tmp=${TMPDIR:-/tmp}/kfp-toggle-key-policy-$$
trap 'rm -f "$tmp"' EXIT HUP INT TERM
cc -std=c99 -Wall -Wextra -Werror -O2 "$here/test_toggle_key_policy.c" -o "$tmp"
"$tmp"
