extends Node
## Debug (autoload)
## In-game testing console. Toggle with F1 (or the ` backtick key). Lives above
## everything on its own CanvasLayer and survives the Surface<->Mine swap, so it
## works both at camp and inside a run. Every control just pokes GameState /
## GameData / the live MineController -- there is no gameplay logic here, only
## shortcuts to reach any stage of the game for testing.
##
## Nothing in this file ships in a "real" build: it is safe to strip the autoload
## line from project.godot to disable it entirely.

# --- palette (mirrors the surface UI so it doesn't look alien) ---
const C_BG := Color8(14, 11, 16)
const C_PANEL := Color8(26, 22, 32)
const C_BORDER := Color8(96, 82, 140)
const C_CARD := Color8(20, 17, 26)
const C_ACCENT := Color8(150, 130, 220)
const C_TEXT := Color8(224, 216, 240)
const C_MUTED := Color8(150, 140, 168)
const C_TITLE := Color8(190, 172, 236)
const C_GREEN := Color8(122, 198, 96)
const C_AMBER := Color8(224, 180, 90)
const C_DANGER := Color8(212, 108, 96)
const C_DARK_TXT := Color8(18, 14, 22)

var _layer: CanvasLayer
var _root: Control
var _open := false
var _status_lbl: Label
var _content: VBoxContainer

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS   # keep working even if the tree is paused
	_build()
	_set_open(false)

# ===========================================================================
# Toggle
# ===========================================================================
func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F1 or event.keycode == KEY_QUOTELEFT:
			_set_open(not _open)
			get_viewport().set_input_as_handled()

func _set_open(v: bool) -> void:
	_open = v
	_root.visible = v
	if v:
		_refresh_status()

# ===========================================================================
# Styling helpers
# ===========================================================================
func _sb(bg: Color, border: Color, bw: int, margin: int) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_border_width_all(bw)
	s.border_color = border
	s.set_corner_radius_all(0)
	s.anti_aliasing = false
	s.set_content_margin_all(margin)
	return s

func _lbl(text: String, size := 15, color := C_TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l

func _section(title: String) -> void:
	var l := _lbl(title, 15, C_TITLE)
	l.add_theme_constant_override("line_spacing", 0)
	var pad := Control.new()
	pad.custom_minimum_size = Vector2(0, 4)
	_content.add_child(pad)
	_content.add_child(l)
	var rule := Panel.new()
	rule.custom_minimum_size = Vector2(0, 2)
	rule.add_theme_stylebox_override("panel", _sb(C_BORDER, C_BORDER, 0, 0))
	_content.add_child(rule)

func _btn(text: String, cb: Callable, color := C_CARD, txt_col := C_TEXT) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 14)
	b.custom_minimum_size = Vector2(0, 30)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.add_theme_stylebox_override("normal", _sb(color, C_BORDER, 1, 5))
	b.add_theme_stylebox_override("hover", _sb(color.lightened(0.12), C_ACCENT, 1, 5))
	b.add_theme_stylebox_override("pressed", _sb(color.darkened(0.15), C_ACCENT, 1, 5))
	b.add_theme_color_override("font_color", txt_col)
	b.add_theme_color_override("font_hover_color", txt_col.lightened(0.1))
	b.pressed.connect(cb)
	return b

## A horizontal row of buttons. `items` is an Array of [label, Callable].
func _row(items: Array, color := C_CARD, txt_col := C_TEXT) -> void:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 5)
	for it in items:
		h.add_child(_btn(it[0], it[1], color, txt_col))
	_content.add_child(h)

# ===========================================================================
# Build
# ===========================================================================
func _build() -> void:
	_layer = CanvasLayer.new()
	_layer.layer = 100
	add_child(_layer)

	_root = Control.new()
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE   # only the drawer itself eats clicks
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_layer.add_child(_root)

	# Right-side drawer.
	var drawer := PanelContainer.new()
	drawer.add_theme_stylebox_override("panel", _sb(C_BG, C_BORDER, 2, 10))
	drawer.mouse_filter = Control.MOUSE_FILTER_STOP
	drawer.set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE)
	drawer.custom_minimum_size = Vector2(320, 0)
	drawer.offset_left = -336
	drawer.offset_top = 8
	drawer.offset_bottom = -8
	drawer.offset_right = -8
	_root.add_child(drawer)

	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 6)
	drawer.add_child(outer)

	# Title bar.
	var titlebar := HBoxContainer.new()
	outer.add_child(titlebar)
	titlebar.add_child(_lbl("DEBUG MENU", 18, C_ACCENT))
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	titlebar.add_child(sp)
	titlebar.add_child(_lbl("[F1]", 14, C_MUTED))

	# Live status readout.
	var statuspanel := PanelContainer.new()
	statuspanel.add_theme_stylebox_override("panel", _sb(C_PANEL, C_BORDER, 1, 8))
	outer.add_child(statuspanel)
	_status_lbl = _lbl("", 14, C_TEXT)
	statuspanel.add_child(_status_lbl)

	# Scrollable content.
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_child(scroll)
	_content = VBoxContainer.new()
	_content.add_theme_constant_override("separation", 5)
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_content)

	_build_sections()

