#!/bin/bash
# usage: apply.sh <tree root>  (compose tree); idempotent check via --dry-run first
set -e; T=${1:?tree}; cd "$T"
patch -p1 --dry-run < "$(dirname "$0")/sfV.patch" && patch -p1 < "$(dirname "$0")/sfV.patch"
php -l lib/npc_player_view.php
