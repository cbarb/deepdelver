class_name MineController
extends Node3D
## Drives a single 60-second mining run:
##  - builds the 3D world (blocks, lights, orthographic side-view camera)
##  - handles mouse hover + click mining with the open-side rule & cooldown
##  - runs AI miners and drills
##  - tracks the run summary and ends the round on the timer.

signal run_finished(summary: Dictionary)

const WIDTH := 14
const BLOCK := 1.0
const RUN_TIME := 60.0
const SPAWN_AHEAD := 26          # rows generated/spawned below the frontier
const COIN_DROP_CHANCE := 0.25   # any mined tile has this chance to drop coins
const START_ABOVE_WINDOW := 10   # rows of shaft spawned above a transport start

# --- grid state ---
var grid: Dictionary = {}         # Vector2i -> tile dict (solid, unmined)
var air: Dictionary = {}          # Vector2i -> true (mined out)
var blocks: Dictionary = {}       # Vector2i -> TileBlock
var spawned_rows: Dictionary = {} # row -> true
var generated_chunks: Dictionary = {}
var rng := RandomNumberGenerator.new()
var generator: MineGenerator

# --- nodes ---
var camera: Camera3D
var hud   # HUD instance
var _blocks_root: Node3D
var _fx_root: Node3D
var _bg_back: MeshInstance3D          # biome backdrop: settled biome (opaque)
var _bg_back_mat: StandardMaterial3D
var _bg_front: MeshInstance3D         # incoming biome, cross-fades over the back
var _bg_front_mat: StandardMaterial3D
var _bg_biome := -1
var _bg_mix := 1.0                    # 0..1 cross-fade progress of the front quad
var _mouse_light: OmniLight3D         # torch light that follows the cursor

# --- run state ---
var stats: Dictionary = {}
var running := false
var time_left := RUN_TIME
var frontier := 0                 # deepest mined row (meters)
var spawn_floor := 1              # lowest row we spawn blocks from (raised by transport)
var _start_depth := 0             # run start depth from Elevator/Drillevator (0 = surface)
var _shaft_col := int(WIDTH / 2)  # central column carved as the transport shaft
var cam_focus_row := 4.0
var cooldown_left := 0.0
var hovered: TileBlock = null
var ortho_size := 13.0

# --- run summary accumulators ---
var tiles_mined := 0
var run_resources: Dictionary = {}
var run_exp := 0
var run_money := 0
var rare_found := 0

# --- workers (golems) ---
var workers: Array = []           # each: {node, target, cd, kind, damage, interval, res_bonus, color}

# --- machines (Auto-Hammer / Line Drill / Deep Bore, plus fuel) ---
var _machines: Array = []
var _fuel_timer := 0.0

# --- active damage-overflow chain reactions (advanced over time in _process) ---
var _chains: Array = []           # each: {current, overflow, source, res_bonus, chained, origin, cd}

const DIRS := [Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)]
const SURROUND := [                 # 8 blocks around a tile (for overflow splash)
	Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1),
	Vector2i(-1, 0),                   Vector2i(1, 0),
	Vector2i(-1, 1), Vector2i(0, 1), Vector2i(1, 1),
]
const OVERFLOW_STAGGER := 0.05      # seconds between each chain-reaction hop (chain saved for later)
const MINER_GRAVITY := 22.0         # miners fall (never jump)
const MINER_WALK := 3.5             # miner horizontal walk speed
const WORKER_Z := 0.6               # z offset so workers sit in front of blocks
const BG_TINT := 0.42               # darken the biome backdrop
const BG_FADE := 0.8                # seconds to cross-fade between biome backdrops
const BG_Z := -30.0                 # backdrop distance behind the blocks
const LIGHT_Z := 3.0                # mouse light distance in front of the blocks
const FUEL_BURN := 2.5              # seconds per unit of fuel consumed
const CENTER_X := (WIDTH - 1) * 0.5 * BLOCK
const CAM_OFFSET := Vector3(-0.5, 1.5, 20.0)   # slight tilt: shows top + left faces

# ===========================================================================
func start_run() -> void:
	rng.randomize()
	generator = MineGenerator.new(WIDTH, rng)
	stats = GameState.get_effective_stats()

	_build_environment()
	_blocks_root = Node3D.new()
	add_child(_blocks_root)
	_fx_root = Node3D.new()
	add_child(_fx_root)

	# HUD
	hud = preload("res://scripts/HUD.gd").new()
	add_child(hud)

	_reset_run()
	_apply_transport_start()      # Elevator / Drillevator: begin deep via a carved shaft
	_ensure_world()
	_spawn_workers()
	_init_machines()
	_update_camera(true)          # snap the camera to the start depth

	running = true
	set_process(true)
	set_process_unhandled_input(true)

func _reset_run() -> void:
	time_left = RUN_TIME
	frontier = 0
	spawn_floor = 1
	_start_depth = 0
	cam_focus_row = 4.0
	cooldown_left = 0.0
	tiles_mined = 0
	run_exp = 0
	run_money = 0
	rare_found = 0
	run_resources.clear()
	_chains.clear()