func _build_sections() -> void:
	# --- Progression ---
	_section("PROGRESSION")
	_row([
		["+1k coins", func(): _add_money(1000)],
		["+100k", func(): _add_money(100000)],
		["+1M", func(): _add_money(1000000)],
	])
	_row([
		["+1 lvl", func(): _add_levels(1)],
		["+10 lvl", func(): _add_levels(10)],
		["+50 lvl", func(): _add_levels(50)],
	])
	_row([
		["All resources +1k", func(): _add_all_resources(1000)],
		["+10k", func(): _add_all_resources(10000)],
	])

	# --- Unlocks (jump to any biome) ---
	_section("UNLOCK DEPTH  (sets best depth)")
	var brow: Array = []
	for i in range(GameData.BIOMES.size()):
		var idx := i
		brow.append(["B%d" % (i + 1), func(): _reach_biome(idx)])
		if brow.size() == 5:
			_row(brow, C_CARD, C_GREEN)
			brow = []
	if not brow.is_empty():
		_row(brow, C_CARD, C_GREEN)

	# --- Gear ---
	_section("GEAR")
	_row([
		["Craft next pickaxe", func(): _next_pickaxe()],
		["MAX pick", func(): _max_pickaxe()],
	])
	_row([
		["+1 of every golem", func(): _add_golems(1)],
		["+5", func(): _add_golems(5)],
	])
	_row([
		["Max all upgrades/machines", func(): _max_upgrades()],
	], C_CARD, C_AMBER)

	# --- Specializations ---
	_section("SPECIALIZATION  (auto-picks 4)")
	_row([
		["Striker", func(): _fill_spec("striker")],
		["Warden", func(): _fill_spec("stonewarden")],
		["Engineer", func(): _fill_spec("engineer")],
	], C_CARD, C_GREEN)
	_row([
		["Clear specialization", func(): _clear_spec()],
	])

	# --- One-shot god button ---
	_section("SHORTCUTS")
	_row([
		["UNLOCK EVERYTHING", func(): _unlock_everything()],
	], C_ACCENT.darkened(0.3), C_TITLE)

	# --- Run controls (only meaningful inside a mine) ---
	_section("CURRENT RUN")
	_row([
		["+30s", func(): _add_time(30.0)],
		["Freeze timer", func(): _add_time(99999.0)],
		["End run", func(): _end_run()],
	])
	_row([
		["God pick (1-shot)", func(): _god_pick()],
		["Reveal ores", func(): _reveal_ores()],
	])
	_row([
		["Speed x1", func(): _time_scale(1.0)],
		["x2", func(): _time_scale(2.0)],
		["x4", func(): _time_scale(4.0)],
	])

	# --- Danger ---
	_section("DANGER")
	_row([
		["To Title", func(): _to_title()],
		["To Surface", func(): _to_surface()],
	])
	_row([
		["RESET ALL PROGRESS", func(): _reset()],
	], C_DANGER.darkened(0.35), C_DANGER)

# ===========================================================================
# Node lookups (the active screens live under Main, rebuilt each transition)
# ===========================================================================
func _find(type_check: Callable, node: Node = null) -> Node:
	if node == null:
		node = get_tree().root
	if type_check.call(node):
		return node
	for c in node.get_children():
		var found := _find(type_check, c)
		if found != null:
			return found
	return null

func _surface() -> SurfaceUI:
	var n := _find(func(x): return x is SurfaceUI)
	return n as SurfaceUI

func _mine() -> MineController:
	var n := _find(func(x): return x is MineController)
	return n as MineController

func _title() -> TitleScreen:
	var n := _find(func(x): return x is TitleScreen)
	return n as TitleScreen

func _main() -> Node:
	# Main.gd is the script on the main-scene root; find it by its method set.
	var n := _find(func(x): return x.has_method("_show_surface") and x.has_method("_on_start_run"))
	return n

## Push state changes into whatever screen is showing + persist + update readout.
func _after_change() -> void:
	var s := _surface()
	if s != null:
		s.refresh()
	GameState.save_game()
	_refresh_status()

func _refresh_status() -> void:
	if _status_lbl == null:
		return
	var lp := GameState.level_progress()
	var md := GameState.max_depth
	var bi := GameData.biome_index_for_row(md)
	var where := "MINE" if _mine() != null else ("TITLE" if _title() != null else "SURFACE")
	var slot := ("slot %d" % GameState.current_slot) if GameState.current_slot > 0 else "no slot"
	_status_lbl.text = "%s (%s)   ·   Lv %d   ·   %d SP free\nDepth %dm  (B%d %s)\nCoins %d" % [
		where, slot, lp["level"], GameState.skill_points_available(),
		md, bi + 1, GameData.BIOMES[bi]["name"], GameState.money,
	]

