extends CanvasLayer
# Complete game HUD built programmatically.
# Panels: TopBar (resources), RightPanel (popularity/rations/tax),
# BuildMenu (building buttons), BottomBar (speed/view controls),
# SelectionPanel (selected entity info), TechTreePanel, EdictPanel.

const HUDController = preload("res://view/hud/HUDController.gd")
const TechTreePanelController = preload("res://view/hud/TechTreePanelController.gd")
const EdictPanelController = preload("res://view/hud/EdictPanelController.gd")
const BuildingRegistry = preload("res://simulation/buildings/BuildingRegistry.gd")
const ObjectiveSystem = preload("res://simulation/core/ObjectiveSystem.gd")
const TechTree = preload("res://simulation/tech/TechTree.gd")
const StorageSystem = preload("res://simulation/economy/StorageSystem.gd")
const FoodSystem = preload("res://simulation/economy/FoodSystem.gd")
const SunMoonClock = preload("res://view/hud/SunMoonClock.gd")
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
var _objective_panel: Panel = null
var _objective_label: Label = null
var _objective_progress: Label = null
var _objective_goal_label: Label = null   # always-visible "Climb to King — you rule as Reeve [pips]"
var _macro_btn: Button = null             # world-map button (glowed when an expansion objective is up)
var _macro_glow_tween: Tween = null
var _was_starving: bool = false

# Resource labels
var _gold_label: Label = null
var _wood_label: Label = null
var _stone_label: Label = null
var _iron_label: Label = null
var _storage_label: Label = null
var _food_label: Label = null
var _food_caption: Label = null   # dynamic "Food · Nd" with a famine warning colour
var _ale_label: Label = null
var _day_label: Label = null
var _time_clock: Control = null   # SunMoonClock — day-cycle clock
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
var _build_mode_banner: Panel = null      # prominent centre-bottom "click the ground" prompt
var _build_mode_banner_label: Label = null
var _tab_pulse_tween: Tween = null  # active attention-flash on an auto-re-pointed tab
var _current_build_category: int = 0  # CIVIC by default — matches the first objective (build a Village Hall)

# Speed buttons
var _speed_btns: Array = []

# Selection panel
var _sel_header: Label = null                  # the panel's top header ("SELECTED" / "YOUR REALM")
var _sel_title: Label = null
var _sel_info: Label = null
var _sel_workers_label: Label = null
var _sel_actions: HBoxContainer = null
var _sel_full_size: Vector2 = Vector2.ZERO     # full panel size (restored on selection)
var _sel_has_selection: bool = false           # collapsed-to-slim-bar when false
var _realm_refresh_accum: float = 0.0          # throttles the idle realm-summary refresh

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
	EventBus.objective_updated.connect(_on_objective_updated)
	EventBus.objective_completed.connect(_on_objective_completed)
	if TutorialSystem.has_signal("tutorial_step_changed"):
		TutorialSystem.tutorial_step_changed.connect(_on_tutorial_step)
	EventBus.blessing_bestowed.connect(func(_pid, _spent): show_notification(
		"A Blessing is bestowed upon your realm — popularity rises and your buildings are warded against fire.",
		5.0, Color(0.85, 0.9, 1.0)))
	# Populate the panels ONCE from the real state now — the HUD otherwise only refreshes on a
	# sim tick, but a fresh game opens PAUSED on the tutorial prompt (no ticks), so the player's
	# very first screen would show hardcoded placeholders (e.g. "Population: 0" with 20 villagers).
	if not GameState.players.is_empty():
		_refresh_top_bar()
		_refresh_right_panel()
		_refresh_build_menu()

# Tutorial advanced: point the build menu at the step's category (pulsing the tab) so the
# highlighted target building is on screen, ready to press.
func _on_tutorial_step(_idx: int) -> void:
	var t: Dictionary = TutorialSystem.current_target()
	if String(t.get("kind", "")) == "build":
		_show_build_category(int(t.get("cat", _current_build_category)), true)
	else:
		_refresh_build_menu()

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
	if starving and not _was_starving:
		var ration: int = int(p.get("food_ration", 2))
		var cause: String = "No rations set!" if ration == 0 else "Food stores depleted!"
		show_notification("STARVATION: %s Popularity falling fast." % cause, 5.0, Color(1.0, 0.35, 0.35))
	elif not starving and _was_starving:
		show_notification("Food crisis resolved — peasants fed.", 3.0, Color(0.4, 1.0, 0.5))
	# Disease onset/clear is announced ONCE via GameState's realm_notice (shown in BOTH the city HUD
	# and the world-map feed, and carrying the cure/prevention advice) — so it is NOT duplicated here.
	# Starvation has no such realm_notice, so the HUD remains its sole alert. (iter302: was double-toasting.)
	_was_starving = starving

func _on_milestone_earned(_player_id: int, milestone_id: String, prestige_bonus: float) -> void:
	const MilestoneSystem = preload("res://simulation/core/MilestoneSystem.gd")
	var label: String = MilestoneSystem.get_label(milestone_id)
	show_notification("Milestone: %s  (+%.0f prestige)" % [label, prestige_bonus], 6.0, Color(1.0, 0.85, 0.2))

func _on_objective_updated(index: int, total: int, text: String) -> void:
	if _objective_label != null:
		_objective_label.text = text
	if _objective_progress != null:
		# 1-based CURRENT step — the old "(completed/total)" read as stuck on "(0/9)" while on task 1.
		_objective_progress.text = "%d/%d" % [mini(index + 1, total), total]
	_refresh_goal_footer()
	# The expansion objectives are the only path past Bailiff, yet the world map is never otherwise
	# pointed at. Glow the Macro button so the player knows WHERE to go to claim/conquer. (iter352)
	if _macro_btn != null and index >= 0 and index < ObjectiveSystem.OBJECTIVES.size():
		var goid: String = String(ObjectiveSystem.OBJECTIVES[index].get("id", ""))
		_set_macro_glow(goid in ["claim_second", "rise_to_baron", "seize_crown"])
	# Auto-point the build menu at the category the new objective needs, so the player
	# always opens the bar onto the right tab (generalises the iter81 Civic default).
	# Only fires when an objective advances (or day 1); objectives with no build leave it be.
	# While the tutorial is active it OWNS the build tab + highlight, so the objective
	# auto-point must stand down (it was overwriting the current tutorial step).
	if TutorialSystem.is_active():
		return
	if _build_item_container != null and index >= 0 and index < ObjectiveSystem.OBJECTIVES.size():
		var oid: String = String(ObjectiveSystem.OBJECTIVES[index].get("id", ""))
		var cat: int = ObjectiveSystem.build_category_for(oid)
		if cat >= 0:
			_show_build_category(cat, true)  # pulse the tab — show the player it re-pointed

# Always-visible gold footer on the OBJECTIVE panel: the ultimate goal (the crown) + how far the
# player's feudal standing has climbed toward it. The core fantasy used to be invisible until the
# final objective; this keeps "you're climbing to King" on screen the whole game. (iter352)
func _refresh_goal_footer() -> void:
	if _objective_goal_label == null:
		return
	var FR = preload("res://simulation/strategic/FeudalRank.gd")
	var idx: int = FR.current_index(GameState.world, GameState.players)
	var king: int = FR.king_index()
	if idx >= king:
		_objective_goal_label.text = "♛ You are KING — the realm is yours."
		return
	var bar: String = ""
	for i in range(king):
		bar += "▰" if i < idx else "▱"
	_objective_goal_label.text = "♛ Climb to King — %s %s" % [FR.title_name(idx), bar]

# Pulse the world-map button gold while an expansion objective is current — the only signpost
# telling a town-builder that the path onward runs through the map.
func _set_macro_glow(on: bool) -> void:
	if _macro_btn == null:
		return
	if _macro_glow_tween != null and _macro_glow_tween.is_valid():
		_macro_glow_tween.kill()
		_macro_glow_tween = null
	if on:
		_macro_glow_tween = create_tween().set_loops()
		_macro_glow_tween.tween_property(_macro_btn, "modulate", Color(1.5, 1.25, 0.65), 0.7).set_trans(Tween.TRANS_SINE)
		_macro_glow_tween.tween_property(_macro_btn, "modulate", Color(1.0, 1.0, 1.0), 0.7).set_trans(Tween.TRANS_SINE)
	else:
		_macro_btn.modulate = Color.WHITE