# ===========================================================================
# World build
# ===========================================================================
func _build_environment() -> void:
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color8(6, 5, 9)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color8(70, 76, 100)
	env.ambient_light_energy = 0.12         # very dark, moody base
	we.environment = env
	add_child(we)

	# Faint key light from upper-left (matches the tile art lighting).
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 40, 0)
	sun.light_energy = 0.22
	add_child(sun)

	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-25, -130, 0)
	fill.light_energy = 0.05
	fill.light_color = Color8(150, 170, 210)
	add_child(fill)

	# Torch light that follows the mouse and lights nearby blocks.
	_mouse_light = OmniLight3D.new()
	_mouse_light.light_color = Color8(255, 236, 200)
	_mouse_light.light_energy = 6.0
	_mouse_light.omni_range = 12.0
	_mouse_light.omni_attenuation = 1.2
	add_child(_mouse_light)

	# Two backdrop quads behind the blocks; the front one cross-fades on biome change.
	_bg_back = _make_bg_quad(false)
	_bg_back_mat = _bg_back.material_override
	_bg_front = _make_bg_quad(true)
	_bg_front_mat = _bg_front.material_override

	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = ortho_size
	camera.near = 0.05
	camera.far = 2000.0
	add_child(camera)
	camera.current = true
	_update_camera(true)

func world_pos(pos: Vector2i) -> Vector3:
	return Vector3(pos.x * BLOCK, -pos.y * BLOCK, 0.0)

# ===========================================================================
# Grid queries
# ===========================================================================
func is_solid(pos: Vector2i) -> bool:
	if pos.y < 1 or pos.x < 0 or pos.x >= WIDTH:
		return false
	if air.has(pos):
		return false
	return grid.has(pos)

func is_air(pos: Vector2i) -> bool:
	# Surface / sky above row 1 is open.
	if pos.y <= 0:
		return true
	# Horizontal + un-generated depths are treated as solid walls.
	if pos.x < 0 or pos.x >= WIDTH:
		return false
	return air.has(pos)

func is_mineable(pos: Vector2i) -> bool:
	if not is_solid(pos):
		return false
	return is_air(pos + Vector2i(0, -1)) or is_air(pos + Vector2i(0, 1)) \
		or is_air(pos + Vector2i(-1, 0)) or is_air(pos + Vector2i(1, 0))

# ===========================================================================
# Generation + spawn window
# ===========================================================================
func _ensure_world() -> void:
	var deepest: int = maxi(frontier + SPAWN_AHEAD, 34)
	for y in range(spawn_floor, deepest + 1):
		_spawn_row(y)

## Descent screen: start the run down at the depth chosen there (clamped to the
## transport cap) by carving a central shaft down to it. 0 = start at the surface.
func _apply_transport_start() -> void:
	var cap := GameState.transport_start_depth()
	var chosen := GameState.selected_start_depth
	if chosen < 0:
		chosen = cap                       # unset -> default to the deepest allowed
	_start_depth = clampi(chosen, 0, cap)
	if _start_depth <= 0:
		_start_depth = 0
		return
	# Only spawn (and carve) a window of shaft above the start point; everything
	# higher stays un-spawned (off-screen) so deep starts don't build the whole map.
	spawn_floor = maxi(1, _start_depth - START_ABOVE_WINDOW)
	for y in range(spawn_floor, _start_depth + 1):
		air[Vector2i(_shaft_col, y)] = true      # open the shaft (air needs no grid entry)
	frontier = _start_depth
	cam_focus_row = float(_start_depth)

func _spawn_row(y: int) -> void:
	if spawned_rows.has(y):
		return
	_ensure_generated(y)
	for x in range(WIDTH):
		var pos := Vector2i(x, y)
		if grid.has(pos) and not air.has(pos) and not blocks.has(pos):
			_spawn_block(pos)
	spawned_rows[y] = true

func _ensure_generated(y: int) -> void:
	var ci: int = int(floor(float(y) / float(MineGenerator.CHUNK)))
	if generated_chunks.has(ci):
		return
	generated_chunks[ci] = true
	generator.generate_chunk(ci, grid)

func _spawn_block(pos: Vector2i) -> void:
	if blocks.has(pos):
		return
	var tb := TileBlock.new()
	tb.setup(pos, grid[pos], BLOCK)
	tb.position = world_pos(pos)
	_blocks_root.add_child(tb)
	blocks[pos] = tb
	# Ore Scanner: ping resource tiles so they're easy to spot.
	if int(stats.get("scanner_level", 0)) > 0 and grid[pos].get("type", "filler") == "resource":
		tb.set_scanned(true)

# ===========================================================================
# Main loop
# ===========================================================================
func _process(delta: float) -> void:
	if not running:
		return
	time_left -= delta
	cooldown_left = maxf(0.0, cooldown_left - delta)
	if time_left <= 0.0:
		_end_run()
		return

	_update_hover()
	_update_mouse_light()
	_process_workers(delta)
	_process_machines(delta)
	_process_chains(delta)
	_update_camera(false)
	_update_hud()

