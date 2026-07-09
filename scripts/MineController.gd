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
var _sfx_pool: Array = []             # round-robin AudioStreamPlayers for mining SFX
var _sfx_idx := 0

# --- run state ---
var stats: Dictionary = {}
var running := false
var _paused := false
var _pause_menu   # PauseMenu instance while paused, else null
var time_left := RUN_TIME
var frontier := 0                 # deepest mined row (meters)
var spawn_floor := 1              # lowest row we spawn blocks from (raised by transport)
var _start_depth := 0             # run start depth from Elevator/Drillevator (0 = surface)
var _shaft_col := int(WIDTH / 2)  # central column carved as the transport shaft
var cam_focus_row := 4.0
var cooldown_left := 0.0
var _hit_count := 0                # manual swings this run (drives Bronze/Ember cadence)
var _mining_held := false          # left button held -> auto-mine each time the cooldown clears
var hovered: TileBlock = null
var ortho_size := 13.0
var _frenzy_left := 0.0            # Striker - Mining Frenzy: seconds of buffed manual mining remaining
var _aftershifting := false        # Engineer - Aftershift Automation: machines-only tail after the timer
var _aftershift_left := 0.0

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
# --- timed damage sequences (e.g. the Spore spiral fires one cell at a time) ---
var _sequences: Array = []        # each: {seq: [{pos, dmg}], i, cd, interval, res_bonus}
# --- Relic pickaxe: shards orbiting the cursor that chip any tile they pass ---
var _orbit_shards := 0            # current shard count (0..SHARD_MAX)
var _shard_nodes: Array = []      # Sprite3D visuals, one per shard
var _shard_angle := 0.0
var _shard_hit_t := 0.0
# --- cosmetic resource orbs that fly from a broken tile to the cursor ---
var _orbs: Array = []             # each: {node, vel, delay}
var _absorb_cd := 0.0             # throttles the absorb "droplet" SFX
var _sfx_absorb: AudioStream = null

const DIRS := [Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)]
const OVERFLOW_MAX_RADIUS := 14     # furthest ring the radial overflow blast can reach
const OVERFLOW_STAGGER := 0.05      # seconds between each chain-reaction hop
const CHAIN_SEEK_RADIUS := 7        # how far the snaking chain looks ahead for resource tiles
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

# Mining SFX. pick_1 = pickaxe striking a block, break_1 = a block breaking.
const SFX_PICK: AudioStream = preload("res://assets/sfx/pick_1.wav")
const SFX_BREAK: AudioStream = preload("res://assets/sfx/break_1.mp3")
const SFX_VOICES := 8              # simultaneous voices (rapid mining overlaps)

# Tier-1 (Rootbound) golem: 3x3 sprite sheet, 9-frame looping animation.
const ROOTBOUND_SHEET: Texture2D = preload("res://assets/spritesheets/rootbound_golem_spritesheet.png")
const GOLEM_SHEET_HFRAMES := 3
const GOLEM_SHEET_VFRAMES := 3
const GOLEM_SHEET_FRAMES := 9
const GOLEM_ANIM_FPS := 10.0
const GOLEM_SPRITE_PIXEL_SIZE := 0.016   # 64px frame -> ~1 block tall

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

	_init_audio()
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
	_hit_count = 0
	_mining_held = false
	_frenzy_left = 0.0
	_aftershifting = false
	_aftershift_left = 0.0
	tiles_mined = 0
	run_exp = 0
	run_money = 0
	rare_found = 0
	run_resources.clear()
	_chains.clear()
	_sequences.clear()
	_orbit_shards = 0
	_shard_angle = 0.0
	_shard_hit_t = 0.0
	for s in _shard_nodes:
		if is_instance_valid(s):
			s.queue_free()
	_shard_nodes.clear()
	for o in _orbs:
		if is_instance_valid(o["node"]):
			o["node"].queue_free()
	_orbs.clear()
	_absorb_cd = 0.0

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
# Audio
# ===========================================================================
func _init_audio() -> void:
	_sfx_pool.clear()
	for _i in SFX_VOICES:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_sfx_pool.append(p)
	_sfx_idx = 0
	# Optional absorb "droplet" sound; silent if the file hasn't been added.
	_sfx_absorb = load(ABSORB_SFX_PATH) if ResourceLoader.exists(ABSORB_SFX_PATH) else null

