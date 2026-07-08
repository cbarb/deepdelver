class_name DepthTrack
extends Control
## A custom-drawn vertical depth slider. Surface (0 m) sits at the top, the
## deepest allowed start at the bottom. The groove is painted with one colored
## band per biome (tinted from that biome's filler), and a chunky amber grabber
## marks the chosen depth. Drag anywhere on the track to set it.

signal changed(depth: int)

const PAD_TOP := 16.0
const PAD_BOT := 16.0
const GROOVE_W := 40.0
const GRAB_W := 62.0
const GRAB_H := 16.0

var cap := 0            # deepest selectable depth (m); 0 = surface only
var depth := 0          # current selection (m)
var _drag := false

const C_BORDER := Color8(74, 54, 30)
const C_GROOVE := Color8(20, 16, 10)
const C_AMBER := Color8(196, 148, 60)
const C_MUTED := Color8(136, 118, 94)

var _body_font: Font = load("res://assets/fonts/VT323/VT323-Regular.ttf")

func setup(cap_: int, depth_: int) -> void:
	cap = maxi(0, cap_)
	depth = clampi(depth_, 0, cap)
	queue_redraw()

func _track_rect() -> Rect2:
	var h: float = size.y - PAD_TOP - PAD_BOT
	return Rect2(Vector2((size.x - GROOVE_W) * 0.5, PAD_TOP), Vector2(GROOVE_W, maxf(1.0, h)))

func _depth_to_y(d: float) -> float:
	var r := _track_rect()
	if cap <= 0:
		return r.position.y
	return r.position.y + (d / float(cap)) * r.size.y

func _y_to_depth(y: float) -> int:
	var r := _track_rect()
	if cap <= 0 or r.size.y <= 0.0:
		return 0
	var frac := clampf((y - r.position.y) / r.size.y, 0.0, 1.0)
	return int(round(frac * cap))

func _draw() -> void:
	var r := _track_rect()
	draw_rect(r, C_GROOVE)

	# One colored band per biome that the track spans.
	if cap > 0:
		for i in GameData.BIOMES.size():
			var b: Dictionary = GameData.BIOMES[i]
			var lo: float = float(b["depth_lo"])
			if lo >= float(cap):
				break
			var hi: float = minf(float(b["depth_hi"]), float(cap))
			var y0 := _depth_to_y(lo)
			var y1 := _depth_to_y(hi)
			var col := _band_color(b)
			# Brighten the band that currently holds the grabber.
			if depth >= int(lo) and depth <= int(b["depth_hi"]):
				col = col.lightened(0.15)
			else:
				col = col.darkened(0.12)
			draw_rect(Rect2(r.position.x, y0, r.size.x, maxf(1.0, y1 - y0)), col)
			# Boundary line + depth tick label to the right of the groove.
			draw_line(Vector2(r.position.x, y1), Vector2(r.position.x + r.size.x, y1), C_BORDER, 1.0)
			if _body_font != null and hi < float(cap):
				draw_string(_body_font, Vector2(r.position.x + r.size.x + 8.0, y1 + 5.0),
					"%d m" % int(hi), HORIZONTAL_ALIGNMENT_LEFT, -1, 15, C_MUTED)

	# Groove border.
	draw_rect(r, C_BORDER, false, 2.0)

	# Surface marker at the very top.
	if _body_font != null:
		draw_string(_body_font, Vector2(r.position.x + r.size.x + 8.0, _depth_to_y(0.0) + 5.0),
			"0 m", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, C_MUTED)

	# Chunky grabber at the selected depth.
	var gy := _depth_to_y(float(depth))
	var gr := Rect2(Vector2(r.position.x + r.size.x * 0.5 - GRAB_W * 0.5, gy - GRAB_H * 0.5),
		Vector2(GRAB_W, GRAB_H))
	draw_rect(gr, C_AMBER)
	draw_rect(gr, C_AMBER.darkened(0.35), false, 2.0)
	for k in range(-1, 2):        # grip lines
		var ly := gr.position.y + gr.size.y * 0.5 + k * 4.0
		draw_line(Vector2(gr.position.x + 12.0, ly), Vector2(gr.position.x + gr.size.x - 12.0, ly),
			C_AMBER.darkened(0.4), 1.0)

func _band_color(b: Dictionary) -> Color:
	var fillers: Array = b.get("fillers", [])
	if fillers.size() > 0:
		return fillers[0].get("color", Color8(80, 70, 55))
	return Color8(80, 70, 55)

func _gui_input(event: InputEvent) -> void:
	if cap <= 0:
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
	var d := _y_to_depth(y)
	if d != depth:
		depth = d
		queue_redraw()
		changed.emit(depth)
