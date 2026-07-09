class_name RunRecap
extends CanvasLayer
## End-of-run recap shown over the frozen mine when the timer runs out (or the run
## is ended early). Summarises the haul and waits for RESURFACE so the return to
## the surface camp isn't abrupt. `summary` must be set before adding to the tree.

signal resurface_pressed

var summary: Dictionary = {}

const C_PANEL := Color8(33, 25, 16)
const C_PANEL_BORDER := Color8(74, 54, 30)
const C_CARD := Color8(27, 20, 13)
const C_CARD_BORDER := Color8(58, 43, 25)
const C_AMBER := Color8(196, 148, 60)
const C_TEXT := Color8(226, 212, 186)
const C_MUTED := Color8(150, 140, 120)
const C_TITLE := Color8(202, 174, 126)
const C_GREEN := Color8(122, 198, 96)
const C_DARK_TXT := Color8(26, 18, 8)

var _header_font: Font = load("res://assets/fonts/Press_Start_2P/PressStart2P-Regular.ttf")

func _ready() -> void:
	layer = 128

	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(root)

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)

	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _sb(C_PANEL, C_PANEL_BORDER, 2, 22))
	panel.custom_minimum_size = Vector2(440, 0)
	center.add_child(panel)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	panel.add_child(v)

	var title := _hlbl("RUN COMPLETE", 22, C_TITLE)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(title)

	if summary.get("new_record", false):
		var rec := _lbl("NEW DEPTH RECORD!", 18, C_AMBER)
		rec.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(rec)

	# Headline stats.
	v.add_child(_row("Depth reached", "%s m" % GameData.fmt(int(summary.get("depth", 0)))))
	v.add_child(_row("Tiles mined", GameData.fmt(int(summary.get("tiles_mined", 0)))))
	v.add_child(_row("Resource tiles", GameData.fmt(int(summary.get("rare_found", 0)))))
	v.add_child(_row("EXP gained", "+%s" % GameData.fmt(int(summary.get("exp", 0))), C_GREEN))
	v.add_child(_row("Coins gained", "+%s" % GameData.fmt(int(summary.get("money", 0))), C_AMBER))

	# Resource haul (scrolls if long).
	var res: Dictionary = summary.get("resources", {})
	if not res.is_empty():
		var divider := Panel.new()
		divider.custom_minimum_size = Vector2(0, 2)
		divider.add_theme_stylebox_override("panel", _sb(C_CARD_BORDER, C_CARD_BORDER, 0, 0))
		v.add_child(divider)
		var scroll := ScrollContainer.new()
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		scroll.custom_minimum_size = Vector2(0, 180)
		v.add_child(scroll)
		var list := VBoxContainer.new()
		list.add_theme_constant_override("separation", 4)
		list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		scroll.add_child(list)
		for id in res:
			list.add_child(_row("  %s" % GameData.resource_name(id), "x%s" % GameData.fmt(int(res[id])), GameData.resource_color(id)))

	var btn := Button.new()
	btn.text = "RESURFACE"
	btn.focus_mode = Control.FOCUS_NONE
	btn.custom_minimum_size = Vector2(0, 60)
	if _header_font != null:
		btn.add_theme_font_override("font", _header_font)
	btn.add_theme_font_size_override("font_size", 16)
	btn.add_theme_stylebox_override("normal", _sb(C_AMBER, C_AMBER.darkened(0.25), 2, 10))
	btn.add_theme_stylebox_override("hover", _sb(C_AMBER.lightened(0.1), C_AMBER.darkened(0.25), 2, 10))
	btn.add_theme_stylebox_override("pressed", _sb(C_AMBER.darkened(0.12), C_AMBER.darkened(0.25), 2, 10))
	btn.add_theme_color_override("font_color", C_DARK_TXT)
	btn.add_theme_color_override("font_hover_color", C_DARK_TXT)
	btn.pressed.connect(func(): resurface_pressed.emit())
	v.add_child(btn)

# --- helpers ---
func _sb(bg: Color, border: Color, bw: int, margin: int) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_border_width_all(bw)
	s.border_color = border
	s.set_corner_radius_all(0)
	s.anti_aliasing = false
	s.set_content_margin_all(margin)
	return s

func _lbl(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l

func _hlbl(text: String, size: int, color: Color) -> Label:
	var l := _lbl(text, size, color)
	if _header_font != null:
		l.add_theme_font_override("font", _header_font)
	return l

func _row(label: String, value: String, value_col := C_TEXT) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_child(_lbl(label, 18, C_MUTED))
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(sp)
	h.add_child(_lbl(value, 18, value_col))
	return h