## Play a one-shot SFX on the next voice in the pool (round-robin so rapid hits
## overlap). `vary_pitch` adds a small random detune so repeats don't sound canned.
func _play_sfx(stream: AudioStream, vary_pitch := false, volume_db := 0.0) -> void:
	if stream == null or _sfx_pool.is_empty():
		return
	var p: AudioStreamPlayer = _sfx_pool[_sfx_idx]
	_sfx_idx = (_sfx_idx + 1) % _sfx_pool.size()
	p.stream = stream
	p.pitch_scale = rng.randf_range(0.93, 1.08) if vary_pitch else 1.0
	p.volume_db = volume_db
	p.play()

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
	if not running or _paused:
		return
	cooldown_left = maxf(0.0, cooldown_left - delta)
	_frenzy_left = maxf(0.0, _frenzy_left - delta)
	if _aftershifting:
		_run_aftershift(delta)      # timer is up: only machines keep working
		return
	time_left -= delta
	if time_left <= 0.0:
		# Engineer - Aftershift Automation: give machines a short overtime tail.
		if stats.get("machine_aftershift", 0.0) > 0.0 and not _machines.is_empty():
			_aftershifting = true
			_aftershift_left = stats["machine_aftershift"]
			hud.flash("AFTERSHIFT!", Color8(140, 175, 220))
			return
		_end_run()
		return

	# Hold-to-mine: fire again as soon as the cooldown clears (no per-tick flash).
	if _mining_held and cooldown_left <= 0.0:
		_try_player_mine()
	_update_hover()
	_update_mouse_light()
	_process_workers(delta)
	_process_machines(delta)
	_process_chains(delta)
	_process_sequences(delta)
	_process_shards(delta)
	_process_orbs(delta)
	_update_camera(false)
	_update_hud()

## Overtime phase: player and golems are done, machines finish their tail.
func _run_aftershift(delta: float) -> void:
	_aftershift_left -= delta
	_process_machines(delta)
	_process_chains(delta)
	_update_camera(false)
	_update_hud()
	if _aftershift_left <= 0.0:
		_aftershifting = false
		_end_run()

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
# Cosmetic resource orbs (fly from a broken tile to the cursor, then absorb)
# ===========================================================================
func _spawn_orbs(at: Vector3, color: Color, count: int) -> void:
	if _orbs.size() >= ORB_MAX_LIVE:
		return
	for i in count:
		var m := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.075
		sm.height = 0.15
		sm.radial_segments = 6
		sm.rings = 3
		m.mesh = sm
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = color
		mat.emission_enabled = true
		mat.emission = color
		mat.emission_energy_multiplier = 1.4
		m.material_override = mat
		m.position = at + Vector3(randf_range(-0.18, 0.18), randf_range(-0.18, 0.18), ORB_Z)
		add_child(m)
		# Small outward "pop" first, then it zooms straight to the cursor.
		var vel := Vector3(randf_range(-1.0, 1.0), randf_range(0.6, 1.8), 0.0) * randf_range(2.0, 4.0)
		_orbs.append({"node": m, "vel": vel, "delay": randf_range(0.04, 0.16), "speed": randf_range(6.0, 9.0)})

func _process_orbs(delta: float) -> void:
	_absorb_cd = maxf(0.0, _absorb_cd - delta)
	if _orbs.is_empty():
		return
	var cur := _cursor_world_pos()
	var target := Vector3(cur.x, cur.y, ORB_Z)
	var still: Array = []
	for orb in _orbs:
		var node: MeshInstance3D = orb["node"]
		if not is_instance_valid(node):
			continue
		if orb["delay"] > 0.0:
			orb["delay"] = float(orb["delay"]) - delta
			node.position += orb["vel"] * delta
			orb["vel"] *= 0.86                        # scatter, decelerating
			still.append(orb)
			continue
		# Zoom straight at the cursor, ramping speed up — move_toward always
		# converges (no orbiting).
		orb["speed"] = minf(ORB_MAX_SPEED, float(orb["speed"]) + ORB_ACCEL * delta)
		node.position = node.position.move_toward(target, float(orb["speed"]) * delta)
		if node.position.distance_to(target) <= ORB_ABSORB_DIST:
			node.queue_free()
			if _absorb_cd <= 0.0:
				_absorb_cd = ORB_SFX_THROTTLE
				_play_sfx(_sfx_absorb, true, -6.0)    # droplet/bubble (if the file exists)
			continue
		still.append(orb)
	_orbs = still

## World point under the cursor on the block plane (z=0). Used by orbiting shards.
func _cursor_world_pos() -> Vector3:
	if camera == null:
		return Vector3.ZERO
	var mp := get_viewport().get_mouse_position()
	var origin := camera.project_ray_origin(mp)
	var dir := camera.project_ray_normal(mp)
	if absf(dir.z) < 0.0001:
		return origin
	return origin + dir * ((0.0 - origin.z) / dir.z)

