#!/usr/bin/env python3
"""Pure synthetic tests for the 4080 i3 source-inspection gate contract."""
from dataclasses import dataclass, replace
import re
import unittest


@dataclass(frozen=True)
class Proof:
    host: str = "DESKTOP-NQQPA73"
    instance: str = "3"
    install_root: str = "/c/KenshiInst/3"
    ini_path: str = "/c/KenshiInst/3/RE_Kenshi/mods/Stobe/StobeCustom.ini"
    ini_host: tuple = ("127.0.0.1",)
    ini_port: tuple = ("18084",)
    ini_malformed: bool = False
    listener_pids: tuple = ("44",)
    listener_args: str = "php -S 127.0.0.1:18084 -t /tmp/stobe-standalone4080/site"
    duplicate_process_count: int = 1
    site_root: str = "/tmp/stobe-standalone4080/site"
    db_host: str = "/tmp/stobe-standalone4080/socket"
    db_name: str = "stobe_standalone4080_test"
    pgdata: str = "/tmp/stobe-standalone4080/pgdata"
    path_redirected: bool = False


def evaluate(p: Proof) -> tuple[bool, bool]:
    eligible = (
        p.host == "DESKTOP-NQQPA73"
        and p.instance == "3"
        and p.install_root == "/c/KenshiInst/3"
        and p.ini_path == "/c/KenshiInst/3/RE_Kenshi/mods/Stobe/StobeCustom.ini"
        and p.ini_host == ("127.0.0.1",)
        and p.ini_port == ("18084",)
        and not p.ini_malformed
        and len(p.listener_pids) == 1
        and p.duplicate_process_count == 1
        and p.listener_args == "php -S 127.0.0.1:18084 -t /tmp/stobe-standalone4080/site"
        and p.site_root == "/tmp/stobe-standalone4080/site"
        and p.db_host == "/tmp/stobe-standalone4080/socket"
        and p.db_name == "stobe_standalone4080_test"
        and p.pgdata == "/tmp/stobe-standalone4080/pgdata"
        and not p.path_redirected
    )
    return eligible, eligible


def possible_secret(text: str) -> bool:
    patterns = (
        r"(?i)authorization\s*:\s*bearer|-----BEGIN [A-Z ]*PRIVATE KEY-----",
        r"(?i)(?:api[_-]?key|access[_-]?token|client[_-]?secret|password)\s*[=:>]\s*['\"][^'\"]{8,}['\"]",
        r"(?i)https?://[^\s/]+:[^\s/@]+@",
    )
    return any(re.search(pattern, text) for pattern in patterns)


class GateTests(unittest.TestCase):
    def test_exact_synthetic_proof_passes(self):
        self.assertEqual(evaluate(Proof()), (True, True))

    def assert_rejected_before_read(self, proof):
        allowed, source_opened = evaluate(proof)
        self.assertFalse(allowed)
        self.assertFalse(source_opened)

    def test_wrong_host_or_route_aborts(self):
        self.assert_rejected_before_read(replace(Proof(), host="OTHER"))
        self.assert_rejected_before_read(replace(Proof(), instance="1"))
        self.assert_rejected_before_read(replace(Proof(), install_root="/c/shared/Kenshi"))
        self.assert_rejected_before_read(replace(Proof(), ini_path="/c/shared/Kenshi/RE_Kenshi/mods/Stobe/StobeCustom.ini"))

    def test_non_loopback_or_duplicate_ini_aborts(self):
        self.assert_rejected_before_read(replace(Proof(), ini_host=("0.0.0.0",)))
        self.assert_rejected_before_read(replace(Proof(), ini_port=("18084", "18084")))
        self.assert_rejected_before_read(replace(Proof(), ini_malformed=True))

    def test_missing_or_ambiguous_listener_aborts(self):
        self.assert_rejected_before_read(replace(Proof(), listener_pids=()))
        self.assert_rejected_before_read(replace(Proof(), listener_pids=("44", "45")))
        self.assert_rejected_before_read(replace(Proof(), duplicate_process_count=5))
        self.assert_rejected_before_read(replace(Proof(), listener_args="php -S 0.0.0.0:18084"))

    def test_redirected_root_or_shared_data_aborts(self):
        self.assert_rejected_before_read(replace(Proof(), path_redirected=True))
        self.assert_rejected_before_read(replace(Proof(), site_root="/var/www/html"))
        self.assert_rejected_before_read(replace(Proof(), db_name="stobe"))
        self.assert_rejected_before_read(replace(Proof(), pgdata="/var/lib/postgresql/data"))

    def test_missing_metadata_aborts(self):
        for field in ("db_host", "db_name", "pgdata", "site_root"):
            self.assert_rejected_before_read(replace(Proof(), **{field: ""}))

    def test_secret_scan_fails_closed(self):
        self.assertFalse(possible_secret("function ptr_read() { return true; }"))
        self.assertTrue(possible_secret("$api_key = 'not-for-output-secret-value';"))
        self.assertTrue(possible_secret("Authorization: Bearer abcdefghijkl"))


if __name__ == "__main__":
    unittest.main(verbosity=2)
