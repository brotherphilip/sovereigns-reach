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
const WeatherSystem = preload("res://simulation/world/WeatherSystem.gd")
const ReligionSystem = preload("res://simulation/economy/ReligionSystem.gd")

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
var _was_starving: bool = false
var _had_disease: bool  = false

# Resource labels
var _gold_label: Label = null
var _wood_label: Label = null
var _stone_label: Label = null
var _iron_label: Label = null
var _food_label: Label = null
var _ale_label: Label = null
var _day_label: Label = null
var _weather_label: Label = null
var _prestige_label: Label = null
var _faith_label: Label = null
var _health_label: Label = null

# Right panel controls
var _pop_bar: ProgressBar = null
var _pop_label: Label = null
var _tax_label_disp: Label = null
var _food_ration_label: Label = null
var _ale_ration_label: Label = null
var _tax_delta_label: Label = null
var _food_ration_delta: Label = null
var _ale_ration_delta: Label = null
var _pop_bar_fill: StyleBoxFlat = null
var _food_variety_label: Label = null
var _pop_count_label: Label = null

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
	EventBus.gold_changed.connect(_on_gold_changed)
	EventBus.milestone_earned.connect(_on_milestone_earned)
	EventBus.blessing_bestowed.connect(func(_pid, _spent): show_notification(
		"A Blessing is bestowed upon your realm — popularity rises and your buildings are warded against fire.",
		5.0, Color(0.85, 0.9, 1.0)))

func _on_tick(tick: int) -> void:
	_refresh_top_bar()
	if tick % 20 == 0:
		_refresh_right_panel()
		_refresh_build_menu()
	_check_crisis_alerts()

func _check_crisis_alerts() -> void:
	if GameState.players.size() == 0: return
	var p: Dictionary = GameState.players[0]
	var starving: bool = p.get("is_starving", false)
	var diseased: bool = p.get("disease_active", false)
	if starving and not _was_starving:
		var ration: int = int(p.get("food_ration", 2))
		var cause: String = "No rations set!" if ration == 0 else "Food stores depleted!"
		show_notification("STARVATION: %s Popularity falling fast." % cause, 5.0, Color(1.0, 0.35, 0.35))
	elif not starving and _was_starving:
		show_notification("Food crisis resolved — peasants fed.", 3.0, Color(0.4, 1.0, 0.5))
	if diseased and not _had_disease:
		show_notification("DISEASE OUTBREAK: Population falling ill. Reduce crowding.", 5.0, Color(1.0, 0.55, 0.1))
	elif not diseased and _had_disease:
		show_notification("Disease cleared — population recovering.", 3.0, Color(0.4, 1.0, 0.5))
	_was_starving = starving
	_had_disease  = diseased

func _on_milestone_earned(_player_id: int, milestone_id: String, prestige_bonus: float) -> void:
	const MilestoneSystem = preload("res://simulation/core/MilestoneSystem.gd")
	var label: String = MilestoneSystem.get_label(milestone_id)
	show_notification("Milestone: %s  (+%.0f prestige)" % [label, prestige_bonus], 6.0, Color(1.0, 0.85, 0.2))

func _on_gold_changed(_player_id: int, old_amount: int, new_amount: int) -> void:
	_refresh_top_bar()
	var delta: int = new_amount - old_amount
	if delta != 0:
		_spawn_gold_flash(delta)

