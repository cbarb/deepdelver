extends Node
## Top-level game controller. Owns the state machine that swaps between the
## Title screen, the Surface hub, and a Mining run, and builds the visual scenes
## in code.

var _title: TitleScreen
var _surface: SurfaceUI
var _mine: MineController

func _ready() -> void:
	_show_title()

func _clear() -> void:
	for c in get_children():
		c.queue_free()
	_title = null
	_surface = null
	_mine = null

func _show_title() -> void:
	_clear()
	_title = TitleScreen.new()
	add_child(_title)
	_title.slot_selected.connect(_on_slot_selected)

func _on_slot_selected(_slot: int) -> void:
	# GameState already loaded/created the slot; drop straight into camp.
	_show_surface()

func _show_surface() -> void:
	_clear()
	_surface = SurfaceUI.new()
	add_child(_surface)
	_surface.start_run.connect(_on_start_run)
	_surface.quit_to_title.connect(_show_title)

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
