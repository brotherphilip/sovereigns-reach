extends CanvasLayer
# Complete game HUD built programmatically.
# Panels: TopBar (resources), RightPanel (popularity/rations/tax),
# BuildMenu (building buttons), BottomBar (speed/view controls),
# SelectionPanel (selected entity info), TechTreePanel, EdictPanel.

const HUDController = preload("res://view/hud/HUDController.gd")
const TechTreePanelController = preload("res://view/hud/TechTreePanelController.gd")
const EdictPanelController = preload("res://view/hud/EdictPanelController.gd")
const BuildingRegistry = preload("res://simulation/buildings/BuildingRegistry.gd")
const TechTree = preload("res://simulation/tech/TechTree.gd")
const EdictSystem = preload("res://simulation/edicts/EdictSystem.gd")
const NotificationFeed = preload("res://view/hud/NotificationFeed.gd")

signal build_requested(building_type: String)
signal tech_research_requested(tech_id: String)
signal edict_activate_requested(edict_id: String)
signal speed_changed(speed: int)
signal tax_changed(rate: int)
signal food_ration_changed(level: int)
signal ale_ration_changed(level: int)
signal recruit_requested(unit_type: String)
signal macro_view_toggled()
signal save_requested()
signal trade_buy_requested(resource: String, amount: int)
signal trade_sell_requested(resource: String, amount: int)

# Panel references
var _top_bar: Panel = null
var _right_panel: Panel = null
var _build_menu: Panel = null
var _bottom_bar: Panel = null
var _selection_panel: Panel = null
var _tech_panel: Panel = null
var _edict_panel: Panel = null
var _notification_feed: NotificationFeed = null

# Resource labels
var _gold_label: Label = null
var _wood_label: Label = null
var _stone_label: Label = null
var _iron_label: Label = null
var _food_label: Label = null
var _ale_label: Label = null
var _day_label: Label = null
var _weather_label: Label = null

# Right panel controls
var _pop_bar: ProgressBar = null
var _pop_label: Label = null
var _tax_label_disp: Label = null
var _food_ration_label: Label = null
var _ale_ration_label: Label = null

# Build menu
var _build_category_btns: Dictionary = {}
var _build_item_container: HBoxContainer = null
var _build_mode_label: Label = null
var _current_build_category: int = 2  # FOOD by default

# Speed buttons
var _speed_btns: Array = []

# Selection panel
var _sel_title: Label = null
var _sel_info: Label = null
var _sel_workers_label: Label = null
var _sel_actions: HBoxContainer = null

# Content containers stored directly (no node-path lookup)
var _tech_content: VBoxContainer = null
var _edict_content: VBoxContainer = null

func _ready() -> void:
	layer = 10
	_build_all_panels()
	EventBus.simulation_tick.connect(_on_tick)
	EventBus.building_placed.connect(func(_a,_b,_c,_d,_e): _refresh_build_menu())
	EventBus.popularity_changed.connect(func(_a,_b,_c): _refresh_right_panel())
	EventBus.gold_changed.connect(func(_a,_b,_c): _refresh_top_bar())

func _on_tick(tick: int) -> void:
	_refresh_top_bar()
	if tick % 20 == 0:
		_refresh_right_panel()
		_refresh_build_menu()

# ── Panel construction ────────────────────────────────────────────────────────

