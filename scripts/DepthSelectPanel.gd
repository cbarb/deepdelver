class_name DepthSelectPanel
extends Control
## Full-screen "prepare descent" overlay shown when the player presses START
## MINING. Left: a vertical DepthTrack slider to pick the starting depth (capped
## by the owned transport). Right: a reserved GAME MODE panel (endless modes are
## stubbed for later). Footer: BACK / DESCEND. Styled to match the surface camp.

signal descend(depth: int)
signal canceled

# --- palette (mirrors SurfaceUI for a consistent look) ---
const C_BG := Color8(18, 14, 10)
const C_PANEL := Color8(33, 25, 16)
const C_PANEL_BORDER := Color8(74, 54, 30)
const C_CARD := Color8(27, 20, 13)
const C_CARD_BORDER := Color8(58, 43, 25)
const C_AMBER := Color8(196, 148, 60)
const C_TEXT := Color8(222, 208, 182)
const C_MUTED := Color8(136, 118, 94)
const C_TITLE := Color8(202, 174, 126)
const C_GREEN := Color8(122, 198, 96)
const C_DARK_TXT := Color8(26, 18, 8)

var _header_font: Font = load("res://assets/fonts/Press_Start_2P/PressStart2P-Regular.ttf")

var _cap := 0
var _track: DepthTrack
var _depth_lbl: Label
var _biome_lbl: Label

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_cap = GameState.transport_start_depth()
	var init_depth := GameState.selected_start_depth
	if init_depth < 0:
		init_depth = _cap                    # unset -> default to the deepest allowed
	init_depth = clampi(init_depth, 0, _cap)
	_build(init_depth)
	_update_readout(init_depth)

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

func _panel(bg := C_PANEL, border := C_PANEL_BORDER, bw := 2, margin := 12) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", _sb(bg, border, bw, margin))
	return p

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

func _wrap_lbl(text: String, size := 17, color := C_MUTED) -> Label:
	var l := _lbl(text, size, color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return l

func _style_button(b: Button, bg: Color, txt: Color, border: Color, bw: int, fsize: int) -> void:
	b.focus_mode = Control.FOCUS_NONE
	if _header_font != null:
		b.add_theme_font_override("font", _header_font)
	b.add_theme_font_size_override("font_size", fsize)
	b.add_theme_stylebox_override("normal", _sb(bg, border, bw, 8))
	b.add_theme_stylebox_override("hover", _sb(bg.lightened(0.10), border, bw, 8))
	b.add_theme_stylebox_override("pressed", _sb(bg.darkened(0.12), border, bw, 8))
	b.add_theme_stylebox_override("disabled", _sb(bg.darkened(0.28), border.darkened(0.2), bw, 8))
	b.add_theme_color_override("font_color", txt)
	b.add_theme_color_override("font_hover_color", txt.lightened(0.1))
	b.add_theme_color_override("font_pressed_color", txt)
	b.add_theme_color_override("font_disabled_color", txt.darkened(0.35))

# --- build ---
func _build(init_depth: int) -> void:
	var bg := ColorRect.new()
	bg.color = C_BG
	add_child(bg)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var root := MarginContainer.new()
	add_child(root)
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for m in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		root.add_theme_constant_override(m, 24)

	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 14)
	root.add_child(outer)

	# Header
	var head := _panel(C_PANEL, C_PANEL_BORDER, 2, 14)
	outer.add_child(head)
	var hrow := HBoxContainer.new()
	hrow.add_theme_constant_override("separation", 12)
	head.add_child(hrow)
	hrow.add_child(_hlbl("PREPARE DESCENT", 20, C_TITLE))
	var sub := _lbl("Choose where to begin the run", 16, C_MUTED)
	sub.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hrow.add_child(sub)

	# Body: depth slider (left) + game-mode panel (right)
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 14)
	outer.add_child(body)
	_build_depth_panel(body, init_depth)
	_build_mode_panel(body)

	# Footer
	var foot := _panel(C_PANEL, C_PANEL_BORDER, 2, 12)
	outer.add_child(foot)
	var frow := HBoxContainer.new()
	frow.add_theme_constant_override("separation", 12)
	foot.add_child(frow)
	var back := Button.new()
	back.text = "BACK"
	back.custom_minimum_size = Vector2(160, 56)
	_style_button(back, C_CARD, C_TEXT, C_CARD_BORDER, 1, 14)
	back.pressed.connect(func(): canceled.emit())
	frow.add_child(back)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	frow.add_child(sp)
	var go := Button.new()
	go.text = "DESCEND"
	go.custom_minimum_size = Vector2(340, 62)
	_style_button(go, C_AMBER, C_DARK_TXT, C_AMBER.darkened(0.25), 2, 18)
	go.pressed.connect(func(): descend.emit(_track.depth))
	frow.add_child(go)