func _update_camera(instant: bool) -> void:
	var target := maxf(float(frontier) + 3.0, 4.0)
	if instant:
		cam_focus_row = target
	else:
		cam_focus_row = lerpf(cam_focus_row, target, clampf(get_process_delta_time() * 3.0, 0.0, 1.0))
	var focus := Vector3(CENTER_X, -cam_focus_row * BLOCK, 0.0)
	camera.position = focus + CAM_OFFSET
	camera.look_at(focus, Vector3.UP)
	camera.size = ortho_size
	_update_background(focus)

func _make_bg_quad(fading: bool) -> MeshInstance3D:
	var q := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(1, 1)
	q.mesh = qm
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	mat.albedo_color = Color(BG_TINT, BG_TINT, BG_TINT, 1.0)
	if fading:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA   # cross-fade via alpha
	q.material_override = mat
	q.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(q)
	return q

## Keeps both backdrop quads centred on the camera view and cross-fades the
## front one in when the visible depth crosses into a new biome.
func _update_background(focus: Vector3) -> void:
	if _bg_back == null:
		return
	# Centre on the camera's view axis at BG_Z so the backdrop always fills view.
	var cam_pos := camera.position
	var fwd := (focus - cam_pos)
	var center := focus
	if absf(fwd.z) > 0.001:
		var t := (BG_Z - cam_pos.z) / fwd.z
		center = cam_pos + fwd * t
	var vp := get_viewport().get_visible_rect().size
	var aspect := vp.x / maxf(1.0, vp.y)
	var h := ortho_size * 1.15
	var sc := Vector3(h * aspect, h, 1.0)
	_bg_back.global_position = Vector3(center.x, center.y, BG_Z)
	_bg_back.scale = sc
	_bg_front.global_position = Vector3(center.x, center.y, BG_Z + 0.1)  # just in front of back
	_bg_front.scale = sc

	# Biome change -> start a cross-fade (settle old biome onto the back quad).
	var bi := GameData.biome_index_for_row(int(round(cam_focus_row)))
	if bi != _bg_biome:
		var first := _bg_biome == -1
		_bg_back_mat.albedo_texture = _bg_front_mat.albedo_texture
		_bg_front_mat.albedo_texture = GameData.get_biome_bg(bi)
		_bg_mix = 1.0 if first else 0.0
		_bg_biome = bi

	if _bg_mix < 1.0:
		_bg_mix = minf(1.0, _bg_mix + get_process_delta_time() / BG_FADE)
	_bg_front_mat.albedo_color = Color(BG_TINT, BG_TINT, BG_TINT, _bg_mix)

## Projects the mouse onto a plane in front of the blocks and parks the torch light there.
func _update_mouse_light() -> void:
	if _mouse_light == null or camera == null:
		return
	var mp := get_viewport().get_mouse_position()
	var origin := camera.project_ray_origin(mp)
	var dir := camera.project_ray_normal(mp)
	if absf(dir.z) < 0.0001:
		return
	var t := (LIGHT_Z - origin.z) / dir.z
	_mouse_light.global_position = origin + dir * t

# ===========================================================================
# Mouse interaction
# ===========================================================================
func _update_hover() -> void:
	var tb := _raycast_tile()
	if tb == hovered:
		if is_instance_valid(hovered):
			hovered.set_highlight(true, not is_mineable(hovered.grid_pos))
		return
	if is_instance_valid(hovered):
		hovered.set_highlight(false)
	hovered = tb
	if is_instance_valid(hovered):
		hovered.set_highlight(true, not is_mineable(hovered.grid_pos))

func _raycast_tile() -> TileBlock:
	var vp := get_viewport()
	if vp == null or camera == null:
		return null
	var mp := vp.get_mouse_position()
	var from := camera.project_ray_origin(mp)
	var dir := camera.project_ray_normal(mp)
	var params := PhysicsRayQueryParameters3D.create(from, from + dir * 500.0)
	var hit := get_world_3d().direct_space_state.intersect_ray(params)
	if hit.is_empty():
		return null
	var c = hit.get("collider")
	return c if c is TileBlock else null

func _unhandled_input(event: InputEvent) -> void:
	if not running:
		return
	if event is InputEventMouseButton and event.pressed:
		match event.button_index:
			MOUSE_BUTTON_LEFT:
				_try_player_mine()
			MOUSE_BUTTON_WHEEL_UP:
				ortho_size = clampf(ortho_size - 1.0, 7.0, 30.0)
			MOUSE_BUTTON_WHEEL_DOWN:
				ortho_size = clampf(ortho_size + 1.0, 7.0, 30.0)