func _build_all_panels() -> void:
	var vp: Vector2 = get_viewport().get_visible_rect().size
	if vp == Vector2.ZERO:
		vp = Vector2(1280, 720)

	_top_bar = _make_panel(Rect2(0, 0, vp.x, 38))
	_build_top_bar(vp)

	_right_panel = _make_panel(Rect2(vp.x - 220, 40, 218, 240))
	_build_right_panel()

	_bottom_bar = _make_panel(Rect2(0, vp.y - 36, vp.x, 34))
	_build_bottom_bar(vp)

	_build_menu = _make_panel(Rect2(0, vp.y - 200, vp.x * 0.65, 162))
	_build_build_menu(vp)

	_selection_panel = _make_panel(Rect2(vp.x * 0.65 + 2, vp.y - 200, vp.x * 0.35 - 222, 162))
	_build_selection_panel()

	_tech_panel = _make_panel(Rect2(vp.x - 440, 40, 438, vp.y - 80))
	_tech_panel.visible = false
	_build_tech_panel()

	_edict_panel = _make_panel(Rect2(vp.x - 440, 40, 438, vp.y - 80))
	_edict_panel.visible = false
	_build_edict_panel()

	# Stacking notification feed (replaces the old single-label notification)
	_notification_feed = NotificationFeed.new()
	_notification_feed.position = Vector2(vp.x * 0.5 - 200, 44)
	_notification_feed.size = Vector2(400, 0)
	add_child(_notification_feed)

	# Diplomacy panel (tribute demands) — hidden until an envoy arrives
	var diplomacy_panel := preload("res://view/hud/DiplomacyPanel.gd").new()
	diplomacy_panel.position = Vector2(vp.x * 0.5 - 160, vp.y * 0.32)
	add_child(diplomacy_panel)

func _make_panel(rect: Rect2) -> Panel:
	var p := Panel.new()
	p.position = rect.position
	p.size     = rect.size
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.10, 0.14, 0.90)
	style.border_width_bottom = 1
	style.border_color = Color(0.3, 0.35, 0.4, 0.8)
	p.add_theme_stylebox_override("panel", style)
	add_child(p)
	return p

func _add_label(parent: Control, text: String, pos: Vector2,
		size_pt: int = 12, color: Color = Color.WHITE_SMOKE) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.position = pos
	lbl.size = Vector2(150, 24)
	lbl.add_theme_font_size_override("font_size", size_pt)
	lbl.add_theme_color_override("font_color", color)
	parent.add_child(lbl)
	return lbl

func _add_button(parent: Control, text: String, pos: Vector2, sz: Vector2,
		callback: Callable) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.position = pos
	btn.size = sz
	btn.add_theme_font_size_override("font_size", 11)
	btn.pressed.connect(callback)
	parent.add_child(btn)
	return btn

# ── Top bar ───────────────────────────────────────────────────────────────────

func _build_top_bar(vp: Vector2) -> void:
	var x: float = 6.0
	_gold_label    = _add_label(_top_bar, "Gold: 0",     Vector2(x, 8));     x += 110
	_wood_label    = _add_label(_top_bar, "Wood: 0",     Vector2(x, 8));     x += 90
	_stone_label   = _add_label(_top_bar, "Stone: 0",    Vector2(x, 8));     x += 90
	_iron_label    = _add_label(_top_bar, "Iron: 0",     Vector2(x, 8));     x += 90
	_food_label    = _add_label(_top_bar, "Food: 0",     Vector2(x, 8));     x += 110
	_ale_label     = _add_label(_top_bar, "Ale: 0",      Vector2(x, 8));     x += 90
	_day_label     = _add_label(_top_bar, "Day 0",       Vector2(x, 8), 13, Color.LIGHT_YELLOW); x += 90
	_weather_label = _add_label(_top_bar, "Clear",       Vector2(x, 8), 12, Color.LIGHT_CYAN)

func _refresh_top_bar() -> void:
	if GameState.players.size() == 0:
		return
	var p: Dictionary = GameState.players[0]
	var res: Dictionary = p.get("resources", {})
	var food: Dictionary = p.get("food", {})
	var total_food: int = HUDController.get_total_food(p)
	var total_ale: int  = int(food.get("ale", 0))
	_gold_label.text    = "Gold: %d" % int(p.get("gold", 0))
	_wood_label.text    = "Wood: %d" % int(res.get("wood", 0))
	_stone_label.text   = "Stone: %d" % int(res.get("stone", 0))
	_iron_label.text    = "Iron: %d" % int(res.get("iron", 0))
	_food_label.text    = "Food: %d" % total_food
	_ale_label.text     = "Ale: %d" % total_ale
	_day_label.text     = "Day %d" % SimulationClock.game_day()
	_weather_label.text = GameState.weather.get("current_name", "Clear")

# ── Right panel ───────────────────────────────────────────────────────────────