func _build_depth_panel(body: HBoxContainer, init_depth: int) -> void:
	var col := VBoxContainer.new()
	col.custom_minimum_size = Vector2(360, 0)
	col.add_theme_constant_override("separation", 10)
	body.add_child(col)

	var panel := _panel()
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	panel.add_child(v)
	v.add_child(_hlbl("START DEPTH", 13, C_TITLE))

	# Big live readout.
	_depth_lbl = _lbl("0 m", 30, C_AMBER)
	v.add_child(_depth_lbl)
	_biome_lbl = _lbl("", 18, C_TITLE)
	v.add_child(_biome_lbl)

	# The slider itself (centered, fills the remaining height).
	var track_row := HBoxContainer.new()
	track_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	track_row.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(track_row)
	_track = DepthTrack.new()
	_track.custom_minimum_size = Vector2(150, 360)
	_track.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_track.setup(_cap, init_depth)
	_track.changed.connect(_update_readout)
	track_row.add_child(_track)

	if _cap <= 0:
		v.add_child(_wrap_lbl("Build an Elevator at the camp to start deeper than the surface.", 16, C_MUTED))
	else:
		v.add_child(_wrap_lbl("Drag the handle. Top = surface, bottom = your deepest reach.", 16, C_MUTED))

func _build_mode_panel(body: HBoxContainer) -> void:
	var panel := _panel()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	panel.add_child(v)
	v.add_child(_hlbl("GAME MODE", 13, C_TITLE))

	# Standard descent is the active mode.
	v.add_child(_mode_card("Standard Descent", "A timed 60s run. Dig as deep as you can.", true))

	# Endless modes per biome reached — stubbed for a future update.
	var reached := GameData.biome_index_for_row(GameState.max_depth)
	for i in range(reached + 1):
		var b: Dictionary = GameData.BIOMES[i]
		v.add_child(_mode_card("Endless · %s" % b["name"], "Mine this biome with no timer.", false))
	v.add_child(_wrap_lbl("More modes coming soon.", 15, C_MUTED))

func _mode_card(title: String, desc: String, active: bool) -> PanelContainer:
	var border := C_AMBER.darkened(0.15) if active else C_CARD_BORDER
	var card := _panel(C_CARD, border, 2, 12)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	card.add_child(v)
	var trow := HBoxContainer.new()
	v.add_child(trow)
	trow.add_child(_lbl(title, 18, C_TITLE if active else C_MUTED))
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	trow.add_child(sp)
	var badge := _panel(C_GREEN.darkened(0.55), C_GREEN, 1, 4) if active else _panel(C_CARD, C_CARD_BORDER, 1, 4)
	badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	badge.add_child(_lbl("ACTIVE" if active else "SOON", 13, C_GREEN if active else C_MUTED))
	trow.add_child(badge)
	v.add_child(_wrap_lbl(desc, 15, C_MUTED))
	return card

func _update_readout(depth: int) -> void:
	_depth_lbl.text = "%d m" % depth
	var b: Dictionary = GameData.biome_for_row(depth)
	_biome_lbl.text = "Biome %d · %s" % [GameData.biome_index_for_row(depth) + 1, b["name"]]
