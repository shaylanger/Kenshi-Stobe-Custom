#!/usr/bin/env bash
# unblockdefs_f3.sh (imm26-sfFixB, 2026-10-16): rows 13-c / 13-c-neg with a PARTICIPATION-QUALIFIED walk. NEW file; unblockdefs_b/f/f2.sh and sfr22b_keep.sh are NOT edited.
# Sourced by unblockrun_f3.sh AFTER unblockdefs_f.sh (rd_13c / rd_13cneg / arrival turn stay exactly as there).
# Why the f runner could not give 13-c a valid sample: (1) NC20 and older never bound the participation proof (participation_bound=0: Character::getInstanceID() is NULL) - fixed in NC21
#   (80f79305, contained in NC28/NC30/NC31); 08-d.prev proved the chain on NC21+ (qualified=1 -> 'Participation award' status enabled -> one sharedexp kept_promise row).
#   (2) The proof is only qualified when Shay stays within 35 u of the NPC at EVERY native sample of the LAST unbroken window (ParticipationEvidence.h); the f hop walk (5 teleports,
#   then ssh/sql gaps) broke the window 4-36 times and 22-b run 1 ended with a last window of 8 s (qualified=0). So here:
#   * positive leg  : sfr22b_keep.sh keeper (one harness call teleports Shay onto the NPC every ~SFK_KEEP_SLEEP s until a native end line) at game speed TRIP_13C_SPEED (default 0.5, the lane
#                     default, i.e. half the NPC real-time speed of speed 1: drift per teleport gap halves; the thresholds are in game time so the walk is just as qualifying).
#   * negative leg  : unchanged hop walk with Shay held TRIP_13C_NEG_GAP u behind (strict native-end classification of unblockdefs_f2.sh).
#   * native_travel.txt now keeps the START line, the terminal NATIVE_TRAVEL line (participation_qualified + participation_diag) and every FINISH/ORDER_ENDED/PART_BIND line (the f dump
#     kept only the first 14 lines, so a long walk could push the terminal line out).
UF3_HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
declare -F uf_terminal >/dev/null || . "$UF3_HERE/unblockdefs_f.sh"
. "$UF3_HERE/unblockdefs_f2.sh"           # strict classify; shadows uf_native_end + uf_walk_stage (hop walk)
eval "uf3_hop_walk_stage() $(declare -f uf_walk_stage | sed '1d')"
. "$UF3_HERE/sfr22b_keep.sh"               # shadows uf_walk_stage (keeper)
eval "uf3_keep_walk_stage() $(declare -f uf_walk_stage | sed '1d')"
uf_walk_stage() {   # uf_walk_stage <npc-quoted> <gate> <back> <neg 0|1> <gap> <speed> <tries>
  if [ "$4" = 1 ]; then uf3_hop_walk_stage "$@"; else uf3_keep_walk_stage "$1" "$2" "$3" "$4" "$5" "$6" "${UF3_KEEP_CALLS:-8}"; fi
}
uf_native_dump() {  # uf_native_dump <file> : START/terminal/FINISH/ORDER_ENDED/PART_BIND lines of this walk + the last 2 OBS lines
  lt_h <<EOT > "$EV/$1" 2>&1
tail -n +$(( ${UF_N0:-0} + 1 )) $LT_STOBELOG 2>/dev/null | grep -a -E 'NATIVE_TRAVEL_START|NATIVE_TRAVEL_FINISH|NATIVE_TRAVEL_ORDER_ENDED|NATIVE_TRAVEL_PART_BIND|NATIVE_TRAVEL[: ].*terminal=1' | cut -c1-520 | head -14 # uf:ndump
tail -n +$(( ${UF_N0:-0} + 1 )) $LT_STOBELOG 2>/dev/null | grep -a NATIVE_TRAVEL_OBS | cut -c1-320 | tail -2 # uf:nobs
EOT
}
