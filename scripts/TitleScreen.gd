class_name TitleScreen
extends Control
## The start menu: parallax cave backdrop, the game logo, three save-file slots,
## and Settings / Quit. Emits `slot_selected` once the player picks a slot to
## play (either continuing an existing save or starting a fresh one); Main.gd
## listens and hands off to the surface camp.

signal slot_selected(slot: int)

const SLOTS := 3

# --- palette (cave / arcane; cards are slightly translucent so the bg shows) ---
const C_CARD := Color(0.078, 0.070, 0.118, 0.86)
const C_CARD_BORDER := Color8(92, 80, 132)
const C_PANEL := Color(0.10, 0.09, 0.15, 0.94)
const C_BORDER := Color8(120, 104, 168)
const C_TEXT := Color8(226, 218, 242)
const C_MUTED := Color8(154, 144, 176)
const C_TITLE := Color8(198, 180, 240)
const C_AMBER := Color8(226, 182, 92)
const C_GREEN := Color8(126, 202, 100)
const C_DANGER := Color8(212, 108, 96)
const C_DARK_TXT := Color8(18, 14, 22)

var _header_font: Font = load("res://assets/fonts/Press_Start_2P/PressStart2P-Regular.ttf")

var _slots_row: HBoxContainer
var _delete_armed := -1        # slot whose delete button is waiting for confirmation
var _settings_layer: CanvasLayer

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build()

# ===========================================================================
# Styling helpers
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

func _style_button(b: Button, bg: Color, txt: Color, border: Color, bw := 2, fsize := 14) -> void:
	b.focus_mode = Control.FOCUS_NONE
	if _header_font != null:
		b.add_theme_font_override("font", _header_font)
	b.add_theme_font_size_override("font_size", fsize)
	b.add_theme_stylebox_override("normal", _sb(bg, border, bw, 8))
	b.add_theme_stylebox_override("hover", _sb(bg.lightened(0.12), border.lightened(0.15), bw, 8))
	b.add_theme_stylebox_override("pressed", _sb(bg.darkened(0.12), border, bw, 8))
	b.add_theme_stylebox_override("disabled", _sb(bg.darkened(0.3), border.darkened(0.2), bw, 8))
	b.add_theme_color_override("font_color", txt)
	b.add_theme_color_override("font_hover_color", txt.lightened(0.1))
	b.add_theme_color_override("font_pressed_color", txt)

# ===========================================================================
# Build
# ===========================================================================
func _build() -> void:
	add_child(CaveParallax.new())

	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.alignment = BoxContainer.ALIGNMENT_CENTER
	root.add_theme_constant_override("separation", 30)
	add_child(root)

	_build_logo(root)
	_build_slots(root)
	_build_footer(root)

func _build_logo(root: VBoxContainer) -> void:
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 8)
	root.add_child(box)

	var title := _hlbl("DEEP DELVER", 52, C_AMBER)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_outline_color", Color(0.05, 0.03, 0.02, 0.9))
	title.add_theme_constant_override("outline_size", 10)
	title.add_theme_color_override("font_shadow_color", Color(0.9, 0.6, 0.2, 0.28))
	title.add_theme_constant_override("shadow_offset_x", 0)
	title.add_theme_constant_override("shadow_offset_y", 0)
	title.add_theme_constant_override("shadow_outline_size", 22)
	box.add_child(title)

	var sub := _lbl("descend  ·  dig  ·  delve", 22, C_MUTED)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(sub)

# ===========================================================================
# Save slots
# ===========================================================================
func _build_slots(root: VBoxContainer) -> void:
	_slots_row = HBoxContainer.new()
	_slots_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_slots_row.add_theme_constant_override("separation", 18)
	root.add_child(_slots_row)
	_fill_slots()

func _fill_slots() -> void:
	for c in _slots_row.get_children():
		_slots_row.remove_child(c)
		c.queue_free()
	for i in range(1, SLOTS + 1):
		_slots_row.add_child(_make_slot_card(i))