func _try_player_mine() -> void:
	if cooldown_left > 0.0:
		hud.flash("On cooldown", Color8(255, 200, 90))
		return
	var tb := _raycast_tile()
	if not is_instance_valid(tb):
		return
	if not is_mineable(tb.grid_pos):
		hud.flash("Blocked - no open side", Color8(255, 90, 90))
		return
	cooldown_left = stats["click_cooldown"]
	hud.swing()
	var dmg := _manual_damage(tb.grid_pos)
	var is_crit: bool = rng.randf() < stats["crit_chance"]
	if is_crit:
		dmg *= stats["crit_damage"]
		_popup(tb.position, "CRIT!", Color8(255, 220, 80))
	# Pickaxe: chance to instantly break the tile.
	if rng.randf() < stats["instant_chance"]:
		dmg = maxf(dmg, tb.remaining())
		_popup(tb.position, "INSTANT!", Color8(180, 240, 255))
	_damage_tile(tb.grid_pos, dmg, "manual", stats["manual_resource_bonus"])

func _manual_damage(pos: Vector2i) -> float:
	return stats["click_damage"] + stats["deep_bonus"] * (float(pos.y) / 100.0)

# ===========================================================================
# Damage / breaking
# ===========================================================================
func _damage_tile(pos: Vector2i, dmg: float, source: String, res_bonus: float) -> bool:
	var tb: TileBlock = blocks.get(pos)
	if not is_instance_valid(tb):
		return false
	var before := tb.remaining()
	if tb.apply_damage(dmg):
		_break_tile(pos, source, res_bonus)
		# Damage overflow: leftover damage is split evenly across surrounding blocks.
		var overflow := dmg - before
		if overflow > 0.0:
			_overflow_splash(pos, overflow, source, res_bonus)
		if source == "manual":
			_manual_break_effects(pos)
		return true
	return false

## Pickaxe on-break effects (manual mining only): shatter splash + cooldown refund.
func _manual_break_effects(origin: Vector2i) -> void:
	if stats["shatter_damage"] > 0.0 and rng.randf() < stats["shatter_chance"]:
		_overflow_splash(origin, stats["shatter_damage"], "manual", stats["manual_resource_bonus"])
	if stats["refund_amount"] > 0.0 and rng.randf() < stats["refund_chance"]:
		cooldown_left = maxf(0.0, cooldown_left - stats["click_cooldown"] * stats["refund_amount"])

## Overflow splash: the leftover damage from a broken tile is divided evenly
## among all surrounding solid blocks and applied in one pass (no chaining).
func _overflow_splash(origin: Vector2i, overflow: float, source: String, res_bonus: float) -> void:
	var targets: Array[Vector2i] = []
	for d in SURROUND:
		var np: Vector2i = origin + d
		if is_solid(np):
			targets.append(np)
	if targets.is_empty():
		return
	var share := overflow / float(targets.size())
	for np in targets:
		_spawn_block(np)
		var tb: TileBlock = blocks.get(np)
		if not is_instance_valid(tb):
			continue
		if tb.apply_damage(share):
			_break_tile(np, source, res_bonus)   # any excess on this block is lost (no chain)

# --- SHELVED: damage-overflow chain reaction (kept for later, currently unused) ---
## Queues a damage-overflow chain reaction that propagates one tile per
## OVERFLOW_STAGGER seconds (advanced in _process_chains), so it reads as a
## travelling cascade rather than an instant wipe.
func _overflow_chain(origin: Vector2i, overflow: float, source: String, res_bonus: float) -> void:
	_chains.append({
		"current": origin, "overflow": overflow, "source": source,
		"res_bonus": res_bonus, "chained": 0, "origin": origin, "cd": OVERFLOW_STAGGER,
	})

func _process_chains(delta: float) -> void:
	if _chains.is_empty():
		return
	var still: Array = []
	var guard := 0
	for ch in _chains:
		ch["cd"] -= delta
		# advance at most a few hops per frame in case of frame drops
		while ch["cd"] <= 0.0 and ch["overflow"] > 0.0 and guard < 4096:
			guard += 1
			ch["cd"] += OVERFLOW_STAGGER
			_advance_chain(ch)
		if ch["overflow"] > 0.0:
			still.append(ch)                          # still cascading
		elif ch["chained"] >= 1:
			_popup(world_pos(ch["origin"]), "CHAIN x%d" % (int(ch["chained"]) + 1), Color8(255, 160, 60))
	_chains = still

## One hop of a chain: bleed the leftover damage into a random adjacent solid
## tile, breaking it (and continuing) or partially damaging it (and stopping).
func _advance_chain(ch: Dictionary) -> void:
	var options: Array[Vector2i] = []
	for d in DIRS:
		var np: Vector2i = ch["current"] + d
		if is_solid(np):
			options.append(np)
	if options.is_empty():
		ch["overflow"] = 0.0                          # dead end -> finished
		return
	var target: Vector2i = options[rng.randi_range(0, options.size() - 1)]
	_spawn_block(target)
	var tb: TileBlock = blocks.get(target)
	if not is_instance_valid(tb):
		ch["overflow"] = 0.0
		return
	var before := tb.remaining()
	if ch["overflow"] >= before:
		tb.apply_damage(before)
		_break_tile(target, ch["source"], ch["res_bonus"])
		ch["overflow"] -= before
		ch["chained"] = int(ch["chained"]) + 1
		ch["current"] = target
	else:
		tb.apply_damage(ch["overflow"])               # partial hit, chain stops
		ch["overflow"] = 0.0

