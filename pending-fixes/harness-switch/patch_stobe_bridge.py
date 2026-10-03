#!/usr/bin/env python3
"""Harness switch-over, Stobe side: replace the built-in test harness with the
bridge to the Kenshi Automation Harness (DRAFT, apply only at the switch-over).

- removes TestAutomation.cpp/.h (moved to the harness repo) and the old
  test_inbox.txt reader (UpdateTestInbox); Stobe's chat commands now arrive
  through the harness as stobe_ping/mode/say/state/give_cats/give_item and
  still run from the player update hook (StobeHarnessBridge.cpp)
- drops Stobe's "speed" test command (the harness has "speed")
- the harness "attack" command lifts Stobe's faction truce through the
  before-attack hook, as the old built-in harness did
- adds StobeHarnessBridge.cpp/.h and the harness API header

Usage: patch_stobe_bridge.py <STOBE-src root> [--build-bat <build_portable.bat>]
                             [--harness <Kenshi-Automation-Harness repo>] [--check]
--check verifies every anchor and changes nothing. Idempotent.
"""
import argparse
import shutil
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent

ap = argparse.ArgumentParser()
ap.add_argument('root')
ap.add_argument('--build-bat')
ap.add_argument('--harness', default=str(HERE.parents[1] / 'Kenshi-Automation-Harness'))
ap.add_argument('--check', action='store_true')
args = ap.parse_args()

root = Path(args.root)
src = root / 'src'
main_cpp = src / 'main.cpp'
cmake = root / 'CMakeLists.txt'
api_header = Path(args.harness) / 'include' / 'KenshiAutomationHarness.h'

s = main_cpp.read_text(encoding='utf-8')
if 'StobeHarnessBridge' in s:
    print('already patched'); sys.exit(0)


def sub(text, old, new, what):
    n = text.count(old)
    assert n == 1, f'{what}: anchor found {n}x: {old[:70]!r}'
    return text.replace(old, new)


def cut(text, start, end, what, must_contain, keep_end=True):
    """Removes from the start anchor up to the end anchor (kept unless keep_end=False)."""
    assert text.count(start) == 1, f'{what}: start anchor found {text.count(start)}x'
    i = text.index(start)
    j = text.find(end, i)
    assert j > i, f'{what}: end anchor not found after start'
    assert must_contain in text[i:j], f'{what}: block does not contain {must_contain!r}'
    return text[:i] + text[j + (0 if keep_end else len(end)):]


s = sub(s, '#include "TestAutomation.h"\n', '#include "StobeHarnessBridge.h"\n', 'include')
s = sub(s,
        '  InstallTestAutomationHooks(); // test-only automation commands (auto_inbox.txt)\n',
        '  Stobe::HarnessBridge::Connect(); // test commands via the automation harness, if installed\n',
        'startPlugin call')
s = sub(s, '  UpdateTestInbox(worldUi, sel);\n',
        '  Stobe::HarnessBridge::Drain(worldUi, sel, &RunTestInboxCommand);\n',
        'player update call')
s = sub(s,
        '// Test inbox: lets tooling submit chat lines as if the player had spoken them.\n'
        '// Active only while mods\\Stobe\\test_inbox.flag exists. Tooling writes\n'
        '// test_inbox.txt (one command per line: id<TAB>command<TAB>args...), the DLL\n'
        '// consumes and deletes it, and appends id<TAB>ok|error<TAB>detail lines to\n'
        '// test_outbox.txt.\n',
        '// Test commands (stobe_say, stobe_state, ...): tooling sends them through the\n'
        '// Kenshi Automation Harness, which queues them for the player update hook\n'
        '// (StobeHarnessBridge.cpp). "say" lines go the same path as push-to-talk.\n',
        'test inbox comment')
# The old file reader: the whole function, up to and including its closing brace.
s = cut(s, 'static void UpdateTestInbox(GameWorld *world, Character *sel) {\n',
        '\n}\n\n', 'UpdateTestInbox', 'test_inbox.txt', keep_end=False)
# "speed" moved to the harness.
s = cut(s, '  if (cmd == "speed") {\n', '  if (cmd == "give_cats") {\n', 'speed command',
        'setGameSpeed')

c = cmake.read_text(encoding='utf-8')
c = sub(c, 'src/TestAutomation.cpp', 'src/StobeHarnessBridge.cpp', 'CMakeLists')

bat = None
if args.build_bat:
    bat_path = Path(args.build_bat)
    bat = bat_path.read_text(encoding='utf-8')
    bat = sub(bat, ' TestAutomation ', ' StobeHarnessBridge ', 'build_portable SOURCES')

for f in (HERE / 'StobeHarnessBridge.cpp', HERE / 'StobeHarnessBridge.h', api_header):
    assert f.exists(), f'missing {f}'
for f in (src / 'TestAutomation.cpp', src / 'TestAutomation.h'):
    assert f.exists(), f'missing {f}'

if args.check:
    print('check ok: every anchor found once; nothing written')
    sys.exit(0)

main_cpp.write_text(s, encoding='utf-8')
cmake.write_text(c, encoding='utf-8')
if bat is not None:
    bat_path.write_text(bat, encoding='utf-8')
for f in (HERE / 'StobeHarnessBridge.cpp', HERE / 'StobeHarnessBridge.h', api_header):
    shutil.copy2(f, src / f.name)
(src / 'TestAutomation.cpp').unlink()
(src / 'TestAutomation.h').unlink()
print('patched: bridge added, TestAutomation removed' + (', build bat updated' if bat else ''))
