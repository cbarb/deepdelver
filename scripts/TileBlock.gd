class_name TileBlock
extends StaticBody3D
## A single mineable 3D block. Holds its grid position + tile data, renders a
## chunky cube, and handles hover highlight + damage/break feedback.

var grid_pos: Vector2i
var tile: Dictionary          # from MineGenerator.make_tile()
var max_health: float = 3.0
var damage: float = 0.0

var _mesh: MeshInstance3D
var _outline: MeshInstance3D
var _mat: StandardMaterial3D
var _base_color: Color
var _glow: bool = false

const SIZE := 0.92

func setup(pos: Vector2i, tile_data: Dictionary, block_size: float) -> void:
	grid_pos = pos
	tile = tile_data
	max_health = float(tile.get("max_health", 3))
	damage = 0.0
	_base_color = tile.get("color", Color.GRAY)
	_glow = bool(tile.get("glow", false))

	var s := block_size * SIZE

	# Main cube mesh + unique material.
	_mesh = MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(s, s, s)
	_mesh.mesh = bm
	_mat = StandardMaterial3D.new()
	_mat.roughness = 0.9
	_mat.metallic = 0.0

	var tex: Texture2D = GameData.get_tile_texture(tile.get("id", ""))
	if tex != null:
		# Full material texture on every cube face (default box UVs). White tint
		# so damage-darkening multiplies the texture instead of replacing it.
		_base_color = Color.WHITE
		_mat.albedo_texture = tex
		_mat.albedo_color = Color.WHITE
		if _glow:
			_mat.emission_enabled = true
			_mat.emission_texture = tex
			_mat.emission = Color.WHITE
			_mat.emission_energy_multiplier = 0.5
	else:
		# Fallback: flat colour cube.
		_mat.albedo_color = _base_color
		if _glow:
			_mat.emission_enabled = true
			_mat.emission = _base_color
			_mat.emission_energy_multiplier = 0.9
	_mesh.material_override = _mat
	add_child(_mesh)

	# Hover outline shell (shows only when hovered).
	_outline = MeshInstance3D.new()
	var om := BoxMesh.new()
	om.size = Vector3(s * 1.08, s * 1.08, s * 1.08)
	_outline.mesh = om
	var omat := StandardMaterial3D.new()
	omat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	omat.cull_mode = BaseMaterial3D.CULL_FRONT     # draw back faces -> silhouette
	omat.albedo_color = Color(0.4, 1.0, 0.5)
	_outline.material_override = omat
	_outline.visible = false
	add_child(_outline)

	# Collision for mouse raycast.
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(s, s, s)
	col.shape = shape
	add_child(col)

func remaining() -> float:
	return max_health - damage

func health_fraction() -> float:
	return clampf(remaining() / max_health, 0.0, 1.0)

## Returns true if this hit broke the block.
func apply_damage(amount: float) -> bool:
	damage += amount
	_refresh_damage_visual()
	_hit_pop()
	return remaining() <= 0.0

func _refresh_damage_visual() -> void:
	var frac := health_fraction()                 # 1 = full, 0 = broken
	# Darken + shrink slightly as it chips away.
	_mat.albedo_color = _base_color * (0.45 + 0.55 * frac)
	var s := (0.82 + 0.18 * frac)
	_mesh.scale = Vector3(s, s, s)

func _hit_pop() -> void:
	var t := create_tween()
	t.tween_property(_mesh, "scale", _mesh.scale * 1.12, 0.04)
	t.tween_property(_mesh, "scale", _mesh.scale, 0.08)
	# brief white flash
	_mat.emission_enabled = true
	_mat.emission = Color(1, 1, 1)
	_mat.emission_energy_multiplier = 1.4
	var t2 := create_tween()
	t2.tween_interval(0.05)
	t2.tween_callback(_restore_emission)

func _restore_emission() -> void:
	if not is_instance_valid(self):
		return
	if _glow:
		_mat.emission = _base_color
		_mat.emission_energy_multiplier = 0.9
	else:
		_mat.emission_enabled = false

## Ore Scanner ping: a small bright marker floating above a resource tile.
func set_scanned(on: bool) -> void:
	if not on:
		return
	var marker := MeshInstance3D.new()
	var mm := BoxMesh.new()
	mm.size = Vector3(0.2, 0.2, 0.2)
	marker.mesh = mm
	marker.rotation_degrees = Vector3(45, 45, 0)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.4, 1.0, 1.0)
	marker.material_override = mat
	marker.position = Vector3(0, 0.62, 0.5)
	add_child(marker)

func set_highlight(on: bool, blocked: bool = false) -> void:
	_outline.visible = on
	if on:
		var omat: StandardMaterial3D = _outline.material_override
		omat.albedo_color = Color(1.0, 0.3, 0.3) if blocked else Color(0.4, 1.0, 0.5)
