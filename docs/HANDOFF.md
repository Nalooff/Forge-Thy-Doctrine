# Forge Thy Doctrine - handoff

Where the project stands, what was being done when this chat stopped, and where it was going.
Engine: Godot 4.4.1 (GDScript). Design doc: `docs/Forge_Thy_Doctrine.md`. Per-feature status list: `docs/STATUS.md`.

## How to work on it
- Open the folder in Godot 4.4. Run tests headless: `godot --headless --path . --script res://tests/<name>.gd`
  (`run_tests`, `editor_ui_test`, `waypoint_test`, `weapons_test`, `tuner_test`, `preview_test`, `heat_test`,
  `interior_test`, `network_test`, `world_test`, `scale_test`, `menu_test`, `editor_scale_test`).
- A few checks need a real renderer (the headless one keeps no MultiMesh data): run the same script with
  `xvfb-run -a godot --rendering-driver opengl3 --script res://tests/scale_test.gd`.
- Benchmark: `tests/bench_ship.gd` (physics frame cost by module count). Screenshots: `tests/*_shot.gd` (need xvfb).
- After adding a `class_name` script run `godot --headless --path . --import` once.
- Nothing was pushed to GitHub (no credentials in the sandbox): the commits are in the `.git` folder of the zip.

## What was built in this session (newest last)
1. **Panel 1 ship model** (`scripts/arena/ship_preview.gd`): glass hull with modules inside + hover/click info cards,
   real exploded view, onion deck slices, Systems tab (links / power / heat), expandable inspector, thin gauges.
2. **Heat system** (`Ship._thermal_step`, `ShipData.HEAT_*`): per-module waste heat, conduction to hull, hull radiates,
   output loss above 80 %, burning above 100 %, HEAT gauge, warnings, heat map, editor estimate.
3. **Interior / corridors** (`scripts/ship/interior.gd`, editor step 4): entrances on module faces, A* routed corridors
   (smooth rounded tubes, whole tube validated inside the hull), bends, widths up to x4.5 (rooms), doors, slope / stairs /
   ladder by steepness, **junctions (T-piece, 4-way) and rooms** (a corridor can be joined to another corridor), saved in
   `bp["interior"]`, shown in Panel 1 (Onion / Basic).
4. **Large worlds** (`scripts/world/`): `Vec3D` (64-bit positions), `WorldSpace` (floating origin, rebase every 4 km),
   `FarSim` (ships > 120 km go dormant: a 64-bit point, wake inside 90 km), `MapDefs` (the 38 maps of the GDD + Test Range,
   100 km to 1,000,000 km, as density fields: slab, sphere, shell, torus, ribbon, lattice + far bodies), `MapStreamer`
   (deterministic chunks of 5 km generated from absolute coordinates, MultiMesh visuals, physics only within 1.5 cells),
   `FarBackdrop` (stars / planets / nebulae as impostors with true direction and angular size, sun light direction).
   Map cube edge pushes ships back. Map chooser in the Freematch and Sandbox screens.
5. **Km-long ships** (`scripts/ship/ship.gd`): power allocation in <= 64 priority groups (O(groups) per frame instead of
   a sort + modules x generators loop), cached generator priority (spatial hash), aggregated thrust per direction, heat in
   time slices (~150 modules per frame), incremental update when a module dies (no full rebuild), spatial grid for hits and
   rays, only barrels / flames are iterated, **MultiMesh visuals** (a ship with > 24 external modules has ~7 scene nodes).
   Ships with <= 64 modules keep the exact per-module path (behaviour unchanged).
   Camera near / far planes and zoom limits follow ship size.
6. **Workshop scale**: `ShipData.validate` was O(n^2) / cubic (10.9 s for 3,000 modules): now 0.4-0.65 s (spatial hash
   for overlaps, O(1) `get_module`, link index, per-z hull cache). Editor: vertex handles as one MultiMesh with constant
   pixel size and a level of detail (far rings thinned, small rings keep fewer vertices), modules as one MultiMesh when > 48.

### Measured (headless, one ship thrusting; `tests/bench_ship.gd`)
| modules | before | after |
|---|---|---|
| 3,000 (2.2 km) | 338 ms / frame | ~2.4 ms median |
| 8,000 (4.5 km) | did not finish | ~2.3 ms median (worst frames up to ~75 ms: see "Known issues") |
Setup of an 8,000-module ship ~1.3 s. A plain Vector3 loses a 10 m offset completely at 900,000 km; `Vec3D` keeps it.

## Test status at the end of the session
All green: run_tests, editor_ui_test, waypoint_test, weapons_test, tuner_test, preview_test, heat_test, interior_test,
network_test, world_test, scale_test, menu_test. `editor_scale_test`: all pass except the 5 checks listed below.

## Known issues / where I stopped
- `tests/editor_scale_test.gd`: 5 checks fail at the very end (everything before passes, including the 90 km ship in the
  arena): "every handle is 6 px wide" (4 sizes) and "zoomed in, more vertices appear". Most likely the test measures
  the handle scale with a different camera / viewport than the editor used for the last LOD update (the LOD runs in
  `_update_cam`; the test calls `_frame_camera` then reads values), or the LOD needs `ed._update_cam()` after
  `cam_dist` changes. Check `_update_handle_lod` / `_world_per_pixel` first. Not yet confirmed to be a real bug.
- Worst-frame spikes (tens of ms) still appear on 8,000-module ships; the heavy rebuild is now rate-limited to once per
  4 s after a generator dies (`PRIO_EVERY`) but is still ~40 ms. Next step would be slicing `_assign_groups`.
- Far ships (`FarSim`) only drift or head for the player: no combat, orders or AI while dormant.
- Map effects of the GDD (radar ghosts, EMP, drift, heat zones...) are NOT implemented: maps are visuals + density only.
- The 3D radar / HUD ranges were not retuned for 10,000+ km maps.
- Premades: Dart is too narrow for a real corridor tube (0 corridors); Lance / Anvil have a 2-corridor network.
- Hull skin has no LOD (a hull is only ~100-600 triangles, fine at any size).

## Where it was going (suggested order)
1. Fix / confirm the editor handle-LOD test, run the full suite, then tag.
2. Slice the priority rebuild; consider moving the module loops to a GDExtension if 20,000+ module ships are wanted.
3. Radar and tactical map zoom levels for 1,000 km - 1,000,000 km maps; show absolute distance / map position in the HUD.
4. Far-sim: let dormant bots keep orders, fight in coarse mode, and be seen on the tactical map.
5. Multiplayer (GDD 4): sector interest management on top of `WorldSpace` / `FarSim`, then lobby and server list.
6. Map mechanical effects (toggle "effects on / off" from the GDD) and the remaining game modes (Zone Control, Base Defense).
7. Remaining modules: Defense Bay, Communication Room / Dish, Breach Doors / Pods, Hangar.
8. Hidden systems still missing: Oxygen, Crew, AI cores, Communication delay. Corridors + doors are the base for Oxygen and Crew.
9. Cosmetics step (props, camo, decals), more hull tools (boolean, array, bridge loops, cross-section slices).

## Design decisions worth keeping
- Never let a node hold a big coordinate: positions in the scene are local to a floating origin; absolute positions live in `Vec3D`.
- Content is described, not stored (density fields + seed): cost depends on what is near the player, not on map size.
- Per-frame work must be O(active). Derived per-module values (demand, frac, heat) are refreshed in time slices and on events.
- A change that touches many modules (death, overheating) must be incremental; full rebuilds only on rare structure changes.
- Visuals of many identical things go through MultiMesh; the headless renderer does not store MultiMesh data (tests skip those).
