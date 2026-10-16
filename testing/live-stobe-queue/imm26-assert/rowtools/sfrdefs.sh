#!/usr/bin/env bash
# sfrdefs.sh (imm26-sfR, 2026-10-16): recipe v2 for the three FAIL rows fxB classed as test defects: 23-b, 22-b, 20-a. Sourced by sfrrun.sh AFTER go-row.sh, reloaddefs_a.sh,
# reloaddefs_b.sh, unblockdefs_a.sh and tripdefs_sfk.sh. It REDEFINES rd_23b / rd_22b / rd_20a only inside that process; rowdefs.sh, tripdefs.sh, unblockdefs_c.sh, reloaddefs_sfj.sh and
# every checker a running operator uses are NOT edited. Verdicts: sfrcheck.py (23-b, 22-b) and unblockcheck_c.py -> rowcheck.py (20-a, unchanged) via sfrpy.sh. No assertion is weakened.
# Source of the diagnosis: agents/imm26-fxB.handoff.md rows 23-b, 22-b, 20-a.
#
# 23-b  (legacy FOLLOW expiry).  The expiry exists (FOLLOW_EXPIRED, [Settings] FollowExpiryGameHours default 24, DLL N1/NC16+, re-read every 10 s) but v1 advanced only ~9.9 game h.
#       v2: FollowExpiryGameHours=SR_23B_LIMIT_H (default 2) is written into the LANE's StobeCustom.ini (backup StobeCustom.ini.sfR.bak, restored byte-identical after the row, also on every
#       early exit), "Follow me.", then game time is advanced IN CHUNKS (rate measured, 2-60 s of speed 10 each; v1's fixed real-time advance gave 9.9 h per 120 s):
#         control : advance to SR_CTRL_FRAC (0.5) x limit -> the follow must still tick and NOT have expired (negative control: the expiry is the limit, not a spurious end)
#         test    : advance to limit + SR_23B_EXTRA_H (1) -> FOLLOW_EXPIRED for the follower with now-started >= limit, no FOLLOW_TICK after it.
#       SR_23B_NO_INI=1: the ini is not touched, limit = 24 h (default) and ~25 h are advanced (about 5 min at speed 10). The checker asserts game hours >= limit AND the expiry event.
# 22-b  (arrival remark, server half).  v1 teleported onto the Squin gate while the native order was live (kills it ~147 u short, sfK2) and then waited in silence (no snapshot is ever
#       pushed without a player turn).  v2: stage by REALLY WALKING to the agreement's own destination_point (sfk_gate + uf_walk_stage, as the sfK2 23-a recipe), then right after the
#       native arrival line: Shay onto the NPC, stobe_ctxpush and ONE targeted bored tick (i4_bored: ctxpush + stream.php optional=1 mode=autochat, people as Name|serial); a second
#       tick is only sent when the first produced no arrival claim (SR_22B_TICKS, default 2 attempts); then the SILENT tick (must say nothing and write no second claim).
#       PRODUCT FOLLOW-UP (not built here, later native package N1): push the NPC context snapshot at the terminal native travel phase (NativeTravelLifecycle completed/failed ->
#       PushImmediateContextSnapshot(npc,"travel_terminal",false), main.cpp:~4195) and widen the 120 game-s freshness for terminal receipts (commitment_native_bridge.php) or ingest in the
#       /context handler; until then a bored tick only sees the arrival if it follows a fresh ctxpush.
# 20-a  (deferred change confirm).  v1 left the native trip running and never re-placed anyone: dist_to_target 8 -> 81 -> 201 -> 326 u (5090-i3), 353-637 u (4080).  v2 (the sfJ 20-d fix
#       shape, per turn): protect + sheathe, SHAY is teleported onto the walking NPC (the NPC is not touched: moving her would end the native order), dist read back <= SR_20A_MAXDIST
#       (70) or SETUP-FAIL before the say; calm_<tag>.txt as unblockdefs_c.sh ub20_calm. The verdict is the unchanged chain unblockcheck_c.py -> rowcheck.py 20-a; sfrcheck.py only turns a
#       NOT-PASS into a SETUP-FAIL when a turn was sent with dist_to_target > 80 u (outside TalkRadius). The product bug fxB found (model answers NONE/PROPOSE on the confirm turn, pending
#       change never accepted) is NOT hidden: with the NPC in range a still-failing row stays FAIL.
# Env: SR_23B_LIMIT_H(2) SR_23B_NO_INI SR_23B_EXTRA_H(1) SR_CTRL_FRAC(0.5) SR_INI_SETTLE(12) SR_ADV_MAX(40 chunks) SR_RATE(0.08 h/s guess) SR_22B_TICKS(2) SR_22B_TICK_SPEED(unset)
#      SR_20A_MAXDIST(70) SFK_23A_BACK(400) SFK_23A_SPEED(1) SFK_23A_TRIES(30) SFK_KO_WAIT(25) TRIP_GATE TRIP_DEST TRIP_ALT.
SR_HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
declare -F rw_prep >/dev/null || . "$SR_HERE/reloaddefs_a.sh"
declare -F i4_bored >/dev/null || . "$SR_HERE/unblockdefs_a.sh"
declare -F sfk_gate >/dev/null || . "$SR_HERE/tripdefs_sfk.sh"

