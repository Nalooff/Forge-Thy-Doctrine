class_name MapDefs
extends RefCounted
## The maps of the design doc (section 4.2.2): 15 maps of 100 km, 15 of 1,000 km, 5 of 10,000 km and 3 of 1,000,000 km,
## plus a small Test Range. A map is described, not stored: density fields (what fills the space and where) and far
## bodies (stars, planets, ...). MapStreamer turns the fields into objects around the player, chunk by chunk, from
## absolute coordinates only, so the content is the same for everybody and costs nothing where nobody is.
##
## field kinds: rock, ice, shard, monolith, wreck, lattice.  density = objects per km3 at the densest point.
## masks (where a field is): uniform, slab (|y| < half), sphere, shell (+ hemi = -1 lower half), torus, ribbon.

const KM := 1000.0
const SIZE_100 := 100.0 * KM
const SIZE_1000 := 1000.0 * KM
const SIZE_10000 := 10000.0 * KM
const SIZE_1M := 1000000.0 * KM

static var _all: Array = []


static func F(kind: String, density: float, rmin: float, rmax: float, col: Color, mask := {"type": "uniform"}, extra := {}) -> Dictionary:
	var d := {"kind": kind, "density": density, "rmin": rmin, "rmax": rmax, "color": col, "mask": mask}
	d.merge(extra)
	return d


static func B(kind: String, pos: Array, radius: float, col: Color, extra := {}) -> Dictionary:
	var d := {"kind": kind, "pos": pos, "radius": radius, "color": col}
	d.merge(extra)
	return d


static func _m(id: String, nm: String, size: float, desc: String, fields: Array, bodies: Array, sky := {}, spawn := [0.0, 0.0, 0.0]) -> Dictionary:
	var s := {"tint": Color(0.004, 0.005, 0.011), "fog": 0.0, "fog_color": Color(0.1, 0.1, 0.14), "sun_color": Color(1.0, 0.96, 0.9), "sun_energy": 1.6, "ambient": Color(0.25, 0.28, 0.38)}
	s.merge(sky, true)
	return {"id": id, "name": nm, "size": size, "desc": desc, "fields": fields, "bodies": bodies, "sky": s, "spawn": spawn, "seed": hash(id) & 0x7fffffff}


static func all() -> Array:
	if _all.is_empty():
		_all = _build()
	return _all


static func get_def(id: String) -> Dictionary:
	for d in all():
		if String(d["id"]) == id:
			return d
	return all()[0]


static func half_extent(d: Dictionary) -> float:
	return float(d["size"]) * 0.5


## Distance between the two teams' spawn points (and from the centre to each): grows with the map, up to 30 km.
static func spawn_dist(d: Dictionary) -> float:
	return clampf(float(d["size"]) * 0.05, 1300.0, 30000.0)


## Places that must stay free of rocks: [[x, y, z, radius], ...] (the spawn points of both teams).
static func keep_out(d: Dictionary) -> Array:
	var sp: Array = d["spawn"]
	var sd := spawn_dist(d)
	var r := 500.0
	return [[sp[0], sp[1], sp[2], r], [sp[0], sp[1], sp[2] + sd, r], [sp[0], sp[1], sp[2] - sd, r]]


static func size_label(d: Dictionary) -> String:
	var km := int(float(d["size"]) / KM)
	var txt := str(km)
	var out := ""
	for i in range(txt.length()):
		if i > 0 and (txt.length() - i) % 3 == 0:
			out += ","
		out += txt[i]
	return out + " km"


