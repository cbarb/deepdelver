class_name HUD
extends CanvasLayer
## In-run heads-up display. Built entirely in code. All controls ignore the
## mouse so world clicks pass through to the mine.

var _timer_lbl: Label
var _depth_lbl: Label
var _totals_lbl: Label
var _run_lbl: Label
var _tile_name: Label
var _tile_bar: ProgressBar
var _tile_state: Label
var _cd_bar: ProgressBar
var _flash_lbl: Label
var _flash_time := 0.0
var _placements: Array = []      # {c, corner, margin} pinned in _apply_placements()
var _cursor_ring: CursorRing

func _ready() -> void:
	layer = 10
	_build()
	_apply_placements()
	_cursor_ring = CursorRing.new()
	add_child(_cursor_ring)
	_cursor_ring.set_pickaxe(GameData.get_pickaxe_texture(GameState.pickaxe_tier))
	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN     # hide OS cursor; we draw the pickaxe
	set_process(true)

func _exit_tree() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE    # restore normal cursor on the surface

func _panel(corner: int, min_width: float, margin: float) -> PanelContainer:
	var p := PanelContainer.new()
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0.5)
	sb.set_corner_radius_all(8)
	sb.set_content_margin_all(10)
	p.add_theme_stylebox_override("panel", sb)
	p.custom_minimum_size = Vector2(min_width, 0)
	add_child(p)
	_placements.append({"c": p, "corner": corner, "margin": margin})
	return p

## Pin each registered control to its screen corner once its content-driven
## minimum size is known. set_anchors_and_offsets_preset also sets offsets, so
## the panels actually sit where intended (unlike set_anchors_preset alone).
func _apply_placements() -> void:
	for pl in _placements:
		var c: Control = pl["c"]
		c.size = c.get_combined_minimum_size()
		c.set_anchors_and_offsets_preset(pl["corner"], Control.PRESET_MODE_KEEP_SIZE, int(pl["margin"]))

func _label(size := 18, color := Color.WHITE) -> Label:
	var l := Label.new()
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l

func _build() -> void:
	# Top-left: timer + depth
	var tl := _panel(Control.PRESET_TOP_LEFT, 220, 14)
	var vb := VBoxContainer.new()
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tl.add_child(vb)
	_timer_lbl = _label(40, Color8(255, 230, 120))
	_depth_lbl = _label(22)
	vb.add_child(_timer_lbl)
	vb.add_child(_depth_lbl)

	# Top-right: totals
	var tr := _panel(Control.PRESET_TOP_RIGHT, 240, 14)
	_totals_lbl = _label(18)
	_totals_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	tr.add_child(_totals_lbl)

	# Left-mid: resources collected this run
	var ml := _panel(Control.PRESET_CENTER_LEFT, 220, 14)
	var mlv := VBoxContainer.new()
	mlv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ml.add_child(mlv)
	var hdr := _label(16, Color8(180, 200, 255))
	hdr.text = "This run"
	mlv.add_child(hdr)
	_run_lbl = _label(16)
	mlv.add_child(_run_lbl)

	# Bottom-center: selected tile
	var bc := _panel(Control.PRESET_CENTER_BOTTOM, 340, 24)
	var bcv := VBoxContainer.new()
	bcv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bcv.alignment = BoxContainer.ALIGNMENT_CENTER
	bc.add_child(bcv)
	_tile_name = _label(20)
	_tile_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bcv.add_child(_tile_name)
	_tile_bar = ProgressBar.new()
	_tile_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tile_bar.custom_minimum_size = Vector2(300, 16)
	_tile_bar.max_value = 1.0
	_tile_bar.show_percentage = false
	bcv.add_child(_tile_bar)
	_tile_state = _label(15)
	_tile_state.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bcv.add_child(_tile_state)

	# Bottom bar: click cooldown
	var cd := _panel(Control.PRESET_BOTTOM_LEFT, 220, 14)
	var cdv := VBoxContainer.new()
	cdv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cd.add_child(cdv)
	var cdl := _label(13, Color8(180, 220, 255))
	cdl.text = "Pickaxe ready"
	cdv.add_child(cdl)
	_cd_bar = ProgressBar.new()
	_cd_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cd_bar.custom_minimum_size = Vector2(200, 12)
	_cd_bar.max_value = 1.0
	_cd_bar.show_percentage = false
	cdv.add_child(_cd_bar)

	# Flash message (center-top)
	_flash_lbl = _label(26, Color8(255, 120, 120))
	_flash_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flash_lbl.custom_minimum_size = Vector2(400, 0)
	_flash_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_flash_lbl)
	_placements.append({"c": _flash_lbl, "corner": Control.PRESET_CENTER_TOP, "margin": 90})

func _process(delta: float) -> void:
	if _flash_time > 0.0:
		_flash_time -= delta
		_flash_lbl.modulate.a = clampf(_flash_time / 0.9, 0.0, 1.0)
		if _flash_time <= 0.0:
			_flash_lbl.text = ""

func flash(text: String, color: Color) -> void:
	_flash_lbl.text = text
	_flash_lbl.add_theme_color_override("font_color", color)
	_flash_lbl.modulate.a = 1.0
	_flash_time = 0.9

func update_hud(d: Dictionary) -> void:
	_timer_lbl.text = "%0.1fs" % maxf(0.0, d["time"])
	_depth_lbl.text = "Depth: %d m\n%s" % [d["depth"], GameData.biome_for_row(int(d["depth"]))["name"]]

	var lp := GameState.level_progress()
	_totals_lbl.text = "Coins: %d\nLevel %d  (%d/%d)" % [d["money"], lp["level"], lp["into"], lp["need"]]

	var run_txt := ""
	if d["run_resources"].is_empty():
		run_txt = "(nothing yet)"
	else:
		for res_id in d["run_resources"]:
			run_txt += "%s: %d\n" % [GameData.resource_name(res_id), d["run_resources"][res_id]]
	_run_lbl.text = run_txt

	if d["tile_name"] == "":
		_tile_name.text = "-"
		_tile_bar.value = 1.0
		_tile_state.text = "Hover a tile"
	else:
		_tile_name.text = d["tile_name"]
		_tile_bar.value = d["tile_frac"]
		match int(d["tile_state"]):
			1:
				_tile_state.text = "Mineable"
				_tile_state.add_theme_color_override("font_color", Color8(120, 255, 140))
			2:
				_tile_state.text = "Blocked (surrounded)"
				_tile_state.add_theme_color_override("font_color", Color8(255, 110, 110))
			_:
				_tile_state.text = ""

	var maxcd: float = maxf(0.001, d["max_cooldown"])
	var readiness := 1.0 - clampf(d["cooldown"] / maxcd, 0.0, 1.0)
	_cd_bar.value = readiness
	if _cursor_ring:
		_cursor_ring.set_progress(readiness)