func _spawn_gold_flash(delta: int) -> void:
	var lbl := Label.new()
	lbl.text = "+%d" % delta if delta > 0 else str(delta)
	lbl.add_theme_font_size_override("font_size", 13)
	lbl.add_theme_color_override("font_color",
		Color(0.4, 1.0, 0.4) if delta > 0 else Color(1.0, 0.4, 0.4))
	# Position near the gold label in the top bar (top-left of screen)
	lbl.position = Vector2(8, 38)
	lbl.size = Vector2(80, 20)
	add_child(lbl)
	var tw: Tween = create_tween()
	tw.set_parallel(true)
	tw.tween_property(lbl, "position:y", lbl.position.y - 32.0, 1.4)
	tw.tween_property(lbl, "modulate:a", 0.0, 1.4)
	tw.tween_callback(lbl.queue_free).set_delay(1.4)

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
	style.bg_color = Color(0.13, 0.10, 0.07, 0.94)        # warm parchment-dark
	style.set_corner_radius_all(7)
	style.set_border_width_all(2)
	style.border_color = Color(0.74, 0.57, 0.26, 0.95)    # gold trim
	style.shadow_color = Color(0.0, 0.0, 0.0, 0.45)
	style.shadow_size = 7
	style.set_content_margin_all(6)
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
		callback: Callable, tooltip: String = "") -> Button:
	var btn := Button.new()
	btn.text = text
	btn.position = pos
	btn.size = sz
	btn.add_theme_font_size_override("font_size", 12)
	btn.add_theme_color_override("font_color", Color(0.93, 0.88, 0.74))
	btn.add_theme_color_override("font_hover_color", Color(1.0, 0.95, 0.7))
	if tooltip != "":
		btn.tooltip_text = tooltip
	var normal_sty := StyleBoxFlat.new()
	normal_sty.bg_color = Color(0.18, 0.14, 0.09, 0.95)
	normal_sty.set_corner_radius_all(5)
	normal_sty.set_border_width_all(1)
	normal_sty.border_color = Color(0.55, 0.43, 0.20, 0.9)
	normal_sty.set_content_margin_all(4)
	btn.add_theme_stylebox_override("normal", normal_sty)
	var hover_sty := normal_sty.duplicate()
	hover_sty.bg_color = Color(0.33, 0.25, 0.12, 0.98)
	hover_sty.border_color = Color(0.86, 0.68, 0.30, 1.0)
	btn.add_theme_stylebox_override("hover", hover_sty)
	var pressed_sty := normal_sty.duplicate()
	pressed_sty.bg_color = Color(0.12, 0.09, 0.05, 1.0)
	btn.add_theme_stylebox_override("pressed", pressed_sty)
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
	_weather_label = _add_label(_top_bar, "Clear",       Vector2(x, 8), 12, Color.LIGHT_CYAN); x += 160
	_prestige_label = _add_label(_top_bar, "Prestige: 0", Vector2(x, 8), 12, Color(0.95, 0.8, 0.3)); x += 130
	_faith_label = _add_label(_top_bar, "Faith: 0", Vector2(x, 8), 12, Color(0.75, 0.85, 1.0)); x += 130
	_health_label = _add_label(_top_bar, "Health: 100", Vector2(x, 8), 12, Color(0.6, 0.9, 0.6))

