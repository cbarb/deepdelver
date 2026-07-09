extends Node
## GameData (autoload)
## Single source of truth for all balancing/definition data.
## Everything here is data-driven so new biomes, resources, upgrades and skills
## can be added without touching gameplay code.

# ---------------------------------------------------------------------------
# RESOURCES  ( id -> display data + coin value )
# ---------------------------------------------------------------------------
var RESOURCES := {
	# Rubble tiers (rubble_1..rubble_10, one per biome) are injected in _ready();
	# deeper biomes drop higher-tier rubble that crushes into more coins.
	"rock":           {"name": "Rock",            "color": Color8(178, 174, 166), "value": 1},
	"wood":           {"name": "Wood Roots",      "color": Color8(146, 104, 62),  "value": 2},
	"copper":         {"name": "Copper",          "color": Color8(206, 120, 66),  "value": 6},
	"coal":           {"name": "Coal",            "color": Color8(70, 70, 78),    "value": 5},
	"iron":           {"name": "Iron",            "color": Color8(158, 132, 116), "value": 12},
	"resin":          {"name": "Resin",           "color": Color8(224, 158, 64),  "value": 10},
	"cave_moss":      {"name": "Cave Moss",       "color": Color8(120, 186, 88),  "value": 8},
	"blue_crystal":   {"name": "Blue Crystal",    "color": Color8(78, 150, 232),  "value": 30},
	"quartz":         {"name": "Quartz",          "color": Color8(234, 238, 248), "value": 18},
	"silver":         {"name": "Silver",          "color": Color8(206, 210, 220), "value": 40},
	"ember":          {"name": "Ember Ore",       "color": Color8(255, 124, 44),  "value": 28},
	"sulfur":         {"name": "Sulfur",          "color": Color8(224, 204, 64),  "value": 22},
	"obsidian":       {"name": "Obsidian",        "color": Color8(90, 80, 120),   "value": 45},
	"relic":          {"name": "Relic Shard",     "color": Color8(92, 164, 152),  "value": 90},
	"gold":           {"name": "Gold",            "color": Color8(244, 192, 72),  "value": 60},
	"rune":           {"name": "Rune Stone",      "color": Color8(92, 182, 232),  "value": 110},
	"mycelium":       {"name": "Mycelium",        "color": Color8(224, 218, 228), "value": 35},
	"glowcap":        {"name": "Glowcap",         "color": Color8(226, 92, 124),  "value": 45},
	"deep_iron":      {"name": "Deep Iron",       "color": Color8(150, 138, 128), "value": 50},
	"titanium":       {"name": "Titanium",        "color": Color8(188, 198, 212), "value": 130},
	"pressure_gem":   {"name": "Pressure Gem",    "color": Color8(120, 222, 232), "value": 200},
	"black_coal":     {"name": "Black Coal",      "color": Color8(55, 55, 62),    "value": 55},
	"astral":         {"name": "Astral Shard",    "color": Color8(176, 156, 255), "value": 320},
	"prismatic":      {"name": "Prismatic Crystal","color": Color8(180, 120, 230),"value": 400},
	"moon":           {"name": "Moon Ore",        "color": Color8(224, 228, 242), "value": 280},
	"heartstone":     {"name": "Heartstone",      "color": Color8(255, 64, 74),   "value": 650},
	"core_fragment":  {"name": "Core Fragment",   "color": Color8(255, 202, 92),  "value": 850},
	"ancient_energy": {"name": "Ancient Energy",  "color": Color8(122, 230, 255), "value": 1200},
}

# ---------------------------------------------------------------------------
# BIOMES  (index 0..9)  -- depth in meters, 1 grid row == 1 meter.
# ---------------------------------------------------------------------------
# Depth thresholds (upper bound, meters) that separate biomes.
var _thresholds := [25, 75, 150, 250, 400, 600, 850, 1150, 1500]

var BIOMES := []

# Per-biome tile HP by category (index 0..9). From the balance-pass PDF.
# Categories: filler, common (resource), rare (resource), barrier.
var TILE_HP := [
	{"filler": 3,    "common": 5,    "rare": 8,    "barrier": 10},
	{"filler": 10,   "common": 15,   "rare": 22,   "barrier": 30},
	{"filler": 24,   "common": 36,   "rare": 52,   "barrier": 70},
	{"filler": 50,   "common": 75,   "rare": 110,  "barrier": 150},
	{"filler": 95,   "common": 140,  "rare": 210,  "barrier": 290},
	{"filler": 170,  "common": 250,  "rare": 380,  "barrier": 520},
	{"filler": 300,  "common": 450,  "rare": 680,  "barrier": 900},
	{"filler": 520,  "common": 780,  "rare": 1150, "barrier": 1550},
	{"filler": 900,  "common": 1350, "rare": 2000, "barrier": 2700},
	{"filler": 1550, "common": 2300, "rare": 3500, "barrier": 4700},
]

# Per-biome tile-category distribution (fractions summing to 1). From the PDF.
var TILE_DISTRIBUTION := [
	{"filler": 0.72, "common": 0.22, "rare": 0.04, "barrier": 0.02},
	{"filler": 0.74, "common": 0.20, "rare": 0.04, "barrier": 0.02},
	{"filler": 0.76, "common": 0.18, "rare": 0.04, "barrier": 0.02},
	{"filler": 0.78, "common": 0.16, "rare": 0.04, "barrier": 0.02},
	{"filler": 0.80, "common": 0.15, "rare": 0.03, "barrier": 0.02},
	{"filler": 0.81, "common": 0.14, "rare": 0.03, "barrier": 0.02},
	{"filler": 0.82, "common": 0.13, "rare": 0.03, "barrier": 0.02},
	{"filler": 0.83, "common": 0.12, "rare": 0.03, "barrier": 0.02},
	{"filler": 0.84, "common": 0.11, "rare": 0.03, "barrier": 0.02},
	{"filler": 0.85, "common": 0.10, "rare": 0.03, "barrier": 0.02},
]

# Cluster sizes for the generator (PDF cluster rules).
const COMMON_VEIN := [3, 8]      # common resources appear in veins of 3-8
const RARE_CLUSTER := [1, 4]     # rare resources appear in clusters of 1-4
const BARRIER_CLUSTER := [1, 2]  # barriers are single blocks or tiny pockets

func tile_hp(biome_index: int, category: String) -> int:
	var bi := clampi(biome_index, 0, TILE_HP.size() - 1)
	return int(TILE_HP[bi].get(category, TILE_HP[bi]["filler"]))

func tile_distribution(biome_index: int) -> Dictionary:
	return TILE_DISTRIBUTION[clampi(biome_index, 0, TILE_DISTRIBUTION.size() - 1)]

func _biome(id, name, depth_lo, depth_hi, fillers, resources, barrier, exp_f, exp_r) -> Dictionary:
	return {
		"id": id, "name": name, "depth_lo": depth_lo, "depth_hi": depth_hi,
		"fillers": fillers, "resources": resources, "barrier": barrier,
		"exp_filler": exp_f, "exp_resource": exp_r,
	}

func _f(id, name, col, w) -> Dictionary:
	return {"id": id, "name": name, "color": col, "weight": w}

# A resource def. `rarity` is "common" (default) or "rare" -> picks its HP tier.
func _r(id, w, amt_lo, amt_hi, glow := false, rarity := "common") -> Dictionary:
	return {"id": id, "weight": w, "amount": [amt_lo, amt_hi], "glow": glow, "rarity": rarity}

