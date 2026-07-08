class_name SpecializationPanel
extends Control
## Full-screen overlay for choosing a specialization and its skills. Three
## columns (Striker / Stonewarden / Engineer), each listing 7 unique skills of
## which the player may pick 4 (one per spec point earned at biome milestones).
## Spending the first point in a column LOCKS the other two columns; general
## skill-tree nodes are unaffected. Built entirely in code to match the camp UI.

signal closed

# --- palette (mirrors the surface Skill Book) ---
const C_BG := Color(0.055, 0.045, 0.078, 0.97)
const C_PANEL := Color8(38, 32, 56)
const C_PANEL_BORDER := Color8(106, 92, 170)
const C_CARD := Color8(30, 26, 44)
const C_CARD_BORDER := Color8(70, 60, 104)
const C_TEXT := Color8(224, 216, 240)
const C_MUTED := Color8(150, 140, 176)
const C_TITLE := Color8(196, 180, 236)
const C_GREEN := Color8(126, 202, 100)
const C_DANGER := Color8(212, 108, 96)
const C_DARK_TXT := Color8(18, 14, 22)

var _header_font: Font = load("res://assets/fonts/Press_Start_2P/PressStart2P-Regular.ttf")
var _body: HBoxContainer
var _pts_lbl: Label
var _status_lbl: Label

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build()

# --- styling helpers ---
func _sb(bg: Color, border: Color, bw: int, margin: int) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_border_width_all(bw)
	s.border_color = border
	s.set_corner_radius_all(0)
	s.anti_aliasing = false
	s.set_content_margin_all(margin)
	return s

func _lbl(text: String, size := 18, color := C_TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l

func _hlbl(text: String, size := 13, color := C_TITLE) -> Label:
	var l := _lbl(text, size, color)
	if _header_font != null:
		l.add_theme_font_override("font", _header_font)
	return l

func _wrap(text: String, size := 16, color := C_MUTED) -> Label:
	var l := _lbl(text, size, color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return l

func _style_button(b: Button, bg: Color, txt: Color, border: Color, bw := 2, fsize := 12) -> void:
	b.focus_mode = Control.FOCUS_NONE
	if _header_font != null:
		b.add_theme_font_override("font", _header_font)
	b.add_theme_font_size_override("font_size", fsize)
	b.add_theme_stylebox_override("normal", _sb(bg, border, bw, 8))
	b.add_theme_stylebox_override("hover", _sb(bg.lightened(0.12), border.lightened(0.12), bw, 8))
	b.add_theme_stylebox_override("pressed", _sb(bg.darkened(0.12), border, bw, 8))
	b.add_theme_stylebox_override("disabled", _sb(bg.darkened(0.3), border.darkened(0.25), bw, 8))
	b.add_theme_color_override("font_color", txt)
	b.add_theme_color_override("font_hover_color", txt.lightened(0.1))
	b.add_theme_color_override("font_pressed_color", txt)
	b.add_theme_color_override("font_disabled_color", txt.darkened(0.4))

func _panel(bg := C_PANEL, border := C_PANEL_BORDER, bw := 2, margin := 12) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", _sb(bg, border, bw, margin))
	return p

func _clear(n: Node) -> void:
	for c in n.get_children():
		n.remove_child(c)
		c.queue_free()

# --- build ---
func _build() -> void:
	var bg := ColorRect.new()
	bg.color = C_BG
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var root := MarginContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for m in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		root.add_theme_constant_override(m, 22)
	add_child(root)

	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 12)
	root.add_child(outer)

	# Header
	var head := _panel(C_PANEL, C_PANEL_BORDER, 2, 14)
	outer.add_child(head)
	var hrow := HBoxContainer.new()
	hrow.add_theme_constant_override("separation", 14)
	head.add_child(hrow)
	hrow.add_child(_hlbl("SPECIALIZATIONS", 20, C_TITLE))
	var vsp := VBoxContainer.new()
	vsp.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hrow.add_child(vsp)
	_pts_lbl = _lbl("", 18, C_GREEN)
	vsp.add_child(_pts_lbl)
	_status_lbl = _lbl("", 15, C_MUTED)
	vsp.add_child(_status_lbl)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hrow.add_child(sp)
	var close := Button.new()
	close.text = "CLOSE"
	close.custom_minimum_size = Vector2(160, 48)
	_style_button(close, C_CARD, C_TEXT, C_CARD_BORDER, 2, 14)
	close.pressed.connect(func(): closed.emit())
	hrow.add_child(close)

	# Body: three spec columns
	_body = HBoxContainer.new()
	_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override("separation", 14)
	outer.add_child(_body)

	_refresh()

func _refresh() -> void:
	var avail := GameState.spec_points_available()
	var total := GameState.spec_points_total()
	_pts_lbl.text = "Spec points: %d free  ·  %d / %d used" % [avail, GameState.spec_points_spent(), total]
	var locked := GameState.spec_locked_to()
	if total <= 0:
		_status_lbl.text = "Reach biome 3, 5, 7 and 9 to earn spec points."
	elif locked == "":
		_status_lbl.text = "Pick a skill to lock in a specialization. Pick 4 in total."
	else:
		_status_lbl.text = "Locked in: %s. Other paths are unavailable (respec unlocks later)." % GameData.SPECIALIZATIONS[locked]["name"]

	_clear(_body)
	for spec in GameData.SPEC_ORDER:
		_body.add_child(_make_spec_column(spec))

func _make_spec_column(spec: String) -> Control:
	var data: Dictionary = GameData.SPECIALIZATIONS[spec]
	var accent: Color = data["color"]
	var locked_to := GameState.spec_locked_to()
	var path_blocked: bool = locked_to != "" and locked_to != spec

	var panel := _panel(C_PANEL, accent if not path_blocked else C_CARD_BORDER, 2, 12)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if path_blocked:
		panel.modulate = Color(1, 1, 1, 0.5)   # dim the excluded paths
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	panel.add_child(v)

	# Column header
	var hrow := HBoxContainer.new()
	v.add_child(hrow)
	hrow.add_child(_hlbl(data["name"], 15, accent))
	var badge_sp := Control.new()
	badge_sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hrow.add_child(badge_sp)
	if locked_to == spec:
		var bp := _panel(accent.darkened(0.55), accent, 1, 4)
		bp.add_child(_lbl("CHOSEN", 14, accent))
		hrow.add_child(bp)
	elif path_blocked:
		var bp2 := _panel(C_CARD, C_CARD_BORDER, 1, 4)
		bp2.add_child(_lbl("LOCKED", 14, C_MUTED))
		hrow.add_child(bp2)
	v.add_child(_lbl("%s focus" % data["style"], 15, C_MUTED))
	v.add_child(_wrap(data["blurb"], 15, C_MUTED))

	# Skills
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(scroll)
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 8)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	for sk in data["skills"]:
		list.add_child(_make_skill_card(spec, sk, accent, path_blocked))
	return panel

