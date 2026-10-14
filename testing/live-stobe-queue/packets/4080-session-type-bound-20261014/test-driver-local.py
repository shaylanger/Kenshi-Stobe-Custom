import io
import pathlib
import subprocess
import sys
import unittest
from unittest.mock import patch

body = pathlib.Path(__file__).with_name('body.sh').read_text()
driver = body.split("db_driver=$(cat <<'KAH_DB_DRIVER'\n", 1)[1].split('\nKAH_DB_DRIVER', 1)[0]

class DriverTests(unittest.TestCase):
    def run_fixture(self, fixture):
        result = subprocess.CompletedProcess([], 0, b'{}\n', b'')
        with patch('builtins.open', return_value=io.StringIO(fixture)), patch('subprocess.run', return_value=result) as mocked, patch.object(sys, 'argv', ['driver', 'PD9waHA=']), patch.object(sys, 'stdout', io.TextIOWrapper(io.BytesIO())):
            try:
                exec(compile(driver, '<fixture-driver>', 'exec'), {})
                code = 0
            except SystemExit as stopped:
                code = stopped.code
            return code, mocked.call_args

    def test_real_provision_shape(self):
        code, call = self.run_fixture('set +x # private\nexport PGPORT=15434 STOBE_DB_PORT=15434 STOBE_DB_HOST=/tmp/stobe-standalone4080/socket STOBE_DB_NAME=stobe_standalone4080_test STOBE_DB_USER=dwemer STOBE_NO_BACKGROUND_PROCESSOR=1 STOBE_ACTIVITY_ENABLED=1\nexport STOBE_ACTIVITY_TRANSPORT_SECRET="$(cat /tmp/stobe-standalone4080/activity-transport.key)"\n')
        self.assertEqual(code, 0)
        self.assertEqual(call.kwargs['env']['STOBE_DB_USER'], 'dwemer')
        self.assertNotIn('STOBE_ACTIVITY_TRANSPORT_SECRET', call.kwargs['env'])
        self.assertEqual(call.kwargs['timeout'], 20)

    def test_db_shell_expression_rejected_before_child(self):
        code, call = self.run_fixture('export STOBE_DB_HOST="$(cat /tmp/secret)"\n')
        self.assertEqual(code, 26)
        self.assertIsNone(call)

    def test_duplicate_rejected(self):
        code, call = self.run_fixture('export STOBE_DB_HOST=/a STOBE_DB_HOST=/b\n')
        self.assertEqual(code, 26)
        self.assertIsNone(call)

if __name__ == '__main__':
    unittest.main()