func _refresh_top_bar() -> void:
	if GameState.players.size() == 0:
		return
	var p: Dictionary = GameState.players[0]
	var res: Dictionary = p.get("resources", {})
	var food: Dictionary = p.get("food", {})
	var total_food: int = HUDController.get_total_food(p)
	var total_ale: int  = int(food.get("ale", 0))
	_gold_label.text         = "Gold: %d" % int(p.get("gold", 0))
	_gold_label.tooltip_text = HUDController.get_gold_tooltip(p, GameState.world)
	_wood_label.text    = "Wood: %d" % int(res.get("wood", 0))
	_stone_label.text   = "Stone: %d" % int(res.get("stone", 0))
	_iron_label.text    = "Iron: %d" % int(res.get("iron", 0))
	_food_label.text    = "Food: %d" % total_food
	_ale_label.text     = "Ale: %d" % total_ale
	_day_label.text     = "Day %d" % SimulationClock.game_day()
	var _wicon: String = HUDController.get_weather_icon(GameState.weather)
	_weather_label.text = "%s %s" % [_wicon, WeatherSystem.weather_name(GameState.weather.get("current", 0))]
	_weather_label.tooltip_text = HUDController.get_weather_tooltip(GameState.weather)
	if _prestige_label != null:
		_prestige_label.text = "Prestige: %d" % int(p.get("prestige", 0.0))
	if _faith_label != null:
		var _blessed: bool = int(p.get("blessing_until", 0)) > SimulationClock.current_tick
		_faith_label.text = "Faith: %d/%d%s" % [int(p.get("faith", 0.0)), int(p.get("faith_cap", 0.0)),
			"  ✝" if _blessed else ""]
		_faith_label.modulate = Color(1.0, 0.95, 0.5) if _blessed else Color.WHITE
		_faith_label.tooltip_text = "Faith from churches, cathedrals and monks. At %d Faith a Blessing fires: +6 popularity and 3 days of fire protection." % int(ReligionSystem.BLESSING_THRESHOLD)
	if _health_label != null:
		var _hp: int = int(p.get("health", 100.0))
		var _diseased: bool = p.get("disease_active", false)
		if _diseased:
			_health_label.text = "Plague! %d%%" % int(p.get("disease_severity", 0.0))
			_health_label.modulate = Color(0.9, 0.4, 0.4)
			_health_label.tooltip_text = "A plague rages (severity %d/100). Apothecaries cure it; wells and food variety raise health to prevent outbreaks." % int(p.get("disease_severity", 0.0))
		else:
			_health_label.text = "Health: %d" % _hp
			_health_label.modulate = Color(0.6, 0.9, 0.6) if _hp >= 60 else Color(0.95, 0.85, 0.4)
			_health_label.tooltip_text = "Public health %d/100 from sanitation (apothecaries + wells), food variety and weather. Low health risks plague." % _hp
	var _crit: Array   = HUDController.get_critical_resources(p)
	var _alert: Color  = Color(1.0, 0.28, 0.28)
	var _norm: Color   = Color.WHITE
	_gold_label.add_theme_color_override("font_color",  _alert if "gold"  in _crit else _norm)
	_wood_label.add_theme_color_override("font_color",  _alert if "wood"  in _crit else _norm)
	_stone_label.add_theme_color_override("font_color", _alert if "stone" in _crit else _norm)
	_iron_label.add_theme_color_override("font_color",  _alert if "iron"  in _crit else _norm)
	_food_label.add_theme_color_override("font_color",  _alert if "food"  in _crit else _norm)

# ── Right panel ───────────────────────────────────────────────────────────────