func _make_skill_card(spec: String, sk: Dictionary, accent: Color, path_blocked: bool) -> Control:
	var id: String = sk["id"]
	var owned := GameState.has_spec_skill(id)
	var card := _panel(C_CARD, accent.darkened(0.2) if owned else C_CARD_BORDER, 2 if owned else 1, 10)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	card.add_child(v)

	var trow := HBoxContainer.new()
	v.add_child(trow)
	trow.add_child(_lbl(sk["name"], 19, accent if not path_blocked else C_MUTED))
	var s := Control.new()
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	trow.add_child(s)
	if owned:
		trow.add_child(_lbl("PICKED", 15, C_GREEN))
	v.add_child(_wrap(sk["desc"], 16, C_MUTED))

	if owned:
		return card   # no button once picked (respec is a separate, later feature)

	var btn := Button.new()
	btn.custom_minimum_size = Vector2(0, 38)
	if path_blocked:
		btn.text = "LOCKED"
		_style_button(btn, C_CARD, C_MUTED, C_CARD_BORDER, 1)
		btn.disabled = true
	elif GameState.can_pick_spec_skill(id):
		btn.text = "PICK"
		_style_button(btn, accent, C_DARK_TXT, accent.darkened(0.25), 2)
		btn.pressed.connect(_on_pick.bind(id))
	else:
		btn.text = "NO POINTS"
		_style_button(btn, C_CARD, C_MUTED, C_CARD_BORDER, 1)
		btn.disabled = true
	v.add_child(btn)
	return card

func _on_pick(id: String) -> void:
	if GameState.buy_spec_skill(id):
		_refresh()
