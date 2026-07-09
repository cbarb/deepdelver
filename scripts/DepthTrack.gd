class_name DepthTrack
extends Control
## A custom-drawn vertical biome picker. One band per discovered biome the
## transport can reach (Biome 1 at the top … deepest at the bottom); click or
## drag to select which biome's START to drop into. Snaps to whole biomes.

signal changed(biome_index: int)

const PAD_TOP := 16.0
const PAD_BOT := 16.0
const GROOVE_W := 120.0

var max_biome := 0      # deepest selectable biome index (0 = surface only)
var biome := 0          # currently selected biome index
var _drag := false

const C_BORDER := Color8(74, 54, 30)
const C_GROOVE := Color8(20, 16, 10)
const C_AMBER := Color8(196, 148, 60)
const C_TEXT := Color8(226, 212, 186)
const C_MUTED := Color8(136, 118, 94)

var _body_font: Font = load("res://assets/fonts/VT323/VT323-Regular.ttf")
var _header_font: Font = load("res://assets/fonts/Press_Start_2P/PressStart2P-Regular.ttf")

func setup(max_biome_: int, biome_: int) -> void:
	max_biome = maxi(0, max_biome_)
	biome = clampi(biome_, 0, max_biome)
	queue_redraw()

func _track_rect() -> Rect2:
	var h: float = size.y - PAD_TOP - PAD_BOT
	return Rect2(Vector2((size.x - GROOVE_W) * 0.5, PAD_TOP), Vector2(GROOVE_W, maxf(1.0, h)))

func _band_count() -> int:
	return max_biome + 1

func _band_rect(i: int) -> Rect2:
	var r := _track_rect()
	var bh := r.size.y / float(_band_count())
	return Rect2(r.position.x, r.position.y + i * bh, r.size.x, bh)

func _band_color(i: int) -> Color:
	var fillers: Array = GameData.BIOMES[i].get("fillers", [])
	if fillers.size() > 0:
		return fillers[0].get("color", Color8(80, 70, 55))
	return Color8(80, 70, 55)

func _draw() -> void:
	var r := _track_rect()
	draw_rect(r, C_GROOVE)
	for i in range(_band_count()):
		var br := _band_rect(i)
		var col := _band_color(i)
		col = col.lightened(0.18) if i == biome else col.darkened(0.2)
		draw_rect(br.grow(-2.0), col)
		if i == biome:
			var ol := br.grow(-1.0)
			draw_rect(ol, C_AMBER, false, 3.0)
		# Label: biome number + start depth.
		if _header_font != null:
			draw_string(_header_font, br.position + Vector2(8, br.size.y * 0.5 + 5.0),
				"B%d" % (i + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 12,
				C_TEXT if i == biome else C_MUTED)
		if _body_font != null:
			var startm := "%d m" % int(GameData.BIOMES[i]["depth_lo"])
			draw_string(_body_font, br.position + Vector2(br.size.x - 62, br.size.y * 0.5 + 6.0),
				startm, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, C_MUTED)
	draw_rect(r, C_BORDER, false, 2.0)

func _gui_input(event: InputEvent) -> void:
	if max_biome <= 0:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_drag = true
			_set_from_y(event.position.y)
		else:
			_drag = false
	elif event is InputEventMouseMotion and _drag:
		_set_from_y(event.position.y)

func _set_from_y(y: float) -> void:
	var r := _track_rect()
	var bh := r.size.y / float(_band_count())
	var idx := clampi(int((y - r.position.y) / bh), 0, max_biome)
	if idx != biome:
		biome = idx
		queue_redraw()
		changed.emit(biome)