func _break_tile(pos: Vector2i, source: String, res_bonus: float) -> void:
	var tile: Dictionary = grid.get(pos, {})
	# Update grid state.
	air[pos] = true
	grid.erase(pos)
	var tb: TileBlock = blocks.get(pos)
	if is_instance_valid(tb):
		if tb == hovered:
			hovered = null
		tb.queue_free()
	blocks.erase(pos)
	_break_particles(world_pos(pos), tile.get("color", Color.WHITE))

	tiles_mined += 1
	if pos.y > frontier:
		frontier = pos.y
		_ensure_world()
	GameState.max_depth = maxi(GameState.max_depth, pos.y)

	var is_res: bool = tile.get("type", "filler") == "resource"

	# EXP (pickaxe can grant bonus EXP from filler tiles)
	var exp_mult_v: float = stats["exp_mult"]
	if not is_res:
		exp_mult_v *= (1.0 + stats["filler_exp_bonus"])
	var exp_gain := int(round(float(tile.get("exp", 1)) * exp_mult_v))
	run_exp += exp_gain
	GameState.add_exp(exp_gain)

	# Drops
	var mult: float = stats["resource_mult"] + res_bonus
	if is_res:
		var drops: Dictionary = tile.get("drops", {})
		var label := ""
		for res_id in drops:
			var rng_amt: Array = drops[res_id]
			var base_amt := rng.randi_range(int(rng_amt[0]), int(rng_amt[1]))
			var amount := int(round(base_amt * mult))
			if rng.randf() < stats["lucky_chance"]:
				amount *= 2
			# Pickaxe: chance to duplicate a manually-mined drop.
			if source == "manual" and rng.randf() < stats["dup_chance"]:
				amount *= 2
			if amount > 0:
				GameState.add_resource(res_id, amount)
				run_resources[res_id] = int(run_resources.get(res_id, 0)) + amount
				label = "+%d %s" % [amount, GameData.resource_name(res_id)]
		rare_found += 1
		if label != "":
			_popup(world_pos(pos), label, tile.get("color", Color.WHITE))
	else:
		# Filler yields Rubble -> crushed into Coins at the surface.
		var amt := maxi(1, int(round(1.0 * mult)))
		GameState.add_resource("rubble", amt)
		run_resources["rubble"] = int(run_resources.get("rubble", 0)) + amt

	# Any tile (filler / resource / barrier) has a chance to drop loose coins.
	# Amount scales with depth so it stays relevant. This is direct coin income
	# on top of the Crusher, so mining pays out from the very first run.
	if rng.randf() < COIN_DROP_CHANCE:
		var bi := GameData.biome_index_for_row(pos.y)
		var coins := rng.randi_range(1, 3) + bi
		GameState.add_money(coins)
		run_money += coins
		_popup(world_pos(pos), "+%d coins" % coins, Color8(255, 210, 90))

func _spark(pos: Vector2i, color: Color) -> void:
	_popup(world_pos(pos), "", color)

## A short one-shot burst of little rubble chunks when a block breaks.
func _break_particles(at: Vector3, color: Color) -> void:
	var p := CPUParticles3D.new()
	p.position = at
	var bm := BoxMesh.new()
	bm.size = Vector3(0.14, 0.14, 0.14)
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true      # tint each chunk by the tile colour
	mat.roughness = 0.95
	bm.material = mat
	p.mesh = bm
	p.amount = 14
	p.lifetime = 0.55
	p.one_shot = true
	p.explosiveness = 1.0                       # emit the whole burst at once
	p.spread = 180.0                            # fling outward in all directions
	p.initial_velocity_min = 1.5
	p.initial_velocity_max = 3.6
	p.gravity = Vector3(0, -9.0, 0)             # then tumble down
	p.angular_velocity_min = -540.0
	p.angular_velocity_max = 540.0
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.15
	p.color = Color(color.r, color.g, color.b, 1.0)
	_blocks_root.add_child(p)
	p.emitting = true
	# Free the emitter once its particles have died.
	get_tree().create_timer(p.lifetime + 0.3).timeout.connect(p.queue_free)

