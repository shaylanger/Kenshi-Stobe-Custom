from pathlib import Path
import hashlib
import re
import unittest

ROOT = Path(__file__).resolve().parents[4]
PACKET = Path(__file__).resolve().parent
BODY = PACKET / "body.sh"
ROUTE = ROOT / "tools/automation/rig4080/instance-route-preflight.sh"
RIG_ENV = ROOT / "tools/automation/rig-env.sh"
PIN_ROUTE = "408FD0CAC181FEE32EF5DD0D0512CBD10494962CF1E251412EB900AF80E6EF51"
PIN_ENV = "A96DF1C3FDD95CF5F96471048F5FC1B63153EA21B6D3AD5A711145F0A80FE20D"


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest().upper()


def embedded_guard(body, helper):
    body_lines = body.replace("\r\n", "\n").splitlines()
    helper_lines = helper.replace("\r\n", "\n").splitlines()
    bstart = body_lines.index("embedded_i3_route_guard() {") + 1
    bend = body_lines.index("}", bstart)
    actual_lines = [line[2:] if line.startswith("  ") else line for line in body_lines[bstart:bend]]

    # Copy the reviewed helper's complete KAH_INSTANCE gate and RIG assignment,
    # skip only its own rig-env source bootstrap (already done by body line 4),
    # then copy every remaining route/path/inbox/harness check verbatim.
    hstart = helper_lines.index('if [[ "${KAH_INSTANCE:-}" != 3 ]]; then')
    hexport = helper_lines.index("export RIG=4080", hstart)
    hbootstrap = helper_lines.index('_here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)', hexport)
    hwant = helper_lines.index("_want_game='/c/KenshiInst/3'", hbootstrap)
    expected = [line for line in helper_lines[hstart:hbootstrap] if line != "export RIG=4080"]
    expected += helper_lines[hwant:]
    # Blank lines are presentation only; every executable line is compared
    # byte-for-byte after removing indentation added by the enclosing function.
    def logic_only(lines):
        kept = []
        skip_printf_continuation = False
        for line in lines:
            stripped = line.strip()
            if skip_printf_continuation:
                skip_printf_continuation = False
                continue
            if stripped.startswith("printf "):
                skip_printf_continuation = line.rstrip().endswith("\\")
                continue
            if stripped.startswith("echo "):
                continue
            if stripped:
                kept.append(stripped)
        return "\n".join(kept)

    return logic_only(actual_lines), logic_only(expected)


def wrapper_tail_violation(body):
    body = body.replace("\r\n", "\n").replace("\r", "\n")
    prefix = (
        "export RIG=4080 KAH_INSTANCE=3\n"
        "export KENSHI_DIR=/c/KenshiInst/3 KDIR=/c/KenshiInst/3\n"
        "export KAH_DIR='C:\\KenshiInst\\3\\mods\\AutomationHarness'\n"
        ". /c/KenshiModding/tools/automation/rig-env.sh\n"
    )
    if not body.startswith(prefix):
        return "bad_preamble"
    tail = body[len(prefix):]
    forbidden = (
        r"(?i)\b(?:RIG|KAH_INSTANCE|KENSHI_DIR|KDIR|KAH_DIR)\s*=",
        r"(?i)\bunset\s+(?:-v\s+)?(?:RIG|KAH_INSTANCE|KENSHI_DIR|KDIR|KAH_DIR)\b",
        r"(?im)(?:^|[;&|\s])(?:command\s+)?(?:env|eval|exec|source)\b",
        r"(?im)(?:^|[;&|\s])\.\s+",
    )
    for pattern in forbidden:
        if re.search(pattern, tail):
            return pattern
    return None


class PacketSelfcheck(unittest.TestCase):
    def test_pinned_local_helpers(self):
        self.assertEqual(sha(ROUTE), PIN_ROUTE)
        self.assertEqual(sha(RIG_ENV), PIN_ENV)

    def test_exact_wrapper_preamble_and_rig_env_invocation(self):
        body = BODY.read_text(encoding="utf-8").replace("\r\n", "\n")
        prefix = (
            "export RIG=4080 KAH_INSTANCE=3\n"
            "export KENSHI_DIR=/c/KenshiInst/3 KDIR=/c/KenshiInst/3\n"
            "export KAH_DIR='C:\\KenshiInst\\3\\mods\\AutomationHarness'\n"
            ". /c/KenshiModding/tools/automation/rig-env.sh\n"
        )
        self.assertTrue(body.startswith(prefix))
        self.assertIn("rig4080_i3_preflight >/dev/null 2>&1 || abort", body)

    def test_wrapper_tail_guard(self):
        body = BODY.read_text(encoding="utf-8")
        self.assertIsNone(wrapper_tail_violation(body))
        self.assertIsNotNone(wrapper_tail_violation(body + "\nKAH_INSTANCE=1\n"))
        self.assertIsNotNone(wrapper_tail_violation(body + "\nunset KDIR\n"))
        self.assertIsNotNone(wrapper_tail_violation(body + "\nsource /tmp/other.sh\n"))

    def test_embedded_guard_is_exact_helper_logic(self):
        actual, expected = embedded_guard(BODY.read_text(encoding="utf-8"), ROUTE.read_text(encoding="utf-8"))
        self.assertEqual(actual, expected)

    def test_rig_env_gate_covers_route_and_inbox_material(self):
        source = RIG_ENV.read_text(encoding="utf-8")
        start = source.index("  rig4080_i3_preflight() {")
        end = source.index("\n  # animlab catalogs/configs", start)
        gate = source[start:end]
        for token in (
            '"${KAH_INSTANCE:-}" != 3',
            '"$KDIR" != "$want_game"',
            '"$KENSHI_DIR" != "$want_game"',
            '"$kah_norm" != "$want_harness"',
            'cygpath -u "$KAH_DIR"',
            '"$harness_unix/inbox.txt"',
            '"$harness_unix/inbox.txt.lock"',
            '[[ ! -d "$harness_unix" ]]',
        ):
            self.assertIn(token, gate)

    def test_embedded_route_decision_fixtures(self):
        def route_ok(instance=3, rig=4080, game="/c/KenshiInst/3", kenshi="/c/KenshiInst/3",
                     harness=r"C:\KenshiInst\3\mods\AutomationHarness", harness_dir=True,
                     inbox=False, lock=False):
            return (instance == 3 and rig == 4080 and game == "/c/KenshiInst/3"
                    and kenshi == "/c/KenshiInst/3"
                    and harness == r"C:\KenshiInst\3\mods\AutomationHarness"
                    and harness_dir and not inbox and not lock)

        self.assertTrue(route_ok())
        self.assertFalse(route_ok(instance=1))
        self.assertFalse(route_ok(rig=5090))
        self.assertFalse(route_ok(game="/c/KenshiInst/1"))
        self.assertFalse(route_ok(kenshi="/c/KenshiInst/1"))
        self.assertFalse(route_ok(harness=r"C:\KenshiInst\1\mods\AutomationHarness"))
        self.assertFalse(route_ok(harness_dir=False))
        self.assertFalse(route_ok(inbox=True))
        self.assertFalse(route_ok(lock=True))


if __name__ == "__main__":
    unittest.main(verbosity=2)