func _build_right_panel() -> void:
	_add_label(_right_panel, "POPULARITY", Vector2(6, 6), 11, Color.LIGHT_YELLOW)
	_pop_bar = ProgressBar.new()
	_pop_bar.position = Vector2(6, 24)
	_pop_bar.size = Vector2(204, 18)
	_pop_bar.min_value = 0; _pop_bar.max_value = 100; _pop_bar.value = 50
	_right_panel.add_child(_pop_bar)
	_pop_label = _add_label(_right_panel, "50%", Vector2(84, 24), 11)

	_add_label(_right_panel, "Tax Rate:", Vector2(6, 50), 11)
	_tax_label_disp = _add_label(_right_panel, "0 (None)", Vector2(90, 50), 11)
	_add_button(_right_panel, "−", Vector2(6, 66), Vector2(30, 22), func(): _change_tax(-1))
	_add_button(_right_panel, "+", Vector2(40, 66), Vector2(30, 22), func(): _change_tax(1))

	_add_label(_right_panel, "Food Ration:", Vector2(6, 98), 11)
	_food_ration_label = _add_label(_right_panel, "Normal", Vector2(112, 98), 11, Color.LIGHT_GREEN)
	_add_button(_right_panel, "−", Vector2(6, 114), Vector2(30, 22), func(): _change_food_ration(-1))
	_add_button(_right_panel, "+", Vector2(40, 114), Vector2(30, 22), func(): _change_food_ration(1))

	_add_label(_right_panel, "Ale Ration:", Vector2(6, 146), 11)
	_ale_ration_label = _add_label(_right_panel, "Half", Vector2(112, 146), 11, Color.LIGHT_BLUE)
	_add_button(_right_panel, "−", Vector2(6, 162), Vector2(30, 22), func(): _change_ale_ration(-1))
	_add_button(_right_panel, "+", Vector2(40, 162), Vector2(30, 22), func(): _change_ale_ration(1))

	_add_label(_right_panel, "Prestige:", Vector2(6, 196), 11, Color.LIGHT_YELLOW)
	_add_label(_right_panel, "Population:", Vector2(6, 212), 11, Color.LIGHT_CYAN)

func _refresh_right_panel() -> void:
	if GameState.players.size() == 0:
		return
	var p: Dictionary = GameState.players[0]
	var pop: float = float(p.get("popularity", 50))
	_pop_bar.value = pop
	var tier: String = HUDController.get_popularity_tier(pop)
	var col: Color = Color.from_string(HUDController.get_popularity_color(tier), Color.WHITE)
	_pop_label.text = "%d%% (%s)" % [int(pop), tier]
	_pop_label.add_theme_color_override("font_color", col)
	_tax_label_disp.text = HUDController.get_tax_label(int(p.get("tax_rate", 0)))
	_food_ration_label.text = HUDController.get_ration_label(int(p.get("food_ration", 2)))
	_ale_ration_label.text  = HUDController.get_ration_label(int(p.get("ale_ration", 1)))

func _change_tax(delta: int) -> void:
	if GameState.players.size() == 0: return
	var cur: int = int(GameState.players[0].get("tax_rate", 0))
	tax_changed.emit(clampi(cur + delta, -3, 3))

func _change_food_ration(delta: int) -> void:
	if GameState.players.size() == 0: return
	var cur: int = int(GameState.players[0].get("food_ration", 2))
	food_ration_changed.emit(clampi(cur + delta, 0, 4))

func _change_ale_ration(delta: int) -> void:
	if GameState.players.size() == 0: return
	var cur: int = int(GameState.players[0].get("ale_ration", 1))
	ale_ration_changed.emit(clampi(cur + delta, 0, 4))

# ── Build menu ────────────────────────────────────────────────────────────────

