class_name SkillTreePanel
extends Control
## Full-screen radial skill tree. Three fan sections (Striker / Stonewarden /
## Engineer) radiate from a central hub. Nodes are custom-DRAWN octagons (not
## Buttons) and hit-tested, so 100+ fit comfortably. Left-drag pans, wheel zooms,
## left-click a node to buy, right-click to refund. Behaviour is unchanged from
## the original; only the presentation was overhauled.

signal closed

var _pixel_font: Font = load("res://assets/fonts/VT323/VT323-Regular.ttf")
var _header_font: Font = load("res://assets/fonts/Press_Start_2P/PressStart2P-Regular.ttf")

# Section identity: internal key -> {color, display label}. Colors tuned to the
# forge/gem palette (amber / emerald / steel).
const SECTION_COLOR := {
	"Manual": Color8(232, 156, 62),
	"Golem": Color8(122, 200, 96),
	"Machinery": Color8(96, 166, 224),
}
const DISPLAY_NAME := {
	"Manual": "STRIKER",
	"Golem": "STONEWARDEN",
	"Machinery": "ENGINEER",
}
const RING0 := 82.0
const RING_STEP := 50.0
const SIZE_RADIUS := {"small": 13.0, "medium": 17.0, "large": 22.0, "capstone": 30.0}

# --- panel styling palette ---
const C_BAR_BG := Color8(26, 22, 18)
const C_BAR_BORDER := Color8(150, 110, 50)
const C_CHIP_BG := Color8(17, 14, 10)
const C_AMBER := Color8(220, 170, 78)
const C_TEXT := Color8(226, 212, 186)
const C_MUTED := Color8(150, 140, 120)

var _nodes := {}          # id -> {rel: Vector2, parent_rel: Vector2, size, section}
var _pan := Vector2.ZERO
var _zoom := 1.0
var _hovered := ""
var _dragging := false
var _drag_moved := 0.0

var _pts_lbl: Label
var _coins_lbl: Label
var _level_lbl: Label
var _tip_panel: PanelContainer      # floating tooltip that follows the cursor
var _tip_lbl: RichTextLabel
var _fitted := false

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_precompute_nodes()
	_build_overlay()
	_refresh_points()

func _precompute_nodes() -> void:
	for id in GameData.SKILLS:
		if id == "heart":
			continue   # the Heart is drawn as the central hub, not a radial node
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

# ===========================================================================
# Overlay (header bar + tooltip). Drawn OVER the tree (children paint last).
# ===========================================================================
func _sb(bg: Color, border: Color, bw: int, margin: int) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_border_width_all(bw)
	s.border_color = border
	s.set_corner_radius_all(0)
	s.anti_aliasing = false
	s.set_content_margin_all(margin)
	return s