# ===========================================================================
# Workers: AI miners + drills
# ===========================================================================
func _spawn_workers() -> void:
	for w in workers:
		if is_instance_valid(w["node"]):
			w["node"].queue_free()
	workers.clear()

	# Golems from the Workshop roster. Active golems are capped to the biome
	# reached (Biome N -> N max active), spawning the strongest tiers first.
	# (A future Stonewarden specialization would raise this cap.)
	var max_active: int = GameData.biome_index_for_row(GameState.max_depth) + 1
	var owned_tiers: Array = []
	for tier in GameState.golems:
		for i in range(int(GameState.golems[tier])):
			owned_tiers.append(int(tier))
	owned_tiers.sort()
	owned_tiers.reverse()                       # strongest tier first
	if owned_tiers.size() > max_active:
		owned_tiers.resize(max_active)
	for tier in owned_tiers:
		var g := GameState.golem_data(tier)
		var eff: Dictionary = g.get("effect", {})
		var dmg: float = (float(g["base_damage"]) + stats["ai_damage"]) * stats["ai_damage_mult"]
		var interval: float = maxf(0.4, float(g["interval"]) * stats["ai_interval"])
		var rbon: float = stats["ai_resource_bonus"] + float(eff.get("res_bonus", 0.0))
		var col := Color.from_hsv(lerpf(0.33, 0.55, float(tier - 1) / 9.0), 0.6, 0.95)
		workers.append(_make_worker("golem", col, interval, dmg, rbon, {
			"prefer_resource": bool(eff.get("prefer_resource", false)),
			"double_hit": float(eff.get("double_hit_chance", 0.0)),
			"splash_chance": float(eff.get("splash_chance", 0.0)),
			"splash_damage": float(eff.get("splash_damage", 0.0)),
		}))
	# Basic Drills (flying machines).
	var dm: Dictionary = GameData.MACHINES["buy_drill"]
	var d_int: float = maxf(0.3, float(dm["base_interval"]) * stats["machine_speed"])
	var d_dmg: float = (float(dm["base_damage"]) + stats["machine_damage"]) * stats["machine_damage_mult"]
	for i in range(int(stats["drill_count"])):
		workers.append(_make_worker("drill", Color8(255, 150, 60), d_int, d_dmg, 0.0, {}))

func _make_worker(kind: String, color: Color, interval: float, damage: float, res_bonus: float, effect: Dictionary) -> Dictionary:
	var node := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.4, 0.4, 0.4)
	node.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 0.8
	node.material_override = mat
	if _start_depth > 0:
		# Transport run: drop workers into the shaft near the start depth.
		node.position = world_pos(Vector2i(_shaft_col, maxi(1, _start_depth - 2))) + Vector3(0, 0.5, 1.0)
	else:
		node.position = Vector3(CENTER_X + randf_range(-3, 3), 1.0, 1.0)
	add_child(node)
	return {"node": node, "target": null, "cd": interval * randf_range(0.2, 1.0),
		"kind": kind, "damage": damage, "interval": interval, "res_bonus": res_bonus,
		"color": color, "idle_off": randf_range(-3.0, 3.0), "vy": 0.0,
		"prefer_resource": bool(effect.get("prefer_resource", false)),
		"double_hit": float(effect.get("double_hit", 0.0)),
		"splash_chance": float(effect.get("splash_chance", 0.0)),
		"splash_damage": float(effect.get("splash_damage", 0.0))}

func _process_workers(delta: float) -> void:
	for w in workers:
		if not is_instance_valid(w["node"]):
			continue
		if w["kind"] == "golem":
			_process_miner(w, delta)
		else:
			_process_drill(w, delta)

## Miner: gravity-bound agent. It falls (never jumps), walks along the floor
## toward the nearest available block, and mines whatever solid tile is next to
## it (digging sideways through walls / straight down).
func _process_miner(w: Dictionary, delta: float) -> void:
	var node: MeshInstance3D = w["node"]
	var pos := node.global_position
	var col := clampi(int(round(pos.x / BLOCK)), 0, WIDTH - 1)
	var row := int(round(-pos.y / BLOCK))

	# Fall through any open cells directly below to find the resting row.
	var floor_row := row
	var g := 0
	while g < 1000 and is_air(Vector2i(col, floor_row + 1)):
		floor_row += 1
		g += 1
	var floor_y := -floor_row * BLOCK

	# Gravity: only ever move down toward the floor.
	if pos.y > floor_y + 0.02:
		w["vy"] += MINER_GRAVITY * delta
		pos.y = maxf(floor_y, pos.y - float(w["vy"]) * delta)
	else:
		pos.y = floor_y
	if pos.y <= floor_y + 0.001:
		w["vy"] = 0.0
	var grounded := pos.y <= floor_y + 0.06
	row = floor_row

	# Direction toward the nearest available (unclaimed) block.
	var nearest = _find_worker_target(w, node.global_position, -2147483648, w["prefer_resource"])
	var dir := 0
	if nearest != null:
		dir = signi(int(nearest.x) - col)

	# The block this golem will actually mine (adjacent + reachable) -> claim it.
	var dig = _pick_miner_dig(w, col, row, dir)
	w["target"] = dig

	# Walk toward the target through open air; a wall in the way is mined, not passed.
	if grounded and dir != 0 and is_air(Vector2i(col + dir, row)):
		pos.x = move_toward(pos.x, float(col + dir) * BLOCK, MINER_WALK * delta)
	node.global_position = Vector3(pos.x, pos.y, WORKER_Z)

	# Mine when grounded and something is adjacent.
	if grounded and dig != null:
		w["cd"] -= delta
		if w["cd"] <= 0.0:
			w["cd"] = w["interval"]
			var dmg: float = w["damage"]
			if w["double_hit"] > 0.0 and rng.randf() < w["double_hit"]:
				dmg *= 2.0
			var broke := _damage_tile(dig, dmg, "golem", w["res_bonus"])
			# Golem splash effect (Spore/Astral/Core) on a break.
			if broke and w["splash_damage"] > 0.0 and rng.randf() < w["splash_chance"]:
				_overflow_splash(dig, w["splash_damage"], "golem", w["res_bonus"])