# A barrier def: tough, no-drop block. No texture id -> renders as a flat dark cube.
func _bar(id, name, col) -> Dictionary:
	return {"id": id, "name": name, "color": col}

# Coins that ONE unit of each biome's rubble is worth at Crusher Lv 1 (deeper =
# more). Crusher level multiplies this. Index 0 = biome 1 ... 9 = biome 10.
const RUBBLE_VALUE := [1, 2, 4, 7, 12, 20, 34, 57, 96, 160]

func _ready() -> void:
	# Inject the per-biome rubble tiers into RESOURCES: "Rubble I".."Rubble X",
	# tinted grey -> warm as they get deeper, with rising coin value.
	for i in range(RUBBLE_VALUE.size()):
		var tint: Color = Color8(120, 118, 112).lerp(Color8(206, 172, 118), float(i) / float(RUBBLE_VALUE.size() - 1))
		RESOURCES["rubble_%d" % (i + 1)] = {
			"name": "Rubble %s" % _roman(i + 1), "color": tint, "value": RUBBLE_VALUE[i]}

	BIOMES = [
		_biome(0, "Shallow Dirtworks", 0, 25, [
			_f("dirt", "Dirt", Color8(138, 98, 62), 50),
			_f("packed_dirt", "Packed Dirt", Color8(112, 78, 48), 30),
			_f("loose_stone", "Loose Stone", Color8(142, 136, 126), 20),
		], [
			_r("rock", 12, 1, 3), _r("wood", 7, 1, 2, false, "rare"),
		], _bar("barrier_1", "Bedrock", Color8(60, 44, 30)), 1, 4),

		_biome(1, "Stone Veins", 25, 75, [
			_f("stone", "Stone", Color8(128, 128, 132), 46),
			_f("gravel", "Gravel", Color8(122, 118, 112), 30),
			_f("hard_dirt", "Hard Dirt", Color8(100, 74, 52), 24),
		], [
			_r("copper", 9, 1, 3, false, "rare"), _r("coal", 9, 1, 3), _r("rock", 6, 1, 2),
		], _bar("barrier_2", "Bedrock", Color8(50, 50, 54)), 2, 7),

		_biome(2, "Moss Caverns", 75, 150, [
			_f("damp_stone", "Damp Stone", Color8(96, 106, 106), 44),
			_f("mossy_dirt", "Mossy Dirt", Color8(92, 86, 58), 32),
			_f("clay", "Clay", Color8(152, 112, 88), 24),
		], [
			_r("iron", 8, 1, 3, false, "rare"), _r("resin", 7, 1, 2, true), _r("cave_moss", 8, 1, 3, true),
		], _bar("barrier_3", "Bedrock", Color8(40, 52, 48)), 3, 11),

		_biome(3, "Crystal Hollow", 150, 250, [
			_f("pale_stone", "Pale Stone", Color8(178, 180, 188), 46),
			_f("crystal_dust", "Crystal Dust", Color8(172, 178, 198), 30),
			_f("brittle_rock", "Brittle Rock", Color8(150, 150, 158), 24),
		], [
			_r("blue_crystal", 6, 1, 2, true), _r("quartz", 8, 1, 3, true), _r("silver", 6, 1, 2, false, "rare"),
		], _bar("barrier_4", "Bedrock", Color8(70, 72, 84)), 4, 16),

		_biome(4, "Emberstone Layer", 250, 400, [
			_f("dark_stone", "Dark Stone", Color8(66, 62, 64), 46),
			_f("ash", "Ash", Color8(92, 86, 84), 30),
			_f("burnt_rock", "Burnt Rock", Color8(58, 50, 48), 24),
		], [
			_r("ember", 7, 1, 3, true), _r("sulfur", 8, 1, 3, true), _r("obsidian", 5, 1, 2, false, "rare"),
		], _bar("barrier_5", "Bedrock", Color8(30, 26, 26)), 6, 24),

		_biome(5, "Ancient Ruins", 400, 600, [
			_f("cracked_brick", "Cracked Brick", Color8(168, 140, 102), 42),
			_f("ancient_stone", "Ancient Stone", Color8(150, 138, 112), 34),
			_f("sand_rock", "Sand-packed Rock", Color8(178, 158, 118), 24),
		], [
			_r("relic", 4, 1, 2), _r("gold", 8, 1, 3, true), _r("rune", 4, 1, 2, true, "rare"),
		], _bar("barrier_6", "Bedrock", Color8(70, 58, 40)), 8, 34),

		_biome(6, "Fungal Depths", 600, 850, [
			_f("fungal_soil", "Fungal Soil", Color8(80, 66, 76), 44),
			_f("soft_stone", "Soft Stone", Color8(112, 106, 112), 32),
			_f("spore", "Spore Block", Color8(140, 120, 160), 24),
		], [
			_r("mycelium", 8, 1, 3, true), _r("glowcap", 6, 1, 2, true), _r("deep_iron", 7, 1, 3, false, "rare"),
		], _bar("barrier_7", "Bedrock", Color8(40, 34, 44)), 11, 48),

		_biome(7, "Pressure Core", 850, 1150, [
			_f("compressed_stone", "Compressed Stone", Color8(74, 76, 86), 46),
			_f("dense_basalt", "Dense Basalt", Color8(52, 54, 64), 30),
			_f("pressure_rock", "Pressure Rock", Color8(64, 64, 72), 24),
		], [
			_r("titanium", 6, 1, 2), _r("pressure_gem", 4, 1, 2, true, "rare"), _r("black_coal", 9, 1, 3),
		], _bar("barrier_8", "Bedrock", Color8(30, 32, 40)), 15, 66),

		_biome(8, "Astral Geode", 1150, 1500, [
			_f("void_stone", "Void Stone", Color8(58, 52, 74), 46),
			_f("geode_shell", "Geode Shell", Color8(88, 78, 94), 32),
			_f("dark_crystal", "Dark Crystal", Color8(120, 74, 178), 22),
		], [
			_r("astral", 5, 1, 2, true), _r("prismatic", 3, 1, 2, true, "rare"), _r("moon", 6, 1, 2, true),
		], _bar("barrier_9", "Bedrock", Color8(34, 28, 50)), 20, 90),

		_biome(9, "The Living Core", 1500, 99999, [
			_f("living_stone", "Living Stone", Color8(98, 60, 58), 44),
			_f("core_matter", "Core Matter", Color8(80, 50, 60), 34),
			_f("organic_rock", "Dense Organic Rock", Color8(76, 58, 52), 22),
		], [
			_r("heartstone", 4, 1, 2, true), _r("core_fragment", 3, 1, 2, true), _r("ancient_energy", 3, 1, 1, true, "rare"),
		], _bar("barrier_10", "Bedrock", Color8(44, 26, 26)), 28, 130),
	]
	_build_skill_tree()

func biome_index_for_row(row: int) -> int:
	var idx := 0
	for t in _thresholds:
		if row > t:
			idx += 1
		else:
			break
	return clampi(idx, 0, BIOMES.size() - 1)

func biome_for_row(row: int) -> Dictionary:
	return BIOMES[biome_index_for_row(row)]

