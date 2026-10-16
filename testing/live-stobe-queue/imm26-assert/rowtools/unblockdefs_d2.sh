#!/usr/bin/env bash
# unblockdefs_d2.sh (imm26-sfD2): row 03-b recipe overrides for the HUB. NEW file; unblockdefs_d.sh is sourced as a library and NOT edited. Sourced by unblockrun_d2.sh.
# Why (imm26-sfD findings, 03-b stayed SETUP-FAIL in the Hub):
#  1 u3_pick_b needed a SPARSE B (<= 6 rows, <= 2 about Shay); in the Hub nobody is sparse -> `none`. With the hearsay fix (ba448ed: the holder's newest 2 heard_from rows are
#    always added to the conversation context, speaker share LIMIT 40) a sparse B is no longer needed: default U03B_MAX_ROWS=999 and the candidate with the FEWEST rows is
#    preferred (then fewest about Shay). --b "<Full Name>" / U03B_B still forces one.
#  2 u3_quiet moved strays away only from the CURRENT place (the Hub, where fights start). Now Shay + Cind + Malzin + B are teleported to the quiet spot HX_SPOT
#    (-48000 1500 2960) FIRST, strays within 400 u go to U_FAR, then B is sent far + protected (it must not witness the attack).
#  3 ba448ed is compose-only. rd_03b refuses (SETUP-FAIL via hearsay_missing.txt, no attack, no DB change) when the lane's lib/imm26_knowledge.php has no
#    stobeKnowledgeHearsayFor; hint: deploy with  bash /mnt/c/KenshiTestRuns/imm26-install/hearsay/deploy.sh <lane-root>  (inside the lane's WSL, only when no operator row runs).
# Extra evidence: hearsay_check.txt, b_candidates.txt (count|about_shay|name, fewest first), quiet.txt.
U2_HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
declare -F rd_03b_body >/dev/null || . "$U2_HERE/unblockdefs_d.sh"
: "${U03B_MAX_ROWS:=999}"; export U03B_MAX_ROWS
U2_SPOT_DEF="-48000 1500 2960"

d2_spot() { printf '%s' "${HX_SPOT:-${HX_SPOT_DEF:-$U2_SPOT_DEF}}"; }

# ---- candidate B: any awake non-slave digit-serial NPC near Shay, FEWEST social_rumor rows first
u3_pick_b() {  # prints the chosen full name (also b.txt); empty = none
  local f="$EV/chars.txt" cands="$EV/b_candidates.txt" cw="$EV/b_counts.txt" nm pick="" st
  if [ -n "${U03B_B:-}" ]; then echo "$U03B_B" | tee "$EV/b.txt"; return 0; fi
  lt_h <<EOT 2>&1 | sed 's/ | /\n/g' | grep -E '#-?[0-9]+/[0-9]+' > "$f"
stobe-auto chars ${U03B_RADIUS:-400} </dev/null 2>&1 | head -c 20000 # u3:chars
EOT
  lt_sql "select holder_name||'|'||count(*)||'|'||count(*) filter (where lower(subject_name) like 'shay%' or lower(victim_name) like 'shay%') from social_rumor where status='active' group by holder_name /* u3:counts */" > "$cw" 2>&1
  sed -nE 's/^[[:space:]]*(.*[^ ]) #([0-9]+)\/[0-9]+ \[([^]]*)\].*/\1|\2|\3/p' "$f" | awk -F'|' -v w="$(printf %s "${RL_NPC_FULL%% *}" | tr A-Z a-z)" '
    {n=tolower($1); fa=tolower($3)} n ~ /^(shay|malzin)/ {next} index(n,w)==1 {next} fa ~ /slave/ {next} {print}' > "$EV/b_all.txt"
  awk -F'|' -v mx="${U03B_MAX_ROWS:-999}" 'NR==FNR{t[$1]=$2; a[$1]=$3; next} {c=($1 in t)?t[$1]:0; s=($1 in a)?a[$1]:0; if (c<=mx) print c"|"s"|"$1}' "$cw" "$EV/b_all.txt" | sort -t'|' -k1,1n -k2,2n > "$cands"
  while IFS='|' read -r _ _ nm; do
    [ -n "$nm" ] || continue
    st=$(printf 'stobe-auto stobe_state %s </dev/null 2>&1 | head -c 3000 # u3:state\n' "$(rl_q "$nm")" | lt_h 2>&1)
    echo "$st" | grep -q '"unconscious": \?false' || continue
    echo "$st" | grep -qiE '"(is_)?slave": ?true' && continue
    pick="$nm"; break
  done < <(head -12 "$cands")
  echo "$pick" | tee "$EV/b.txt"
}

