# Forge Thy Doctrine

*Instrument of Ege* · Game Design Document, working draft


---

## 0. Vision & Pillars 🆕

**Pitch (draft):** a multiplayer space-combat game where you command one ship, built by a player (you or the community), in huge wars from small craft to capital ships, on maps up to 1,000,000 km.

**Candidate pillars:**

1. *Command a player-made ship*: ships are a community creation, built by players, tested and compared by players. Building is a main part of the game, but you do not have to use your own ship.
2. *Every module matters*: links and damage propagation make each room a tactical choice.
3. *Command, not just fly*: commander, crew, boarding and fleet play are first-class.
4. *Scale*: from micro-craft to capital ships, on maps from 100 km to 1,000,000 km.

**✅ Decided**

- The pillars are about *commanding* a ship that was built by a player. Creating ships is a main part of the game, but you do not have to use YOUR ship: ships are a community creation, and players can test each other's ships and see which is best.
- The player should feel like the captain of a vessel that went to war, the commanding officer.
- Closest game: Nebulous: Fleet Commander. Nebulous is about taking care of a whole fleet; here you take care of one ship, with less attention to the other ships, apart from communication with other players.

* **Why teams:** like in any team game, nobody can go 1v20, so teaming up is the best way to win.

---

## 1. Ship Creation

### 1.1 How it works

Ship creation is done in steps shown on a timeline that can be freely navigated; you can always go back to a previous step.

1. **Hull.** Built with Direct Mesh Manipulation / Vector-Based Modeling, with the tools in 1.2.
2. **Modules.** Place Modules in the ship. They can be reshaped with the same mesh tools but have a **minimum size on each of X, Y and Z** (not a minimum volume). The smallest possible shape is shown as a red outline. See section 2.
3. **Module Link.** Define system dependencies and command logic: which command centers, sub-systems or control nodes operate which targets. This allows setups from a single-seat ship to split or multi-crew control. See 2.4.
4. **Interior.** Link modules with corridors, doors, stairs, ladders and empty rooms. First place the entrances of the Internal Modules (any side, top or bottom), then link entrances together. Paths are forced inside the hull. You can add points to bend a corridor, widen parts of it and add doors. If a corridor gets too steep it becomes a slope, then stairs, then a ladder.
5. **Cosmetics.** Personalize appearance without changing performance:
   - *3D Stowage & Cosmetic Props:* pre-modeled, non-functional exterior accessories (tools, spare parts, antennas, equipment bags) that snap onto hull surfaces.
   - *Paint & Pattern:* solid colors per module, or brushed camouflage, wear and tarnish effects.
   - *Decal & Vinyl:* 2D projection tool to position, scale, rotate and layer badges, insignia, text and graphics anywhere on the exterior.

🆕 **Proposed changes to the flow:**

- **Joints in the Hull step** (decided): joints are placed in the hull; their movement is set in a small console in the last, visual step of creation (see 1.4).
- **A permanent stat panel** visible in every step: class, point cost, mass, power balance, polygon budget, and a green/red legality indicator for the selected map and team points (see 1.3).
- **A Test step** (decided, last): a solo test range, like in War Thunder. The player places a dummy ship anywhere and tests turning, aiming, shooting, moving parts and turrets, and can fire a chosen bullet at their own hull to see how it is damaged.

**✅ Decided**

- **Test step:** yes. It is a solo test by the player, not a match. The player can place a false ship anywhere and see how it reacts to turning, aiming and shooting, test moving parts and turrets, and make a certain bullet hit the hull to see how it damages it and how well it resists fire (like testing guns against your own ship in War Thunder).
- **Going back:** the player can go back to any earlier step. After a change, the editor rechecks the limits and rules, and marks in red whatever broke because of the change.
- **Starting points:** premade ships ship with the game, and ships can be downloaded and exported. A new ship can start from a prefab (own, downloaded or premade), and the player decides what to take: hull only, hull + modules, hull + modules + corridors, or everything.

* **Test range dummy:** it can be any ship from the library, and its behavior can be set.
* **Saving:** everything must be green; a ship must be playable (all limits and rules valid) to be saved.

### 1.2 Scale & dimensional range

The engine supports ships from micro-craft (**5 m**) to capital ships (**100,000 m** in any direction). The workspace adapts grid snapping, LOD and camera clipping planes to the ship's current bounding box so vertex manipulation stays precise at both scales. Far vertices are displayed at low detail (some even hidden) to show the general shape; near vertices show full detail.

**✅ Decided**

- Each map has hard limits on which ships it accepts; some maps cannot accept certain ships. On top of the map, the host sets the points (see 1.3).

* **Map limit format:** a maximum number of ships per class.

### 1.3 Ship Classes & Balancing 🆕

You want multiple ship categories based on size, weight, power, firepower and more, so that maps and modes can limit which types are allowed. This is the backbone of balancing, so here is a proposed structure with the decisions you need to make.

**Step A: class = size only (decided).** A ship's class is computed from its size alone. Maps use it to limit how many ships of each class are allowed. Class carries no bonuses and no hard rules; balance is handled by points.

**What feeds the point cost** (a mix of what the ship can do and what it is made of):

| Axis | How it's measured | Why it matters |
| --- | --- | --- |
| Size | Longest bounding-box dimension (and/or volume) | Fits maps, hangars, corridors |
| Mass | Sum of hull + modules | Turning and acceleration |
| Power | Total generator output | What can run at once |
| Firepower | Combined weapon rating (damage × rate × range) | Offensive threat |
| Crew | Crew capacity required | Boarding, damage control |
| Defense | Armor + shields + structural HP | Survivability |

**Step B: example tiers (names and thresholds are placeholders):**

