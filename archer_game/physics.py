"""Projectile physics and hit detection for the archer game.

All values are SI units in a world frame where +x points right, +y points up
and the ground is the line y = 0. Air resistance is ignored, so an arrow is an
ideal projectile:

    x(t) = x0 + v0 * cos(theta) * t
    y(t) = y0 + v0 * sin(theta) * t - 1/2 * g * t^2
    vx(t) = v0 * cos(theta)
    vy(t) = v0 * sin(theta) - g * t

The aiming line and the arrow in flight both come from `simulate`, so the
preview the player sees is exactly the path the arrow takes.
"""

from __future__ import annotations

import math
from dataclasses import dataclass, field

G = 9.81  # gravitational acceleration, m/s^2

HEAD = "head"
TORSO = "torso"
LEGS = "legs"

# Damage as a percentage of max HP.
DAMAGE = {HEAD: 50, TORSO: 20, LEGS: 10}


@dataclass(frozen=True)
class Vec:
    x: float
    y: float


def launch_velocity(speed: float, angle_deg: float, facing: int) -> Vec:
    """Initial velocity for a shot. `angle_deg` is the elevation above the
    horizontal in the direction the archer faces (`facing` is +1 or -1)."""
    a = math.radians(angle_deg)
    return Vec(facing * speed * math.cos(a), speed * math.sin(a))


def position(origin: Vec, v0: Vec, t: float, g: float = G) -> Vec:
    """Exact projectile position at time t."""
    return Vec(origin.x + v0.x * t, origin.y + v0.y * t - 0.5 * g * t * t)


def velocity(v0: Vec, t: float, g: float = G) -> Vec:
    return Vec(v0.x, v0.y - g * t)


def ground_time(origin: Vec, v0: Vec, g: float = G) -> float:
    """Positive time at which the projectile reaches y = 0 (exact root of
    y0 + vy*t - g*t^2/2 = 0)."""
    disc = v0.y * v0.y + 2.0 * g * origin.y
    return (v0.y + math.sqrt(max(disc, 0.0))) / g


def apex(origin: Vec, v0: Vec, g: float = G) -> Vec:
    """Highest point of the trajectory (the start point if fired downward)."""
    t = max(v0.y / g, 0.0)
    return position(origin, v0, t, g)


# --------------------------------------------------------------------------
# Hitboxes
# --------------------------------------------------------------------------

@dataclass(frozen=True)
class Circle:
    cx: float
    cy: float
    r: float

    def segment_hit(self, p0: Vec, p1: Vec) -> float | None:
        """Smallest s in [0, 1] where p0 + s*(p1 - p0) touches the circle."""
        dx, dy = p1.x - p0.x, p1.y - p0.y
        fx, fy = p0.x - self.cx, p0.y - self.cy
        c = fx * fx + fy * fy - self.r * self.r
        if c <= 0:
            return 0.0  # starts inside
        a = dx * dx + dy * dy
        if a == 0:
            return None
        b = 2 * (fx * dx + fy * dy)
        disc = b * b - 4 * a * c
        if disc < 0:
            return None
        s = (-b - math.sqrt(disc)) / (2 * a)
        return s if 0.0 <= s <= 1.0 else None


@dataclass(frozen=True)
class Rect:
    left: float
    bottom: float
    right: float
    top: float

    def segment_hit(self, p0: Vec, p1: Vec) -> float | None:
        """Liang-Barsky clip: smallest s in [0, 1] where the segment enters."""
        dx, dy = p1.x - p0.x, p1.y - p0.y
        s_min, s_max = 0.0, 1.0
        for p, q in (
            (-dx, p0.x - self.left),
            (dx, self.right - p0.x),
            (-dy, p0.y - self.bottom),
            (dy, self.top - p0.y),
        ):
            if p == 0:
                if q < 0:
                    return None
                continue
            r = q / p
            if p < 0:
                s_min = max(s_min, r)
            else:
                s_max = min(s_max, r)
            if s_min > s_max:
                return None
        return s_min