## Rubble resource id for a given biome index (0-based) -> "rubble_1".."rubble_10".
func rubble_id_for_biome(biome_index: int) -> String:
	return "rubble_%d" % (clampi(biome_index, 0, RUBBLE_VALUE.size() - 1) + 1)

func resource_name(id: String) -> String:
	return RESOURCES.get(id, {}).get("name", id)

func resource_color(id: String) -> Color:
	return RESOURCES.get(id, {}).get("color", Color.WHITE)

func resource_value(id: String) -> int:
	return int(RESOURCES.get(id, {}).get("value", 1))

# --- Item icons (assets/items/) mapped to resources, coins, and rubble. ---
const ICON_DIR := "res://assets/items/"
const COIN_ICON := "coin-gold-stack"
const RUBBLE_ICON := "rock-stone"
const RESOURCE_ICONS := {
	"rock": "rock-gray", "wood": "root-brown", "copper": "ore-copper-chunk",
	"coal": "rock-dark", "iron": "bar-iron", "resin": "log-orange-bundle",
	"cave_moss": "leaf-pile-green", "blue_crystal": "crystal-blue-cluster",
	"quartz": "crystal-silver-shards", "silver": "ore-silver-rock", "ember": "ore-ember",
	"sulfur": "gem-topaz-shard", "obsidian": "rock-obsidian", "relic": "gem-emerald-block",
	"gold": "bar-gold", "rune": "ring-rune-blue", "mycelium": "food-mushroom-cluster",
	"glowcap": "food-mushroom-red", "deep_iron": "bar-steel", "titanium": "bar-platinum",
	"pressure_gem": "gem-diamond-cut", "black_coal": "ore-dark-orb", "astral": "gem-crystal-comet",
	"prismatic": "gem-crystal-crown", "moon": "orb-crystal", "heartstone": "heart-red",
	"core_fragment": "orb-red-swirl", "ancient_energy": "orb-flame-gold",
}
var _icon_cache := {}

## Texture for an item id (resource id, "coins", or any "rubble_N"). null if none.
func item_icon(id: String) -> Texture2D:
	if _icon_cache.has(id):
		return _icon_cache[id]
	var file := ""
	if id == "coins":
		file = COIN_ICON
	elif id.begins_with("rubble"):
		file = RUBBLE_ICON
	elif RESOURCE_ICONS.has(id):
		file = RESOURCE_ICONS[id]
	var tex: Texture2D = null
	if file != "":
		var p: String = ICON_DIR + file + ".png"
		if ResourceLoader.exists(p):
			tex = load(p)
	_icon_cache[id] = tex
	return tex

# ---------------------------------------------------------------------------
# UPGRADES  (bought with resources on the surface)
#   stat/mode/per_level : how each level changes an effective stat
#   mode "add"      -> stat += per_level * level
#   mode "mult"     -> stat *= (1 + per_level * level)
#   mode "cooldown" -> stat *= (1 - per_level) ** level   (multiplicative reduction)
#   "count" upgrades (hire_miner / buy_drill) have no stat; their level == the count.
# ---------------------------------------------------------------------------
var UPGRADES := {
	# --- Pickaxe ---
	"pick_damage": {
		"name": "Sharpen", "category": "Pickaxe", "desc": "+1 click damage / level (stacks on your pickaxe)",
		"max_level": 25, "cost": {"rock": 20, "wood": 5}, "cost_growth": 1.7,
		"stat": "click_damage", "mode": "add", "per_level": 1,
	},
	"quick_swing": {
		"name": "Quick Swing", "category": "Pickaxe", "desc": "-8% click cooldown / level (floors at 0.30s)",
		"max_level": 10, "cost": {"wood": 30, "rock": 20, "coins": 40}, "cost_growth": 1.8,
		"stat": "click_cooldown", "mode": "cooldown", "per_level": 0.08,
	},
	"lucky_strike": {
		"name": "Lucky Strike", "category": "Pickaxe", "desc": "+5% bonus-resource chance / level",
		"max_level": 10, "cost": {"rock": 40, "copper": 10}, "cost_growth": 1.7,
		"stat": "lucky_chance", "mode": "add", "per_level": 0.05,
	},
	"deep_miner": {
		"name": "Deep Miner", "category": "Pickaxe", "desc": "+0.5 damage per 100m depth / level",
		"max_level": 10, "cost": {"iron": 15, "gold": 5}, "cost_growth": 1.8,
		"stat": "deep_bonus", "mode": "add", "per_level": 0.5,
	},
	# --- Resources ---
	"resource_mult": {
		"name": "Bigger Backpack", "category": "Resources", "desc": "+15% resource yield / level",
		"max_level": 15, "cost": {"rock": 50, "iron": 10, "coins": 80}, "cost_growth": 1.7,
		"stat": "resource_mult", "mode": "mult", "per_level": 0.15,
	},
	"exp_boost": {
		"name": "Scholar's Lamp", "category": "Resources", "desc": "+15% EXP gain / level",
		"max_level": 15, "cost": {"wood": 40, "blue_crystal": 5, "coins": 80}, "cost_growth": 1.7,
		"stat": "exp_mult", "mode": "mult", "per_level": 0.15,
	},
	# --- Golems ---  (individual golems are bought in the Golem Workshop; these
	#                  upgrades buff every golem you own.)
	"miner_speed": {
		"name": "Golem Speed", "category": "Golems", "desc": "-10% golem mine interval / level (all golems)",
		"max_level": 10, "cost": {"copper": 40, "iron": 15, "coins": 60}, "cost_growth": 1.8,
		"stat": "ai_interval", "mode": "cooldown", "per_level": 0.10,
	},
	"miner_strength": {
		"name": "Golem Strength", "category": "Golems", "desc": "+1 golem mine damage / level (all golems)",
		"max_level": 20, "cost": {"iron": 25, "copper": 20, "coins": 60}, "cost_growth": 1.7,
		"stat": "ai_damage", "mode": "add", "per_level": 1,
	},
	# --- Machinery ---  (infrastructure: area, downward drilling, economy, fuel)
	"buy_drill": {
		"name": "Basic Drill", "category": "Machinery", "desc": "Auto-drills a random exposed tile",
		"max_level": 10, "cost": {"copper": 75, "coal": 30}, "cost_growth": 1.9,
		"stat": "", "mode": "count",
	},
	"buy_hammer": {
		"name": "Auto-Hammer", "category": "Machinery", "desc": "Slams a zone of exposed tiles (area damage)",
		"max_level": 8, "cost": {"copper": 120, "iron": 20, "coins": 200}, "cost_growth": 1.9,
		"stat": "", "mode": "count",
	},
	"buy_linedrill": {
		"name": "Line Drill", "category": "Machinery", "desc": "Drills straight down a column, piercing blocks",
		"max_level": 8, "cost": {"iron": 40, "copper": 60, "coins": 300}, "cost_growth": 1.9,
		"stat": "", "mode": "count",
	},
	"buy_deepbore": {
		"name": "Deep Bore", "category": "Machinery", "desc": "Bores its own downward shaft on its own",
		"max_level": 6, "cost": {"iron": 80, "titanium": 5, "coins": 1500}, "cost_growth": 2.0,
		"stat": "", "mode": "count",
	},
	"buy_conveyor": {
		"name": "Conveyor System", "category": "Machinery", "desc": "+10% resource yield / level (run-wide)",
		"max_level": 12, "cost": {"copper": 100, "iron": 30, "coins": 400}, "cost_growth": 1.7,
		"stat": "resource_mult", "mode": "mult", "per_level": 0.10,
	},
	"buy_scanner": {
		"name": "Ore Scanner", "category": "Machinery", "desc": "Marks resource tiles so you can spot them",
		"max_level": 5, "cost": {"blue_crystal": 10, "coins": 600}, "cost_growth": 1.8,
		"stat": "", "mode": "count",
	},
	"buy_fuel": {
		"name": "Fuel Engine", "category": "Machinery", "desc": "Burns Coal to speed up all machinery / level",
		"max_level": 8, "cost": {"coal": 60, "copper": 40, "coins": 300}, "cost_growth": 1.8,
		"stat": "", "mode": "count",
	},
	"buy_crusher": {
		"name": "Crusher", "category": "Machinery", "desc": "Crush Rubble into Coins at the surface (+rate / level)",
		"max_level": 10, "cost": {"copper": 60, "coal": 20}, "cost_growth": 1.8,
		"stat": "", "mode": "count",
	},
	"drill_speed": {
		"name": "Better Motors", "category": "Machinery", "desc": "-10% machine interval / level (all machines)",
		"max_level": 12, "cost": {"copper": 50, "coal": 25, "coins": 60}, "cost_growth": 1.8,
		"stat": "machine_speed", "mode": "cooldown", "per_level": 0.10,
	},
	"drill_power": {
		"name": "Heavy Drill Bits", "category": "Machinery", "desc": "+1 machine damage / level (all machines)",
		"max_level": 20, "cost": {"iron": 30, "coal": 20, "coins": 60}, "cost_growth": 1.7,
		"stat": "machine_damage", "mode": "add", "per_level": 1,
	},
	# --- Transport ---  (one-time buys; start a run already down at your best depth)
	"buy_elevator": {
		"name": "Elevator", "category": "Transport",
		"desc": "Start each run at your deepest point (down to biome 3 at most).",
		"max_level": 1, "cost": {"wood": 60, "rock": 80, "coins": 800}, "cost_growth": 1.0,
		"stat": "", "mode": "count",
	},
	"buy_drillevator": {
		"name": "Drillevator", "category": "Transport",
		"desc": "Drills a central shaft to your deepest point at run start (no depth limit).",
		"max_level": 1, "cost": {"iron": 200, "cave_moss": 120, "blue_crystal": 100, "silver": 60, "coins": 30000}, "cost_growth": 1.0,
		"stat": "", "mode": "count",
	},
}

