# Forge Thy Doctrine - Instrument of Ege (Godot 4.4 prototype)

A playable vertical slice of the design document in `docs/Forge_Thy_Doctrine.md`
(solo-dev, PC, Godot 4.4, GDScript). It covers **roadmap steps 1-3 in single player**:
the ship editor, a Newtonian flight model, module/power/damage systems, bots and a team
deathmatch. Multiplayer (step 4+) is not implemented.

## Run
1. Install Godot **4.4.x** (standard build).
2. Open this folder as a project and press F5 (or `godot --path .`).

## Play
Main menu -> **SinglePlayer**: *Freematch* (team deathmatch vs bots), *Sandbox/Tutorial* (test range).
Main menu -> **Creation -> Ship creation**: the Ship Forge.

### Flight / command controls
| Key | Action |
|---|---|
| W / S, A / D, Space / C(Ctrl) | thrust forward-back, strafe, up-down |
| Q / E | roll |
| Arrow keys (or mouse in first person) | pitch / yaw |
| LMB | fire all linked barrels (locked target = lead aiming) |
| RMB drag, wheel | orbit / zoom commander camera |
| V | first person (from the Commander Post) / commander view |
| Tab | free cursor, T lock target, X assisted/manual flight, Z brake, Esc pause |

The console is a black-iron and ember-orange command board laid out like the mock-up: Panel 3 (modules, with category tabs) bottom-left, round Panel 4 (true 3D radar: drag to rotate, wheel for range), Panel 2 (modes) bottom-centre, round Panel 5 (Objectives / Log tabs), Panel 1 (live 3D ship model with Basic 3D / Exploded / Onion tabs, gauges, telemetry) bottom-right. Clicking a mode opens Sub Panel 2 above Panel 2; click it again to close. `UI_SCALE` in `scripts/arena/hud.gd` resizes the whole cluster.
All 11 modes are listed; modes that depend on unimplemented systems say what they need.

### Ship editor
Steps: **Hull -> Modules -> Links -> Interior -> Cosmetics -> Test**.
* Hull: 8-point rings lofted into a closed hull. Drag vertices, mirror symmetry (X), soft selection,
  loop cut, extrude, scale, round, thickness. Snap and camera adapt to ship size.
* Modules: Commander Post, Generator, Engine Room, Turret Bay, Radar Room (internal/external rules enforced),
  Thruster, Barrel (kinetic / laser / missile). Resize with a red *minimum size* outline, facing, mirror copy.
* Links: Commander -> Engine/Turret/Radar, Engine -> Thruster, Turret -> Barrel (or auto-link).
* Permanent stat panel: class from size only, mass, cost vs team budget, power, acceleration, polygon budget,
  and a live legality list. A ship must be fully legal to be saved or tested. Undo/redo, autosave drafts.
* Saves are JSON in `user://ships` (shown in the menu).

## What is implemented vs the design doc
| Doc area | Status |
|---|---|
| 1 Ship creation: hull editing, modules, links, stats panel, legality, prefabs, undo | done (simplified: ring-loft hull, no interior) |
| 1.4 Interior (corridors, doors, stairs) | not implemented (roadmap step 6) |
| 2 Systems: power priority, thrusters + engine rooms, RCS 10%, gyro (torque ~ 1/mass) | done |
| 3 Modes: Freematch (TDM) / Tutorial / Sandbox | done (Campaign, multiplayer: no) |
| 4 Command: commander + first-person camera, console panels, radar, movement orders | done (Defense, Comms, Crew, Boarding, Hangar, AI modes listed but inert) |
| 6 Damage: hull armor vs penetration, spatial module damage, ramming, 30 s shake lockout, commander-post death | done (no crew, repair, fires, breaches) |
| Weapons: kinetic, laser, missiles (homing) | done; flak, mines, ammo bays: no |
| 7 Tech: compound convex collision, no render tricks | done; floating origin / very large ships: no |
| Multiplayer (lobby, netcode, community sharing) | not implemented |

Design simplifications you may want to revisit are noted in the code (e.g. forces are applied centrally -
the gyro cancels thruster torque for free - and modules have no collision of their own).

## Tests
```
godot --headless --path . --script res://tests/run_tests.gd
godot --headless --path . --script res://tests/arena_test.gd -- freematch 40
```
`tests/shot.gd` renders a scene to a PNG (needs a display: `xvfb-run ... --rendering-driver opengl3`).

## Layout
* `scripts/ship/` data model (`ship_data.gd`), live ship (`ship.gd`), projectiles, premade ships
* `scripts/editor/` ship forge, `scripts/arena/` arena + HUD + camera, `scripts/ai/` bots/autopilot
* `scripts/autoload/game.gd` input map and ship library
