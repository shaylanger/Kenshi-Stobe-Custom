# REL SR12/p7: re-seed NPC event state once social capture turns on after a load.
import sys
p = sys.argv[1] + "/src/main.cpp"
s = open(p).read()
def rep(a, b):
    global s
    assert s.count(a) == 1, a
    s = s.replace(a, b)
rep("struct NpcWorldEventState {\n  bool initialized;\n",
    "struct NpcWorldEventState {\n  bool initialized;\n  bool seededWithCapture; // REL_SEED_CAPTURE_M22\n")
rep("      : initialized(false), dead(false),",
    "      : initialized(false), seededWithCapture(false), dead(false),")
rep("""    NpcWorldEventState &state = g_npcWorldEventStateBySerial[serial];
""", """    NpcWorldEventState &state = g_npcWorldEventStateBySerial[serial];
    // REL_SEED_CAPTURE_M22: sweeps run right after world-stable, before the playthrough session is
    // ready (SocialCaptureEnabled false). States seeded then were silent (no "first seen already
    // enslaved", squad slaves missed on a later load). Re-seed once capture is on.
    if (state.initialized && !state.seededWithCapture && SocialCaptureEnabled())
      state.initialized = false;
""")
rep("""    if (!state.initialized) {
      state.initialized = true;
      state.useState = useStateNow;""", """    if (!state.initialized) {
      state.initialized = true;
      state.seededWithCapture = SocialCaptureEnabled();
      state.useState = useStateNow;""")
open(p, "w").write(s)
print("patched")
