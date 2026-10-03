"""Archer Duel: a two-player, turn-based projectile-motion game.

Run:  python main.py

Controls (current player):
  Mouse     click and drag backwards (like pulling a bowstring), release to shoot
  Up/Down   adjust elevation angle by 1 deg (hold Shift for 0.1 deg)
  Left/Right adjust launch speed by 0.5 m/s (hold Shift for 0.1 m/s)
  Space     shoot
  H         show/hide hitboxes
  R         restart
  Esc       quit
"""

from __future__ import annotations

import math
import random
import sys

import pygame

from physics import (
    DAMAGE, G, HEAD, HEAD_CENTER_Y, HEAD_RADIUS, LEGS, TORSO,
    TORSO_BOTTOM, TORSO_TOP, Archer, ShotResult, Vec, apex, launch_velocity,
    simulate,
)

# ---------------------------------------------------------------- settings
WIDTH, HEIGHT = 1200, 700
FPS = 60
PPM = 40  # pixels per metre
GROUND_Y = HEIGHT - 80  # screen y of world y = 0
WORLD_W = WIDTH / PPM  # 30 m
WORLD_LEFT, WORLD_RIGHT = -1.0, WORLD_W + 1.0

MIN_SPEED, MAX_SPEED = 5.0, 30.0  # m/s
DRAG_PX_PER_MS = 6.0  # mouse drag pixels per 1 m/s of launch speed
ARROW_LEN = 0.75  # metres
TURN_DELAY = 1.4  # seconds between impact and next turn

SKY_TOP = (120, 170, 230)
SKY_BOTTOM = (200, 225, 245)
GROUND = (86, 125, 70)
DIRT = (110, 85, 60)
WHITE = (255, 255, 255)
BLACK = (20, 20, 25)
P_COLORS = [(40, 90, 200), (200, 50, 50)]
PART_COLORS = {HEAD: (255, 60, 60), TORSO: (255, 170, 40), LEGS: (255, 230, 80)}


def to_screen(p: Vec) -> tuple[int, int]:
    return round(p.x * PPM), round(GROUND_Y - p.y * PPM)


def to_world(sx: float, sy: float) -> Vec:
    return Vec(sx / PPM, (GROUND_Y - sy) / PPM)


