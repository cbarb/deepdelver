class_name PauseMenu
extends CanvasLayer
## Overlay shown when the player presses ESC mid-run. Dims the game, offers
## RESUME and END RUN EARLY. Styled to match the surface camp / descent screen.

signal resume_pressed
signal end_pressed

const C_BG := Color8(18, 14, 10)
const C_PANEL := Color8(33, 25, 16)
const C_PANEL_BORDER := Color8(74, 54, 30)
const C_CARD := Color8(27, 20, 13)
const C_CARD_BORDER := Color8(58, 43, 25)
const C_AMBER := Color8(196, 148, 60)
const C_TEXT := Color8(226, 212, 186)
const C_MUTED := Color8(150, 140, 120)
const C_TITLE := Color8(202, 174, 126)
const C_DANGER := Color8(198, 112, 92)
const C_DARK_TXT := Color8(26, 18, 8)

var _header_font: Font = load("res://assets/fonts/Press_Start_2P/PressStart2P-Regular.ttf")

func _ready() -> void:
	layer = 128   # above the HUD CanvasLayer

	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP   # swallow clicks so mining can't fire
	add_child(root)

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.62)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)

	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _sb(C_PANEL, C_PANEL_BORDER, 2, 28))
	center.add_child(panel)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 16)
	panel.add_child(v)

	var title := _hlbl("PAUSED", 28, C_TITLE)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(title)

	var resume := _button("RESUME", C_AMBER, C_DARK_TXT, C_AMBER.darkened(0.25))
	resume.pressed.connect(func(): resume_pressed.emit())
	v.add_child(resume)

	var quit := _button("END RUN EARLY", C_CARD, C_DANGER, C_DANGER.darkened(0.2))
	quit.pressed.connect(func(): end_pressed.emit())
	v.add_child(quit)

	var hint := _hlbl("Esc to resume", 10, C_MUTED)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(hint)

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
	return l

func _button(text: String, bg: Color, txt: Color, border: Color) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(320, 58)
	if _header_font != null:
		b.add_theme_font_override("font", _header_font)
	b.add_theme_font_size_override("font_size", 14)
	b.add_theme_stylebox_override("normal", _sb(bg, border, 2, 10))
	b.add_theme_stylebox_override("hover", _sb(bg.lightened(0.10), border, 2, 10))
	b.add_theme_stylebox_override("pressed", _sb(bg.darkened(0.12), border, 2, 10))
	b.add_theme_color_override("font_color", txt)
	b.add_theme_color_override("font_hover_color", txt.lightened(0.1))
	b.add_theme_color_override("font_pressed_color", txt)
	return b