# ===========================================================================
# Progression actions
# ===========================================================================
func _add_money(n: int) -> void:
	GameState.add_money(n)
	_after_change()

## Advance the player exactly `n` levels by topping up EXP to the next threshold.
func _add_levels(n: int) -> void:
	for i in range(n):
		var lp := GameState.level_progress()
		GameState.add_exp(int(lp["need"]) - int(lp["into"]))
	_after_change()

func _add_all_resources(n: int) -> void:
	for id in GameData.RESOURCES:
		GameState.add_resource(id, n)
	_after_change()

# ===========================================================================
# Unlock actions
# ===========================================================================
## Set best depth to the start of biome `idx` (unlocks its pickaxes/golems and
## lets the descent screen start there). Only ever raises max_depth.
func _reach_biome(idx: int) -> void:
	var b: Dictionary = GameData.BIOMES[idx]
	var depth := int(b["depth_lo"]) + 1
	GameState.max_depth = maxi(GameState.max_depth, depth)
	# Make sure a transport exists so the descent screen can actually start deep.
	if not GameState.owns_transport():
		GameState.upgrade_levels["buy_drillevator"] = 1
	_after_change()

# ===========================================================================
# Gear actions
# ===========================================================================
func _next_pickaxe() -> void:
	var nt := GameState.pickaxe_tier + 1
	if nt < GameData.PICKAXES.size():
		GameState.pickaxe_tier = nt
	_after_change()

func _max_pickaxe() -> void:
	GameState.pickaxe_tier = GameData.PICKAXES.size() - 1
	GameState.pickaxe_upgrade_levels[GameState.pickaxe_tier] = GameData.PICKAXE_UPGRADE_MULT.size()
	_after_change()

func _add_golems(n: int) -> void:
	for tier in range(1, GameData.GOLEMS.size() + 1):
		GameState.golems[tier] = GameState.golem_owned(tier) + n
	_after_change()

func _max_upgrades() -> void:
	for id in GameData.UPGRADES:
		GameState.upgrade_levels[id] = int(GameData.UPGRADES[id].get("max_level", 1))
	_after_change()

## Grant enough depth for 4 spec points, then auto-pick the first 4 skills of `spec`.
func _fill_spec(spec: String) -> void:
	GameState.max_depth = maxi(GameState.max_depth, int(GameData.BIOMES[8]["depth_lo"]) + 1)
	GameState.clear_specialization()
	var skills: Array = GameData.SPECIALIZATIONS[spec]["skills"]
	for i in range(GameData.SPEC_MAX_PICKS):
		GameState.buy_spec_skill(skills[i]["id"])
	_after_change()

func _clear_spec() -> void:
	GameState.clear_specialization()
	_after_change()

func _unlock_everything() -> void:
	GameState.max_depth = maxi(GameState.max_depth, int(GameData.BIOMES[-1]["depth_lo"]) + 1)
	GameState.add_money(10000000)
	_add_levels(50)                       # calls _after_change
	_add_all_resources(100000)            # calls _after_change
	_max_pickaxe()
	_add_golems(5)
	_max_upgrades()

# ===========================================================================
# Run actions (need a live MineController)
# ===========================================================================
func _add_time(t: float) -> void:
	var m := _mine()
	if m != null:
		m.time_left += t

func _end_run() -> void:
	var m := _mine()
	if m != null and m.running:
		m._end_run()

## Make the pickaxe one-shot any block for the rest of this run.
func _god_pick() -> void:
	var m := _mine()
	if m != null:
		m.stats["click_damage"] = 1.0e9
		m.stats["instant_chance"] = 1.0

func _reveal_ores() -> void:
	var m := _mine()
	if m == null:
		return
	for pos in m.blocks:
		var tb = m.blocks[pos]
		if is_instance_valid(tb) and tb.tile.get("type", "filler") == "resource":
			tb.set_scanned(true)

func _time_scale(s: float) -> void:
	Engine.time_scale = s

# ===========================================================================
# Danger / navigation
# ===========================================================================
func _to_title() -> void:
	Engine.time_scale = 1.0
	GameState.save_game()
	var main := _main()
	if main != null:
		main._show_title()
	_refresh_status()

func _to_surface() -> void:
	Engine.time_scale = 1.0
	var m := _mine()
	if m != null and m.running:
		m._end_run()   # ends the run cleanly -> Main returns to the surface
		return
	var main := _main()
	if main != null:
		main._show_surface()
	_refresh_status()

func _reset() -> void:
	Engine.time_scale = 1.0
	GameState.reset_progress()
	var main := _main()
	if main != null:
		main._show_surface()
	_refresh_status()
