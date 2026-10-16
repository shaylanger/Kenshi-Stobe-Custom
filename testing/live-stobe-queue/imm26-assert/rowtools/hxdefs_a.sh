#!/usr/bin/env bash
# hxdefs_a.sh: hardening rows, family A (imm26-hxA): 01-bx 01-cx 02-cx.  Sourced by hxrun.sh AFTER hxdefs.sh (reuses hxd_* / hx17_ids / hx02_profile); hxdefs.sh itself
# is not edited.  Verdict: hxcheck_a.py (assert_stance 01-bx / 01-cx once per save, assert_principle 02-cx once).  Bundles (flat sample dirs, rl_bundle files + utterance.txt
# + effects_full.txt = `select * from social_effect order by 1 desc limit 12`, never left(detail,200)) go to $HXD = $HX_OUT/<ROW> or $EV.
#   01-bx  savA/{T1-3,CN1-3,CP1-3} savB/{...}: T = H-AFF -80 + SEED, CN = H-AFF -80 no seed, CP = H-AFF +60 + SEED; the base save is RELOADED before every sample;
#          savX/seed.txt = the 3 seed lines joined by `|`; every sample dir has haff.txt (`aff=<n>` read after the set).  Save A = --save, save B = --save2 (default A again).
#   01-cx  savA/{H1-3,A1-3} savB/{...}: H = stranger of a hostile faction (faction_relation_state faction->player faction <= -50), A = stranger of an allied faction
#          (relation >= 50, < 100).  Strangers are picked from `chars` (no Shay relationship entry, distinct profile factions) or named by HX01C_H / HX01C_A; the relation
#          rows are SET on the private DB when they are not already in band (faction_rel_set.txt before/after); faction_rel.txt `rel=<n>` per dir; both checked out of combat.
#   02-cx  C1-3 (Cind after save+reload) O1-3 (unrelated NPC after reload); principle_rows_pre.txt principle_rows.txt profile_md5_before/after.txt info_panel.txt per C dir.
#          Two fresh lineages: lineage 1 (base --save) -> C1 C2 O1, lineage 2 (--save2, default the same) -> C3 O2 O3; each = principle reset + set in the profile, the 02-b
#          request derives the stored row, `stobe-auto save kah-imm26-hx-02c-<n>` + load (new session), then the 02-a question variants.  Profile text restored at the end.
# Env knobs: HX01C_H HX01C_A (stranger names) HX01C_RADIUS (3000) HX01C_REL_H (-100) HX01C_REL_A (70) HX01C_PF (player faction name, default read from core_npc 'Shay', else Nameless)
#   HX02C_CTL ("Karnic Liplom" candidates) HX02C_PRIN (slavery) HX02C_TEXT (profile sentence) HX02C_SAVE (kah-imm26-hx-02c: save-name prefix) HX02C_PANEL_TRIES (4)
HXA_ROWS="01-bx 01-cx 02-cx"

# ------------------------------------------------------------------ shared
hxa_sq() { printf '%s' "${1//\'/\'\'}"; }   # SQL string literal body
hxa_start() {  # hxa_start <save> : load (hxrun.sh preloaded the first one), quiet scene, clean leftovers
  hxd_load "$1" || return $?; hxd_scene || return $?; hxd_dbclean
}

