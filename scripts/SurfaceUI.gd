class_name SurfaceUI
extends Control
## The surface hub: run summary, resource stockpile, upgrades, skill tree and
## the button to start the next 60-second run. Rebuilt from data each refresh.

signal start_run

var _summary_box: VBoxContainer
var _resource_box: VBoxContainer
var _stats_box: VBoxContainer
var _upgrade_box: VBoxContainer
var _skill_box: VBoxContainer
var _exp_lbl: Label

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build()
	refresh()

func _bg() -> void:
	var bg := ColorRect.new()
	bg.color = Color8(24, 26, 34)
	add_child(bg)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

func _header(text: String, size := 22, color := Color8(180, 200, 255)) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l

func _column(title: String) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0.28)
	sb.set_corner_radius_all(10)
	sb.set_content_margin_all(12)
	panel.add_theme_stylebox_override("panel", sb)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var vb := VBoxContainer.new()
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.add_theme_constant_override("separation", 6)
	vb.add_child(_header(title, 24, Color8(255, 220, 140)))
	scroll.add_child(vb)
	panel.add_child(scroll)
	panel.set_meta("body", vb)
	return panel

func _build() -> void:
	_bg()
	var root := MarginContainer.new()
	add_child(root)
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("margin_left", 18)
	root.add_theme_constant_override("margin_right", 18)
	root.add_theme_constant_override("margin_top", 14)
	root.add_theme_constant_override("margin_bottom", 14)

	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 10)
	root.add_child(outer)

	# Title row
	var title := _header("DEEP DELVER  -  Surface Camp", 34, Color8(255, 235, 150))
	outer.add_child(title)

	# Three columns
	var cols := HBoxContainer.new()
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cols.add_theme_constant_override("separation", 12)
	outer.add_child(cols)

	# --- Left column: summary + stockpile + stats ---
	var left := _column("Last Run")
	cols.add_child(left)
	var lbody: VBoxContainer = left.get_meta("body")
	_summary_box = VBoxContainer.new()
	lbody.add_child(_summary_box)
	lbody.add_child(HSeparator.new())
	lbody.add_child(_header("Stockpile", 20))
	_resource_box = VBoxContainer.new()
	lbody.add_child(_resource_box)
	lbody.add_child(HSeparator.new())
	lbody.add_child(_header("Your Stats", 20))
	_stats_box = VBoxContainer.new()
	lbody.add_child(_stats_box)

	# --- Middle column: upgrades ---
	var mid := _column("Upgrades")
	cols.add_child(mid)
	_upgrade_box = mid.get_meta("body")

	# --- Right column: skill tree launcher ---
	var right := _column("Skill Tree")
	cols.add_child(right)
	var rbody: VBoxContainer = right.get_meta("body")
	_exp_lbl = _header("", 18, Color8(180, 255, 200))
	rbody.add_child(_exp_lbl)
	_skill_box = VBoxContainer.new()
	rbody.add_child(_skill_box)

	# --- Bottom: start button ---
	var bottom := HBoxContainer.new()
	bottom.alignment = BoxContainer.ALIGNMENT_CENTER
	outer.add_child(bottom)
	var start_btn := Button.new()
	start_btn.text = "START MINING RUN  (60s)"
	start_btn.add_theme_font_size_override("font_size", 26)
	start_btn.custom_minimum_size = Vector2(360, 60)
	start_btn.pressed.connect(func(): start_run.emit())
	bottom.add_child(start_btn)

# ===========================================================================
func refresh() -> void:
	_fill_summary()
	_fill_resources()
	_fill_stats()
	_fill_upgrades()
	_fill_skills()

func _row_label(box: VBoxContainer, text: String, color := Color.WHITE, size := 16) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(l)