## Density of a field (0..1) at an absolute position.
static func mask_value(mask: Dictionary, p: Vec3D) -> float:
	match String(mask["type"]):
		"uniform":
			return 1.0
		"slab":
			return 1.0 if absf(p.y - float(mask.get("y", 0.0))) < float(mask["half"]) else 0.0
		"sphere":
			var c: Array = mask["c"]
			return 1.0 if Vector3(p.x - c[0], p.y - c[1], p.z - c[2]).length() < float(mask["r"]) else 0.0
		"shell":
			var c2: Array = mask["c"]
			var d := Vector3(p.x - c2[0], p.y - c2[1], p.z - c2[2])
			if float(mask.get("hemi", 0.0)) != 0.0 and d.y * float(mask["hemi"]) < 0.0:
				return 0.0
			return clampf(1.0 - absf(d.length() - float(mask["r"])) / float(mask["t"]), 0.0, 1.0)
		"torus":
			var c3: Array = mask["c"]
			var n: Array = mask.get("n", [0.0, 1.0, 0.0])
			var nv := Vector3(n[0], n[1], n[2]).normalized()
			var d3 := Vector3(p.x - c3[0], p.y - c3[1], p.z - c3[2])
			var h := d3.dot(nv)
			var rad := (d3 - nv * h).length()
			var q := Vector2(rad - float(mask["R"]), h).length()
			return clampf(1.0 - q / float(mask["r"]), 0.0, 1.0)
		"ribbon":
			var wx := float(mask["amp"]) * sin(p.z / float(mask["wave"]))
			return clampf(1.0 - Vector2(p.x - wx, p.y).length() / float(mask["width"]), 0.0, 1.0)
	return 0.0