# ------------------------------------------------------------------ 01-bx : refusal at -80 is caused by affinity, not by history
HXA_SEED=("Sure, a walk sounds good." "Fine, lead the way." "Count me in.")
hxa01_seedrows() {  # hxa01_seedrows <mark> : the 3 cooperative Cind chat rows (spoken, visible, fresh ts) copied from the newest Cind+Shay row at or below the mark
  local line r ids=""
  hx17_ids
  for line in "${HXA_SEED[@]}"; do
    r=$(lt_sql "insert into eventlog(type,data,sess,gamets,localts,ts,people,location,geo,utterance_id,delivery_state) select 'chat','$RL_NPC_FULL: $line (talking to: Shay)',sess,(select max(gamets) from eventlog),(select max(localts) from eventlog),(select max(ts) from eventlog),people,location,geo,'','spoken' from eventlog where rowid<=$1 and people like '%hand_${H17_NPC_SER}%' and people like '%hand_${H17_SHAY_SER}%' order by rowid desc limit 1 returning rowid" 2>&1 | head -1)
    ids="$ids ${r:-none}"
  done
  echo "$ids"
}
hxa01_sample() {  # hxa01_sample <savdir> <label> <aff> <seed yes|no> "<utterance>" <save> : reload, set H-AFF, (seed), say
  local sv="$1" lab="$2" aff="$3" seed="$4" text="$5" save="$6" d="$HXD/$1/$2" an ids
  hxa_start "$save" || return $?
  hxd_trim "$HXA_M0"; mkdir -p "$d"
  hxd_haff "$d" set "$RL_NPC_FULL" "$aff" platonic
  hxd_haff "$d" read "$RL_NPC_FULL" "" read
  an=$(hxd_affnum "$d/haff-read.txt")
  hxd_dry && an="${an:-$aff}"
  [ -n "$an" ] || { RL_REASON="H-AFF read gave no aff for $RL_NPC_FULL in $sv/$lab (see $d/haff-read.txt)"; return 3; }
  { echo "aff=$an"; cat "$d/haff-set.txt" "$d/haff-read.txt"; } > "$d/haff.txt"
  if [ "$seed" = yes ]; then
    ids=$(hxa01_seedrows "$HXA_M0"); echo "$ids" > "$d/seed_rowids.txt"
    hxd_dry || ! echo "$ids" | grep -q none || { RL_REASON="seed rows not inserted in $sv/$lab (no Cind+Shay row at or below mark $HXA_M0): $ids"; return 3; }
  fi
  hxd_sample "$sv/$lab" "$text" || return $?
}
rd_01bx() {
  hxd_begin; rd_need_npc || return 3
  local sv savename save i tpl t
  local -a us=("I was thinking we might do something together." "Fancy travelling somewhere with me today?" "Come on, let's head out together, same as before.")
  local seedj
  seedj=$(printf '%s|' "${HXA_SEED[@]}"); seedj="${seedj%|}"
  # one-time: the eventlog needs one Cind+Shay row to copy people/location/geo from (a plain greeting makes one); the mark is taken after it
  hxa_start "$HX_SAVE" || return $?; hx17_ids
  tpl=$(lt_sql "select count(*) from eventlog where people like '%hand_${H17_NPC_SER}%' and people like '%hand_${H17_SHAY_SER}%'" | head -1 | tr -dc 0-9)
  if [ "${tpl:-0}" = 0 ]; then hxd_sample warm "Hello." >/dev/null || return $?; echo "warm-up greeting row made" >> "$EV/phases.txt"; fi
  HXA_M0=$(hxd_rowid); echo "mark=$HXA_M0 tpl_rows=${tpl:-0}" >> "$EV/phases.txt"
  for sv in A B; do
    savename="sav$sv"; save="$HX_SAVE"; [ "$sv" = B ] && save="$HX_SAVE2"
    mkdir -p "$HXD/$savename"; echo "$seedj" > "$HXD/$savename/seed.txt"; echo "$save" > "$HXD/$savename/save.txt"
    i=0; for t in "${us[@]}"; do i=$((i+1)); hxa01_sample "$savename" "T$i" -80 yes "$t" "$save" || return $?; done
    i=0; for t in "${us[@]}"; do i=$((i+1)); hxa01_sample "$savename" "CN$i" -80 no "$t" "$save" || return $?; done
    i=0; for t in "${us[@]}"; do i=$((i+1)); hxa01_sample "$savename" "CP$i" 60 yes "$t" "$save" || return $?; done
  done
  hxd_trim "$HXA_M0"
}

