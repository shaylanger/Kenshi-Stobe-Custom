#!/usr/bin/env bash
# reloaddefs_sfi.sh (imm26-sfI): hunt26a-scene ground for the three Hunt save+load rows 26-d, 26-dx, 26-e (SETUP-FAIL tickets 26-d/26-dx/26-e, 5090-i3 op20 2026-10-16).
# Sourced by reload-run-sfi.sh AFTER go-row.sh and reloaddefs_a.sh: it REPLACES rd_26d / rd_26dx / rd_26e (and nothing else) in that shell only. reloaddefs_a.sh,
# reload-run.sh, reloadcheck_a.py are untouched (queued lists use them); the checker is the unchanged reloadcheck_a.py via reload-py.sh.
#
# Why: the set-A recipe spawns "wild goats" `near <npc> dist 7` at the ready-save spot (Copper Mine V -53205,960,4852). There Cind has canISee=0 / canIHear=0 for the goats
# (ACTIVITY_SIGHT_DIAG), the candidate is suitable:false and no Hunt proposal comes. The scene that passes 25-a / 26-a is rowtools/hunt26a-scene.sh (recipe
# agents/out/imm26-26a-recipe/latest.md): the open ground E of the Hub (Shay -49400 1660 3625, NPC -49422 1661 3643), goats spawned `at -49405 1664 3645` (NOT near/dist 7: goats
# within ~12 u flee), pinned in place, NPC faced to the first goat, `senses` sees=1 as the go/no-go, relation 50, H-AFF friend 60, quarrel apology, ctxpush, NPC faction
# re-serial (clears personal enmity -> no requester_now_hostile), accept only after the offer speech was DELIVERED (RECHAT_TIMING follow-up; a Yes during delivery cancels the offer).
# This file ports that scene to the generic lane helpers (lt_h / rl_say / rd19_*), so it runs on any lane, and rebuilds it after the load (pins are dropped on load).
#
# Steps / evidence (all under $EV): scene.txt (+ plain_say.txt apology), scene_pre.txt scene_post.txt (last line SCENE-OK | SCENE-BAD <why>), spawn_<tag>.txt goats_<tag>.txt,
#   s1 [s1b] s2 [s2c] s3 (say bundles, same numbering as set A so reloadcheck_a.py is unchanged), delivery_<step>.txt, act_*.txt, out_*.txt.
#   A bad scene is SETUP-FAIL (rc 3 + RL_REASON), never a FAIL: it proves nothing about the resume feature.
# Env knobs: RW_FACTION ("Traders Guild": re-serial the NPC into this faction; "Nameless" = the player faction, needs NC17 Stobe.dll) RW_REFACTION=0 (skip the re-serial)
#   RW_APOLOGY=0 (skip the apology) RW_APOLOGY_WAIT (8) RW_GOATS (8 spawned, the first 5 pinned) RW_PIN_GOATS=0 RW_EG_SHAY ("-49400 1660 3625") RW_EG_NPC ("-49422 1661 3643")
#   RW_EG_GOAT ("-49405 1664 3645") RW_SENSE_TRIES (3) RW_DELIVERY_WAIT (40 s) RW_ACCEPT_DELAY (1 s) RW_OFFER2 (fallback wording) plus every set-A knob (RW_OFFER RW_ACCEPT RW_RESUME_SAY RW_COMPLETE ...).
SI_OFFER2_DEF="Agreed, we split the meat evenly and stay together. Will you hunt one of these goats with me?"   # op8e: offer in 8 s when the first wording got a FOLLOW instead

