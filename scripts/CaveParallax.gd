class_name CaveParallax
extends Control
## A fully code-drawn cave backdrop for the title screen. Several jagged rock
## layers (stalactites above, stalagmites below) sit at different parallax
## depths and slide with the mouse to fake 3D depth. A soft glow drifts in the
## distance, crystals shimmer on the mid layers, and dust motes float upward.
## Everything is generated once from a fixed seed (normalized coords) and mapped
## to the current size each _draw, so it survives window resizes and UI zoom.

const AMP := 60.0          # max parallax shift (px) at full mouse deflection
const SWAY := 8.0          # gentle idle drift amplitude (px) so it breathes at rest

# Rock layers, far -> near. `factor` = how strongly it reacts to the mouse.
const LAYER_DEFS := [
	{"tone": Color8(34, 40, 60),  "factor": 0.05, "segs": 7,  "top": 0.16, "bot": 0.14},
	{"tone": Color8(24, 28, 45),  "factor": 0.12, "segs": 9,  "top": 0.22, "bot": 0.20},
	{"tone": Color8(15, 17, 30),  "factor": 0.22, "segs": 11, "top": 0.30, "bot": 0.28},
	{"tone": Color8(6, 6, 13),    "factor": 0.38, "segs": 8,  "top": 0.40, "bot": 0.40},
]

var _rng := RandomNumberGenerator.new()
var _layers: Array = []        # {tone, factor, top_pts, bot_pts}
var _crystals: Array = []      # {n (normalized Vector2), factor, color, r, phase}
var _motes: Array = []         # {n, speed, r, alpha, factor}
var _off := Vector2.ZERO       # smoothed mouse deflection, ~[-1,1]
var _t := 0.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE   # let the menu above receive clicks
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_rng.seed = 0x0DE7A11   # fixed -> the cave looks the same every launch
	_generate()
	set_process(true)

func _generate() -> void:
	for def in LAYER_DEFS:
		_layers.append({
			"tone": def["tone"], "factor": def["factor"],
			"top_pts": _edge(int(def["segs"]), float(def["top"]), true),
			"bot_pts": _edge(int(def["segs"]), float(def["bot"]), false),
		})
	# Glowing crystals scattered on the mid layers.
	var cols := [Color8(120, 220, 235), Color8(180, 150, 245), Color8(235, 200, 120), Color8(140, 230, 180)]
	for i in range(9):
		_crystals.append({
			"n": Vector2(_rng.randf_range(0.06, 0.94), _rng.randf_range(0.20, 0.86)),
			"factor": _rng.randf_range(0.14, 0.30),
			"color": cols[i % cols.size()],
			"r": _rng.randf_range(2.5, 5.0),
			"phase": _rng.randf_range(0.0, TAU),
		})
	# Floating dust motes.
	for i in range(46):
		_motes.append({
			"n": Vector2(_rng.randf(), _rng.randf()),
			"speed": _rng.randf_range(0.010, 0.035),
			"r": _rng.randf_range(1.0, 2.6),
			"alpha": _rng.randf_range(0.05, 0.22),
			"factor": _rng.randf_range(0.08, 0.30),
		})

## Build one jagged rock edge as normalized points. x spans [-0.2, 1.2] so
## parallax shifts never reveal a gap; y is a fraction of the full height, 0 at
## the edge and growing inward. `top` true hangs from the top, false from bottom.
func _edge(segs: int, depth: float, top: bool) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var x0 := -0.2
	var x1 := 1.2
	var span := x1 - x0
	pts.append(Vector2(x0, 0.0))
	for i in range(segs + 1):
		var t := float(i) / float(segs)
		var vx := x0 + t * span
		var valley := depth * _rng.randf_range(0.05, 0.28)
		pts.append(Vector2(vx, valley))
		if i < segs:
			var mx := x0 + (t + 0.5 / float(segs)) * span
			var tip := depth * _rng.randf_range(0.55, 1.0)
			pts.append(Vector2(mx, tip))
	pts.append(Vector2(x1, 0.0))
	if not top:   # mirror handled at draw time; keep points as fraction-from-edge
		pass
	return pts

func _process(delta: float) -> void:
	_t += delta
	# Smoothly chase the mouse deflection (normalized to roughly [-1, 1]).
	var target := Vector2.ZERO
	if size.x > 1.0 and size.y > 1.0:
		var m := get_local_mouse_position()
		target = ((m / size) - Vector2(0.5, 0.5)) * 2.0
		target.x = clampf(target.x, -1.0, 1.0)
		target.y = clampf(target.y, -1.0, 1.0)
	_off = _off.lerp(target, clampf(delta * 4.0, 0.0, 1.0))
	# Drift motes upward, wrapping around.
	for mote in _motes:
		mote["n"].y -= mote["speed"] * delta
		if mote["n"].y < -0.05:
			mote["n"].y = 1.05
			mote["n"].x = _rng.randf()
	queue_redraw()