func _build_build_menu(vp: Vector2) -> void:
	_add_label(_build_menu, "BUILD:", Vector2(6, 4), 11, Color.LIGHT_YELLOW)
	_build_mode_label = _add_label(_build_menu, "", Vector2(60, 4), 11, Color.YELLOW)

	# Category tabs
	var cat_names: Array = ["Civic", "Harvest", "Food", "Military", "Defense"]
	var cat_x: float = 120.0
	for i in range(cat_names.size()):
		var ci: int = i
		var btn: Button = _add_button(_build_menu, cat_names[i], Vector2(cat_x, 2),
			Vector2(70, 20), func(): _show_build_category(ci))
		_build_category_btns[i] = btn
		cat_x += 74

	# Building items row
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(4, 26)
	scroll.size = Vector2(_build_menu.size.x - 8, 128)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_build_menu.add_child(scroll)

	_build_item_container = HBoxContainer.new()
	_build_item_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_build_item_container)

	_show_build_category(2)  # Start on FOOD

func _show_build_category(cat: int) -> void:
	_current_build_category = cat
	for child in _build_item_container.get_children():
		child.queue_free()

	if GameState.players.size() == 0:
		return
	var player: Dictionary = GameState.players[0]
	var buildings: Array = BuildingRegistry.get_by_category(cat)

	for btype in buildings:
		var defn: Dictionary = BuildingRegistry.lookup(btype)
		var name_str: String = defn.get("name", btype)
		var cost: Dictionary = defn.get("cost", {})
		var cost_str: String = _format_cost(cost)
		var can_afford: bool = _can_afford(cost, player)
		var req_tech: Array  = defn.get("requires_tech", [])
		var tech_ok: bool    = _tech_met(req_tech, player)

		var card := VBoxContainer.new()
		card.custom_minimum_size = Vector2(110, 120)
		_build_item_container.add_child(card)

		var name_lbl := Label.new()
		name_lbl.text = name_str
		name_lbl.add_theme_font_size_override("font_size", 10)
		name_lbl.add_theme_color_override("font_color",
			Color.WHITE if (can_afford and tech_ok) else Color(0.5, 0.5, 0.5))
		name_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		card.add_child(name_lbl)

		var cost_lbl := Label.new()
		cost_lbl.text = cost_str if tech_ok else "Needs: %s" % ", ".join(req_tech).left(18)
		cost_lbl.add_theme_font_size_override("font_size", 9)
		cost_lbl.add_theme_color_override("font_color",
			Color.LIGHT_GREEN if can_afford else Color.ORANGE_RED)
		card.add_child(cost_lbl)

		var bi: String = btype
		var build_btn := Button.new()
		build_btn.text = "Build"
		build_btn.disabled = not (can_afford and tech_ok)
		build_btn.add_theme_font_size_override("font_size", 10)
		build_btn.pressed.connect(func(): build_requested.emit(bi))
		card.add_child(build_btn)

func _refresh_build_menu() -> void:
	_show_build_category(_current_build_category)

func _format_cost(cost: Dictionary) -> String:
	if cost.is_empty():
		return "Free"
	var parts: Array = []
	for k in cost:
		parts.append("%d %s" % [int(cost[k]), k.left(3)])
	return ", ".join(parts)

func _can_afford(cost: Dictionary, player: Dictionary) -> bool:
	var res: Dictionary = player.get("resources", {})
	var gold: int = int(player.get("gold", 0))
	for k in cost:
		var needed: int = int(cost[k])
		if k == "gold":
			if gold < needed: return false
		else:
			if int(res.get(k, 0)) < needed: return false
	return true

func _tech_met(req_tech: Array, player: Dictionary) -> bool:
	if req_tech.is_empty():
		return true
	var unlocks: Array = player.get("tech_unlocks", [])
	for t in req_tech:
		if t not in unlocks:
			return false
	return true

# ── Bottom bar ────────────────────────────────────────────────────────────────

func _build_bottom_bar(vp: Vector2) -> void:
	var speeds: Array = [["❚❚", 0], ["▶ 1×", 1], ["▶▶ 2×", 2], ["▶▶▶ 5×", 3]]
	var x: float = 6.0
	for s in speeds:
		var sp: int = s[1]
		_add_button(_bottom_bar, s[0], Vector2(x, 4), Vector2(56, 26),
			func(): speed_changed.emit(sp))
		x += 60

	_add_button(_bottom_bar, "⊞ Macro [Tab]", Vector2(x + 10, 4), Vector2(110, 26),
		func(): macro_view_toggled.emit())
	_add_button(_bottom_bar, "🔬 Tech", Vector2(x + 130, 4), Vector2(70, 26),
		func(): _toggle_tech_panel())
	_add_button(_bottom_bar, "📜 Edicts", Vector2(x + 208, 4), Vector2(80, 26),
		func(): _toggle_edict_panel())
	_add_button(_bottom_bar, "💾 Save", Vector2(x + 296, 4), Vector2(70, 26),
		func(): save_requested.emit())