# ---- scene: the quiet spot first, then everyone but Shay/Cind/Malzin/B away; B sent far (must not witness) and protected
u3_quiet() {  # u3_quiet <B full>
  local n b bs; n=$(rl_q "$RL_NPC_FULL"); b=$(rl_q "$1"); bs="${1%% *}"
  lt_h <<EOT >> "$EV/quiet.txt" 2>&1
stobe-auto teleport Shay $(d2_spot) </dev/null | head -1
stobe-auto teleport $n Shay </dev/null | head -1
stobe-auto teleport Malzin Shay </dev/null | head -1
stobe-auto teleport $b Shay </dev/null | head -1
stobe-auto stobe_drawn sheathe Shay </dev/null | head -1
for pass in 1 2; do
  stobe-auto chars 400 </dev/null 2>&1 | sed 's/ | /\n/g' | grep -v -E "Shay #|${RL_NPC_FULL%% *} \[|Malzin #|$bs " | grep -E "#[0-9]+/[0-9]+" | sed -E 's/.*#([0-9]+\/[0-9]+).*/\1/' | sort -u > /tmp/u3-ids.txt
  while read id; do stobe-auto teleport "#\$id" $U_FAR </dev/null >/dev/null 2>&1; done < /tmp/u3-ids.txt
done
stobe-auto protect $b on </dev/null | head -1
stobe-auto teleport $b $U_FAR </dev/null | head -1
for nm in Shay $n Malzin; do stobe-auto health "\$nm" 100 </dev/null >/dev/null 2>&1; done
stobe-auto protect $n on </dev/null | head -1
stobe-auto where $n </dev/null | head -1 | cut -c1-140
EOT
}

# ---- the hearsay fix must be in the lane copy
d2_hearsay_check() {  # rc 0 = present (or dry run); rc 1 = missing (hearsay_missing.txt written)
  local c
  if [ -n "${KAH_ROW_DRY:-}" ]; then echo "dry run: check skipped" > "$EV/hearsay_check.txt"; return 0; fi
  c=$(printf 'grep -c stobeKnowledgeHearsayFor %s/site/lib/imm26_knowledge.php 2>/dev/null; true # u3:hearsay\n' "$LT_ROOT" | lt_w 2>&1 | tail -1 | tr -dc 0-9)
  echo "stobeKnowledgeHearsayFor matches in $LT_ROOT/site/lib/imm26_knowledge.php: ${c:-0}" > "$EV/hearsay_check.txt"
  if [ "${c:-0}" -ge 1 ] 2>/dev/null; then return 0; fi
  echo "lane copy of lib/imm26_knowledge.php has no stobeKnowledgeHearsayFor (fix ba448ed not deployed on $LT_LANE): deploy it inside the lane's WSL when no operator row runs: bash /mnt/c/KenshiTestRuns/imm26-install/hearsay/deploy.sh $LT_ROOT" > "$EV/hearsay_missing.txt"
  return 1
}

rd_03b() {
  tr_cfg
  d2_hearsay_check || return 0                               # checker: SETUP-FAIL with the deploy hint
  rd_03b_body "$@"; local rc=$?; u3_restore; return $rc
}