| Tier | Class | Example length | Typical role |
| --- | --- | --- | --- |
| 1 | Drone / Pod | 5-15 m | Scout, parasite craft |
| 2 | Fighter | 15-40 m | Fast strike, dogfight |
| 3 | Corvette | 40-120 m | Light multirole |
| 4 | Frigate | 120-400 m | Escort, support |
| 5 | Destroyer | 400-1,200 m | Heavy hitter |
| 6 | Cruiser | 1.2-4 km | Fleet anchor |
| 7 | Battleship | 4-20 km | Capital firepower |
| 8 | Titan | 20-100 km | Flagship, mobile base |

**Step C: how limits are enforced (decided)**

1. **Point budget.** The host sets the points per team. Each ship costs points. If a player takes a ship that costs too much, the team has less budget left and other players join a teammate's ship as secondary commanders. Two teams with the same points should always get a fair, equal fight.
2. **Class limits from the map.** The map decides how many ships of each class are allowed (see 1.2): typically 1-2 big ships per team, and more only on huge maps.
3. **No hard module rules.** Nothing like a Fighter can mount at most N weapons; points do that job. Physics still applies: a heavier ship needs more power and accelerates and turns slower (gyro included).

**✅ Decided**

- **Goal of the points:** fairness. Ships of a total cost Y against other ships of the same total cost Y should always be a fair, equal fight. Points should also stop everyone from taking big ships: ideally 1-2 per team, rarely more, except on huge maps.
- **What points reflect:** a mix of what the ship can do and what it is made of, enough to balance the game and push players toward different types of ships.
- **Cost tendencies:** the faster a module makes the ship, the more it costs; the more resistant, the more it costs; the more possibilities it gives, the more it costs; the heavier, the less it costs.
- **Who sets what:** the host sets the points per team; the allowed classes come from the selected map.
- **Ranked:** there is no ranked mode, so no official-only ship rule.

* **Armor vs weapons:** there are different weapon types, and some are made to go against armor, as in real life. Everyone wants the best armor, but it always has a drawback: speed and maneuvering often beat a slow tank.
* **Module prices are computed by the game** from the module's size and type; nobody hand-makes a price for every size of every module.
* **Budget:** the team points are one shared pool.

**Balancing rules to decide** 🆕:

- Counter relationships (small fast vs big slow, radar vs stealth, EMP vs electronics).
- The point-cost formula for hull, modules and crew (see the table above).
- Mass-to-thrust physics: heavier ships need more power and accelerate and turn slower (the Gyro already scales with weight).
- **Legality check in the editor:** shows whether the ship fits the selected map's class limits and the team's points, and marks in red whatever breaks after a change.

### 1.4 Articulated Parts (moving hull) 🆕

Goal: make ships feel alive. Moving parts are a feature of the **hull**: the player places joints while building the hull, so a moving part is simply hull that is allowed to move.

**Joint types:** turning (hinge), sliding, or other kinds of moving connection, a bit like the joint of a door. Wings are dropped: in space they serve no purpose. Devices such as radar dishes are modules, not joints.

**Authoring (decided):** the player places joints between two parts of the hull while building it. The movement itself is set in a small console in the last part of ship creation (the visual details step): movements are cycles, meant to give life to the ship. Several joints can be combined into multi-joint parts; if joints contradict each other, the part cannot move.

**Gameplay effects (decided):** a moving part is hull, so it can be deformed or cut like any hull, its hitbox moves with it, and so do the modules attached to it. It costs no points and no electricity, because it is mostly decoration. A part moves only as long as it does not collide with something; it stops just before it would interfere with the hull.

**Network cost:** one animation value per part, synced as a delta.

**✅ Decided**

- **Moving parts are hull.** Their hitbox moves with them, and so do the modules inside or attached, because modules are set by the hull. It impacts gameplay, but not enough to give a special advantage; the part is mostly visual.
- **Set up in the Hull step:** the player places the point of movement between two parts of the hull and makes it a moving connection (turning, sliding or other). Contradicting joints mean the part cannot move.
- **Multi-joint parts are allowed.** A part moves according to its joints as long as nothing breaks. A part connected to hull that should not move stays still, unless that connection is also a joint placed to allow the motion.
- **They behave like hull:** they can be deformed or cut. If a deformation would make a moving part go inside another part, its movement is limited to just before that, like a real thing.
- **Modules:** devices like radar dishes are modules; adding one is just setting the module, nothing else needs to change outside it.
- **First version:** none of the examples are required apart from the radar dish. Wings have no reason to exist in space.

* **Moving a joint:** it is set in a small console where you define the movement. Movements are cycles, mostly visual, to put life in the created ships. It is like the last part of ship creation, which adds visual details.
* **Cost:** none. It brings nothing but decoration.
* **Collisions:** a joint cannot move if the motion would collide with something; it moves as long as it does not interfere with the hull.

### 1.5 Ship Creation Tools

**Shape-building & deformation (the core creators)**

- **Extrude / Boss Extrude:** pull a flat face or edge outward along an axis to grow a hull section, cockpit or engine mount.
- **Bevel / Fillet:** round or chamfer sharp edges.
- **Loft / Skin Surface:** draw cross-section curves (ship ribs) and let the system skin a smooth hull between them.
- **Loop Cut / Edge Split:** insert a ring of control points to add local detail.
- **Proportional Editing / Soft Selection:** move one vertex and let neighbors follow smoothly (digital clay).
- **Boolean Operations (Union, Subtract, Intersect):** punch holes for docking bays, merge weapons into wings, cut chunks of geometry.

**Procedural & repetitive (the pattern makers)**

- **Array Mesh (Linear & Radial):** clone elements (exhaust ports, armor plates, rivet rows) along a line or around a core.
- **Curve Modifier / Path Deform:** a mesh (pipe, cable, corridor) bends to follow a drawn curve.
- **Solidify:** give a thin hull sheet physical thickness in one click.
- **Subdivision Surface / Control Cage:** edit a low-poly cage and the engine smooths it.

**Connection & transition (the bridge operators)**