# ── Selection panel ────────────────────────────────────────────────────────────

func _build_selection_panel() -> void:
	_add_label(_selection_panel, "SELECTED", Vector2(6, 4), 11, Color.LIGHT_YELLOW)
	_sel_title = _add_label(_selection_panel, "Nothing selected", Vector2(6, 22), 12)
	_sel_info  = _add_label(_selection_panel, "", Vector2(6, 42), 10, Color.LIGHT_GRAY)
	_sel_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_sel_info.size = Vector2(_selection_panel.size.x - 12, 60)
	_sel_workers_label = _add_label(_selection_panel, "", Vector2(6, 106), 10)

	_sel_actions = HBoxContainer.new()
	_sel_actions.position = Vector2(6, 110)
	_sel_actions.size = Vector2(_selection_panel.size.x - 12, 48)
	_sel_actions.add_theme_constant_override("separation", 3)
	_selection_panel.add_child(_sel_actions)

func show_selected_building(building: Dictionary) -> void:
	if not _sel_title:
		return
	const BR = preload("res://simulation/buildings/BuildingRegistry.gd")
	const UR = preload("res://simulation/units/UnitRegistry.gd")
	var btype: String = building.get("type", "")
	var defn: Dictionary = BR.lookup(btype)
	_sel_title.text = defn.get("name", btype)
	var hp: int = building.get("hp", 0)
	var max_hp: int = defn.get("hp", 100)
	var workers: int = building.get("workers", 0)
	var max_w: int = defn.get("max_workers", 0)
	_sel_info.text = "HP: %d/%d  |  Fire: %s\n%s" % [
		hp, max_hp,
		"YES" if building.get("on_fire", false) else "No",
		defn.get("description", "")
	]
	_sel_workers_label.text = "Workers: %d/%d" % [workers, max_w]
	for c in _sel_actions.get_children(): c.queue_free()

	# Worker buttons (when building has worker slots)
	if max_w > 0:
		var wlbl := Label.new(); wlbl.text = "W:"; wlbl.add_theme_font_size_override("font_size", 10)
		_sel_actions.add_child(wlbl)
		for i in range(0, max_w + 1):
			var wc: int = i
			var wb: Button = Button.new()
			wb.text = str(i)
			wb.add_theme_font_size_override("font_size", 10)
			wb.custom_minimum_size = Vector2(26, 24)
			wb.pressed.connect(func(): _set_workers_on_building(building.get("id", -1), wc))
			_sel_actions.add_child(wb)

	# Recruit buttons (for buildings that train units)
	var recruitable: Array = UR.get_units_for_building(btype)
	if not recruitable.is_empty() and GameState.players.size() > 0:
		var player: Dictionary = GameState.players[0]
		for utype in recruitable:
			var udefn: Dictionary = UR.lookup(utype)
			var check: Dictionary = UR.can_recruit(utype, player)
			var rb: Button = Button.new()
			rb.text = "Recruit %s" % udefn.get("name", utype)
			rb.add_theme_font_size_override("font_size", 9)
			rb.custom_minimum_size = Vector2(90, 24)
			rb.disabled = not check.get("ok", false)
			rb.tooltip_text = check.get("reason", "")
			var ut: String = utype
			rb.pressed.connect(func(): recruit_requested.emit(ut))
			_sel_actions.add_child(rb)

	# Market: buy/sell buttons
	if btype == "market" or btype == "guildhall":
		_add_market_actions(building)