# Archer body proportions in metres, relative to the feet position.
HEIGHT = 1.8
HEAD_RADIUS = 0.15
HEAD_CENTER_Y = HEIGHT - HEAD_RADIUS  # 1.65
TORSO_BOTTOM = 0.9
TORSO_TOP = HEAD_CENTER_Y - HEAD_RADIUS  # 1.5, neck
TORSO_HALF_WIDTH = 0.2
LEGS_HALF_WIDTH = 0.17
BOW_OFFSET = Vec(0.35, 1.3)  # arrow nock point, in front of the chest


@dataclass
class Archer:
    x: float  # feet position on the ground
    facing: int  # +1 faces right, -1 faces left
    max_hp: int = 100
    hp: int = field(default=-1)

    def __post_init__(self) -> None:
        if self.hp < 0:
            self.hp = self.max_hp

    @property
    def alive(self) -> bool:
        return self.hp > 0

    def bow_position(self) -> Vec:
        return Vec(self.x + self.facing * BOW_OFFSET.x, BOW_OFFSET.y)

    def hitboxes(self) -> list[tuple[str, Circle | Rect]]:
        return [
            (HEAD, Circle(self.x, HEAD_CENTER_Y, HEAD_RADIUS)),
            (TORSO, Rect(self.x - TORSO_HALF_WIDTH, TORSO_BOTTOM,
                         self.x + TORSO_HALF_WIDTH, TORSO_TOP)),
            (LEGS, Rect(self.x - LEGS_HALF_WIDTH, 0.0,
                        self.x + LEGS_HALF_WIDTH, TORSO_BOTTOM)),
        ]

    def segment_hit(self, p0: Vec, p1: Vec) -> tuple[str, float] | None:
        """Earliest body part hit by segment p0->p1, with its parameter s."""
        best: tuple[str, float] | None = None
        for part, box in self.hitboxes():
            s = box.segment_hit(p0, p1)
            if s is not None and (best is None or s < best[1]):
                best = (part, s)
        return best

    def apply_hit(self, part: str) -> int:
        dmg = round(self.max_hp * DAMAGE[part] / 100)
        self.hp = max(0, self.hp - dmg)
        return dmg


# --------------------------------------------------------------------------
# Simulation
# --------------------------------------------------------------------------

@dataclass
class ShotResult:
    origin: Vec
    v0: Vec
    points: list[Vec]  # sampled path, ending at the impact point
    times: list[float]  # time of each point
    end_time: float
    impact: Vec
    part: str | None  # body part hit, None if the arrow missed

    @property
    def end_velocity(self) -> Vec:
        return velocity(self.v0, self.end_time)


def simulate(
    origin: Vec,
    v0: Vec,
    target: Archer,
    world_left: float,
    world_right: float,
    dt: float = 1 / 240,
) -> ShotResult:
    """Trace a shot until it hits `target`, the ground, or leaves the world.

    Points are taken from the exact closed-form solution every `dt` seconds;
    between samples the path is treated as a straight chord for collision
    tests. At dt = 1/240 s the chord deviates from the true parabola by at
    most g*dt^2/8 ~ 0.02 mm, far below the size of any hitbox.
    """
    t_ground = ground_time(origin, v0)
    points = [origin]
    times = [0.0]
    t = 0.0
    while True:
        t_next = min(t + dt, t_ground)
        p0, p1 = points[-1], position(origin, v0, t_next)

        hit = target.segment_hit(p0, p1)
        if hit is not None:
            part, s = hit
            t_hit = t + s * (t_next - t)
            impact = position(origin, v0, t_hit)
            points.append(impact)
            times.append(t_hit)
            return ShotResult(origin, v0, points, times, t_hit, impact, part)

        points.append(p1)
        times.append(t_next)
        t = t_next
        if t >= t_ground or not (world_left <= p1.x <= world_right):
            return ShotResult(origin, v0, points, times, t, p1, None)
