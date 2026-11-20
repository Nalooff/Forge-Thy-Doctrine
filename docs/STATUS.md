# Forge Thy Doctrine - Status list

Last audit: 2026-11-20, against `docs/Forge_Thy_Doctrine.md` and the code in `scripts/`.

- **DONE**: implemented and used in the game.
- **IN WORK**: some code exists but it is not used yet or not fully implemented.
- **TO COME**: not started.

## DONE
- Main menu: 4 buttons with connector lines, Join/Host/Campaign/Freematch/Tutorial/Sandbox tree, big spinning "last loaded ship" (no more corner card)
- Ship Forge layout (mock-up): top bars (name/save/undo/redo/load, view settings, export/import), Type / Modifier / Helper tabs with a tools panel on the left, Ship info panel + Legal label, chevron step timeline at the bottom
- Load popup (select a ship, copy scope, "Load as new ship (prefab)" vs "Modify this ship"), Import/Export of ship files, view settings (Full/X-ray/Wireframe, Perspective/Orthogonal, Camera presets)
- Ship Forge: 6-step timeline (Hull, Modules, Links, Interior, Cosmetics, Test), ring-loft hull, vertex drag, mirror + centerline, soft selection, loop cut, extrude, scale, undo/redo, autosave drafts
- View modifier (shaded / X-ray / wireframe + front, rear, side, top, perspective), grid snap and camera that adapt to ship size
- Stat panel (class from size, mass, cost, power, acceleration, polygon budget, legality list), a ship must be legal to save or test
- Modules: Commander Post, Generator, Engine Room, Radar Room, Turret Bay (external), Turret Control (internal), Thruster, Barrel; min-size red outline, internal/external placement rules, Auto-Hull and clearance slider
- Module links and damage propagation (Commander to Engine/Turret/Radar, Engine to Thruster, Bay/Control to Barrel)
- Hidden systems: Electricity (priority by distance), RCS (10%), Gyro (inverse to mass), Radar
- Flight (Newtonian, assisted/manual), commander and first-person views, free cursor, damage flash with 30 s shake lockout
- Console HUD: panels 1-5 (3D ship model with Basic/Exploded/Onion tabs, module tabs, 3D radar, objectives/log), sub-panel 2
- Game modes vs bots: Team Deathmatch, Team Elimination, Deathmatch (Freematch)
- Bots/autopilot, projectiles (kinetic, laser, missile), premade ships (Dart, Lance, Anvil), JSON ship saves
- Headless test suite (`tests/run_tests.gd`, 36 checks passing)

## IN WORK (code exists, not finished or not wired in)
- Editor Type modes: only Vertex and Ring exist on the Hull step; Edge and Face are not implemented yet; Modifier/Helper lists are short (Mirror, Soft select, Thickness / Ruler, Frame view)
- Editor Export saves the ship currently open (not a picker of several ships)
- Hull tools: Bevel/fillet (ring "round") and Solidify (thickness) are partial
- Top notification ticker: plain ticker, no comms/crew icons routing yet
- Console sub-panels: Combat and Movement simplified; Tactical Map view not at GDD level
- Console modes listed but inert: Defense, Comms, Crew Cmd, Boarding, Hangar/Fleet, AI/Auto (each shows what it needs)
- Menu stubs: Join, Host (info text only), Campaign, Module creation, Download creation
- Interior and Cosmetics steps exist in the timeline: Interior is a placeholder, Cosmetics is colors only

## TO COME (not started)
- Hull tools: Boolean ops, Array mesh, Curve deform, SubD, Bridge edge loops, Weld/Stitch, Blend surface, Cross-section slices
- Interior step: entrances, corridors, doors, stairs, ladders, slopes
- Cosmetics: stowage props, paint patterns/camo, decals/vinyl
- Modules: Defense Bay, Communication Room, Communication Dish, Breach Doors, Breach Pods, Hangar
- Hidden systems: Heat, Oxygen, Crew, AI cores, Communication (delay vs instant)
- Multiplayer: host/join, server list and filters, GameLobby (player cards, ship selection, settings, objectives, chat, voice-to-text, objective links, spectator)
- Modes: Zone Control, Base Defense
- Maps: the 30+ maps and their effects (only one asteroid arena exists)
- Scale range 5 m to 100,000 m with LOD vertex culling (snap/camera adapt, LOD culling not done)
- Tutorial content, campaign, module creation, downloads