func _hlbl(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	if _header_font != null:
		l.add_theme_font_override("font", _header_font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return l

## A "LABEL  value" chip for the header bar.
func _chip(label: String, value_color: Color) -> Array:
	var chip := PanelContainer.new()
	chip.add_theme_stylebox_override("panel", _sb(C_CHIP_BG, C_BAR_BORDER.darkened(0.2), 1, 8))
	chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	chip.add_child(row)
	row.add_child(_hlbl(label, 12, C_MUTED))
	var val := _hlbl("0", 14, value_color)
	row.add_child(val)
	return [chip, val]

func _build_overlay() -> void:
	# --- top bar ---
	var bar := PanelContainer.new()
	bar.add_theme_stylebox_override("panel", _sb(C_BAR_BG, C_BAR_BORDER, 2, 10))
	add_child(bar)
	bar.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 12)
	bar.add_child(hb)

	var pts := _chip("SKILL POINTS", C_AMBER)
	hb.add_child(pts[0])
	_pts_lbl = pts[1]
	var coins := _chip("COINS", C_AMBER)
	hb.add_child(coins[0])
	_coins_lbl = coins[1]

	var spL := Control.new()
	spL.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(spL)

	# Centered LEVEL banner.
	var banner := PanelContainer.new()
	banner.add_theme_stylebox_override("panel", _sb(C_CHIP_BG, C_BAR_BORDER, 2, 8))
	banner.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var bv := VBoxContainer.new()
	bv.alignment = BoxContainer.ALIGNMENT_CENTER
	banner.add_child(bv)
	var lv_cap := _hlbl("LEVEL", 10, C_MUTED)
	lv_cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bv.add_child(lv_cap)
	_level_lbl = _hlbl("1", 20, C_TEXT)
	_level_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bv.add_child(_level_lbl)
	hb.add_child(banner)

	var spR := Control.new()
	spR.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(spR)

	var close_btn := Button.new()
	close_btn.text = "CLOSE"
	close_btn.focus_mode = Control.FOCUS_NONE
	if _header_font != null:
		close_btn.add_theme_font_override("font", _header_font)
	close_btn.add_theme_font_size_override("font_size", 12)
	close_btn.add_theme_stylebox_override("normal", _sb(C_CHIP_BG, C_BAR_BORDER, 2, 10))
	close_btn.add_theme_stylebox_override("hover", _sb(C_CHIP_BG.lightened(0.1), C_AMBER, 2, 10))
	close_btn.add_theme_stylebox_override("pressed", _sb(C_CHIP_BG.darkened(0.15), C_BAR_BORDER, 2, 10))
	close_btn.add_theme_color_override("font_color", C_TEXT)
	close_btn.add_theme_color_override("font_hover_color", C_AMBER)
	close_btn.pressed.connect(func(): closed.emit())
	hb.add_child(close_btn)

	# --- hint line under the bar ---
	var hint := Label.new()
	hint.text = "Drag to pan   ·   Wheel to zoom   ·   Left-click a node to buy   ·   Right-click to refund"
	hint.add_theme_font_size_override("font_size", 16)
	hint.add_theme_color_override("font_color", C_MUTED)
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(hint)
	hint.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP, Control.PRESET_MODE_KEEP_SIZE, 62)

	# --- floating tooltip ---
	_tip_panel = PanelContainer.new()
	_tip_panel.add_theme_stylebox_override("panel", _sb(Color8(24, 20, 15), C_AMBER.darkened(0.1), 2, 12))
	_tip_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tip_panel.visible = false
	add_child(_tip_panel)
	_tip_lbl = RichTextLabel.new()
	_tip_lbl.bbcode_enabled = true
	_tip_lbl.fit_content = true
	_tip_lbl.custom_minimum_size = Vector2(330, 0)
	_tip_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tip_panel.add_child(_tip_lbl)

func _refresh_points() -> void:
	_pts_lbl.text = GameData.fmt(GameState.skill_points_available())
	_coins_lbl.text = GameData.fmt(GameState.money)
	_level_lbl.text = "%d" % GameState.get_level()

# ===========================================================================
# Drawing
# ===========================================================================
func _view_center() -> Vector2:
	return size * 0.5 + _pan

func _screen_pos(rel: Vector2) -> Vector2:
	return _view_center() + rel * _zoom