## Parallax pixel offset for a layer: mouse deflection + a slow idle sway.
func _layer_offset(factor: float) -> Vector2:
	var sway := Vector2(sin(_t * 0.5), cos(_t * 0.37)) * SWAY * factor
	return -_off * AMP * factor + sway

func _draw() -> void:
	var w := size.x
	var h := size.y

	# Distant background gradient (dark cave blue, a touch lighter toward middle).
	draw_rect(Rect2(0, 0, w, h), Color8(10, 11, 20))
	var bands := 24
	for i in range(bands):
		var f := float(i) / float(bands - 1)
		var glow := 1.0 - absf(f - 0.42) * 2.0     # brightest ~42% down
		glow = clampf(glow, 0.0, 1.0)
		var c := Color8(10, 11, 20).lerp(Color8(30, 38, 58), glow * 0.9)
		draw_rect(Rect2(0, f * h, w, h / float(bands) + 1.0), c)

	# Soft distant light glow (parallaxes gently the opposite way).
	var gc := Vector2(w * 0.5, h * 0.40) + _off * AMP * 0.10
	var pulse := 0.85 + 0.15 * sin(_t * 0.8)
	for i in range(6):
		var rr := (0.10 + 0.06 * i) * h
		var a := (0.06 - 0.008 * i) * pulse
		draw_circle(gc, rr, Color(0.42, 0.58, 0.72, maxf(a, 0.0)))

	# Rock layers, far -> near.
	for layer in _layers:
		var off: Vector2 = _layer_offset(float(layer["factor"]))
		_draw_edge(layer["top_pts"], off, layer["tone"], true)
		_draw_edge(layer["bot_pts"], off, layer["tone"], false)

	# Crystals: a bright diamond with a translucent halo.
	for cr in _crystals:
		var p: Vector2 = Vector2(cr["n"].x * w, cr["n"].y * h) + _layer_offset(float(cr["factor"]))
		var tw: float = 0.55 + 0.45 * sin(_t * 1.6 + float(cr["phase"]))
		var col: Color = cr["color"]
		draw_circle(p, float(cr["r"]) * 3.2, Color(col.r, col.g, col.b, 0.10 * tw))
		var r: float = float(cr["r"]) * (0.85 + 0.25 * tw)
		var dia := PackedVector2Array([
			p + Vector2(0, -r * 1.6), p + Vector2(r, 0),
			p + Vector2(0, r * 1.6), p + Vector2(-r, 0),
		])
		draw_colored_polygon(dia, Color(col.r, col.g, col.b, 0.85 * tw + 0.15))

	# Dust motes.
	for mote in _motes:
		var mp: Vector2 = Vector2(mote["n"].x * w, mote["n"].y * h) + _layer_offset(float(mote["factor"]))
		draw_circle(mp, float(mote["r"]), Color(0.75, 0.82, 0.95, float(mote["alpha"])))

	# Edge vignette to sink the frame into darkness.
	var vg := 0.5
	draw_rect(Rect2(0, 0, w, h * 0.12), Color(0, 0, 0, vg))
	draw_rect(Rect2(0, h * 0.88, w, h * 0.12), Color(0, 0, 0, vg))
	draw_rect(Rect2(0, 0, w * 0.06, h), Color(0, 0, 0, vg))
	draw_rect(Rect2(w * 0.94, 0, w * 0.06, h), Color(0, 0, 0, vg))

## Map a normalized rock edge to screen coords (applying parallax) and fill it.
## The edge is concave (a row of spikes), so triangulate before drawing —
## draw_colored_polygon alone fans from the first vertex and mangles concave shapes.
func _draw_edge(pts: PackedVector2Array, off: Vector2, tone: Color, top: bool) -> void:
	var w := size.x
	var h := size.y
	var out := PackedVector2Array()
	for p in pts:
		var sx := p.x * w + off.x
		var sy := (p.y * h + off.y) if top else (h - p.y * h + off.y)
		out.append(Vector2(sx, sy))
	var idx := Geometry2D.triangulate_polygon(out)
	if idx.is_empty():
		draw_colored_polygon(out, tone)   # fallback (shouldn't happen)
		return
	var i := 0
	while i < idx.size():
		draw_colored_polygon(PackedVector2Array([out[idx[i]], out[idx[i + 1]], out[idx[i + 2]]]), tone)
		i += 3