func _fill_summary() -> void:
	for c in _summary_box.get_children():
		c.queue_free()
	var s: Dictionary = GameState.last_summary
	if s.is_empty():
		_row_label(_summary_box, "No runs yet. Press Start to dig!", Color8(200, 200, 200))
		return
	if s.get("new_record", false):
		_row_label(_summary_box, "NEW DEPTH RECORD!", Color8(255, 220, 90), 18)
	_row_label(_summary_box, "Depth reached: %d m" % s.get("depth", 0))
	_row_label(_summary_box, "Tiles mined: %d" % s.get("tiles_mined", 0))
	_row_label(_summary_box, "Resource tiles: %d" % s.get("rare_found", 0))
	_row_label(_summary_box, "EXP gained: %d" % s.get("exp", 0), Color8(180, 255, 200))
	var res: Dictionary = s.get("resources", {})
	if not res.is_empty():
		_row_label(_summary_box, "Gathered:", Color8(180, 200, 255))
		for id in res:
			_row_label(_summary_box, "  %s x%d" % [GameData.resource_name(id), res[id]],
				GameData.resource_color(id))

func _fill_resources() -> void:
	for c in _resource_box.get_children():
		c.queue_free()
	_row_label(_resource_box, "Coins: %d" % GameState.money, Color8(255, 220, 120))

	# Crusher: convert Rubble into Coins.
	var rubble := int(GameState.resources.get("rubble", 0))
	var rate := GameState.crush_rate()
	if rate > 0:
		var btn := Button.new()
		btn.text = "Crush %d Rubble  →  %d Coins" % [rubble, rubble * rate]
		btn.disabled = rubble <= 0
		btn.pressed.connect(_on_crush)
		_resource_box.add_child(btn)
	elif rubble > 0:
		_row_label(_resource_box, "(buy a Crusher to turn Rubble into Coins)", Color8(170, 170, 170), 14)

	var any := false
	for id in GameData.RESOURCES:
		var amt := int(GameState.resources.get(id, 0))
		if amt > 0:
			any = true
			_row_label(_resource_box, "%s: %d" % [GameData.resource_name(id), amt],
				GameData.resource_color(id))
	if not any:
		_row_label(_resource_box, "(empty - go mine some!)", Color8(160, 160, 160))

func _fill_stats() -> void:
	for c in _stats_box.get_children():
		c.queue_free()
	var st := GameState.get_effective_stats()
	_row_label(_stats_box, "Pickaxe: %s" % GameState.current_pickaxe()["name"], Color8(255, 210, 140))
	_row_label(_stats_box, "Click damage: %.1f" % st["click_damage"])
	_row_label(_stats_box, "Click cooldown: %.2fs" % st["click_cooldown"])
	_row_label(_stats_box, "Resource yield: x%.2f" % st["resource_mult"])
	_row_label(_stats_box, "EXP gain: x%.2f" % st["exp_mult"])
	_row_label(_stats_box, "Crit: %d%% (x%.1f)" % [int(st["crit_chance"] * 100), st["crit_damage"]])
	_row_label(_stats_box, "Golems: %d" % int(st["ai_count"]))
	_row_label(_stats_box, "Drills: %d" % int(st["drill_count"]))
	_row_label(_stats_box, "Crusher: Lv %d" % GameState.crush_rate())

func _cost_text(cost: Dictionary) -> String:
	var parts := PackedStringArray()
	for res in cost:
		var rname := "Coins" if res == "coins" else GameData.resource_name(res)
		parts.append("%d %s" % [cost[res], rname])
	return ", ".join(parts)

func _fill_upgrades() -> void:
	for c in _upgrade_box.get_children():
		c.queue_free()
	_fill_pickaxe_shop()
	_fill_golem_shop()
	var cur_cat := ""
	for id in GameData.UPGRADE_ORDER:
		var def: Dictionary = GameData.UPGRADES[id]
		if def["category"] != cur_cat:
			cur_cat = def["category"]
			_upgrade_box.add_child(_header(cur_cat, 18, Color8(160, 210, 255)))
		var lvl := GameState.upgrade_level(id)
		var maxed := GameState.is_upgrade_maxed(id)
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(0, 44)
		btn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		if maxed:
			btn.text = "%s  [MAX Lv%d]\n%s" % [def["name"], lvl, def["desc"]]
			btn.disabled = true
		else:
			var cost := GameState.upgrade_cost(id)
			btn.text = "%s  (Lv%d)\n%s\nCost: %s" % [def["name"], lvl, def["desc"], _cost_text(cost)]
			btn.disabled = not GameState.can_afford(cost)
			btn.pressed.connect(_on_buy_upgrade.bind(id))
		_upgrade_box.add_child(btn)

