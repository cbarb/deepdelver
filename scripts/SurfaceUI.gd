class_name SurfaceUI
extends Control
## The surface camp: header (level/EXP/coins), a Character panel + Stockpile, a
## tabbed Crafting Bench (Manual / Golems / Machine / Carts), a Skill Book +
## Crusher + Last Run column, and the footer (Elevator toggle + Start Mining).
## Rebuilt from data each refresh(). Built entirely from code-styled Controls.

signal start_run
signal quit_to_title

# --- palette (dark umber/brown; gold reserved for coins/CTAs, not everywhere) ---
const C_BG := Color8(18, 14, 10)
const C_PANEL := Color8(33, 25, 16)
const C_PANEL_BORDER := Color8(74, 54, 30)
const C_CARD := Color8(27, 20, 13)
const C_CARD_BORDER := Color8(58, 43, 25)
const C_AMBER := Color8(196, 148, 60)      # deeper gold: coins, primary buttons, active tab
const C_TEXT := Color8(222, 208, 182)
const C_MUTED := Color8(136, 118, 94)
const C_TITLE := Color8(202, 174, 126)     # tan section headings (not bright yellow)
const C_NEW := Color8(120, 190, 108)
const C_GREEN := Color8(122, 198, 96)
const C_BLUE := Color8(140, 175, 220)      # machine / transport accent
const C_PURPLE_BG := Color8(38, 32, 56)
const C_PURPLE_BORDER := Color8(106, 92, 170)
const C_PURPLE_TXT := Color8(182, 170, 226)
const C_DANGER := Color8(198, 112, 92)
const C_DARK_TXT := Color8(26, 18, 8)

const TABS := ["Manual", "Golems", "Machine", "Carts"]
# Which UPGRADE categories show under each bench tab.
const TAB_CATEGORIES := {
	"Manual": ["Pickaxe", "Resources"],
	"Golems": ["Golems"],
	"Machine": ["Machinery"],
	"Carts": ["Transport"],
}

# Blocky pixel display font, used only for big header/title text. Body text uses
# the project-wide VT323 (set in project.godot).
var _header_font: Font = load("res://assets/fonts/Press_Start_2P/PressStart2P-Regular.ttf")

var _active_tab := "Manual"

# refresh-updated references
var _lv_lbl: Label
var _exp_bar: ProgressBar
var _exp_range_lbl: Label
var _coins_lbl: Label
var _char_body: VBoxContainer
var _stock_grid: GridContainer
var _bench_grid: GridContainer
var _tab_btns := {}
var _skill_body: VBoxContainer
var _crusher_body: VBoxContainer
var _lastrun_body: VBoxContainer

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build()
	refresh()

# ===========================================================================
# Small styling helpers
# ===========================================================================
func _sb(bg: Color, border: Color, bw: int, _radius: int, margin: int) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_border_width_all(bw)
	s.border_color = border
	s.set_corner_radius_all(0)      # hard square corners -> pixel-art frames
	s.anti_aliasing = false         # crisp edges (no smoothing)
	s.set_content_margin_all(margin)
	return s