si_sh() { printf '%s\n' "$1" | lt_h 2>&1; }
si_say_plain() {   # si_say_plain <npc id> <text> [wait s]: one stobe_say that is NOT a row step (apology); waits for the first NPC sentence. Evidence plain_say.txt
  rl_prep_player || return 0
  lt_h <<EOT >> "$EV/plain_say.txt" 2>&1
L=$(rl_q "$LT_STOBELOG"); n0=\$(wc -l < "\$L")
stobe-auto stobe_say "$1" $(rl_q "$2") </dev/null 2>&1 | head -2
end=\$((SECONDS+${3:-40}))
while [ \$SECONDS -lt \$end ]; do sleep 2; tail -n +\$((n0+1)) "\$L" | grep -qE "ACTION_EXEC: SAY \[[^]]*\](.*)\((NPC|PC)\)" && { sleep 3; break; }; done
EOT
}
si_scene_base() {   # once per row, before the goats: teleports, relation, friend 60, ctxpush, apology. rc 3 + RL_REASON when the NPC cannot be resolved
  local c n sc="$EV/scene.txt" sh="${RW_EG_SHAY:--49400 1660 3625}" np="${RW_EG_NPC:--49422 1661 3643}"
  : > "$sc"; unset TR_SCENE
  rl_resolve "$ROW_NPC" >/dev/null 2>&1 || { RL_REASON="cannot resolve $ROW_NPC for the hunt scene"; return 3; }
  c="$RL_NPC_ID"
  lt_h <<EOT >> "$sc" 2>&1
stobe-auto wake "$c" </dev/null | head -1; stobe-auto health "$c" 100 </dev/null | head -1; sleep 3
stobe-auto pin "$c" off </dev/null | head -1; stobe-auto pin Shay off </dev/null | head -1
stobe-auto teleport Shay $sh </dev/null | head -2
stobe-auto teleport "$c" $np </dev/null | head -2
stobe-auto select Shay </dev/null | head -1
stobe-auto relation "$c" 50 </dev/null | head -2
for w in Shay Malzin; do stobe-auto stobe_drawn sheathe \$w </dev/null | head -1; done
EOT
  rw_sleep 10                                                                # NPC onmesh (ACTIVITY_PROPOSAL_DIAG gate=navigation onmesh=0 otherwise)
  tr_clean_db                                                                # leftover travel_agreement rows make the NPC answer "agree on the changed travel plans first"
  rd_aff 60 friend haffi
  rl_resolve "$ROW_NPC" >/dev/null 2>&1; n=$(rl_q "$RL_NPC_FULL")
  printf 'stobe-auto stobe_ctxpush %s </dev/null | head -2\n' "$n" | lt_h >> "$sc" 2>&1
  if [ "${RW_APOLOGY:-1}" = 1 ]; then                                        # quarrel memory ("blade in my face"): one apology clears it for a few turns
    si_say_plain "$c" "It was a mistake, I'm sorry." 40
    rw_sleep "${RW_APOLOGY_WAIT:-8}"
    printf 'stobe-auto stobe_ctxpush %s </dev/null | head -2\n' "$n" | lt_h >> "$sc" 2>&1
  fi
  return 0
}
si_refaction() {   # re-serial the NPC into RW_FACTION (clears baked personal enmity -> no requester_now_hostile); sets RL_NPC_ID from the command's answer
  local fo nid
  fo=$(si_sh "stobe-auto faction $(rl_q "$RL_NPC_ID") $(rl_q "${RW_FACTION:-Traders Guild}") </dev/null | head -2"); echo "faction: $fo" >> "$EV/scene.txt"
  nid=$(echo "$fo" | grep -oE '#[0-9]+/[0-9]+' | head -1)
  rw_sleep 3
  rl_resolve "$ROW_NPC" >/dev/null 2>&1
  [ -z "$nid" ] || RL_NPC_ID="$nid"                                          # the name lookup can hit a namesake (Cade shared a handle); the command's own id is exact
  echo "npc id now $RL_NPC_ID" >> "$EV/scene.txt"
}
si_goats() {   # si_goats pre|post: (post: put Shay + NPC back on the ground first) spawn, pin, refaction (pre, late), face, senses go/no-go. rc 3 + RL_REASON when the NPC cannot see a goat
  local tag="$1" sc ids g1 pl g s sees t att c n sh="${RW_EG_SHAY:--49400 1660 3625}" np="${RW_EG_NPC:--49422 1661 3643}" at="${RW_EG_GOAT:--49405 1664 3645}"
  sc="$EV/scene_$tag.txt"; : > "$sc"
  rl_resolve "$ROW_NPC" >/dev/null 2>&1 || { RL_REASON="cannot resolve $ROW_NPC for the goats ($tag)"; return 3; }
  [ "$tag" = pre ] && [ -n "${SI_NPC_ID:-}" ] && RL_NPC_ID="$SI_NPC_ID"
  c="$RL_NPC_ID"
  if [ "$tag" = post ]; then
    lt_h <<EOT >> "$sc" 2>&1
stobe-auto pin "$c" off </dev/null | head -1; stobe-auto pin Shay off </dev/null | head -1
stobe-auto teleport Shay $sh </dev/null | head -1
stobe-auto teleport "$c" $np </dev/null | head -1
stobe-auto select Shay </dev/null | head -1
EOT
    rw_sleep 6
  fi
  for att in 1 2; do
    lt_h <<EOT > "$EV/spawn_$tag.txt" 2>&1
stobe-auto spawn "wild goats" Herbivore at $at count ${RW_GOATS:-8} size 0.2 </dev/null | head -3
sleep 2
stobe-auto chars 80 "[Herbivore]|!dead" </dev/null | head -6
EOT
    cut -c1-300 "$EV/spawn_$tag.txt" >> "$sc"
    ids=$(sed -n '/within/,$p' "$EV/spawn_$tag.txt" | grep -oE '#[0-9]+/[0-9]+' | grep -v "^$c$" | sort -u | head -5)   # chars answer only (herbivores)
    [ -n "$ids" ] || ids=$(grep -oE '#[0-9]+/[0-9]+' "$EV/spawn_$tag.txt" | grep -v "^$c$" | sort -u | head -5)
    [ -n "$ids" ] || { RL_REASON="SCENE-BAD no goats found after the spawn ($tag; see $EV/spawn_$tag.txt)"; echo "SCENE-BAD no goats" >> "$sc"; return 3; }
    echo "$ids" > "$EV/goats_$tag.txt"
    if [ "${RW_PIN_GOATS:-1}" = 1 ]; then                                    # goats flee at 10-25 u/s; the offer takes 10-15 s
      pl=""; for g in $ids; do pl="${pl}stobe-auto pin \"$g\" </dev/null | head -1"$'\n'; done; si_sh "$pl" >> "$sc"
    fi
    if [ "$tag" = pre ] && [ "${RW_REFACTION:-1}" = 1 ] && [ -z "${SI_REFACTIONED:-}" ]; then
      si_refaction; SI_REFACTIONED=1; SI_NPC_ID="$RL_NPC_ID"; c="$RL_NPC_ID"
      n=$(rl_q "$RL_NPC_FULL"); printf 'stobe-auto stobe_ctxpush %s </dev/null | head -2\n' "$n" | lt_h >> "$sc" 2>&1
    fi
    g1=$(echo $ids | awk '{print $1}')
    sees=0
    for t in $(seq 1 "${RW_SENSE_TRIES:-3}"); do                             # turn the NPC toward the first goat (sees=0/fov=0 while she faces away)
      si_sh "stobe-auto face $(rl_q "$c") $(rl_q "$g1") </dev/null | head -1; sleep 1" >> "$sc"
      sees=0
      for g in $ids; do
        s=$(si_sh "stobe-auto senses $(rl_q "$c") $(rl_q "$g") </dev/null | head -2"); echo "senses $g: $s" >> "$sc"
        echo "$s" | grep -qE 'sees=1' && sees=$((sees+1))
      done
      echo "attempt $att try $t senses sees=1 count=$sees of $(echo $ids | wc -w)" >> "$sc"
      [ "$sees" -ge 1 ] && break
      rw_sleep 2
    done
    [ "$sees" -ge 1 ] && break
    echo "respawn: attempt $att had no goat in sight" >> "$sc"
  done
  [ "$sees" -ge 1 ] || { echo "SCENE-BAD cind sees no goat" >> "$sc"; RL_REASON="SCENE-BAD the NPC sees no goat on the hunt ground ($tag; sees=0 for every goat after $att spawns; see $sc)"; return 3; }
  echo "SCENE-OK" >> "$sc"
  RL_NPC_ID="$c"
  return 0
}
si_wait_delivery() {   # si_wait_delivery <step>: wait until the offer speech of say step s<step> was delivered (RECHAT_TIMING follow-up), then the accept delay. Evidence delivery_<step>.txt
  local l; l=$(sed -nE 's/^mark=[0-9]+ [0-9]+ ([0-9]+) .*/\1/p' "$EV/s$1/meta.txt" 2>/dev/null | head -1); l=${l:-0}
  lt_h <<EOT > "$EV/delivery_$1.txt" 2>&1
L=$(rl_q "$LT_STOBELOG"); end=\$((SECONDS+${RW_DELIVERY_WAIT:-40}))
while [ \$SECONDS -lt \$end ]; do tail -n +$((l+1)) "\$L" | grep -qE "RECHAT_TIMING: follow-up (dispatch scheduled|suppressed)" && break; sleep 0.5; done
echo "DELIVERY_CONFIRMED \$(tail -n +$((l+1)) "\$L" | grep -E "RECHAT_TIMING: follow-up" | head -1 | cut -c1-120)"
EOT
  rw_sleep "${RW_ACCEPT_DELAY:-1}"
}
si_offer() {   # si_offer <dumpfile>: the Hunt offer (s1), one fallback wording (s1b) when no proposal; leaves the offer's say step name in SI_OFFER_STEP; the dump holds the final state
  local offer="${RW_OFFER:-$RW_OFFER_DEF}"
  SI_OFFER_STEP=1
  rl_say 1 "$offer" || return $?
  rw_act_dump "$1"
  if ! rw_has_status "$1" proposed; then
    SI_OFFER_STEP=1b
    rl_say 1b "${RW_OFFER2:-$SI_OFFER2_DEF}" || return $?
    rw_act_dump "$1"
  fi
  return 0
}
si_start() {   # common start: clean activity rows + H-AFF (rw_prep without the quiet scene: tr_quiet would send the goats' neighbours away), the hunt ground, the goats
  SI_REFACTIONED=""; SI_NPC_ID=""
  TRIP_QUIET=0 rw_prep || return $?
  si_scene_base || return $?
  si_goats pre || return $?
  return 0
}
si_job() {   # si_job run|nc  (26-d / 26-dx), the rw_job_resume legs on the hunt ground
  local mode="$1" accept rsay n0 n1
  echo Hunt > "$EV/kind.txt"; echo "$mode" > "$EV/mode.txt"
  si_start || return $?
  accept="${RW_ACCEPT:-$RW_ACCEPT_DEF}"; rsay="${RW_RESUME_SAY:-Are we still on that job?}"
  n0=$(rw_logn)
  si_offer act_s1.txt || return $?
  rw_has_status act_s1.txt proposed || { rw_log act_log_pre.txt "${n0:-0}"; return 0; }          # checker: SETUP-FAIL (no offer)
  si_wait_delivery "$SI_OFFER_STEP"
  rl_say 2 "$accept" || return $?
  rw_sleep "${RW_SAY_WAIT:-8}"
  if [ "$mode" = nc ]; then rl_say 2c "Cancel that." || return $?; rw_sleep 4; fi
  rw_act_dump act_pre.txt; rw_out_dump out_pre.txt; rw_log act_log_pre.txt "${n0:-0}"
  if [ "$mode" = run ]; then rw_has_status act_pre.txt accepted || return 0; fi                  # checker: SETUP-FAIL (accept did not land)
  tr_state state_pre.txt "$RL_NPC_FULL"
  rw_save_load job || return $?
  n1=$(rw_logn); si_goats post || return $?
  rl_say 3 "$rsay" || return $?
  rw_sleep "${RW_SAY_WAIT:-8}"
  rw_act_dump act_post.txt; rw_out_dump out_post.txt; rw_log act_log_post.txt "${n1:-0}"
  tr_state state_post.txt "$RL_NPC_FULL"
  if [ "$mode" = run ] && [ -n "${RW_COMPLETE:-}" ]; then
    lt_h <<EOT >> "$EV/complete.txt" 2>&1
stobe-auto speed 3 </dev/null >/dev/null
sleep ${RW_HUNT_WAIT:-180}
stobe-auto speed 0.5 </dev/null >/dev/null
EOT
    rw_act_dump act_final.txt; rw_out_dump out_final.txt
  fi
  return 0
}
rd_26d() { si_job run; }
rd_26dx() { si_job nc; }
rd_26e() {   # a PROPOSED Hunt across a save+load (re-bound in place, the NPC must propose again), on the hunt ground
  local n1 accept="${RW_ACCEPT:-$RW_ACCEPT_DEF}" offer="${RW_OFFER:-$RW_OFFER_DEF}"
  echo Hunt > "$EV/kind.txt"; echo offer > "$EV/mode.txt"
  si_start || return $?
  si_offer act_pre.txt || return $?
  rw_has_status act_pre.txt proposed || return 0                                                  # checker: SETUP-FAIL (no offer)
  rw_out_dump out_pre.txt
  rw_save_load offer || return $?
  n1=$(rw_logn); si_goats post || return $?
  rl_say 2 "$offer" || return $?                                                                 # resume turn + the NPC proposes again
  rw_sleep "${RW_SAY_WAIT:-8}"
  rw_act_dump act_post_s2.txt
  si_wait_delivery 2
  rl_say 3 "$accept" || return $?
  rw_sleep "${RW_SAY_WAIT:-8}"
  rw_act_dump act_post_s3.txt; rw_out_dump out_post.txt; rw_log act_log_post.txt "${n1:-0}"
  return 0
}