## Relic pickaxe: keep `_orbit_shards` shard sprites circling the cursor and let
## them chip any solid tile they pass over (50% of click damage, on a tick).
func _process_shards(delta: float) -> void:
	var want: int = _orbit_shards if stats.get("manual_pattern", "") == "relic_orbit" else 0
	while _shard_nodes.size() < want:
		var s := Sprite3D.new()
		s.texture = SHARD_ICON
		s.pixel_size = 0.022
		s.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		s.shaded = false
		add_child(s)
		_shard_nodes.append(s)
	while _shard_nodes.size() > want:
		var n = _shard_nodes.pop_back()
		if is_instance_valid(n):
			n.queue_free()
	if want == 0:
		return

	_shard_angle += SHARD_SPIN * delta
	var cur := _cursor_world_pos()
	var count := _shard_nodes.size()
	for i in count:
		var ang := _shard_angle + float(i) * TAU / float(count)
		_shard_nodes[i].global_position = Vector3(
			cur.x + cos(ang) * SHARD_ORBIT_R, cur.y + sin(ang) * SHARD_ORBIT_R, SHARD_Z)

	_shard_hit_t -= delta
	if _shard_hit_t <= 0.0:
		_shard_hit_t = SHARD_HIT_INTERVAL
		var dmg: float = stats["click_damage"] * SHARD_DMG_FRAC
		var rbon: float = stats["manual_resource_bonus"]
		for sn in _shard_nodes:
			var gp: Vector3 = sn.global_position
			var cell := Vector2i(int(round(gp.x)), int(round(-gp.y)))
			if is_solid(cell):
				_spawn_block(cell)
				_damage_tile(cell, dmg, "shard", rbon)

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
	if event.is_action_pressed("ui_cancel"):
		_toggle_pause()
		return
	if _paused:
		return
	if event is InputEventMouseButton:
		match event.button_index:
			MOUSE_BUTTON_LEFT:
				_mining_held = event.pressed        # hold to keep mining on cooldown
				if event.pressed:
					_try_player_mine()
			MOUSE_BUTTON_WHEEL_UP:
				if event.pressed:
					ortho_size = clampf(ortho_size - 1.0, 7.0, 30.0)
			MOUSE_BUTTON_WHEEL_DOWN:
				if event.pressed:
					ortho_size = clampf(ortho_size + 1.0, 7.0, 30.0)

func _try_player_mine() -> void:
	if _aftershifting:
		return
	if cooldown_left > 0.0:
		hud.flash("On cooldown", Color8(255, 200, 90))
		return
	var tb := _raycast_tile()
	if not is_instance_valid(tb):
		return
	# Core pickaxe can dig sealed-in blocks; otherwise the open-side rule applies.
	var can_mine: bool = is_mineable(tb.grid_pos)
	if stats.get("mine_unexposed", 0.0) > 0.0 and is_solid(tb.grid_pos):
		can_mine = true
	if not can_mine:
		hud.flash("Blocked - no open side", Color8(255, 90, 90))
		return
	# Striker - Mining Frenzy: active buff = faster swings + more damage.
	var frenzy: bool = _frenzy_left > 0.0
	cooldown_left = stats["click_cooldown"] * (0.6 if frenzy else 1.0)
	hud.swing()
	_play_sfx(SFX_PICK, true)   # pickaxe strike
	_hit_count += 1
	var pat: String = stats.get("manual_pattern", "")
	var dmg := _manual_damage(tb.grid_pos)
	if frenzy:
		dmg *= 1.5
	# Crit: random, or guaranteed on every 5th hit for the Bronze pickaxe.
	var is_crit: bool = rng.randf() < stats["crit_chance"]
	if pat == "bronze" and _hit_count % 5 == 0:
		is_crit = true
	if is_crit:
		dmg *= stats["crit_damage"]
		_popup(tb.position, "CRIT!", Color8(255, 220, 80))
	# Chance to instantly break the clicked tile.
	if rng.randf() < stats["instant_chance"]:
		dmg = maxf(dmg, tb.remaining())
		_popup(tb.position, "INSTANT!", Color8(180, 240, 255))
	_apply_manual_pattern(tb.grid_pos, dmg, is_crit, stats["manual_resource_bonus"])

func _manual_damage(pos: Vector2i) -> float:
	return stats["click_damage"] + stats["deep_bonus"] * (float(pos.y) / 100.0)

# ===========================================================================
# Damage / breaking
# ===========================================================================
## Plain damage to one tile: break it if HP hits 0. No overflow/patterns — used
## by golems, machines, and the manual pattern helpers (overflow is Core-only).
func _damage_tile(pos: Vector2i, dmg: float, source: String, res_bonus: float) -> bool:
	var tb: TileBlock = blocks.get(pos)
	if not is_instance_valid(tb):
		return false
	if tb.apply_damage(dmg):
		_break_tile(pos, source, res_bonus)
		return true
	return false

# ===========================================================================
# Manual pickaxe effects — each pickaxe has one unique pattern around the click.
# ===========================================================================
const ASTRAL_CHAIN_MULT := 6.0    # Astral snake budget = click_damage * this
const SPORE_STEP := 0.02          # seconds between Spore spiral hits (chain reaction feel)
# Relic orbiting shards.
const SHARD_MAX := 12
const SHARD_ORBIT_R := 1.6        # orbit radius (tiles)
const SHARD_SPIN := 2.4           # orbit speed (rad/sec)
const SHARD_HIT_INTERVAL := 0.2   # seconds between shard damage ticks
const SHARD_DMG_FRAC := 0.5       # shard damage = 50% of click damage
const SHARD_Z := 0.6              # in front of the blocks
const SHARD_ICON: Texture2D = preload("res://assets/items/gem-emerald-shard.png")
# Resource orbs (cosmetic).
const ORB_Z := 0.8
const ORB_ABSORB_DIST := 0.55
const ORB_ACCEL := 46.0
const ORB_MAX_SPEED := 24.0
const ORB_MAX_LIVE := 140         # hard cap so big AoE breaks don't flood the screen
const ORB_SFX_THROTTLE := 0.045   # min seconds between absorb droplets
# Optional "droplet/bubble" absorb sound — drop a file here to enable it.
const ABSORB_SFX_PATH := "res://assets/sfx/absorb_1.wav"

