#!/usr/bin/env python3
"""Wire TestAutomation.cpp (test-only automation commands) into Stobe.dll.

Usage: patch_test_automation_dll.py <STOBE tree root> [<build root> ...]
Adds the include + InstallTestAutomationHooks() call to src/main.cpp, the
source to CMakeLists.txt, and to SOURCES of build_portable.bat / build.bat
in each given build root.
Idempotent: re-running on a patched tree changes nothing.
"""
import sys
from pathlib import Path


def patch(path, anchor, insert, after=True, marker=None):
    text = path.read_text(encoding='utf-8')
    marker = marker or insert.strip()
    if marker in text:
        print('already patched:', path, '|', marker[:50])
        return
    assert text.count(anchor) == 1, 'anchor not unique/missing in %s: %r' % (path, anchor)
    text = text.replace(anchor, anchor + insert if after else insert + anchor)
    path.write_text(text, encoding='utf-8', newline='')
    print('patched:', path, '|', marker[:50])


root = Path(sys.argv[1])
main = root / 'src' / 'main.cpp'
assert (root / 'src' / 'TestAutomation.cpp').exists(), 'TestAutomation.cpp missing'
patch(main, '#include "StobeChatMode.h"\n', '#include "TestAutomation.h"\n')
patch(main, '  Log("HOOK: PlayerInterface::update installed (UI-only mode).");\n',
      '  InstallTestAutomationHooks(); // test-only automation commands (auto_inbox.txt)\n')
patch(root / 'CMakeLists.txt', '  src/StobeEventPolicy.cpp\n', '  src/TestAutomation.cpp\n')

for build_root in sys.argv[2:]:
    for name in ('build_portable.bat', 'build.bat'):
        bat = Path(build_root) / name
        if bat.exists():
            patch(bat, ' StobeEventPolicy main ', 'TestAutomation ', marker=' TestAutomation ')