func _lbl(text: String, size := 18, color := C_TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l

## A blocky header/title label rendered in Press Start 2P. Press Start is much
## wider and reads larger than VT323, so header sizes here are smaller numbers.
func _hlbl(text: String, size := 13, color := C_TITLE) -> Label:
	var l := _lbl(text, size, color)
	if _header_font != null:
		l.add_theme_font_override("font", _header_font)
	return l

func _wrap_lbl(text: String, size := 18, color := C_MUTED) -> Label:
	var l := _lbl(text, size, color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return l

func _panel(bg := C_PANEL, border := C_PANEL_BORDER, bw := 2, margin := 12) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", _sb(bg, border, bw, 6, margin))
	return p

func _clear(n: Node) -> void:
	for c in n.get_children():
		n.remove_child(c)
		c.queue_free()

func _style_button(b: Button, bg: Color, txt: Color, border: Color, bw: int) -> void:
	b.focus_mode = Control.FOCUS_NONE
	if _header_font != null:
		b.add_theme_font_override("font", _header_font)   # blocky Press Start on all buttons
	b.add_theme_stylebox_override("normal", _sb(bg, border, bw, 5, 8))
	b.add_theme_stylebox_override("hover", _sb(bg.lightened(0.10), border, bw, 5, 8))
	b.add_theme_stylebox_override("pressed", _sb(bg.darkened(0.12), border, bw, 5, 8))
	b.add_theme_stylebox_override("disabled", _sb(bg.darkened(0.28), border.darkened(0.2), bw, 5, 8))
	b.add_theme_color_override("font_color", txt)
	b.add_theme_color_override("font_hover_color", txt.lightened(0.1))
	b.add_theme_color_override("font_pressed_color", txt)
	b.add_theme_color_override("font_disabled_color", txt.darkened(0.35))

## An item's pack icon at `px` size, falling back to a colored swatch if the
## item has no icon mapped.
func _item_icon(id: String, px: int, col: Color) -> Control:
	var tex := GameData.item_icon(id)
	if tex != null:
		var r := TextureRect.new()
		r.texture = tex
		r.custom_minimum_size = Vector2(px, px)
		r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		r.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		return r
	var sq := Panel.new()
	sq.custom_minimum_size = Vector2(px, px)
	sq.add_theme_stylebox_override("panel", _sb(col, col.darkened(0.35), 1, 2, 0))
	return sq

## A small item icon + amount chip.
func _chip(res: String, amount: int) -> Control:
	var col: Color = C_AMBER if res == "coins" else GameData.resource_color(res)
	var rname := "Coins" if res == "coins" else GameData.resource_name(res)
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 5)
	var icon := _item_icon(res, 20, col)
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	box.add_child(icon)
	box.add_child(_lbl("%s %s" % [GameData.fmt(amount), rname], 17, C_TEXT))
	return box

# ===========================================================================
# Build (static skeleton)
# ===========================================================================
func _build() -> void:
	var bg := ColorRect.new()
	bg.color = C_BG
	add_child(bg)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var root := MarginContainer.new()
	add_child(root)
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for m in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		root.add_theme_constant_override(m, 16)

	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 12)
	root.add_child(outer)

	_build_header(outer)

	var cols := HBoxContainer.new()
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cols.add_theme_constant_override("separation", 14)
	outer.add_child(cols)
	_build_left(cols)
	_build_center(cols)
	_build_right(cols)

	_build_footer(outer)

func _build_header(outer: VBoxContainer) -> void:
	var bar := _panel(C_PANEL, C_PANEL_BORDER, 2, 12)
	outer.add_child(bar)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 12)
	bar.add_child(hb)
	hb.add_child(_hlbl("DEEP DELVER", 22, C_TITLE))
	var sub := _lbl("Surface Camp", 18, C_MUTED)
	sub.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hb.add_child(sub)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(spacer)

	# LV chip
	var lvchip := _panel(Color8(20, 16, 10), C_PANEL_BORDER, 1, 8)
	lvchip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hb.add_child(lvchip)
	var lvrow := HBoxContainer.new()
	lvrow.add_theme_constant_override("separation", 10)
	lvchip.add_child(lvrow)
	_lv_lbl = _lbl("LV 1", 20, C_GREEN)
	lvrow.add_child(_lv_lbl)
	var expcol := VBoxContainer.new()
	expcol.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	lvrow.add_child(expcol)
	_exp_range_lbl = _lbl("EXP  0 / 0", 16, C_MUTED)
	expcol.add_child(_exp_range_lbl)
	_exp_bar = ProgressBar.new()
	_exp_bar.show_percentage = false
	_exp_bar.custom_minimum_size = Vector2(180, 12)
	_exp_bar.add_theme_stylebox_override("background", _sb(Color8(18, 14, 9), C_PANEL_BORDER, 1, 3, 0))
	var fill := _sb(C_GREEN, C_GREEN, 0, 3, 0)
	_exp_bar.add_theme_stylebox_override("fill", fill)
	expcol.add_child(_exp_bar)

	# Coins chip
	var coinchip := _panel(Color8(20, 16, 10), C_AMBER.darkened(0.15), 1, 8)
	coinchip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hb.add_child(coinchip)
	var crow := HBoxContainer.new()
	crow.add_theme_constant_override("separation", 6)
	coinchip.add_child(crow)
	var dot := _item_icon("coins", 22, C_AMBER)
	dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	crow.add_child(dot)
	_coins_lbl = _lbl("0", 20, C_AMBER)
	crow.add_child(_coins_lbl)

	# Menu (return to the title screen; progress is already saved per-action).
	var menu_btn := Button.new()
	menu_btn.text = "MENU"
	menu_btn.add_theme_font_size_override("font_size", 11)
	menu_btn.custom_minimum_size = Vector2(96, 40)
	menu_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_style_button(menu_btn, C_CARD, C_TEXT, C_CARD_BORDER, 1)
	menu_btn.pressed.connect(_on_menu)
	hb.add_child(menu_btn)

