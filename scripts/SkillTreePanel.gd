class_name SkillTreePanel
extends Control
## Full-screen radial skill tree. Three pie sections (Manual / Golem / Machinery)
## radiate from the centre. Nodes are drawn (not Buttons) and hit-tested, so 100+
## fit comfortably. Left-drag pans, wheel zooms, click a node to spend a point.

signal closed

const SECTION_COLOR := {
	"Manual": Color8(255, 150, 90),
	"Golem": Color8(120, 220, 140),
	"Machinery": Color8(120, 170, 255),
}
const RING0 := 78.0
const RING_STEP := 48.0
const SIZE_RADIUS := {"small": 11.0, "medium": 15.0, "large": 19.0, "capstone": 27.0}

var _nodes := {}          # id -> {rel: Vector2, parent_rel: Vector2, size, section}
var _pan := Vector2.ZERO
var _zoom := 1.0
var _hovered := ""
var _dragging := false
var _drag_moved := 0.0

var _points_lbl: Label
var _info_lbl: RichTextLabel
var _fitted := false

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_precompute_nodes()
	_build_overlay()
	_refresh_points()

func _precompute_nodes() -> void:
	for id in GameData.SKILLS:
		var n: Dictionary = GameData.SKILLS[id]
		var radius: float = RING0 + (int(n["ring"]) - 1) * RING_STEP
		var a: float = deg_to_rad(float(n["angle_deg"]))
		var rel := Vector2(cos(a), sin(a)) * radius
		var parent_rel := Vector2.ZERO
		var req: String = n.get("requires", "")
		if req != "" and GameData.SKILLS.has(req):
			var pn: Dictionary = GameData.SKILLS[req]
			var pr: float = RING0 + (int(pn["ring"]) - 1) * RING_STEP
			var pa: float = deg_to_rad(float(pn["angle_deg"]))
			parent_rel = Vector2(cos(pa), sin(pa)) * pr
		_nodes[id] = {"rel": rel, "parent_rel": parent_rel,
			"size": n["size"], "section": n["section"]}

func _build_overlay() -> void:
	# NOTE: the dark background is painted in _draw() (a node draws before its
	# children, so a ColorRect child would cover the tree).

	# Header: available points + close
	var top := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0.5)
	sb.set_content_margin_all(10)
	top.add_theme_stylebox_override("panel", sb)
	add_child(top)
	top.position = Vector2(14, 14)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 20)
	top.add_child(hb)
	_points_lbl = Label.new()
	_points_lbl.add_theme_font_size_override("font_size", 22)
	hb.add_child(_points_lbl)
	var close_btn := Button.new()
	close_btn.text = "Close"
	close_btn.pressed.connect(func(): closed.emit())
	hb.add_child(close_btn)

	var hint := Label.new()
	hint.text = "Drag to pan  ·  Wheel to zoom  ·  Click a node to spend a point"
	hint.add_theme_font_size_override("font_size", 13)
	hint.add_theme_color_override("font_color", Color8(160, 165, 180))
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(hint)
	hint.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP, Control.PRESET_MODE_KEEP_SIZE, 16)

	# Info box (bottom-left)
	var info := PanelContainer.new()
	var sb2 := StyleBoxFlat.new()
	sb2.bg_color = Color(0, 0, 0, 0.6)
	sb2.set_content_margin_all(12)
	sb2.set_corner_radius_all(8)
	info.add_theme_stylebox_override("panel", sb2)
	info.custom_minimum_size = Vector2(340, 0)
	info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(info)
	info.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT, Control.PRESET_MODE_KEEP_SIZE, 14)
	_info_lbl = RichTextLabel.new()
	_info_lbl.bbcode_enabled = true
	_info_lbl.fit_content = true
	_info_lbl.custom_minimum_size = Vector2(316, 0)
	_info_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info.add_child(_info_lbl)
	_update_info()

func _refresh_points() -> void:
	_points_lbl.text = "Skill Points: %d   (Level %d)" % [GameState.skill_points_available(), GameState.get_level()]

# --- drawing ---
func _view_center() -> Vector2:
	return size * 0.5 + _pan

func _screen_pos(rel: Vector2) -> Vector2:
	return _view_center() + rel * _zoom