# Runtime parameters for the active in-run machines (keyed by their buy upgrade).
var MACHINES := {
	# Basic Drill tuned to the PDF's low drill tier (Scrap/Bronze Drill). It scales
	# up through the Machine Damage / Speed upgrades rather than through drill tiers.
	"buy_drill":     {"base_damage": 1, "base_interval": 2.8},
	"buy_hammer":    {"base_damage": 3, "base_interval": 3.5, "splash": 22},
	"buy_linedrill": {"base_damage": 4, "base_interval": 2.0, "pierce": 2},
	"buy_deepbore":  {"base_damage": 6, "base_interval": 1.5},
}

# Order upgrades appear in the UI, grouped by category.
var UPGRADE_ORDER := [
	"pick_damage", "quick_swing", "lucky_strike", "deep_miner",
	"resource_mult", "exp_boost",
	"miner_speed", "miner_strength",
	"buy_drill", "buy_hammer", "buy_linedrill", "buy_deepbore",
	"buy_conveyor", "buy_scanner", "buy_fuel", "buy_crusher",
	"drill_speed", "drill_power",
	"buy_elevator", "buy_drillevator",
]

# ---------------------------------------------------------------------------
# SKILL TREE  -- large radial tree, 3 pie sections (Manual / Golem / Machinery),
# ~34 nodes each (100+ total). Bought with skill points earned by levelling up.
# Generated procedurally in _build_skill_tree(); each node has:
#   name, section, ring, angle_deg, size, cost(points), max_level, requires,
#   stat/mode/per_level (folded into effective stats), desc.
# ---------------------------------------------------------------------------
var SKILLS := {}
var SKILL_PATHS := ["Manual", "Golem", "Machinery"]

# Nodes per ring (index 0 = ring 1). Sums to 34 per section -> 102 total.
const _RING_COUNTS := [3, 4, 5, 5, 5, 5, 4, 2, 1]

# Stat pools per section: [stat, mode, per_level, label]. Damage stats use "mult"
# so the PDF's percentage caps are meaningful; per_level magnitudes here are only
# relative weights -- _normalize_skill_caps() rescales each capped stat so a fully
# maxed section lands exactly on its SKILL_CAPS total.
var _SKILL_POOLS := {
	"Manual": [
		["click_damage", "mult", 0.05, "Click Damage"],
		["click_cooldown", "cooldown", 0.03, "Click Cooldown"],
		["crit_chance", "add", 0.03, "Crit Chance"],
		["crit_damage", "add", 0.25, "Crit Damage"],
		["manual_resource_bonus", "add", 0.1, "Manual Resource Yield"],
		["deep_bonus", "add", 0.3, "Depth Damage"],
		["lucky_chance", "add", 0.03, "Lucky Strike"],
		["exp_mult", "mult", 0.05, "EXP Gain"],
	],
	"Golem": [
		["ai_damage_mult", "mult", 0.05, "Golem Damage"],
		["ai_interval", "cooldown", 0.03, "Golem Speed"],
		["ai_resource_bonus", "add", 0.08, "Golem Resource Yield"],
		["exp_mult", "mult", 0.04, "EXP Gain"],
	],
	"Machinery": [
		["machine_damage_mult", "mult", 0.05, "Machine Damage"],
		["machine_speed", "cooldown", 0.03, "Machine Speed"],
		["resource_mult", "mult", 0.05, "Resource Yield"],
		["exp_mult", "mult", 0.04, "EXP Gain"],
	],
}

# PDF "Max General Bonus" caps: the TOTAL bonus a fully-maxed general skill tree
# grants for each stat. mult stats -> +fraction; cooldown stats -> -fraction.
# (Specializations, unbuilt, would push a single style further on top of these.)
var SKILL_CAPS := {
	"click_damage": 1.5, "click_cooldown": 0.4,
	"ai_damage_mult": 1.5, "ai_interval": 0.4,
	"machine_damage_mult": 1.5, "machine_speed": 0.4,
	"resource_mult": 1.0, "exp_mult": 1.0,
}

func _size_for_ring(ring: int) -> String:
	if ring <= 3: return "small"
	elif ring <= 5: return "medium"
	elif ring <= 8: return "large"
	return "capstone"

const SKILL_SIZE_COST := {"small": 1, "medium": 2, "large": 3, "capstone": 5}
const SKILL_SIZE_MAXLVL := {"small": 5, "medium": 3, "large": 2, "capstone": 1}
const SKILL_SIZE_SCALE := {"small": 1.0, "medium": 2.0, "large": 3.5, "capstone": 6.0}

# --- Heart of the Delve (endless central node) ---
const HEART_UNLOCK_LEVEL := 100        # player level required to spend points here
const HEART_COST := 1                  # skill points per level
const HEART_MAX_LEVEL := 1_000_000_000 # effectively infinite
const HEART_PER_LEVEL := 0.02          # +2% to ALL damage per point (linear)

