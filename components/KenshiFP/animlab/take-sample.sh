# take-sample.sh -- evidence sampler for labelled KenshiFP video takes (judged by the harness's
# tools/animlab/takecheck.py with take-rules.txt). Source it in a take script (WSL, stobe-auto on PATH):
#   . /mnt/c/KenshiModding/components/KenshiFP/animlab/take-sample.sh
#   T0=$(date +%s.%N)                         # the same T0 the script's lab() uses for the labels file
#   take_sample_start <ev file> "$T0" <fp character> ["<allowed handle or name>|..."]
#   ... the take (labels written as `<t> <text>`, last one `end`) ...
#   take_sample_stop
#   python3 $HARN/tools/animlab/takecheck.py --labels <lab> --ev <ev file> --rules $HERE/take-rules.txt --video <mp4>
# Two background loops, each line stamped with its own sample time (seconds since T0):
#   <t> fp ui_state=<fpc ui state> hud_text=<FP HUD text> loaded=<crossbow shots loaded> fp_ui_state=<combat view>
#   <t> world near=<other characters within TAKE_R m of the fp character, allowed ones excluded> nearest=<m>
#        down=<dead/KO among them> msgs=<new on-screen messages since the last sample> [msg=<text, spaces as _> ...]
# Allowed = '|'-separated substrings of a `chars` line (the dummy target's handle, a test mate): they never count.
# Squad members (the fp character's faction) never count either. TAKE_R (default 20 m), TAKE_DT (default 0.25 s).
_ts_now() { awk -v a="$(date +%s.%N)" -v b="$_TS_T0" 'BEGIN{printf "%.2f", a-b}'; }
_ts_fp() {
  while [ -e "$_TS_RUN" ]; do
    local t k c; t=$(_ts_now); k=$(stobe-auto fp_keys state 2>/dev/null); c=$(stobe-auto fp_combat state 2>/dev/null)
    echo "$t fp $(echo "$k" | grep -o ' ui_state=[^ ]*\| hud_text=[^ ]*' | tr -d '\n') $(echo "$c" | grep -o ' loaded=[^ ]*\| fp_ui_state=[^ ]*' | tr -d '\n')" >> "$_TS_EV"
    sleep "${TAKE_DT:-0.25}"
  done
}
_ts_world() {
  local seen=/tmp/take-sample-msgs.$$ cur=/tmp/take-sample-msgs-cur.$$
  stobe-auto messages 20 2>/dev/null | grep -v '^(hook' > "$seen"
  while [ -e "$_TS_RUN" ]; do
    local t p ch; t=$(_ts_now)
    p=$(stobe-auto where "$_TS_ME" 2>/dev/null | head -1)
    ch=$(stobe-auto chars $(( ${TAKE_R:-20} + 60 )) 2>/dev/null)
    stobe-auto messages 20 2>/dev/null | grep -v '^(hook' > "$cur"
    local new; new=$(grep -vxF -f "$seen" "$cur"); cp "$cur" "$seen"
    local w; w=$(echo "$ch" | awk -v me="$p" -v r="${TAKE_R:-20}" -v allow="$_TS_ALLOW" '
      BEGIN{ match(me, /pos=[-0-9.]+,[-0-9.]+,[-0-9.]+/); split(substr(me, RSTART+4, RLENGTH-4), m, ",");
             match(me, /\[[^]]*\]/); fac = substr(me, RSTART, RLENGTH); na = split(allow, al, "|"); n = 0; dn = 0; best = -1 }
      / pos=/ { if (fac != "" && index($0, fac)) next
                for (i = 1; i <= na; i++) if (al[i] != "" && index($0, al[i])) next
                match($0, /pos=[-0-9.]+,[-0-9.]+,[-0-9.]+/); split(substr($0, RSTART+4, RLENGTH-4), q, ",")
                d = sqrt((q[1]-m[1])^2 + (q[2]-m[2])^2 + (q[3]-m[3])^2); if (d > r) next
                n++; if ($0 ~ / (DEAD|KO)( |$)/) dn++; if (best < 0 || d < best) best = d }
      END{ printf "near=%d nearest=%s down=%d", n, (best < 0 ? "none" : sprintf("%.1f", best)), dn }')
    local nm=0 ml=""; if [ -n "$new" ]; then nm=$(echo "$new" | wc -l); ml=$(echo "$new" | cut -d' ' -f2- | tr ' ' '_' | sed 's/^/msg=/' | tr '\n' ' '); fi
    echo "$t world $w msgs=$nm $ml" >> "$_TS_EV"
    sleep "${TAKE_DT:-0.25}"
  done
  rm -f "$seen" "$cur"
}
take_sample_start() {
  _TS_EV=$1; _TS_T0=$2; _TS_ME=$3; _TS_ALLOW=${4:-}; _TS_RUN=/tmp/take-sample-run.$$
  : > "$_TS_EV"; touch "$_TS_RUN"
  _ts_fp & _TS_P1=$!; _ts_world & _TS_P2=$!
}
take_sample_stop() { rm -f "$_TS_RUN"; wait "$_TS_P1" "$_TS_P2" 2>/dev/null; }