func _octagon(center: Vector2, r: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for k in range(8):
		var a := deg_to_rad(22.5 + k * 45.0)
		pts.append(center + Vector2(cos(a), sin(a)) * r)
	return pts

func _stroke_poly(pts: PackedVector2Array, col: Color, w: float) -> void:
	var closed := pts.duplicate()
	closed.append(pts[0])
	draw_polyline(closed, col, w)

func _draw() -> void:
	# Background.
	draw_rect(Rect2(Vector2.ZERO, size), Color8(16, 14, 18))
	# One-time auto-fit so the whole tree is visible on any window size.
	if not _fitted and size.y > 1.0:
		var max_r := RING0 + 8.0 * RING_STEP + 40.0
		_zoom = clampf(minf(size.x, size.y) * 0.46 / max_r, 0.4, 1.3)
		_fitted = true
	var c := _view_center()

	# Faint colored glow disk behind each section arm.
	for si in range(GameData.SKILL_PATHS.size()):
		var section: String = GameData.SKILL_PATHS[si]
		var a := deg_to_rad(-90.0 + si * 120.0)
		var dc := c + Vector2(cos(a), sin(a)) * (RING0 + 3.2 * RING_STEP) * _zoom
		var col: Color = SECTION_COLOR[section]
		draw_circle(dc, 4.0 * RING_STEP * _zoom, Color(col.r, col.g, col.b, 0.055))

	# Connecting links (glow under, bright over).
	for id in _nodes:
		var n: Dictionary = _nodes[id]
		var a := _screen_pos(n["rel"])
		var b := c if n["parent_rel"] == Vector2.ZERO else _screen_pos(n["parent_rel"])
		var base: Color = SECTION_COLOR[n["section"]]
		var lvl := GameState.skill_level(id)
		var unlocked: bool = GameState.skill_unlocked(id)
		if lvl > 0:
			draw_line(b, a, Color(base.r, base.g, base.b, 0.22), 7.0 * _zoom)
			draw_line(b, a, base, 2.6 * _zoom)
		elif unlocked:
			draw_line(b, a, Color(base.r, base.g, base.b, 0.55), 2.2 * _zoom)
		else:
			draw_line(b, a, Color(1, 1, 1, 0.10), 2.0 * _zoom)

	_draw_hub(c)

	for id in _nodes:
		_draw_node(id, _nodes[id])

	# Section labels (fixed size so they stay readable at any zoom).
	var font: Font = _header_font if _header_font != null else ThemeDB.fallback_font
	for si in range(GameData.SKILL_PATHS.size()):
		var section: String = GameData.SKILL_PATHS[si]
		var a := deg_to_rad(-90.0 + si * 120.0)
		var lp := c + Vector2(cos(a), sin(a)) * (RING0 + 8.6 * RING_STEP) * _zoom
		var label: String = DISPLAY_NAME.get(section, section)
		draw_string(font, lp - Vector2(140, 0), label, HORIZONTAL_ALIGNMENT_CENTER, 280, 20, SECTION_COLOR[section])

func _draw_hub(c: Vector2) -> void:
	# The hub IS the Heart of the Delve node.
	var hs := 26.0 * _zoom
	var lvl := GameState.skill_level("heart")
	var unlocked: bool = GameState.skill_unlocked("heart")
	var core: Color
	if lvl > 0:
		core = Color8(232, 96, 104)          # active: molten heart red
	elif unlocked:
		core = Color8(228, 196, 108)          # ready: lit gold
	else:
		core = Color8(96, 98, 110)            # locked: grey
	var diamond := func(r: float) -> PackedVector2Array:
		return PackedVector2Array([c + Vector2(0, -r), c + Vector2(r, 0), c + Vector2(0, r), c + Vector2(-r, 0)])
	draw_colored_polygon(diamond.call(hs * 1.24), Color8(12, 10, 14))
	draw_colored_polygon(diamond.call(hs), core.darkened(0.45))
	draw_colored_polygon(diamond.call(hs * 0.62), core)
	_stroke_poly(diamond.call(hs), core.lightened(0.35) if unlocked else Color8(60, 58, 70), 2.0 * _zoom)
	if _hovered == "heart":
		_stroke_poly(diamond.call(hs * 1.24), Color.WHITE, 2.5 * _zoom)
	# Level number (active) or a lock hint on the ready/locked hub.
	var font: Font = _header_font if _header_font != null else ThemeDB.fallback_font
	if lvl > 0:
		var txt := str(lvl)
		draw_string(font, c + Vector2(-hs, 6 * _zoom), txt, HORIZONTAL_ALIGNMENT_CENTER, hs * 2.0, int(14 * _zoom), Color8(28, 18, 14))
	elif not unlocked:
		draw_string(font, c + Vector2(-hs, 5 * _zoom), "Lv%d" % GameData.HEART_UNLOCK_LEVEL, HORIZONTAL_ALIGNMENT_CENTER, hs * 2.0, int(10 * _zoom), Color8(200, 200, 210))

func _draw_node(id: String, n: Dictionary) -> void:
	var p := _screen_pos(n["rel"])
	var r: float = SIZE_RADIUS[n["size"]] * _zoom
	var base: Color = SECTION_COLOR[n["section"]]
	var lvl := GameState.skill_level(id)
	var maxl := int(GameData.SKILLS[id].get("max_level", 1))
	var maxed: bool = GameState.is_skill_maxed(id)
	var unlocked: bool = GameState.skill_unlocked(id)

	var rim: Color
	var face: Color
	var icon_col: Color
	if maxed:
		rim = base.lightened(0.4); face = base.darkened(0.32); icon_col = Color(1, 1, 1, 0.95)
	elif lvl > 0:
		rim = base; face = base.darkened(0.58); icon_col = base.lightened(0.55)
	elif unlocked:
		rim = base.darkened(0.22); face = Color8(32, 29, 36); icon_col = base.lightened(0.35)
	else:
		rim = Color8(72, 74, 86); face = Color8(26, 25, 31); icon_col = Color8(120, 124, 138)

	draw_colored_polygon(_octagon(p, r * 1.14), Color8(10, 9, 12))   # dark metal frame
	draw_colored_polygon(_octagon(p, r), rim)                        # colored rim
	draw_colored_polygon(_octagon(p, r * 0.72), face)                # inner face
	_draw_icon(p, r * 0.5, GameData.SKILLS[id].get("stat", ""), icon_col)

	if maxed:
		_stroke_poly(_octagon(p, r * 1.14), base.lightened(0.5), 2.0 * _zoom)
	if id == _hovered:
		_stroke_poly(_octagon(p, r * 1.22), Color.WHITE, 2.5 * _zoom)

	if lvl > 0 or id == _hovered:
		_draw_pips(p, r, lvl, maxl, base)

func _draw_pips(p: Vector2, r: float, lvl: int, maxl: int, base: Color) -> void:
	if maxl <= 0:
		return
	var pr := 2.4 * _zoom
	var gap := 3.0 * _zoom
	var total := maxl * (pr * 2.0) + (maxl - 1) * gap
	var x0 := p.x - total * 0.5 + pr
	var y := p.y + r * 1.32
	for i in range(maxl):
		var cx := x0 + i * (pr * 2.0 + gap)
		if i < lvl:
			draw_circle(Vector2(cx, y), pr, base.lightened(0.3))
		else:
			draw_circle(Vector2(cx, y), pr, Color8(60, 58, 66))

func _icon_kind(stat: String) -> String:
	match stat:
		"click_damage", "ai_damage", "ai_damage_mult", "machine_damage", "machine_damage_mult":
			return "dmg"
		"click_cooldown", "ai_interval", "machine_speed":
			return "speed"
		"resource_mult", "manual_resource_bonus", "ai_resource_bonus", "machine_resource_bonus":
			return "gem"
		"exp_mult":
			return "star"
		"crit_chance", "crit_damage":
			return "crit"
		"lucky_chance":
			return "luck"
		"deep_bonus":
			return "deep"
		_:
			return "dot"

## Small procedural glyph centred on `p`, scaled to `s`, in `col`.
func _draw_icon(p: Vector2, s: float, stat: String, col: Color) -> void:
	var w := maxf(1.5, 1.8 * _zoom)
	match _icon_kind(stat):
		"dmg":   # upward chevron (pickaxe strike)
			draw_colored_polygon(PackedVector2Array([
				p + Vector2(-s, s * 0.55), p + Vector2(0, -s * 0.75), p + Vector2(s, s * 0.55),
				p + Vector2(s * 0.45, s * 0.55), p + Vector2(0, -s * 0.05), p + Vector2(-s * 0.45, s * 0.55)]), col)
		"speed":   # lightning bolt
			draw_colored_polygon(PackedVector2Array([
				p + Vector2(s * 0.15, -s), p + Vector2(-s * 0.5, s * 0.1),
				p + Vector2(-s * 0.05, s * 0.1), p + Vector2(-s * 0.15, s),
				p + Vector2(s * 0.5, -s * 0.1), p + Vector2(s * 0.05, -s * 0.1)]), col)
		"gem":   # diamond
			draw_colored_polygon(PackedVector2Array([
				p + Vector2(0, -s), p + Vector2(s * 0.75, 0), p + Vector2(0, s), p + Vector2(-s * 0.75, 0)]), col)
		"star":
			draw_colored_polygon(_star(p, s, s * 0.45, 5), col)
		"crit":   # asterisk burst
			for k in range(3):
				var a := deg_to_rad(k * 60.0)
				var d := Vector2(cos(a), sin(a)) * s
				draw_line(p - d, p + d, col, w)
		"luck":   # four-dot clover
			for k in range(4):
				var a2 := deg_to_rad(45.0 + k * 90.0)
				draw_circle(p + Vector2(cos(a2), sin(a2)) * s * 0.5, s * 0.4, col)
		"deep":   # downward triangle
			draw_colored_polygon(PackedVector2Array([
				p + Vector2(-s, -s * 0.6), p + Vector2(s, -s * 0.6), p + Vector2(0, s * 0.8)]), col)
		_:   # generic dot
			draw_circle(p, s * 0.5, col)

func _star(center: Vector2, outer: float, inner: float, points: int) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in range(points * 2):
		var rad := outer if i % 2 == 0 else inner
		var a := -PI / 2.0 + i * PI / points
		pts.append(center + Vector2(cos(a), sin(a)) * rad)
	return pts

# ===========================================================================
# Interaction (unchanged behaviour)
# ===========================================================================
func _hit_test(mouse: Vector2) -> String:
	# Central hub = the Heart node.
	if mouse.distance_to(_view_center()) <= 30.0 * _zoom:
		return "heart"
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
							_update_tooltip(event.position)
							queue_redraw()
			MOUSE_BUTTON_RIGHT:
				if event.pressed and _hovered != "":
					if GameState.refund_skill(_hovered):
						_refresh_points()
						_update_tooltip(event.position)
						queue_redraw()
	elif event is InputEventMouseMotion:
		if _dragging:
			_pan += event.relative
			_drag_moved += event.relative.length()
		var h := _hit_test(event.position)
		if h != _hovered:
			_hovered = h
		_update_tooltip(event.position)
		queue_redraw()

func _update_tooltip(mpos: Vector2) -> void:
	if _hovered == "" or not GameData.SKILLS.has(_hovered):
		_tip_panel.visible = false
		return
	var n: Dictionary = GameData.SKILLS[_hovered]
	var lvl := GameState.skill_level(_hovered)
	var maxl := int(n["max_level"])
	var col: Color = SECTION_COLOR[n["section"]]
	var nl := "%c" % 10
	var div := nl + "[color=#5a5048]────────────────────[/color]" + nl
	# Title + rank.
	var lines := "[font_size=22][b][color=#%s]%s[/color][/b][/font_size]" % [col.to_html(false), n["name"]]
	if _hovered == "heart":
		lines += nl + "[color=#b8ad98]Rank %d   ·   [/color][color=#d6aa4e]ENDLESS[/color]" % lvl
	else:
		lines += nl + "[color=#b8ad98]Rank %d / %d[/color]" % [lvl, maxl]
	lines += div
	lines += "[color=#d8ccb4]%s[/color]" % n["desc"]
	if lvl > 0:
		lines += nl + "Now (Lv %d): [color=#8f8]%s[/color]" % [lvl, GameData.skill_total_desc(_hovered, lvl)]
	if lvl < maxl:
		lines += nl + "Next (Lv %d): [color=#ffd]%s[/color]" % [lvl + 1, GameData.skill_total_desc(_hovered, lvl + 1)]
	lines += div
	lines += "[color=#d6aa4e]COST:  %d POINT%s[/color]" % [int(n["cost"]), "" if int(n["cost"]) == 1 else "S"]
	# Buy state.
	lines += nl
	if GameState.is_skill_maxed(_hovered):
		lines += "[color=#8f8]MAXED[/color]"
	elif not GameState.skill_unlocked(_hovered):
		if _hovered == "heart":
			lines += "[color=#f88]LOCKED — reach Level %d[/color]" % GameData.HEART_UNLOCK_LEVEL
		else:
			lines += "[color=#f88]LOCKED — buy the prior node first[/color]"
	elif GameState.skill_points_available() >= int(n["cost"]):
		lines += "[color=#ff6]Left-click to buy[/color]"
	else:
		lines += "[color=#f88]Not enough skill points[/color]"
	# Refund state (coins).
	if lvl > 0:
		var rc := GameState.skill_refund_cost(_hovered)
		if GameState.can_refund_skill(_hovered):
			lines += nl + "[color=#7cf]Right-click: refund 1 level (−%s coins)[/color]" % GameData.fmt(rc)
		elif GameState.skill_level(_hovered) == 1 and GameState.skill_has_owned_dependents(_hovered):
			lines += nl + "[color=#f88]Can't refund: reclaim dependent nodes first[/color]"
		else:
			lines += nl + "[color=#f88]Refund needs %s coins[/color]" % GameData.fmt(rc)
	_tip_lbl.text = lines
	_tip_panel.visible = true
	# Position near the cursor, clamped to stay on-screen.
	var ts := _tip_panel.get_combined_minimum_size()
	var pos := mpos + Vector2(18, 18)
	pos.x = clampf(pos.x, 0.0, maxf(0.0, size.x - ts.x))
	pos.y = clampf(pos.y, 0.0, maxf(0.0, size.y - ts.y))
	_tip_panel.position = pos