func _build_left(cols: HBoxContainer) -> void:
	var col := VBoxContainer.new()
	col.custom_minimum_size = Vector2(330, 0)
	col.add_theme_constant_override("separation", 12)
	cols.add_child(col)

	# Character panel
	var char_panel := _panel()
	col.add_child(char_panel)
	var cv := VBoxContainer.new()
	cv.add_theme_constant_override("separation", 8)
	char_panel.add_child(cv)
	cv.add_child(_hlbl("CHARACTER", 13, C_TITLE))
	_char_body = VBoxContainer.new()
	_char_body.add_theme_constant_override("separation", 8)
	cv.add_child(_char_body)

	# Stockpile panel
	var stock_panel := _panel()
	stock_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(stock_panel)
	var sv := VBoxContainer.new()
	sv.add_theme_constant_override("separation", 8)
	stock_panel.add_child(sv)
	var srow := HBoxContainer.new()
	sv.add_child(srow)
	srow.add_child(_hlbl("STOCKPILE", 13, C_TITLE))
	var ssp := Control.new()
	ssp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	srow.add_child(ssp)
	srow.add_child(_lbl("chest · kept between runs", 16, C_MUTED))
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sv.add_child(scroll)
	_stock_grid = GridContainer.new()
	_stock_grid.columns = 3
	_stock_grid.add_theme_constant_override("h_separation", 10)
	_stock_grid.add_theme_constant_override("v_separation", 10)
	_stock_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_stock_grid)

func _build_center(cols: HBoxContainer) -> void:
	var panel := _panel()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	panel.add_child(v)

	# Header row: title + tab buttons
	var hdr := HBoxContainer.new()
	v.add_child(hdr)
	hdr.add_child(_hlbl("CRAFTING BENCH", 15, C_TITLE))
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hdr.add_child(sp)
	var tabrow := HBoxContainer.new()
	tabrow.add_theme_constant_override("separation", 6)
	hdr.add_child(tabrow)
	for t in TABS:
		var b := Button.new()
		b.text = t.to_upper()
		b.add_theme_font_size_override("font_size", 11)
		b.pressed.connect(_on_tab.bind(t))
		tabrow.add_child(b)
		_tab_btns[t] = b

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(scroll)
	_bench_grid = GridContainer.new()
	_bench_grid.columns = 3
	_bench_grid.add_theme_constant_override("h_separation", 12)
	_bench_grid.add_theme_constant_override("v_separation", 12)
	_bench_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_bench_grid)

func _build_right(cols: HBoxContainer) -> void:
	var col := VBoxContainer.new()
	col.custom_minimum_size = Vector2(300, 0)
	col.add_theme_constant_override("separation", 12)
	cols.add_child(col)

	# Skill Book (purple)
	var sk := _panel(C_PURPLE_BG, C_PURPLE_BORDER, 2, 12)
	col.add_child(sk)
	var skv := VBoxContainer.new()
	skv.add_theme_constant_override("separation", 6)
	sk.add_child(skv)
	skv.add_child(_hlbl("SKILL BOOK", 13, C_PURPLE_TXT))
	_skill_body = VBoxContainer.new()
	_skill_body.add_theme_constant_override("separation", 6)
	skv.add_child(_skill_body)

	# Crusher
	var cr := _panel()
	col.add_child(cr)
	var crv := VBoxContainer.new()
	crv.add_theme_constant_override("separation", 6)
	cr.add_child(crv)
	crv.add_child(_hlbl("CRUSHER", 13, C_TITLE))
	_crusher_body = VBoxContainer.new()
	_crusher_body.add_theme_constant_override("separation", 6)
	crv.add_child(_crusher_body)

	# Last Run
	var lr := _panel()
	lr.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(lr)
	var lrv := VBoxContainer.new()
	lrv.add_theme_constant_override("separation", 6)
	lrv.size_flags_vertical = Control.SIZE_EXPAND_FILL
	lr.add_child(lrv)
	lrv.add_child(_hlbl("LAST RUN", 13, C_TITLE))
	# Scroll the body so a long resource list can't overflow the panel/other UI.
	var lrscroll := ScrollContainer.new()
	lrscroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	lrscroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	lrv.add_child(lrscroll)
	_lastrun_body = VBoxContainer.new()
	_lastrun_body.add_theme_constant_override("separation", 4)
	_lastrun_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lrscroll.add_child(_lastrun_body)

