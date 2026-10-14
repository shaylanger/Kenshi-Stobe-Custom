#!/usr/bin/env python3
"""Mocked route tests for tools/stobe-say; never accesses a game or harness."""
import importlib.util
import importlib.machinery
import os
import tempfile
import unittest

SCRIPT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', 'stobe-say'))
SPEC = importlib.util.spec_from_loader('stobe_say', importlib.machinery.SourceFileLoader('stobe_say', SCRIPT))
stobe_say = importlib.util.module_from_spec(SPEC)
_route_env = {key: os.environ.pop(key) for key in ('KAH_INSTANCE', 'KENSHI_DIR', 'KAH_DIR') if key in os.environ}
try:
    SPEC.loader.exec_module(stobe_say)
finally:
    os.environ.update(_route_env)


class RouteTests(unittest.TestCase):
    def test_explicit_instance_three_resolves_4080_c_and_5090_d(self):
        old_isdir = stobe_say.os.path.isdir
        old_check_output = stobe_say.subprocess.check_output
        try:
            stobe_say.subprocess.check_output = lambda args, **kwargs: (_ for _ in ()).throw(FileNotFoundError())
            for drive in ('c', 'd'):
                game = '/%s/KenshiInst/3' % drive
                harness = '/mnt/%s/KenshiInst/3/mods/AutomationHarness' % drive
                route = {'KAH_INSTANCE': '3', 'KENSHI_DIR': game,
                         'KAH_DIR': r'%s:\KenshiInst\3\mods\AutomationHarness' % drive.upper()}
                stobe_say.os.path.isdir = lambda p, want=harness: p == want
                self.assertEqual(stobe_say._resolve_paths(route), ('/mnt/%s/KenshiInst/3' % drive, harness))
        finally:
            stobe_say.os.path.isdir = old_isdir
            stobe_say.subprocess.check_output = old_check_output

    def test_bad_or_incomplete_isolated_route_fails_closed(self):
        cases = [
            {'KENSHI_DIR': '/c/KenshiInst/3'},
            {'KAH_INSTANCE': '3'},
            {'KAH_INSTANCE': '3', 'KENSHI_DIR': '/c/KenshiInst/3',
             'KAH_DIR': r'C:\Program Files (x86)\Steam\steamapps\common\Kenshi\mods\AutomationHarness'},
            {'KAH_INSTANCE': '2', 'KENSHI_DIR': '/c/KenshiInst/3',
             'KAH_DIR': r'C:\KenshiInst\3\mods\AutomationHarness'},
        ]
        for env in cases:
            with self.subTest(env=env), self.assertRaises(SystemExit):
                stobe_say._resolve_paths(env)

    def test_unconfigured_default_preserves_instance_one(self):
        self.assertEqual(stobe_say._resolve_paths({}),
                         (stobe_say.MAIN_GAME, stobe_say.MAIN_HARNESS))
        self.assertEqual(stobe_say.MOD,
                         stobe_say.MAIN_GAME + '/RE_Kenshi/mods/Stobe')
        self.assertEqual(stobe_say.STOBE_LOG,
                         stobe_say.MAIN_GAME + '/RE_Kenshi/mods/Stobe/stobe.log')


if __name__ == '__main__':
    unittest.main()