func _build_right_panel() -> void:
	_add_label(_right_panel, "POPULARITY", Vector2(6, 6), 11, Color.LIGHT_YELLOW)
	_pop_bar = ProgressBar.new()
	_pop_bar.position = Vector2(6, 24)
	_pop_bar.size = Vector2(204, 18)
	_pop_bar.min_value = 0; _pop_bar.max_value = 100; _pop_bar.value = 50
	_pop_bar_fill = StyleBoxFlat.new()
	_pop_bar_fill.bg_color = Color(0.55, 0.76, 0.29)  # "good" green default
	_pop_bar.add_theme_stylebox_override("fill", _pop_bar_fill)
	_right_panel.add_child(_pop_bar)
	_pop_label = _add_label(_right_panel, "50%", Vector2(84, 24), 11)

	_add_label(_right_panel, "Tax Rate:", Vector2(6, 50), 11)
	_tax_label_disp = _add_label(_right_panel, "0 (None)", Vector2(90, 50), 11)
	_tax_delta_label = _add_label(_right_panel, "", Vector2(154, 50), 9, Color.GRAY)
	_tax_delta_label.size = Vector2(60, 20)
	_add_button(_right_panel, "−", Vector2(6, 66), Vector2(30, 22), func(): _change_tax(-1),
		"Lower tax rate\nReduces income, improves popularity")
	_add_button(_right_panel, "+", Vector2(40, 66), Vector2(30, 22), func(): _change_tax(1),
		"Raise tax rate\nIncreases income, reduces popularity")
	_add_label(_right_panel, "◄Bribe  Free  Tax►", Vector2(74, 69), 8, Color(0.5, 0.5, 0.5))

	_add_label(_right_panel, "Food Ration:", Vector2(6, 98), 11)
	_food_ration_label = _add_label(_right_panel, "Normal", Vector2(112, 98), 11, Color.LIGHT_GREEN)
	_food_ration_delta = _add_label(_right_panel, "", Vector2(154, 98), 9, Color.GRAY)
	_food_ration_delta.size = Vector2(60, 20)
	_add_button(_right_panel, "−", Vector2(6, 114), Vector2(30, 22), func(): _change_food_ration(-1),
		"Reduce food rations\nSaves food, reduces popularity")
	_add_button(_right_panel, "+", Vector2(40, 114), Vector2(30, 22), func(): _change_food_ration(1),
		"Increase food rations\nBoosts popularity, uses more food")
	_add_label(_right_panel, "◄None  Norm  Dbl►", Vector2(74, 117), 8, Color(0.5, 0.5, 0.5))

	_add_label(_right_panel, "Ale Ration:", Vector2(6, 146), 11)
	_ale_ration_label = _add_label(_right_panel, "Half", Vector2(112, 146), 11, Color.LIGHT_BLUE)
	_ale_ration_delta = _add_label(_right_panel, "", Vector2(154, 146), 9, Color.GRAY)
	_ale_ration_delta.size = Vector2(60, 20)
	_add_button(_right_panel, "−", Vector2(6, 162), Vector2(30, 22), func(): _change_ale_ration(-1),
		"Reduce ale rations\nSaves ale, reduces popularity")
	_add_button(_right_panel, "+", Vector2(40, 162), Vector2(30, 22), func(): _change_ale_ration(1),
		"Increase ale rations\nBoosts popularity, uses more ale")
	_add_label(_right_panel, "◄None  Half  Dbl►", Vector2(74, 165), 8, Color(0.5, 0.5, 0.5))

	_food_variety_label = _add_label(_right_panel, "Variety: none", Vector2(6, 186), 9, Color.GRAY)
	_food_variety_label.size = Vector2(206, 18)

	_add_label(_right_panel, "Prestige:", Vector2(6, 206), 11, Color.LIGHT_YELLOW)
	_pop_count_label = _add_label(_right_panel, "Pop: 0", Vector2(6, 222), 11, Color.LIGHT_CYAN)

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
	_pop_label.tooltip_text = HUDController.get_popularity_breakdown_tooltip(p)
	_pop_bar_fill.bg_color = col
	var _tr: int = int(p.get("tax_rate", 0))
	_tax_label_disp.text = HUDController.get_tax_label(_tr)
	_tax_label_disp.tooltip_text = HUDController.get_tax_tooltip(_tr)
	_food_ration_label.text = HUDController.get_ration_label(int(p.get("food_ration", 2)))
	_ale_ration_label.text  = HUDController.get_ration_label(int(p.get("ale_ration", 1)))

	if _tr < 0:
		_tax_delta_label.text = "↑pop"
		_tax_delta_label.add_theme_color_override("font_color", Color.LIGHT_GREEN)
	elif _tr == 0:
		_tax_delta_label.text = "neutral"
		_tax_delta_label.add_theme_color_override("font_color", Color.GRAY)
	else:
		_tax_delta_label.text = "↓pop"
		_tax_delta_label.add_theme_color_override("font_color", Color.ORANGE_RED)

	var food_lvl: int = int(p.get("food_ration", 2))
	if food_lvl < 2:
		_food_ration_delta.text = "↓pop"
		_food_ration_delta.add_theme_color_override("font_color", Color.ORANGE_RED)
	elif food_lvl == 2:
		_food_ration_delta.text = "normal"
		_food_ration_delta.add_theme_color_override("font_color", Color.GRAY)
	else:
		_food_ration_delta.text = "↑pop"
		_food_ration_delta.add_theme_color_override("font_color", Color.LIGHT_GREEN)

	var ale_lvl: int = int(p.get("ale_ration", 1))
	if ale_lvl == 0:
		_ale_ration_delta.text = "↓pop"
		_ale_ration_delta.add_theme_color_override("font_color", Color.ORANGE_RED)
	elif ale_lvl == 1:
		_ale_ration_delta.text = "½ bonus"
		_ale_ration_delta.add_theme_color_override("font_color", Color.GRAY)
	else:
		_ale_ration_delta.text = "↑pop"
		_ale_ration_delta.add_theme_color_override("font_color", Color.LIGHT_GREEN)

	if _pop_count_label != null:
		_pop_count_label.text = "Pop: %d" % int(p.get("population", 0))

	var var_bonus: int = HUDController.get_food_variety_bonus(p)
	var var_types: Array = HUDController.get_food_variety_types(p)
	if var_bonus > 0:
		_food_variety_label.text = "Variety +%d pop: %s" % [var_bonus, ", ".join(var_types)]
		_food_variety_label.add_theme_color_override("font_color", Color.LIGHT_GREEN)
	else:
		_food_variety_label.text = "Variety: none (diversify food for bonus)"
		_food_variety_label.add_theme_color_override("font_color", Color.GRAY)

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
	var cat_tips: Array  = [
		"Civic buildings: housing, wells, markets",
		"Harvest buildings: farms, mines, woodcutters",
		"Food production: mills, bakeries, fisheries",
		"Military: barracks, stables, training grounds",
		"Defenses: walls, towers, gates",
	]
	var cat_x: float = 120.0
	for i in range(cat_names.size()):
		var ci: int = i
		var btn: Button = _add_button(_build_menu, cat_names[i], Vector2(cat_x, 2),
			Vector2(70, 20), func(): _show_build_category(ci), cat_tips[i])
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
		var reason: String = ""
		if not tech_ok:
			reason = "\nRequires: %s" % ", ".join(req_tech)
		elif not can_afford:
			reason = "\n(Cannot afford)"
		build_btn.tooltip_text = "Place %s\n%s%s" % [name_str, cost_str, reason]
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
	var speeds: Array = [
		["❚❚",      0, "Pause game"],
		["▶ 1×",    1, "Normal speed (1×)"],
		["▶▶ 2×",   2, "Fast speed (2×)"],
		["▶▶▶ 5×",  3, "Very fast speed (5×)"],
	]
	var x: float = 6.0
	for s in speeds:
		var sp: int = s[1]
		_add_button(_bottom_bar, s[0], Vector2(x, 4), Vector2(56, 26),
			func(): speed_changed.emit(sp), s[2])
		x += 60

	_add_button(_bottom_bar, "⊞ Macro [Tab]", Vector2(x + 10, 4), Vector2(110, 26),
		func(): macro_view_toggled.emit(), "Toggle world map view (Tab)")
	_add_button(_bottom_bar, "🔬 Tech", Vector2(x + 130, 4), Vector2(70, 26),
		func(): _toggle_tech_panel(), "Open technology tree")
	_add_button(_bottom_bar, "📜 Edicts", Vector2(x + 208, 4), Vector2(80, 26),
		func(): _toggle_edict_panel(), "Open royal edicts panel")
	_add_button(_bottom_bar, "💾 Save", Vector2(x + 296, 4), Vector2(70, 26),
		func(): save_requested.emit(), "Save game")

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
		"YES" if building.get("is_on_fire", false) else "No",
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
			var gold_cost: int = udefn.get("cost_gold", 0)
			var unit_hp: int = udefn.get("max_hp", 0)
			var atk: int = udefn.get("attack", 0)
			var tip_base: String = "%s · Cost: %dg · HP: %d · Atk: %d" % [udefn.get("name", utype), gold_cost, unit_hp, atk]
			rb.tooltip_text = tip_base if check.get("ok", false) else "%s\n%s" % [tip_base, check.get("reason", "Cannot recruit")]
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
	const CAT_DISPLAY: Dictionary = {
		"civilian":       ["CIVILIAN",  Color(0.70, 0.70, 0.70)],
		"light_infantry": ["LIGHT INF", Color(0.50, 1.00, 0.50)],
		"heavy_infantry": ["HEAVY INF", Color(1.00, 0.80, 0.30)],
		"siege":          ["SIEGE",     Color(1.00, 0.42, 0.42)],
	}
	const ATK_DISPLAY: Dictionary = {
		"none":   "-",
		"melee":  "MELEE",
		"pierce": "PIERCE",
		"siege":  "SIEGE",
	}
	var cat: String   = defn.get("category", "civilian")
	var cat_d: Array  = CAT_DISPLAY.get(cat, ["?", Color.GRAY])
	var atk_s: String = ATK_DISPLAY.get(defn.get("attack_type", "none"), "-")
	_sel_workers_label.text = "[%s · %s]" % [cat_d[0], atk_s]
	_sel_workers_label.add_theme_color_override("font_color", cat_d[1])
	for c in _sel_actions.get_children(): c.queue_free()