## Damage a NON-clicked solid tile (spawns it first). Source stays "manual" so
## drop rules still apply. Returns true if it broke. Ignores 0/empty targets.
func _pat_hit(pos: Vector2i, dmg: float, res_bonus: float) -> bool:
	if dmg <= 0.0 or not is_solid(pos):
		return false
	_spawn_block(pos)
	return _damage_tile(pos, dmg, "manual", res_bonus)

## A tile the Iron splinter may catch: solid AND (exposed or already chipped).
func _is_exposed_or_damaged(pos: Vector2i) -> bool:
	if not is_solid(pos):
		return false
	if is_mineable(pos):
		return true
	var tb: TileBlock = blocks.get(pos)
	return is_instance_valid(tb) and tb.damage > 0.0

func _is_crystal_tile(pos: Vector2i) -> bool:
	var id := String(grid.get(pos, {}).get("id", ""))
	for k in ["crystal", "quartz", "gem", "prism", "geode", "obsidian", "astral", "moon"]:
		if id.contains(k):
			return true
	return false

## Route the equipped pickaxe's manual effect around the clicked tile.
func _apply_manual_pattern(pos: Vector2i, dmg: float, is_crit: bool, res_bonus: float) -> void:
	var pat: String = stats.get("manual_pattern", "")
	# How the clicked tile's overkill behaves on break.
	var mode := "none"
	if pat == "core":
		mode = "splash"          # Core: overkill always overflows to neighbours
	elif pat == "astral_snake":
		mode = "snake"           # Astral: overkill snakes toward ore
	elif is_crit:
		mode = "splash"          # any crit spills its overkill
	var broke := _break_primary(pos, dmg, res_bonus, mode)

	match pat:
		"root":
			_pat_root(pos, dmg, res_bonus)
		"iron_splinter":
			_pat_iron(pos, dmg, broke, res_bonus)
		"crystal_shatter":
			if broke:
				_pat_crystal(pos, dmg, res_bonus)
		"ember":
			if _hit_count % 3 == 0:
				_pat_ember(pos, dmg, is_crit, res_bonus)
		"spore":
			_pat_spore(pos, dmg, is_crit, res_bonus)
		"titanium":
			_pat_titanium(pos, dmg, res_bonus)

	# Relic-style cooldown refund on a manual break.
	if broke and stats["refund_amount"] > 0.0 and rng.randf() < stats["refund_chance"]:
		cooldown_left = maxf(0.0, cooldown_left - stats["click_cooldown"] * stats["refund_amount"])

## Damage the CLICKED tile; on break, route the leftover per `mode`.
func _break_primary(pos: Vector2i, dmg: float, res_bonus: float, mode: String) -> bool:
	var tb: TileBlock = blocks.get(pos)
	if not is_instance_valid(tb):
		return false
	var before := tb.remaining()
	if not tb.apply_damage(dmg):
		return false
	_break_tile(pos, "manual", res_bonus)
	var overflow := maxf(0.0, dmg - before)
	match mode:
		"splash":
			if overflow > 0.0:
				_overflow_splash(pos, overflow, "manual", res_bonus)
		"snake":
			_overflow_chain(pos, overflow + stats["click_damage"] * ASTRAL_CHAIN_MULT, "manual", res_bonus)
	return true

# Rootbound: a widening root spreads straight down (clicked tile already at 100%).
func _pat_root(pos: Vector2i, dmg: float, res_bonus: float) -> void:
	for dx in [-1, 0, 1]:
		_pat_hit(pos + Vector2i(dx, 1), dmg * 0.5, res_bonus)
	for dx in [-2, 0, 2]:
		_pat_hit(pos + Vector2i(dx, 2), dmg * 0.25, res_bonus)

# Iron: splinter to up to 4 orthogonal exposed/chipped tiles (25%, 50% if broke).
func _pat_iron(pos: Vector2i, dmg: float, broke: bool, res_bonus: float) -> void:
	var frac := 0.5 if broke else 0.25
	for d in DIRS:
		var np: Vector2i = pos + d
		if _is_exposed_or_damaged(np):
			_pat_hit(np, dmg * frac, res_bonus)

# Crystal: on break, 3 shards jump to nearby ore/exposed tiles (40%), chaining
# once (20%) if a shard shatters a crystal-type tile.
func _pat_crystal(pos: Vector2i, dmg: float, res_bonus: float) -> void:
	for t in _shard_targets(pos, 3):
		var was_crystal := _is_crystal_tile(t)
		if _pat_hit(t, dmg * 0.4, res_bonus) and was_crystal:
			for d in DIRS:
				if is_solid(t + d):
					_pat_hit(t + d, dmg * 0.2, res_bonus)
					break