## Adjacent solid tile a miner should dig, in priority order: toward its target,
## straight down, either side, then up. Skips tiles another worker has claimed.
func _pick_miner_dig(w: Dictionary, col: int, row: int, dir: int):
	var cands: Array[Vector2i] = []
	if dir != 0:
		cands.append(Vector2i(col + dir, row))
	cands.append(Vector2i(col, row + 1))
	cands.append(Vector2i(col - 1, row))
	cands.append(Vector2i(col + 1, row))
	cands.append(Vector2i(col, row - 1))
	for c in cands:
		if is_solid(c) and not _target_taken_by_other(w, c):
			return c
	return null

## Drill: flies (machine), but only targets tiles at or below its current row.
func _process_drill(w: Dictionary, delta: float) -> void:
	var node: MeshInstance3D = w["node"]
	var drill_row := int(round(-node.global_position.y / BLOCK))
	var target = w["target"]
	if target == null or not is_mineable(target) or int(target.y) < drill_row or _target_taken_by_other(w, target):
		w["target"] = _find_worker_target(w, node.global_position, drill_row)
		target = w["target"]
	if target == null:
		var idle := Vector3(CENTER_X + w["idle_off"], -maxf(float(frontier), 1.0) * BLOCK + 1.0, WORKER_Z)
		node.global_position = node.global_position.lerp(idle, delta * 2.0)
		return
	var tpos: Vector3 = world_pos(target) + Vector3(0, 0, WORKER_Z)
	node.global_position = node.global_position.lerp(tpos, clampf(delta * 6.0, 0.0, 1.0))
	w["cd"] -= delta
	if w["cd"] <= 0.0 and node.global_position.distance_to(tpos) < BLOCK * 1.3:
		w["cd"] = w["interval"]
		_damage_tile(target, w["damage"], "drill", w["res_bonus"])

## True if a *different* worker is currently assigned to this tile.
func _target_taken_by_other(self_w: Dictionary, pos: Vector2i) -> bool:
	for w in workers:
		if w["node"] == self_w["node"]:
			continue
		if w["target"] == pos:
			return true
	return false

## Nearest mineable block not claimed by another worker. `min_row` restricts the
## search to that row or deeper (used by drills so they never go above).
func _find_worker_target(self_w: Dictionary, from: Vector3, min_row: int = -2147483648, prefer_resource: bool = false):
	var claimed := {}
	for w in workers:
		if w["node"] == self_w["node"]:
			continue
		if w["target"] != null:
			claimed[w["target"]] = true

	var best = null
	var best_score := INF
	for pos in blocks:
		if claimed.has(pos) or not is_mineable(pos):
			continue
		if int(pos.y) < min_row:
			continue
		var score := from.distance_to(world_pos(pos))
		if prefer_resource and blocks[pos].tile.get("type", "filler") == "resource":
			score -= 1000.0     # strongly prefer resource tiles
		if score < best_score:
			best_score = score
			best = pos
	return best

# ===========================================================================
# Machines: Auto-Hammer (area), Line Drill (column), Deep Bore (auto shaft)
# ===========================================================================
func _init_machines() -> void:
	_machines.clear()
	_fuel_timer = 0.0
	_add_machines("hammer", int(stats["hammer_count"]), Color8(255, 210, 70))
	_add_machines("linedrill", int(stats["linedrill_count"]), Color8(255, 140, 50))
	_add_machines("deepbore", int(stats["deepbore_count"]), Color8(235, 70, 70))

func _add_machines(kind: String, count: int, color: Color) -> void:
	if count <= 0:
		return
	var md: Dictionary = GameData.MACHINES["buy_" + kind]
	for i in range(count):
		var col := clampi(int((float(i) + 0.5) / float(maxi(1, count)) * WIDTH), 0, WIDTH - 1)
		_machines.append({
			"kind": kind, "node": _machine_node(color),
			"cd": float(md["base_interval"]) * randf_range(0.2, 1.0),
			"base_interval": float(md["base_interval"]), "base_damage": float(md["base_damage"]),
			"splash": float(md.get("splash", 0.0)), "pierce": int(md.get("pierce", 1)),
			"col": col, "bore_row": 1,
		})

func _machine_node(color: Color) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.55, 0.55, 0.55)
	node.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 1.0
	node.material_override = mat
	node.position = Vector3(CENTER_X, 1.0, WORKER_Z)
	add_child(node)
	return node

func _process_machines(delta: float) -> void:
	if _machines.is_empty():
		return
	# Fuel Engine: burn coal to speed up all machines while fuelled.
	var fuel_mult := 1.0
	var fl := int(stats["fuel_level"])
	if fl > 0 and _has_fuel():
		fuel_mult = maxf(0.4, 1.0 - 0.08 * fl)
		_fuel_timer += delta
		if _fuel_timer >= FUEL_BURN:
			_fuel_timer -= FUEL_BURN
			_burn_fuel()
	var mmult: float = stats["machine_damage_mult"]
	var mdmg: float = stats["machine_damage"]
	var mspeed: float = stats["machine_speed"]
	for mac in _machines:
		mac["cd"] -= delta
		if mac["cd"] <= 0.0:
			mac["cd"] = maxf(0.3, mac["base_interval"] * mspeed * fuel_mult)
			_fire_machine(mac, mdmg, mmult)