func show_selected_unit(unit: Dictionary) -> void:
	if not _sel_title:
		return
	const UR = preload("res://simulation/units/UnitRegistry.gd")
	var utype: String = unit.get("type", "")
	var defn: Dictionary = UR.lookup(utype)
	_sel_title.text = defn.get("name", utype)
	_sel_info.text = "HP: %d/%d  |  Order: %s\nAtk: %d  Def: %d  Speed: %d" % [
		int(unit.get("hp", 0)), int(unit.get("max_hp", 1)),
		unit.get("order", "idle"),
		int(defn.get("attack", 0)), int(defn.get("defense", 0)),
		int(defn.get("speed", 0)),
	]
	_sel_workers_label.text = ""
	for c in _sel_actions.get_children(): c.queue_free()

func clear_selection() -> void:
	if not _sel_title: return
	_sel_title.text = "Nothing selected"
	_sel_info.text = ""
	_sel_workers_label.text = ""
	for c in _sel_actions.get_children(): c.queue_free()

func _set_workers_on_building(bid: int, count: int) -> void:
	CommandQueue.enqueue(9, {"building_id": bid, "workers": count}, 0)

func _add_market_actions(_building: Dictionary) -> void:
	var trade_resources: Array = ["wood", "stone", "iron", "gold"]
	for res in trade_resources:
		var r: String = res
		var buy_btn := Button.new()
		buy_btn.text = "Buy %s" % r.left(2).to_upper()
		buy_btn.add_theme_font_size_override("font_size", 9)
		buy_btn.custom_minimum_size = Vector2(56, 22)
		buy_btn.pressed.connect(func(): trade_buy_requested.emit(r, 10))
		_sel_actions.add_child(buy_btn)
		var sell_btn := Button.new()
		sell_btn.text = "Sell"
		sell_btn.add_theme_font_size_override("font_size", 9)
		sell_btn.custom_minimum_size = Vector2(36, 22)
		sell_btn.pressed.connect(func(): trade_sell_requested.emit(r, 10))
		_sel_actions.add_child(sell_btn)

# ── Tech Tree Panel ────────────────────────────────────────────────────────────

func _build_tech_panel() -> void:
	_add_label(_tech_panel, "TECHNOLOGY", Vector2(8, 6), 14, Color.LIGHT_YELLOW)
	_add_button(_tech_panel, "✕", Vector2(_tech_panel.size.x - 30, 4), Vector2(26, 24),
		func(): _tech_panel.visible = false)
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(4, 36)
	scroll.size = Vector2(_tech_panel.size.x - 8, _tech_panel.size.y - 44)
	_tech_panel.add_child(scroll)
	_tech_content = VBoxContainer.new()
	scroll.add_child(_tech_content)

func _refresh_tech_panel() -> void:
	if not _tech_panel.visible or GameState.players.size() == 0:
		return
	if _tech_content == null: return
	var vbox: VBoxContainer = _tech_content
	for c in vbox.get_children(): c.queue_free()

	var player: Dictionary = GameState.players[0]
	var panel_data: Dictionary = TechTreePanelController.get_panel_data(player)
	var branches: Dictionary = panel_data.get("branches", {})

	const BRANCH_NAMES: Array = ["Agriculture", "Industry", "Military", "Statecraft", "Misc"]
	for branch_val in branches:
		var branch_techs: Array = branches[branch_val]
		if branch_techs.is_empty(): continue
		var branch_lbl := Label.new()
		branch_lbl.text = "── %s ──" % BRANCH_NAMES[mini(int(branch_val), BRANCH_NAMES.size()-1)]
		branch_lbl.add_theme_font_size_override("font_size", 11)
		branch_lbl.add_theme_color_override("font_color", Color.LIGHT_YELLOW)
		vbox.add_child(branch_lbl)
		for item in branch_techs:
			_add_tech_item(vbox, item, player)

