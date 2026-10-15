#!/usr/bin/env python3
"""Source-contract regression checks for the Windows-only session worker.

Run with: python3 components/STOBE/tests/cpp/playthrough_session_retry_source_tests.py
The production translation unit requires the Windows SDK and is compile-checked
by build-stobe.ps1; these checks guard retry/auth boundaries on hosts without it.
"""
from pathlib import Path
import re
import unittest


SOURCE = Path(__file__).resolve().parents[1] / "src" / "PlaythroughSession.cpp"
TEXT = SOURCE.read_text(encoding="utf-8")


class PlaythroughRetrySourceTests(unittest.TestCase):
    def test_transient_http_statuses_are_narrow_and_explicit(self):
        self.assertRegex(
            TEXT,
            r"bool RetryableStatus\(unsigned long status\)\s*\{\s*return status == 0\s*\|\|\s*status == 408\s*\|\|\s*status == 429\s*\|\|\s*\(status >= 500 && status <= 599\);",
        )

    def test_retry_count_and_delays_are_bounded(self):
        self.assertIn("const unsigned long kMaxAttempts = 6;", TEXT)
        self.assertIn("static const ULONGLONG delays[] = {1000, 2000, 4000, 8000, 16000};", TEXT)
        self.assertIn("s.attempts>=kMaxAttempts", TEXT)
        self.assertRegex(TEXT, r"request\.attempt<kMaxAttempts")

    def test_permanent_rejection_does_not_become_authorized(self):
        self.assertIn('if(status==404){fields["status"]="sunsupported";accepted=true;break;}', TEXT)
        self.assertRegex(
            TEXT,
            r"status==200&&valid&&fields\[\"ok\"\]==\"ltrue\"",
        )
        self.assertIn('state.ready=true;', TEXT)
        self.assertIn('else if(!accepted){', TEXT)

    def test_retry_is_scoped_to_current_generation_and_single_flight(self):
        self.assertIn("if(request.epoch!=state.generation)return 0;", TEXT)
        self.assertIn("s.inFlightGeneration==s.generation", TEXT)
        self.assertIn("s.attempts>0&&now<s.retryAt", TEXT)
        self.assertIn("s.attempts=0;s.retryAt=0;s.ready=false", TEXT)

    def test_restored_campaign_marker_preserves_new_campaign_identity(self):
        restore = re.search(
            r"void RestoreCharacter\([^\n]+\n", TEXT
        )
        self.assertIsNotNone(restore)
        self.assertIn("Get().isNew=isNew", restore.group(0))
        self.assertIn("s.isNew=newGame", TEXT)
        self.assertIn("BeginLoad(true)", (SOURCE.parent / "main.cpp").read_text(encoding="utf-8"))

    def test_diagnostics_exclude_request_body_and_secrets(self):
        self.assertIn('outcome=transient http=', TEXT)
        self.assertIn('transient?"retry_exhausted":"rejected"', TEXT)
        for line in TEXT.splitlines():
            if "PLAYTHROUGH: outcome=" in line:
                self.assertNotRegex(line, re.compile(r"body|token|character_id|client_id", re.I))


if __name__ == "__main__":
    unittest.main(verbosity=2)