- **Bridge Edge Loops:** generate a surface or tunnel between two open holes or edge rings (parameters: segments/resolution, twist/tension).
- **Auto-Merge / Weld / Stitch:** fuse nearby vertices to prevent gaps and leaks.
- **Blend Surface / Fillet Edge:** smooth, continuous transition between two intersecting plates (G1/G2 continuity).

**Non-destructive modifiers & helpers (the safety net)**

- **Mirror Modifier:** sculpt one side, the other mirrors (center-merge and clipping options).
- **History / Non-Destructive Stack:** step back or edit an extrusion depth or bevel size later.
- **Symmetry & Centerline Lock:** keep vertices from drifting off the main axis.
- **View Modifier:** wireframe / X-ray / full object, plus saved viewpoints for modeling.

**Construction geometry & visual guides**

- **Symmetry Axis / Mirror Plane Gizmo.**
- **Cross-Section Slices (Waterlines / Buttocks):** transparent cutting planes showing width profile or internal layout.
- **Live Rulers & Bounding Box Dimensions:** length, beam, height, estimated internal volume and mass.
- **Snapping & Grid Constraints:** to grid, vertices or neighboring panels.

🆕 **Possible additions:** symmetry across more than one axis, a reference-image import (blueprints), a hull "health check" (open holes, self-intersections, non-manifold edges that would break physics), copy/paste of ship sections between designs, a polygon budget meter.

**✅ Decided**

- **Mesh freedom:** players can express the form of their ship with no limitation. The game tries to simplify the mesh automatically to avoid lag.
- **Too heavy ships:** if the ship is too big, the editor shows a warning that it might not be allowed in multiplayer, depending on the player's performance.
- **In a lobby:** if people in a server cannot load a ship because it costs too much RAM or computing power, it is not allowed. If it was selected before a player without the capacity joined, that player gets a warning that a ship that might exceed their PC limit is already selected and that it might not be a good server for them.
- **Sharing:** yes, between users, like a Steam Workshop. Ships are saved in a simple format like .obj or .JSON, so they are easy to give to others.

* **Sharing:** players find their own places to share the ships they make. The only support from the developer is the Steam Workshop integrated in the game; how to share, and how to avoid people reposting ships, is up to them.
* **Can this PC load the ship?** the game looks at the costly operations (vertices, modules and so on) and estimates how far the PC can go. At first launch it measures this, asks to read PC information such as the graphics card, and with that data checks whether the PC can handle a given ship.

---

## 2. Ship Modules

### 2.1 Internal Modules

Habitable or functional rooms that must live completely inside the ship's volume.

- **Placement rule:** must remain 100% enclosed by the hull. If a module intersects or protrudes past the hull, placement is blocked and shows "Not Placeable Here".
- **Player-driven Auto-Hull Expansion:** the player can toggle "Auto-Hull" on invalid placements; the game pushes the exterior hull outward to surround the module cleanly.
- **Hull Thickness Slider (X distance):** once Auto-Hull is active, a slider sets the distance between the module walls and the outer skin (custom armor clearance or hull depth).

| Module | Role |
| --- | --- |
| **Generator** | Produces operational electricity and sets up the power network. Routes power outward starting with the closest modules by default (highest priority; overridable in game). |
| **Engine Room** | Generates operational power and propulsion thrust data for all linked Thrusters. |
| **Turret Bay** | Structural and mechanical control housing for mounted weaponry (barrels, missile launchers). Rotates any weapon physically linked to its mounting surface around a customizable pivot center. If rotation would break the weapon's contact with the bay boundary, the maximum angle is restricted. Direct physical mounting is required; unlinked weapons cannot rotate. |
| **Defense Bay** | Housing for automated defensive hardware (point-defense cannons, interceptor turrets, countermeasure launchers). Automatically tracks and rotates linked hardware with the same pivot and contact rules as the Turret Bay. Unlinked hardware cannot operate. |
| **Radar Room** | Active/passive sensor arrays to detect, track and target distant vessels and hazards. |
| **Communication Room** | Interior transmission hardware for long-range signals, fleet data and relay (damage reports, commands). High structural protection, but requires active crew to operate. |
| AmmoBay | Stores missile ammunition (only missiles cost ammo; everything else runs on electricity). Regenerates ammo very slowly and risks exploding if hit. |

### 2.2 External Modules

Components that interact with the outside world and need direct exposure to space. Each has an **exposure requirement**: a designated surface, nozzle or mounting point must protrude through the hull into open space while the rest of the body stays anchored inside.

| Module | Role |
| --- | --- |
| **Commander Post** | The heart of the ship, where the player is and orders originate. Mostly inside the hull, with a face looking out to space; in first person the player sees outside through that face. Requires a direct viewing port or window to the outside. |
| **Thruster** | External propulsion nozzles for directional movement and velocity. |
| **Barrel** | Offensive hardpoints (ballistics, lasers, missile pods). Must be mounted onto a Turret Bay or hull face to align and fire. |
| **Communication Dish** | Exterior transmission hardware. No crew needed, but low structural protection and high vulnerability. |
| **Breach Doors** | External boarding hatch flush against the hull for docking or ramming. Outward-facing seal; on collision with a compatible enemy hull section it welds a pressurized seal and opens a direct internal path for boarding, sabotage and melee. |
| **Breach Pods** | Module with a forward launch tube housing self-propelled boarding capsules loaded from the internal crew pool. The pod detaches, crosses open space, drives its reinforced nose cone through the enemy hull and embeds as an airlock, spawning crew inside the target. |
| **Hangar** | Large internal/external hybrid bay with an external access gate to house, service and fully repair docked parasite craft. A real-time spatial check compares the incoming ship's 3D bounding box against entry corridors and turning clearances; if valid, the docked ship is fully reconstructed and repaired. |

**✅ Decided**