# ------------------------------------------------------------------ shared helpers
sr_calm() {   # Shay sheathed + held off, Shay and the NPC protected (Hub outlaws KO'd Shay mid-row in earlier runs)
  local n; n=$(rl_q "$RL_NPC_FULL")
  lt_h <<EOT >> "$EV/calm.txt" 2>&1
stobe-auto stobe_drawn hold Shay off </dev/null 2>&1 | head -1
stobe-auto stobe_drawn sheathe Shay </dev/null 2>&1 | head -1
stobe-auto protect Shay on </dev/null 2>&1 | head -1
stobe-auto protect $n on </dev/null 2>&1 | head -1
EOT
}
sr_calm_ev() {   # sr_calm_ev <tag>: identical to unblockdefs_c.sh ub20_calm (calm_<tag>.txt = Shay's state + characters within 120 u; read by unblockcheck_c.py 20-a)
  lt_h <<EOT > "$EV/calm_$1.txt" 2>&1
stobe-auto stobe_drawn hold Shay off </dev/null 2>&1 | head -1
stobe-auto stobe_drawn sheathe Shay </dev/null 2>&1 | head -1
echo "STATE \$(stobe-auto stobe_state Shay </dev/null 2>&1 | head -c 1500 | tr '\n' ' ')"
echo "CHARS \$(stobe-auto chars 120 </dev/null 2>&1 | head -c 700 | tr '\n' ' ')"
EOT
}