# ------------------------------------------------------------------ 01-cx : first contact with a hostile-faction stranger vs an allied-faction stranger
hxa_facname() {  # hxa_facname <npc full> : the faction NAME of the profile (core_npc.faction without its [id] suffix), as the server's lookup reads it
  lt_sql "select trim(regexp_replace(coalesce(faction,''), '[[:space:]]*[[]+[^]]*[]]+[[:space:]]*\$', '')) from core_npc where name='$(hxa_sq "$1")' limit 1" | head -1 | tr -d '\r'
}
hxa_rel() {  # hxa_rel <source faction> <target faction> : directed relation the server finds by names (newest row), empty when none
  lt_sql "select relation from faction_relation_state where lower(source_name)=lower('$(hxa_sq "$1")') and lower(target_name)=lower('$(hxa_sq "$2")') order by game_ts desc, updated_at desc, id desc limit 1" | head -1 | tr -d '\r'
}
hxa_relset() {  # hxa_relset <source> <target> <value> : UPDATE every matching row; INSERT one (merge_key name:s->name:t) when none exists
  local s t; s=$(hxa_sq "$1"); t=$(hxa_sq "$2")
  lt_sqlx "update faction_relation_state set relation=$3, updated_at=now() where lower(source_name)=lower('$s') and lower(target_name)=lower('$t'); insert into faction_relation_state(merge_key,source_name,target_name,relation) select 'name:'||lower('$s')||'->name:'||lower('$t'),'$s','$t',$3 where not exists (select 1 from faction_relation_state where lower(source_name)=lower('$s') and lower(target_name)=lower('$t')) on conflict (merge_key) do update set relation=excluded.relation, updated_at=now()" >> "$EV/relset.txt" 2>&1
}
hxa01c_band() {  # hxa01c_band <H|A> <value> : rc 0 when the value is in the row's band (H <= -50, A 50..99)
  awk -v k="$1" -v v="$2" 'BEGIN{ if (v=="") exit 1; if (k=="H") exit !(v+0<=-50); exit !(v+0>=50 && v+0<100) }'
}
hxa01c_ensure() {  # hxa01c_ensure <H|A> <faction> : make the directed relation faction->player faction land in band (record before/after); echoes the value
  local k="$1" f="$2" pf="$HXA_PF" before after want
  before=$(hxa_rel "$f" "$pf"); want="${HX01C_REL_H:--100}"; [ "$k" = A ] && want="${HX01C_REL_A:-70}"
  if hxd_dry || hxa01c_band "$k" "$before"; then echo "$k $f -> $pf: kept ${before:-dry}" >> "$EV/faction_rel_set.txt"; echo "${before:-0}"; return 0; fi
  hxa_relset "$f" "$pf" "$want"; after=$(hxa_rel "$f" "$pf")
  echo "$k $f -> $pf: before=${before:-none} set=$want after=${after:-none}" >> "$EV/faction_rel_set.txt"
  echo "$after"
}
hxa01c_names() {  # hxa01c_names <radius> : character names (no id/faction) within the radius of Shay, one per line
  printf 'stobe-auto chars %s </dev/null 2>&1 | sed "s/ | /\\n/g" | grep -E "#[0-9]+/[0-9]+" | sed -E "s/^[0-9]+ within [0-9.]+: //; s/ #[0-9]+\\/[0-9]+.*//" | sort -u\n' "$1" | lt_h
}
hxa01c_pick() {  # sets HXA_H / HXA_A (full names): HX01C_H / HX01C_A, else the first two strangers (no Shay relationship entry, profile faction known, distinct factions) from `chars`
  local names n fac hf="" ro cnt=0 sk
  if [ -n "${HX01C_H:-}" ] && [ -n "${HX01C_A:-}" ]; then HXA_H="$HX01C_H"; HXA_A="$HX01C_A"; return 0; fi
  names=$(hxa01c_names "${HX01C_RADIUS:-3000}" 2>&1)
  echo "$names" > "$EV/chars_candidates.txt"
  hxd_dry && names="${names:-Dry One [Hungry Bandit]
Dry Two [Hungry Bandit]}"
  sk="Shay|Cind|Malzin"
  HXA_H="${HX01C_H:-}"; HXA_A="${HX01C_A:-}"
  while IFS= read -r n <&3; do
    [ -n "$n" ] || continue; echo "$n" | grep -qE "^($sk)( |\$)" && continue
    cnt=$((cnt+1)); [ $cnt -le 16 ] || break
    [ -n "$HXA_H" ] && [ -n "$HXA_A" ] && break
    fac=$(hxa_facname "$n"); [ -n "$fac" ] || { hxd_dry && fac="F$cnt" || continue; }
    hxd_haff "$EV/pick" "$cnt" "$n" "" read
    ro=$(grep -v '^$' "$EV/pick/haff-$cnt.txt" 2>/dev/null | tail -1 | sed 's/.*"after"://')
    echo "$ro" | grep -q '"Shay"' && { echo "skip $n: has a Shay relationship entry" >> "$EV/pick.txt"; continue; }
    if [ -z "$HXA_H" ] && [ "$n" != "$HXA_A" ]; then HXA_H="$n"; hf="$fac"; echo "H candidate $n ($fac)" >> "$EV/pick.txt"
    elif [ -z "$HXA_A" ] && [ "$(echo "$fac" | tr A-Z a-z)" != "$(echo "$hf" | tr A-Z a-z)" ]; then HXA_A="$n"; echo "A candidate $n ($fac)" >> "$EV/pick.txt"; fi
  done 3<<<"$names"
  [ -n "$HXA_H" ] && [ -n "$HXA_A" ] || { RL_REASON="no stranger pair found within ${HX01C_RADIUS:-3000} u (candidates: $(echo "$names" | head -5 | tr '\n' ';')): name them with --h/--a style env HX01C_H / HX01C_A"; return 3; }
}
hxa01c_calm() {  # hxa01c_calm <npc full> : rc 3 when stobe_state says the listener is in combat (the earlier run's confound)
  local js; js=$(printf 'stobe-auto stobe_state %s </dev/null 2>&1 | head -c 6000\n' "$(rl_q "$1")" | lt_h 2>&1)
  echo "$js" | grep -qE '"in_combat": ?true' && { RL_REASON="$1 is in combat (confound; the row needs both listeners calm)"; return 3; }
  return 0
}
hxa01c_sample() {  # hxa01c_sample <savdir> <label> <npc full> <faction> <H|A> "<text>"
  local sv="$1" lab="$2" npc="$3" fac="$4" k="$5" text="$6" d="$HXD/$1/$2" rel other aff
  mkdir -p "$d"
  rel=$(hxa01c_ensure "$k" "$fac"); hxd_dry && rel="${rel:-0}"
  hxa01c_band "$k" "$rel" || hxd_dry || { RL_REASON="faction relation $fac -> $HXA_PF is '$rel' after the set, not in the $k band (faction_rel_set.txt)"; return 3; }
  { echo "rel=$rel"; echo "listener_faction=$fac player_faction=$HXA_PF"; } > "$d/faction_rel.txt"
  hxd_haff "$d" stranger "$npc" "" read; aff=$(hxd_affnum "$d/haff-stranger.txt")
  awk -v a="${aff:-0}" 'BEGIN{exit !(a+0>5 || a+0<-5)}' && { RL_REASON="$npc has a personal relationship with Shay (aff=$aff): not a stranger (see $d/haff-stranger.txt); name another with HX01C_H / HX01C_A"; return 3; }
  other="$HXA_A"; [ "$k" = A ] && other="$HXA_H"
  printf 'stobe-auto teleport %s Shay </dev/null | head -1\nstobe-auto teleport %s %s </dev/null | head -1\n' "$(rl_q "$npc")" "$(rl_q "$other")" "$HX_FAR" | lt_h >> "$EV/place.txt" 2>&1
  hxd_dry || hxa01c_calm "$npc" || return $?
  hxd_sample "$sv/$lab" "$text" "$npc" || return $?
  hxd_state "$sv/$lab" none
  hxd_trim "$HXA_M0"
}
rd_01cx() {
  hxd_begin; rd_need_npc || return 3
  local sv savename save i t hfac afac
  local -a gs=("Hello there." "Good day to you." "Who are you people?")
  HXA_PF="${HX01C_PF:-}"
  hxa_start "$HX_SAVE" || return $?; HXA_M0=$(hxd_rowid)
  [ -n "$HXA_PF" ] || HXA_PF=$(hxa_facname Shay); HXA_PF="${HXA_PF:-Nameless}"; echo "player_faction=$HXA_PF" >> "$EV/phases.txt"
  hxa01c_pick || return $?
  hfac=$(hxa_facname "$HXA_H"); afac=$(hxa_facname "$HXA_A")
  hxd_dry && { hfac="${hfac:-HostileDry}"; afac="${afac:-AlliedDry}"; }
  [ -n "$hfac" ] && [ -n "$afac" ] || { RL_REASON="no profile faction for the strangers (H '$HXA_H'=$hfac, A '$HXA_A'=$afac): core_npc.faction is empty"; return 3; }
  [ "$(echo "$hfac" | tr A-Z a-z)" != "$(echo "$afac" | tr A-Z a-z)" ] || { RL_REASON="H '$HXA_H' and A '$HXA_A' share the faction '$hfac': pick strangers of different factions"; return 3; }
  echo "H=$HXA_H ($hfac) A=$HXA_A ($afac)" | tee -a "$EV/phases.txt" > "$HXD/strangers.txt"
  for sv in A B; do
    savename="sav$sv"; save="$HX_SAVE"; [ "$sv" = B ] && save="$HX_SAVE2"
    mkdir -p "$HXD/$savename"; echo "$save" > "$HXD/$savename/save.txt"
    [ "$sv" = A ] || { hxa_start "$save" || return $?; hxd_trim "$HXA_M0"; }
    i=0; for t in "${gs[@]}"; do i=$((i+1)); hxa01c_sample "$savename" "H$i" "$HXA_H" "$hfac" H "$t" || return $?; done
    i=0; for t in "${gs[@]}"; do i=$((i+1)); hxa01c_sample "$savename" "A$i" "$HXA_A" "$afac" A "$t" || return $?; done
  done
  hxd_trim "$HXA_M0"
}