func _build_footer(outer: VBoxContainer) -> void:
	var bar := _panel(C_PANEL, C_PANEL_BORDER, 2, 12)
	outer.add_child(bar)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 12)
	bar.add_child(hb)

	# Hint: depth is now chosen on the descent screen after pressing START.
	var tcol := VBoxContainer.new()
	tcol.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hb.add_child(tcol)
	tcol.add_child(_lbl("Press START to choose your depth", 16, C_MUTED))

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(spacer)

	var rt := VBoxContainer.new()
	rt.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hb.add_child(rt)
	rt.add_child(_lbl("RUN TIME", 16, C_MUTED))
	rt.add_child(_lbl("60s", 22, C_TEXT))

	var start_btn := Button.new()
	start_btn.text = "START MINING"
	start_btn.add_theme_font_size_override("font_size", 18)
	start_btn.custom_minimum_size = Vector2(320, 62)
	_style_button(start_btn, C_AMBER, C_DARK_TXT, C_AMBER.darkened(0.25), 2)
	start_btn.pressed.connect(_open_depth_select)
	hb.add_child(start_btn)

# ===========================================================================
# Refresh (data -> UI)
# ===========================================================================
func refresh() -> void:
	_fill_header()
	_fill_character()
	_fill_stockpile()
	_update_tabs()
	_fill_bench()
	_fill_skills()
	_fill_crusher()
	_fill_lastrun()

func _fill_header() -> void:
	var lp := GameState.level_progress()
	_lv_lbl.text = "LV %d" % lp["level"]
	_exp_range_lbl.text = "EXP  %s / %s" % [GameData.fmt(lp["into"]), GameData.fmt(lp["need"])]
	_exp_bar.max_value = maxf(1.0, float(lp["need"]))
	_exp_bar.value = float(lp["into"])
	_coins_lbl.text = GameData.fmt(GameState.money)

func _stat_cell(cell_name: String, value: String) -> PanelContainer:
	var p := _panel(C_CARD, C_CARD_BORDER, 1, 8)
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var v := VBoxContainer.new()
	p.add_child(v)
	v.add_child(_lbl(cell_name.to_upper(), 16, C_MUTED))
	v.add_child(_lbl(value, 20, C_TEXT))
	return p

func _fill_character() -> void:
	_clear(_char_body)
	var st := GameState.get_effective_stats()
	var cur := GameState.current_pickaxe()

	# Equipped row: pickaxe icon + name
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 10)
	_char_body.add_child(top)
	var tex := GameData.get_pickaxe_texture(GameState.pickaxe_tier)
	if tex != null:
		var icon := TextureRect.new()
		icon.texture = tex
		icon.custom_minimum_size = Vector2(44, 44)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		top.add_child(icon)
	var namecol := VBoxContainer.new()
	top.add_child(namecol)
	namecol.add_child(_lbl("EQUIPPED", 16, C_MUTED))
	namecol.add_child(_lbl(cur["name"], 20, C_TITLE))

	# Stat grid (2 columns)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	_char_body.add_child(grid)
	grid.add_child(_stat_cell("Click Dmg", GameData.fmt(st["click_damage"])))
	grid.add_child(_stat_cell("Cooldown", "%.2fs" % st["click_cooldown"]))
	grid.add_child(_stat_cell("Yield", "x%.2f" % st["resource_mult"]))
	grid.add_child(_stat_cell("EXP", "x%.2f" % st["exp_mult"]))
	grid.add_child(_stat_cell("Crit", "%d%% ·x%.1f" % [int(st["crit_chance"] * 100), st["crit_damage"]]))
	grid.add_child(_stat_cell("Golems", "%d" % int(st["ai_count"])))
	grid.add_child(_stat_cell("Drills", "%d" % int(st["drill_count"])))
	grid.add_child(_stat_cell("Crusher", "Lv %d" % GameState.crush_rate()))

