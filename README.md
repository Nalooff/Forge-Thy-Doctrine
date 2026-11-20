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
Steps (chevron timeline at the bottom): **Hull -> Modules -> Links -> Interior -> Cosmetics -> Test**.
Top bars: Save/Undo/Redo/Load, view settings (Full/X-ray/Wireframe, Perspective/Orthogonal, Camera), Export/Import. Second bar: **Type / Modifier / Helper** buttons open their tool tab on the left, the dropdown next to each picks which one (e.g. Type: Vertex or Ring). Load opens a popup: *Load as new ship (prefab)* leaves the prefab untouched on Save, *Modify this ship* overwrites it.
* Hull: 8-point rings lofted into a closed hull. Drag vertices, mirror symmetry (X), soft selection,
  loop cut, extrude, scale, round, thickness. Snap and camera adapt to ship size.
* Modules: Commander Post, Generator, Engine Room, Turret Bay, Radar Room (internal/external rules enforced),
  Thruster, Barrel (kinetic / laser / missile). Resize with a red *minimum size* outline, facing, mirror copy.
* Links: Commander -> Engine/Turret/Radar, Engine -> Thruster, Turret -> Barrel (or auto-link).
* Permanent stat panel: class from size only, mass, cost vs team budget, power, acceleration, polygon budget,
  and a live legality list. A ship must be fully legal to be saved or tested. Undo/redo, autosave drafts.
* Saves are JSON in `user://ships` (shown in the menu).

## Modules (current)
Commander Post, Generator, Engine Room, Radar Room, Thruster, Barrel, plus the two turret modules:
* **Turret Bay** (external): rotates the barrels that physically **touch** it, as one body, so aiming stays consistent.
  It slews toward the aim point (or the lead point of a locked target) within a 75 degree cone, and a barrel will not fire
  into its own hull.
* **Turret Control** (internal): can be linked to **any** barrel, but those barrels stay fixed (aim by pointing the ship).

## Game modes (Freematch)
Team Deathmatch (respawns, kill limit), Team Elimination (one life, last team standing), Deathmatch (free for all).
Zone Control and Base Defense are not implemented.

## Coverage of the base design doc
| Base GDD area | Status |
|---|---|
| Ship creation: 5-step timeline, hull loft, loop cut, extrude, soft selection, mirror + centerline lock, history/undo, rulers (stat panel), grid snapping that adapts to size | done (ring-loft hull) |
| View modifier: shaded / X-ray / wireframe + front, rear, side, top, perspective viewpoints | done |
| Auto-Hull on invalid internal placement + hull clearance X slider | done |
| Bevel/fillet (ring "round"), solidify (thickness) | partial |
| Boolean ops, array mesh, curve deform, SubD, bridge loops, weld, blend surface, cross-section slices | not implemented |
| Interior step (corridors, doors, stairs, ladders), stowage props, decals, camo | not implemented (colors only) |
| Internal modules: Generator, Engine Room, Radar Room, Turret Control | done |
| Internal modules: Defense Bay, Communication Room | not implemented |
| External modules: Commander Post, Thruster, Barrel, Turret Bay | done |
| External modules: Communication Dish, Breach Doors, Breach Pods, Hangar | not implemented |
| Hidden systems: Electricity (priority by distance), RCS (10%), Gyro (1/mass), Radar | done |
| Hidden systems: Heat, Oxygen, Crew, AI cores, Communication | not implemented |
| Module links and damage propagation (Commander -> Engine/Turret/Radar, Engine -> Thruster, Bay/Control -> Barrel) | done |
| Main menu (Multi Player / Single Player / Creation / Other with connector lines, last loaded ship) | done (Join/Host are info stubs) |
| Multiplayer lobby, GameLobby interface, voice-to-text chat | not implemented |
| Modes: Team Elimination, Team Deathmatch, Deathmatch | done (solo vs bots) |
| Modes: Zone Control, Base Defense; the 30+ maps and their effects | not implemented (one asteroid arena) |
| Controls: commander + first-person views, free-float cursor, damage flash + 30 s shake lockout | done |
| Top ticker with comms/crew icons | partial (plain ticker) |
| Console panels 1-5 incl. Exploded / Onion Slice 3D model, category tabs, 3D radar, objectives/log toggle | done; Combat/Movement sub-panels simplified; Crew Command, Defense, Boarding, Hangar listed but inert |

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
