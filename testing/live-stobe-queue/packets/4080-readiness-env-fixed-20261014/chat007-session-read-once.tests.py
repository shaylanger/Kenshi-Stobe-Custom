import importlib.util
import json
import pathlib
import subprocess
import unittest
import tempfile
from types import SimpleNamespace


HELPER = pathlib.Path(__file__).with_name("chat007-session-read-once.py")
SPEC = importlib.util.spec_from_file_location("chat007_session_reader", HELPER)
READER = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(READER)


class SessionReaderDiagnosticTests(unittest.TestCase):
    def setUp(self):
        self.original_read = READER.read_session
        READER.read_session = lambda run: self.original_read(run, lambda: ({'STOBE_DB_HOST':'synthetic'}, 'STOBE_DB_HOST'))

    def tearDown(self):
        READER.read_session = self.original_read

    def test_nonzero_exit_captures_only_sanitized_stderr_metadata(self):
        secrets = ("LOAD_ID_SENTINEL", "BEARER_TOKEN_SENTINEL", "DB_PASSWORD_SENTINEL", "SHELL_COMMAND_SENTINEL")
        stderr = (
            "sudo: permission denied; load_id=" + secrets[0] +
            " token=" + secrets[1] + " DB_PASSWORD=" + secrets[2] +
            "; echoed command=sudo -u www-data php -r '" + secrets[3] + "'"
        )
        observed = {}

        def fake_run(args, **kwargs):
            observed["args"] = args
            observed.update(kwargs)
            return SimpleNamespace(returncode=255, stdout="", stderr=stderr)

        result = READER.read_session(fake_run)
        encoded = json.dumps(result, sort_keys=True)
        self.assertEqual(result["result"], "FAIL")
        self.assertEqual(result["exit_code"], 255)
        self.assertEqual(result["failure_kind"], "subprocess_failed")
        self.assertTrue(result["stderr_captured"])
        self.assertEqual(result["stderr_class"], "permission_denied")
        self.assertEqual(result["stderr_line_count"], 1)
        self.assertTrue(observed["capture_output"])
        self.assertTrue(observed["text"])
        self.assertEqual(observed["encoding"], "utf-8")
        self.assertEqual(observed["errors"], "replace")
        self.assertEqual(observed["timeout"], 20)
        self.assertEqual(observed['args'][:4], ['sudo','-u','www-data','--preserve-env=STOBE_DB_HOST'])
        self.assertEqual(observed['env'], {'STOBE_DB_HOST':'synthetic'})
        for secret in secrets:
            self.assertNotIn(secret, encoded)
        self.assertNotIn("sudo -u www-data php -r", encoded)
        self.assertNotIn("load_id", encoded)
        self.assertNotIn("token", encoded)
        self.assertNotIn("DB_PASSWORD", encoded)

    def test_timeout_and_launch_failure_do_not_expose_exception_text(self):
        def timeout_run(_args, **_kwargs):
            raise subprocess.TimeoutExpired("SECRET_COMMAND_SENTINEL", 20, stderr=b"timed out token=SECRET_TOKEN_SENTINEL")

        def failed_launch(_args, **_kwargs):
            raise OSError("SECRET_ENV_SENTINEL SECRET_COMMAND_SENTINEL")

        timeout = READER.read_session(timeout_run)
        launch = READER.read_session(failed_launch)
        encoded = json.dumps([timeout, launch], sort_keys=True)
        self.assertEqual(timeout["exit_code"], 124)
        self.assertEqual(timeout["stderr_class"], "timeout")
        self.assertEqual(launch["exit_code"], 127)
        self.assertEqual(launch["failure_kind"], "process_launch_error")
        for secret in ("SECRET_COMMAND_SENTINEL", "SECRET_TOKEN_SENTINEL", "SECRET_ENV_SENTINEL"):
            self.assertNotIn(secret, encoded)

    def test_invalid_stdout_is_not_echoed(self):
        sentinel = "RAW_STDOUT_LOAD_ID_SENTINEL"
        result = READER.read_session(
            lambda _args, **_kwargs: SimpleNamespace(returncode=0, stdout="load_id=" + sentinel, stderr="")
        )
        encoded = json.dumps(result, sort_keys=True)
        self.assertEqual(result["failure_kind"], "invalid_json")
        self.assertFalse(result["stderr_captured"])
        self.assertNotIn(sentinel, encoded)

    def test_success_allowlist_drops_raw_secret_fields(self):
        payload = {
            "session_present": True,
            "status": "ready",
            "gamets": "12345",
            "load_id_sha256": "a" * 64,
            "generation_present": True,
            "manager_ready_matches": True,
            "load_id": "RAW_LOAD_ID_SENTINEL",
            "token": "RAW_TOKEN_SENTINEL",
            "env": {"DB_PASSWORD": "RAW_ENV_SECRET_SENTINEL"},
            "command": "RAW_COMMAND_SENTINEL",
        }
        safe = READER.read_session(
            lambda _args, **_kwargs: SimpleNamespace(returncode=0, stdout=json.dumps(payload), stderr="")
        )
        encoded = json.dumps(safe, sort_keys=True)
        self.assertEqual(safe["gamets"], 12345)
        self.assertEqual(set(safe), {
            "session_present", "status", "gamets", "load_id_sha256",
            "generation_present", "manager_ready_matches",
        })
        for secret in ("RAW_LOAD_ID_SENTINEL", "RAW_TOKEN_SENTINEL", "RAW_ENV_SECRET_SENTINEL", "RAW_COMMAND_SENTINEL"):
            self.assertNotIn(secret, encoded)


class DbEnvironmentTests(unittest.TestCase):
    provision = "export STOBE_DB_HOST=127.0.0.1 STOBE_DB_PORT=5432 STOBE_DB_NAME=synthetic STOBE_DB_USER=test\nexport STOBE_ACTIVITY_SECRET=$(ignored)\n"

    def load(self, text):
        with tempfile.TemporaryDirectory() as folder:
            path = pathlib.Path(folder) / 'env.sh'
            path.write_text(text, encoding='utf-8')
            return READER.load_db_env(str(path))

    def test_provision_multi_assignment_and_unknown_expression(self):
        child,preserve=self.load(self.provision)
        self.assertEqual(child['STOBE_DB_NAME'], 'synthetic')
        self.assertEqual(preserve, 'STOBE_DB_HOST,STOBE_DB_NAME,STOBE_DB_PORT,STOBE_DB_USER')

    def test_selected_expression_duplicate_and_missing_fail_closed(self):
        for text in (self.provision+'export STOBE_DB_PASSWORD=$(secret)\n', self.provision+'export STOBE_DB_HOST=duplicate\n', 'export STOBE_DB_HOST=only\n'):
            with self.assertRaises(ValueError):
                self.load(text)

    def test_bad_env_does_not_launch_or_expose_exception(self):
        def bad_env():
            raise ValueError('SECRET_SENTINEL')
        def forbidden(*args, **kwargs):
            self.fail('subprocess launched for invalid env')
        result=READER.read_session(forbidden, bad_env)
        self.assertEqual(result['failure_kind'], 'db_environment_invalid')
        self.assertNotIn('SECRET_SENTINEL', json.dumps(result))


if __name__ == "__main__":
    unittest.main(verbosity=2)