# --- Deep-descent HP scaling (offsets the endless Heart bonus) ---
# Past DEEP_HP_THRESHOLD metres (well inside the endless final biome), block HP
# rises DEEP_HP_PER_STEP for every DEEP_HP_STEP metres deeper. This mirrors the
# Heart's +2%/point: a delver gains roughly one Heart point per ~50 m of new
# depth, so tougher deep blocks and stronger damage track each other and the
# challenge stays flat instead of the Heart trivialising the abyss.
const DEEP_HP_THRESHOLD := 2000
const DEEP_HP_PER_STEP := 0.02
const DEEP_HP_STEP := 50.0

## HP multiplier for a block at the given row (metres). 1.0 until the threshold.
func deep_hp_mult(row: int) -> float:
	if row <= DEEP_HP_THRESHOLD:
		return 1.0
	return 1.0 + DEEP_HP_PER_STEP * (float(row - DEEP_HP_THRESHOLD) / DEEP_HP_STEP)

func _build_skill_tree() -> void:
	SKILLS.clear()
	for si in range(SKILL_PATHS.size()):
		var section: String = SKILL_PATHS[si]
		var base_angle: float = -90.0 + si * 120.0        # Manual up, then clockwise
		var pool: Array = _SKILL_POOLS[section]
		var prev_ring: Array = []                          # [{id, angle}]
		var pool_i := 0
		for r in range(1, _RING_COUNTS.size() + 1):
			var count: int = _RING_COUNTS[r - 1]
			var this_ring: Array = []
			for k in range(count):
				var t := (float(k) + 0.5) / float(count)
				var angle: float = base_angle + lerp(-52.0, 52.0, t) if count > 1 else base_angle
				var size := _size_for_ring(r)
				var effect: Array = pool[pool_i % pool.size()]
				pool_i += 1
				var scale: float = SKILL_SIZE_SCALE[size]
				var per: float = float(effect[2]) * scale
				var id := "%s_r%d_%d" % [section.to_lower(), r, k]
				# parent = nearest node (by angle) in the previous ring, else center.
				var requires := ""
				if not prev_ring.is_empty():
					var best_d := 999.0
					for pn in prev_ring:
						var d: float = absf(pn["angle"] - angle)
						if d < best_d:
							best_d = d
							requires = pn["id"]
				SKILLS[id] = {
					"name": "%s %s" % [effect[3], _roman(r)],
					"path": section, "section": section, "ring": r, "angle_deg": angle,
					"size": size, "cost": SKILL_SIZE_COST[size], "max_level": SKILL_SIZE_MAXLVL[size],
					"requires": requires, "stat": effect[0], "mode": effect[1], "per_level": per,
					"desc": _effect_desc(effect[0], effect[1], per),
				}
				this_ring.append({"id": id, "angle": angle})
			prev_ring = this_ring
	_normalize_skill_caps()

	# Heart of the Delve: the central hub node. Unlocks at level 100, then takes
	# skill points ENDLESSLY, each granting +2% to ALL mining damage (linear, no
	# cap). Drawn as the hub in SkillTreePanel (excluded from the radial layout).
	SKILLS["heart"] = {
		"name": "Heart of the Delve", "path": "", "section": "Manual",
		"ring": 0, "angle_deg": 0, "size": "capstone",
		"cost": HEART_COST, "max_level": HEART_MAX_LEVEL, "requires": "",
		"unlock_level": HEART_UNLOCK_LEVEL,
		"stat": "all_damage_mult", "mode": "mult", "per_level": HEART_PER_LEVEL,
		"desc": "The tree's core. +2% to ALL damage per point, forever — but the deep dark fights back.",
	}

## Rescale each capped stat's per_level so that maxing every node of that stat
## across the whole tree lands exactly on its SKILL_CAPS total. Node effects stack
## multiplicatively in get_effective_stats (mult: *= 1+per*lvl; cooldown:
## *= (1-per)^lvl), so we solve for a scale k that makes the combined product hit
## the target, then regenerate each node's description from the new per_level.
func _normalize_skill_caps() -> void:
	for stat in SKILL_CAPS:
		var cap: float = float(SKILL_CAPS[stat])
		var nodes: Array = []
		for id in SKILLS:
			if SKILLS[id]["stat"] == stat:
				nodes.append(SKILLS[id])
		if nodes.is_empty():
			continue
		var mode: String = nodes[0]["mode"]
		var target: float = (1.0 + cap) if mode == "mult" else (1.0 - cap)
		var k := _solve_skill_scale(nodes, mode, target)
		for n in nodes:
			n["per_level"] = float(n["per_level"]) * k
			n["desc"] = _effect_desc(n["stat"], n["mode"], n["per_level"])

## Bisection for the scale factor k such that the maxed combined product equals
## `target`. mult product increases with k; cooldown product decreases with k.
func _solve_skill_scale(nodes: Array, mode: String, target: float) -> float:
	var increasing: bool = (mode == "mult")
	var lo := 0.0
	var hi := 1.0
	# Grow hi until the product brackets the target (guard against runaway).
	var guard := 0
	while guard <= 60:
		var p: float = _skill_product(nodes, mode, hi)
		var bracketed: bool = (p >= target) if increasing else (p <= target)
		if bracketed:
			break
		hi *= 2.0
		guard += 1
	for _i in range(60):
		var mid := (lo + hi) * 0.5
		var p2: float = _skill_product(nodes, mode, mid)
		var too_low: bool = (p2 < target) if increasing else (p2 > target)
		if too_low:
			lo = mid
		else:
			hi = mid
	return (lo + hi) * 0.5

func _skill_product(nodes: Array, mode: String, k: float) -> float:
	var prod := 1.0
	for n in nodes:
		var per: float = float(n["per_level"]) * k
		var lvl: int = int(n["max_level"])
		if mode == "mult":
			prod *= (1.0 + per * lvl)
		else:   # cooldown
			prod *= pow(maxf(0.0, 1.0 - per), lvl)
	return prod

func _roman(n: int) -> String:
	var r := ["I", "II", "III", "IV", "V", "VI", "VII", "VIII", "IX", "X"]
	return r[clampi(n - 1, 0, r.size() - 1)]

## Human-friendly number: shown in full up to 9999, then abbreviated (10K, 1.5M,
## 2B, ...). Whole values below the threshold drop their decimals. Use everywhere
## a raw count/coin/damage number is displayed.
func fmt(value) -> String:
	var f := float(value)
	var a := absf(f)
	if a < 10000.0:
		if f == floor(f):
			return str(int(f))
		return "%.1f" % f
	var sign := "-" if f < 0.0 else ""
	var units := ["K", "M", "B", "T", "Qa", "Qi", "Sx", "Sp"]
	var idx := 0
	# 999.5+ rounds up to the next unit (avoids "1000K" instead of "1M").
	while a >= 999.5 and idx < units.size():
		a /= 1000.0
		idx += 1
	var s: String
	if a >= 100.0:
		s = "%.0f" % a
	elif a >= 10.0:
		s = "%.1f" % a
	else:
		s = "%.2f" % a
	if s.contains("."):
		s = s.rstrip("0").rstrip(".")
	return sign + s + units[idx - 1]

