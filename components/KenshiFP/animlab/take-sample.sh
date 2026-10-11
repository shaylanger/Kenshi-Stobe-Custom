# take-sample.sh -- evidence sampler for labelled KenshiFP video takes (judged by the harness's
# tools/animlab/takecheck.py with take-rules.txt). Source it in a take script (WSL):
#   . /mnt/c/KenshiModding/components/KenshiFP/animlab/take-sample.sh
#   T0=$(date +%s.%N)                         # the same T0 the script's lab() uses for the labels file
#   take_sample_start <ev file> "$T0" <fp character> ["<allowed handle or name>|..."]
#   ... the take (labels written as `<t> <text>`, last one `end`) ...
#   take_sample_stop
#   python3 $HARN/tools/animlab/takecheck.py --labels <lab> --ev <ev file> --rules $HERE/take-rules.txt --video <mp4>
# The sampling runs in take_sample.py (one python process, ONE harness inbox write per sample for all five queries:
# fp_keys state, fp_combat state, where, chars, messages), every TAKE_DT s (default 0.6: mock max gap 0.63 s, no take-script slowdown; 0.4 gave 0.54 s but +35% take-script call latency; one sample ~ one 250 ms
# harness poll). Lines (seconds since T0):
#   <t> fp ui_state=.. hud_text=.. loaded=.. fp_ui_state=..
#   <t> world near=<other chars within TAKE_R m (default 20) of the fp char> nearest=<m> down=<dead/KO> msgs=<new> [msg=..]
# Allowed = '|'-separated substrings of a `chars` entry (the dummy target's handle, a test mate): they never count.
# Squad members (the fp character's faction) never count either.
# Sync flashes (T6 label lag, 2026-10-10): take_sample_start shows sync flash 0 at T0 (harness `sync_flash`: full-view
# magenta, TAKE_FLASH_MS default 150 ms), and `take_mark` (call it in the script's lab(), right after the label line,
# not for `end`) shows the next one. Each writes `<t> mark sync=<n>` (send time) to the ev file; takecheck.py --video
# pairs them with the flashes in the video (frames.py syncmarks) and FAILs a label whose flash is > 0.15 s off the T0
# offset or missing. A harness without sync_flash: one `<t> mark sync_off=no-sync_flash` line, take_mark does nothing.
#   lab(){ echo "$(awk ... ) $*" >> "$N.lab"; take_mark "$*"; }
# Frame stamp (frame-stamp 2026-10-10; default on since proof 2 05-stamp-proof2-1011-0018, TAKE_STAMP=0 turns it off): take_sample_start also sends harness
# `stamp on 8 [log $TAKE_STAMP_LOG]` (per-frame code in the top-left corner: game frame + FP state + label mark), the
# sync_flash calls then set the stamp mark instead of flashing, take_sample_stop sends `stamp off`; takecheck.py /
# review-pack.py read labels + state from the video (harness tools/animlab/stamp.py). Writes `<t> mark stamp=on|off-<why>`.
_TS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_ts_now() { awk -v a="$(date +%s.%N)" -v b="$_TS_T0" 'BEGIN{printf "%.2f", a-b}'; }
take_sample_start() {
  _TS_RUN=/tmp/take-sample-run.$$; : > "$1"; touch "$_TS_RUN"; _TS_EV=$1; _TS_T0=$2; _TS_MN=0
  local t r rs=; t=$(_ts_now)
  [ "${TAKE_STAMP:-1}" = 1 ] && rs=$(stobe-auto stamp on 8 ${TAKE_STAMP_LOG:+log "$TAKE_STAMP_LOG"} </dev/null 2>&1)
  r=$(stobe-auto sync_flash "${TAKE_FLASH_MS:-150}" 0 </dev/null 2>&1)
  case "$r" in *"sync_flash n=0"*) _TS_MOK=1; echo "$t mark sync=0" >> "$1";;
    *) _TS_MOK=0; echo "$t mark sync_off=no-sync_flash" >> "$1";; esac
  _TS_STAMP=0
  if [ "${TAKE_STAMP:-1}" = 1 ]; then
    case "$rs" in *"stamp on"*) _TS_STAMP=1; echo "$t mark stamp=on" >> "$1";;
      *) echo "$t mark stamp=off-no-harness-stamp" >> "$1";; esac
  fi
  KAH_DIR="${KAH_DIR:-D:\\Steam\\steamapps\\common\\Kenshi\\mods\\AutomationHarness}" \
    python3 "$_TS_DIR/take_sample.py" "$1" "$2" "$3" "${4:-}" --run "$_TS_RUN" 2>>"$1.err" & _TS_P=$!
}
take_mark() {   # take_mark "<label>": sync flash for the label just written (none for `end`: the video stops there);
  # no-op outside a sampled take or without harness sync_flash
  [ "${_TS_MOK:-0}" = 1 ] && [ -e "${_TS_RUN:-/nonexistent}" ] && [ "${1:-}" != end ] || return 0
  _TS_MN=$((_TS_MN + 1)); echo "$(_ts_now) mark sync=$_TS_MN" >> "$_TS_EV"
  stobe-auto sync_flash "${TAKE_FLASH_MS:-150}" "$_TS_MN" </dev/null >/dev/null 2>&1 &
}
take_sample_stop() { rm -f "$_TS_RUN"; wait "$_TS_P" 2>/dev/null
  [ "${_TS_STAMP:-0}" = 1 ] && stobe-auto stamp off </dev/null >/dev/null 2>&1; _TS_STAMP=0; return 0; }
