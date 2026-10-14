#!/usr/bin/env python3
"""Offline checks for the workspace-only 5090b/i2 backend overlay.

This validates file provenance and source/config isolation contracts. It never
starts a server, connects to PostgreSQL, calls KAH, or contacts a rig.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import re
import shutil
import subprocess
import sys
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
DEFAULT_LANE_DIR = ROOT / "pending-fixes/basic-ingame-smoke/standalone5090-overlays/5090b"
SOURCE_MANIFEST = ROOT / (
    "pending-fixes/release-coordination/"
    "stobe-server-final-composition-20261013-activity-travel/"
    "release-candidate/server/final-source-manifest.json"
)
BACKEND_CONTRACT = ROOT / "pending-fixes/basic-ingame-smoke/standalone5090-backend.ps1"
RESOURCE_LEDGER = ROOT / "pending-fixes/basic-ingame-smoke/standalone5090-resource-ledger.json"
ACTIVATION_MAP = ROOT / "pending-fixes/rig5090-validation/5090b-instance2/activation-map.md"

I2 = {
    "root": "/tmp/stobe-standalone5090b",
    "socket": "/tmp/stobe-standalone5090b/socket",
    "pgdata": "/tmp/stobe-standalone5090b/pgdata",
    "php_tmp": "/tmp/stobe-standalone5090b/tmp",
    "native_tmp": r"D:\KenshiInst\2\StobeTemp",
    "http": "127.0.0.1:18085",
    "pgport": "15435",
    "database": "stobe_standalone5090b_test",
    "role": "stobe5090b",
    "mod": "/mnt/d/KenshiInst/2/RE_Kenshi/mods/Stobe",
}
I3 = {
    "root": "/tmp/stobe-standalone5090c",
    "socket": "/tmp/stobe-standalone5090c/socket",
    "pgdata": "/tmp/stobe-standalone5090c/pgdata",
    "php_tmp": "/tmp/stobe-standalone5090c/tmp",
    "native_tmp": r"D:\KenshiInst\3\StobeTemp",
    "http": "127.0.0.1:18086",
    "pgport": "15436",
    "database": "stobe_standalone5090c_test",
    "role": "stobe5090c",
    "mod": "/mnt/d/KenshiInst/3/RE_Kenshi/mods/Stobe",
}


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest().upper()


def read_json(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def private_source_files(overlay: Path) -> list[tuple[Path, str]]:
    return [
        (p, p.read_text(encoding="utf-8", errors="replace"))
        for p in overlay.rglob("*")
        if p.is_file() and p.suffix.lower() in {".php", ".sql", ".json", ".ini", ".conf", ".sh"}
    ]


def check_fake_backend_record(record: dict, lane: str, contract: dict) -> bool:
    """Pure test oracle for a mocked schema/session/health response."""
    return (
        record.get("lane") == lane
        and record.get("database") == contract["database"]
        and record.get("role") == contract["role"]
        and record.get("schema_ready") is True
        and record.get("session_generation") == "fixture-generation-5090b"
        and record.get("session_secret_digest") == "a" * 64
    )


class OverlayIsolationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        parser = argparse.ArgumentParser(add_help=False)
        parser.add_argument("--lane-dir", type=Path, default=DEFAULT_LANE_DIR)
        args, _ = parser.parse_known_args()
        cls.lane_dir = args.lane_dir.resolve()
        cls.overlay = cls.lane_dir / "server-overlay"
        cls.manifest_path = cls.lane_dir / "DERIVED-TEST-MANIFEST.json"
        cls.manifest = read_json(cls.manifest_path)
        cls.source_manifest = read_json(SOURCE_MANIFEST)
        cls.allowlist = cls.source_manifest["live"]
        cls.contract_text = BACKEND_CONTRACT.read_text(encoding="utf-8")
        cls.ledger = read_json(RESOURCE_LEDGER)
        cls.b_sources = private_source_files(cls.overlay)
        cls.b_text = "\n".join(text for _, text in cls.b_sources)

    def test_manifest_matches_exact_canonical_allowlist_and_hashes(self) -> None:
        self.assertEqual(self.manifest.get("lane"), "5090b")
        self.assertIs(self.manifest.get("installable"), False)
        files = self.manifest.get("files")
        self.assertIsInstance(files, dict)
        self.assertEqual(set(files), set(self.allowlist))
        actual = {p.relative_to(self.overlay).as_posix() for p in self.overlay.rglob("*") if p.is_file()}
        self.assertEqual(actual, set(files), "overlay has missing or unmanifested files")
        for rel, expected_hash in files.items():
            path = self.overlay / Path(rel)
            self.assertFalse(path.is_symlink(), f"symlink is not an allowlisted payload: {rel}")
            self.assertEqual(sha256(path), expected_hash.upper(), f"manifest hash mismatch: {rel}")

    def test_lane_private_backend_contract_is_exact_and_distinct(self) -> None:
        block = re.search(r"'5090b'\s*=\s*\[ordered\]@\{([^}]+)\}", self.contract_text)
        self.assertIsNotNone(block, "5090b workspace contract is missing")
        text = block.group(1)
        expected = {
            "install": (r"D:\KenshiInst\2", True),
            "http": ("18085", False),
            "root": (I2["root"], True),
            "socket": (I2["socket"], True),
            "pgdata": (I2["pgdata"], True),
            "tmpdir": (I2["php_tmp"], True),
            "gametmp": (I2["native_tmp"], True),
            "pgport": (I2["pgport"], False),
            "db": (I2["database"], True),
            "role": (I2["role"], True),
            "game": (I2["mod"], True),
        }
        for key, (value, quoted) in expected.items():
            rendered = f"'{value}'" if quoted else value
            self.assertRegex(text, rf"(?:^|\s){key}={re.escape(rendered)}(?:;|\s|$)", f"wrong i2 {key}")
        for key, b_key, c_key in (
            ("root", "root", "root"),
            ("socket", "socket", "socket"),
            ("pgdata", "pgdata", "pgdata"),
            ("php temp", "php_tmp", "php_tmp"),
            ("native temp", "native_tmp", "native_tmp"),
            ("HTTP endpoint", "http", "http"),
            ("PostgreSQL socket parameter", "pgport", "pgport"),
            ("database", "database", "database"),
            ("role", "role", "role"),
            ("game path", "mod", "mod"),
        ):
            self.assertNotEqual(I2[b_key], I3[c_key], f"5090b and 5090c share {key}")
        self.assertIn(I2["root"], self.contract_text)
        self.assertIn(I2["socket"], self.contract_text)
        self.assertIn(I2["pgdata"], self.contract_text)
        self.assertIn(I2["php_tmp"], self.contract_text)
        self.assertIn(I2["native_tmp"], self.contract_text)

    def test_overlay_has_no_shared_instance_aliases_or_throttle_alias(self) -> None:
        forbidden = (
            "/var/lib/stobe",
            "/mnt/d/Steam/steamapps/common/Kenshi/",
            "/tmp/stobe_negotiation_",
            "/tmp/stobe-standalone5090c",
            "/tmp/stobe-standalone4080",
            "127.0.0.1:8083",
            "127.0.0.1:18083",
            "127.0.0.1:18084",
            "127.0.0.1:18086",
        )
        for value in forbidden:
            self.assertNotIn(value, self.b_text)
        self.assertIn("STOBE_TEST_INSTANCE_ID", self.b_text)
        self.assertIn("5090b", self.b_text)
        self.assertIn("STOBE_TEST_GAME_MOD_DIR", self.b_text)
        self.assertIn("STOBE_ACTIVITY_TRANSPORT_SECRET", self.b_text)
        self.assertIn("TMPDIR", self.b_text)
        self.assertIn(I2["php_tmp"], self.contract_text)

    def test_activity_secret_is_required_and_has_no_shared_file_fallback(self) -> None:
        activity = (self.overlay / "lib/activity/ActivityConfig.php").read_text(encoding="utf-8")
        self.assertIn("STOBE_ACTIVITY_TRANSPORT_SECRET", activity)
        self.assertIn("STOBE_TEST_INSTANCE_ID", activity)
        self.assertIn("5090b", activity)
        self.assertNotIn("/var/lib/stobe", activity)
        self.assertNotRegex(activity, r"file_get_contents\s*\(\s*['\"]/?var/lib/stobe")

    def test_php_syntax_when_php_cli_is_available(self) -> None:
        php = shutil.which("php")
        if not php:
            self.skipTest("PHP CLI is not installed in this local environment")
        for path, _ in self.b_sources:
            if path.suffix.lower() == ".php":
                result = subprocess.run([php, "-l", str(path)], capture_output=True, text=True, check=False)
                self.assertEqual(result.returncode, 0, f"PHP syntax failure in {path}: {result.stdout}{result.stderr}")

    def test_backend_recipe_has_no_provisioning_implementation(self) -> None:
        # The package is a source overlay only; operational actions must remain hard-stopped.
        self.assertIn("REVIEWED EXECUTION NOT IMPLEMENTED", self.contract_text)
        self.assertIn("cannot create, start, stop, or delete any host resource", self.contract_text.lower())
        resources = self.ledger.get("hostResourcesCreated", [])
        self.assertEqual(resources, [])

    def test_socket_only_postgres_is_the_declared_contract(self) -> None:
        # Static preparation contract only; no PostgreSQL instance is launched here.
        doc = ACTIVATION_MAP.read_text(encoding="utf-8").lower()
        self.assertIn("no tcp listener", doc)
        self.assertIn(I2["socket"], doc)
        self.assertIn(I2["pgdata"], doc)
        self.assertIn("15435", doc)
        self.assertIn("postgresql socket parameter", doc)

    def test_mock_schema_session_health_accepts_only_private_identity(self) -> None:
        # Synthetic values exercise the isolation contract without a DB, PHP server, or KAH call.
        valid = {
            "lane": "5090b",
            "database": I2["database"],
            "role": I2["role"],
            "schema_ready": True,
            "session_generation": "fixture-generation-5090b",
            "session_secret_digest": "a" * 64,
        }
        self.assertTrue(check_fake_backend_record(valid, "5090b", I2))
        for patch in (
            {"lane": "5090c"},
            {"database": I3["database"]},
            {"role": I3["role"]},
            {"schema_ready": False},
            {"session_generation": "fixture-generation-5090c"},
            {"session_secret_digest": "b" * 64},
        ):
            self.assertFalse(check_fake_backend_record({**valid, **patch}, "5090b", I2))
        i3_fixture = {**valid, "lane": "5090c", "database": I3["database"], "role": I3["role"],
                      "session_generation": "fixture-generation-5090c", "session_secret_digest": "b" * 64}
        self.assertFalse(check_fake_backend_record(i3_fixture, "5090b", I2))
        self.assertNotEqual(valid["session_secret_digest"], i3_fixture["session_secret_digest"])


def main() -> int:
    unittest.main(argv=[sys.argv[0]], verbosity=2)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
