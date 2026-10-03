# Archer Duel

Two-player, turn-based archery game built on real projectile motion.

## Run

```bash
pip install -r requirements.txt
python main.py
```

## How to play

Players take turns shooting at each other. A dotted **aiming line** shows the exact path of the arrow. Its color tells you what it will hit: red = head, orange = torso, yellow = legs, white = miss. First player to reach 0 HP loses.

| Hit   | Damage (of max HP) |
|-------|--------------------|
| Head  | 50% (critical)     |
| Torso | 20%                |
| Legs  | 10%                |

**Controls**

- **Mouse:** click, drag backwards like pulling a bowstring, release to shoot. Drag direction sets the angle, drag length sets the speed.
- **Up / Down:** angle ±1° (hold Shift for ±0.1°)
- **Left / Right:** speed ±0.5 m/s (hold Shift for ±0.1 m/s)
- **Space:** shoot · **H:** show hitboxes · **R:** restart · **Esc:** quit

## Physics

The world uses SI units (1 m = 40 px) with g = 9.81 m/s² and no air resistance:

```
x(t) = x0 + v0·cos(θ)·t
y(t) = y0 + v0·sin(θ)·t − ½·g·t²
```

Positions come from this closed-form solution, not from frame-by-frame integration, so the frame rate doesn't affect accuracy. The ground impact time is solved exactly from the quadratic. Hit detection tests each 1/240 s chord of the parabola against the hitboxes (circle for the head, rectangles for torso and legs). The chord differs from the true curve by less than 0.02 mm. The aiming line and the arrow in flight use the same `simulate()` call, so the preview always matches the real shot.

## Tests

```bash
python -m unittest discover -s tests
```