func clear_selection() -> void:
	if not _sel_title: return
	_sel_title.text = "Nothing selected"
	_sel_info.text = ""
	_sel_workers_label.text = ""
	_sel_workers_label.remove_theme_color_override("font_color")
	for c in _sel_actions.get_children(): c.queue_free()

func _set_workers_on_building(bid: int, count: int) -> void:
	CommandQueue.enqueue(9, {"building_id": bid, "workers": count}, 0)

func _add_market_actions(_building: Dictionary) -> void:
	var trade_resources: Array = ["wood", "stone", "iron", "gold"]
	var world: Dictionary = GameState.world
	for res in trade_resources:
		var r: String = res
		var trend: String = HUDController.get_market_trend(r, world)
		var mp: Dictionary = HUDController.get_market_prices(r, world)
		var trend_note: String = (
			"↑ above normal — good time to sell" if trend == "↑" else
			"↓ below normal — good time to buy" if trend == "↓" else
			"→ at normal price"
		)
		var buy_btn := Button.new()
		buy_btn.text = "%s %s" % [trend, r.left(2).to_upper()]
		buy_btn.add_theme_font_size_override("font_size", 9)
		buy_btn.custom_minimum_size = Vector2(52, 22)
		var hist_tip: String = HUDController.get_market_history_tooltip(r, world)
		buy_btn.tooltip_text = "Buy 10 %s · Cost: %s each\n%s\n%s" % [r, mp["buy"], trend_note, hist_tip]
		buy_btn.pressed.connect(func(): trade_buy_requested.emit(r, 10))
		_sel_actions.add_child(buy_btn)
		var sell_btn := Button.new()
		sell_btn.text = "Sell"
		sell_btn.add_theme_font_size_override("font_size", 9)
		sell_btn.custom_minimum_size = Vector2(34, 22)
		sell_btn.tooltip_text = "Sell 10 %s · Receive: %s each\n%s\n%s" % [r, mp["sell"], trend_note, hist_tip]
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
		var hint: String = TechTreePanelController.get_tech_hint_text(item)
		btn.tooltip_text = "Research %s for %d prestige\n%s" % [item.get("name", ""), int(item.get("cost_prestige", 0)), hint]
		btn.pressed.connect(func(): tech_research_requested.emit(tech_id))
		row.add_child(btn)