## Up to `count` nearby solid tiles for shards: resources first (nearest), then
## any exposed tile.
func _shard_targets(origin: Vector2i, count: int) -> Array:
	var res_t: Array = []
	var exp_t: Array = []
	for dy in range(-3, 4):
		for dx in range(-3, 4):
			if dx == 0 and dy == 0:
				continue
			var p := origin + Vector2i(dx, dy)
			if not is_solid(p):
				continue
			if _tile_rarity(p) > 0:
				res_t.append(p)
			elif is_mineable(p):
				exp_t.append(p)
	res_t.sort_custom(func(a, b): return origin.distance_squared_to(a) < origin.distance_squared_to(b))
	var out: Array = []
	for p in res_t + exp_t:
		out.append(p)
		if out.size() >= count:
			break
	return out

# Ember: ring explosion. Center 100%, each Euclidean ring 10% weaker.
func _pat_ember(pos: Vector2i, dmg: float, is_crit: bool, res_bonus: float) -> void:
	var radius := 5 if is_crit else 3
	_popup(world_pos(pos), "BOOM!", Color8(255, 140, 50))
	for r in range(1, radius + 1):
		var frac := maxf(0.0, 1.0 - 0.10 * r)
		for np in _ring_tiles(pos, r):
			_pat_hit(np, dmg * frac, res_bonus)

# Spore: a real spiral winding outward from the epicentre, resolved as a timed
# CHAIN REACTION (one cell at a time), each ring 5% weaker. layers = max radius.
func _pat_spore(pos: Vector2i, dmg: float, is_crit: bool, res_bonus: float) -> void:
	var layers := 8 if is_crit else 5
	var seq: Array = []
	for c in _spiral_cells(pos, layers):
		var ring := int(round((c - pos).length()))
		var frac := maxf(0.0, 1.0 - 0.05 * ring)
		if frac > 0.0:
			seq.append({"pos": c, "dmg": dmg * frac})
	if not seq.is_empty():
		_sequences.append({"seq": seq, "i": 0, "cd": SPORE_STEP, "interval": SPORE_STEP, "res_bonus": res_bonus})

## Ordered cells along an Archimedean spiral out to `max_radius` (~2.5 turns).
func _spiral_cells(origin: Vector2i, max_radius: int) -> Array:
	var out: Array = []
	var seen := {}
	var theta_max := 2.5 * TAU
	var a := float(max_radius) / theta_max
	var theta := 0.0
	while theta <= theta_max:
		var r := a * theta
		var c := origin + Vector2i(int(round(cos(theta) * r)), int(round(sin(theta) * r)))
		if c != origin and not seen.has(c):
			seen[c] = true
			out.append(c)
		theta += 0.12
	return out

## Advance timed damage sequences: fire the next queued cell(s) each interval so
## an effect (the Spore spiral) resolves as a chain reaction rather than at once.
func _process_sequences(delta: float) -> void:
	if _sequences.is_empty():
		return
	var still: Array = []
	for sq in _sequences:
		sq["cd"] = float(sq["cd"]) - delta
		var guard := 0
		while float(sq["cd"]) <= 0.0 and int(sq["i"]) < sq["seq"].size() and guard < 256:
			guard += 1
			sq["cd"] = float(sq["cd"]) + float(sq["interval"])
			var step: Dictionary = sq["seq"][int(sq["i"])]
			sq["i"] = int(sq["i"]) + 1
			_pat_hit(step["pos"], step["dmg"], float(sq["res_bonus"]))
		if int(sq["i"]) < sq["seq"].size():
			still.append(sq)
	_sequences = still

# Titanium: drill 7 tiles down (-5%/tile). Even depths branch sideways
# (-15%/tile), tapering to a drill-bit point: the first even depth reaches 5
# tiles each side, each subsequent even depth 1 fewer (5, 4, 3...).
func _pat_titanium(pos: Vector2i, dmg: float, res_bonus: float) -> void:
	for d in range(1, 8):
		var down_frac := maxf(0.0, 1.0 - 0.05 * d)
		_pat_hit(pos + Vector2i(0, d), dmg * down_frac, res_bonus)
		if d % 2 == 0:
			var width := maxi(0, 5 - (d / 2 - 1))   # d=2->5, d=4->4, d=6->3
			for h in range(1, width + 1):
				var hf := down_frac * maxf(0.0, 1.0 - 0.15 * h)
				_pat_hit(pos + Vector2i(-h, d), dmg * hf, res_bonus)
				_pat_hit(pos + Vector2i(h, d), dmg * hf, res_bonus)

## Radial overflow blast: leftover damage expands outward from the origin one
## circular LAYER at a time. If the budget can break the whole layer, that layer
## shatters and the remaining damage (budget - layer's total HP) rolls out to the
## next layer; this repeats outward until a layer is too tough to fully break, at
## which point the last of the budget is spread across it and the blast stops.
func _overflow_splash(origin: Vector2i, overflow: float, source: String, res_bonus: float) -> void:
	var budget := overflow
	var radius := 1
	while budget > 0.0 and radius <= OVERFLOW_MAX_RADIUS:
		var ring := _ring_tiles(origin, radius)
		if not ring.is_empty():
			# Total HP needed to break this whole layer.
			var layer_hp := 0.0
			for np in ring:
				_spawn_block(np)
				var tb: TileBlock = blocks.get(np)
				if is_instance_valid(tb):
					layer_hp += tb.remaining()
			if budget >= layer_hp:
				# Enough to shatter the entire layer; the remainder rolls onward.
				for np in ring:
					var tb2: TileBlock = blocks.get(np)
					if is_instance_valid(tb2):
						tb2.apply_damage(tb2.remaining())
						_break_tile(np, source, res_bonus)
				budget -= layer_hp
			else:
				# Can't break the whole layer -> spend what's left here, then stop.
				var share := budget / float(ring.size())
				for np in ring:
					var tb3: TileBlock = blocks.get(np)
					if is_instance_valid(tb3) and tb3.apply_damage(share):
						_break_tile(np, source, res_bonus)
				budget = 0.0
		radius += 1

