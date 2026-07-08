extends Node
## Settings (autoload)
## Global, save-slot-independent options persisted to user://settings.cfg.
## For now this is just the UI zoom: it drives the root window's canvas-item
## content scale, so all 2D/UI scales up or down while the 3D mine keeps
## rendering at native resolution.

const PATH := "user://settings.cfg"
const MIN_SCALE := 0.75
const MAX_SCALE := 2.0
const STEP := 0.05

signal ui_scale_changed(value: float)

var ui_scale: float = 1.0

func _ready() -> void:
	_load()
	# The window exists by now, but apply on the next idle frame to be safe.
	call_deferred("apply")

## Push the current settings onto the live window.
func apply() -> void:
	var w := get_window()
	if w == null:
		return
	# CANVAS_ITEMS scales only the 2D layer (menus, HUD) — the 3D world is untouched.
	w.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	w.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	w.content_scale_factor = ui_scale

func set_ui_scale(v: float) -> void:
	ui_scale = clampf(snappedf(v, STEP), MIN_SCALE, MAX_SCALE)
	apply()
	_save()
	ui_scale_changed.emit(ui_scale)

func nudge_ui_scale(delta: float) -> void:
	set_ui_scale(ui_scale + delta)

# ---------------------------------------------------------------------------
func _save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("display", "ui_scale", ui_scale)
	cfg.save(PATH)

func _load() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return
	ui_scale = clampf(float(cfg.get_value("display", "ui_scale", 1.0)), MIN_SCALE, MAX_SCALE)
