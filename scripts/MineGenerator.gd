class_name MineGenerator
extends RefCounted
## Generates mine tile data one chunk (band of rows) at a time so the mine can
## be effectively infinite. Fills mostly filler, then carves ore *veins*
## (small clusters) rather than scattering resources evenly.

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
		var biome := GameData.biome_for_row(y)
		for x in range(width):
			grid[Vector2i(x, y)] = _make_filler(biome, y)

	# Pass 2: seed ore veins.
	for y in range(row0, row1 + 1):
		for x in range(width):
			var biome := GameData.biome_for_row(y)
			if rng.randf() < biome["vein_chance"]:
				_grow_vein(Vector2i(x, y), biome, grid, row0, row1)

func _grow_vein(start: Vector2i, biome: Dictionary, grid: Dictionary, row0: int, row1: int) -> void:
	var res_def := _weighted_pick(biome["resources"])
	if res_def.is_empty():
		return
	var cs: Array = biome["cluster_size"]
	var target: int = rng.randi_range(int(cs[0]), int(cs[1]))
	var cur := start
	var placed := 0
	var guard := 0
	while placed < target and guard < target * 6:
		guard += 1
		if cur.x >= 0 and cur.x < width and cur.y >= row0 and cur.y <= row1:
			grid[cur] = _make_resource(res_def, biome, cur.y)
			placed += 1
		# random-walk step, biased slightly downward for vein feel
		var dir := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, 1), Vector2i(0, -1)]
		cur += dir[rng.randi_range(0, dir.size() - 1)]

func _make_filler(biome: Dictionary, row: int) -> Dictionary:
	var f := _weighted_pick(biome["fillers"])
	return {
		"id": f["id"], "name": f["name"], "color": f["color"],
		"type": "filler", "glow": false,
		"max_health": biome["base_health"],
		"exp": biome["exp_filler"], "drops": {},
	}

func _make_resource(res_def: Dictionary, biome: Dictionary, row: int) -> Dictionary:
	var id: String = res_def["id"]
	var amt: Array = res_def["amount"]
	return {
		"id": id, "name": GameData.resource_name(id), "color": GameData.resource_color(id),
		"type": "resource", "glow": bool(res_def.get("glow", false)),
		"max_health": int(ceil(biome["base_health"] * 1.4)),
		"exp": biome["exp_resource"],
		"drops": {id: [int(amt[0]), int(amt[1])]},
	}

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
