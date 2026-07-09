extends Node
## Settings (autoload)
## Global, save-slot-independent options persisted to user://settings.cfg.
## For now this is just the UI zoom: it drives the root window's canvas-item
## content scale, so all 2D/UI scales up or down while the 3D mine keeps
## rendering at native resolution.

const PATH := "user://settings.cfg"
const SAVE_VERSION := 2
# ui_scale is the user-facing fraction: 1.0 = 100% = the regular size. The actual
# window content factor is BASE_SCALE * ui_scale, so 100% renders at what used to
# be the 75% setting. The UI can only scale DOWN from 100% (never up).
const BASE_SCALE := 0.75
const MIN_SCALE := 0.5    # down to 50%
const MAX_SCALE := 1.0    # 100% = regular, no upscaling
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
	w.content_scale_factor = BASE_SCALE * ui_scale

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
	cfg.set_value("display", "version", SAVE_VERSION)
	cfg.set_value("display", "ui_scale", ui_scale)
	cfg.save(PATH)

func _load() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return
	var ver := int(cfg.get_value("display", "version", 1))
	var raw := float(cfg.get_value("display", "ui_scale", 1.0))
	if ver < SAVE_VERSION:
		# v1 stored the raw content factor (regular = 1.0). Convert to the new
		# fraction so the old 75% setting becomes the new 100%, then persist.
		raw = raw / BASE_SCALE
		ui_scale = clampf(raw, MIN_SCALE, MAX_SCALE)
		_save()
	else:
		ui_scale = clampf(raw, MIN_SCALE, MAX_SCALE)