# ------------------------------------------------------------------ 02-cx : the stored principle survives save + reload + new session (profile-text source, explicit caveat)
HXA_PRIN_DEF=" Firmly and openly opposed to slavery; will never take captives or put shackles on anyone"
hxa02_prin_on() {  # hxa02_prin_on <npc> : append the principle sentence to personality (master + live row), once
  local n t; n=$(hxa_sq "$1"); t=$(hxa_sq "${HX02C_TEXT:-$HXA_PRIN_DEF}")
  lt_sqlx "update core_npc_master set personality=personality||'$t' where name='$n' and personality not like '%$(hxa_sq "${HX02C_PRIN:-slavery}")%'; update core_npc set personality=personality||'$t' where name='$n' and personality not like '%$(hxa_sq "${HX02C_PRIN:-slavery}")%'" >> "$EV/profile_set.txt" 2>&1
}
hxa02_prin_off() {  # hxa02_prin_off <npc> : remove the sentence again (replace), so 02-ax / 02-bx runs start from the original profile
  local n t; n=$(hxa_sq "$1"); t=$(hxa_sq "${HX02C_TEXT:-$HXA_PRIN_DEF}")
  lt_sqlx "update core_npc_master set personality=replace(personality,'$t','') where name='$n'; update core_npc set personality=replace(personality,'$t','') where name='$n'" >> "$EV/profile_set.txt" 2>&1
}
hxa02_rows() {  # hxa02_rows <npc> <file> [full-file] : compact principle rows (npc|topic|stance|strength|source) the assert compares; the full rows to <full-file>
  lt_sql "select npc_name,topic,stance,strength,source from imm26_npc_principle where npc_name='$(hxa_sq "$1")' order by topic,stance" > "$2" 2>&1
  [ -z "${3:-}" ] || lt_sql "select * from imm26_npc_principle where npc_name='$(hxa_sq "$1")' order by id" > "$3" 2>&1
}
hxa02_md5() {  # hxa02_md5 <npc> <outfile> : md5 of the profile text (hx02_profile) -> <outfile>
  local t="$2.src"; hx02_profile "$1" "$t"
  md5sum < "$t" | cut -d' ' -f1 > "$2"
}
hxa02_panel() {  # hxa02_panel <dir> <npc> : NPC info panel text for the speaker Shay (open, wait for the bio, read; refreshed up to HX02C_PANEL_TRIES x 8 s until it names the principle)
  local d="$1" f="$1/info_panel.txt" k pr="${HX02C_PRIN:-slavery}"
  : > "$f"; : > "$d/info_panel_calls.txt"
  printf 'stobe-auto stobe_npcinfo open %s Shay </dev/null 2>&1 | head -2\n' "$(rl_q "$2")" | lt_h >> "$d/info_panel_calls.txt" 2>&1
  for k in $(seq 1 "${HX02C_PANEL_TRIES:-4}"); do
    hxd_sleep 8
    printf 'stobe-auto stobe_npcinfo refresh </dev/null 2>&1 | head -1\nsleep 4\nstobe-auto stobe_npcinfo read </dev/null 2>&1 | head -c 8000\n' | lt_h > "$f" 2>&1
    grep -qi "$pr" "$f" && break
  done
  echo 'stobe-auto stobe_npcinfo close </dev/null 2>&1 | head -1' | lt_h >> "$d/info_panel_calls.txt" 2>&1
  hxd_dry || ! grep -qiE '^ERROR|unknown command|unknown handler|not supported|no such command' "$f" || grep -qi "$pr" "$f" || { RL_REASON="stobe_npcinfo failed on $LT_LANE (see $f / info_panel_calls.txt): $(head -c 160 "$f")"; return 3; }
}
hxa02_lineage() {  # hxa02_lineage <n> <base save> <C labels...> -- <O labels...> : one lineage = reset+set principle, derive, save, load, questions
  local ln="$1" base="$2" npc ctl cn lab q i svn pre d; shift 2
  local -a cl=() ol=(); local seen=""
  for lab in "$@"; do if [ "$lab" = -- ]; then seen=1; elif [ -z "$seen" ]; then cl+=("$lab"); else ol+=("$lab"); fi; done
  local -a qs=("Is there anything you feel strongly about that you would rather not compromise on?" "What is the one thing you will not do?" "Remind me, what do you refuse?")
  hxa_start "$base" || return $?; npc="$RL_NPC_FULL"; hxd_trim "$HXA_M0"
  # fresh lineage: no stored row, original profile, then the principle sentence
  hxa02_prin_off "$npc"; lt_sqlx "delete from imm26_npc_principle where npc_name='$(hxa_sq "$npc")'" >> "$EV/profile_set.txt" 2>&1
  hxa02_prin_on "$npc"
  d="$HXD/prep$ln"; mkdir -p "$d"
  hxd_sample "prep$ln" "Help me take that captive and put him in shackles." || return $?   # the 02-b request: the server derives and stores the principle row
  hxa02_rows "$npc" "$d/principle_rows_pre.txt" "$d/principle_rows_pre_full.txt"
  hxd_dry || grep -qi "${HX02C_PRIN:-slavery}" "$d/principle_rows_pre.txt" || { RL_REASON="no ${HX02C_PRIN:-slavery} row in imm26_npc_principle for $npc after the 02-b request (see $d/principle_rows_pre.txt; the server did not derive the principle from the profile text)"; return 3; }
  hxa02_md5 "$npc" "$d/profile_md5_before.txt"
  svn="${HX02C_SAVE:-kah-imm26-hx-02c}-$ln"
  printf 'stobe-auto save %s </dev/null | head -1\n' "$svn" | lt_h >> "$EV/save.txt" 2>&1
  hxd_sleep 6; echo "$svn" > "$d/save_name.txt"
  rd19_load "$svn" || return $?                                # reload = new session (the DLL starts a fresh chat session on 'game load detected')
  hxd_scene || return $?; hxd_dbclean; hxd_trim "$HXA_M0"; npc="$RL_NPC_FULL"
  # --- targets: Cind after the reload
  i=0; for lab in "${cl[@]}"; do
    i=$((i+1)); q="${qs[$(( ( $( echo "$lab" | tr -dc 0-9 ) - 1 ) % 3 ))]}"; d="$HXD/$lab"
    hxd_sample "$lab" "$q" || return $?
    cp "$HXD/prep$ln/principle_rows_pre.txt" "$d/principle_rows_pre.txt"
    hxa02_rows "$npc" "$d/principle_rows.txt" "$d/principle_rows_full.txt"
    cp "$HXD/prep$ln/profile_md5_before.txt" "$d/profile_md5_before.txt"; hxa02_md5 "$npc" "$d/profile_md5_after.txt"
    hxa02_panel "$d" "$npc" || return $?
    hxd_trim "$HXA_M0"
  done
  # --- controls: an unrelated NPC after the same reload (no principle in the prompt, none in the reply)
  for lab in "${ol[@]}"; do
    q="${qs[$(( ( $( echo "$lab" | tr -dc 0-9 ) - 1 ) % 3 ))]}"
    if [ -z "${HXA_CTL:-}" ]; then
      for ctl in ${HX02C_CTL:-Karnic Liplom}; do rl_resolve "$ctl" && { HXA_CTL="$RL_NPC_FULL"; break; }; done
      [ -n "${HXA_CTL:-}" ] || { RL_REASON="cannot resolve a control NPC (tried: ${HX02C_CTL:-Karnic Liplom}); set HX02C_CTL"; return 3; }
      echo "$HXA_CTL" > "$EV/ctl_npc.txt"
    fi
    printf 'stobe-auto teleport %s Shay </dev/null | head -1\n' "$(rl_q "$HXA_CTL")" | lt_h >> "$EV/place.txt" 2>&1
    hxd_sample "$lab" "$q" "$HXA_CTL" || return $?
    hxa02_rows "$HXA_CTL" "$HXD/$lab/principle_rows.txt"
    hxd_trim "$HXA_M0"
  done
}
rd_02cx() {
  hxd_begin; rd_need_npc || return 3
  local npc
  HXA_CTL=""; echo "${HX02C_PRIN:-slavery}" > "$HXD/principle.txt"
  hxa_start "$HX_SAVE" || return $?; HXA_M0=$(hxd_rowid); npc="$RL_NPC_FULL"; echo "$npc" > "$EV/target_npc.txt"
  hxa02_md5 "$npc" "$EV/profile_md5_original.txt"
  hxa02_lineage 1 "$HX_SAVE" C1 C2 -- O1 || return $?
  hxa02_lineage 2 "$HX_SAVE2" C3 -- O2 O3 || return $?
  hxa02_prin_off "$npc"; hxa02_md5 "$npc" "$EV/profile_md5_restored.txt"
  hxd_trim "$HXA_M0"
}
