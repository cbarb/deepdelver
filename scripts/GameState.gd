extends Node
## GameState (autoload)
## Persistent progression: resources, money, EXP, purchased upgrades & skills,
## records. Also computes the player's *effective* stats from all bonuses and
## handles buying things + save/load.

const SAVE_PATH := "user://deepdelver_save.json"

var resources: Dictionary = {}          # resource_id -> amount (int)
var money: int = 0
var exp: int = 0                         # spendable EXP (skill-tree currency)
var lifetime_exp: int = 0                # for level display
var upgrade_levels: Dictionary = {}      # upgrade_id -> level
var skill_levels: Dictionary = {}        # skill_id -> level
var max_depth: int = 0                   # best depth ever (meters)
var pickaxe_tier: int = 0                # owned pickaxe tier (index into GameData.PICKAXES)
var golems: Dictionary = {}              # tier(int) -> count owned
var last_summary: Dictionary = {}        # summary of the most recent run

# Base (unmodified) player stats.
var _base_stats := {
	"click_damage": 1.0,
	"click_cooldown": 0.7,
	"resource_mult": 1.0,
	"exp_mult": 1.0,
	"crit_chance": 0.0,
	"crit_damage": 2.0,
	"lucky_chance": 0.0,
	"deep_bonus": 0.0,           # extra damage per 100m
	"manual_resource_bonus": 0.0,
	"ai_interval": 1.0,          # MULTIPLIER on each golem's tier interval (lower = faster)
	"ai_damage": 0.0,            # flat ADD to each golem's tier damage
	"ai_resource_bonus": 0.0,
	"machine_speed": 1.0,        # MULTIPLIER on machine intervals (lower = faster)
	"machine_damage": 0.0,       # flat ADD to every machine's damage
	# pickaxe effect fields (set from the equipped pickaxe)
	"filler_exp_bonus": 0.0,
	"shatter_chance": 0.0,
	"shatter_damage": 0.0,
	"instant_chance": 0.0,
	"dup_chance": 0.0,
	"refund_chance": 0.0,
	"refund_amount": 0.0,
}

func _ready() -> void:
	load_game()

# ---------------------------------------------------------------------------
# Effective stats
# ---------------------------------------------------------------------------
func current_pickaxe() -> Dictionary:
	return GameData.PICKAXES[clampi(pickaxe_tier, 0, GameData.PICKAXES.size() - 1)]

func get_effective_stats() -> Dictionary:
	var s := _base_stats.duplicate(true)
	# Equipped pickaxe sets base damage + grants its effect, before upgrades/skills.
	var pk := current_pickaxe()
	s["click_damage"] = float(pk.get("base_damage", 1))
	var eff: Dictionary = pk.get("effect", {})
	s["click_cooldown"] *= float(eff.get("cooldown_mult", 1.0))
	s["deep_bonus"] += float(eff.get("depth_bonus", 0.0))
	s["manual_resource_bonus"] += float(eff.get("rare_resource_bonus", 0.0))
	s["filler_exp_bonus"] = float(eff.get("filler_exp_bonus", 0.0))
	s["shatter_chance"] = float(eff.get("shatter_chance", 0.0))
	s["shatter_damage"] = float(eff.get("shatter_damage", 0.0))
	s["instant_chance"] = float(eff.get("instant_chance", 0.0))
	s["dup_chance"] = float(eff.get("dup_chance", 0.0))
	s["refund_chance"] = float(eff.get("refund_chance", 0.0))
	s["refund_amount"] = float(eff.get("refund_amount", 0.0))
	for id in GameData.UPGRADES:
		_apply_effect(s, GameData.UPGRADES[id], int(upgrade_levels.get(id, 0)))
	for id in GameData.SKILLS:
		_apply_effect(s, GameData.SKILLS[id], int(skill_levels.get(id, 0)))
	# Count-based values.
	s["ai_count"] = golem_count()
	s["drill_count"] = int(upgrade_levels.get("buy_drill", 0))
	s["hammer_count"] = int(upgrade_levels.get("buy_hammer", 0))
	s["linedrill_count"] = int(upgrade_levels.get("buy_linedrill", 0))
	s["deepbore_count"] = int(upgrade_levels.get("buy_deepbore", 0))
	s["scanner_level"] = int(upgrade_levels.get("buy_scanner", 0))
	s["fuel_level"] = int(upgrade_levels.get("buy_fuel", 0))
	# Safety clamps.
	s["click_cooldown"] = maxf(0.12, s["click_cooldown"])
	s["ai_interval"] = maxf(0.15, s["ai_interval"])       # golem interval multiplier floor
	s["machine_speed"] = maxf(0.2, s["machine_speed"])    # machine interval multiplier floor
	s["crit_chance"] = clampf(s["crit_chance"], 0.0, 1.0)
	s["lucky_chance"] = clampf(s["lucky_chance"], 0.0, 1.0)
	return s

