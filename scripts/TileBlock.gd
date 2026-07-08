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

# Cube meshes keyed by edge length. Godot's BoxMesh unwraps its texture into a
# 3x2 atlas (each face shows only 1/6 of the image -> looks "zoomed"). We reuse
# BoxMesh's geometry but rewrite the UVs so the FULL texture maps onto every face.
static var _cube_cache := {}

static func _cube_mesh(sz: float) -> ArrayMesh:
	var key := snappedf(sz, 0.0001)
	if _cube_cache.has(key):
		return _cube_cache[key]
	var src := BoxMesh.new()
	src.size = Vector3(sz, sz, sz)
	var arr: Array = src.surface_get_arrays(0)
	var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var norms: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
	var uvs := PackedVector2Array()
	uvs.resize(verts.size())
	for i in verts.size():
		var q := verts[i] / sz          # each component in [-0.5, 0.5]
		var n := norms[i]
		var uv := Vector2.ZERO
		if absf(n.z) > 0.5:             # front / back
			uv = Vector2(0.5 + q.x * signf(n.z), 0.5 - q.y)
		elif absf(n.x) > 0.5:           # right / left
			uv = Vector2(0.5 - q.z * signf(n.x), 0.5 - q.y)
		else:                           # top / bottom
			uv = Vector2(0.5 + q.x, 0.5 + q.z * signf(n.y))
		uvs[i] = uv
	var out := []
	out.resize(Mesh.ARRAY_MAX)
	out[Mesh.ARRAY_VERTEX] = verts
	out[Mesh.ARRAY_NORMAL] = norms
	out[Mesh.ARRAY_TANGENT] = arr[Mesh.ARRAY_TANGENT]
	out[Mesh.ARRAY_TEX_UV] = uvs
	out[Mesh.ARRAY_INDEX] = arr[Mesh.ARRAY_INDEX]
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, out)
	_cube_cache[key] = am
	return am

func setup(pos: Vector2i, tile_data: Dictionary, block_size: float) -> void:
	grid_pos = pos
	tile = tile_data
	max_health = float(tile.get("max_health", 3))
	damage = 0.0
	_base_color = tile.get("color", Color.GRAY)
	_glow = bool(tile.get("glow", false))

	var s := block_size * SIZE

	# Main cube mesh + unique material. Custom cube maps the full texture per face.
	_mesh = MeshInstance3D.new()
	_mesh.mesh = _cube_mesh(s)
	_mat = StandardMaterial3D.new()
	_mat.roughness = 0.9
	_mat.metallic = 0.0

	var tex: Texture2D = GameData.get_tile_texture(tile.get("id", ""))
	if tex != null:
		# Full material texture on every cube face. White tint so damage-darkening
		# multiplies the texture instead of replacing it.
		_base_color = Color.WHITE
		_mat.albedo_texture = tex
		_mat.albedo_color = Color.WHITE
	else:
		# Fallback: flat colour cube.
		_mat.albedo_color = _base_color
	_mesh.material_override = _mat
	add_child(_mesh)

	# Hover outline shell (shows only when hovered). A thin, semi-transparent
	# silhouette rim rather than a bold solid shell -> subtle highlight.
	_outline = MeshInstance3D.new()
	var om := BoxMesh.new()
	om.size = Vector3(s * 1.04, s * 1.04, s * 1.04)
	_outline.mesh = om
	var omat := StandardMaterial3D.new()
	omat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	omat.cull_mode = BaseMaterial3D.CULL_FRONT     # draw back faces -> silhouette
	omat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	omat.albedo_color = Color(0.45, 1.0, 0.55, 0.28)
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
	# No persistent glow — just clear the transient hit-flash emission.
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
		omat.albedo_color = Color(1.0, 0.4, 0.4, 0.30) if blocked else Color(0.45, 1.0, 0.55, 0.28)
