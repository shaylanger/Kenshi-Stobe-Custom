#!/usr/bin/env python3
"""Source-contract checks for the harness `stobe_ctxpush` command (NC tree).

main.cpp and StobeHarnessBridge.cpp need the Windows SDK, so these checks guard on any host that
ctxpush stays test-inbox only: registered through the harness bridge, never wired into the
production selection path, and never gated by ManualInputAllowed.
Run: python3 NC/tests/ctxpush_source_tests.py
"""
from pathlib import Path
import re
import unittest

SRC = Path(__file__).resolve().parents[1] / "src"
MAIN = (SRC / "main.cpp").read_text(encoding="utf-8")
BRIDGE = (SRC / "StobeHarnessBridge.cpp").read_text(encoding="utf-8")


def body(text, start_pat, end_pat):
    s = re.search(start_pat, text)
    assert s, start_pat
    e = re.search(end_pat, text[s.end():])
    assert e, end_pat
    return text[s.start(): s.end() + e.start()]


HELPER = body(MAIN, r"static std::string TestInboxPushNpcContext\(", r"\nstatic std::string RunTestInboxCommand\(")
RUNNER = body(MAIN, r"static std::string RunTestInboxCommand\(", r"\n  if \(cmd == \"npcinfo\"\)")
CTXPUSH = body(RUNNER, r'if \(cmd == "ctxpush"\)', r'\n  if \(cmd == "mode"\)')
SAY = body(RUNNER, r'if \(cmd == "say"\)', r"\n  return|\Z")


class CtxPushSourceTests(unittest.TestCase):
    def test_command_is_registered_and_counted(self):
        self.assertRegex(BRIDGE, r'\{"ctxpush", "stobe_ctxpush <target')
        self.assertIn('registered == 11 ? "11 commands"', BRIDGE)
        n = len(re.findall(r'^\s*\{"[a-z_]+", "stobe_', BRIDGE, re.M))
        self.assertEqual(n, 11)

    def test_command_builds_the_envelope_and_posts_context_and_gamedata(self):
        self.assertIn("BuildNpcContextEnvelope(npc, contextType)", HELPER)
        self.assertIn('AsyncPostToStobe(L"/context", contextJson);', HELPER)
        self.assertIn('AsyncPostToStobe(L"/gamedata"', HELPER)
        for key in ("native_ai", "referral_people", "travel_destinations"):
            self.assertIn('"\\"%s\\":"' % key, HELPER)

    def test_ctxpush_resolves_target_and_does_not_need_manual_input(self):
        self.assertIn("ResolveTestInboxTarget(world, sel, speaker, f[2])", CTXPUSH)
        self.assertIn("TestInboxPushNpcContext(ctxTarget", CTXPUSH)
        self.assertNotIn("ManualInputAllowed", CTXPUSH)
        self.assertNotIn("ManualInputAllowed", HELPER)

    def test_say_pushes_only_when_stale(self):
        self.assertRegex(SAY, r'TestInboxPushNpcContext\(target, "say", true, ctxPushed\)')
        self.assertIn("onlyIfStale &&", HELPER)
        self.assertIn("kSelectionContextMinIntervalMs", HELPER)

    def test_helper_does_not_touch_production_selection_state(self):
        for name in ("g_pendingSelectionContext", "g_lastSelectionContextPushed", "g_stateMutex",
                     "QueueSelectionContextPush", "ClearPendingSelectionContextPush"):
            self.assertNotIn(name, HELPER)

    def test_production_selection_path_unchanged(self):
        # the only callers of the helper are the two test-inbox sites
        calls = [m.start() for m in re.finditer(r"TestInboxPushNpcContext\(", MAIN)]
        self.assertEqual(len(calls), 3)  # definition + ctxpush + say
        self.assertEqual(len(re.findall(r"QueueSelectionContextPush\(", MAIN)), 1)  # definition only (selection push stays disabled)
        self.assertRegex(MAIN, r"ClearPendingSelectionContextPush\(\);\s*\} else \{\s*ClearPendingSelectionContextPush\(\);")


if __name__ == "__main__":
    unittest.main()