func _apply_effect(s: Dictionary, def: Dictionary, level: int) -> void:
	if level <= 0:
		return
	var stat: String = def.get("stat", "")
	if stat == "" or not s.has(stat):
		return
	var per: float = float(def.get("per_level", 0))
	match def.get("mode", "add"):
		"add":
			s[stat] += per * level
		"mult":
			s[stat] *= (1.0 + per * level)
		"cooldown":
			s[stat] *= pow(1.0 - per, level)

# ---------------------------------------------------------------------------
# Economy helpers
# ---------------------------------------------------------------------------
func add_resource(id: String, amount: int) -> void:
	resources[id] = int(resources.get(id, 0)) + amount

func add_money(amount: int) -> void:
	money += amount

func add_exp(amount: int) -> void:
	exp += amount
	lifetime_exp += amount

## EXP required to advance FROM the given level to the next.
func _exp_for_next(level: int) -> int:
	return int(round(25.0 * pow(float(level), 1.5)))

func get_level() -> int:
	return int(level_progress()["level"])

## {level, into (exp into current level), need (exp to next level)}
func level_progress() -> Dictionary:
	var lvl := 1
	var rem := lifetime_exp
	var need := _exp_for_next(lvl)
	while rem >= need:
		rem -= need
		lvl += 1
		need = _exp_for_next(lvl)
	return {"level": lvl, "into": rem, "need": need}

# --- Skill points (1 earned per level; spent on skill-tree nodes) ---
func skill_points_total() -> int:
	return maxi(0, get_level() - 1)

func skill_points_spent() -> int:
	var t := 0
	for id in skill_levels:
		if GameData.SKILLS.has(id):
			t += int(GameData.SKILLS[id]["cost"]) * int(skill_levels[id])
	return t

func skill_points_available() -> int:
	return skill_points_total() - skill_points_spent()

# ---------------------------------------------------------------------------
# Upgrades
# ---------------------------------------------------------------------------
func upgrade_level(id: String) -> int:
	return int(upgrade_levels.get(id, 0))

func upgrade_cost(id: String) -> Dictionary:
	var def: Dictionary = GameData.UPGRADES[id]
	var level := upgrade_level(id)
	var growth: float = float(def.get("cost_growth", 1.6))
	var out := {}
	for res in def["cost"]:
		out[res] = int(ceil(float(def["cost"][res]) * pow(growth, level)))
	return out

func is_upgrade_maxed(id: String) -> bool:
	return upgrade_level(id) >= int(GameData.UPGRADES[id].get("max_level", 9999))

func can_afford(cost: Dictionary) -> bool:
	for res in cost:
		if res == "coins":
			if money < int(cost[res]):
				return false
		elif int(resources.get(res, 0)) < int(cost[res]):
			return false
	return true

func buy_upgrade(id: String) -> bool:
	if not GameData.UPGRADES.has(id) or is_upgrade_maxed(id):
		return false
	var cost := upgrade_cost(id)
	if not can_afford(cost):
		return false
	for res in cost:
		if res == "coins":
			money -= int(cost[res])
		else:
			resources[res] = int(resources.get(res, 0)) - int(cost[res])
	upgrade_levels[id] = upgrade_level(id) + 1
	return true

# --- Crusher: convert stored Rubble into Coins (rate scales with Crusher level) ---
func crush_rate() -> int:
	return int(upgrade_levels.get("buy_crusher", 0))   # coins per rubble

func crush_rubble() -> int:
	var rubble := int(resources.get("rubble", 0))
	var rate := crush_rate()
	if rubble <= 0 or rate <= 0:
		return 0
	var coins := rubble * rate
	resources["rubble"] = 0
	money += coins
	return coins

# ---------------------------------------------------------------------------
# Pickaxes
# ---------------------------------------------------------------------------
func next_pickaxe() -> Dictionary:
	var nt := pickaxe_tier + 1
	if nt < GameData.PICKAXES.size():
		return GameData.PICKAXES[nt]
	return {}

## Has the player reached the biome required to unlock the given pickaxe tier?
func pickaxe_unlocked(pk: Dictionary) -> bool:
	return GameData.biome_index_for_row(max_depth) >= int(pk.get("biome", 0))