## Human-readable name for a stat key (used in skill descriptions/tooltips).
func stat_label(stat: String) -> String:
	return {
		"click_damage": "click damage", "click_cooldown": "click cooldown",
		"crit_chance": "crit chance", "crit_damage": "crit damage",
		"manual_resource_bonus": "manual resource yield", "deep_bonus": "depth damage",
		"lucky_chance": "lucky chance", "exp_mult": "EXP gain",
		"ai_damage": "golem damage", "ai_damage_mult": "golem damage", "ai_interval": "golem interval",
		"ai_resource_bonus": "golem resource yield",
		"machine_damage": "machine damage", "machine_damage_mult": "machine damage", "machine_speed": "machine interval",
		"resource_mult": "resource yield", "all_damage_mult": "all damage",
	}.get(stat, stat)

func _effect_desc(stat: String, mode: String, per: float) -> String:
	var label := stat_label(stat)
	match mode:
		"add":
			if per < 1.0:
				return "+%d%% %s / level" % [int(round(per * 100)), label]
			return "+%s %s / level" % [str(per).trim_suffix(".0"), label]
		"mult":
			return "+%d%% %s / level" % [int(round(per * 100)), label]
		"cooldown":
			return "-%d%% %s / level" % [int(round(per * 100)), label]
	return label

## The *cumulative* effect a skill grants at a given level (0 = none yet).
## e.g. Click Cooldown at level 2 -> "-12% click cooldown". Used by tooltips.
func skill_total_desc(id: String, level: int) -> String:
	if not SKILLS.has(id):
		return ""
	if level <= 0:
		return "no bonus yet"
	var n: Dictionary = SKILLS[id]
	var stat: String = n["stat"]
	var per: float = float(n["per_level"])
	var label := stat_label(stat)
	match n["mode"]:
		"add":
			if per < 1.0:
				return "+%d%% %s" % [int(round(per * level * 100)), label]
			return "+%s %s" % [str(per * level).trim_suffix(".0"), label]
		"mult":
			return "+%d%% %s" % [int(round(per * level * 100)), label]
		"cooldown":
			return "-%d%% %s" % [int(round((1.0 - pow(1.0 - per, level)) * 100)), label]
	return label

# ---------------------------------------------------------------------------
# PICKAXE SHOP  -- 10 tiers, one per biome. Each is a one-time purchase that
# raises base click damage and grants a unique manual-mining effect. Index in
# this array == pickaxe tier (0 = free starter). `biome` is the biome index the
# player must have reached to unlock that tier.
#
# effect keys (all optional, consumed for MANUAL mining):
#   cooldown_mult        multiply click cooldown (e.g. 0.92 = -8%)
#   depth_bonus          extra click damage per 100m depth
#   rare_resource_bonus  +yield on manually-mined resource tiles
#   filler_exp_bonus     +EXP fraction from mining filler
#   shatter_chance/_damage  chance a manual break splashes N damage to neighbours
#   instant_chance       chance a manual click instantly breaks the tile
#   dup_chance           chance to double a manually-mined resource drop
#   refund_chance/_amount  chance a manual break refunds a fraction of cooldown
# ---------------------------------------------------------------------------
# Per-pickaxe upgrade multipliers (levels 1..5; level 1 = base). From the PDF's
# "Pickaxe Upgrade Levels" table. Applied to the equipped pickaxe's base damage.
const PICKAXE_UPGRADE_MULT := [1.0, 1.2, 1.45, 1.75, 2.10]

# Base damage & costs from the balance-pass PDF. Coin costs are the PDF's pickaxe-
# tier coin costs exactly (coins are the main economy gate via the Crusher); themed
# material amounts are set to attainable values given the new resource-tile counts.
var PICKAXES := [
	{"tier": 0, "name": "Wooden Pickaxe", "biome": 0, "base_damage": 1, "cost": {},
		"desc": "Crude starter tool.", "effect": {}},
	{"tier": 1, "name": "Rootbound Pickaxe", "biome": 0, "base_damage": 4,
		"cost": {"rock": 25, "wood": 10, "coins": 50},
		"desc": "Roots burrow down: hits a widening root pattern below (50% then 25%).", "effect": {"pattern": "root"}},
	{"tier": 2, "name": "Bronze Pickaxe", "biome": 1, "base_damage": 8,
		"cost": {"copper": 40, "coal": 20, "coins": 250},
		"desc": "Faster swings. Every 5th hit is a guaranteed crit (crits overflow).", "effect": {"pattern": "bronze", "cooldown_mult": 0.92}},
	{"tier": 3, "name": "Iron Pickaxe", "biome": 2, "base_damage": 20,
		"cost": {"iron": 150, "resin": 250, "coins": 2500},
		"desc": "Splinters into up to 4 exposed/chipped neighbours (25%, 50% if the tile breaks).", "effect": {"pattern": "iron_splinter"}},
	{"tier": 4, "name": "Crystal Pickaxe", "biome": 3, "base_damage": 30,
		"cost": {"blue_crystal": 550, "quartz": 700, "silver": 300, "coins": 11000},
		"desc": "On break, 3 shards leap to nearby ore/exposed tiles (40%), chaining on crystals. +rare yield.",
		"effect": {"pattern": "crystal_shatter", "rare_resource_bonus": 0.25}},
	{"tier": 5, "name": "Ember Pickaxe", "biome": 4, "base_damage": 55,
		"cost": {"ember": 900, "sulfur": 900, "obsidian": 450, "coins": 32000},
		"desc": "Every 3rd hit explodes in a 3-tile radius (5 on crit), 100% center, -10% per ring.",
		"effect": {"pattern": "ember"}},
	{"tier": 6, "name": "Relic Pickaxe", "biome": 5, "base_damage": 95,
		"cost": {"relic": 500, "gold": 1400, "rune": 550, "coins": 85000},
		"desc": "Shards orbit your pickaxe, hitting any tile for 50% damage. +1 shard per tile broken (max 12).",
		"effect": {"pattern": "relic_orbit"}},
	{"tier": 7, "name": "Mycelium Pickaxe", "biome": 6, "base_damage": 160,
		"cost": {"deep_iron": 800, "mycelium": 1600, "glowcap": 1100, "coins": 220000},
		"desc": "Spores spiral out 5 layers (8 on crit), each layer -5%. +EXP from filler.",
		"effect": {"pattern": "spore", "filler_exp_bonus": 0.5}},
	{"tier": 8, "name": "Titanium Pickaxe", "biome": 7, "base_damage": 270,
		"cost": {"titanium": 1800, "pressure_gem": 700, "black_coal": 2400, "coins": 550000},
		"desc": "Drills 7 tiles down; even depths branch sideways. Scales with depth.",
		"effect": {"pattern": "titanium", "depth_bonus": 1.0}},
	{"tier": 9, "name": "Astral Pickaxe", "biome": 8, "base_damage": 460,
		"cost": {"astral": 2600, "moon": 3200, "prismatic": 1300, "coins": 1400000},
		"desc": "Breaks snake through nearby tiles toward ore. Mines sealed blocks. Chance to insta-break.",
		"effect": {"pattern": "astral_snake", "mine_unexposed": true, "instant_chance": 0.1, "depth_bonus": 2.0}},
	{"tier": 10, "name": "Core Pickaxe", "biome": 9, "base_damage": 780,
		"cost": {"heartstone": 3800, "core_fragment": 2800, "ancient_energy": 1900, "coins": 3500000},
		"desc": "Overkill damage overflows to surrounding tiles. Mines sealed blocks. +rare yield & insta-break.",
		"effect": {"pattern": "core", "rare_resource_bonus": 0.5, "instant_chance": 0.08, "mine_unexposed": true}},
]

