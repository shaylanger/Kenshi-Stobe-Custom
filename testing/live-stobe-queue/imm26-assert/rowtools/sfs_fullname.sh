# sfs_fullname.sh (imm26 op25): source AFTER unblockdefs_sfs.sh. Re-defines i4_bored so the targeted bored tick names the speaker with the FULL name
# ("Cind [Hungry Bandit]", what the DLL sends: ChatBox.cpp:5752-5754/5833-5844) instead of the bare "Cind" (inv22b2: the bare name resolves to a stale
# placeholder row, so bored.php's native reconcile never ingests the travel receipt). Derived from the current i4_bored by text substitution, so it follows later edits of that function.
_sfn_def="$(declare -f i4_bored)"
_sfn_new="${_sfn_def//'nm="${RL_NPC_FULL%% \[*}"'/'nm="$RL_NPC_FULL"'}"
_sfn_new="${_sfn_new//'nm="${ROW_NPC%% \[*}"'/'nm="$ROW_NPC"'}"
_sfn_new="${_sfn_new//"sed 's/ /%20/g'"/"sed 's/ /%20/g; s/\[/%5B/g; s/\]/%5D/g'"}"
if [ "$_sfn_new" = "$_sfn_def" ] || [[ "$_sfn_new" == *'RL_NPC_FULL%%'* ]]; then echo "sfs_fullname.sh: i4_bored substitution failed (function changed?)" >&2; return 1 2>/dev/null || exit 1; fi
eval "$_sfn_new"; unset _sfn_def _sfn_new
# op25: tr_walk_stage (unblockdefs_a.sh:59) staged Cind at <gate> dist <back> (350 u west: ridge at y 386 stopped Cind 112 u short, 08-d op16 run); honour
# TRIP_13C_STAGE="x y z" (valley floor, same staging as 22-b/13-c) like uf_walk_stage does. Unset = unchanged behaviour.
_sfn_def="$(declare -f tr_walk_stage)"
_sfn_new="${_sfn_def//'teleport $n $g dist $back'/'teleport $n ${TRIP_13C_STAGE:-$g dist $back}'}"
if [ "$_sfn_new" = "$_sfn_def" ]; then echo "sfs_fullname.sh: tr_walk_stage substitution failed (function changed?)" >&2; return 1 2>/dev/null || exit 1; fi
eval "$_sfn_new"; unset _sfn_def _sfn_new