func _on_objective_completed(_id: String, _text: String) -> void:
	# A little "done!" beat on the objective panel (the feed already logs the text): a bright
	# achievement chime, a green pulse over the panel, and a check-mark that pops in, rises, fades.
	if _objective_panel == null:
		return
	AudioManager.play(AudioManager.SoundEvent.PRESTIGE_GAINED)
	# A green wash that fades — modulate can't brighten a dark panel (it multiplies), so overlay it.
	var flash := ColorRect.new()
	flash.color = Color(0.42, 1.0, 0.48, 0.32)
	flash.size = _objective_panel.size
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_objective_panel.add_child(flash)
	var ft := create_tween()
	ft.tween_property(flash, "color:a", 0.0, 0.75)
	ft.tween_callback(func() -> void:
		if is_instance_valid(flash):
			flash.queue_free())
	var tick := Label.new()
	tick.text = "✓"
	tick.add_theme_font_size_override("font_size", 44)
	tick.add_theme_color_override("font_color", Color(0.55, 1.0, 0.58))
	tick.size = Vector2(60, 60)
	tick.position = Vector2(78, 16)
	tick.pivot_offset = Vector2(30, 30)
	tick.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tick.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	tick.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_objective_panel.add_child(tick)
	tick.scale = Vector2(0.3, 0.3)
	var tw := create_tween()
	tw.tween_property(tick, "scale", Vector2(1.15, 1.15), 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(tick, "position:y", 2.0, 0.95)
	tw.tween_interval(0.25)
	tw.tween_property(tick, "modulate:a", 0.0, 0.45)
	tw.tween_callback(func() -> void:
		if is_instance_valid(tick):
			tick.queue_free())

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
	lbl.position = Vector2(30, 44)
	lbl.size = Vector2(80, 20)
	add_child(lbl)
	var tw: Tween = create_tween()
	tw.set_parallel(true)
	tw.tween_property(lbl, "position:y", lbl.position.y - 32.0, 1.4)
	tw.tween_property(lbl, "modulate:a", 0.0, 1.4)
	tw.tween_callback(lbl.queue_free).set_delay(1.4)

# ── Panel construction ────────────────────────────────────────────────────────

# When watching ANOTHER faction's city (spectator), the player-economy chrome — the resource
# top-bar, the popularity/tax/ration panel, the standing-objective panel and the build menu —
# represents the player's OWN realm, not the spectated town (which runs no live economy). Left
# visible it shows static, uncontrollable numbers that read as a frozen economy ("the wood/food
# never changes"). Hide it while spectating; the spectator banner conveys the city's real state.
# The bottom bar (speed controls + Macro return) stays so the watcher can still pace the view.
func set_spectator_chrome(spectating: bool) -> void:
	for p in [_top_bar, _right_panel, _objective_panel, _build_menu]:
		if p != null:
			p.visible = not spectating

func _build_all_panels() -> void:
	var vp: Vector2 = get_viewport().get_visible_rect().size
	if vp == Vector2.ZERO:
		vp = Vector2(1280, 720)

	_top_bar = _make_panel(Rect2(0, 0, vp.x, 44))
	_build_top_bar(vp)

	_right_panel = _make_panel(Rect2(vp.x - 222, 50, 220, 248))
	_build_right_panel()

	# Standing objective panel — the player's current goal, just below the realm panel. Taller now,
	# so a gold footer can always show the ultimate goal (the crown) + how close standing is — the core
	# fantasy was previously invisible until the very last objective. (iter352)
	_objective_panel = _make_panel(Rect2(vp.x - 222, 304, 220, 110))
	_add_label(_objective_panel, "OBJECTIVE", Vector2(8, 6), 11, Color(1.0, 0.85, 0.35))
	_objective_progress = _add_label(_objective_panel, "", Vector2(150, 6), 10, Color(0.7, 0.8, 0.95))
	_objective_progress.size = Vector2(64, 16)
	_objective_label = _add_label(_objective_panel, "Found your seat — build a Village Hall.",
		Vector2(8, 26), 12, Color(0.93, 0.92, 0.85))
	_objective_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_objective_label.custom_minimum_size = Vector2(202, 52)
	_objective_label.size = Vector2(202, 52)
	_objective_goal_label = _add_label(_objective_panel, "", Vector2(8, 86), 10, Color(1.0, 0.84, 0.42))
	_objective_goal_label.size = Vector2(204, 18)
	_refresh_goal_footer()

	_bottom_bar = _make_panel(Rect2(0, vp.y - 36, vp.x, 34))
	_build_bottom_bar(vp)

	_build_menu = _make_panel(Rect2(0, vp.y - 200, vp.x * 0.65, 162))
	_build_build_menu(vp)

	_selection_panel = _make_panel(Rect2(vp.x * 0.65 + 2, vp.y - 200, vp.x * 0.35 - 222, 162))
	_build_selection_panel()

	_tech_panel = _make_panel(Rect2(vp.x - 440, 50, 438, vp.y - 92))
	_tech_panel.visible = false
	_build_tech_panel()

	_edict_panel = _make_panel(Rect2(vp.x - 440, 50, 438, vp.y - 92))
	_edict_panel.visible = false
	_build_edict_panel()

	# Live event feed — docked on the left under the minimap / World Map button. Keeps a
	# scrollable history; the header toggle drops it down to read past messages.
	_notification_feed = NotificationFeed.new()
	_notification_feed.position = Vector2(4, 236)
	add_child(_notification_feed)

	# Diplomacy panel (tribute demands) — hidden until an envoy arrives
	var diplomacy_panel := preload("res://view/hud/DiplomacyPanel.gd").new()
	diplomacy_panel.position = Vector2(vp.x * 0.5 - 160, vp.y * 0.32)
	add_child(diplomacy_panel)

	# Event choice panel (decisions on World Events) — hidden until a choice-event fires
	var event_panel := preload("res://view/hud/EventChoicePanel.gd").new()
	event_panel.position = Vector2(vp.x * 0.5 - 180, vp.y * 0.28)
	add_child(event_panel)

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

# A small drawn, colour-coded resource icon so the top bar is scannable at a glance
# (the resource name lives in the value label's tooltip). 16×16, drawn via the draw signal.
func _make_res_icon(parent: Control, pos: Vector2, kind: String) -> Control:
	var ic := Control.new()
	ic.position = pos
	ic.size = Vector2(16, 16)
	ic.custom_minimum_size = Vector2(16, 16)
	ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ic.draw.connect(func(): _draw_res_icon(ic, kind))
	parent.add_child(ic)
	return ic

func _draw_res_icon(ci: Control, kind: String) -> void:
	var c := Vector2(8, 8)
	match kind:
		"gold":
			ci.draw_circle(c, 6.5, Color(0.86, 0.68, 0.24))
			ci.draw_arc(c, 6.4, 0, TAU, 14, Color(0.52, 0.39, 0.12), 1.0)
			ci.draw_arc(c, 3.2, 0, TAU, 12, Color(1.0, 0.92, 0.55), 1.0)
		"wood":
			ci.draw_rect(Rect2(1, 4, 14, 3.2), Color(0.55, 0.40, 0.25))
			ci.draw_rect(Rect2(1, 8.5, 14, 3.2), Color(0.45, 0.32, 0.19))
			ci.draw_circle(Vector2(2, 5.6), 1.7, Color(0.68, 0.52, 0.33))
			ci.draw_circle(Vector2(2, 10.1), 1.7, Color(0.62, 0.46, 0.28))
		"stone":
			ci.draw_rect(Rect2(1.5, 3, 13, 10), Color(0.74, 0.72, 0.66))
			ci.draw_line(Vector2(1.5, 8), Vector2(14.5, 8), Color(0.5, 0.49, 0.45), 1.0)
			ci.draw_line(Vector2(8, 3), Vector2(8, 8), Color(0.5, 0.49, 0.45), 1.0)
			ci.draw_line(Vector2(5, 8), Vector2(5, 13), Color(0.5, 0.49, 0.45), 1.0)
			ci.draw_line(Vector2(11, 8), Vector2(11, 13), Color(0.5, 0.49, 0.45), 1.0)
		"iron":
			ci.draw_colored_polygon(PackedVector2Array([Vector2(3, 12), Vector2(13, 12), Vector2(11, 6), Vector2(5, 6)]), Color(0.55, 0.58, 0.64))
			ci.draw_line(Vector2(5, 6), Vector2(11, 6), Color(0.78, 0.82, 0.88), 1.2)
		"stock":
			ci.draw_rect(Rect2(2, 3, 12, 11), Color(0.55, 0.41, 0.25))
			ci.draw_rect(Rect2(2, 3, 12, 11), Color(0.36, 0.26, 0.15), false, 1.2)
			ci.draw_line(Vector2(2.6, 3.6), Vector2(13.4, 13.4), Color(0.36, 0.26, 0.15), 1.0)
			ci.draw_line(Vector2(13.4, 3.6), Vector2(2.6, 13.4), Color(0.36, 0.26, 0.15), 1.0)
		"food":
			ci.draw_circle(Vector2(8, 9), 5.4, Color(0.78, 0.24, 0.20))
			ci.draw_circle(Vector2(6.2, 7.4), 1.6, Color(0.92, 0.45, 0.4))   # highlight
			ci.draw_line(Vector2(8, 4), Vector2(8, 2), Color(0.4, 0.28, 0.16), 1.2)  # stem
			ci.draw_colored_polygon(PackedVector2Array([Vector2(8, 3), Vector2(11, 2), Vector2(9.5, 4.2)]), Color(0.3, 0.55, 0.25))  # leaf
		"ale":
			ci.draw_rect(Rect2(3, 5, 8, 9), Color(0.80, 0.58, 0.22))         # mug body
			ci.draw_rect(Rect2(3, 3.5, 8, 2.4), Color(0.95, 0.93, 0.86))     # foam
			ci.draw_arc(Vector2(11.5, 9), 3.0, -PI * 0.5, PI * 0.5, 8, Color(0.62, 0.45, 0.18), 1.4)  # handle

func _top_divider(x: float) -> void:
	var d := ColorRect.new()
	d.color = Color(0.74, 0.57, 0.26, 0.45)
	d.position = Vector2(x, 11)
	d.size = Vector2(1.5, 22)
	d.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_top_bar.add_child(d)

func _top_value(text: String, x: float, w: float, size_pt: int = 14, color: Color = Color.WHITE) -> Label:
	# Resource values sit slightly higher (y=5) to leave room for a tiny caption beneath.
	var lbl := _add_label(_top_bar, text, Vector2(x, 5), size_pt, color)
	lbl.size = Vector2(w, 18)
	return lbl

# A tiny upper-case caption beneath a resource icon/value so a new player can read what
# the bare number means at a glance (the full description still lives in the value tooltip).
func _res_caption(text: String, x: float, w: float) -> Label:
	var cap := _add_label(_top_bar, text, Vector2(x, 28), 8, Color(0.70, 0.64, 0.50))
	cap.size = Vector2(w, 12)
	cap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return cap

func _build_top_bar(vp: Vector2) -> void:
	var x: float = 10.0
	# ── Resources: colour-coded icon + value + caption (full name in the value tooltip) ──
	_make_res_icon(_top_bar, Vector2(x, 6), "gold");  _res_caption("Gold", x, 64);  x += 20
	_gold_label    = _top_value("0", x, 46); x += 50
	_make_res_icon(_top_bar, Vector2(x, 6), "wood");  _res_caption("Wood", x, 60);  x += 20
	_wood_label    = _top_value("0", x, 42); x += 46
	_make_res_icon(_top_bar, Vector2(x, 6), "stone"); _res_caption("Stone", x, 60); x += 20
	_stone_label   = _top_value("0", x, 42); x += 46
	_make_res_icon(_top_bar, Vector2(x, 6), "iron");  _res_caption("Iron", x, 60);  x += 20
	_iron_label    = _top_value("0", x, 42); x += 46
	_make_res_icon(_top_bar, Vector2(x, 6), "stock"); _res_caption("Storage", x, 84); x += 20
	_storage_label = _top_value("0/0", x, 66, 13, Color(0.82, 0.76, 0.6)); x += 70
	_make_res_icon(_top_bar, Vector2(x, 6), "food");  _food_caption = _res_caption("Food", x, 84);  x += 20
	_food_label    = _top_value("0/0", x, 66); x += 70
	_make_res_icon(_top_bar, Vector2(x, 6), "ale");   _res_caption("Ale", x, 60);   x += 20
	_ale_label     = _top_value("0", x, 42); x += 46
	_top_divider(x); x += 14
	# ── World: day-cycle clock + season/weather ──
	_time_clock = SunMoonClock.new()
	_time_clock.position = Vector2(x, 6)
	_time_clock.size = Vector2(150, 40)
	_top_bar.add_child(_time_clock)
	x += 158
	_weather_label = _top_value("Clear", x, 176, 13, Color.LIGHT_CYAN); x += 180
	_top_divider(x); x += 14
	# ── Realm: prestige / faith / health ──
	_prestige_label = _top_value("Prestige: 0", x, 116, 13, Color(0.95, 0.8, 0.3)); x += 120
	_faith_label    = _top_value("Faith: 0", x, 116, 13, Color(0.75, 0.85, 1.0)); x += 118
	_health_label   = _top_value("Health: 100", x, 116, 13, Color(0.6, 0.9, 0.6))
	# Descriptive name tooltips for every resource value. Gold/storage/food get a richer,
	# live tooltip rebuilt each refresh; these are sensible defaults before the first tick.
	_gold_label.tooltip_text  = "Gold — your treasury. Spent on buildings, units and trade."
	_wood_label.tooltip_text  = "Wood — timber for building and tools."
	_stone_label.tooltip_text = "Stone — masonry for walls and grand buildings."
	_iron_label.tooltip_text  = "Iron — weapons, armour and tools."
	_storage_label.tooltip_text = "Storage — raw goods stored vs. stockpile capacity. Build stockpiles to store more."
	_food_label.tooltip_text  = "Food — total food vs. granary capacity. Feeds your people each day."
	_ale_label.tooltip_text   = "Ale — brewed from hops; served at inns to keep the people merry."

func _refresh_top_bar() -> void:
	if GameState.players.size() == 0:
		return
	var p: Dictionary = GameState.players[0]
	var res: Dictionary = p.get("resources", {})
	var food: Dictionary = p.get("food", {})
	var total_food: int = HUDController.get_total_food(p)
	var total_ale: int  = int(food.get("ale", 0))
	_gold_label.text         = "%d" % int(p.get("gold", 0))
	_gold_label.tooltip_text = HUDController.get_gold_tooltip(p, GameState.world)
	_wood_label.text    = "%d" % int(res.get("wood", 0))
	_stone_label.text   = "%d" % int(res.get("stone", 0))
	_iron_label.text    = "%d" % int(res.get("iron", 0))
	if _storage_label != null:
		_storage_label.text = "%d/%d" % [StorageSystem.get_stored(p), StorageSystem.get_capacity(p)]
		_storage_label.tooltip_text = "Raw goods stored vs. stockpile capacity. Build stockpiles to store more; production stops when full."
	_food_label.text    = "%d/%d" % [total_food, FoodSystem.get_granary_capacity(p)]
	_food_label.tooltip_text = HUDController.get_food_tooltip(p)
	# Always-visible food-security read under the stock: days of food left, coloured as an early
	# famine warning so starvation (the #1 way a young realm dies) never sneaks up unseen.
	if _food_caption != null:
		var fdays: int = HUDController.get_food_days(p)
		if fdays >= 999:
			_food_caption.text = "Food"
			_food_caption.add_theme_color_override("font_color", Color(0.70, 0.64, 0.50))
		else:
			_food_caption.text = "Food · %dd" % fdays
			_food_caption.add_theme_color_override("font_color",
				Color(0.95, 0.42, 0.34) if fdays <= 2 else (Color(0.95, 0.78, 0.38) if fdays <= 5 else Color(0.66, 0.80, 0.52)))
	_ale_label.text     = "%d" % total_ale
	var _phase: Dictionary = HUDController.get_day_phase(SimulationClock.current_tick)
	if _time_clock != null:
		# Drive the clock from the ACTUAL day/night cycle, not the calendar day.
		_time_clock.set_time(float(_phase.get("cycle_f", 0.0)), bool(_phase.get("is_night", false)),
			String(_phase.get("phase", "Day")), String(_phase.get("season", "")), SimulationClock.calendar_day())
	var _wicon: String = HUDController.get_weather_icon(GameState.weather)
	# Season (sky-day calendar) shown with the weather — both are "what the world is doing".
	_weather_label.text = "%s · %s %s" % [
		_phase.get("season", ""), _wicon, WeatherSystem.weather_name(GameState.weather.get("current", 0))]
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
	_add_label(_right_panel, "POPULARITY", Vector2(6, 5), 11, Color.LIGHT_YELLOW)
	_pop_bar = ProgressBar.new()
	_pop_bar.position = Vector2(6, 22)
	_pop_bar.size = Vector2(206, 20)
	_pop_bar.show_percentage = false
	_pop_bar.min_value = 0; _pop_bar.max_value = 100; _pop_bar.value = 50
	_pop_bar_fill = StyleBoxFlat.new()
	_pop_bar_fill.bg_color = Color(0.55, 0.76, 0.29)  # "good" green default
	_pop_bar_fill.set_corner_radius_all(3)
	_pop_bar.add_theme_stylebox_override("fill", _pop_bar_fill)
	var pop_bg := StyleBoxFlat.new()
	pop_bg.bg_color = Color(0.08, 0.06, 0.04, 0.9)
	pop_bg.set_corner_radius_all(3)
	pop_bg.set_border_width_all(1)
	pop_bg.border_color = Color(0.4, 0.32, 0.16, 0.8)
	_pop_bar.add_theme_stylebox_override("background", pop_bg)
	_right_panel.add_child(_pop_bar)
	# Readout centred over the bar so it never collides with the fill.
	_pop_label = _add_label(_right_panel, "50%", Vector2(6, 23), 12)
	_pop_label.size = Vector2(206, 18)
	_pop_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_pop_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	_pop_label.add_theme_constant_override("shadow_offset_y", 1)

	# Each control row: label (left), value (mid), delta hint (right) — fixed widths, no overlap.
	_make_slider_row("Tax Rate:", 50, func(): _change_tax(-1), func(): _change_tax(1),
		"Lower tax rate — less income, happier people", "Raise tax rate — more income, angrier people",
		"◄ Bribe · Free · Tax ►")
	_tax_label_disp  = _add_label(_right_panel, "0 (None)", Vector2(74, 50), 11); _tax_label_disp.size = Vector2(78, 18)
	_tax_delta_label = _add_label(_right_panel, "", Vector2(156, 50), 9, Color.GRAY); _tax_delta_label.size = Vector2(58, 18)

	_make_slider_row("Food Ration:", 98, func(): _change_food_ration(-1), func(): _change_food_ration(1),
		"Reduce food rations — saves food, lowers popularity", "Increase food rations — boosts popularity, uses more food",
		"◄ None · Norm · Dbl ►")
	_food_ration_label = _add_label(_right_panel, "Normal", Vector2(96, 98), 11, Color.LIGHT_GREEN); _food_ration_label.size = Vector2(56, 18)
	_food_ration_delta = _add_label(_right_panel, "", Vector2(156, 98), 9, Color.GRAY); _food_ration_delta.size = Vector2(58, 18)

	_make_slider_row("Ale Ration:", 146, func(): _change_ale_ration(-1), func(): _change_ale_ration(1),
		"Reduce ale rations — saves ale, lowers popularity", "Increase ale rations — boosts popularity, uses more ale",
		"◄ None · Half · Dbl ►")
	_ale_ration_label = _add_label(_right_panel, "Half", Vector2(96, 146), 11, Color.LIGHT_BLUE); _ale_ration_label.size = Vector2(56, 18)
	_ale_ration_delta = _add_label(_right_panel, "", Vector2(156, 146), 9, Color.GRAY); _ale_ration_delta.size = Vector2(58, 18)

	_food_variety_label = _add_label(_right_panel, "Variety: none", Vector2(6, 192), 9, Color.GRAY)
	_food_variety_label.size = Vector2(208, 16)
	# Divider above the realm totals.
	var div := ColorRect.new(); div.color = Color(0.74, 0.57, 0.26, 0.4)
	div.position = Vector2(6, 210); div.size = Vector2(206, 1)
	_right_panel.add_child(div)
	_add_label(_right_panel, "Population:", Vector2(6, 216), 11, Color.LIGHT_YELLOW)
	_pop_count_label = _add_label(_right_panel, "0", Vector2(120, 216), 11, Color.LIGHT_CYAN)
	_pop_count_label.size = Vector2(94, 18)
	_pop_count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT

# A label + −/+ buttons + a scale hint, shared by the three control rows.
func _make_slider_row(title: String, y: float, dec: Callable, inc: Callable,
		dec_tip: String, inc_tip: String, scale_hint: String) -> void:
	_add_label(_right_panel, title, Vector2(6, y), 11)
	_add_button(_right_panel, "−", Vector2(6, y + 16), Vector2(30, 22), dec, dec_tip)
	_add_button(_right_panel, "+", Vector2(40, y + 16), Vector2(30, 22), inc, inc_tip)
	var hint := _add_label(_right_panel, scale_hint, Vector2(76, y + 20), 8, Color(0.55, 0.5, 0.42))
	hint.size = Vector2(140, 16)

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
	var ale_fx: Dictionary = HUDController.get_ale_ration_effect(ale_lvl, float(p.get("inn_coverage", 0.0)))
	_ale_ration_delta.text = ale_fx.get("text", "")
	var ale_tone: String = ale_fx.get("tone", "neutral")
	var ale_col: Color = Color.GRAY
	if ale_tone == "good":
		ale_col = Color.LIGHT_GREEN
	elif ale_tone == "bad":
		ale_col = Color.ORANGE_RED
	_ale_ration_delta.add_theme_color_override("font_color", ale_col)

	if _pop_count_label != null:
		_pop_count_label.text = "%d" % int(p.get("population", 0))

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
	# Name only buildings that actually exist in each tab — the old tips advertised fisheries,
	# stables and training grounds that aren't in the game, which reads as broken. (iter350)
	var cat_tips: Array  = [
		"Civic: Village Hall, Hovels (homes), Market, Well, Church",
		"Harvest raw goods: Woodcutter, Stone Quarry, Iron Mine, Stockpile",
		"Food: Orchards & farms, Mill, Bakery, Brewery, Granary",
		"Military: Barracks, Blacksmith, Armory, Siege Workshop",
		"Defences: Palisade, Stone Wall, Gatehouse, Towers",
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

	_show_build_category(0)  # Start on CIVIC — the Village Hall (first objective) is here, so a
	# new player following the opening objective sees the right building immediately.

func _show_build_category(cat: int, pulse: bool = false) -> void:
	_current_build_category = cat
	_highlight_category_tab(cat)
	# When the menu re-points itself (objective advanced), flash the tab so the player
	# notices it moved — a silent auto-switch would just be confusing. Manual clicks and
	# affordability refreshes pass pulse=false (the default), so only the auto-path flashes.
	if pulse:
		_pulse_category_tab(cat)
	for child in _build_item_container.get_children():
		child.queue_free()
	_build_item_container.add_theme_constant_override("separation", 6)

	if GameState.players.size() == 0:
		return
	var player: Dictionary = GameState.players[0]
	var buildings: Array = BuildingRegistry.get_by_category(cat)

	# Tutorial gating: during a build step, only the target building is buildable and it
	# is highlighted; everything else is greyed so the player can't get lost.
	var _tut: Dictionary = TutorialSystem.current_target()
	# Only gate/highlight on the target's OWN tab — otherwise switching tabs would grey
	# everything with no visible target.
	var _tut_build: bool = String(_tut.get("kind", "")) == "build" and int(_tut.get("cat", -1)) == cat
	var _tut_target: String = String(_tut.get("build", ""))

	for btype in buildings:
		var defn: Dictionary = BuildingRegistry.lookup(btype)
		var name_str: String = defn.get("name", btype)
		var cost: Dictionary = defn.get("cost", {})
		var cost_str: String = _format_cost(cost)
		var can_afford: bool = _can_afford(cost, player)
		var req_tech: Array  = defn.get("requires_tech", [])
		var tech_ok: bool    = _tech_met(req_tech, player)
		var enabled: bool    = can_afford and tech_ok
		var is_tut_target: bool = _tut_build and btype == _tut_target
		if _tut_build and not is_tut_target:
			enabled = false   # tutorial: only the highlighted target may be built

		# Each building is a proper card: bordered, padded panel, with a state colour.
		var card := PanelContainer.new()
		card.custom_minimum_size = Vector2(120, 140)
		var card_sty := StyleBoxFlat.new()
		card_sty.bg_color = (Color(0.22, 0.17, 0.09, 0.99) if is_tut_target
			else (Color(0.17, 0.13, 0.08, 0.96) if enabled else Color(0.12, 0.10, 0.08, 0.92)))
		card_sty.set_corner_radius_all(5)
		card_sty.set_border_width_all(3 if is_tut_target else 1)
		card_sty.border_color = (Color(1.0, 0.85, 0.25) if is_tut_target
			else (Color(0.62, 0.49, 0.22, 0.95) if enabled else Color(0.34, 0.30, 0.26, 0.8)))
		card_sty.set_content_margin_all(6)
		card.add_theme_stylebox_override("panel", card_sty)
		_build_item_container.add_child(card)

		var vb := VBoxContainer.new()
		vb.add_theme_constant_override("separation", 4)
		card.add_child(vb)

		var name_lbl := Label.new()
		name_lbl.text = ("▶ " + name_str) if is_tut_target else name_str
		name_lbl.add_theme_font_size_override("font_size", 12)
		name_lbl.add_theme_color_override("font_color",
			Color(0.97, 0.92, 0.78) if enabled else Color(0.55, 0.52, 0.48))
		name_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		name_lbl.custom_minimum_size = Vector2(108, 30)
		vb.add_child(name_lbl)

		var cost_lbl := Label.new()
		# Readable lock reason ("Requires Advanced Masonry"), wrapped so words aren't clipped.
		cost_lbl.text = cost_str if tech_ok else "Requires %s" % _humanize_tech_list(req_tech)
		cost_lbl.add_theme_font_size_override("font_size", 10)
		cost_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		cost_lbl.custom_minimum_size = Vector2(108, 0)
		cost_lbl.add_theme_color_override("font_color",
			(Color(0.62, 0.86, 0.42) if can_afford else Color(0.9, 0.45, 0.35)) if tech_ok else Color(0.7, 0.66, 0.5))
		vb.add_child(cost_lbl)

		# What the building DOES — so a new player isn't left guessing what an "Apothecary" is.
		var desc: String = _clean_desc(String(defn.get("description", "")))
		var desc_lbl := Label.new()
		desc_lbl.text = desc
		desc_lbl.add_theme_font_size_override("font_size", 9)
		desc_lbl.add_theme_color_override("font_color",
			Color(0.76, 0.72, 0.62) if enabled else Color(0.5, 0.47, 0.42))
		desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc_lbl.clip_text = true
		desc_lbl.custom_minimum_size = Vector2(108, 40)
		desc_lbl.size_flags_vertical = Control.SIZE_EXPAND_FILL
		vb.add_child(desc_lbl)

		# Production-chain input — building a Bakery with no Mill to feed it is the #1 "economy feels
		# broken" trap. Name what it consumes, in red when the player produces none of that input. (iter351)
		var consumes: Dictionary = defn.get("consumes", {})
		if not consumes.is_empty():
			var ins: Array = []
			var missing: bool = false
			for res in consumes:
				ins.append(_humanize_res(res))
				if not _player_produces(res, player):
					missing = true
			var needs_lbl := Label.new()
			needs_lbl.text = "Needs: %s" % ", ".join(ins)
			needs_lbl.add_theme_font_size_override("font_size", 9)
			needs_lbl.add_theme_color_override("font_color",
				Color(0.93, 0.47, 0.37) if missing else Color(0.86, 0.73, 0.42))
			needs_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			needs_lbl.custom_minimum_size = Vector2(108, 0)
			vb.add_child(needs_lbl)

		var bi: String = btype
		var build_btn := _make_card_button("Build", enabled)
		var reason: String = ""
		if not tech_ok:
			reason = "\nRequires: %s" % _humanize_tech_list(req_tech)
		elif not can_afford:
			reason = "\n(Cannot afford)"
		build_btn.tooltip_text = "Place %s\n%s%s" % [name_str, cost_str, reason]
		build_btn.pressed.connect(func(): build_requested.emit(bi))
		vb.add_child(build_btn)

# A compact themed button for build cards, with a clear enabled/disabled look.
func _make_card_button(text: String, enabled: bool) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.disabled = not enabled
	btn.custom_minimum_size = Vector2(0, 22)
	btn.add_theme_font_size_override("font_size", 11)
	btn.add_theme_color_override("font_color", Color(0.1, 0.08, 0.05))
	btn.add_theme_color_override("font_disabled_color", Color(0.5, 0.47, 0.43))
	var n := StyleBoxFlat.new()
	n.bg_color = Color(0.80, 0.64, 0.26) if enabled else Color(0.20, 0.17, 0.13)
	n.set_corner_radius_all(4)
	n.set_content_margin_all(3)
	btn.add_theme_stylebox_override("normal", n)
	var h := n.duplicate(); h.bg_color = Color(0.92, 0.76, 0.34)
	btn.add_theme_stylebox_override("hover", h)
	var pr := n.duplicate(); pr.bg_color = Color(0.66, 0.52, 0.20)
	btn.add_theme_stylebox_override("pressed", pr)
	var d := n.duplicate(); d.bg_color = Color(0.18, 0.15, 0.12)
	btn.add_theme_stylebox_override("disabled", d)
	return btn

# Mark the active build-category tab so the player knows where they are.
func _highlight_category_tab(cat: int) -> void:
	for i in _build_category_btns:
		var btn: Button = _build_category_btns[i]
		var active: bool = (i == cat)
		var sty := StyleBoxFlat.new()
		sty.bg_color = Color(0.42, 0.32, 0.14, 0.98) if active else Color(0.18, 0.14, 0.09, 0.95)
		sty.set_corner_radius_all(5)
		sty.set_border_width_all(2 if active else 1)
		sty.border_color = Color(0.95, 0.78, 0.34, 1.0) if active else Color(0.55, 0.43, 0.20, 0.9)
		sty.set_content_margin_all(4)
		btn.add_theme_stylebox_override("normal", sty)
		btn.add_theme_color_override("font_color",
			Color(1.0, 0.95, 0.7) if active else Color(0.85, 0.80, 0.66))

# Brief attention flash on a category tab (used when the menu auto-re-points on an
# objective advance). Brightens via modulate a few times, then settles back to normal.
func _pulse_category_tab(cat: int) -> void:
	if not _build_category_btns.has(cat):
		return
	var btn: Button = _build_category_btns[cat]
	if btn == null:
		return
	if _tab_pulse_tween != null and _tab_pulse_tween.is_valid():
		_tab_pulse_tween.kill()
	btn.modulate = Color(1, 1, 1, 1)
	_tab_pulse_tween = create_tween().set_loops(3)
	_tab_pulse_tween.tween_property(btn, "modulate", Color(1.7, 1.45, 0.7, 1.0), 0.18)
	_tab_pulse_tween.tween_property(btn, "modulate", Color(1, 1, 1, 1), 0.18)

func _refresh_build_menu() -> void:
	_show_build_category(_current_build_category)

const _COST_ABBR := {
	"gold": "g", "wood": "wd", "stone": "st", "iron": "ir", "food": "fd", "ale": "ale"}

func _format_cost(cost: Dictionary) -> String:
	if cost.is_empty():
		return "Free"
	var parts: Array = []
	for k in cost:
		# A space between value and unit so costs read as "20 wd  10 g", not "20wd10g".
		parts.append("%d %s" % [int(cost[k]), _COST_ABBR.get(k, str(k).left(2))])
	return "  ".join(parts)

# Convert a tech id to its readable display name. Prefers the canonical name from the
# tech registry (e.g. "advanced_masonry" → "Advanced Masonry"); falls back to a generic
# snake_case → Title Case conversion for anything not in the registry.
func _humanize_tech(tech_id: String) -> String:
	var defn: Dictionary = TechTree.lookup(tech_id)
	var nm: String = String(defn.get("name", ""))
	if nm != "":
		return nm
	return _titleize(tech_id)

# Generic snake_case → Title Case (e.g. "transport_logistics" → "Transport Logistics").
func _titleize(raw: String) -> String:
	var words: PackedStringArray = raw.replace("_", " ").split(" ", false)
	var out: Array = []
	for w in words:
		out.append(w.capitalize())
	return " ".join(out)

# Join a list of tech ids into a readable "Advanced Masonry, Crop Tiers" string.
func _humanize_tech_list(req_tech: Array) -> String:
	var names: Array = []
	for t in req_tech:
		names.append(_humanize_tech(String(t)))
	return ", ".join(names)

# Humanize a {ok,reason} lock string that may embed a raw tech id, e.g.
# "Requires tech: advanced_masonry" → "Requires Advanced Masonry".
func _humanize_reason(reason: String) -> String:
	var prefix: String = "Requires tech: "
	if reason.begins_with(prefix):
		return "Requires " + _humanize_tech(reason.substr(prefix.length()).strip_edges())
	return reason

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

	_macro_btn = _add_button(_bottom_bar, "⊞ Macro [Tab]", Vector2(x + 10, 4), Vector2(110, 26),
		func(): macro_view_toggled.emit(), "Toggle world map view (Tab) — march armies, claim villages")
	_add_button(_bottom_bar, "🔬 Tech", Vector2(x + 130, 4), Vector2(70, 26),
		func(): _toggle_tech_panel(), "Open technology tree")
	_add_button(_bottom_bar, "📜 Edicts", Vector2(x + 208, 4), Vector2(80, 26),
		func(): _toggle_edict_panel(), "Open royal edicts panel")
	_add_button(_bottom_bar, "💾 Save", Vector2(x + 296, 4), Vector2(70, 26),
		func(): save_requested.emit(), "Save game")

# ── Selection panel ────────────────────────────────────────────────────────────

func _build_selection_panel() -> void:
	_sel_full_size = _selection_panel.size   # remember full height so we can restore it
	_sel_header = _add_label(_selection_panel, "SELECTED", Vector2(6, 4), 11, Color.LIGHT_YELLOW)
	_sel_title = _add_label(_selection_panel, "Nothing selected", Vector2(6, 20), 14, Color(0.97, 0.92, 0.78))
	_sel_info  = _add_label(_selection_panel, "", Vector2(6, 42), 10, Color.LIGHT_GRAY)
	_sel_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_sel_info.size = Vector2(_selection_panel.size.x - 12, 60)
	_sel_workers_label = _add_label(_selection_panel, "", Vector2(6, 106), 10)

	_sel_actions = HBoxContainer.new()
	_sel_actions.position = Vector2(6, 110)
	_sel_actions.size = Vector2(_selection_panel.size.x - 12, 48)
	_sel_actions.add_theme_constant_override("separation", 3)
	_selection_panel.add_child(_sel_actions)

	clear_selection()   # start collapsed to a slim hint bar — nothing is selected yet

# Restore the full selection panel when something is picked.
func _expand_selection_panel() -> void:
	if _sel_full_size != Vector2.ZERO:
		_selection_panel.size = _sel_full_size
	# Restore the title's selected styling (clear_selection shrinks it for the hint bar).
	_sel_title.add_theme_font_size_override("font_size", 14)
	_sel_title.add_theme_color_override("font_color", Color(0.97, 0.92, 0.78))
	if _sel_header:
		_sel_header.text = "SELECTED"
	_sel_info.remove_theme_color_override("font_color")   # drop the realm-summary tint
	_sel_info.visible = true
	_sel_workers_label.visible = true
	_sel_actions.visible = true
	_sel_has_selection = true

func show_selected_building(building: Dictionary) -> void:
	if not _sel_title:
		return
	_expand_selection_panel()
	const BR = preload("res://simulation/buildings/BuildingRegistry.gd")
	const UR = preload("res://simulation/units/UnitRegistry.gd")
	var btype: String = building.get("type", "")
	var defn: Dictionary = BR.lookup(btype)
	_sel_title.text = defn.get("name", btype)
	var hp: int = building.get("hp", 0)
	var max_hp: int = defn.get("hp", 100)
	var workers: int = building.get("workers", 0)
	var max_w: int = defn.get("max_workers", 0)
	# For producer buildings, the player most wants to know what it makes/needs and whether it's
	# actually working — more useful than flavour text — so show that in place of the description. (iter351)
	var _p0: Dictionary = GameState.players[0] if GameState.players.size() > 0 else {}
	var prod_sum: String = _building_production_summary(building, defn, _p0)
	var sel_body: String = prod_sum if prod_sum != "" else _clean_desc(String(defn.get("description", "")))
	_sel_info.text = "HP: %d/%d  |  Fire: %s\n%s" % [
		hp, max_hp,
		"YES" if building.get("is_on_fire", false) else "No",
		sel_body
	]
	_sel_workers_label.text = "Workers: %d/%d" % [workers, max_w]
	for c in _sel_actions.get_children(): c.queue_free()

	# Worker buttons (when building has worker slots)
	if max_w > 0:
		var wlbl := Label.new(); wlbl.text = "W:"; wlbl.add_theme_font_size_override("font_size", 10)
		_sel_actions.add_child(wlbl)
		for i in range(0, max_w + 1):
			var wc: int = i
			var wb: Button = _make_card_button(str(i), true)
			wb.add_theme_font_size_override("font_size", 10)
			wb.custom_minimum_size = Vector2(26, 24)
			if i == workers:
				wb.add_theme_color_override("font_color", Color(0.30, 0.16, 0.05))  # current — darker, reads 'set'
			wb.pressed.connect(func(): _set_workers_on_building(building.get("id", -1), wc))
			_sel_actions.add_child(wb)

	# Recruit buttons (for buildings that train units)
	var recruitable: Array = UR.get_units_for_building(btype)
	if not recruitable.is_empty() and GameState.players.size() > 0:
		var player: Dictionary = GameState.players[0]
		for utype in recruitable:
			var udefn: Dictionary = UR.lookup(utype)
			var check: Dictionary = UR.can_recruit(utype, player)
			var rb: Button = _make_card_button("Recruit %s" % udefn.get("name", utype), check.get("ok", false))
			rb.add_theme_font_size_override("font_size", 9)
			rb.custom_minimum_size = Vector2(96, 24)
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

	# Demolish — tear down your OWN building (also bound to the Delete key). The seat itself
	# (village hall / keep) can't be razed by hand; losing it is a defeat, not a build choice.
	if btype != "village_hall" and btype != "keep":
		var dbtn: Button = _make_card_button("Demolish", true)
		dbtn.add_theme_font_size_override("font_size", 10)
		dbtn.custom_minimum_size = Vector2(80, 24)
		dbtn.add_theme_color_override("font_color", Color(1.0, 0.55, 0.45))
		dbtn.tooltip_text = "Tear this building down (or press Delete)."
		var did: int = int(building.get("id", -1))
		dbtn.pressed.connect(func():
			CommandQueue.enqueue(CommandQueue.CommandType.DEMOLISH_BUILDING, {"building_id": did}, 0)
			clear_selection())
		_sel_actions.add_child(dbtn)

func show_selected_unit(unit: Dictionary) -> void:
	if not _sel_title:
		return
	_expand_selection_panel()
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

	# Stance toggle for the player's own combat units: Guard (hold post, leashed) ⇄
	# Aggressive (pursue any foe freely). Routes through the command pipeline.
	if int(unit.get("owner_id", -1)) == 0 and int(defn.get("attack", 0)) > 0:
		var uid: int = int(unit.get("id", -1))
		var cur: String = String(unit.get("stance", "guard"))
		var sb: Button = _make_card_button("Stance: %s" % ("Aggressive" if cur == "aggressive" else "Guard"), true)
		sb.custom_minimum_size = Vector2(130, 24)
		sb.tooltip_text = "Guard: hold your post and return after a fight.\nAggressive: chase any foe freely.\nClick to toggle."
		var next_stance: String = "guard" if cur == "aggressive" else "aggressive"
		sb.pressed.connect(func(): CommandQueue.enqueue(32, {"unit_id": uid, "stance": next_stance}, 0))
		_sel_actions.add_child(sb)

# A villager's life at a glance — their name and family, sex/life-stage, what they do, and the
# three things that keep them alive (HP, food, warmth). Coloured red as each need runs low.
func show_selected_citizen(c: Dictionary) -> void:
	if not _sel_title:
		return
	_expand_selection_panel()
	const Needs = preload("res://simulation/world/NeedsSystem.gd")
	_sel_title.text = Needs.full_name(c)
	var hp: int     = int(round(float(c.get("hp", 100.0))))
	var food: int   = int(round(float(c.get("food", 100.0))))
	var warmth: int = int(round(float(c.get("warmth", 100.0))))
	var role_s: String = String(c.get("job_type", ""))
	if role_s == "":
		role_s = String(c.get("role", "peasant"))
	_sel_info.text = "HP %d/100\nFood %d/100   Warmth %d/100\n%s" % [
		hp, food, warmth, role_s.capitalize()]
	var sex_s: String   = "Woman" if String(c.get("sex", "m")) == "f" else "Man"
	var stage_s: String = String(c.get("stage", "adult")).capitalize()
	_sel_workers_label.text = "[%s · %s]" % [sex_s, stage_s]
	var low: bool = food < int(Needs.LOW) or warmth < int(Needs.LOW) or hp < 50
	_sel_workers_label.add_theme_color_override("font_color",
		Color(1.0, 0.5, 0.4) if low else Color(0.8, 0.85, 0.95))
	for ch in _sel_actions.get_children():
		ch.queue_free()

func clear_selection() -> void:
	if not _sel_title: return
	# Nothing selected → instead of a dead "click to inspect" bar, show a REALM-AT-A-GLANCE summary:
	# your feudal title + progress toward the next rank (the win condition, otherwise invisible during
	# city play), and whether a siege looms. Keeps the core goal in view between rank-ups. (iter331)
	_sel_workers_label.text = ""
	_sel_workers_label.visible = false
	_sel_workers_label.remove_theme_color_override("font_color")
	_sel_has_selection = false
	_realm_refresh_accum = 0.0
	_render_realm_summary()

# The idle realm summary (shown when nothing is selected). Refreshed ~every 1.5s by _process so the
# title/progress/threat stay current as the realm grows. Reads live state; mutates nothing.
func _render_realm_summary() -> void:
	if _sel_title == null:
		return
	var FR = preload("res://simulation/strategic/FeudalRank.gd")
	var CM = preload("res://simulation/strategic/CampaignMap.gd")
	var world: Dictionary = GameState.world
	var players: Array = GameState.players
	var idx: int = FR.current_index(world, players)
	if _sel_header:
		_sel_header.text = "YOUR REALM"
	_sel_title.text = "⚜  You rule as %s" % FR.title_name(idx)
	_sel_title.add_theme_font_size_override("font_size", 14)
	_sel_title.add_theme_color_override("font_color", Color(1.0, 0.86, 0.42))
	_sel_title.autowrap_mode = TextServer.AUTOWRAP_OFF
	_sel_title.size = Vector2(_sel_full_size.x - 12, 22)
	# Progress toward the next rank — a little block-bar between the two titles.
	var prog_line: String
	if idx >= FR.king_index():
		prog_line = "✦ The crown is yours — long may you reign. ✦"
	else:
		var prestige: float = float(players[0].get("prestige", 0.0)) if players.size() > 0 else 0.0
		var score: int = FR.domain_score(world, CM.player_faction_id(world), prestige)
		var cur_min: int = int(FR.TITLES[idx]["min_score"])
		var next_min: int = int(FR.TITLES[idx + 1]["min_score"])
		var frac: float = clampf(float(score - cur_min) / float(maxi(1, next_min - cur_min)), 0.0, 1.0)
		var filled: int = int(round(frac * 6.0))
		var bar: String = ""
		for i in range(6):
			bar += "▰" if i < filled else "▱"
		prog_line = "%s  %s  %s" % [FR.title_name(idx), bar, FR.title_name(idx + 1)]
	# Threat — is anyone marshalling a siege on the seat?
	var threat_line: String = "⚜  Your realm is at peace."
	var under_threat: bool = false
	for fac in GameState.ai_factions:
		if fac is Dictionary and int(fac.get("siege_assembly", {}).get("target_player_id", -1)) == 0:
			threat_line = "⚔  %s is marshalling a siege on your seat!" % GameState.get_faction_display_name(int(fac.get("id", -1)))
			under_threat = true
			break
	_sel_info.text = "%s\n%s\n\nClick a building, unit or citizen to inspect it." % [prog_line, threat_line]
	_sel_info.visible = true
	_sel_info.add_theme_font_size_override("font_size", 11)
	_sel_info.add_theme_color_override("font_color", Color(1.0, 0.62, 0.46) if under_threat else Color(0.83, 0.86, 0.78))
	_sel_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_sel_info.position = Vector2(6, 40)
	_sel_info.size = Vector2(_sel_full_size.x - 12, 96)
	for c in _sel_actions.get_children():
		c.queue_free()
	_sel_actions.visible = false
	_selection_panel.size = Vector2(_sel_full_size.x, 120)

func _process(delta: float) -> void:
	_realm_refresh_accum += delta
	if _realm_refresh_accum >= 1.5:
		_realm_refresh_accum = 0.0
		# The objective-panel crown footer is ALWAYS visible, so refresh it even while something is
		# selected; the idle realm summary only when nothing owns the selection panel.
		_refresh_goal_footer()
		if not _sel_has_selection:
			_render_realm_summary()

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
		# "Buy WD ↑" — explicit action + price-trend glyph (↑ pricey / ↓ cheap / → normal),
		# so it's not a cryptic "→ WO" the player can't tell from the Sell button.
		var buy_btn := _make_card_button("Buy %s %s" % [r.left(2).to_upper(), trend], true)
		buy_btn.add_theme_font_size_override("font_size", 9)
		buy_btn.custom_minimum_size = Vector2(64, 22)
		var hist_tip: String = HUDController.get_market_history_tooltip(r, world)
		buy_btn.tooltip_text = "Buy 10 %s · Cost: %s each\n%s\n%s" % [r, mp["buy"], trend_note, hist_tip]
		buy_btn.pressed.connect(func(): trade_buy_requested.emit(r, 10))
		_sel_actions.add_child(buy_btn)
		var sell_btn := _make_card_button("Sell %s" % r.left(2).to_upper(), true)
		sell_btn.add_theme_font_size_override("font_size", 9)
		sell_btn.custom_minimum_size = Vector2(52, 22)
		sell_btn.tooltip_text = "Sell 10 %s · Receive: %s each\n%s\n%s" % [r, mp["sell"], trend_note, hist_tip]
		sell_btn.pressed.connect(func(): trade_sell_requested.emit(r, 10))
		_sel_actions.add_child(sell_btn)

# ── Tech Tree Panel ────────────────────────────────────────────────────────────

func _build_tech_panel() -> void:
	_add_label(_tech_panel, "TECHNOLOGY", Vector2(8, 6), 14, Color.LIGHT_YELLOW)
	_add_button(_tech_panel, "✕", Vector2(_tech_panel.size.x - 30, 4), Vector2(26, 24),
		func(): _tech_panel.visible = false; _set_side_panels_hidden(false))
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
	# A tech is a small two-line card: the name+cost+Research row, then an always-visible one-line
	# summary of what it gets you (unlocks/effect) — so the tree reads as choices, not bare names.
	var card := VBoxContainer.new()
	card.add_theme_constant_override("separation", 0)
	parent.add_child(card)

	var row := HBoxContainer.new()
	row.custom_minimum_size = Vector2(0, 24)
	card.add_child(row)

	var status: String = item.get("status", "locked")
	var status_sym: String = {"researched": "✓", "available": "◆", "unaffordable": "◇", "locked": "·"}.get(status, "?")
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
		var btn := _make_card_button("Research", true)
		btn.add_theme_font_size_override("font_size", 10)
		btn.custom_minimum_size = Vector2(82, 24)
		var hint: String = TechTreePanelController.get_tech_hint_text(item)
		btn.tooltip_text = "Research %s for %d prestige\n%s" % [item.get("name", ""), int(item.get("cost_prestige", 0)), hint]
		btn.pressed.connect(func(): tech_research_requested.emit(tech_id))
		row.add_child(btn)

	var summary: String = TechTreePanelController.get_tech_summary(item)
	if summary != "":
		var sub := Label.new()
		sub.text = "    " + summary
		sub.add_theme_font_size_override("font_size", 9)
		sub.add_theme_color_override("font_color",
			Color(0.66, 0.72, 0.54) if status != "locked" else Color(0.50, 0.48, 0.44))
		sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		card.add_child(sub)

func _toggle_tech_panel() -> void:
	_edict_panel.visible = false
	if _tech_panel.visible:
		_animate_panel_close(_tech_panel)
		_set_side_panels_hidden(false)
	else:
		# Open (visible=true) BEFORE refresh — _refresh_tech_panel bails while hidden,
		# so refreshing first left the tech tree permanently blank (same as edicts).
		_animate_panel_open(_tech_panel)
		_refresh_tech_panel()
		_set_side_panels_hidden(true)

# The Tech/Edict panels share the right edge with the popularity + objective panels — hide
# those while a big panel is open (restore on close) so they don't overlap into clutter.
func _set_side_panels_hidden(hidden: bool) -> void:
	if _right_panel != null:
		_right_panel.visible = not hidden
	if _objective_panel != null:
		_objective_panel.visible = not hidden

# ── Edict Panel ────────────────────────────────────────────────────────────────

func _build_edict_panel() -> void:
	_add_label(_edict_panel, "ROYAL EDICTS", Vector2(8, 6), 14, Color.LIGHT_YELLOW)
	_add_button(_edict_panel, "✕", Vector2(_edict_panel.size.x - 30, 4), Vector2(26, 24),
		func(): _edict_panel.visible = false; _set_side_panels_hidden(false))
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

	# Always show the points line — so an empty panel reads as "save up / unlock" not "broken".
	var pts := Label.new()
	pts.text = "Edict Points: %d   (royal decrees cost points; earned over time once unlocked)" % int(panel_data.get("edict_points", 0))
	pts.add_theme_font_size_override("font_size", 10)
	pts.add_theme_color_override("font_color", Color(0.7, 0.8, 0.95))
	pts.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(pts)

	_add_edict_section(vbox, "Active Edicts", panel_data.get("active", []), "active")
	_add_edict_section(vbox, "Available Edicts", panel_data.get("available", []), "available")
	# Show LOCKED edicts too (greyed, with the reason) — otherwise a new player who hasn't
	# unlocked anything opens an empty panel and has no idea edicts exist or how to get them.
	_add_edict_section(vbox, "Locked Edicts", panel_data.get("locked", []), "locked")

func _add_edict_section(parent: VBoxContainer, title: String, items: Array, kind: String) -> void:
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
		if kind == "locked":
			lbl.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
		row.add_child(lbl)
		if kind == "active":
			var rem_lbl := Label.new()
			rem_lbl.text = item.get("remaining_label", "")
			rem_lbl.add_theme_font_size_override("font_size", 10)
			rem_lbl.add_theme_color_override("font_color", Color.ORANGE)
			row.add_child(rem_lbl)
		elif kind == "locked":
			var why := Label.new()
			# Readable reason ("Requires Advanced Masonry"), wrapped instead of clipped mid-word.
			why.text = "(locked) " + _humanize_reason(String(item.get("reason", "Locked")))
			why.add_theme_font_size_override("font_size", 9)
			why.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			why.custom_minimum_size = Vector2(150, 0)
			why.add_theme_color_override("font_color", Color(0.85, 0.6, 0.4))
			row.add_child(why)
		else:
			var eid: String = item.get("id", "")
			var btn := _make_card_button("Activate (%dP)" % int(item.get("cost_points", 0)), true)
			btn.add_theme_font_size_override("font_size", 9)
			btn.custom_minimum_size = Vector2(96, 22)
			btn.tooltip_text = "Activate '%s'\nCosts %d edict points" % [item.get("name", ""), int(item.get("cost_points", 0))]
			btn.pressed.connect(func(): edict_activate_requested.emit(eid))
			row.add_child(btn)

func _toggle_edict_panel() -> void:
	_tech_panel.visible = false
	if _edict_panel.visible:
		_animate_panel_close(_edict_panel)
		_set_side_panels_hidden(false)
	else:
		# Open (sets visible=true) BEFORE refreshing — _refresh_edict_panel bails out
		# while the panel is hidden, so refreshing first left the panel permanently blank.
		_animate_panel_open(_edict_panel)
		_refresh_edict_panel()
		_set_side_panels_hidden(true)

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

# Strip internal "GDD §x" design citations that leak out of building description text, so the
# player never sees raw dev notes. Used by both the build card and the selection panel.
func _clean_desc(desc: String) -> String:
	var gi: int = desc.find("GDD")
	if gi > 0:
		return desc.substr(0, gi).strip_edges()
	return desc.strip_edges()

# ── Production-chain readouts (iter351) — make the hidden gather→process→deliver chain legible,
# so a Bakery built with no Mill to feed it reads as "needs flour", not as a broken economy. ──
func _humanize_res(key: String) -> String:
	return key.capitalize()   # "leather_armor" -> "Leather Armor"

# Friendly name of the FIRST building that produces `res` (wheat -> "Wheat Farm", flour -> "Mill").
func _resource_producer_name(res: String) -> String:
	for t in BuildingRegistry.BUILDINGS:
		if BuildingRegistry.BUILDINGS[t].get("produces", {}).has(res):
			return BuildingRegistry.BUILDINGS[t].get("name", t)
	return ""

# Does the player have at least one BUILT building producing `res`?
func _player_produces(res: String, player: Dictionary) -> bool:
	for b in player.get("buildings", []):
		if b is Dictionary and b.get("built", false) \
				and BuildingRegistry.lookup(b.get("type", "")).get("produces", {}).has(res):
			return true
	return false

# Two-line "Makes: X · Needs: Y \n <live status>" for a producer building, or "" for non-producers.
func _building_production_summary(building: Dictionary, defn: Dictionary, player: Dictionary) -> String:
	var outs: Array = []
	for r in defn.get("produces", {}):
		if r != "population_cap":
			outs.append(_humanize_res(r))
	var ins: Array = []
	for r in defn.get("consumes", {}):
		ins.append(_humanize_res(r))
	if outs.is_empty() and ins.is_empty():
		return ""
	var head_parts: Array = []
	if not outs.is_empty(): head_parts.append("Makes: %s" % ", ".join(outs))
	if not ins.is_empty():  head_parts.append("Needs: %s" % ", ".join(ins))
	var status: String = "⚒ Working"
	var max_w: int = int(defn.get("max_workers", 0))
	if max_w > 0 and int(building.get("workers", 0)) == 0:
		status = "⏸ Idle — assign a worker"
	else:
		for r in defn.get("consumes", {}):
			if not _player_produces(r, player):
				var src: String = _resource_producer_name(r)
				status = ("⏸ Idle — no %s yet (build a %s)" % [_humanize_res(r), src]) if src != "" \
					else ("⏸ Idle — no %s" % _humanize_res(r))
				break
	return "%s\n%s" % ["  ·  ".join(head_parts), status]

func set_build_mode_display(building_type: String) -> void:
	var in_build: bool = building_type != ""
	var nice: String = BuildingRegistry.lookup(building_type).get("name", building_type) if in_build else ""
	if _build_mode_label:
		_build_mode_label.text = "Placing: %s" % nice if in_build else ""
	# The single worst onboarding stall was a new player pressing Build, seeing a tiny "Mode: village_hall"
	# corner label, and not knowing the next step is to CLICK THE GROUND. Show a prominent centre-bottom
	# prompt that names the building and spells out the action. (iter350)
	if _build_mode_banner == null:
		var vp: Vector2 = get_viewport().get_visible_rect().size
		_build_mode_banner = Panel.new()
		_build_mode_banner.size = Vector2(560, 38)
		# Sit just ABOVE the build menu (its top is vp.y - 200) so the prompt never overlaps the cards.
		_build_mode_banner.position = Vector2((vp.x - 560.0) * 0.5, vp.y - 250.0)
		var st := StyleBoxFlat.new()
		st.bg_color = Color(0.10, 0.08, 0.05, 0.92)
		st.set_corner_radius_all(8)
		st.set_border_width_all(2)
		st.border_color = Color(0.95, 0.80, 0.34, 0.95)
		st.shadow_color = Color(0, 0, 0, 0.5); st.shadow_size = 8
		_build_mode_banner.add_theme_stylebox_override("panel", st)
		_build_mode_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_build_mode_banner)
		_build_mode_banner_label = Label.new()
		_build_mode_banner_label.size = Vector2(560, 38)
		_build_mode_banner_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_build_mode_banner_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_build_mode_banner_label.add_theme_font_size_override("font_size", 15)
		_build_mode_banner_label.add_theme_color_override("font_color", Color(1.0, 0.92, 0.66))
		_build_mode_banner.add_child(_build_mode_banner_label)
	_build_mode_banner.visible = in_build
	if in_build:
		_build_mode_banner_label.text = "Placing %s  —  left-click open ground to build  ·  right-click / Esc to cancel" % nice