- **Commander Post:** it is an external module because it needs a face that sees outside; otherwise the commander could not see outside. Most of it is inside the hull and it can have a face on the outside. In manual control or first person, the player is in this post, and the faces pointing to space (not to the hull) are what the player sees outside, like a pilot seat.
- **Ship death:** if another commander is still alive in another Commander Post, the ship is alive. When no commander is alive, the ship is dead and becomes debris. In a mode with respawn the ship is deleted and the player respawns; otherwise it stays on the map as an obstacle.
- **Other ways to lose a ship:** all crew dead, or no thruster power and no generator left that can be fixed.
- **Breach Pods and Doors:** they are modules, so their look can be edited like the hull; their size, and so their capacity, depends on how big the module is.
- **Boarding combat:** only seen as dots on the ship map, and computed. Each dot is a crew member with health. Every second a dot damages an enemy dot with almost random damage, with small modifiers like training and equipment: `damage = random(base_attack_min + modifier, base_attack_max + modifier)`.

* **Ship without thrusters:** it can keep fighting. A clear Give up message is shown; the player can continue firing, or give up and the ship is considered dead. In a deathmatch it counts as a death and a kill for the other player even if the player does not give up; not giving up only lets the player maybe get a few more kills.
* **Module stats and crew:** like all modules, they are computed from the module's size plus its type, with a function per type. For example a pod launcher could use crew = Volume × class\_spec, or crew = (Volume + Const) / (Volume − class\_spec) (careful: the second one breaks when Volume equals class\_spec). Any such function must make things fair and balanced. This also sets how many boarders a pod carries.
* **Boarding orders:** the player gives them in the secondary panel of the Boarding tab.

### 2.3 Hidden Modules

Instead of physical blocks placed by hand, these are the core system networks, resource pools and simulation loops that keep the ship alive.

| System | Description |
| --- | --- |
| **Heat** | Thermal simulation loop tracking the variable heat output of each module (identical module types can produce different loads) and the spatial average centroid of where heat builds up. For now heat only makes the ship more present and detectable from farther away by radar and heat-seeking weapons; cooling modules (radiators, heat sinks) would be external modules but do not exist yet. |
| **Electricity** | Power grid ensuring every module is powered. If generation falls short, modules shut down by priority. Paired with the Generator, which distributes power starting with the closest connected module (in-game priority overrides). Electricity is also the fuel: thrusters and weapons only draw power, there is no propellant, and the limit is how much can be used at one time. |
| **RCS** | Auxiliary thrust independent of thrusters. Generates force from the ship's Center of Mass across 26 directions (all orthogonal and diagonal vectors) at 10% of the ship's base maximum thruster power in its best vector. |
| **Gyro** | Torque-based orientation system that rotates the ship and counters thruster torque without propellant. Consumes energy; turning speed scales inversely with total ship weight. |
| **Oxygen** | Life-support network supplying air to internal rooms and corridors. After a hull breach, oxygen bleeds out from all connected spaces unless isolated by bulkhead/airlock doors. |
| **Crew** | Not players: crew are dots on the ship map. Each ship has a minimum crew and more can be added at a point cost. They die if their sector is hit. Repairs take real time because a crew member must go there. |
| **Radar** | Sensor network driven by Radar Rooms and the Commander Post's Line of Sight (rays of length X meters through windows/viewports). Fallback detection works at 70% of LoS range and requires active communications; otherwise it incurs a delay. |
| **AI** | Not a physical module but a game system that makes control easier: when given a destination it handles the macro adjustments (turning around, slowing down in space), and it directs crew so the player does not have to micro-manage them. |
| **Communication** | Data relay network governing how fast tactical information (damage reports, command updates) arrives. Instant transfer needs a working Communication Dish or Room. Without comms, telemetry is delayed and crew must physically travel to damaged areas and return to report. |

**✅ Decided**

- **Heat:** for now it only makes the ship more present and detectable from farther away by radar and heat-seeking weapons. Modules that reduce it (radiator, heat sink) would be external modules; none exist for now, but they would not be hard to add.
- **Fuel:** unlimited. Electricity is the fuel, and the only limit is how much can be used at one time. One thruster could run forever, but 5 thrusters may not all be powered, so only 4 fire. Weapons work the same way.
- **Ammo:** only missiles cost ammunition, on top of electricity. A new internal module, the **AmmoBay**, holds it. It regenerates really slowly and can explode if hit.
- **AI:** not really a module but the game's own help. When you set a destination it handles the macro adjustments (turning around, slowing down, no atmosphere), and it directs crew so you do not have to micro-manage, like automation aiding pilots on real spaceships.
- **Crew:** crew are not players, only dots on the ship map. The number depends on the ship, with a minimum; the player can add more at a point cost. They die if they are in a sector where a hit was registered. Commands are never instant: a repair takes real time because someone must go there.
- **Giving orders:** the player can select dots on the map and send them somewhere, but usually just asks to go see something, and the AI sends the closest inactive crew member; if none is free, the one whose current activity is least important.
- **Crew per module:** it depends on the module's size. One crew member is enough, but one for a big module has big drawbacks: slower repairs, slower turret movement and firing, lower precision, lower ship power. The drawbacks depend on the module.

* **Crew orders:** all automatic. Crew have their own roles and act without orders, like on real ships; the player can override orders and ask them to act outside their normal job when needed.
* **Crew per module:** crew are assigned per module (the AI needs this to know what each crew member should do).
* **AmmoBay:** it follows the same size-based rules as all modules, and the explosion grows with the stored ammo.

### 2.4 Module Link

The linking system sets command authority, operational dependencies and damage propagation. Links decide how orders travel from the player to active subsystems.

- **Commander Post links (command authority).** A Commander Post can link directly to any functional internal module (Engine Room, Turret Bay, Communication Room...). A Commander Post **cannot** link directly to secondary hardware like barrels or thrusters. A player can only command a module through the Commander Post linked to it. Several Commander Posts allow split or centralized control (one for piloting, one for gunnery).
- **Engine Room links (propulsion).** An Engine Room must link to the Thrusters it powers and controls. If it is destroyed or disabled, every linked Thruster loses power even if undamaged.
- **Turret Bay links (weaponry).** A Turret Bay must be physically and logically linked to the weaponry mounted on or assigned to it. If it is taken out, all linked weaponry loses targeting, rotation and the ability to fire.