func _toggle_tech_panel() -> void:
	_edict_panel.visible = false
	if _tech_panel.visible:
		_animate_panel_close(_tech_panel)
	else:
		_refresh_tech_panel()
		_animate_panel_open(_tech_panel)

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
			btn.tooltip_text = "Activate '%s'\nCosts %d edict points" % [item.get("name", ""), int(item.get("cost_points", 0))]
			btn.pressed.connect(func(): edict_activate_requested.emit(eid))
			row.add_child(btn)

func _toggle_edict_panel() -> void:
	_tech_panel.visible = false
	if _edict_panel.visible:
		_animate_panel_close(_edict_panel)
	else:
		_refresh_edict_panel()
		_animate_panel_open(_edict_panel)

func _animate_panel_open(panel: Panel) -> void:
	panel.modulate.a = 0.0
	panel.visible = true
	create_tween().tween_property(panel, "modulate:a", 1.0, 0.18)

func _animate_panel_close(panel: Panel) -> void:
	var tw: Tween = create_tween()
	tw.tween_property(panel, "modulate:a", 0.0, 0.14)
	tw.tween_callback(func(): panel.visible = false; panel.modulate.a = 1.0)

# ── Notification system ───────────────────────────────────────────────────────

func show_notification(text: String, duration: float = 3.0, color: Color = Color.YELLOW) -> void:
	if _notification_feed == null: return
	_notification_feed.push(text, duration, color)

func set_build_mode_display(building_type: String) -> void:
	if _build_mode_label:
		_build_mode_label.text = "Mode: %s" % (building_type if building_type != "" else "Select")