func buy_next_pickaxe() -> bool:
	var pk := next_pickaxe()
	if pk.is_empty() or not pickaxe_unlocked(pk):
		return false
	var cost: Dictionary = pk.get("cost", {})
	if not can_afford(cost):
		return false
	for res in cost:
		if res == "coins":
			money -= int(cost[res])
		else:
			resources[res] = int(resources.get(res, 0)) - int(cost[res])
	pickaxe_tier += 1
	return true

# ---------------------------------------------------------------------------
# Golems (Workshop roster: own many of each tier)
# ---------------------------------------------------------------------------
func golem_count() -> int:
	var t := 0
	for k in golems:
		t += int(golems[k])
	return t

func golem_owned(tier: int) -> int:
	return int(golems.get(tier, 0))

func golem_data(tier: int) -> Dictionary:
	return GameData.GOLEMS[clampi(tier - 1, 0, GameData.GOLEMS.size() - 1)]

func golem_unlocked(tier: int) -> bool:
	return GameData.biome_index_for_row(max_depth) >= int(golem_data(tier).get("biome", 0))

func golem_buy_cost(tier: int) -> Dictionary:
	var base: Dictionary = golem_data(tier).get("cost", {})
	var owned := golem_owned(tier)
	var mult: float = pow(GameData.GOLEM_COST_GROWTH, owned)
	var out := {}
	for res in base:
		out[res] = int(ceil(float(base[res]) * mult))
	return out

func buy_golem(tier: int) -> bool:
	if tier < 1 or tier > GameData.GOLEMS.size() or not golem_unlocked(tier):
		return false
	var cost := golem_buy_cost(tier)
	if not can_afford(cost):
		return false
	for res in cost:
		if res == "coins":
			money -= int(cost[res])
		else:
			resources[res] = int(resources.get(res, 0)) - int(cost[res])
	golems[tier] = golem_owned(tier) + 1
	return true

# ---------------------------------------------------------------------------
# Skills
# ---------------------------------------------------------------------------
func skill_level(id: String) -> int:
	return int(skill_levels.get(id, 0))

func skill_cost(id: String) -> int:
	return int(GameData.SKILLS[id]["cost"])   # skill points per level

func is_skill_maxed(id: String) -> bool:
	return skill_level(id) >= int(GameData.SKILLS[id].get("max_level", 9999))

func skill_unlocked(id: String) -> bool:
	var req: String = GameData.SKILLS[id].get("requires", "")
	return req == "" or skill_level(req) > 0

func buy_skill(id: String) -> bool:
	if not GameData.SKILLS.has(id) or is_skill_maxed(id) or not skill_unlocked(id):
		return false
	if skill_points_available() < skill_cost(id):
		return false
	skill_levels[id] = skill_level(id) + 1
	return true

# ---------------------------------------------------------------------------
# Save / Load
# ---------------------------------------------------------------------------
func save_game() -> void:
	var data := {
		"resources": resources, "money": money, "exp": exp, "lifetime_exp": lifetime_exp,
		"upgrade_levels": upgrade_levels, "skill_levels": skill_levels, "max_depth": max_depth,
		"pickaxe_tier": pickaxe_tier, "golems": golems,
	}
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data))
		f.close()

func load_game() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if not f:
		return
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	resources = _to_int_dict(parsed.get("resources", {}))
	money = int(parsed.get("money", 0))
	exp = int(parsed.get("exp", 0))
	lifetime_exp = int(parsed.get("lifetime_exp", 0))
	upgrade_levels = _to_int_dict(parsed.get("upgrade_levels", {}))
	skill_levels = _to_int_dict(parsed.get("skill_levels", {}))
	max_depth = int(parsed.get("max_depth", 0))
	pickaxe_tier = int(parsed.get("pickaxe_tier", 0))
	golems = _to_int_keyed_dict(parsed.get("golems", {}))

func _to_int_dict(d) -> Dictionary:
	var out := {}
	if typeof(d) == TYPE_DICTIONARY:
		for k in d:
			out[k] = int(d[k])
	return out

## Like _to_int_dict but also converts keys to int (JSON stringifies dict keys).
func _to_int_keyed_dict(d) -> Dictionary:
	var out := {}
	if typeof(d) == TYPE_DICTIONARY:
		for k in d:
			out[int(k)] = int(d[k])
	return out

func reset_progress() -> void:
	resources.clear()
	money = 0
	exp = 0
	lifetime_exp = 0
	upgrade_levels.clear()
	skill_levels.clear()
	max_depth = 0
	pickaxe_tier = 0
	golems.clear()
	last_summary.clear()
	save_game()