🆕 **Links still to define:** Radar Room → Commander Post (who sees the radar), Defense Bay links, Hangar links (who launches craft), Articulated Parts links (who moves them), Generator → power groups.

**✅ Decided**

- **Shared control:** two Commander Posts can link to the same module. Control is shared and the last command wins; for example, with two posts on one turret, the turret aims at the last aiming command.
- **Re-routing in game:** yes, a link can be re-routed during a match, and a crew member must rewire it.
- **Links are logical, not physical.** But a module with no corridor path to the rest of the ship is only usable if communications are up and crew are inside the disconnected part.

* **Rewire time:** it depends on how long the crew member walks; long enough not to be too quick, but fast enough not to be useless.
* **Cut-off parts:** no rewiring there; the corridor needs to be repaired and accessible first.

---

## 3. Multiplayer

### 3.1 Before Playing

Players choose to **Host** or **Join** a game session.

**Hosting a lobby** requires: Lobby Name; Game Mode; Map Selection (single fixed map or a custom map pool, editable later in the lobby); Custom Ships Allowed (checkbox); Late-Join Allowed (checkbox); Privacy Status (Public, or Private with a password). On confirmation the host goes to the GameLobby.

**Joining a lobby** shows the active server list with filters (maps, custom ship settings, Public/Private) and a search bar (by name, state "In GameLobby" vs "Currently Playing", other keywords). Selecting a server leads to the GameLobby.

🆕 **Missing host options to consider:** the team point budget (set by the host; class limits come from the map, see 1.3), max players, map effects on/off (your maps already support this), friendly fire, respawn rules, match length, team balance/auto-balance, and a region/ping display.

**✅ Decided**

- **No matchmaking for now:** lobbies and a server browser only.
- **Peer-to-peer** with a player as host, because there is no budget to pay for servers.
- **Anti-cheat:** not now; it is for a really far future.

* **Host capacity:** not thought about yet.
* **Networking later:** Steam multiplayer is likely in the future, and real servers in a farther future.

### 3.2 GameLobby Interface

**Right panel: Current Players Info.** One split card per connected player.

- *Top:* profile picture → name tag → player level.
- *Bottom, three windows:*
  - **Ship Preview Box:** 3D preview of the selected vessel with its name at the top right; clicking opens a full inspect view (rotate, zoom).
  - **Module Layout Box:** top-down categorized list of installed modules based on the linked architecture; clicking a module auto-zooms the preview to its position on the hull.
  - **Crew Assignment Box:** list of secondary commanders and their Commander Posts, with a "Join as Secondary Commander" button.
- *Footer:* **Become Spectator** below the list; **Leave Server** (everyone) and **Start Game** (host only) beneath the panel.

**Left panel: Lobby Settings & Selection (3 tabs).**

- **Tab 1, ShipSelection:** selectable list of ships with 3D cards; selecting one opens an expanded preview with all Commander Posts and their occupation (players can reassign freely) and a **Lock Ship** button at the bottom right.
- **Tab 2, Game Settings:** active match parameters (map, mode, rulesets); read-only for joiners, editable by the host.
- **Tab 3, Objectives & Communications:** top section shows mission objectives and win conditions with status; bottom section is the chat with channel tabs (General / Team / Crew). *Voice-to-Text:* spoken voice is transcribed into the chat in parentheses, e.g. *(Voice) "Engine room is taking heavy fire!"*. *Objective Linking:* players embed clickable goal links in messages (e.g. "Goal 1: Go to Sector A") that highlight the matching objective.

**✅ Decided**

- **Sharing a ship:** several players can share one ship. One player chooses the ship and locks it; he is the principal commander and decides the loadout. The others can join if there is room and become secondary commanders. They only have rights once the game has launched, and the principal commander has no extra ability.
- **If the principal commander leaves:** nothing changes. He is considered dead, and the other commanders stay in the ship. Back in the lobby the ship is unlocked and everyone must choose a ship again.
- **Changing ship:** the only way is to unlock; a ship must be locked to play.
- **Enemy information:** not a concern. Most ships will be community ships that players do not know; the only info they get on an enemy is its preview and its modules.
- **Non-commanders:** players can only go to a Commander Post; all other modules are run by AI crew. In first person, a player can go to a turret module and shoot it by himself, as a small gimmick (like the second gunner view in War Thunder).

* **Moving between posts:** a secondary commander can move to another Commander Post (or a turret) only if it is accessible and not full.
* **Respawn of a shared ship:** all commanders respawn together on the same ship.

### 3.3 Game Modes

| Mode | Players | Rules |
| --- | --- | --- |
| **Team Elimination** | 2-4 teams of 5-20 | Last team standing; one life per round, no respawns. |
| **Team Deathmatch** | 2-4 teams of 5-20 | Unlimited respawns; first team to 100 kills wins. |
| **Deathmatch** | 10-80 | Free-for-all, unlimited respawns; first to 30 kills. |
| **Zone Control** | 10v10 to 40v40 | Each team has a countdown timer (1h30 to 5h). Capture and hold 3-5 zones to drain your clock; every 30 consecutive seconds of control boosts drain speed by 1.75x (max 5 stacks) until the zone is lost. Each enemy kill also removes 10 seconds from your timer. The 1h30 to 5h range is only the maximum if nobody does anything: holding 2 zones all game turns 1h30 into about 5 minutes. |
| **Base Defense** | 10v10 to 40v40 | One team defends 1-3 space stations for 10-30 minutes while the other teams try to destroy them before the timer ends. *Stations are premade; attackers and defenders get the same point budget.* |

**✅ Decided**