func _stock_tile(id: String, count: int) -> VBoxContainer:
	var is_coin := id == "coins"
	var col: Color = C_AMBER if is_coin else GameData.resource_color(id)
	var nm := "Coins" if is_coin else GameData.resource_name(id)
	var tex := GameData.item_icon(id)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	var sq := Panel.new()
	sq.custom_minimum_size = Vector2(70, 60)
	sq.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# With an icon, use a dim backdrop so the icon reads; otherwise the old bright swatch.
	if tex != null:
		sq.add_theme_stylebox_override("panel", _sb(col.darkened(0.6), col.darkened(0.25), 2, 4, 2))
		var ic := TextureRect.new()
		ic.texture = tex
		ic.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		ic.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		ic.offset_left = 6; ic.offset_top = 3; ic.offset_right = -6; ic.offset_bottom = -3
		sq.add_child(ic)
	else:
		sq.add_theme_stylebox_override("panel", _sb(col, col.darkened(0.35), 2, 4, 2))
	var cl := _lbl(GameData.fmt(count), 18, Color.WHITE)
	cl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	cl.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	cl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	cl.offset_right = -4
	cl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	cl.add_theme_constant_override("outline_size", 6)
	sq.add_child(cl)
	v.add_child(sq)
	var nl := _lbl(nm, 17, C_MUTED)
	nl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(nl)
	return v

func _fill_stockpile() -> void:
	_clear(_stock_grid)
	_stock_grid.add_child(_stock_tile("coins", GameState.money))
	for id in GameData.RESOURCES:
		var amt := int(GameState.resources.get(id, 0))
		if amt > 0:
			_stock_grid.add_child(_stock_tile(id, amt))

# ===========================================================================
# Crafting Bench (tabs + cards)
# ===========================================================================
func _on_tab(t: String) -> void:
	_active_tab = t
	_update_tabs()
	_fill_bench()

func _update_tabs() -> void:
	for t in _tab_btns:
		var b: Button = _tab_btns[t]
		if t == _active_tab:
			_style_button(b, C_AMBER, C_DARK_TXT, C_AMBER.darkened(0.25), 2)
		else:
			_style_button(b, C_CARD, C_TEXT, C_CARD_BORDER, 1)

## Build one bench card. `cost` is a resource->amount dict (may be empty).
## action_kind: "craft" | "need" | "max" | "locked".
func _make_card(icon_col: Color, title: String, badge: String, badge_col: Color, desc: String, cost: Dictionary, action_text: String, action_kind: String, cb: Callable) -> void:
	var card := _panel(C_CARD, C_CARD_BORDER, 2, 12)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.custom_minimum_size = Vector2(240, 0)
	if action_kind == "craft":
		card.add_theme_stylebox_override("panel", _sb(C_CARD, C_AMBER.darkened(0.15), 2, 6, 12))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	card.add_child(v)

	# Title row: icon + name + badge
	var trow := HBoxContainer.new()
	trow.add_theme_constant_override("separation", 8)
	v.add_child(trow)
	var icon := Panel.new()
	icon.custom_minimum_size = Vector2(28, 28)
	icon.add_theme_stylebox_override("panel", _sb(icon_col, icon_col.darkened(0.3), 1, 4, 0))
	trow.add_child(icon)
	var nl := _hlbl(title, 12, icon_col)   # blocky title, tinted by category (blue machine, green golem, ...)
	nl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART   # Press Start is wide -> let long names wrap
	nl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	trow.add_child(nl)
	if badge != "":
		var bp := _panel(badge_col.darkened(0.55), badge_col, 1, 4)
		bp.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		bp.add_child(_lbl(badge, 15, badge_col))
		trow.add_child(bp)

	v.add_child(_wrap_lbl(desc, 18, C_MUTED))

	if not cost.is_empty():
		var chips := HFlowContainer.new()
		chips.add_theme_constant_override("h_separation", 8)
		chips.add_theme_constant_override("v_separation", 4)
		v.add_child(chips)
		for res in cost:
			chips.add_child(_chip(res, int(cost[res])))

	var btn := Button.new()
	btn.text = action_text
	btn.add_theme_font_size_override("font_size", 12)
	btn.custom_minimum_size = Vector2(0, 44)
	match action_kind:
		"craft":
			_style_button(btn, C_AMBER, C_DARK_TXT, C_AMBER.darkened(0.25), 2)
			btn.pressed.connect(cb)
		"max":
			_style_button(btn, C_CARD, C_GREEN, C_GREEN.darkened(0.4), 1)
			btn.disabled = true
		_:   # "need" / "locked"
			_style_button(btn, C_CARD, C_MUTED, C_CARD_BORDER, 1)
			btn.disabled = true
	v.add_child(btn)
	_bench_grid.add_child(card)