# ------------------------------------------------------------------ 23-b helpers: lane ini, chunked game-time advance, FOLLOW log slice
sr_ini_path() { printf '%s/StobeCustom.ini' "${LT_STOBELOG%/*}"; }   # the DLL reads Stobe.ini then StobeCustom.ini (custom wins) from <game>/mods/Stobe/
sr_ini_set() {   # sr_ini_set <hours>: backup + set [Settings] FollowExpiryGameHours (CRLF-safe). Evidence ini_set.txt. rc 3 + RL_REASON when the key did not stick
  local f h="$1"; f=$(sr_ini_path)
  lt_h <<EOT > "$EV/ini_set.txt" 2>&1
# sr:iniset h=$h
F='$f'
if [ ! -f "\$F" ]; then echo "NO-INI \$F"
else
  if [ -f "\$F.sfR.bak" ]; then cp -p "\$F.sfR.bak" "\$F" && echo "leftover backup restored first"; fi
  cp -p "\$F" "\$F.sfR.bak"
  if grep -aqi '^FollowExpiryGameHours=' "\$F"; then
    echo "was: \$(grep -ai '^FollowExpiryGameHours=' "\$F" | head -1 | tr -d '\r')"
    sed -i -E 's/^(FollowExpiryGameHours=)[0-9]*(.*)\$/\1$h\2/I' "\$F"
  else
    echo "was: (unset, default 24)"
    CR=\$(printf '\r'); if grep -aq "\$CR" "\$F"; then NL='\r\n'; else NL='\n'; fi
    sed -i -E "0,/^\[Settings\]/ s//[Settings]\$NL""FollowExpiryGameHours=$h/" "\$F"
  fi
  echo "now: \$(grep -ai '^FollowExpiryGameHours=' "\$F" | head -1 | tr -d '\r')"
fi
EOT
  if grep -qi "^now: FollowExpiryGameHours=$h\$" "$EV/ini_set.txt" 2>/dev/null; then return 0; fi
  RL_REASON="could not set FollowExpiryGameHours=$h in $f (ini_set.txt: $(tail -1 "$EV/ini_set.txt" 2>/dev/null | cut -c1-120)); needs: recipe (lane ini path / [Settings] section) or SR_23B_NO_INI=1 (advance 25 h)"
  return 3
}
sr_ini_restore() {   # always safe to call: restores the byte-identical ini from StobeCustom.ini.sfR.bak
  local f; f=$(sr_ini_path)
  lt_h <<EOT >> "$EV/ini_restore.txt" 2>&1
# sr:inirestore
F='$f'
if [ -f "\$F.sfR.bak" ]; then cp -p "\$F.sfR.bak" "\$F" && rm -f "\$F.sfR.bak" && echo "restored; key now: [\$(grep -ai '^FollowExpiryGameHours=' "\$F" | head -1 | tr -d '\r')] (empty = unset)"; else echo "no-backup (nothing to restore)"; fi
EOT
}
sr_advance_to() {   # sr_advance_to <delta hours since SR_T0>: speed 10 in measured chunks; sets SR_CUR (game hours) and SR_DELTA; rc 3 + RL_REASON when the target is not reached
  local want="$1" cur d rate="${SR_RATE:-0.08}" secs k pc="" ps="" nr
  for k in $(seq 1 "${SR_ADV_MAX:-40}"); do
    cur=$(rl_gametime); [ -n "$cur" ] || { RL_REASON="cannot read game time (stobe-auto time returned no number)"; return 3; }
    if [ -n "$pc" ]; then   # measured game hours per real second of the last chunk
      nr=$(awk -v c="$cur" -v p="$pc" -v s="$ps" 'BEGIN{printf "%.5f", (c-p)/s}')
      awk -v r="$nr" 'BEGIN{exit !(r+0>0.005)}' && rate="$nr"
    fi
    d=$(awk -v c="$cur" -v t0="$SR_T0" 'BEGIN{printf "%.4f", c-t0}'); SR_CUR="$cur"; SR_DELTA="$d"
    echo "chunk=$k game_hours=$cur delta=$d want=$want rate=$rate" >> "$EV/advance.txt"
    if awk -v d="$d" -v w="$want" 'BEGIN{exit !(d+0>=w+0)}'; then return 0; fi
    secs=$(awk -v d="$d" -v w="$want" -v r="$rate" 'BEGIN{s=(w-d)/r*0.9; if(s<2)s=2; if(s>60)s=60; printf "%d", s+0.5}')
    pc="$cur"; ps="$secs"
    lt_h <<EOT >> "$EV/advance.txt" 2>&1
stobe-auto speed 10 </dev/null | head -1
sleep $secs
stobe-auto speed 0.5 </dev/null | head -1
EOT
  done
  RL_REASON="game time did not reach +${want} h after ${SR_ADV_MAX:-40} chunks (delta ${SR_DELTA:-?} h, advance.txt); needs: recipe (raise SR_ADV_MAX) or lane (game paused / speed command ignored)"
  return 3
}
sr_follow_log() {   # sr_follow_log <file> <stobe.log line mark>: FOLLOW lines since the mark WITHOUT the (very many) FOLLOW_TICK lines, tick count + last 2 ticks, ticks after this follower's expiry
  local ser="${RL_NPC_ID#\#}"; ser="${ser%%/*}"
  lt_h <<EOT > "$EV/$1" 2>&1
# sr:follow
tail -n +$(( $2 + 1 )) $LT_STOBELOG | grep -a 'FOLLOW' > /tmp/sr-follow.\$\$
grep -a -v 'FOLLOW_TICK' /tmp/sr-follow.\$\$ | cut -c1-300 | head -60
echo "# ticks=\$(grep -a -c 'FOLLOW_TICK' /tmp/sr-follow.\$\$)"
grep -a 'FOLLOW_TICK' /tmp/sr-follow.\$\$ | tail -2 | cut -c1-300
awk -v s="$ser" '/FOLLOW_EXPIRED: follower=/{ if (index(\$0, "follower=" s " ") || index(\$0, "follower=" s) ) e=1 } e && /FOLLOW_TICK: follower=/{ if (index(\$0, "follower=" s)) k++ } END{print "# ticks_after_expiry=" k+0}' /tmp/sr-follow.\$\$
rm -f /tmp/sr-follow.\$\$
EOT
}