- **Zone Control timers:** 1h30 to 5h is only the maximum if nobody does anything. Players die quite often, and a team holding 2 zones all game turns 1h30 into about 5 minutes, even without counting kills.
- **Base Defense:** the station is premade; attacker and defender get the same budget.
- **More modes:** yes, more modes are wanted, including modes against AI; none chosen yet.

* **Respawn:** a player respawns with the same ship after a delay that depends on the ship's size. Before respawning, the player can swap to another ship: the points of the first ship are given back, and the new ship's cost is deducted from the new budget.
* **Extra modes:** none for now.

### 3.4 Maps

Map effects can be toggled on (real mechanical impact) or off (purely visual). *Condensed from your descriptions.*

**100 km × 100 km × 100 km**

| Map | Effect |
| --- | --- |
| The Shard Graveyard | Crystal shards block line of sight; small craft use passive radar to ambush. |
| Cinder Core | White dwarf radiation; heat management or radar exposure through glare. |
| Echo Nebula | Ion gas distorts comms and sensors; close-range visual spotting. |
| The Iron Ring | Orbital ring ruins; tight cover and obstacle-dodging dogfights. |
| Glinting Hollow | Metallic asteroids bounce radar; ghost echoes confuse AI targeting. |
| Viper's Nest | Volatile gas pockets ignite from fire/exhaust; area hazards. |
| Obsidian Veil | Pitch-black dust cloud; blinds optical Commander Posts without thermal/night optics. |
| Stellar Spark | Protostar flares; periodic EMP bursts disable unshielded modules/comms. |
| The Rust Caldera | Inside a hollow planet mantle; overhead cover from external missiles. |
| Frozen Prism | Sublimating ice comets; vapor trails mask movement vectors. |
| Gorgon's Eye | Magnetar pull causes drift; constant RCS corrections. |
| The Labyrinth | Scaffolding maze; hit-and-run tactics, blocks capital turning arcs. |
| Solar Flare Basin | Solar wind pushes ships in one vector and heats sinks; punishes stationary sniping. |
| Ashen Spire | Vertical basalt monoliths; vertical cover and terrain masking against radar. |
| Null-G Sanctuary | Clear, dust-free pocket; maximum LoS, pure piloting and gunnery. |

**1,000 km × 1,000 km × 1,000 km**

| Map | Effect |
| --- | --- |
| Binary Cradle | Twin-sun overlapping shadows hide thermal signatures. |
| The Veil of Sirens | Dense dust dampens long-range radar; knife-fight, sensor traps. |
| Titan's Gate | Planetary-crust arch as a choke point for capital ships. |
| The Shattered Ring | Ring-world fragments as impenetrable bulkheads. |
| Comet's Wake | Comet trails change drag and sensor tracking. |
| Auroran Expanse | Aurora glare hides stealth torpedoes from manual gunners. |
| The Graveyard of Giants | Wrecks as cover; scrap can be looted in match. |
| Prismatic Dustway | Crystal concentrations refract lasers; deceptive aiming angles. |
| Obsidian Reach | Dark star; active radar exposes your position to the whole map. |
| The Serpentine Belt | Asteroid river forces linear formations; rewards mines. |
| Cyclone Cloud | Storm turbulence disrupts RCS and gyro stability. |
| The Twin Moons | Gravity assists and slingshots around tidally locked moons. |
| Solar Sanctuary | Dyson swarm panels as cover and hackable power objectives. |
| The Whispering Hollow | Acoustic anomaly; sound carries and warns of hidden enemies. |
| Crimson Horizon | Red supergiant light reduces contrast; small unlit craft nearly invisible. |

**10,000 km × 10,000 km × 10,000 km**

| Map | Effect |
| --- | --- |
| The Trinary Crossroads | Three stars create shifting shadows; constant repositioning of command posts. |
| Nebulous Expanse | Gas clouds block radar; hidden capital flanking. |
| The Outer Rim Asteroid Sea | Millions of planetoids; guerrilla and ambush tactics. |
| Stellar Nexus | Plasma streams and beacons; capture points boost shield regeneration. |
| Shattered Halo | Black-hole lensing distorts visuals; masked approach vectors. |

**1,000,000 km × 1,000,000 km × 1,000,000 km**

| Map | Effect |
| --- | --- |
| Solar System | Full star system; gravity wells, moon shadows, orbital rings, multi-hour campaigns, orbital bombardment. |
| The Binary Empire System | Two stars, stations and debris rings; frontlines need relays and radar coverage. |
| Prime Sanctuary System | Trinary system with Dyson swarms; sandbox for 80-ship mega-fleet wars. |

**✅ Decided**

- **Class limits per map:** they depend on each map; which map allows which classes is not decided yet.
- **Movement and distance:** no jump drive. Speed comes only from Newtonian force from the Thruster modules. Some maps could have a place, like in Star Wars, where ships travel at hyperspeed.
- **Physics layer** (orbits, drag, looting, mines): the maps have not been cleaned up yet; to decide later.
- **Spawns:** they depend on the mode, not on the map. In most modes teams spawn on opposite sides.

* **Speed:** there will be some hyperspeed lanes, but no speed cap. It is realistic: in space only the speed of light limits speed.
* **Class limits per map:** the developer will fill the map × class table himself for now.

---

## 4. Controls & Command Console

### 4.1 Perspectives

- **Commander Mode (third person):** exterior view of the ship, seated at an immersive physical command console representing the active commander station. The camera is as free as in Nebulous: Fleet Commander. A button press switches to first person.
- **Crew Mode (first person, in the Commander Post):** first-person view from the Commander Post, seeing outside through its faces that point to space, with access to the same console panels. Manual flight controls inspired by Star Citizen, Star Wars Outlaws or Starfield, with computer-assisted stabilization to prevent drift and make small ships easier to pilot. *Free-Float Cursor Toggle:* a key unlocks the mouse into a free cursor to click console buttons without steering.
- **Immersion & combat feedback:** direct hits trigger a flashing red warning light and camera shake; a 30-second timer of uninterrupted safety is required before shake can retrigger.
- **Top Notification Ticker:** unified alert banner. *Comms icon (speaker):* incoming text/audio, destroyed-module logs and remote status when comms are online. *Crew icon (face):* internal status, local alerts and crew reports when comms are jammed or destroyed.

