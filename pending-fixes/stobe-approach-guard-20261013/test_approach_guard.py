import unittest

from approach_guard import (Leg, PositionSnapshot, guarded_approach,
                            walktime_arguments)


class GuardTests(unittest.TestCase):
    def run_guard(self, samples, **kwargs):
        pending = iter(samples)
        issued = []

        def read():
            return next(pending)

        result = guarded_approach(read, issued.append,
                                  expected_player_id="player:1/1",
                                  expected_target_id="npc:42/3",
                                  clock=lambda: 100.0, **kwargs)
        return result, issued

    @staticmethod
    def snap(target_x, *, target_id="npc:42/3", captured=99.5,
             player_x=0.0, player_id="player:1/1"):
        return PositionSnapshot(player_id, target_id, player_x, 0.0, 0.0,
                                target_x, 0.0, 0.0, captured - 0.5, captured)

    def test_in_range_boundary_values_emit_zero_legs(self):
        for raw_distance in (57.0, 79.9, 80.0):
            with self.subTest(raw_distance=raw_distance):
                result, issued = self.run_guard([self.snap(raw_distance)])
                self.assertEqual((result.status, result.legs), ("IN_RANGE", 0))
                self.assertEqual(issued, [])

    def test_just_outside_boundary_produces_one_bounded_leg(self):
        result, issued = self.run_guard([self.snap(80.1), self.snap(79.0)])
        self.assertEqual((result.status, result.legs), ("IN_RANGE", 1))
        self.assertEqual(len(issued), 1)
        self.assertGreaterEqual(issued[0].distance, 2.0)

    def test_rechecks_and_stops_when_target_enters_radius_between_legs(self):
        result, issued = self.run_guard([self.snap(250.0), self.snap(75.0)])
        self.assertEqual((result.status, result.legs), ("IN_RANGE", 1))
        self.assertEqual(len(issued), 1)
        self.assertLessEqual(issued[0].distance, 100.0)

    def test_target_identity_change_aborts_before_next_leg(self):
        result, issued = self.run_guard([
            self.snap(250.0), self.snap(240.0, target_id="npc:99/1")])
        self.assertEqual(result.status, "ABORT")
        self.assertIn("target identity", result.reason)
        self.assertEqual(len(issued), 1)

    def test_stale_snapshot_aborts_without_leg(self):
        result, issued = self.run_guard([self.snap(250.0, captured=90.0)])
        self.assertEqual(result.status, "ABORT")
        self.assertIn("stale", result.reason)
        self.assertEqual(issued, [])

    def test_delayed_first_position_read_makes_pair_stale(self):
        snapshot = PositionSnapshot("player:1/1", "npc:42/3", 0.0, 0.0, 0.0,
                                    250.0, 0.0, 0.0, 97.0, 99.5)
        result, issued = self.run_guard([snapshot])
        self.assertEqual(result.status, "ABORT")
        self.assertIn("acquisition", result.reason)
        self.assertEqual(issued, [])

    def test_missing_snapshot_aborts_without_leg(self):
        result, issued = self.run_guard([None])
        self.assertEqual(result.status, "ABORT")
        self.assertIn("missing or malformed", result.reason)
        self.assertEqual(issued, [])

    def test_vertical_distance_participates_in_stop_gate(self):
        snapshot = PositionSnapshot("player:1/1", "npc:42/3", 0.0, 0.0, 0.0,
                                    0.0, 57.0, 0.0, 99.0, 99.5)
        result, issued = self.run_guard([snapshot])
        self.assertEqual((result.status, result.legs), ("IN_RANGE", 0))
        self.assertEqual(issued, [])

    def test_walktime_tokens_are_bounded_and_non_executing(self):
        self.assertEqual(walktime_arguments(Leg("x", 1, 206.0)),
                         ["walktime", "@player", "206", "+x", "walk"])
        with self.assertRaises(ValueError):
            walktime_arguments(Leg("x", 1, 501.0))

    def test_no_horizontal_vector_aborts_without_leg(self):
        snapshot = PositionSnapshot("player:1/1", "npc:42/3", 0.0, 0.0, 0.0,
                                    0.0, 100.0, 0.0, 99.0, 99.5)
        result, issued = self.run_guard([snapshot])
        self.assertEqual(result.status, "ABORT")
        self.assertIn("horizontal", result.reason)
        self.assertEqual(issued, [])

    def test_each_leg_is_fresh_bounded_and_revalidated(self):
        result, issued = self.run_guard([
            self.snap(500.0), self.snap(400.0), self.snap(300.0),
            self.snap(200.0), self.snap(79.0)], max_leg=100.0)
        self.assertEqual((result.status, result.legs), ("IN_RANGE", 4))
        self.assertTrue(all(0 < leg.distance <= 100.0 for leg in issued))


if __name__ == "__main__":
    unittest.main(verbosity=2)
