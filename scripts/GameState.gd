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
var pickaxe_upgrade_levels: Dictionary = {}  # tier(int) -> upgrade level 1..5 (1 = base)
var golems: Dictionary = {}              # tier(int) -> count owned
var last_summary: Dictionary = {}        # summary of the most recent run
var use_transport: bool = true           # (legacy) transport ride flag; superseded by selected_start_depth
var selected_start_depth: int = -1       # depth (m) chosen on the descent screen; -1 = unset -> default deepest

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
	"ai_damage": 0.0,            # flat ADD to each golem's tier damage (upgrades)
	"ai_damage_mult": 1.0,       # MULTIPLIER on total golem damage (skills; PDF-capped)
	"ai_resource_bonus": 0.0,
	"machine_speed": 1.0,        # MULTIPLIER on machine intervals (lower = faster)
	"machine_damage": 0.0,       # flat ADD to every machine's damage (upgrades)
	"machine_damage_mult": 1.0,  # MULTIPLIER on total machine damage (skills; PDF-capped)
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
	s["click_damage"] = float(pk.get("base_damage", 1)) * pickaxe_upgrade_mult()
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
	s["click_cooldown"] = maxf(0.30, s["click_cooldown"])   # hard cap (manual spec would lower to ~0.22-0.25)
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

# --- Per-pickaxe upgrade levels (1..5, ×1.0/1.2/1.45/1.75/2.10 damage) ---
# Coins-only, scaled from the pickaxe's own craft coin cost.
const PICKAXE_UPGRADE_COST_FACTOR := [0.25, 0.5, 0.9, 1.5]   # for level 1->2, 2->3, 3->4, 4->5

func pickaxe_upgrade_level(tier: int) -> int:
	return clampi(int(pickaxe_upgrade_levels.get(tier, 1)), 1, GameData.PICKAXE_UPGRADE_MULT.size())

## Damage multiplier of the currently-equipped pickaxe from its upgrade level.
func pickaxe_upgrade_mult() -> float:
	var lvl := pickaxe_upgrade_level(pickaxe_tier)
	return float(GameData.PICKAXE_UPGRADE_MULT[lvl - 1])

func is_pickaxe_upgrade_maxed(tier: int) -> bool:
	return pickaxe_upgrade_level(tier) >= GameData.PICKAXE_UPGRADE_MULT.size()

## Coin cost to raise the given pickaxe from its current level to the next.
func pickaxe_upgrade_cost(tier: int) -> int:
	var lvl := pickaxe_upgrade_level(tier)
	if lvl >= GameData.PICKAXE_UPGRADE_MULT.size():
		return 0
	var craft_coins: int = int(GameData.PICKAXES[tier].get("cost", {}).get("coins", 0))
	var base := maxi(25, craft_coins)   # Wooden starter has no craft coins; give it a floor
	return int(round(base * float(PICKAXE_UPGRADE_COST_FACTOR[lvl - 1])))

# --- Transport (Elevator / Drillevator): start a run down at your best depth ---
const ELEVATOR_CAP := 150   # Elevator start-depth cap (bottom of biome 3)

func owns_elevator() -> bool:
	return upgrade_level("buy_elevator") > 0

func owns_drillevator() -> bool:
	return upgrade_level("buy_drillevator") > 0

func owns_transport() -> bool:
	return owns_elevator() or owns_drillevator()

## Depth a run would start at with the best owned transport (0 = none/surface).
## Ignores the use_transport toggle -- that gate is applied by the caller.
func transport_start_depth() -> int:
	if owns_drillevator():
		return max_depth
	if owns_elevator():
		return mini(max_depth, ELEVATOR_CAP)
	return 0

## Upgrade the currently-equipped pickaxe one level. Returns true on success.
func buy_pickaxe_upgrade() -> bool:
	if is_pickaxe_upgrade_maxed(pickaxe_tier):
		return false
	var cost := pickaxe_upgrade_cost(pickaxe_tier)
	if money < cost:
		return false
	money -= cost
	pickaxe_upgrade_levels[pickaxe_tier] = pickaxe_upgrade_level(pickaxe_tier) + 1
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

# --- Refund: pay coins to reclaim a skill point (one level at a time) ---
const SKILL_REFUND_COIN_PER_POINT := 50   # coins charged per skill point reclaimed

func skill_refund_cost(id: String) -> int:
	return SKILL_REFUND_COIN_PER_POINT * skill_cost(id)

## True if any *owned* node lists `id` as its prerequisite — such a node would be
## orphaned if `id` dropped to level 0, so its last level can't be refunded first.
func skill_has_owned_dependents(id: String) -> bool:
	for other in skill_levels:
		if int(skill_levels[other]) > 0 and GameData.SKILLS.has(other):
			if GameData.SKILLS[other].get("requires", "") == id:
				return true
	return false

func can_refund_skill(id: String) -> bool:
	if not GameData.SKILLS.has(id) or skill_level(id) <= 0:
		return false
	if money < skill_refund_cost(id):
		return false
	# Refunding the final level would unlock-break any owned dependents.
	if skill_level(id) == 1 and skill_has_owned_dependents(id):
		return false
	return true

func refund_skill(id: String) -> bool:
	if not can_refund_skill(id):
		return false
	money -= skill_refund_cost(id)
	var lvl := skill_level(id) - 1
	if lvl <= 0:
		skill_levels.erase(id)
	else:
		skill_levels[id] = lvl
	return true

# ---------------------------------------------------------------------------
# Save / Load
# ---------------------------------------------------------------------------
func save_game() -> void:
	var data := {
		"resources": resources, "money": money, "exp": exp, "lifetime_exp": lifetime_exp,
		"upgrade_levels": upgrade_levels, "skill_levels": skill_levels, "max_depth": max_depth,
		"pickaxe_tier": pickaxe_tier, "pickaxe_upgrade_levels": pickaxe_upgrade_levels, "golems": golems,
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
	pickaxe_upgrade_levels = _to_int_keyed_dict(parsed.get("pickaxe_upgrade_levels", {}))
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
	pickaxe_upgrade_levels.clear()
	golems.clear()
	last_summary.clear()
	save_game()