* **Switching view:** first person and third person are one button press apart.
* **Going to another post (a turret, for example):** the camera waits for the walking time and then sits at the module. While there, it is as if nobody controls the ship: nothing can be commanded. This is mostly useful on ships with several players: one keeps controlling the ship while the other helps inside.
* **Ideal version:** a separate interior scene for each ship, loaded only for the players roaming inside that ship, so the camera does not wait and pop. The player enters first person, walks freely to any module and acts as real crew (repairing, going to the turret bay and shooting). It is a separate scene so that it does not drop the frame rate.
* **Commander camera:** as free as in Nebulous: Fleet Commander.

### 4.2 Console Panels

The commander console has five core panels plus sub-panels.

- **Panel 1, Ship Status & 3D Preview (right console):** interactive 3D ship model for structural damage and integrity, with Basic 3D, Exploded and Onion Slice tabs; minimal telemetry (heading vector, velocity, trajectory).
- **Panel 2 + Sub-Panel 2, Mode Selection & Tactical Control (central console):** quick-toggle between operational modes (see 4.3).
- **Panel 3, Module Management (left console):** category tabs and filters to inspect operational stats, health and power state per module type.
- **Panel 4, Tactical 3D Radar (mid-left console):** 3D sensor map with red dots for enemies and color-coded dots for friendlies, incoming projectiles and telemetry.
- **Panel 5, Mission Objectives & Chat (mid-right console):** objectives, task statuses and progress toward victory; a toggle switches the panel into the written team chat log.

🆕 **Rule:** the list of modes is fixed and every mode is always on the console. What changes is how well a mode works when its modules are missing or destroyed (no Radar Room means a degraded Panel 4), and a panel can be linked to a specific Commander Post.

### 4.3 Panel 2: Mode Selection, full specification 🆕

All the modes below are in the game and all are important; the list is fixed for every ship (decided). The actions under each mode are the working list.

| Mode | Sub-panel content / actions | Needs (module) |
| --- | --- | --- |
| **Movement** | *Direct:* thrust per axis, strafe, rotate, brake, boost, RCS-only fine mode, speed limiter/cruise, hold position. *Target-relative:* orbit, follow at offset, keep distance, face target, intercept, flee. Also waypoints and evasive patterns. *View 1:* standard flight camera. *View 2:* Tactical Radar Map (free long-distance camera, XZ plane positioning, altitude adjustment). Decided control schemes: assisted orders (drive toward, go to, orbit around), manual (direct input to control the ship), and assisted manual (manual input with stabilization, less drifty). | Engine Room, Thrusters, Gyro/RCS |
| **Combat** | Turret firing arcs, weapon orientation, primary target designation, multi-target distribution; weapon groups; fire modes (single/burst/hold); ammo type; target priority (nearest, weakest, module-specific); hold fire/free fire. | Turret Bay, Barrels |
| **Defense** | Defense Bay behavior (missiles, fighters, both), countermeasures launch, sector priority. | Defense Bay |
| **Sensors / Radar** | Active/passive toggle, range and sweep angle, lock target, mark/ping, share contacts, filters (ships, projectiles, debris), radar-silent mode. | Radar Room, Commander Post LoS |
| **Communications** | Team/crew channels, quick orders and pings, relay status, jamming/anti-jam. | Communication Room/Dish |
| **Crew Command** | *Damage Control:* inspect and repair damaged modules during comms blackouts. *Boarding Defense:* position crew at choke points. *Boarding Offense:* designate strike teams and targets. Plus crew priorities, recall, patrol. | Crew |
| **Boarding** | Launch Breach Pods, deploy/seal Breach Doors, choose targets and team size. | Breach Pods/Doors |
| **Hangar / Fleet** | Launch, recall, repair parasite craft; order drones; formation commands. | Hangar |
| **Power & Systems** | Power priority overrides, heat view and venting, module on/off, emergency shutdown, oxygen and bulkhead control, Gyro/RCS toggles. | Generator, hidden systems |
| **AI / Automation** | Choose which functions AI handles (targeting, flight assist, damage control) and aggressiveness profile. | AI core |
| **Tactical Map** | Fleet orders, map markers, objective tracking. *(Currently View 2 of Movement: keep as a sub-view or make its own mode?)* | Radar, Comms |

**For every mode, define:** the panel layout, available inputs (keyboard/controller/mouse), which modules are required, what the mode shows when a required module is destroyed, and whether another player on another Commander Post can use it at the same time.

- **Modes:** all of them are in, and all are important. The mode list is fixed for every ship.
- **Movement control:** inside the sub-panel there are buttons for drive toward, go to and orbit around, all assisted. There is also a manual mode (direct input) and an assisted manual mode (manual with stabilization to make it more controllable and less drifty).
- **Weapon types are modifiable:** the player makes a type (for example kinetic) and edits its size, speed, number fired and so on, which changes the damage and its type. *Kinetic:* deforms or penetrates. *Laser:* almost instant, near impossible to miss, can start fires, does not deform but can penetrate. *Missile:* can have aim assistance (like heat seeking through an integrated radar), explosion damage, high penetration, easier to detect. *Flak:* less precise but harder to avoid by number, makes explosions. *Mines:* stealthy and immobile, to catch the opponent by surprise.
- **Crew actions:** crew operate each module. A module needs one crew member, and more make it better: faster repairs, faster turret aim and fire, more power generated and so on.

---

## 5. Menus & Settings 🆕

**Menu structure (decided):** the main menu has four entries: **Multiplayer**, **SinglePlayer**, **Creation** and **Plus**. Selecting an entry extends a line showing its options: Multiplayer (host or join), SinglePlayer (Campaign, not available; Freematch, the base game against bots instead of players; Tutorial or Sandbox), Creation (Ship creation, Module creation, Download creation), Plus (Options, Credits, Quit). After Play (proposal): GameLobby (section 3.2) → Match → post-match summary (stats, ship damage report) → back to the lobby.