func _draw() -> void:
	# Opaque background (painted here so it sits UNDER the tree, not over it).
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.05, 0.05, 0.08))
	# One-time auto-fit so the whole tree is visible on any window size.
	if not _fitted and size.y > 1.0:
		var max_r := RING0 + 8.0 * RING_STEP + 40.0
		_zoom = clampf(minf(size.x, size.y) * 0.46 / max_r, 0.4, 1.3)
		_fitted = true
	var c := _view_center()
	# connecting lines
	for id in _nodes:
		var n: Dictionary = _nodes[id]
		var a := _screen_pos(n["rel"])
		var b := c if n["parent_rel"] == Vector2.ZERO else _screen_pos(n["parent_rel"])
		var owned := GameState.skill_level(id) > 0
		var lc := Color(1, 1, 1, 0.30) if owned else Color(1, 1, 1, 0.12)
		draw_line(b, a, lc, 2.0 * _zoom)
	# centre hub
	draw_circle(c, 16.0 * _zoom, Color8(230, 230, 240))
	# nodes
	for id in _nodes:
		var n: Dictionary = _nodes[id]
		var p := _screen_pos(n["rel"])
		var rad: float = SIZE_RADIUS[n["size"]] * _zoom
		var col := _node_color(id, n["section"])
		draw_circle(p, rad, col)
		if id == _hovered:
			draw_arc(p, rad + 3.0 * _zoom, 0, TAU, 24, Color.WHITE, 2.0 * _zoom)
	# section labels
	var font := ThemeDB.fallback_font
	for si in range(GameData.SKILL_PATHS.size()):
		var section: String = GameData.SKILL_PATHS[si]
		var a := deg_to_rad(-90.0 + si * 120.0)
		var lp := c + Vector2(cos(a), sin(a)) * (RING0 + 8.5 * RING_STEP) * _zoom
		draw_string(font, lp - Vector2(40, 0), section, HORIZONTAL_ALIGNMENT_CENTER, 90, 20, SECTION_COLOR[section])

func _node_color(id: String, section: String) -> Color:
	var base: Color = SECTION_COLOR[section]
	var lvl := GameState.skill_level(id)
	if GameState.is_skill_maxed(id):
		return base.lightened(0.35)
	if lvl > 0:
		return base
	if GameState.skill_unlocked(id):
		return base.darkened(0.15)     # available, clearly lit
	return Color8(78, 82, 98)          # locked (visible grey, not near-black)

# --- interaction ---
func _hit_test(mouse: Vector2) -> String:
	var best := ""
	var best_d := INF
	for id in _nodes:
		var p := _screen_pos(_nodes[id]["rel"])
		var rad: float = SIZE_RADIUS[_nodes[id]["size"]] * _zoom + 4.0
		var d := mouse.distance_to(p)
		if d <= rad and d < best_d:
			best_d = d
			best = id
	return best

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		match event.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				if event.pressed:
					_zoom = clampf(_zoom * 1.1, 0.5, 2.2)
					queue_redraw()
			MOUSE_BUTTON_WHEEL_DOWN:
				if event.pressed:
					_zoom = clampf(_zoom / 1.1, 0.5, 2.2)
					queue_redraw()
			MOUSE_BUTTON_LEFT:
				if event.pressed:
					_dragging = true
					_drag_moved = 0.0
				else:
					_dragging = false
					if _drag_moved < 6.0 and _hovered != "":
						if GameState.buy_skill(_hovered):
							_refresh_points()
							_update_info()
							queue_redraw()
	elif event is InputEventMouseMotion:
		if _dragging:
			_pan += event.relative
			_drag_moved += event.relative.length()
		var h := _hit_test(event.position)
		if h != _hovered:
			_hovered = h
			_update_info()
		queue_redraw()

func _update_info() -> void:
	if _hovered == "" or not GameData.SKILLS.has(_hovered):
		_info_lbl.text = "[color=#aab]Hover a node for details.[/color]"
		return
	var n: Dictionary = GameData.SKILLS[_hovered]
	var lvl := GameState.skill_level(_hovered)
	var maxl := int(n["max_level"])
	var col: Color = SECTION_COLOR[n["section"]]
	var state := ""
	if GameState.is_skill_maxed(_hovered):
		state = "[color=#8f8]MAXED[/color]"
	elif not GameState.skill_unlocked(_hovered):
		state = "[color=#f88]LOCKED (needs prior node)[/color]"
	elif GameState.skill_points_available() >= int(n["cost"]):
		state = "[color=#ff6]Click to buy[/color]"
	else:
		state = "[color=#f88]Not enough points[/color]"
	_info_lbl.text = "[b][color=#%s]%s[/color][/b]  (%s)\n%s\nLevel %d / %d   ·   Cost: %d pt\n%s" % [
		col.to_html(false), n["name"], n["size"], n["desc"], lvl, maxl, int(n["cost"]), state]