func _fill_bench() -> void:
	_clear(_bench_grid)
	match _active_tab:
		"Manual":
			_add_pickaxe_cards()
			_add_category_cards(["Pickaxe", "Resources"])
		"Golems":
			_add_golem_cards()
			_add_category_cards(["Golems"])
		"Machine":
			_add_category_cards(["Machinery"])
		"Carts":
			_add_category_cards(["Transport"])

func _add_category_cards(cats: Array) -> void:
	for id in GameData.UPGRADE_ORDER:
		var def: Dictionary = GameData.UPGRADES[id]
		if not cats.has(def["category"]):
			continue
		var lvl := GameState.upgrade_level(id)
		var badge := ("Lv %d" % lvl) if lvl > 0 else "NEW"
		var badge_col: Color = C_TITLE if lvl > 0 else C_NEW
		if GameState.is_upgrade_maxed(id):
			_make_card(C_MUTED, def["name"], "MAX Lv%d" % lvl, C_GREEN, def["desc"], {},
				"MAXED", "max", Callable())
			continue
		var cost := GameState.upgrade_cost(id)
		var afford := GameState.can_afford(cost)
		_make_card(_cat_color(def["category"]), def["name"], badge, badge_col, def["desc"], cost,
			"CRAFT" if afford else "NEED MORE", "craft" if afford else "need",
			_on_buy_upgrade.bind(id))

func _cat_color(cat: String) -> Color:
	match cat:
		"Pickaxe": return C_TITLE
		"Resources": return Color8(190, 160, 100)
		"Golems": return C_GREEN
		"Machinery": return C_BLUE
		"Transport": return C_BLUE
	return C_MUTED

func _add_pickaxe_cards() -> void:
	var cur: Dictionary = GameState.current_pickaxe()
	var tier: int = GameState.pickaxe_tier
	var lvl: int = GameState.pickaxe_upgrade_level(tier)

	# Craft next tier
	var nxt: Dictionary = GameState.next_pickaxe()
	if not nxt.is_empty():
		if not GameState.pickaxe_unlocked(nxt):
			var bname: String = GameData.BIOMES[int(nxt["biome"])]["name"]
			_make_card(C_AMBER, "Craft %s" % nxt["name"], "LOCKED", C_DANGER,
				"Reach %s to unlock (base dmg %d)." % [bname, int(nxt["base_damage"])], {},
				"LOCKED", "locked", Callable())
		else:
			var afford := GameState.can_afford(nxt["cost"])
			_make_card(C_AMBER, "Craft %s" % nxt["name"], "NEW", C_NEW,
				"%s (base dmg %d)." % [nxt.get("desc", ""), int(nxt["base_damage"])], nxt["cost"],
				"CRAFT" if afford else "NEED MORE", "craft" if afford else "need", _on_buy_pickaxe)

	# Upgrade equipped pickaxe
	if GameState.is_pickaxe_upgrade_maxed(tier):
		_make_card(C_AMBER, "Upgrade %s" % cur["name"], "MAX Lv%d" % lvl, C_GREEN,
			"This pickaxe is fully upgraded.", {}, "MAXED", "max", Callable())
	else:
		var ucost: Dictionary = GameState.pickaxe_upgrade_cost(tier)
		var next_mult: float = float(GameData.PICKAXE_UPGRADE_MULT[lvl])
		var afford := GameState.can_afford(ucost)
		_make_card(C_AMBER, "Upgrade %s" % cur["name"], "Lv %d" % lvl, C_AMBER,
			"Raise damage to x%.2f (Lv %d)." % [next_mult, lvl + 1], ucost,
			"CRAFT" if afford else "NEED MORE", "craft" if afford else "need", _on_upgrade_pickaxe)

