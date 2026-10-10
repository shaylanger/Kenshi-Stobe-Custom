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
_TS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
take_sample_start() {
  _TS_RUN=/tmp/take-sample-run.$$; : > "$1"; touch "$_TS_RUN"
  KAH_DIR="${KAH_DIR:-D:\\Steam\\steamapps\\common\\Kenshi\\mods\\AutomationHarness}" \
    python3 "$_TS_DIR/take_sample.py" "$1" "$2" "$3" "${4:-}" --run "$_TS_RUN" 2>>"$1.err" & _TS_P=$!
}
take_sample_stop() { rm -f "$_TS_RUN"; wait "$_TS_P" 2>/dev/null; }
