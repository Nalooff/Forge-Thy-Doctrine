# Forge Thy Doctrine - Status list

Last audit: 2026-11-20, against `docs/Forge_Thy_Doctrine.md` and the code in `scripts/`.

- **DONE**: implemented and used in the game.
- **IN WORK**: some code exists but it is not used yet or not fully implemented.
- **TO COME**: not started.

## DONE
- Main menu: 4 buttons with connector lines, Join/Host/Campaign/Freematch/Tutorial/Sandbox tree, big spinning "last loaded ship" (no more corner card)
- Ship Forge layout (mock-up): top bars (name/save/undo/redo/load, view settings, export/import), Type / Modifier / Helper tabs with a tools panel on the left, Ship info panel + Legal label, chevron step timeline at the bottom
- Shared look (`scripts/ui/ui_style.gd`): black iron / ember orange / dark red like the main menu in the editor, menu and HUD; fonts Cinzel (titles, buttons, timeline) and Barlow Condensed (text), both OFL in `assets/fonts/`
- Load popup (select a ship, copy scope, "Load as new ship (prefab)" vs "Modify this ship"), Import/Export of ship files, view settings (Full/X-ray/Wireframe, Perspective/Orthogonal, Camera presets)
- Ship Forge: 6-step timeline (Hull, Modules, Links, Interior, Cosmetics, Test), ring-loft hull, vertex drag, mirror + centerline, soft selection, loop cut, extrude, scale, undo/redo, autosave drafts
- View modifier (shaded / X-ray / wireframe + front, rear, side, top, perspective), grid snap and camera that adapt to ship size
- Stat panel (class from size, mass, cost, power, acceleration, polygon budget, legality list), a ship must be legal to save or test
- Modules: Commander Post, Generator, Engine Room, Radar Room, Turret Bay (external), Turret Control (internal), Thruster, Barrel; min-size red outline, internal/external placement rules, Auto-Hull and clearance slider
- Module links and damage propagation (Commander to Engine/Turret/Radar, Engine to Thruster, Bay/Control to Barrel)
- Hidden systems: Electricity (priority by distance), RCS (10%), Gyro (inverse to mass), Radar
- Flight (Newtonian, assisted/manual), commander and first-person views, free cursor, damage flash with 30 s shake lockout
- Console HUD: panels 1-5 (module tabs, 3D radar, objectives/log), sub-panel 2
- Interior step (`scripts/ship/interior.gd`, editor step 4): entrances on the faces of internal modules (click a face), corridors between two entrances auto-routed (A* on a voxel grid) inside the hull and around the modules, hand-editable (click a corridor to add a bend point, drag / arrows to move it, Del removes; Width cycles x1 / 1.5 / 2 / 3 = room; Doors toggle), every segment is classified by steepness: corridor < 12 deg, slope, stairs from 32 deg, ladder from 58 deg; corridors are drawn as smooth tubes with rounded corners (quadratic arcs, as round as still fits), door frames, ribs on stairs and rungs on ladders; the WHOLE tube (height, width, widened parts, rounded corners, hull armour margin) must stay inside the hull and clear of modules; width scales with the ship (0.8 - 3 m); entrances follow their module, a corridor that leaves the hull or cuts a module makes the ship NOT LEGAL; "Auto-connect all" and Lance / Anvil come with a network (the Dart is too narrow for a real corridor); saved in `bp["interior"]`, counts in the polygon budget. Panel 1: corridors in Onion (cut by deck) and Basic (Corr toggle) with a hover card per segment. Tests: `tests/interior_test.gd`, screenshots `tests/interior_shot.gd`
- Corridor network (GDD step 4: corridors, doors, stairs, ladders, empty rooms): a corridor joins two ENDS, an entrance on a module or a NODE placed in the hull. Click a corridor with Type Junction to cut it and put a junction there; Type Corridor + click an end, then ANY corridor, joins them with a new junction = T-piece (3 corridors) or 4-way (4); a junction made bigger is a ROOM (Modifier Rooms or `Next room size`: 2.2 / 3.2 / 4.7 / 6.8 m wide at 0.9 m corridors, +/- per axis, it slides to the nearest spot where it fits); a corridor part can also be widened (x1 / 1.5 / 2 / 3 / 4.5, x3 and above are long rooms, taller too); every new corridor gets doors at its entrances and at a room's wall; junctions and rooms drag, resize, delete (deleting a 2-way junction joins the corridors back); all validated against hull and modules (nodes, corridors, widened parts), saved in `bp["interior"]["nodes"]`, Panel 1 shows and describes them (junction / T-piece / 4-way / room, size, area, volume). Code: `scripts/ship/interior.gd`; tests `tests/network_test.gd`, `tests/network_shot.gd`
- Heat (hidden system, `Ship._thermal_step`, constants `ShipData.HEAT_*`): every module turns 35% of the power it uses into heat (generators 12% of what they deliver), each with its own fixed thermal factor (0.75-1.25); modules conduct to the hull, the hull radiates into space (bigger hull = better cooling, ~75 s time constant). Above 80% a module loses output (thrust, fire rate, generator power, down to 40%), above 100% it burns (and the hull above 100%). Centre of heat = weighted average of module heat. UI: HEAT gauge (hottest module), one ticker + log warning per overheating module, module list tinted, heat lines in Power & Systems, Panel 1 Systems > Heat map (colours, % labels, centre-of-heat marker), hover card heat line + OVERHEATING status, editor Ship info line (heat idle / hard use). Test: `tests/heat_test.gd`
- Panel 1 ship model (`scripts/arena/ship_preview.gd`; the panel is bigger, the five gauges are thin and only shown in the normal panel, Expand turns it into a large pure-3D inspector): Basic 3D = glass hull with every module inside, hover or click (pin) any module or piece of hull for an info card (status, HP, power, thrust / weapon data, links, deck); Exploded = hull cut into sections that slide apart + every module pushed away so none overlap, spread slider, leader lines back to the real position, labels; Onion = ship cut into decks (2-16, -/+), pick a deck with the slider / Up / Dn / ALL, everything above is hidden (or ghosted), hull outline + module footprints drawn on the cut, layers below dimmed; Systems = command / engine / turret links or the power grid (green / amber / red) on the model; extras: hull Glass / Solid / Wire / Off, centre-of-mass marker, bow arrow, module labels, Expand button (Panel 1 grows into an inspector). Tests: `tests/preview_test.gd`, screenshots: `tests/preview_shot.gd`
- Game modes vs bots: Team Deathmatch, Team Elimination, Deathmatch (Freematch)
- Bots/autopilot, projectiles (kinetic, laser, missile), premade ships (Dart, Lance, Anvil), JSON ship saves
- Movement orders as tuning modes (sub panel hides, you shape the order in the 3D view): Drive to point (plane under the cursor, ship turns to look at it, Alt+mouse = height, click = go, click-drag = optional final heading), Drive to ship (distance circle), Orbit (ship or point, radius = mouse distance, Alt = tilt of the orbit plane + its axis, R flips direction), Face, Follow offset (ghost ship + optional heading, kept in the leader's frame), Route (Shift+click chain), Hold position (returns to the exact spot); Facing while moving: Auto / Lock heading / Lock direction / Face point; Esc cancels
- Per-turret targeting (Combat panel): turret list (Turret Bays and fixed barrels), click to toggle, quick select (All, None, Invert, Best, In arc, Idle, Kinetic, Laser, Missile, Online), send the selected turrets at a picked ship / nearest enemy / the locked target / the cursor; each turret aims, leads and fires at its own target (falls back to the lock if it dies); lines to targets and "<< N turrets" labels in 3D
- Movement waypoints: tactical map view (M) with range rings, click the XZ plane to place the point, drag it to slide, drag the diamond up/down for altitude (or the slider), G = go to the cursor point, waypoint label with distance/ETA and edge arrow, autopilot brakes with the real reverse thrust and stops on the point
- Headless test suite (`tests/run_tests.gd`, 36 checks + editor UI test + waypoint test passing)

## IN WORK (code exists, not finished or not wired in)
- Editor Type modes: only Vertex and Ring exist on the Hull step; Edge and Face are not implemented yet; Modifier/Helper lists are short (Mirror, Soft select, Thickness / Ruler, Frame view)
- Editor Export saves the ship currently open (not a picker of several ships)
- Hull tools: Bevel/fillet (ring "round") and Solidify (thickness) are partial
- Top notification ticker: plain ticker, no comms/crew icons routing yet
- Console sub-panels: Combat simplified; Movement orders are for the player's ship only (no fleet/formation commands for other ships yet)
- Console modes listed but inert: Defense, Comms, Crew Cmd, Boarding, Hangar/Fleet, AI/Auto (each shows what it needs)
- Menu stubs: Join, Host (info text only), Campaign, Module creation, Download creation
- Cosmetics step exists in the timeline but is colors only

## TO COME (not started)
- Hull tools: Boolean ops, Array mesh, Curve deform, SubD, Bridge edge loops, Weld/Stitch, Blend surface, Cross-section slices
- Cosmetics: stowage props, paint patterns/camo, decals/vinyl
- Modules: Defense Bay, Communication Room, Communication Dish, Breach Doors, Breach Pods, Hangar
- Hidden systems: Oxygen, Crew, AI cores, Communication (delay vs instant)
- Multiplayer: host/join, server list and filters, GameLobby (player cards, ship selection, settings, objectives, chat, voice-to-text, objective links, spectator)
- Modes: Zone Control, Base Defense
- Maps: the 30+ maps and their effects (only one asteroid arena exists)
- Scale range 5 m to 100,000 m with LOD vertex culling (snap/camera adapt, LOD culling not done)
- Tutorial content, campaign, module creation, downloads

- Large worlds, km-long ships, workshop scale (see docs/HANDOFF.md): floating origin + 64-bit positions, 39 maps streamed by chunks, far backdrop, dormant far ships, O(active) ship simulation with MultiMesh visuals, validation in 0.4 s for 3,000 modules, editor handles with level of detail. Tests: `world_test`, `scale_test`, `editor_scale_test`, `menu_test`, `bench_ship`