func _add_tech_item(parent: VBoxContainer, item: Dictionary, player: Dictionary) -> void:
	var row := HBoxContainer.new()
	row.custom_minimum_size = Vector2(0, 28)
	parent.add_child(row)

	var status: String = item.get("status", "locked")
	var status_sym: String = {"researched": "✓", "available": "◯", "unaffordable": "⊘", "locked": "🔒"}.get(status, "?")
	var lbl := Label.new()
	lbl.text = "%s %s (%dP)" % [status_sym, item.get("name", "?"), int(item.get("cost_prestige", 0))]
	lbl.add_theme_font_size_override("font_size", 10)
	lbl.add_theme_color_override("font_color",
		Color.LIGHT_GREEN if status == "researched" else
		Color.WHITE if status == "available" else Color.GRAY)
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(lbl)

	if status == "available":
		var tech_id: String = item.get("id", "")
		var btn := Button.new()
		btn.text = "Research"
		btn.add_theme_font_size_override("font_size", 10)
		btn.custom_minimum_size = Vector2(80, 24)
		btn.pressed.connect(func(): tech_research_requested.emit(tech_id))
		row.add_child(btn)

func _toggle_tech_panel() -> void:
	_tech_panel.visible = not _tech_panel.visible
	_edict_panel.visible = false
	if _tech_panel.visible:
		_refresh_tech_panel()

# ── Edict Panel ────────────────────────────────────────────────────────────────

func _build_edict_panel() -> void:
	_add_label(_edict_panel, "ROYAL EDICTS", Vector2(8, 6), 14, Color.LIGHT_YELLOW)
	_add_button(_edict_panel, "✕", Vector2(_edict_panel.size.x - 30, 4), Vector2(26, 24),
		func(): _edict_panel.visible = false)
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(4, 36)
	scroll.size = Vector2(_edict_panel.size.x - 8, _edict_panel.size.y - 44)
	_edict_panel.add_child(scroll)
	_edict_content = VBoxContainer.new()
	scroll.add_child(_edict_content)

func _refresh_edict_panel() -> void:
	if not _edict_panel.visible or GameState.players.size() == 0:
		return
	if _edict_content == null: return
	var vbox: VBoxContainer = _edict_content
	for c in vbox.get_children(): c.queue_free()

	var player: Dictionary = GameState.players[0]
	var panel_data: Dictionary = EdictPanelController.get_panel_data(player, SimulationClock.current_tick)

	_add_edict_section(vbox, "Active Edicts", panel_data.get("active", []), true)
	_add_edict_section(vbox, "Available Edicts", panel_data.get("available", []), false)

func _add_edict_section(parent: VBoxContainer, title: String, items: Array, is_active: bool) -> void:
	if items.is_empty(): return
	var hdr := Label.new()
	hdr.text = "── %s ──" % title
	hdr.add_theme_font_size_override("font_size", 11)
	hdr.add_theme_color_override("font_color", Color.LIGHT_YELLOW)
	parent.add_child(hdr)
	for item in items:
		var row := HBoxContainer.new()
		row.custom_minimum_size = Vector2(0, 28)
		parent.add_child(row)
		var lbl := Label.new()
		lbl.text = item.get("name", "?")
		lbl.add_theme_font_size_override("font_size", 10)
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(lbl)
		if is_active:
			var rem_lbl := Label.new()
			rem_lbl.text = item.get("remaining_label", "")
			rem_lbl.add_theme_font_size_override("font_size", 10)
			rem_lbl.add_theme_color_override("font_color", Color.ORANGE)
			row.add_child(rem_lbl)
		else:
			var eid: String = item.get("id", "")
			var btn := Button.new()
			btn.text = "Activate (%dP)" % int(item.get("cost_points", 0))
			btn.add_theme_font_size_override("font_size", 9)
			btn.pressed.connect(func(): edict_activate_requested.emit(eid))
			row.add_child(btn)

func _toggle_edict_panel() -> void:
	_edict_panel.visible = not _edict_panel.visible
	_tech_panel.visible = false
	if _edict_panel.visible:
		_refresh_edict_panel()

# ── Notification system ───────────────────────────────────────────────────────

func show_notification(text: String, duration: float = 3.0) -> void:
	if _notification_feed == null: return
	_notification_feed.push(text, duration)

func set_build_mode_display(building_type: String) -> void:
	if _build_mode_label:
		_build_mode_label.text = "Mode: %s" % (building_type if building_type != "" else "Select")