rd_23b() {   # H-AFF 60; "Follow me."; control advance (< limit: no expiry); advance past the limit: FOLLOW_EXPIRED
  local lim="${SR_23B_LIMIT_H:-2}" viaini=1 rc=0
  [ -n "${SR_23B_NO_INI:-}" ] && { viaini=0; lim=24; }
  tr_prep || return $?
  ROW_NATIVE=1; rd_need_npc || return 3; rd_aff 60
  echo "$lim" > "$EV/limit_hours.txt"; echo "ini=$viaini" > "$EV/limit_mode.txt"
  if [ "$viaini" = 1 ]; then
    sr_ini_set "$lim" || { local r="$RL_REASON"; sr_ini_restore; RL_REASON="$r"; return 3; }
    rw_sleep "${SR_INI_SETTLE:-12}"   # the DLL re-reads the ini at most every 10 s
  fi
  sr_23b_body "$lim"; rc=$?
  [ "$viaini" = 1 ] && sr_ini_restore
  return $rc
}
sr_23b_body() {   # sr_23b_body <limit h>
  local lim="$1" l t0 mid fin
  sr_calm
  rl_say 1 "Follow me." || return $?
  l=$(sed -nE 's/^mark=[0-9]+ [0-9]+ ([0-9]+) .*/\1/p' "$EV/s1/meta.txt" | head -1); l=${l:-0}
  echo "$RL_NPC_ID" > "$EV/follow_npc.txt"
  sr_follow_log follow_log.txt "$l"
  grep -q 'FOLLOW target resolved' "$EV/follow_log.txt" || return 0      # checker: SETUP-FAIL (follow never started)
  t0=$(rl_gametime); [ -n "$t0" ] || { RL_REASON="cannot read game time (stobe-auto time returned no number)"; return 3; }
  echo "$t0" > "$EV/time0.txt"; SR_T0="$t0"
  mid=$(awk -v l="$lim" -v f="${SR_CTRL_FRAC:-0.5}" 'BEGIN{printf "%.3f", l*f}')
  sr_advance_to "$mid" || return $?
  echo "$SR_CUR" > "$EV/time_mid.txt"
  rw_sleep 4
  sr_follow_log follow_log_mid.txt "$l"
  fin=$(awk -v l="$lim" -v x="${SR_23B_EXTRA_H:-1}" 'BEGIN{printf "%.3f", l+x}')
  sr_advance_to "$fin" || return $?
  echo "$SR_CUR" > "$EV/time1.txt"
  rw_sleep 8
  sr_follow_log follow_log_after.txt "$l"
  tr_state state_after.txt "$RL_NPC_FULL"
}

# ------------------------------------------------------------------ 22-b
sr_sit_dump() {   # sr_sit_dump <file>: situated_event / situated_remark_claim / travel_agreement rows since mark_rowid.txt
  local m; m=$(head -1 "$EV/mark_rowid.txt" 2>/dev/null | tr -dc 0-9); m=${m:-0}
  lt_sql "select rowid||'|'||type||'|'||left(data,500) from eventlog where rowid>$m and type in ('situated_event','situated_remark_claim','travel_agreement') order by rowid -- sr:sit" > "$EV/$1" 2>&1
}
sr_claims() { grep -c '|situated_remark_claim|' "$EV/$1" 2>/dev/null | head -1; }
rd_22b() {   # situated arrival: REAL walk to the agreement's own destination_point, ctxpush + targeted bored tick(s) right after the native arrival, then one silent tick
  tr_prep || return $?
  tr_trip_setup || return $?
  local n g k c rc tk="${SR_22B_TICKS:-2}" claimed=0 h
  n=$(rl_q "$RL_NPC_FULL"); g=$(sfk_gate)
  [ -n "$g" ] || { RL_REASON="no gate coordinates for '$TR_DEST' (set TRIP_GATE='x y z')"; return 3; }
  echo "$g" > "$EV/gate.txt"
  lt_sql "select coalesce(max(rowid),0) from eventlog" | head -1 | tr -dc 0-9 > "$EV/mark_rowid.txt"
  sr_calm
  UF_N0=$(echo "wc -l < $LT_STOBELOG" | lt_h | tail -1 | tr -dc 0-9); UF_N0=${UF_N0:-0}
  uf_walk_stage "$n" "$g" "${SFK_23A_BACK:-400}" 0 150 "${SFK_23A_SPEED:-1}" "${SFK_23A_TRIES:-30}"
  uf_native_dump native_travel.txt
  printf 'end=%s gate=%s last_progress=%s\n' "$UB_WALK_END" "$g" "$(tail -1 "$EV/walk_progress.txt" 2>/dev/null)" > "$EV/arrival.txt"
  case "$UB_WALK_END" in
    TIMEOUT) RL_REASON="no native arrival within ${SFK_23A_TRIES:-30} walk cycles (walk_progress.txt: $(tail -1 "$EV/walk_progress.txt" 2>/dev/null | cut -c1-120)); needs: recipe (raise SFK_23A_TRIES / lower SFK_23A_BACK) or native (no NATIVE_TRAVEL line = old DLL)"; return 3;;
    FAILED)  RL_REASON="the trip ended FAILED before any arrival (native_travel.txt, agr_final); an arrival remark is untestable; needs: recipe (other gate / TRIP_DEST)"; tr_agr agr_final.txt 8; return 3;;
  esac
  lt_h <<EOT >> "$EV/walk.txt" 2>&1