**Settings categories:**

- **Graphics:** resolution, display mode, quality presets, LOD distance, shadows, effects, draw-distance for ships/maps, framerate cap, VSync.
- **Audio:** master/music/effects/voice volumes, voice chat input/output, push-to-talk, spatial audio.
- **Controls:** full key rebinding per mode (Commander and Crew), controller support, mouse sensitivity, invert axes, free-cursor toggle key.
- **Gameplay:** assisted flight on/off, damage-feedback intensity (camera shake can be disabled), notification ticker options, units (m, km), UI scale.
- **Interface & accessibility:** colorblind modes (important for red/friendly radar dots), text size, subtitles for voice transcription, reduced flashing.
- **Network:** region, ping display, voice chat and text chat filters, privacy.
- **Ship Forge settings:** grid snapping defaults, viewport defaults, autosave, polygon-budget warnings.

* **Ship editor:** only reachable from the main menu (Creation); ships cannot be edited in game.
* **Profile:** only a profile showing games played, win/loss ratio, kill/death/assist ratio, average damage per game and small info like that.

---

## 6. Combat & Damage Model 🆕

There are no numbers yet in the draft. This section lists what must be defined so the module, link and class systems have something to balance against.

- **Damage layers:** hull (outer skin) → armor → internal modules → crew. Is damage applied to the *mesh hit location* (spatial, expensive but spectacular) or to a *module HP pool*?
- **Structural integrity:** can ships break apart, lose sections, or only lose modules? What happens to a hull cut in two?
- **Defenses:** shields (mentioned by maps), armor thickness (the Hull Thickness slider), point-defense, countermeasures, EMP resistance.
- **Weapon stats:** damage, fire rate, projectile speed, range, penetration, ammo, heat, power draw.
- **Fire and decompression:** hull breaches already drain oxygen; do fires, explosions or crew casualties follow?
- **Time-to-kill targets:** how long should a Fighter, a Cruiser and a Titan survive against equal-class fire?
- **Repair:** can damaged modules be repaired in combat (crew), only at a Hangar, or only after the match?

* **Destruction:** realistic, with debris, deformation, holes and sections tearing apart.
* **Friendly fire** can be toggled. **Ramming** is a damage type and the biggest reason for deformation, and it follows real-life rules: a big ship ramming a big ship barely moves the target and is pushed back itself; a small ship has a bigger chance of being sent flying.
* **Time-to-kill:** no target yet.

---

## 7. Technical Architecture & Optimization 🆕

Targets to write down: minimum/recommended hardware, target FPS, maximum ships in a match (80 players), maximum polygons per ship, and server tick rate.

**Ship geometry**

- Cap vertex/poly budget per ship (scaled by class) and show it live in the editor.
- Bake finished ships into optimized static meshes with hierarchical LODs, merged materials and impostors at long range.
- Use simplified collision (compound convex shapes), not mesh collision.
- Treat interiors separately: only load and simulate corridors, doors and crew near players or when relevant.
- Articulated Parts: animate as separate transforms with a simple collision proxy.

**Simulation**

- Run hidden systems (heat, power, oxygen, comms) as graph simulations at low fixed tick rates, lower still for distant ships.
- Distance-based simulation LOD: far ships use simplified damage; only nearby ones run full per-module physics.
- Projectiles: hitscan for lasers, pooled objects for missiles and ballistics.

**Large maps**

- Floating origin and/or double-precision coordinates for the 10,000 km and 1,000,000 km maps (standard 32-bit floats will jitter far from the origin).
- Instance asteroids and debris, stream chunks, render the far field as skybox/billboards.
- Spatial partitioning (grid or octree) for radar queries, collision and interest management.

**Networking (up to 80 players)**

- Peer-to-peer with the host running the match (decided: no dedicated servers for now). Send each ship's blueprint once, then only deltas (transforms, damage events, animation values).
- Interest management by radar range and distance; lower update rates for far entities.
- Save format: a compact versioned ship file (hull mesh, modules, links, interior paths, parts, cosmetics) with validation on upload to prevent cheating via edited files.

* **Platform:** PC only, at a basic PC performance level.
* **Ships are local files.** Even if the host does not have a ship, it can be used: the player's computer loads it and sends it to the host so it can spawn. Respawns do not reload everything, because the ship is saved and pooled.
* **Two copies of a ship:** a preloaded ship (never really played, no deformation) and the deformation ship (the one played, built with help from the preloaded one). Respawn uses the preloaded copy because undoing all the deformation would take too long.

---

## 8. Progression, Economy & Monetization 🆕

- **Progression:** none. Everything is unlocked from the start (decided).
- **Currencies:** none, since there is no progression to pay for.
- **Monetization:** undecided. Keep performance-affecting items out of paid systems to avoid pay-to-win.
- **Level:** game played, kills, damage gives exp

---

## 9. Scope & Roadmap 🆕

The full vision is very large. A proposed order of work:

1. **Prototype:** basic hull editor (extrude, mirror, snap), one module (Engine Room + Thruster), one test map, flight model.
2. **Core combat:** Turret Bay + Barrel, damage model with simple numbers, 1v1 on a 100 km map.
3. **Systems:** Generator, power priority, links, Commander Post, hidden systems (power, heat first).
4. **Multiplayer vertical slice:** lobby, host/join, one mode (Team Deathmatch), 2 classes.
5. **Classes & budget:** point system, legality check, map restrictions.
6. **Interior, crew & boarding.**
7. **Articulated parts, cosmetics, hangar.**
8. **Large maps, optimization pass, full mode list.**

- **MVP:** roadmap steps 1 to 6 (up to Interior, crew & boarding).
- **Team:** solo developer, working with AI.