# ---------------------------------------------------------------- game
class Game:
    def __init__(self) -> None:
        pygame.init()
        pygame.display.set_caption("Archer Duel - Projectile Motion")
        self.screen = pygame.display.set_mode((WIDTH, HEIGHT))
        self.clock = pygame.time.Clock()
        self.font = pygame.font.SysFont("consolas,dejavusansmono,monospace", 18)
        self.big = pygame.font.SysFont("arial,dejavusans", 48, bold=True)
        self.mid = pygame.font.SysFont("arial,dejavusans", 26, bold=True)
        self.background = self._make_background()
        self.show_hitboxes = False
        self.reset()

    def reset(self) -> None:
        # Small random spread in spacing so each match plays differently.
        left = 3.0 + random.uniform(0, 2)
        right = WORLD_W - 3.0 - random.uniform(0, 2)
        self.archers = [Archer(left, +1), Archer(right, -1)]
        self.aim = [[45.0, 18.0], [45.0, 18.0]]  # [angle deg, speed m/s]
        self.turn = 0
        self.state = "aiming"  # aiming | flying | result | over
        self.shot: ShotResult | None = None
        self.flight_t = 0.0
        self.result_timer = 0.0
        self.message = ""
        self.message_color = WHITE
        self.stuck_arrows: list[tuple[Vec, Vec]] = []  # (tip, direction)
        self.drag_start: tuple[int, int] | None = None
        self.preview = self._compute_preview()

    # ------------------------------------------------------------ helpers
    @property
    def shooter(self) -> Archer:
        return self.archers[self.turn]

    @property
    def target(self) -> Archer:
        return self.archers[1 - self.turn]

    def _compute_preview(self) -> ShotResult:
        angle, speed = self.aim[self.turn]
        v0 = launch_velocity(speed, angle, self.shooter.facing)
        return simulate(self.shooter.bow_position(), v0, self.target,
                        WORLD_LEFT, WORLD_RIGHT)

    def _set_aim(self, angle: float, speed: float) -> None:
        angle = max(-45.0, min(89.9, angle))
        speed = max(MIN_SPEED, min(MAX_SPEED, speed))
        self.aim[self.turn] = [angle, speed]
        self.preview = self._compute_preview()

    def _aim_from_drag(self, mouse: tuple[int, int]) -> bool:
        sx, sy = self.drag_start
        dx, dy = sx - mouse[0], mouse[1] - sy  # pull back; screen y is down
        length = math.hypot(dx, dy)
        if length < 8:
            return False
        angle = math.degrees(math.atan2(dy, dx * self.shooter.facing))
        self._set_aim(angle, length / DRAG_PX_PER_MS)
        return True

    def shoot(self) -> None:
        self.shot = self.preview
        self.flight_t = 0.0
        self.state = "flying"

    def _finish_shot(self) -> None:
        shot = self.shot
        v = shot.end_velocity
        n = math.hypot(v.x, v.y) or 1.0
        self.stuck_arrows.append((shot.impact, Vec(v.x / n, v.y / n)))
        if shot.part is None:
            self.message, self.message_color = "Miss!", WHITE
        else:
            dmg = self.target.apply_hit(shot.part)
            if shot.part == HEAD:
                self.message = f"CRITICAL HEADSHOT!  -{dmg} HP"
            else:
                self.message = f"{shot.part.capitalize()} hit  -{dmg} HP"
            self.message_color = PART_COLORS[shot.part]
        if not self.target.alive:
            self.state = "over"
            self.message = f"Player {self.turn + 1} wins!"
            self.message_color = P_COLORS[self.turn]
        else:
            self.state = "result"
            self.result_timer = TURN_DELAY

    # ------------------------------------------------------------ loop
    def run(self) -> None:
        while True:
            dt = self.clock.tick(FPS) / 1000.0
            self.handle_events()
            self.update(dt)
            self.draw()
            pygame.display.flip()

    def handle_events(self) -> None:
        for e in pygame.event.get():
            if e.type == pygame.QUIT or (e.type == pygame.KEYDOWN and e.key == pygame.K_ESCAPE):
                pygame.quit()
                sys.exit()
            if e.type == pygame.KEYDOWN:
                if e.key == pygame.K_r:
                    self.reset()
                elif e.key == pygame.K_h:
                    self.show_hitboxes = not self.show_hitboxes
                elif self.state == "aiming":
                    fine = e.mod & pygame.KMOD_SHIFT
                    angle, speed = self.aim[self.turn]
                    da, dv = (0.1, 0.1) if fine else (1.0, 0.5)
                    if e.key == pygame.K_UP:
                        self._set_aim(angle + da, speed)
                    elif e.key == pygame.K_DOWN:
                        self._set_aim(angle - da, speed)
                    elif e.key == pygame.K_RIGHT:
                        self._set_aim(angle, speed + dv)
                    elif e.key == pygame.K_LEFT:
                        self._set_aim(angle, speed - dv)
                    elif e.key == pygame.K_SPACE:
                        self.shoot()
            if self.state != "aiming":
                self.drag_start = None
                continue
            if e.type == pygame.MOUSEBUTTONDOWN and e.button == 1:
                self.drag_start = e.pos
            elif e.type == pygame.MOUSEMOTION and self.drag_start:
                self._aim_from_drag(e.pos)
            elif e.type == pygame.MOUSEBUTTONUP and e.button == 1 and self.drag_start:
                if self._aim_from_drag(e.pos):
                    self.shoot()
                self.drag_start = None

    def update(self, dt: float) -> None:
        if self.state == "flying":
            self.flight_t += dt
            if self.flight_t >= self.shot.end_time:
                self._finish_shot()
        elif self.state == "result":
            self.result_timer -= dt
            if self.result_timer <= 0:
                self.turn = 1 - self.turn
                self.state = "aiming"
                self.message = ""
                self.preview = self._compute_preview()

    # ------------------------------------------------------------ drawing
    def _make_background(self) -> pygame.Surface:
        bg = pygame.Surface((WIDTH, HEIGHT))
        for y in range(GROUND_Y):
            k = y / GROUND_Y
            c = [round(a + (b - a) * k) for a, b in zip(SKY_TOP, SKY_BOTTOM)]
            pygame.draw.line(bg, c, (0, y), (WIDTH, y))
        pygame.draw.rect(bg, DIRT, (0, GROUND_Y, WIDTH, HEIGHT - GROUND_Y))
        pygame.draw.rect(bg, GROUND, (0, GROUND_Y, WIDTH, 10))
        # distance ruler every 5 m
        f = pygame.font.SysFont("consolas,dejavusansmono,monospace", 14)
        for m in range(0, int(WORLD_W) + 1):
            x = m * PPM
            h = 10 if m % 5 == 0 else 4
            pygame.draw.line(bg, (60, 45, 30), (x, GROUND_Y + 12), (x, GROUND_Y + 12 + h))
            if m % 5 == 0:
                bg.blit(f.render(f"{m}m", True, (230, 220, 200)), (x + 2, GROUND_Y + 24))
        return bg

    def draw(self) -> None:
        s = self.screen
        s.blit(self.background, (0, 0))

        for tip, d in self.stuck_arrows:
            self._draw_arrow(tip, d, (90, 60, 30))

        for i, a in enumerate(self.archers):
            self._draw_archer(a, P_COLORS[i], i == self.turn and self.state == "aiming")

        if self.state == "aiming":
            self._draw_preview()
        elif self.state == "flying":
            self._draw_flight()

        self._draw_hud()

    def _draw_archer(self, a: Archer, color, active: bool) -> None:
        s = self.screen
        f = a.facing
        head = to_screen(Vec(a.x, HEAD_CENTER_Y))
        neck = to_screen(Vec(a.x, TORSO_TOP))
        hip = to_screen(Vec(a.x, TORSO_BOTTOM))
        shoulder = to_screen(Vec(a.x, 1.4))
        bow = a.bow_position()
        bow_s = to_screen(bow)
        alive = a.alive
        col = color if alive else (110, 110, 110)

        # legs
        for side in (-1, 1):
            pygame.draw.line(s, col, hip, to_screen(Vec(a.x + side * 0.17, 0)), 6)
        # torso
        pygame.draw.line(s, col, neck, hip, 9)
        # arms: front arm to bow, back arm to string
        pygame.draw.line(s, col, shoulder, bow_s, 5)
        pygame.draw.line(s, col, shoulder, to_screen(Vec(a.x + f * 0.05, 1.3)), 5)
        # head
        pygame.draw.circle(s, (240, 200, 160) if alive else (150, 150, 150),
                           head, round(HEAD_RADIUS * PPM))
        pygame.draw.circle(s, col, head, round(HEAD_RADIUS * PPM), 2)

        # bow, oriented with the current aim for the active archer
        if a is self.shooter and self.state == "aiming":
            ang = math.radians(self.aim[self.turn][0])
        else:
            ang = math.radians(20)
        dirx, diry = f * math.cos(ang), math.sin(ang)
        px, py = -diry, dirx  # perpendicular
        r = 0.55
        pts = []
        for k in range(13):
            t = -math.pi / 2 + math.pi * k / 12
            pts.append(to_screen(Vec(bow.x + 0.18 * math.cos(t) * dirx + r * math.sin(t) * px,
                                     bow.y + 0.18 * math.cos(t) * diry + r * math.sin(t) * py)))
        pygame.draw.lines(s, (120, 70, 20), False, pts, 4)
        pygame.draw.line(s, (230, 230, 230), pts[0], pts[-1], 1)

        if active:
            top = to_screen(Vec(a.x, 2.15))
            pygame.draw.polygon(s, color, [(top[0] - 8, top[1] - 12),
                                           (top[0] + 8, top[1] - 12), top])

        if self.show_hitboxes:
            for part, box in a.hitboxes():
                c = PART_COLORS[part]
                if part == HEAD:
                    pygame.draw.circle(s, c, to_screen(Vec(box.cx, box.cy)),
                                       round(box.r * PPM), 1)
                else:
                    l, t = to_screen(Vec(box.left, box.top))
                    r_, b = to_screen(Vec(box.right, box.bottom))
                    pygame.draw.rect(s, c, (l, t, r_ - l, b - t), 1)

    def _draw_arrow(self, tip: Vec, d: Vec, color=(60, 40, 20)) -> None:
        tail = Vec(tip.x - d.x * ARROW_LEN, tip.y - d.y * ARROW_LEN)
        ts, ta = to_screen(tip), to_screen(tail)
        pygame.draw.line(self.screen, color, ta, ts, 3)
        # arrowhead
        ang = math.atan2(-(ts[1] - ta[1]), ts[0] - ta[0])
        for side in (-1, 1):
            a = ang + math.pi + side * 0.45
            pygame.draw.line(self.screen, (80, 80, 90), ts,
                             (ts[0] + 10 * math.cos(a), ts[1] - 10 * math.sin(a)), 3)
        # fletching
        for side in (-1, 1):
            a = ang + math.pi + side * 0.6
            pygame.draw.line(self.screen, (230, 230, 230), ta,
                             (ta[0] + 8 * math.cos(a), ta[1] - 8 * math.sin(a)), 2)

    def _draw_preview(self) -> None:
        p = self.preview
        color = PART_COLORS[p.part] if p.part else WHITE
        # dotted line: one dot every 0.04 s of flight time
        last = -1.0
        for pt, t in zip(p.points, p.times):
            if t - last >= 0.04:
                pygame.draw.circle(self.screen, color, to_screen(pt), 2)
                last = t
        end = to_screen(p.impact)
        pygame.draw.circle(self.screen, color, end, 6, 2)
        if p.part:
            label = "HEAD (CRIT)" if p.part == HEAD else p.part.upper()
            txt = self.font.render(f"{label} -{DAMAGE[p.part]}%", True, color)
            self.screen.blit(txt, (end[0] - txt.get_width() // 2, end[1] - 50))
        # apex marker
        top = apex(p.origin, p.v0)
        if top.y > p.origin.y + 0.05:
            ts = to_screen(top)
            pygame.draw.line(self.screen, (255, 255, 255), (ts[0] - 5, ts[1]), (ts[0] + 5, ts[1]), 1)
        # arrow nocked on bow
        n = math.hypot(p.v0.x, p.v0.y)
        self._draw_arrow(Vec(p.origin.x + p.v0.x / n * 0.3, p.origin.y + p.v0.y / n * 0.3),
                         Vec(p.v0.x / n, p.v0.y / n))
        if self.drag_start:
            pygame.draw.line(self.screen, (255, 255, 255), self.drag_start,
                             pygame.mouse.get_pos(), 1)

    def _draw_flight(self) -> None:
        shot = self.shot
        t = min(self.flight_t, shot.end_time)
        # faint trail of the path flown so far
        for pt, pt_t in zip(shot.points[::6], shot.times[::6]):
            if pt_t > t:
                break
            pygame.draw.circle(self.screen, (255, 255, 255), to_screen(pt), 1)
        o, v0 = shot.origin, shot.v0
        pos = Vec(o.x + v0.x * t, o.y + v0.y * t - 0.5 * G * t * t)
        vx, vy = v0.x, v0.y - G * t
        n = math.hypot(vx, vy) or 1.0
        self._draw_arrow(pos, Vec(vx / n, vy / n))

    def _draw_hud(self) -> None:
        s = self.screen
        for i, a in enumerate(self.archers):
            w, h = 360, 26
            x = 20 if i == 0 else WIDTH - 20 - w
            y = 20
            pygame.draw.rect(s, (40, 40, 40), (x - 2, y - 2, w + 4, h + 4), border_radius=6)
            frac = a.hp / a.max_hp
            bar_col = (60, 200, 80) if frac > 0.5 else (230, 190, 40) if frac > 0.2 else (220, 50, 50)
            pygame.draw.rect(s, (80, 30, 30), (x, y, w, h), border_radius=5)
            if a.hp > 0:
                pygame.draw.rect(s, bar_col, (x, y, round(w * frac), h), border_radius=5)
            label = self.font.render(f"P{i + 1}  {a.hp}/{a.max_hp} HP", True, WHITE)
            s.blit(label, (x + 10, y + 3))
            if i == self.turn and self.state in ("aiming", "flying", "result"):
                pygame.draw.rect(s, P_COLORS[i], (x - 5, y - 5, w + 10, h + 10), 3, border_radius=8)

        if self.state == "aiming":
            angle, speed = self.aim[self.turn]
            p = self.preview
            top = apex(p.origin, p.v0)
            lines = [
                f"Player {self.turn + 1}'s turn",
                f"Angle  {angle:6.1f} deg   Speed {speed:5.1f} m/s",
                f"vx {abs(p.v0.x):5.2f} m/s  vy {p.v0.y:5.2f} m/s  g = {G} m/s^2",
                f"Max height {top.y:5.2f} m   Flight time {p.end_time:4.2f} s",
            ]
            for k, line in enumerate(lines):
                txt = self.font.render(line, True, BLACK)
                s.blit(txt, (WIDTH // 2 - txt.get_width() // 2, 60 + k * 22))
            hint = self.font.render(
                "Drag mouse back & release to shoot | Arrows: aim (Shift = fine) | Space: shoot | H: hitboxes",
                True, (40, 40, 60))
            s.blit(hint, (WIDTH // 2 - hint.get_width() // 2, HEIGHT - 26))

        if self.message:
            font = self.big if self.state == "over" else self.mid
            txt = font.render(self.message, True, self.message_color)
            shadow = font.render(self.message, True, BLACK)
            pos = (WIDTH // 2 - txt.get_width() // 2, 200)
            s.blit(shadow, (pos[0] + 2, pos[1] + 2))
            s.blit(txt, pos)
            if self.state == "over":
                sub = self.mid.render("Press R to play again", True, BLACK)
                s.blit(sub, (WIDTH // 2 - sub.get_width() // 2, 270))


if __name__ == "__main__":
    Game().run()
