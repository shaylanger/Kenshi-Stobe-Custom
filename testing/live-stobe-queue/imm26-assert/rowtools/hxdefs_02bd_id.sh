# hxdefs_02bd_id.sh (imm26-i3op30): sourced AFTER hxdefs_02bd.sh by hxrun_02bd_id.sh. Two live defects of the 02-bx control (4080-i3 op30, 2026-10-16):
#  1 `stobe-auto where "Hungry Bandit"` matched Cind (template name Hungry Bandit, teleported to HX_FAR): S1 went to the wrong NPC (dist_to_target=6110).
#  2 the server RENAMES the spawned bandit at its first chat ("Hungry Bandit" -> "Karnith [Hungry Bandit]"), but hxd_sample waits for a reply from the pre-chat
#    short name: it timed out although the NPC answered ("no reply of Hungry within 150s in S1").
# Fix: the control is found by its #serial/idx id; one unscored priming chat (dir P0, reply not required) makes the server rename it BEFORE S1; afterwards
# CTL_FULL = the control's current name (resolved from the id), so the original S1-S3 loop and its wait pattern work unchanged.
hx02bd_ctl_resolve() {
  local id="${CTL_ID:-}" q
  if [ -z "$id" ]; then id="$(grep -oE '#[0-9]+/[0-9]+' "$EV/spawn.txt" 2>/dev/null | tail -1)"; fi
  [ -n "$id" ] || { hxd_dry && id="${HX_SPAWNED:-Dry}"; }
  [ -n "$id" ] || { RL_REASON="cannot resolve the spawned control NPC: no #id in $EV/spawn.txt"; return 3; }
  CTL_ID="$id"
  if [ -z "${HX02BD_PRIMED:-}" ]; then
    HX02BD_PRIMED=1
    hxd_sample P0 "Hello there." "$id" 60 noreply || return $?
    echo "prime: control chatted once (dir P0, unscored) so the server renames it before S1" >> "$EV/phases.txt"
  fi
  rl_resolve "$id" || { RL_REASON="cannot resolve the spawned control NPC by id $id (see $EV/spawn.txt)"; return 3; }
  CTL_FULL="$RL_NPC_FULL"; echo "$CTL_FULL $CTL_ID" > "$EV/ctl_npc.txt"; return 0
}