func _fill_pickaxe_shop() -> void:
	_upgrade_box.add_child(_header("Pickaxe Shop", 18, Color8(255, 210, 140)))
	var cur: Dictionary = GameState.current_pickaxe()
	_row_label(_upgrade_box, "Equipped: %s  (base dmg %d)" % [cur["name"], int(cur["base_damage"])],
		Color8(220, 222, 232))
	if cur.get("desc", "") != "":
		_row_label(_upgrade_box, cur["desc"], Color8(165, 172, 190), 13)

	var nxt: Dictionary = GameState.next_pickaxe()
	if nxt.is_empty():
		_row_label(_upgrade_box, "Highest pickaxe crafted!", Color8(160, 255, 160))
	else:
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(0, 56)
		btn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		if not GameState.pickaxe_unlocked(nxt):
			var bname: String = GameData.BIOMES[int(nxt["biome"])]["name"]
			btn.text = "%s  (locked)\nReach %s to unlock" % [nxt["name"], bname]
			btn.disabled = true
		else:
			btn.text = "Craft %s  (base dmg %d)\n%s\nCost: %s" % [
				nxt["name"], int(nxt["base_damage"]), nxt["desc"], _cost_text(nxt["cost"])]
			btn.disabled = not GameState.can_afford(nxt["cost"])
			btn.pressed.connect(_on_buy_pickaxe)
		_upgrade_box.add_child(btn)
	_upgrade_box.add_child(HSeparator.new())

func _on_buy_pickaxe() -> void:
	if GameState.buy_next_pickaxe():
		refresh()

func _fill_golem_shop() -> void:
	_upgrade_box.add_child(_header("Golem Workshop", 18, Color8(150, 230, 170)))
	_row_label(_upgrade_box, "Golems owned: %d" % GameState.golem_count(), Color8(180, 255, 200))
	for tier in range(1, GameData.GOLEMS.size() + 1):
		var g: Dictionary = GameData.GOLEMS[tier - 1]
		if not GameState.golem_unlocked(tier):
			var bname: String = GameData.BIOMES[int(g["biome"])]["name"]
			_row_label(_upgrade_box, "%s — locked (reach %s)" % [g["name"], bname], Color8(150, 150, 162), 13)
			break     # tiers past the first locked one are also locked
		var owned := GameState.golem_owned(tier)
		var cost := GameState.golem_buy_cost(tier)
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(0, 52)
		btn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		btn.text = "Build %s  (own %d)\ndmg %d · %.1fs · %s\nCost: %s" % [
			g["name"], owned, int(g["base_damage"]), float(g["interval"]), g["desc"], _cost_text(cost)]
		btn.disabled = not GameState.can_afford(cost)
		btn.pressed.connect(_on_buy_golem.bind(tier))
		_upgrade_box.add_child(btn)
	_upgrade_box.add_child(HSeparator.new())

func _on_buy_golem(tier: int) -> void:
	if GameState.buy_golem(tier):
		refresh()

func _on_buy_upgrade(id: String) -> void:
	if GameState.buy_upgrade(id):
		refresh()

func _on_crush() -> void:
	GameState.crush_rubble()
	refresh()

func _fill_skills() -> void:
	var lp := GameState.level_progress()
	_exp_lbl.text = "Level %d   ·   %d / %d EXP" % [lp["level"], lp["into"], lp["need"]]
	for c in _skill_box.get_children():
		c.queue_free()
	_row_label(_skill_box, "Available skill points: %d" % GameState.skill_points_available(),
		Color8(255, 235, 150), 18)
	_row_label(_skill_box, "Spent: %d of %d" % [GameState.skill_points_spent(), GameState.skill_points_total()],
		Color8(180, 185, 200), 14)
	_row_label(_skill_box, "A large radial tree with 3 build paths:\nManual · Golem · Machinery. Invest anywhere.",
		Color8(190, 195, 210), 14)
	var open_btn := Button.new()
	open_btn.text = "OPEN SKILL TREE"
	open_btn.add_theme_font_size_override("font_size", 20)
	open_btn.custom_minimum_size = Vector2(0, 54)
	open_btn.pressed.connect(_open_skill_tree)
	_skill_box.add_child(open_btn)

func _open_skill_tree() -> void:
	var panel := SkillTreePanel.new()
	add_child(panel)
	panel.closed.connect(func():
		panel.queue_free()
		refresh())