func _add_golem_cards() -> void:
	for tier in range(1, GameData.GOLEMS.size() + 1):
		var g: Dictionary = GameData.GOLEMS[tier - 1]
		if not GameState.golem_unlocked(tier):
			var bname: String = GameData.BIOMES[int(g["biome"])]["name"]
			_make_card(C_GREEN, g["name"], "LOCKED", C_DANGER,
				"Reach %s to unlock." % bname, {}, "LOCKED", "locked", Callable())
			break
		var owned := GameState.golem_owned(tier)
		var cost := GameState.golem_buy_cost(tier)
		var afford := GameState.can_afford(cost)
		_make_card(C_GREEN, g["name"], "x%d" % owned, C_GREEN,
			"%s\ndmg %d · every %.2fs" % [g["desc"], int(g["base_damage"]), float(g["interval"])], cost,
			"BUILD" if afford else "NEED MORE", "craft" if afford else "need", _on_buy_golem.bind(tier))

# ===========================================================================
# Right column fills
# ===========================================================================
func _fill_skills() -> void:
	_clear(_skill_body)
	var lp := GameState.level_progress()
	var row := func(k: String, value: String) -> void:
		var h := HBoxContainer.new()
		h.add_child(_lbl(k, 17, C_PURPLE_TXT.darkened(0.1)))
		var sp := Control.new()
		sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(sp)
		h.add_child(_lbl(value, 17, C_TEXT))
		_skill_body.add_child(h)
	row.call("Level", str(lp["level"]))
	row.call("Points free", GameData.fmt(GameState.skill_points_available()))
	row.call("Spent", "%s / %s" % [GameData.fmt(GameState.skill_points_spent()), GameData.fmt(GameState.skill_points_total())])

	var chips := HBoxContainer.new()
	chips.add_theme_constant_override("separation", 6)
	_skill_body.add_child(chips)
	var paths := {"MANUAL": C_AMBER, "GOLEM": C_GREEN, "MACHINE": Color8(150, 170, 220)}
	for pname in paths:
		var cp := _panel(C_PURPLE_BG.lightened(0.05), paths[pname], 1, 4)
		cp.add_child(_lbl(pname, 15, paths[pname]))
		chips.add_child(cp)

	_skill_body.add_child(_wrap_lbl("A big radial tree with 3 paths — spend points anywhere.", 17, C_PURPLE_TXT.darkened(0.15)))
	var open_btn := Button.new()
	open_btn.text = "OPEN TREE"
	open_btn.add_theme_font_size_override("font_size", 12)
	open_btn.custom_minimum_size = Vector2(0, 46)
	_style_button(open_btn, C_PURPLE_BORDER.darkened(0.2), Color.WHITE, C_PURPLE_BORDER, 2)
	open_btn.pressed.connect(_open_skill_tree)
	_skill_body.add_child(open_btn)

	# Specialization launcher + status.
	var spec_avail := GameState.spec_points_available()
	var locked := GameState.spec_locked_to()
	var spec_txt := "Spec points free: %d" % spec_avail
	if locked != "":
		spec_txt += "  ·  %s" % GameData.SPECIALIZATIONS[locked]["name"]
	var srow := HBoxContainer.new()
	_skill_body.add_child(srow)
	srow.add_child(_lbl(spec_txt, 16, C_GREEN if spec_avail > 0 else C_PURPLE_TXT.darkened(0.1)))
	var spec_btn := Button.new()
	spec_btn.text = "SPECIALIZE" + ("  ●" if spec_avail > 0 else "")
	spec_btn.add_theme_font_size_override("font_size", 12)
	spec_btn.custom_minimum_size = Vector2(0, 44)
	var spec_bg := C_AMBER if spec_avail > 0 else C_PURPLE_BG.lightened(0.05)
	var spec_fg := C_DARK_TXT if spec_avail > 0 else C_PURPLE_TXT
	_style_button(spec_btn, spec_bg, spec_fg, C_PURPLE_BORDER, 2)
	spec_btn.pressed.connect(_open_spec_panel)
	_skill_body.add_child(spec_btn)

