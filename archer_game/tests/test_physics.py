import math
import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from physics import (  # noqa: E402
    G, HEAD, LEGS, TORSO, Archer, Circle, Rect, Vec, apex, ground_time,
    launch_velocity, position, simulate,
)


class KinematicsTest(unittest.TestCase):
    def test_range_on_flat_ground_matches_formula(self):
        # R = v^2 sin(2θ) / g when launched from ground level.
        v, angle = 20.0, 37.0
        v0 = launch_velocity(v, angle, +1)
        t = ground_time(Vec(0, 0), v0)
        landing = position(Vec(0, 0), v0, t)
        expected = v * v * math.sin(math.radians(2 * angle)) / G
        self.assertAlmostEqual(landing.x, expected, places=9)
        self.assertAlmostEqual(landing.y, 0.0, places=9)

    def test_apex_height(self):
        v, angle = 15.0, 60.0
        v0 = launch_velocity(v, angle, +1)
        top = apex(Vec(0, 1.3), v0)
        expected = 1.3 + (v * math.sin(math.radians(angle))) ** 2 / (2 * G)
        self.assertAlmostEqual(top.y, expected, places=9)

    def test_facing_left_mirrors_x(self):
        r = launch_velocity(10, 30, +1)
        l = launch_velocity(10, 30, -1)
        self.assertAlmostEqual(r.x, -l.x)
        self.assertAlmostEqual(r.y, l.y)

    def test_ground_time_from_height_horizontal_shot(self):
        # Dropped from height h with no vertical speed: t = sqrt(2h/g).
        t = ground_time(Vec(0, 5.0), Vec(10, 0))
        self.assertAlmostEqual(t, math.sqrt(2 * 5.0 / G), places=12)


class HitboxTest(unittest.TestCase):
    def test_circle_segment(self):
        c = Circle(0, 0, 1)
        self.assertAlmostEqual(c.segment_hit(Vec(-2, 0), Vec(2, 0)), 0.25)
        self.assertIsNone(c.segment_hit(Vec(-2, 2), Vec(2, 2)))
        self.assertIsNone(c.segment_hit(Vec(-3, 0), Vec(-2, 0)))

    def test_rect_segment(self):
        r = Rect(0, 0, 1, 1)
        self.assertAlmostEqual(r.segment_hit(Vec(-1, 0.5), Vec(1, 0.5)), 0.5)
        self.assertIsNone(r.segment_hit(Vec(-1, 2), Vec(2, 2)))

    def test_damage_values(self):
        for part, dmg in ((HEAD, 50), (TORSO, 20), (LEGS, 10)):
            a = Archer(0, -1)
            self.assertEqual(a.apply_hit(part), dmg)
            self.assertEqual(a.hp, 100 - dmg)

    def test_hp_never_negative(self):
        a = Archer(0, -1, hp=30)
        a.apply_hit(HEAD)
        self.assertEqual(a.hp, 0)
        self.assertFalse(a.alive)


class SimulateTest(unittest.TestCase):
    def _shot_through(self, target_point: Vec, target: Archer, angle: float):
        """Solve for the launch speed that passes through target_point."""
        origin = Vec(2.0, 1.3)
        dx = target_point.x - origin.x
        dy = target_point.y - origin.y
        a = math.radians(angle)
        # y = x tanθ - g x^2 / (2 v^2 cos^2θ)  ->  solve for v
        v = math.sqrt(G * dx * dx / (2 * math.cos(a) ** 2 * (dx * math.tan(a) - dy)))
        return simulate(origin, launch_velocity(v, angle, +1), target, -5, 40)

    def test_aimed_at_head_is_headshot(self):
        target = Archer(20.0, -1)
        res = self._shot_through(Vec(20.0, 1.65), target, 30)
        self.assertEqual(res.part, HEAD)

    def test_aimed_at_chest_is_torso(self):
        target = Archer(20.0, -1)
        res = self._shot_through(Vec(20.0, 1.2), target, 25)
        self.assertEqual(res.part, TORSO)

    def test_aimed_at_knee_is_legs(self):
        target = Archer(20.0, -1)
        res = self._shot_through(Vec(20.0, 0.5), target, 20)
        self.assertEqual(res.part, LEGS)

    def test_short_shot_lands_on_ground(self):
        target = Archer(20.0, -1)
        res = simulate(Vec(2, 1.3), launch_velocity(8, 30, +1), target, -5, 40)
        self.assertIsNone(res.part)
        self.assertAlmostEqual(res.impact.y, 0.0, places=9)

    def test_impact_lies_on_exact_parabola(self):
        target = Archer(20.0, -1)
        res = self._shot_through(Vec(20.0, 1.2), target, 25)
        exact = position(res.origin, res.v0, res.end_time)
        self.assertAlmostEqual(res.impact.x, exact.x, places=12)
        self.assertAlmostEqual(res.impact.y, exact.y, places=12)


if __name__ == "__main__":
    unittest.main()