static func _build() -> Array:
	var rockc := Color(0.32, 0.29, 0.27)
	var dark := Color(0.12, 0.11, 0.12)
	var metal := Color(0.62, 0.64, 0.68)
	var iceb := Color(0.75, 0.9, 1.0)
	var crystal := Color(0.45, 0.75, 1.0)
	var out: Array = []
	# ---- test range (the old arena: a field around the start)
	out.append(_m("range", "Test Range", 20.0 * KM, "A small field of rocks to learn the ship in.", [F("rock", 0.9, 15, 90, rockc, {"type": "slab", "half": 700.0})], []))
	# ---- 100 km
	out.append(_m("shard_graveyard", "The Shard Graveyard", SIZE_100, "Shattered crystalline moon in a shimmering dust field; shards block line of sight completely.",
		[F("shard", 0.7, 20, 140, crystal), F("rock", 0.2, 10, 40, Color(0.4, 0.55, 0.7))], [B("star", [4.0e7, 2.0e7, -8.0e7], 2.0e6, Color(0.8, 0.9, 1.0))], {"fog": 0.00004, "fog_color": Color(0.25, 0.4, 0.6), "tint": Color(0.01, 0.02, 0.05)}))
	out.append(_m("cinder_core", "Cinder Core", SIZE_100, "Orbiting a dying hyper-dense white dwarf; thermal and electromagnetic radiation floods the map.",
		[F("rock", 0.3, 10, 60, Color(0.45, 0.4, 0.38))], [B("star", [0.0, 3.0e6, -4.0e7], 4.0e6, Color(1.0, 1.0, 1.0), {"power": 3.0})], {"sun_energy": 3.2, "sun_color": Color(1.0, 1.0, 1.0), "tint": Color(0.03, 0.03, 0.04)}))
	out.append(_m("echo_nebula", "Echo Nebula", SIZE_100, "A small pocket of purple and blue ion gas; sensor sweeps and long-range comms are distorted.",
		[F("rock", 0.25, 12, 60, rockc)], [B("nebula", [0.0, 0.0, -2.0e7], 3.0e7, Color(0.5, 0.3, 1.0))], {"fog": 0.00012, "fog_color": Color(0.35, 0.2, 0.7), "tint": Color(0.03, 0.01, 0.07)}))
	out.append(_m("iron_ring", "The Iron Ring", SIZE_100, "A tightly packed artificial orbital ring falling slowly into a dead planet.",
		[F("wreck", 1.6, 25, 160, Color(0.35, 0.33, 0.32), {"type": "torus", "c": [0.0, 0.0, -30000.0], "R": 30000.0, "r": 2500.0, "n": [1.0, 0.0, 0.0]})], [B("planet", [0.0, -5.0e6, -6.0e7], 2.5e7, Color(0.28, 0.22, 0.2))]))
	out.append(_m("glinting_hollow", "Glinting Hollow", SIZE_100, "A dense reflective metallic asteroid cluster rich in hyper-conductive ores.",
		[F("rock", 1.5, 20, 120, metal)], [B("star", [-6.0e7, 1.0e7, 3.0e7], 1.5e6, Color(1.0, 0.95, 0.85))], {"sun_energy": 2.2}))
	out.append(_m("vipers_nest", "Viper's Nest", SIZE_100, "A collapsing cluster of carbonaceous rocks peppered with pockets of volatile gas.",
		[F("rock", 1.0, 20, 110, dark)], [B("nebula", [2.0e4, 0.0, 0.0], 4.0e4, Color(0.4, 0.8, 0.3))], {"fog": 0.00006, "fog_color": Color(0.2, 0.35, 0.12)}))
	out.append(_m("obsidian_veil", "Obsidian Veil", SIZE_100, "A dark-matter dust cloud that absorbs ambient light; the map is pitch black.",
		[F("rock", 0.35, 12, 70, dark)], [], {"fog": 0.0003, "fog_color": Color(0.0, 0.0, 0.0), "ambient": Color(0.02, 0.02, 0.03), "sun_energy": 0.15, "tint": Color(0, 0, 0)}))
	out.append(_m("stellar_spark", "Stellar Spark", SIZE_100, "A young erratic protostar throwing off frequent solar flare arcs.",
		[F("shard", 0.25, 10, 50, Color(1.0, 0.55, 0.2))], [B("star", [3.0e7, 0.0, -3.0e7], 3.0e6, Color(1.0, 0.45, 0.2), {"power": 2.0})], {"sun_color": Color(1.0, 0.6, 0.35)}))
	out.append(_m("rust_caldera", "The Rust Caldera", SIZE_100, "The hollowed-out iron-rich mantle of a split planet; fight in the giant concave bowl.",
		[F("rock", 2.0, 20, 160, Color(0.45, 0.25, 0.15), {"type": "shell", "c": [0.0, 20000.0, 0.0], "r": 30000.0, "t": 6000.0, "hemi": -1.0})], [B("star", [0.0, 6.0e7, -1.0e7], 2.0e6, Color(1.0, 0.85, 0.7))], {"tint": Color(0.04, 0.02, 0.01)}))
	out.append(_m("frozen_prism", "Frozen Prism", SIZE_100, "Nitrogen and water-ice mega-comets sublimating under distant starlight; vapor trails make smoke screens.",
		[F("ice", 0.9, 30, 200, iceb), F("shard", 0.2, 10, 60, Color(0.8, 0.95, 1.0))], [B("star", [-5.0e7, 0.0, 2.0e7], 1.2e6, Color(0.9, 0.95, 1.0))], {"fog": 0.00003, "fog_color": Color(0.5, 0.65, 0.8)}))
	out.append(_m("gorgons_eye", "Gorgon's Eye", SIZE_100, "A dense asteroid belt circling a tiny pulsing magnetar.",
		[F("rock", 2.2, 15, 90, rockc, {"type": "torus", "c": [0.0, 0.0, -25000.0], "R": 25000.0, "r": 5000.0, "n": [0.0, 1.0, 0.1]})], [B("star", [0.0, 0.0, -9.0e7], 8.0e5, Color(0.6, 0.8, 1.0), {"power": 2.5})]))
	out.append(_m("labyrinth", "The Labyrinth", SIZE_100, "An artificial matrix of interlocking structural scaffolding; perfect for hit and run.",
		[F("lattice", 1.0, 20, 40, Color(0.4, 0.42, 0.46), {"type": "slab", "half": 3000.0}, {"spacing": 600.0})], []))
	out.append(_m("solar_flare_basin", "Solar Flare Basin", SIZE_100, "The edge of a yellow star's corona; solar wind pushes ships along one vector.",
		[F("rock", 0.4, 12, 60, Color(0.5, 0.42, 0.33))], [B("star", [0.0, 0.0, -2.2e7], 1.0e7, Color(1.0, 0.85, 0.4), {"power": 3.0})], {"sun_color": Color(1.0, 0.85, 0.55), "sun_energy": 2.6, "tint": Color(0.06, 0.03, 0.0)}))
	out.append(_m("ashen_spire", "Ashen Spire", SIZE_100, "Towering needle-like basalt monoliths floating vertically; terrain masking for nimble ships.",
		[F("monolith", 0.5, 30, 130, Color(0.2, 0.2, 0.22))], [B("star", [6.0e7, 3.0e7, 1.0e7], 1.5e6, Color(1.0, 0.8, 0.6))]))
	out.append(_m("null_g_sanctuary", "Null-G Sanctuary", SIZE_100, "A calm dust-free pocket enclosed by a shimmering ring of silicate space moss.",
		[F("rock", 1.2, 25, 90, Color(0.3, 0.75, 0.5), {"type": "shell", "c": [0.0, 0.0, 0.0], "r": 45000.0, "t": 7000.0})], [B("star", [0.0, 5.0e7, 5.0e7], 1.4e6, Color(1.0, 1.0, 0.95))]))
	# ---- 1,000 km
	out.append(_m("binary_cradle", "Binary Cradle", SIZE_1000, "A balanced binary star system casting double shadows over rocky moonlets.",
		[F("rock", 0.25, 40, 400, Color(0.4, 0.37, 0.35))], [B("star", [-1.5e8, 2.0e7, -3.0e8], 1.5e7, Color(1.0, 0.7, 0.4), {"power": 2.0}), B("star", [2.0e8, -1.0e7, -3.5e8], 1.0e7, Color(0.6, 0.75, 1.0), {"power": 1.5})]))
	out.append(_m("veil_of_sirens", "The Veil of Sirens", SIZE_1000, "A sweeping golden emission nebula with dense pockets of cosmic dust.",
		[F("rock", 0.3, 20, 120, Color(0.5, 0.4, 0.2))], [B("nebula", [0.0, 0.0, -3.0e8], 8.0e8, Color(1.0, 0.75, 0.3))], {"fog": 0.00005, "fog_color": Color(0.5, 0.38, 0.12), "tint": Color(0.05, 0.035, 0.0)}))
	out.append(_m("titans_gate", "Titan's Gate", SIZE_1000, "A massive natural archway of planetary crust floating between two dead worlds.",
		[F("rock", 1.4, 80, 900, Color(0.38, 0.33, 0.3), {"type": "torus", "c": [0.0, 0.0, -200000.0], "R": 200000.0, "r": 40000.0, "n": [1.0, 0.0, 0.0]})], [B("planet", [-4.0e8, 0.0, -2.0e8], 1.2e8, Color(0.3, 0.25, 0.22)), B("planet", [4.0e8, 0.0, -2.0e8], 1.0e8, Color(0.26, 0.28, 0.32))]))
	out.append(_m("shattered_ring", "The Shattered Ring", SIZE_1000, "Continent-sized fragments of a destroyed ring-world drift in slow rotation.",
		[F("wreck", 0.15, 400, 3000, Color(0.5, 0.5, 0.55), {"type": "torus", "c": [0.0, 0.0, -300000.0], "R": 300000.0, "r": 80000.0, "n": [0.0, 1.0, 0.0]})], [B("star", [3.0e8, 1.0e8, -4.0e8], 2.0e7, Color(1.0, 0.95, 0.85))]))
	out.append(_m("comets_wake", "Comet's Wake", SIZE_1000, "A swarm of active comets trailing millions of kilometers of ice crystals.",
		[F("ice", 0.5, 40, 500, iceb, {"type": "ribbon", "amp": 60000.0, "wave": 40000.0, "width": 120000.0}), F("shard", 0.6, 10, 80, Color(0.85, 0.95, 1.0), {"type": "ribbon", "amp": 60000.0, "wave": 40000.0, "width": 160000.0})], [B("star", [-2.0e8, 0.0, 3.0e8], 1.0e7, Color(1.0, 0.95, 0.8))], {"fog": 0.000025, "fog_color": Color(0.5, 0.65, 0.85)}))
	out.append(_m("auroran_expanse", "Auroran Expanse", SIZE_1000, "Planet-sized auroras glow in emerald and violet.",
		[F("rock", 0.15, 30, 250, rockc)], [B("planet", [0.0, -1.5e8, -4.0e8], 1.6e8, Color(0.2, 0.5, 0.45)), B("nebula", [0.0, 0.0, -3.0e8], 5.0e8, Color(0.3, 1.0, 0.7))], {"tint": Color(0.0, 0.04, 0.03)}))
	out.append(_m("graveyard_of_giants", "The Graveyard of Giants", SIZE_1000, "A battlefield littered with the wrecked hulls of ancient, continent-sized vessels.",
		[F("wreck", 0.12, 300, 2200, Color(0.32, 0.3, 0.3))], [B("star", [2.5e8, 0.0, 2.0e8], 1.2e7, Color(0.95, 0.9, 0.8))]))
	out.append(_m("prismatic_dustway", "Prismatic Dustway", SIZE_1000, "A cosmic highway of light-refracting silicate crystals.",
		[F("shard", 1.0, 20, 200, Color(0.9, 0.6, 1.0)), F("shard", 0.6, 20, 160, Color(0.5, 1.0, 0.8)), F("shard", 0.6, 20, 160, Color(1.0, 0.8, 0.4))], [B("star", [-3.0e8, 5.0e7, -1.0e8], 1.5e7, Color(1.0, 0.98, 0.95))]))
	out.append(_m("obsidian_reach", "Obsidian Reach", SIZE_1000, "A pitch-black region overshadowed by an immense non-luminous dark star.",
		[F("rock", 0.1, 20, 120, dark)], [B("star", [0.0, 5.0e7, -3.0e8], 2.0e8, Color(0.02, 0.0, 0.0), {"power": 0.0})], {"ambient": Color(0.03, 0.02, 0.02), "sun_energy": 0.2, "tint": Color(0.0, 0.0, 0.0)}))
	out.append(_m("serpentine_belt", "The Serpentine Belt", SIZE_1000, "A winding, densely packed asteroid river curving across the sector.",
		[F("rock", 1.6, 30, 300, rockc, {"type": "ribbon", "amp": 120000.0, "wave": 70000.0, "width": 25000.0})], [B("star", [2.0e8, 3.0e7, -2.0e8], 1.0e7, Color(1.0, 0.9, 0.7))]))
	out.append(_m("cyclone_cloud", "Cyclone Cloud", SIZE_1000, "A massive swirling vortex of space storm clouds driven by stellar winds.",
		[F("rock", 0.8, 20, 150, Color(0.35, 0.3, 0.45), {"type": "torus", "c": [0.0, 0.0, -50000.0], "R": 50000.0, "r": 30000.0, "n": [0.0, 1.0, 0.0]})], [B("nebula", [0.0, 0.0, -1.0e8], 4.0e8, Color(0.6, 0.4, 0.9))], {"fog": 0.00009, "fog_color": Color(0.3, 0.2, 0.45)}))
	out.append(_m("twin_moons", "The Twin Moons", SIZE_1000, "Two rocky, tidally locked moons orbiting a shared barycenter.",
		[F("rock", 0.12, 30, 200, rockc)], [B("planet", [-1.2e8, 0.0, -3.0e8], 4.5e7, Color(0.55, 0.52, 0.5)), B("planet", [1.2e8, 0.0, -3.0e8], 4.0e7, Color(0.45, 0.42, 0.45)), B("star", [4.0e8, 1.0e8, 2.0e8], 1.8e7, Color(1.0, 0.95, 0.85))]))
	out.append(_m("solar_sanctuary", "Solar Sanctuary", SIZE_1000, "A stable yellow star surrounded by a Dyson swarm of incomplete energy-harvesting panels.",
		[F("wreck", 0.35, 200, 1200, Color(0.6, 0.62, 0.7), {"type": "shell", "c": [0.0, 0.0, -150000.0], "r": 150000.0, "t": 30000.0})], [B("star", [0.0, 0.0, -2.0e8], 2.2e7, Color(1.0, 0.9, 0.55), {"power": 2.0})], {"sun_energy": 2.2}))
	out.append(_m("whispering_hollow", "The Whispering Hollow", SIZE_1000, "An acoustic anomaly zone where low-frequency space waves carry noise across vast distances.",
		[F("rock", 0.15, 25, 160, rockc)], [B("nebula", [0.0, 0.0, -2.0e8], 5.0e8, Color(0.3, 0.8, 0.8))], {"fog": 0.00003, "fog_color": Color(0.1, 0.3, 0.32)}))
	out.append(_m("crimson_horizon", "Crimson Horizon", SIZE_1000, "Bathed in the deep red light of a giant red supergiant.",
		[F("rock", 0.2, 25, 180, Color(0.35, 0.2, 0.2))], [B("star", [0.0, 0.0, -4.5e8], 1.2e8, Color(1.0, 0.25, 0.15), {"power": 2.0})], {"sun_color": Color(1.0, 0.35, 0.25), "tint": Color(0.05, 0.0, 0.0)}))
	# ---- 10,000 km
	out.append(_m("trinary_crossroads", "The Trinary Crossroads", SIZE_10000, "Three stars dance in a stable gravitational figure-eight.",
		[F("rock", 0.06, 40, 300, rockc)], [B("star", [-1.5e9, 0.0, -3.0e9], 6.0e7, Color(1.0, 0.8, 0.5)), B("star", [1.5e9, 2.0e8, -3.0e9], 5.0e7, Color(0.7, 0.8, 1.0)), B("star", [0.0, -3.0e8, -4.0e9], 7.0e7, Color(1.0, 0.5, 0.4))]))
	out.append(_m("nebulous_expanse", "Nebulous Expanse", SIZE_10000, "A massive stellar nursery of glowing gas pillars and newly forming protostars.",
		[F("monolith", 0.02, 500, 3000, Color(0.7, 0.45, 0.4))], [B("nebula", [0.0, 0.0, -3.0e9], 6.0e9, Color(1.0, 0.4, 0.5)), B("star", [8.0e8, 0.0, -2.0e9], 3.0e7, Color(1.0, 0.7, 0.6))], {"fog": 0.00002, "fog_color": Color(0.35, 0.12, 0.18)}))
	out.append(_m("outer_rim_asteroid_sea", "The Outer Rim Asteroid Sea", SIZE_10000, "A vast dispersed sea of millions of small planetoids and rogue ice bodies.",
		[F("rock", 1.8, 12, 120, rockc), F("ice", 0.4, 15, 140, iceb)], [B("star", [0.0, 1.0e9, -3.0e9], 5.0e7, Color(1.0, 0.95, 0.85))]))
	out.append(_m("stellar_nexus", "Stellar Nexus", SIZE_10000, "A cosmic intersection dense with plasma streams and ancient navigational beacons.",
		[F("shard", 0.5, 20, 120, Color(0.4, 0.8, 1.0), {"type": "ribbon", "amp": 3.0e5, "wave": 2.0e5, "width": 1.2e5}), F("monolith", 0.03, 60, 200, Color(0.9, 0.9, 1.0))], [B("star", [0.0, 0.0, -2.5e9], 4.0e7, Color(0.7, 0.85, 1.0))]))
	out.append(_m("shattered_halo", "Shattered Halo", SIZE_10000, "A colossal ring system around an invisible rogue black hole; gravitational lensing warps the light.",
		[F("ice", 0.9, 40, 400, iceb, {"type": "torus", "c": [0.0, 0.0, -2.0e6], "R": 2.0e6, "r": 5.0e5, "n": [0.0, 1.0, 0.0]})], [B("blackhole", [0.0, 0.0, -2.0e9], 5.0e7, Color(0.0, 0.0, 0.0))]))
	# ---- 1,000,000 km
	out.append(_m("solar_system", "Solar System", SIZE_1M, "A complete living star system: central sun, inner rocky planets, an asteroid belt, outer gas giants with rings.",
		[F("rock", 0.0004, 30, 600, rockc, {"type": "torus", "c": [0.0, 0.0, 0.0], "R": 3.0e8, "r": 4.0e7, "n": [0.0, 1.0, 0.0]})],
		[B("star", [0.0, 0.0, 0.0], 6.0e7, Color(1.0, 0.92, 0.65), {"power": 3.0}), B("planet", [1.0e8, 0.0, 0.0], 1.5e6, Color(0.6, 0.55, 0.5)), B("planet", [1.6e8, 0.0, 1.2e8], 3.5e6, Color(0.9, 0.7, 0.4)), B("planet", [-2.2e8, 0.0, 1.0e8], 4.0e6, Color(0.3, 0.5, 0.85)), B("planet", [0.0, 0.0, -2.6e8], 2.2e6, Color(0.75, 0.4, 0.25)), B("gas", [4.0e8, 0.0, 3.0e8], 3.5e7, Color(0.85, 0.7, 0.55), {"ring": true}), B("gas", [-4.8e8, 0.0, -2.0e8], 3.0e7, Color(0.8, 0.8, 0.6), {"ring": true})],
		{"sun_energy": 2.4}, [2.0e8, 0.0, 0.0]))
	out.append(_m("binary_empire", "The Binary Empire System", SIZE_1M, "Two contrasting stars, a blue hypergiant and a red dwarf, with inhabited stations and debris rings.",
		[F("wreck", 0.00015, 100, 1200, Color(0.5, 0.52, 0.58), {"type": "torus", "c": [-2.0e8, 0.0, 0.0], "R": 1.8e8, "r": 3.0e7, "n": [0.0, 1.0, 0.0]})],
		[B("star", [-2.0e8, 0.0, 0.0], 8.0e7, Color(0.55, 0.7, 1.0), {"power": 3.0}), B("star", [3.0e8, 0.0, 0.0], 2.5e7, Color(1.0, 0.4, 0.3), {"power": 1.5}), B("planet", [1.0e8, 0.0, 2.0e8], 2.5e6, Color(0.5, 0.6, 0.5))], {"sun_color": Color(0.8, 0.88, 1.0)}, [0.0, 0.0, 0.0]))
	out.append(_m("prime_sanctuary", "Prime Sanctuary System", SIZE_1M, "A pristine trinary system surrounded by ancient Dyson swarms and deep-space gas clouds.",
		[F("wreck", 0.0006, 150, 1500, Color(0.6, 0.62, 0.7), {"type": "shell", "c": [0.0, 0.0, 0.0], "r": 3.0e8, "t": 6.0e7}), F("monolith", 0.00005, 300, 900, Color(0.7, 0.7, 0.8))],
		[B("star", [0.0, 0.0, 0.0], 4.0e7, Color(1.0, 0.95, 0.8), {"power": 2.5}), B("star", [8.0e7, 2.0e7, 6.0e7], 2.5e7, Color(0.8, 0.85, 1.0)), B("star", [-9.0e7, -1.0e7, 5.0e7], 2.0e7, Color(1.0, 0.7, 0.5)), B("nebula", [0.0, 0.0, -3.0e8], 5.0e8, Color(0.4, 0.5, 0.9))], {"fog": 0.0000004, "fog_color": Color(0.1, 0.12, 0.25)}, [0.0, 0.0, 2.0e8]))
	return out