func _fill_crusher() -> void:
	_clear(_crusher_body)
	_crusher_body.add_child(_wrap_lbl("Smash leftover Rubble into Coins. Deeper Rubble is worth more.", 18, C_MUTED))
	var rubble := GameState.total_rubble()
	var rate := GameState.crush_rate()
	var btn := Button.new()
	btn.add_theme_font_size_override("font_size", 11)
	btn.custom_minimum_size = Vector2(0, 44)
	if rate <= 0:
		btn.text = "Build a Crusher first"
		_style_button(btn, C_CARD, C_MUTED, C_CARD_BORDER, 1)
		btn.disabled = true
	else:
		btn.text = "CRUSH %s → +%s COINS" % [GameData.fmt(rubble), GameData.fmt(GameState.rubble_coins_preview())]
		_style_button(btn, C_AMBER, C_DARK_TXT, C_AMBER.darkened(0.25), 2)
		btn.disabled = rubble <= 0
		if rubble > 0:
			btn.pressed.connect(_on_crush)
	_crusher_body.add_child(btn)

func _fill_lastrun() -> void:
	_clear(_lastrun_body)
	var s: Dictionary = GameState.last_summary
	if s.is_empty():
		var e := _wrap_lbl("No runs yet.\nGrab your pick and dig!", 17, C_MUTED)
		e.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_lastrun_body.add_child(e)
		return
	if s.get("new_record", false):
		_lastrun_body.add_child(_lbl("NEW DEPTH RECORD!", 18, C_AMBER))
	_lastrun_body.add_child(_lbl("Depth reached: %s m" % GameData.fmt(s.get("depth", 0)), 17, C_TEXT))
	_lastrun_body.add_child(_lbl("Tiles mined: %s" % GameData.fmt(s.get("tiles_mined", 0)), 17, C_TEXT))
	_lastrun_body.add_child(_lbl("Resource tiles: %s" % GameData.fmt(s.get("rare_found", 0)), 17, C_TEXT))
	_lastrun_body.add_child(_lbl("EXP gained: %s" % GameData.fmt(s.get("exp", 0)), 17, C_GREEN))
	var res: Dictionary = s.get("resources", {})
	for id in res:
		_lastrun_body.add_child(_lbl("  %s x%s" % [GameData.resource_name(id), GameData.fmt(res[id])], 17, GameData.resource_color(id)))

# ===========================================================================
# Actions
# ===========================================================================
## Open the "prepare descent" screen. Its DESCEND button records the chosen depth
## and kicks off the run; BACK just closes it.
func _open_depth_select() -> void:
	var panel := DepthSelectPanel.new()
	add_child(panel)
	panel.descend.connect(func(depth: int):
		GameState.selected_start_depth = depth
		panel.queue_free()
		start_run.emit())
	panel.canceled.connect(func():
		panel.queue_free())
func _on_menu() -> void:
	GameState.save_game()
	quit_to_title.emit()

func _on_buy_pickaxe() -> void:
	if GameState.buy_next_pickaxe():
		refresh()

func _on_upgrade_pickaxe() -> void:
	if GameState.buy_pickaxe_upgrade():
		refresh()

func _on_buy_golem(tier: int) -> void:
	if GameState.buy_golem(tier):
		refresh()

func _on_buy_upgrade(id: String) -> void:
	if GameState.buy_upgrade(id):
		refresh()

func _on_crush() -> void:
	GameState.crush_rubble()
	refresh()

func _open_skill_tree() -> void:
	var panel := SkillTreePanel.new()
	add_child(panel)
	panel.closed.connect(func():
		panel.queue_free()
		refresh())

func _open_spec_panel() -> void:
	var panel := SpecializationPanel.new()
	add_child(panel)
	panel.closed.connect(func():
		panel.queue_free()
		refresh())