# ---------------------------------------------------------------------------
# GOLEM WORKSHOP  -- 10 golem tiers. You can own MANY of each tier (a roster);
# their strength is quantity + the global Golem upgrades/skills. Index == tier-1.
# `biome` = biome index required to unlock. Buying another of a tier costs more
# each time (scaled by how many of that tier you already own).
#
# effect keys (optional, per-golem):
#   prefer_resource   golem walks toward resource tiles
#   double_hit_chance chance a mining tick deals double damage
#   splash_chance/_damage  chance a golem break splashes N damage to neighbours
#   res_bonus         +resource yield on tiles this golem breaks
# ---------------------------------------------------------------------------
const GOLEM_COST_GROWTH := 1.45

var GOLEMS := [
	{"tier": 1, "name": "Rootstone Golem", "biome": 0, "base_damage": 4, "interval": 0.7,
		"cost": {"rock": 60, "wood": 30, "coins": 40}, "effect": {},
		"desc": "Slow, cheap starter miner."},
	{"tier": 2, "name": "Bronze Golem", "biome": 1, "base_damage": 8, "interval": 0.6,
		"cost": {"copper": 40, "coal": 25, "coins": 120}, "effect": {},
		"desc": "Faster, sturdier automation."},
	{"tier": 3, "name": "Ironbark Golem", "biome": 2, "base_damage": 18, "interval": 0.6,
		"cost": {"iron": 35, "resin": 15, "coins": 280}, "effect": {"double_hit_chance": 0.15},
		"desc": "Occasionally strikes twice."},
	{"tier": 4, "name": "Crystal Golem", "biome": 3, "base_damage": 36, "interval": 0.6,
		"cost": {"blue_crystal": 18, "quartz": 20, "silver": 12, "coins": 600},
		"effect": {"prefer_resource": true, "res_bonus": 0.15},
		"desc": "Seeks out resource tiles."},
	{"tier": 5, "name": "Ember Golem", "biome": 4, "base_damage": 68, "interval": 0.6,
		"cost": {"ember": 18, "sulfur": 18, "obsidian": 10, "coins": 1200}, "effect": {},
		"desc": "Slow but heavy hits; hard-block breaker."},
	{"tier": 6, "name": "Relic Golem", "biome": 5, "base_damage": 125, "interval": 0.6,
		"cost": {"relic": 8, "gold": 20, "rune": 8, "coins": 2200}, "effect": {"res_bonus": 0.25},
		"desc": "Bonus resources from what it mines."},
	{"tier": 7, "name": "Spore Golem", "biome": 6, "base_damage": 225, "interval": 0.6,
		"cost": {"deep_iron": 18, "mycelium": 18, "glowcap": 10, "coins": 4000},
		"effect": {"splash_chance": 0.25, "splash_damage": 20},
		"desc": "Spore bursts damage nearby tiles."},
	{"tier": 8, "name": "Pressure Golem", "biome": 7, "base_damage": 405, "interval": 0.6,
		"cost": {"titanium": 12, "pressure_gem": 6, "black_coal": 16, "coins": 7500}, "effect": {},
		"desc": "Deep-layer workhorse."},
	{"tier": 9, "name": "Astral Golem", "biome": 8, "base_damage": 720, "interval": 0.6,
		"cost": {"astral": 8, "moon": 10, "prismatic": 6, "coins": 14000},
		"effect": {"prefer_resource": true, "splash_chance": 0.2, "splash_damage": 80},
		"desc": "Smart miner; targets valuables & bursts."},
	{"tier": 10, "name": "Core Golem", "biome": 9, "base_damage": 1240, "interval": 0.6,
		"cost": {"heartstone": 6, "core_fragment": 5, "ancient_energy": 4, "coins": 26000},
		"effect": {"splash_chance": 0.3, "splash_damage": 200, "res_bonus": 0.3},
		"desc": "Endgame leader; shockwaves on break."},
]

# ---------------------------------------------------------------------------
# TILE MATERIAL TEXTURES  (assets/tile_materials/tile_r<row>_c<col>.png)
# Full-bleed material textures wrapped on every face of the cube. Row == biome
# layer; column chosen by matching the texture art to each tile.
# ---------------------------------------------------------------------------
const TEX_DIR := "res://assets/tile_materials/"

var TILE_TEXTURES := {
	# L1 Shallow Dirtworks
	"dirt": "tile_r1_c1.png", "packed_dirt": "tile_r1_c2.png", "loose_stone": "tile_r1_c6.png",
	"rock": "tile_r1_c4.png", "wood": "tile_r1_c7.png",
	# L2 Stone Veins
	"stone": "tile_r2_c1.png", "gravel": "tile_r2_c2.png", "hard_dirt": "tile_r2_c4.png",
	"copper": "tile_r2_c6.png", "coal": "tile_r2_c7.png",
	# L3 Moss Caverns
	"damp_stone": "tile_r3_c1.png", "mossy_dirt": "tile_r3_c2.png", "clay": "tile_r3_c4.png",
	"iron": "tile_r3_c5.png", "resin": "tile_r3_c6.png", "cave_moss": "tile_r3_c7.png",
	# L4 Crystal Hollow
	"pale_stone": "tile_r4_c1.png", "crystal_dust": "tile_r4_c2.png", "brittle_rock": "tile_r4_c3.png",
	"blue_crystal": "tile_r4_c5.png", "quartz": "tile_r4_c6.png", "silver": "tile_r4_c7.png",
	# L5 Emberstone Layer
	"dark_stone": "tile_r5_c1.png", "ash": "tile_r5_c2.png", "burnt_rock": "tile_r5_c3.png",
	"ember": "tile_r5_c5.png", "sulfur": "tile_r5_c6.png", "obsidian": "tile_r5_c7.png",
	# L6 Ancient Ruins
	"cracked_brick": "tile_r6_c1.png", "ancient_stone": "tile_r6_c2.png", "sand_rock": "tile_r6_c4.png",
	"relic": "tile_r6_c5.png", "gold": "tile_r6_c6.png", "rune": "tile_r6_c7.png",
	# L7 Fungal Depths
	"fungal_soil": "tile_r7_c1.png", "soft_stone": "tile_r7_c2.png", "spore": "tile_r7_c3.png",
	"mycelium": "tile_r7_c5.png", "glowcap": "tile_r7_c6.png", "deep_iron": "tile_r7_c7.png",
	# L8 Pressure Core
	"compressed_stone": "tile_r8_c1.png", "dense_basalt": "tile_r8_c2.png", "pressure_rock": "tile_r8_c3.png",
	"titanium": "tile_r8_c4.png", "pressure_gem": "tile_r8_c5.png", "black_coal": "tile_r8_c7.png",
	# L9 Astral Geode
	"void_stone": "tile_r9_c1.png", "geode_shell": "tile_r9_c2.png", "dark_crystal": "tile_r9_c3.png",
	"astral": "tile_r9_c5.png", "prismatic": "tile_r9_c6.png", "moon": "tile_r9_c7.png",
	# L10 The Living Core
	"living_stone": "tile_r10_c1.png", "core_matter": "tile_r10_c2.png", "organic_rock": "tile_r10_c3.png",
	"heartstone": "tile_r10_c5.png", "core_fragment": "tile_r10_c6.png", "ancient_energy": "tile_r10_c7.png",
}

