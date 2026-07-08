class_name CursorRing
extends Control
## The software mouse cursor: draws the equipped pickaxe sprite plus a small
## cooldown bar just below it — the bar fills as the click recharges and turns
## green (with a brief flash) the moment it becomes usable.

var progress: float = 1.0        # 1.0 = ready, <1.0 = still cooling down
var pickaxe_tex: Texture2D       # software cursor sprite (equipped pickaxe)
const PICK_SIZE := 64.0
const BAR_W := 46.0              # cooldown bar size / offset below the cursor
const BAR_H := 7.0
const BAR_Y := 34.0
var _ready_flash: float = 0.0
var _swing: float = 0.0           # remaining swing-animation time (s)
const SWING_TIME := 0.22

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

## Kick off a one-shot pickaxe swing (called when the player mines).
func swing() -> void:
	_swing = SWING_TIME

func _process(delta: float) -> void:
	if _ready_flash > 0.0:
		_ready_flash = maxf(0.0, _ready_flash - delta)
	if _swing > 0.0:
		_swing = maxf(0.0, _swing - delta)
	position = get_viewport().get_mouse_position()
	queue_redraw()

func _draw() -> void:
	# Pickaxe sprite drawn centred on the cursor (software cursor), flipped
	# horizontally and rotated through a quick chop while swinging.
	if pickaxe_tex != null:
		var ang := 0.0
		if _swing > 0.0:
			var t := 1.0 - _swing / SWING_TIME    # 0 at start -> 1 at end
			# Asymmetric chop: snap down fast, ease back up (reads as a strike).
			var chop: float = (t / 0.35) if t < 0.35 else (1.0 - (t - 0.35) / 0.65)
			ang = -deg_to_rad(42.0) * chop
		# Pivot near the grip so the head swings through an arc. scale.x = -1
		# flips the sprite horizontally; the local centre is placed so the
		# sprite sits on the cursor at rest.
		var pivot := Vector2(0.0, 16.0)
		draw_set_transform(pivot, ang, Vector2(-1.0, 1.0))
		var center := Vector2(pivot.x, -pivot.y)
		draw_texture_rect(pickaxe_tex,
			Rect2(center - Vector2(PICK_SIZE * 0.5, PICK_SIZE * 0.5), Vector2(PICK_SIZE, PICK_SIZE)), false)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)  # reset for the bar

	# Cooldown bar below the pickaxe, centred on the cursor.
	var bar_pos := Vector2(-BAR_W * 0.5, BAR_Y)
	# Dark backdrop so it reads against any background.
	draw_rect(Rect2(bar_pos - Vector2(1, 1), Vector2(BAR_W + 2, BAR_H + 2)), Color(0, 0, 0, 0.55), true)
	# Fill: amber while charging, green (briefly brighter) once ready.
	var fill: Color
	if progress < 1.0:
		fill = Color(1.0, 0.82, 0.3, 0.95)
	else:
		fill = Color(0.4, 1.0, 0.55, clampf(0.85 + _ready_flash * 1.3, 0.0, 1.0))
	draw_rect(Rect2(bar_pos, Vector2(BAR_W * progress, BAR_H)), fill, true)