func _make_slot_card(slot: int) -> Control:
	var info := GameState.slot_info(slot)
	var exists: bool = info.get("exists", false)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	col.custom_minimum_size = Vector2(248, 0)

	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", _sb(C_CARD, C_CARD_BORDER, 2, 14))
	card.custom_minimum_size = Vector2(248, 150)
	col.add_child(card)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	card.add_child(v)

	var head := HBoxContainer.new()
	v.add_child(head)
	head.add_child(_hlbl("SLOT %d" % slot, 15, C_TITLE))
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(sp)
	var badge := _lbl("SAVE" if exists else "EMPTY", 15, C_GREEN if exists else C_MUTED)
	head.add_child(badge)

	var rule := Panel.new()
	rule.custom_minimum_size = Vector2(0, 2)
	rule.add_theme_stylebox_override("panel", _sb(C_CARD_BORDER, C_CARD_BORDER, 0, 0))
	v.add_child(rule)

	if exists:
		var bi := GameData.biome_index_for_row(int(info["max_depth"]))
		var bname: String = GameData.BIOMES[bi]["name"]
		v.add_child(_lbl("Level %d" % int(info["level"]), 20, C_TEXT))
		v.add_child(_lbl("Depth %s m" % GameData.fmt(int(info["max_depth"])), 18, C_MUTED))
		v.add_child(_lbl(bname, 17, C_TITLE))
		var coins := _lbl("%s coins" % GameData.fmt(int(info["money"])), 17, C_AMBER)
		v.add_child(coins)
	else:
		var empty := _lbl("No expedition yet.\nStart a fresh dig!", 18, C_MUTED)
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty.size_flags_vertical = Control.SIZE_EXPAND_FILL
		empty.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		v.add_child(empty)

	# Primary action.
	var play := Button.new()
	play.text = "CONTINUE" if exists else "NEW GAME"
	play.custom_minimum_size = Vector2(0, 44)
	_style_button(play, C_AMBER, C_DARK_TXT, C_AMBER.darkened(0.25), 2, 13)
	play.pressed.connect(_on_play.bind(slot, exists))
	col.add_child(play)

	# Delete (existing slots only, two-step confirm).
	if exists:
		var del := Button.new()
		del.text = "Delete" if _delete_armed != slot else "Confirm?"
		del.custom_minimum_size = Vector2(0, 30)
		var dcol := C_DANGER if _delete_armed == slot else C_MUTED
		_style_button(del, C_CARD, dcol, C_CARD_BORDER, 1, 12)
		del.pressed.connect(_on_delete.bind(slot))
		col.add_child(del)

	return col

func _on_play(slot: int, exists: bool) -> void:
	if exists:
		GameState.load_slot(slot)
	else:
		GameState.new_game(slot)
	slot_selected.emit(slot)

func _on_delete(slot: int) -> void:
	if _delete_armed == slot:
		GameState.delete_slot(slot)
		_delete_armed = -1
	else:
		_delete_armed = slot     # arm; a second click confirms
	_fill_slots()

# ===========================================================================
# Footer: Settings + Quit
# ===========================================================================
func _build_footer(root: VBoxContainer) -> void:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 14)
	root.add_child(row)

	var settings := Button.new()
	settings.text = "SETTINGS"
	settings.custom_minimum_size = Vector2(200, 48)
	_style_button(settings, C_PANEL, C_TEXT, C_BORDER, 2, 14)
	settings.pressed.connect(_open_settings)
	row.add_child(settings)

	var quit := Button.new()
	quit.text = "QUIT"
	quit.custom_minimum_size = Vector2(160, 48)
	_style_button(quit, C_PANEL, C_DANGER, C_BORDER, 2, 14)
	quit.pressed.connect(func(): get_tree().quit())
	row.add_child(quit)

# ===========================================================================
# Settings overlay (UI zoom)
# ===========================================================================
func _open_settings() -> void:
	if _settings_layer != null:
		return
	_settings_layer = CanvasLayer.new()
	_settings_layer.layer = 50
	add_child(_settings_layer)

	# Dim + input blocker behind the dialog.
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_settings_layer.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_settings_layer.add_child(center)

	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _sb(C_PANEL, C_BORDER, 2, 20))
	panel.custom_minimum_size = Vector2(420, 0)
	center.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 16)
	panel.add_child(v)

	v.add_child(_hlbl("SETTINGS", 20, C_TITLE))

	# --- UI Zoom row ---
	var zbox := VBoxContainer.new()
	zbox.add_theme_constant_override("separation", 8)
	v.add_child(zbox)
	zbox.add_child(_lbl("UI Zoom — scale the interface up or down.", 18, C_MUTED))

	var zrow := HBoxContainer.new()
	zrow.add_theme_constant_override("separation", 10)
	zbox.add_child(zrow)

	var minus := Button.new()
	minus.text = "–"
	minus.custom_minimum_size = Vector2(56, 44)
	_style_button(minus, C_CARD, C_TEXT, C_BORDER, 2, 20)
	zrow.add_child(minus)

	var val := _lbl("", 24, C_AMBER)
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	val.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	zrow.add_child(val)

	var plus := Button.new()
	plus.text = "+"
	plus.custom_minimum_size = Vector2(56, 44)
	_style_button(plus, C_CARD, C_TEXT, C_BORDER, 2, 20)
	zrow.add_child(plus)

	var update_val := func():
		val.text = "%d%%" % int(round(Settings.ui_scale * 100.0))
	update_val.call()
	minus.pressed.connect(func(): Settings.nudge_ui_scale(-Settings.STEP); update_val.call())
	plus.pressed.connect(func(): Settings.nudge_ui_scale(Settings.STEP); update_val.call())

	# Close.
	var close := Button.new()
	close.text = "CLOSE"
	close.custom_minimum_size = Vector2(0, 46)
	_style_button(close, C_AMBER, C_DARK_TXT, C_AMBER.darkened(0.25), 2, 14)
	close.pressed.connect(_close_settings)
	v.add_child(close)

func _close_settings() -> void:
	if _settings_layer != null:
		_settings_layer.queue_free()
		_settings_layer = null
