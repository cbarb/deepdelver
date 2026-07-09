class_name MineGenerator
extends RefCounted
## Generates mine tile data one chunk (band of rows) at a time so the mine can
## be effectively infinite. Fills mostly filler, then seeds clustered veins of
## common/rare resources and the occasional barrier block, aiming for each
## biome's target distribution (GameData.TILE_DISTRIBUTION). Coverage is
## approximate (clusters can overlap) -- close enough for pacing.

const CHUNK := 20        # rows per chunk

var width: int
var rng: RandomNumberGenerator

func _init(grid_width: int, random: RandomNumberGenerator) -> void:
	width = grid_width
	rng = random

## Fills `grid` (Dictionary Vector2i->tile) for every row in the given chunk.
func generate_chunk(chunk_index: int, grid: Dictionary) -> void:
	var row0: int = maxi(1, chunk_index * CHUNK)
	var row1: int = chunk_index * CHUNK + CHUNK - 1

	# Pass 1: filler everywhere.
	for y in range(row0, row1 + 1):
		var bi := GameData.biome_index_for_row(y)
		var biome: Dictionary = GameData.BIOMES[bi]
		for x in range(width):
			grid[Vector2i(x, y)] = _make_filler(biome, bi, y)

	# Pass 2: seed clustered common/rare resources + barriers per target %.
	for y in range(row0, row1 + 1):
		var bi := GameData.biome_index_for_row(y)
		var biome: Dictionary = GameData.BIOMES[bi]
		var dist := GameData.tile_distribution(bi)
		# seed-chance per cell = target fraction / (avg cluster size * efficiency).
		# The efficiency factors compensate for coverage lost to cluster overlap and
		# chunk-edge clipping (measured empirically so coverage lands near target).
		var sc: float = float(dist["common"]) / (_avg(GameData.COMMON_VEIN) * 0.80)
		var sr: float = float(dist["rare"]) / (_avg(GameData.RARE_CLUSTER) * 0.60)
		var sb: float = float(dist["barrier"]) / (_avg(GameData.BARRIER_CLUSTER) * 0.85)
		for x in range(width):
			var roll := rng.randf()
			if roll < sc:
				_grow_cluster(Vector2i(x, y), biome, bi, grid, row0, row1, "common")
			elif roll < sc + sr:
				_grow_cluster(Vector2i(x, y), biome, bi, grid, row0, row1, "rare")
			elif roll < sc + sr + sb:
				_grow_cluster(Vector2i(x, y), biome, bi, grid, row0, row1, "barrier")

func _avg(range_arr: Array) -> float:
	return maxf(1.0, (float(range_arr[0]) + float(range_arr[1])) * 0.5)

## Random-walk a cluster of the given category from `start`, staying in-chunk.
func _grow_cluster(start: Vector2i, biome: Dictionary, bi: int, grid: Dictionary, row0: int, row1: int, category: String) -> void:
	var size_range: Array
	var tile_def := {}
	if category == "barrier":
		size_range = GameData.BARRIER_CLUSTER
	else:
		var pool := _resources_of_rarity(biome, category)
		if pool.is_empty():
			return
		tile_def = _weighted_pick(pool)
		if tile_def.is_empty():
			return
		size_range = GameData.COMMON_VEIN if category == "common" else GameData.RARE_CLUSTER

	var target: int = rng.randi_range(int(size_range[0]), int(size_range[1]))
	var cur := start
	var placed := 0
	var guard := 0
	while placed < target and guard < target * 6:
		guard += 1
		if cur.x >= 0 and cur.x < width and cur.y >= row0 and cur.y <= row1:
			if category == "barrier":
				grid[cur] = _make_barrier(biome, bi, cur.y)
			else:
				grid[cur] = _make_resource(tile_def, biome, bi, category, cur.y)
			placed += 1
		# random-walk step, biased slightly downward for a vein feel
		var dir := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, 1), Vector2i(0, -1)]
		cur += dir[rng.randi_range(0, dir.size() - 1)]

func _resources_of_rarity(biome: Dictionary, rarity: String) -> Array:
	var out: Array = []
	for r in biome["resources"]:
		if String(r.get("rarity", "common")) == rarity:
			out.append(r)
	return out

func _make_filler(biome: Dictionary, bi: int, row: int) -> Dictionary:
	var f := _weighted_pick(biome["fillers"])
	return {
		"id": f["id"], "name": f["name"], "color": f["color"],
		"type": "filler", "glow": false,
		"max_health": _hp(bi, "filler", row),
		"exp": biome["exp_filler"], "drops": {},
	}

func _make_resource(res_def: Dictionary, biome: Dictionary, bi: int, category: String, row: int) -> Dictionary:
	var id: String = res_def["id"]
	var amt: Array = res_def["amount"]
	return {
		"id": id, "name": GameData.resource_name(id), "color": GameData.resource_color(id),
		"type": "resource", "rarity": category, "glow": bool(res_def.get("glow", false)),
		"max_health": _hp(bi, category, row),   # "common" or "rare"
		"exp": biome["exp_resource"],
		"drops": {id: [int(amt[0]), int(amt[1])]},
	}

func _make_barrier(biome: Dictionary, bi: int, row: int) -> Dictionary:
	var b: Dictionary = biome["barrier"]
	return {
		"id": b["id"], "name": b["name"], "color": b["color"],
		"type": "barrier", "glow": false,
		"max_health": _hp(bi, "barrier", row),
		"exp": biome["exp_filler"], "drops": {},   # tough, no resource drops
	}

## Base biome HP for a category, scaled up by the deep-descent multiplier.
func _hp(bi: int, category: String, row: int) -> int:
	return int(round(GameData.tile_hp(bi, category) * GameData.deep_hp_mult(row)))

func _weighted_pick(list: Array) -> Dictionary:
	var total := 0.0
	for e in list:
		total += float(e["weight"])
	if total <= 0.0:
		return {}
	var roll := rng.randf() * total
	for e in list:
		roll -= float(e["weight"])
		if roll <= 0.0:
			return e
	return list[list.size() - 1]