func _has_fuel() -> bool:
	return int(GameState.resources.get("coal", 0)) > 0 or int(GameState.resources.get("black_coal", 0)) > 0

func _burn_fuel() -> void:
	if int(GameState.resources.get("coal", 0)) > 0:
		GameState.resources["coal"] = int(GameState.resources["coal"]) - 1
	elif int(GameState.resources.get("black_coal", 0)) > 0:
		GameState.resources["black_coal"] = int(GameState.resources["black_coal"]) - 1

func _fire_machine(mac: Dictionary, mdmg: float, mmult: float) -> void:
	var dmg: float = (mac["base_damage"] + mdmg) * mmult
	match mac["kind"]:
		"hammer":
			var t = _random_exposed()
			if t == null:
				return
			mac["node"].global_position = world_pos(t) + Vector3(0, 0, WORKER_Z)
			_damage_tile(t, dmg, "machine", 0.0)
			_overflow_splash(t, (mac["splash"] + mdmg) * mmult, "machine", 0.0)   # area slam
			_popup(world_pos(t), "SLAM", Color8(255, 220, 90))
		"linedrill":
			var seed_tile = _random_exposed()
			if seed_tile == null:
				return
			var c: int = seed_tile.x
			var top = _topmost_solid_in_col(c, 1)
			if top == null:
				return
			mac["node"].global_position = world_pos(top) + Vector3(0, 0, WORKER_Z)
			var r: int = top.y
			var hits := 0
			while hits < int(mac["pierce"]) and r <= frontier + SPAWN_AHEAD:
				var p := Vector2i(c, r)
				if is_solid(p):
					_spawn_block(p)
					_damage_tile(p, dmg, "machine", 0.0)
					hits += 1
				r += 1
		"deepbore":
			var target = _topmost_solid_in_col(int(mac["col"]), int(mac["bore_row"]))
			if target == null:
				mac["bore_row"] = mini(int(mac["bore_row"]) + 1, frontier + SPAWN_AHEAD)
				return
			mac["bore_row"] = target.y
			mac["node"].global_position = world_pos(target) + Vector3(0, 0, WORKER_Z)
			_spawn_block(target)
			_damage_tile(target, dmg, "machine", 0.0)

func _random_exposed():
	var opts: Array[Vector2i] = []
	for pos in blocks:
		if is_mineable(pos):
			opts.append(pos)
	if opts.is_empty():
		return null
	return opts[rng.randi_range(0, opts.size() - 1)]

func _topmost_solid_in_col(c: int, from_row: int):
	var y := maxi(1, from_row)
	var limit := frontier + SPAWN_AHEAD + 4
	while y <= limit:
		if is_solid(Vector2i(c, y)):
			return Vector2i(c, y)
		y += 1
	return null

# ===========================================================================
# HUD + FX
# ===========================================================================
func _update_hud() -> void:
	var tile_name := ""
	var frac := 1.0
	var state := 0                       # 0 none, 1 mineable, 2 blocked
	if is_instance_valid(hovered):
		tile_name = hovered.tile.get("name", "")
		frac = hovered.health_fraction()
		state = 1 if is_mineable(hovered.grid_pos) else 2
	hud.update_hud({
		"time": time_left, "depth": frontier, "run_resources": run_resources,
		"run_exp": run_exp, "money": GameState.money, "exp": GameState.exp,
		"tile_name": tile_name, "tile_frac": frac, "tile_state": state,
		"cooldown": cooldown_left, "max_cooldown": stats["click_cooldown"],
	})

func _popup(at: Vector3, text: String, color: Color) -> void:
	if text == "":
		return
	var lbl := Label3D.new()
	lbl.text = text
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.modulate = color
	lbl.outline_modulate = Color(0, 0, 0, 0.8)
	lbl.font_size = 64
	lbl.outline_size = 12
	lbl.pixel_size = 0.006
	lbl.no_depth_test = true
	lbl.position = at + Vector3(0, 0, BLOCK)
	_fx_root.add_child(lbl)
	var t := lbl.create_tween()
	t.set_parallel(true)
	t.tween_property(lbl, "position", lbl.position + Vector3(0, 1.2, 0), 0.8)
	t.tween_property(lbl, "modulate:a", 0.0, 0.8)
	t.chain().tween_callback(lbl.queue_free)

# ===========================================================================
# End of run
# ===========================================================================
func _end_run() -> void:
	running = false
	set_process(false)
	set_process_unhandled_input(false)
	var summary := {
		"depth": frontier,
		"tiles_mined": tiles_mined,
		"resources": run_resources.duplicate(),
		"exp": run_exp,
		"rare_found": rare_found,
		"money": run_money,
		"new_record": frontier >= GameState.max_depth,
	}
	run_finished.emit(summary)