# ---------------------------------------------------------------------------
# BIOME BACKGROUNDS  (assets/biome_bg/*.png)  -- one backdrop per biome layer.
# ---------------------------------------------------------------------------
const BIOME_BG_DIR := "res://assets/biome_bg/"
# index 0..9 -> filename (note biome 4's file is "b4.png", not "bg4.png").
var BIOME_BG := [
	"bg1.png", "bg2.png", "bg3.png", "b4.png", "bg5.png",
	"bg6.png", "bg7.png", "bg8.png", "bg9.png", "bg10.png",
]
var _bg_cache := {}

func get_biome_bg(index: int) -> Texture2D:
	index = clampi(index, 0, BIOME_BG.size() - 1)
	if _bg_cache.has(index):
		return _bg_cache[index]
	var tex: Texture2D = null
	var p: String = BIOME_BG_DIR + BIOME_BG[index]
	if ResourceLoader.exists(p):
		tex = load(p)
	_bg_cache[index] = tex
	return tex

var _pick_tex_cache := {}

## Full pickaxe sprite for a tier (0 = starter -> pickaxe_01), for drawing as a
## software cursor. Returns null if missing.
func get_pickaxe_texture(tier: int) -> Texture2D:
	tier = clampi(tier, 0, PICKAXES.size() - 1)
	if _pick_tex_cache.has(tier):
		return _pick_tex_cache[tier]
	var tex: Texture2D = null
	var p: String = "res://assets/pickaxes2/pickaxe_%02d.png" % (tier + 1)
	if ResourceLoader.exists(p):
		tex = load(p)
	_pick_tex_cache[tier] = tex
	return tex

var _cursor_cache := {}

## Pickaxe cursor for a tier (0 = starter -> pickaxe_01). Downscaled to a cursor-
## friendly size. Returns null if the asset is missing.
func get_pickaxe_cursor(tier: int) -> Texture2D:
	tier = clampi(tier, 0, PICKAXES.size() - 1)
	if _cursor_cache.has(tier):
		return _cursor_cache[tier]
	var tex: Texture2D = null
	var p: String = "res://assets/pickaxes2/pickaxe_%02d.png" % (tier + 1)
	if ResourceLoader.exists(p):
		var src: Texture2D = load(p)
		var img: Image = src.get_image()
		if img != null:
			img = img.duplicate()
			if img.is_compressed():
				img.decompress()
			img.resize(64, 64, Image.INTERPOLATE_LANCZOS)
			tex = ImageTexture.create_from_image(img)
	_cursor_cache[tier] = tex
	return tex

# ---------------------------------------------------------------------------
# SPECIALIZATIONS  (design doc: 3 specs, 7 skills each, pick only 4)
#   Spec points are earned at biome milestones (reach biome 3/5/7/9 = 4 total).
#   Picking the first skill in a spec LOCKS OUT the other two specs' skills;
#   normal skill-tree nodes stay open. The numeric effect of each skill lives in
#   GameState._apply_specialization() (keyed by id); here we hold display data.
# ---------------------------------------------------------------------------
const SPEC_MILESTONE_BIOMES := [2, 4, 6, 8]   # biome indices (biome 3/5/7/9) that each grant +1 point
const SPEC_MAX_PICKS := 4

var SPECIALIZATIONS := {
	"striker": {
		"name": "Striker", "style": "Manual", "color": Color8(226, 182, 92),
		"blurb": "You are the mine's cutting edge. Clicking becomes fast, heavy and rewarding.",
		"skills": [
			{"id": "striker_power_swing", "name": "Power Swing", "desc": "Manual clicks deal +60% damage."},
			{"id": "striker_quick_hands", "name": "Quick Hands", "desc": "-25% click cooldown."},
			{"id": "striker_weak_point", "name": "Weak Point", "desc": "+25% crit chance and +0.5x crit damage."},
			{"id": "striker_shatter", "name": "Shatter Strike", "desc": "Breaking a tile splashes heavy damage onto exposed neighbours."},
			{"id": "striker_frenzy", "name": "Mining Frenzy", "desc": "Breaking a resource tile grants a few seconds of faster, harder swings."},
			{"id": "striker_precision", "name": "Precision Extraction", "desc": "Manually mined resource tiles drop +75% materials."},
			{"id": "striker_relentless", "name": "Relentless Delver", "desc": "Manual damage scales up the deeper you dig this run."},
		],
	},
	"stonewarden": {
		"name": "Stonewarden", "style": "Golem", "color": Color8(126, 202, 100),
		"blurb": "You command a crew of mining golems. Strength comes from the whole team.",
		"skills": [
			{"id": "warden_commander", "name": "Golem Commander", "desc": "All golems: +40% damage and 20% faster."},
			{"id": "warden_focus", "name": "Focus Orders", "desc": "Golems prioritise resource tiles."},
			{"id": "warden_quarry", "name": "Living Quarry", "desc": "Each golem owned adds +4% damage to all golems."},
			{"id": "warden_sync", "name": "Synchronized Strike", "desc": "Coordinated crew: +15% golem damage."},
			{"id": "warden_bond", "name": "Ancient Bond", "desc": "Doubles the chance of golem unique effects (double-hit / splash)."},
			{"id": "warden_efficient", "name": "Efficient Workers", "desc": "Golem-mined tiles yield +50% materials."},
			{"id": "warden_endless", "name": "Endless Crew", "desc": "Start each run with +1 active golem scaled to your deepest biome."},
		],
	},
	"engineer": {
		"name": "Engineer", "style": "Machine", "color": Color8(140, 175, 220),
		"blurb": "You run an industrial dig site. Machines scale as a network.",
		"skills": [
			{"id": "eng_motors", "name": "Overclocked Motors", "desc": "All machinery works 25% faster."},
			{"id": "eng_drillbits", "name": "Reinforced Drill Bits", "desc": "+40% machine damage."},
			{"id": "eng_fuel", "name": "Fuel Mastery", "desc": "Fuel lasts longer and gives a stronger machine boost."},
			{"id": "eng_network", "name": "Industrial Network", "desc": "Each machine owned adds +3% damage to all machines."},
			{"id": "eng_sorter", "name": "Auto-Sorter", "desc": "Machine-mined tiles yield +50% materials."},
			{"id": "eng_deepbore", "name": "Deep Bore Protocol", "desc": "Machines deal bonus damage that scales with depth."},
			{"id": "eng_aftershift", "name": "Aftershift Automation", "desc": "Machinery keeps mining for 5s after the run timer ends."},
		],
	},
}

const SPEC_ORDER := ["striker", "stonewarden", "engineer"]

## Which specialization (if any) a spec-skill id belongs to.
func spec_of_skill(id: String) -> String:
	for spec in SPECIALIZATIONS:
		for sk in SPECIALIZATIONS[spec]["skills"]:
			if sk["id"] == id:
				return spec
	return ""

var _tex_cache := {}

func get_tile_texture(tile_id: String) -> Texture2D:
	if _tex_cache.has(tile_id):
		return _tex_cache[tile_id]
	var tex: Texture2D = null
	if TILE_TEXTURES.has(tile_id):
		var p: String = TEX_DIR + TILE_TEXTURES[tile_id]
		if ResourceLoader.exists(p):
			tex = load(p)
	_tex_cache[tile_id] = tex
	return tex
