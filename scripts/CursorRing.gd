class_name CursorRing
extends Control
## A small ring drawn around the mouse cursor that visualises the click
## cooldown: while cooling down an arc sweeps from empty to full; when ready it
## shows a faint green ring with a brief flash the moment it becomes usable.

var progress: float = 1.0        # 1.0 = ready, <1.0 = still cooling down
var radius: float = 34.0
var thickness: float = 4.0
var pickaxe_tex: Texture2D       # software cursor sprite (equipped pickaxe)
const PICK_SIZE := 64.0
var _ready_flash: float = 0.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE   # never block world clicks
	set_process(true)

func set_pickaxe(tex: Texture2D) -> void:
	pickaxe_tex = tex
	queue_redraw()

func set_progress(p: float) -> void:
	p = clampf(p, 0.0, 1.0)
	if p >= 1.0 and progress < 1.0:
		_ready_flash = 0.35                      # just became ready -> flash
	progress = p

func _process(delta: float) -> void:
	if _ready_flash > 0.0:
		_ready_flash = maxf(0.0, _ready_flash - delta)
	position = get_viewport().get_mouse_position()
	queue_redraw()

func _draw() -> void:
	# Pickaxe sprite drawn centred on the cursor (software cursor).
	if pickaxe_tex != null:
		draw_texture_rect(pickaxe_tex,
			Rect2(Vector2(-PICK_SIZE * 0.5, -PICK_SIZE * 0.5), Vector2(PICK_SIZE, PICK_SIZE)), false)
	# Faint backdrop ring so it always reads against any background.
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 48, Color(0, 0, 0, 0.45), thickness + 2.0, true)

	if progress < 1.0:
		# Cooldown: bright arc sweeping clockwise from the top.
		var start := -PI / 2.0
		var end := start + TAU * progress
		draw_arc(Vector2.ZERO, radius, start, end, 48, Color(1.0, 0.82, 0.3, 0.95), thickness, true)
	else:
		# Ready: soft green ring, briefly brighter right after recharge.
		var a := 0.55 + _ready_flash * 1.3
		draw_arc(Vector2.ZERO, radius, 0.0, TAU, 48, Color(0.4, 1.0, 0.55, clampf(a, 0.0, 1.0)), thickness, true)
