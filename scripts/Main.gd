extends Node
## Top-level game controller. Owns the state machine that swaps between the
## Surface hub and a Mining run, and builds the visual scenes in code.

var _surface: SurfaceUI
var _mine: MineController

func _ready() -> void:
	_show_surface()

func _clear() -> void:
	for c in get_children():
		c.queue_free()
	_surface = null
	_mine = null

func _show_surface() -> void:
	_clear()
	_surface = SurfaceUI.new()
	add_child(_surface)
	_surface.start_run.connect(_on_start_run)

func _on_start_run() -> void:
	_clear()
	_mine = MineController.new()
	add_child(_mine)
	_mine.run_finished.connect(_on_run_finished)
	_mine.start_run()

func _on_run_finished(summary: Dictionary) -> void:
	GameState.last_summary = summary
	GameState.save_game()
	_show_surface()