stobe-auto teleport Shay $n </dev/null | head -1 | cut -c1-120
EOT
  sfk_shay_guard || return 3
  tr_state state_shay.txt Shay
  [ -z "${SR_22B_TICK_SPEED:-}" ] || echo "stobe-auto speed ${SR_22B_TICK_SPEED} </dev/null | head -1" | lt_h >> "$EV/walk.txt" 2>&1
  : > "$EV/sr_ticks.txt"; U_BORED_SERIALS=1
  for k in $(seq 1 "$tk"); do
    i4_bored "tick$k" 1 || { rc=$?; U_BORED_SERIALS=0; return $rc; }
    rw_sleep 2; sr_sit_dump "sit_after$k.txt"; c=$(sr_claims "sit_after$k.txt"); h=$(rl_gametime)
    echo "tick$k|res=$U_BORED_RES|claims=${c:-0}|game_hours=${h:-?}" >> "$EV/sr_ticks.txt"
    [ "${c:-0}" -ge 1 ] && { claimed=1; break; }
  done
  i4_bored tick_silent 1 || { rc=$?; U_BORED_SERIALS=0; return $rc; }   # the silent tick: nothing left to claim (one-shot event, per-NPC spacing)
  U_BORED_SERIALS=0
  rw_sleep 2; sr_sit_dump sit_after_silent.txt; c=$(sr_claims sit_after_silent.txt); h=$(rl_gametime)
  echo "tick_silent|res=$U_BORED_RES|claims=${c:-0}|game_hours=${h:-?}" >> "$EV/sr_ticks.txt"
  echo "claimed_before_silent=$claimed ticks_sent=$k" > "$EV/sr_summary.txt"
  [ -z "${SR_22B_TICK_SPEED:-}" ] || echo 'stobe-auto speed 0.5 </dev/null | head -1' | lt_h >> "$EV/walk.txt" 2>&1
  tr_agr agr_final.txt 8
}

# ------------------------------------------------------------------ 20-a
sr_turn_ready() {   # sr_turn_ready <tag>: Shay onto the (walking) NPC, dist read back <= SR_20A_MAXDIST, else rc 3 BEFORE the say. Evidence place.txt, place_dist.txt
  local tag="$1" n d k max="${SR_20A_MAXDIST:-70}"
  RL_NPC_ID=""; rd_need_npc || return 3
  n=$(rl_q "$RL_NPC_FULL")
  for k in 1 2 3; do
    lt_h <<EOT >> "$EV/place.txt" 2>&1
stobe-auto protect Shay on </dev/null | head -1
stobe-auto protect $n on </dev/null | head -1
stobe-auto teleport Shay $n </dev/null | head -1 | cut -c1-120
EOT
    rw_sleep 1
    RL_NPC_ID=""; rd_need_npc || return 3; d="${RL_DIST:-?}"
    echo "$tag try=$k dist=$d" >> "$EV/place.txt"
    if [ "$d" != "?" ] && awk -v d="$d" -v m="$max" 'BEGIN{exit !(d+0<=m+0)}'; then echo "$tag|$d" >> "$EV/place_dist.txt"; return 0; fi
  done
  RL_REASON="could not bring Shay within ${max} u of ${RL_NPC_FULL} before $tag (place.txt: last dist=$d); needs: recipe (the NPC keeps walking away) or a calmer scene"
  return 3
}
rd_20a() {   # ACCEPTED trip; change request must not move the row; two confirm turns; Shay placed on the NPC and sheathed before EVERY turn
  tr_prep || return $?
  sr_calm
  sr_calm_ev pre; tr_trip_setup || return $?
  echo "$TR_ALT" > "$EV/alt.txt"
  local core="${TR_ALT#the }"
  sr_turn_ready s3 || return $?; sr_calm_ev s3; rl_say 3 "Actually, go to $TR_ALT instead." || return $?
  sr_turn_ready s4 || return $?; sr_calm_ev s4; rl_say 4 "Yes, I mean it. I am sure, change it to $TR_ALT." || return $?
  grep -qE '"status":"(ENDED|CANCELLED)"' "$EV/s4/ev_full.txt" 2>/dev/null || grep -qiE "\"destination\":\"[^\"]*$core" "$EV/s4/ev_full.txt" 2>/dev/null \
    || { sr_turn_ready s4b || return $?; sr_calm_ev s4b; rl_say 4b "Yes. Take me to $TR_ALT." || return $?; }
  tr_agr agr_final.txt 8
}
