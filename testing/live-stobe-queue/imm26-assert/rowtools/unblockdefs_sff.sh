#!/usr/bin/env bash
# unblockdefs_sff.sh (imm26-sfFixA): row 03-b, FORCED WITNESS LINE. NEW file; unblockdefs_d/d2/sfz are sourced as libraries and NOT edited. Sourced by unblockrun_sff.sh.
# Why (5090-i5 NC24 3 attempts + 4080-i3/i4 attempts, 03-b SETUP-FAIL): the sfz seam opens the chance gate, but the pair request is still an LLM lottery: Cind's autochat line must NAME
#   Shay before stobeKnowledgeShareFromSpeech (processor/bored.php:566) creates B's heard_from row. The bored prompt gives her the "what you personally know" block, but the
#   instruction ("a concrete trigger in the current situation", hooks from her recent eventlog) makes her talk about the nearest drone/idle NPC: 0 successes in 20 + 24 + 6 tries.
# Seam (no server change, no lane deploy, private lane DB only): after the real attack and the Cind first-hand row, the witness line is FORCED by running the server's own hook for a scripted
#   line: sharehook.php -> stobeKnowledgeShareFromSpeech(Cind, B, "I saw Shay attack Malzin ...", gamets) = the same call bored.php makes after every NPC -> NPC line, so the heard_from row
#   (source Cind, hops 1, dedupe, opinion effect) is created by the real code. What is NOT exercised on this path: the LLM naming Shay (director scenes already do it in the wild:
#   'NPC gossip passed on ... via director'). The verdict line says so (seed=forced-line). Everything downstream is real: B is asked "Have you heard anything about me?" in game and its prompt is captured.
# Env: SFF_REAL_TRIES (default 0: real LLM pair requests to try FIRST, via the sfz loop; the forced line runs when they give nothing)  SFF_TEXT (the scripted line)  SFF_SUBJECT (Shay)  SFF_VICTIM (Malzin).
# Extra evidence: forced_line.txt (sharehook.php json: ids, gamets, eligible rows, shared; SHARERC=0 means a row was created), seed_mode.txt (forced-line | llm-line | none), gossip_all.txt gets a `## forced-line` block.
SFF_HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
declare -F sz_03b_body >/dev/null || . "$SFF_HERE/unblockdefs_sfz.sh"
: "${SFF_REAL_TRIES:=0}"; export SFF_REAL_TRIES
SFF_HOOK="$SFF_HERE/sharehook.php"

# keep the sfz LLM loop as sz_gossip_loop_real (once), then replace sz_gossip_loop (called by sz_03b_body) with the two-stage version
declare -F sz_gossip_loop_real >/dev/null || eval "$(declare -f sz_gossip_loop | sed '1s/^sz_gossip_loop/sz_gossip_loop_real/')"

sff_wsl_path() { echo "$1" | sed -E 's#^/([a-zA-Z])/#/mnt/\1/#'; }

sff_force_line() {  # sff_force_line <B full> : sets U3_RES gossip|no_gossip ; writes forced_line.txt, seed_mode.txt, gossip_ok.txt
  local b="$1" subj="${SFF_SUBJECT:-Shay}" vic="${SFF_VICTIM:-Malzin}" txt f="$EV/forced_line.txt" rc
  txt="${SFF_TEXT:-I saw $subj attack $vic with my own eyes, ${b%% \[*}. Keep clear of $subj.}"
  printf 'cd %q/site; KAH_LANE_ROOT=%q KAH_LANE_DB=%q php %q %q %q %q 2>&1 | head -c 2500; R=${PIPESTATUS[0]}; echo; echo SHARERC=$R # sff:share\n' \
    "$LT_ROOT" "$LT_ROOT" "$LT_DB" "$(sff_wsl_path "$SFF_HOOK")" "$RL_NPC_FULL" "$b" "$txt" | lt_w > "$f" 2>&1
  rc=$(grep -o 'SHARERC=[0-9]*' "$f" | tail -1 | tr -dc 0-9)
  { echo "## forced-line (direct call of the server's gossip hook, NOT an LLM line) rc=${rc:-?}"; cat "$f"; } >> "$EV/gossip_all.txt"
  if [ "${rc:-9}" = 0 ]; then U3_RES=gossip; echo forced-line > "$EV/seed_mode.txt"; echo "ok forced-line tick=0 gated=${SZ_GATED:-0} spoken=${SZ_SPOKEN:-0}" > "$EV/gossip_ok.txt"
  else U3_RES=no_gossip; echo none > "$EV/seed_mode.txt"; echo "none tries=${SZ_K:-0} gated=${SZ_GATED:-0} spoken=${SZ_SPOKEN:-0} forced=1" > "$EV/gossip_ok.txt"; fi
}

sz_gossip_loop() {  # sz_gossip_loop <B full>
  local b="$1" t0="${U03B_TRIES:-24}" s0="${SZ_MAX_SPOKEN:-12}"
  SZ_GATED=0; SZ_SPOKEN=0; SZ_K=0; U3_RES=no_gossip
  if [ "${SFF_REAL_TRIES:-0}" -gt 0 ] 2>/dev/null; then
    U03B_TRIES="$SFF_REAL_TRIES"; SZ_MAX_SPOKEN="$SFF_REAL_TRIES"
    sz_gossip_loop_real "$b"; local rc=$?
    U03B_TRIES="$t0"; SZ_MAX_SPOKEN="$s0"
    [ $rc = 0 ] || return $rc
    if [ "$U3_RES" = gossip ]; then echo llm-line > "$EV/seed_mode.txt"; return 0; fi
  fi
  sff_force_line "$b"
}