## Solid tiles whose distance from origin rounds to `radius` -> one circular ring.
func _ring_tiles(origin: Vector2i, radius: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for dy in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			if dx == 0 and dy == 0:
				continue
			if int(round(sqrt(float(dx * dx + dy * dy)))) != radius:
				continue
			var np := origin + Vector2i(dx, dy)
			if is_solid(np):
				out.append(np)
	return out

# --- Snaking chain reaction (Core pickaxe's on-break effect) ---
## Queues a damage-overflow chain that propagates to a random adjacent solid tile
## one hop per OVERFLOW_STAGGER seconds (advanced in _process_chains), so it reads
## as a snake travelling through the rock rather than an instant splash.
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

## Rarity weight of a solid tile for chain-seeking: 2 = rare resource, 1 = common
## resource, 0 = filler/barrier. Reads the grid directly (no spawned block needed).
func _tile_rarity(pos: Vector2i) -> int:
	var t: Dictionary = grid.get(pos, {})
	if t.get("type", "filler") != "resource":
		return 0
	return 2 if String(t.get("rarity", "common")) == "rare" else 1

## Nearest resource tile to `from` within CHAIN_SEEK_RADIUS. Prioritises vicinity
## (smallest Manhattan distance); rarity only breaks ties. Returns null if none.
func _nearest_resource(from: Vector2i):
	var best = null
	var best_dist := 1 << 30
	var best_rar := -1
	for dy in range(-CHAIN_SEEK_RADIUS, CHAIN_SEEK_RADIUS + 1):
		for dx in range(-CHAIN_SEEK_RADIUS, CHAIN_SEEK_RADIUS + 1):
			var p := from + Vector2i(dx, dy)
			var rar := _tile_rarity(p)
			if rar == 0 or not is_solid(p):
				continue
			var dist: int = absi(dx) + absi(dy)
			if dist < best_dist or (dist == best_dist and rar > best_rar):
				best_dist = dist
				best_rar = rar
				best = p
	return best

## Pick the chain's next hop: steer toward the nearest resource tile (vicinity
## first, rarity as tie-break); if none is in range, snake through a random
## adjacent solid tile. Returns null when boxed in.
func _pick_chain_next(current: Vector2i):
	var cands: Array[Vector2i] = []
	for d in DIRS:
		var np: Vector2i = current + d
		if is_solid(np):
			cands.append(np)
	if cands.is_empty():
		return null
	var goal = _nearest_resource(current)
	if goal == null:
		return cands[rng.randi_range(0, cands.size() - 1)]
	# Move to the neighbour nearest the goal; prefer a resource cell, then rarity.
	var best: Vector2i = cands[0]
	var best_dist := 1 << 30
	var best_rar := -1
	for np in cands:
		var dist: int = absi(np.x - goal.x) + absi(np.y - goal.y)
		var rar := _tile_rarity(np)
		if dist < best_dist or (dist == best_dist and rar > best_rar):
			best_dist = dist
			best_rar = rar
			best = np
	return best

## One hop of a chain: bleed the leftover damage into the chosen adjacent solid
## tile, breaking it (and continuing) or partially damaging it (and stopping).
func _advance_chain(ch: Dictionary) -> void:
	var target = _pick_chain_next(ch["current"])
	if target == null:
		ch["overflow"] = 0.0                          # dead end -> finished
		return
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
	_play_sfx(SFX_BREAK, true, -12.0)   # block shatters (muted/subtle)

	tiles_mined += 1
	if pos.y > frontier:
		frontier = pos.y
		_ensure_world()
	GameState.max_depth = maxi(GameState.max_depth, pos.y)

	# Relic pickaxe: gain an orbiting shard on each tile you break (by hand or shard).
	if stats.get("manual_pattern", "") == "relic_orbit" and (source == "manual" or source == "shard") and _orbit_shards < SHARD_MAX:
		_orbit_shards += 1

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
				_spawn_orbs(world_pos(pos), GameData.resource_color(res_id), clampi(amount, 1, 6))
		rare_found += 1
		if label != "":
			_popup(world_pos(pos), label, tile.get("color", Color.WHITE))
		# Striker - Mining Frenzy: breaking a resource tile by hand refreshes the buff.
		if source == "manual" and stats.get("manual_frenzy", 0.0) > 0.0:
			var was_active := _frenzy_left > 0.0
			_frenzy_left = 4.0
			if not was_active:
				hud.flash("MINING FRENZY!", Color8(255, 200, 90))
	else:
		# Filler yields Rubble -> crushed into Coins at the surface. Deeper biomes
		# drop a higher rubble tier (Rubble I..X) worth more per unit at the Crusher.
		var amt := maxi(1, int(round(1.0 * mult)))
		var rid := GameData.rubble_id_for_biome(GameData.biome_index_for_row(pos.y))
		GameState.add_resource(rid, amt)
		run_resources[rid] = int(run_resources.get(rid, 0)) + amt

	# Any tile (filler / resource / barrier) has a chance to drop loose coins.
	# Amount scales with depth so it stays relevant. This is direct coin income
	# on top of the Crusher, so mining pays out from the very first run.
	if rng.randf() < COIN_DROP_CHANCE:
		var bi := GameData.biome_index_for_row(pos.y)
		var coins := rng.randi_range(1, 3) + bi
		GameState.add_money(coins)
		run_money += coins
		_popup(world_pos(pos), "+%d coins" % coins, Color8(255, 210, 90))
		_spawn_orbs(world_pos(pos), Color8(255, 210, 90), 2)

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
	# Stonewarden's Endless Crew raises the cap with extra temporary golems.
	var deepest_biome: int = GameData.biome_index_for_row(GameState.max_depth)
	var max_active: int = deepest_biome + 1
	var owned_tiers: Array = []
	for tier in GameState.golems:
		for i in range(int(GameState.golems[tier])):
			owned_tiers.append(int(tier))
	owned_tiers.sort()
	owned_tiers.reverse()                       # strongest tier first
	if owned_tiers.size() > max_active:
		owned_tiers.resize(max_active)
	for tier in owned_tiers:
		_add_golem_worker(tier)
	# Stonewarden - Endless Crew: bonus temporary golems scaled to the deepest biome.
	var bonus: int = int(stats.get("golem_active_bonus", 0.0))
	for i in range(bonus):
		_add_golem_worker(clampi(deepest_biome + 1, 1, GameData.GOLEMS.size()))

	# Basic Drills (flying machines).
	var dm: Dictionary = GameData.MACHINES["buy_drill"]
	var d_int: float = maxf(0.3, float(dm["base_interval"]) * stats["machine_speed"])
	var d_dmg: float = (float(dm["base_damage"]) + stats["machine_damage"]) * stats["machine_damage_mult"] * stats.get("all_damage_mult", 1.0)
	for i in range(int(stats["drill_count"])):
		workers.append(_make_worker("drill", Color8(255, 150, 60), d_int, d_dmg, stats["machine_resource_bonus"], {}))

## Build one golem worker of the given tier, folding in Stonewarden spec skills
## (global resource-preference + doubled unique-effect chances).
func _add_golem_worker(tier: int) -> void:
	var g := GameState.golem_data(tier)
	var eff: Dictionary = g.get("effect", {})
	var dmg: float = (float(g["base_damage"]) + stats["ai_damage"]) * stats["ai_damage_mult"] * stats.get("all_damage_mult", 1.0)
	var interval: float = maxf(0.4, float(g["interval"]) * stats["ai_interval"])
	var rbon: float = stats["ai_resource_bonus"] + float(eff.get("res_bonus", 0.0))
	var col := Color.from_hsv(lerpf(0.33, 0.55, float(tier - 1) / 9.0), 0.6, 0.95)
	var umult: float = stats.get("golem_unique_mult", 1.0)
	var sheet: Texture2D = ROOTBOUND_SHEET   # placeholder: all golem tiers use the Rootbound sprite for now
	workers.append(_make_worker("golem", col, interval, dmg, rbon, {
		"prefer_resource": bool(eff.get("prefer_resource", false)) or stats.get("golem_prefer_resource", 0.0) > 0.0,
		"double_hit": clampf(float(eff.get("double_hit_chance", 0.0)) * umult, 0.0, 1.0),
		"splash_chance": clampf(float(eff.get("splash_chance", 0.0)) * umult, 0.0, 1.0),
		"splash_damage": float(eff.get("splash_damage", 0.0)),
	}, sheet))

func _make_worker(kind: String, color: Color, interval: float, damage: float, res_bonus: float, effect: Dictionary, sheet: Texture2D = null) -> Dictionary:
	var node := MeshInstance3D.new()
	var spr: Sprite3D = null
	if sheet != null:
		# Animated sprite golem: leave the mesh empty so only the sprite renders.
		spr = Sprite3D.new()
		spr.texture = sheet
		spr.hframes = GOLEM_SHEET_HFRAMES
		spr.vframes = GOLEM_SHEET_VFRAMES
		spr.frame = 0
		spr.pixel_size = GOLEM_SPRITE_PIXEL_SIZE
		spr.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST   # crisp pixel art
		# Feet fill the frame bottom; drop the (centered) sprite so they plant on the
		# top of the solid block below the worker (which sits ~0.5 under the node).
		var half_h := GOLEM_SPRITE_PIXEL_SIZE * 64.0 * 0.5
		spr.position = Vector3(0, -0.5 + half_h - 0.03, 0)
		node.add_child(spr)
	else:
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
	return {"node": node, "sprite": spr, "anim_t": randf_range(0.0, float(GOLEM_SHEET_FRAMES)),
		"target": null, "cd": interval * randf_range(0.2, 1.0),
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
		_animate_sprite(w, delta)

## Advance a sprite-golem's frame animation. While mining, frames are driven by
## the cooldown cycle so the last 2 (impact) frames land right on the hit; while
## walking/idle it loops the earlier wind-up frames only.
func _animate_sprite(w: Dictionary, delta: float) -> void:
	var spr = w.get("sprite")
	if spr == null or not is_instance_valid(spr):
		return
	if w.get("mining", false):
		var interval: float = maxf(0.001, float(w["interval"]))
		var progress := clampf(1.0 - float(w["cd"]) / interval, 0.0, 1.0)
		spr.frame = clampi(int(progress * GOLEM_SHEET_FRAMES), 0, GOLEM_SHEET_FRAMES - 1)
	else:
		var loop_frames := GOLEM_SHEET_FRAMES - 2   # reserve the last 2 for impacts
		w["anim_t"] = fmod(float(w["anim_t"]) + delta * GOLEM_ANIM_FPS, float(loop_frames))
		spr.frame = int(w["anim_t"])

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
	var spr = w.get("sprite")
	if spr != null and is_instance_valid(spr) and dir != 0:
		spr.flip_h = dir < 0

	# The block this golem will actually mine (adjacent + reachable) -> claim it.
	var dig = _pick_miner_dig(w, col, row, dir)
	w["target"] = dig

	# Walk toward the target through open air; a wall in the way is mined, not passed.
	if grounded and dir != 0 and is_air(Vector2i(col + dir, row)):
		pos.x = move_toward(pos.x, float(col + dir) * BLOCK, MINER_WALK * delta)
	node.global_position = Vector3(pos.x, pos.y, WORKER_Z)

	# Mine when grounded and something is adjacent.
	w["mining"] = grounded and dig != null
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
		_damage_tile(target, w["damage"] + _machine_deep_dmg(int(target.y)), "drill", w["res_bonus"])

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
	# Engineer - Fuel Mastery: stronger boost + fuel burns slower (lasts longer).
	var fuel_mult := 1.0
	var mastery: bool = stats.get("fuel_bonus", 0.0) > 0.0
	var fl := int(stats["fuel_level"])
	if fl > 0 and _has_fuel():
		var per_level := 0.12 if mastery else 0.08
		fuel_mult = maxf(0.3 if mastery else 0.4, 1.0 - per_level * fl)
		_fuel_timer += delta
		var burn_period := FUEL_BURN * 2.0 if mastery else FUEL_BURN
		if _fuel_timer >= burn_period:
			_fuel_timer -= burn_period
			_burn_fuel()
	var mmult: float = stats["machine_damage_mult"] * stats.get("all_damage_mult", 1.0)
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

## Engineer - Deep Bore Protocol: extra machine damage that scales with depth.
func _machine_deep_dmg(row: int) -> float:
	return stats.get("machine_deep_bonus", 0.0) * (float(row) / 100.0) * stats["machine_damage_mult"]

func _fire_machine(mac: Dictionary, mdmg: float, mmult: float) -> void:
	var base_dmg: float = (mac["base_damage"] + mdmg) * mmult
	var rbon: float = stats["machine_resource_bonus"]   # Engineer - Auto-Sorter
	match mac["kind"]:
		"hammer":
			var t = _random_exposed()
			if t == null:
				return
			mac["node"].global_position = world_pos(t) + Vector3(0, 0, WORKER_Z)
			_damage_tile(t, base_dmg + _machine_deep_dmg(int(t.y)), "machine", rbon)
			_overflow_splash(t, (mac["splash"] + mdmg) * mmult, "machine", rbon)   # area slam
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
					_damage_tile(p, base_dmg + _machine_deep_dmg(r), "machine", rbon)
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
			_damage_tile(target, base_dmg + _machine_deep_dmg(int(target.y)), "machine", rbon)

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
# Pause
# ===========================================================================
func _toggle_pause() -> void:
	if _paused:
		_resume()
	else:
		_pause()

func _pause() -> void:
	_paused = true
	_mining_held = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE   # show a normal pointer for the menu
	_pause_menu = PauseMenu.new()
	add_child(_pause_menu)
	_pause_menu.resume_pressed.connect(_resume)
	_pause_menu.end_pressed.connect(_end_run_early)

func _resume() -> void:
	_paused = false
	_close_pause_menu()
	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN    # back to the software pickaxe cursor

func _end_run_early() -> void:
	_paused = false
	_close_pause_menu()
	_end_run()                                    # finalize now; surface restores the cursor

func _close_pause_menu() -> void:
	if is_instance_valid(_pause_menu):
		_pause_menu.queue_free()
	_pause_menu = null

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
	# Show a recap over the frozen mine; only return to the surface on RESURFACE.
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var recap := RunRecap.new()
	recap.summary = summary
	add_child(recap)
	recap.resurface_pressed.connect(func(): run_finished.emit(summary))
