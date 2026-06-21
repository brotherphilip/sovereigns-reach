extends Node
# Strategic world map scene. Generates WorldMapData (or reads cached),
# builds WorldMapView, handles city-click to enter CityViewScene.

const WorldMapData = preload("res://simulation/world/WorldMapData.gd")
const _CampaignMap = preload("res://simulation/strategic/CampaignMap.gd")

var _world_view: Control = null

var _loading_canvas: CanvasLayer = null
var _event_feed: Panel = null            # strategic realm_notice feed (iter270)
var _endgame_shown: bool = false         # the win/defeat screen fires at most once (iter271/272)

# "Watch the campaign" live strategic ticker.
var _watching: bool = false
var _watch_accum: float = 0.0
var _last_seen_day: int = -1            # last strategic day the view synced to
var _watch_btn: Button = null
var _watch_speed_btn: Button = null
var _day_label: Label = null
var _develop_btn: Button = null
var _realm_label: Label = null
var _march_status_label: Label = null
var _raise_btn: Button = null
var _march_btn: Button = null
var _diplo_btn: Button = null
var _action_city_id: int = -1     # right-click-selected city for strategic orders
var _diplo_faction_id: int = -1   # owner kingdom of a selected rival city (diplomacy target)
var _march_arming: bool = false   # true = awaiting a target for the real-troop host march
var _march_source_city: int = -1  # the owned city the marching host departs from
const WATCH_INTERVAL: float = 0.45      # real seconds per strategic day at speed 1

func _ready() -> void:
	_show_loading()
	# Defer actual build one frame so the loading screen renders first
	call_deferred("_init_and_build")

func _show_loading() -> void:
	_loading_canvas = CanvasLayer.new()
	_loading_canvas.layer = 100
	add_child(_loading_canvas)
	var bg := ColorRect.new()
	bg.color = Color(0.08, 0.10, 0.07, 1.0)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_loading_canvas.add_child(bg)
	var lbl := Label.new()
	lbl.text = "Generating world map…"
	lbl.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	lbl.add_theme_font_size_override("font_size", 20)
	lbl.add_theme_color_override("font_color", Color(0.91, 0.76, 0.26))
	_loading_canvas.add_child(lbl)

func _init_and_build() -> void:
	# Generate or reuse world map data
	if not GameState.world.has("world_map") or GameState.world["world_map"].is_empty():
		var seed_val: int = GameState.server_config.get("map_seed", 42)
		GameState.world["world_map"] = WorldMapData.generate(seed_val)

	# Promote the static map into a living strategic state (idempotent) so the
	# campaign sim has owners, garrisons and kingdoms to work with.
	GameState.ensure_strategic_initialized()

	# Start the player on their ONE village: default-select it so the first city entry
	# (and the "Return to…" button) land on the holding they actually own.
	if int(GameState.world.get("selected_city_id", -1)) < 0:
		for c in GameState.world.get("world_map", {}).get("cities", []):
			if c is Dictionary and c.get("is_player_start", false):
				GameState.world["selected_city_id"] = c.get("id", -1)
				break

	# Dev/headless hook: drive a competent climb for SR_CLIMB game-days BEFORE building the
	# scene, so a screenshot shows a climbed realm (higher title + several gold holdings).
	# Dev-only; uses the same public player command surface the real game uses.
	if OS.get_environment("SR_CLIMB") != "":
		_dev_autoclimb(int(OS.get_environment("SR_CLIMB")))

	_build_scene()
	# Single shared clock: keep it RUNNING on the map so the seat economy + the strategic
	# layer keep advancing in the background (no more freezing the world when you leave town).
	if not SimulationClock.is_paused():
		SimulationClock.set_speed(SimulationClock.SPEED_NORMAL)

	# Dev/headless hook: jump straight into spectating a developed rival city.
	# (Returns early — that flow changes scene itself.)
	if OS.get_environment("SR_SPECTATE") != "":
		_dev_jump_to_spectator()
		return

	# Reveal the map: drop the loading overlay now that the scene is built.
	if _loading_canvas:
		_loading_canvas.queue_free()
		_loading_canvas = null

	_refresh_watch_btn()

	# Dev/headless hook: preview the world-map end-game screens (the win/defeat this scene must now
	# present, since both the climb to King and the loss of the last holding happen here). Use
	# SR_WINTEST=defeat for the DEFEAT panel, anything else for the King VICTORY panel.
	if OS.get_environment("SR_WINTEST") != "":
		match OS.get_environment("SR_WINTEST"):
			"defeat":   _show_endgame(false, "Your last holding has fallen. Your domain is no more.")
			"revolt":   _on_popularity_changed(0, 50.0, 5.0)
			"siege":    _on_ai_siege_assembling(90, 0, 48 * 240)
			"envoy":    _on_envoy_sent_map(90, {"player_id": 0, "faction_id": 90,
							"demands": {"gold": 80, "iron": 15},
							"deadline_tick": SimulationClock.current_tick + 240 * 7})
			"conquest": _show_endgame(true, "All enemies vanquished! Sovereign's Reach is yours!")
			_:          _on_title_promoted(6, "King")

	# Dev/headless hook: fast-forward the shared clock (used for screenshots).
	if OS.get_environment("SR_AUTOWATCH") != "":
		SimulationClock.set_speed(SimulationClock.SPEED_FASTEST)
		_refresh_watch_btn()

	# Dev hook: render for SR_SHOT_DELAY seconds, save a PNG to SR_SHOT, then quit.
	if OS.get_environment("SR_SHOT") != "":
		_dev_screenshot(OS.get_environment("SR_SHOT"))

func _dev_screenshot(path: String) -> void:
	var delay: float = 6.0
	if OS.get_environment("SR_SHOT_DELAY") != "":
		delay = float(OS.get_environment("SR_SHOT_DELAY"))
	await get_tree().create_timer(delay).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
	print("[WorldMap] screenshot saved: %s" % path)
	get_tree().quit()

# Dev-only: advance the strategic layer `days` days while playing a competent climb
# (develop-first + capped expansion) through GameState's public player commands — mirrors
# tests/TestKingClimb.gd so the on-screen render matches the verified headless climb.
func _dev_autoclimb(days: int) -> void:
	var CampaignSystem = preload("res://simulation/strategic/CampaignSystem.gd")
	var pfid: int = _CampaignMap.player_faction_id(GameState.world)
	var ids: Array = _CampaignMap.faction_city_ids(GameState.world, pfid)
	if ids.is_empty():
		return
	var home: int = ids[0]
	GameState.world["player_seat_city_id"] = home
	var k: Dictionary = _CampaignMap.kingdom_by_id(GameState.world, pfid)
	for _d in range(days):
		GameState.advance_strategic_day()
		var low: int = GameState.player_lowest_dev_city()
		if low >= 0 and GameState.can_player_develop_city(low) and int(k.get("treasury", 0)) > 250:
			GameState.player_develop_city(low)
		if CampaignSystem.total_army_size(k) == 0 and _CampaignMap.faction_city_ids(GameState.world, pfid).size() < 16:
			var best: int = -1
			var bd: int = 1 << 30
			for t in _CampaignMap.frontier_targets(GameState.world, pfid):
				var tc: Dictionary = _CampaignMap.city_by_id(GameState.world, t)
				if _CampaignMap.owner_of(tc) == pfid:
					continue
				var dd: int = _CampaignMap.city_defense(tc)
				if dd < bd:
					bd = dd; best = t
			if best >= 0:
				var host: int = mini(maxi(40, int(ceil(float(bd) * 1.7))), int(k.get("treasury", 0)) / 5)
				if host >= int(ceil(float(bd) * 1.1)):
					while CampaignSystem.total_army_size(k) < host and int(k.get("treasury", 0)) >= 200:
						GameState.player_raise_army(home, mini(40, host - CampaignSystem.total_army_size(k)))
					var aid: int = GameState.player_army_at_city(home)
					if aid >= 0:
						GameState.player_launch_campaign(aid, best)
	# Re-center selection on the (still-owned) seat so the HUD reads the climbed realm.
	GameState.world["selected_city_id"] = home

func _dev_jump_to_spectator() -> void:
	var cs: Array = GameState.world.get("world_map", {}).get("cities", [])
	if cs.size() < 3:
		return
	GameState.world["player_seat_city_id"] = cs[0].get("id", 0)
	var target_id: int = cs[2].get("id", 2)
	GameState.world["selected_city_id"] = target_id
	for c in cs:
		if c.get("id", -1) == target_id:
			c["development"] = 8  # show a sizeable, walled town
			break
	get_tree().change_scene_to_file("res://view/cityview/CityViewScene.tscn")

# The single autoload clock now drives time everywhere (its simulate_tick advances both the
# strategic layer and the live seat). The map just keeps its view in sync with that clock —
# refresh on each day boundary, and slide marching armies smoothly within a day.
func _process(_delta: float) -> void:
	if _world_view == null:
		return
	var day: int = GameState.strategic_day()
	if day != _last_seen_day:
		_last_seen_day = day
		_world_view.set_current_day(day)  # fade battle markers
		_world_view.refresh()
		_refresh_develop_btn()
		_refresh_raise_btn()
		_refresh_march_btn()
		_refresh_realm_label()
		_refresh_march_status()
		if _day_label != null:
			_day_label.text = "Campaign day %d" % day
	# Sub-day march progress from the live clock, so the campaign visibly creeps across the map.
	var frac: float = float(SimulationClock.ticks_into_current_day()) / float(SimulationClock.TICKS_PER_GAME_DAY)
	_world_view.set_army_frac(clampf(frac, 0.0, 1.0))

func _build_scene() -> void:
	var data: Dictionary = GameState.world["world_map"]

	# Full-rect world map view
	_world_view = preload("res://view/worldmap/WorldMapView.gd").new()
	_world_view.name = "WorldMapView"
	_world_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_world_view.apply_data(data)
	add_child(_world_view)
	_world_view.city_clicked.connect(_on_city_clicked)

	# HUD canvas layer with buttons
	var canvas := CanvasLayer.new()
	canvas.name  = "HUD"
	canvas.layer = 10
	add_child(canvas)

	var vp: Vector2 = get_viewport().get_visible_rect().size
	if vp == Vector2.ZERO: vp = Vector2(1280, 720)

	# Top bar
	var top_bar := Panel.new()
	top_bar.position = Vector2(0, 0)
	top_bar.size     = Vector2(vp.x, 36)
	var sty := StyleBoxFlat.new()
	sty.bg_color = Color(0.08, 0.10, 0.07, 0.88)
	sty.border_width_bottom = 1
	sty.border_color = Color(0.55, 0.45, 0.20, 0.7)
	top_bar.add_theme_stylebox_override("panel", sty)
	canvas.add_child(top_bar)

	var title_lbl := Label.new()
	title_lbl.text     = "Sovereign's Reach — World Map"
	title_lbl.position = Vector2(10, 8)
	title_lbl.size     = Vector2(400, 22)
	title_lbl.add_theme_font_size_override("font_size", 14)
	title_lbl.add_theme_color_override("font_color", Color(0.91, 0.76, 0.26))
	top_bar.add_child(title_lbl)

	var hint_lbl := Label.new()
	hint_lbl.text     = "Click a city to enter it"
	hint_lbl.position = Vector2(vp.x * 0.5 - 100, 8)
	hint_lbl.size     = Vector2(200, 22)
	hint_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint_lbl.add_theme_font_size_override("font_size", 12)
	hint_lbl.add_theme_color_override("font_color", Color(0.72, 0.66, 0.48))
	top_bar.add_child(hint_lbl)

	var menu_btn := Button.new()
	menu_btn.text     = "Main Menu"
	menu_btn.position = Vector2(vp.x - 110, 4)
	menu_btn.size     = Vector2(100, 28)
	menu_btn.add_theme_font_size_override("font_size", 12)
	menu_btn.pressed.connect(_on_main_menu)
	top_bar.add_child(menu_btn)

	# "Watch the campaign" controls — run the strategic AI live on the map.
	_watch_btn = Button.new()
	_watch_btn.text     = "▶ Watch Campaign"
	_watch_btn.position = Vector2(vp.x - 270, 4)
	_watch_btn.size     = Vector2(150, 28)
	_watch_btn.add_theme_font_size_override("font_size", 12)
	_watch_btn.pressed.connect(_on_toggle_watch)
	top_bar.add_child(_watch_btn)

	_watch_speed_btn = Button.new()
	_watch_speed_btn.text     = "1×"
	_watch_speed_btn.position = Vector2(vp.x - 312, 4)
	_watch_speed_btn.size     = Vector2(36, 28)
	_watch_speed_btn.add_theme_font_size_override("font_size", 12)
	_watch_speed_btn.pressed.connect(_on_cycle_watch_speed)
	top_bar.add_child(_watch_speed_btn)

	# Player feudal title + holdings — the "work your way up" progress readout.
	var title_label := Label.new()
	title_label.name = "TitleLabel"
	title_label.text = "%s · %d %s" % [
		GameState.player_title_name(), GameState.player_holdings_count(),
		("village" if GameState.player_holdings_count() == 1 else "villages")]
	title_label.position = Vector2(248, 9)
	title_label.size     = Vector2(260, 22)
	title_label.add_theme_font_size_override("font_size", 14)
	title_label.add_theme_color_override("font_color", Color(0.97, 0.85, 0.42))
	top_bar.add_child(title_label)

	_day_label = Label.new()
	_day_label.text     = "Campaign day %d" % GameState.strategic_day()
	_day_label.position = Vector2(vp.x - 470, 8)
	_day_label.size     = Vector2(150, 22)
	_day_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_day_label.add_theme_font_size_override("font_size", 12)
	_day_label.add_theme_color_override("font_color", Color(0.80, 0.74, 0.54))
	top_bar.add_child(_day_label)

	var last_city_id: int = GameState.world.get("selected_city_id", -1)
	if last_city_id >= 0:
		var last_city: Dictionary = GameState.get_city(last_city_id)
		if not last_city.is_empty():
			var resume_btn := Button.new()
			resume_btn.text = "↩ Return to %s" % last_city.get("name", "City")
			resume_btn.position = Vector2(vp.x - 260, 4)
			resume_btn.size = Vector2(140, 28)
			resume_btn.add_theme_font_size_override("font_size", 11)
			resume_btn.pressed.connect(func(): _fade_to_scene("res://view/cityview/CityViewScene.tscn"))
			top_bar.add_child(resume_btn)

	# Info panel (bottom-left) — shows selected city info
	var info_panel := Panel.new()
	info_panel.name     = "InfoPanel"
	info_panel.position = Vector2(8, vp.y - 90)
	info_panel.size     = Vector2(280, 82)
	var isty := StyleBoxFlat.new()
	isty.bg_color = Color(0.08, 0.10, 0.07, 0.88)
	isty.set_border_width_all(1)
	isty.border_color = Color(0.55, 0.45, 0.20, 0.7)
	info_panel.add_theme_stylebox_override("panel", isty)
	canvas.add_child(info_panel)

	var info_lbl := Label.new()
	info_lbl.name     = "InfoLabel"
	info_lbl.text     = "Hover for details · Left-click to enter & rule · Right-click to select for orders"
	info_lbl.position = Vector2(8, 6)
	info_lbl.size     = Vector2(264, 70)
	info_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info_lbl.add_theme_font_size_override("font_size", 11)
	info_lbl.add_theme_color_override("font_color", Color(0.80, 0.74, 0.54))
	info_panel.add_child(info_lbl)

	# Controls legend — the right-click→act model isn't obvious (left-click enters), so
	# spell out the strategic orders for first-time players.
	var legend := Label.new()
	legend.name = "OrdersLegend"
	legend.text = "⚜ Realm orders: right-click your seat, then ⚔ March your trained host onto an enemy village · ⚒ Develop · 🕊 Diplomacy"
	legend.position = Vector2(8, vp.y - 176)
	legend.size = Vector2(900, 20)
	legend.add_theme_font_size_override("font_size", 12)
	legend.add_theme_color_override("font_color", Color(0.72, 0.66, 0.48))
	canvas.add_child(legend)

	# Realm stores readout — so the player can plan strategic investments (treasury +
	# the wood/stone that develop costs draw on, and how many cities they hold).
	_realm_label = Label.new()
	_realm_label.name     = "RealmStores"
	_realm_label.position = Vector2(8, vp.y - 152)
	_realm_label.size     = Vector2(360, 22)
	_realm_label.add_theme_font_size_override("font_size", 12)
	_realm_label.add_theme_color_override("font_color", Color(0.91, 0.82, 0.45))
	canvas.add_child(_realm_label)
	_refresh_realm_label()

	# Persistent "armies on the march" readout so you always know where your hosts are
	# headed and roughly when they'll arrive — even after closing a panel.
	_march_status_label = Label.new()
	_march_status_label.name     = "MarchStatus"
	_march_status_label.position = Vector2(8, vp.y - 174)
	_march_status_label.size     = Vector2(560, 22)
	_march_status_label.add_theme_font_size_override("font_size", 12)
	_march_status_label.add_theme_color_override("font_color", Color(1.0, 0.78, 0.42))
	canvas.add_child(_march_status_label)
	_refresh_march_status()

	# Player strategic action (the first interactive control — was watch/enter only):
	# invest the realm's treasury to grow your least-developed holding.
	_develop_btn = Button.new()
	_develop_btn.name     = "DevelopBtn"
	_develop_btn.position = Vector2(8, vp.y - 124)
	_develop_btn.size     = Vector2(280, 28)
	_develop_btn.add_theme_font_size_override("font_size", 12)
	_develop_btn.pressed.connect(_on_develop_realm)
	_style_action_button(_develop_btn)
	canvas.add_child(_develop_btn)
	_refresh_develop_btn()

	# Raise Army at the right-click-selected city — musters a field army there.
	_raise_btn = Button.new()
	_raise_btn.name     = "RaiseArmyBtn"
	_raise_btn.position = Vector2(296, vp.y - 124)
	_raise_btn.size     = Vector2(250, 28)
	_raise_btn.add_theme_font_size_override("font_size", 12)
	_raise_btn.pressed.connect(_on_raise_army)
	_style_action_button(_raise_btn)
	canvas.add_child(_raise_btn)
	_refresh_raise_btn()

	# Launch Campaign: send the selected city's army to march on an enemy target.
	_march_btn = Button.new()
	_march_btn.name     = "MarchBtn"
	_march_btn.position = Vector2(554, vp.y - 124)
	_march_btn.size     = Vector2(250, 28)
	_march_btn.add_theme_font_size_override("font_size", 12)
	_march_btn.pressed.connect(_on_march)
	_style_action_button(_march_btn)
	canvas.add_child(_march_btn)
	_refresh_march_btn()

	# Diplomacy: offer a truce to (or declare war on) the kingdom holding a selected city.
	_diplo_btn = Button.new()
	_diplo_btn.name     = "DiplomacyBtn"
	_diplo_btn.position = Vector2(812, vp.y - 124)
	_diplo_btn.size     = Vector2(280, 28)
	_diplo_btn.add_theme_font_size_override("font_size", 12)
	_diplo_btn.pressed.connect(_on_diplomacy)
	_style_action_button(_diplo_btn)
	canvas.add_child(_diplo_btn)
	_refresh_diplo_btn()

	# Connect hover → info panel (show the hovered city's details)
	_world_view.mouse_entered.connect(_on_mouse_entered_map)
	_world_view.city_hovered.connect(_on_city_hovered)
	_world_view.city_selected.connect(_on_city_selected)
	_world_view.army_inspected.connect(_on_army_inspected)

	# Strategic event feed: surface the same realm_notice toasts the CITY HUD shows — campaign
	# results ("⚔ Your host has taken X!", "X seized your city!"), plagues, low-stores warnings —
	# so they aren't LOST while the player is on the world map (where they actually launch the
	# campaigns whose outcomes these announce). Mirrors CityViewScene's realm_notice wiring;
	# left side, under the top bar. The connection dies with the scene on the way back to a city.
	_event_feed = preload("res://view/hud/NotificationFeed.gd").new()
	_event_feed.name = "WorldEventFeed"
	_event_feed.position = Vector2(8, 44)
	canvas.add_child(_event_feed)
	EventBus.realm_notice.connect(func(text: String, tone: String):
		var col: Color = Color(0.95, 0.85, 0.55)
		if tone == "bad": col = Color(0.92, 0.6, 0.5)
		elif tone == "good": col = Color(0.6, 0.9, 0.6)
		if is_instance_valid(_event_feed): _event_feed.push("📜 " + text, 7.0, col))
	# Title promotions (Reeve→…→King) fire from the strategic tick, which advances WHILE the player
	# is on this map — but the celebration + the King WIN screen were wired only in CityViewScene, so
	# climbing to King by capturing the final city on the MAP showed nothing. Handle it here too.
	EventBus.title_promoted.connect(_on_title_promoted)
	# Symmetric DEFEAT: losing your LAST holding also happens on the map (rivals capture your cities
	# during the strategic tick); that game-over was likewise city-view-only (iter272).
	EventBus.player_realm_lost.connect(func():
		_show_endgame(false, "Your last holding has fallen. Your domain is no more."))
	# The REMAINING win/loss conditions also fire from the seat + strategic sim that keep ticking on
	# this map, yet their game-over was city-view-only (iter273): vanquishing the LAST rival = a win;
	# the seat's hall razed (siege) or popularity < 10 (revolt) = defeat. Present them here too.
	EventBus.ai_faction_defeated.connect(_on_ai_faction_defeated)
	EventBus.popularity_changed.connect(_on_popularity_changed)
	EventBus.building_destroyed.connect(_on_building_destroyed)
	# A siege MARSHALLING against your seat is the key actionable telegraph — but its visual warning
	# was city-view-only, so a player off campaigning on the map only HEARD the VO with no on-screen
	# "raise walls, ~N days" advice. Surface it in the map feed too (iter274).
	EventBus.ai_siege_assembling.connect(_on_ai_siege_assembling)
	# A tribute ENVOY can arrive while the player is on the map, but the Accept/Refuse panel lives
	# only in the city HUD — so the demand was invisible here and silently expired unanswered (the
	# panel now re-presents it on return, iter276). Tell the player to GO BACK and answer it.
	EventBus.ai_envoy_sent.connect(_on_envoy_sent_map)

# Gold-bordered parchment styling for the bottom action buttons. The default theme
# rendered them near-transparent over the busy map terrain (Raise/March/Diplomacy
# labels floated illegibly); this gives each a solid dark backing + gold edge with
# clear hover/pressed/disabled states.
func _style_action_button(btn: Button) -> void:
	var mk := func(bg: Color, border: Color) -> StyleBoxFlat:
		var s := StyleBoxFlat.new()
		s.bg_color = bg
		s.border_color = border
		s.set_border_width_all(1)
		s.set_corner_radius_all(4)
		s.content_margin_left = 8.0
		s.content_margin_right = 8.0
		s.content_margin_top = 4.0
		s.content_margin_bottom = 4.0
		return s
	var gold := Color(0.62, 0.49, 0.22)
	var bright := Color(0.85, 0.69, 0.34)
	btn.add_theme_stylebox_override("normal",   mk.call(Color(0.13, 0.10, 0.06, 0.94), gold))
	btn.add_theme_stylebox_override("hover",    mk.call(Color(0.22, 0.17, 0.09, 0.97), bright))
	btn.add_theme_stylebox_override("pressed",  mk.call(Color(0.09, 0.07, 0.04, 0.97), bright))
	btn.add_theme_stylebox_override("disabled", mk.call(Color(0.10, 0.09, 0.08, 0.82), Color(0.34, 0.30, 0.24)))
	btn.add_theme_color_override("font_color",           Color(0.96, 0.90, 0.74))
	btn.add_theme_color_override("font_hover_color",      Color(1.0, 0.95, 0.80))
	btn.add_theme_color_override("font_pressed_color",    Color(0.90, 0.82, 0.62))
	btn.add_theme_color_override("font_disabled_color",   Color(0.58, 0.53, 0.47))

func _on_city_clicked(city_id: int) -> void:
	GameState.world["selected_city_id"] = city_id
	var city: Dictionary = GameState.get_city(city_id)
	if city.is_empty(): return

	# Show brief loading message
	var canvas: CanvasLayer = get_node_or_null("HUD")
	if canvas:
		var info: Label = canvas.get_node_or_null("InfoPanel/InfoLabel")
		if info:
			info.text = "Entering %s..." % city.get("name", "city")
			info.add_theme_color_override("font_color", Color.YELLOW)

	_fade_to_scene("res://view/cityview/CityViewScene.tscn")

func _fade_to_scene(path: String) -> void:
	var canvas: CanvasLayer = get_node_or_null("HUD")
	if not canvas:
		get_tree().change_scene_to_file(path)
		return
	var fade := ColorRect.new()
	fade.name = "FadeOverlay"
	fade.color = Color(0, 0, 0, 0)
	fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	canvas.add_child(fade)
	var tween: Tween = create_tween()
	tween.tween_property(fade, "color", Color(0, 0, 0, 1), 0.35)
	tween.tween_callback(func(): get_tree().change_scene_to_file(path))

func _on_toggle_watch() -> void:
	# Pause / resume the single shared simulation clock.
	if SimulationClock.is_paused():
		SimulationClock.set_speed(SimulationClock.SPEED_NORMAL)
	else:
		SimulationClock.set_speed(SimulationClock.SPEED_PAUSED)
	_refresh_watch_btn()

func _refresh_watch_btn() -> void:
	if _watch_btn != null:
		_watch_btn.text = "▶ Resume Time" if SimulationClock.is_paused() else "⏸ Pause Time"
	if _watch_speed_btn != null:
		_watch_speed_btn.text = {0: "1×", 1: "1×", 2: "2×", 3: "5×"}.get(SimulationClock.game_speed, "1×")

func _on_cycle_watch_speed() -> void:
	# Cycle the shared clock NORMAL → FAST → FASTEST → NORMAL.
	var s: int = SimulationClock.game_speed
	if s == SimulationClock.SPEED_FAST:
		s = SimulationClock.SPEED_FASTEST
	elif s == SimulationClock.SPEED_FASTEST:
		s = SimulationClock.SPEED_NORMAL
	else:
		s = SimulationClock.SPEED_FAST
	SimulationClock.set_speed(s)
	if _watch_speed_btn != null:
		_watch_speed_btn.text = {1: "1×", 2: "2×", 3: "5×"}.get(s, "1×")

# The city the Develop button acts on: the right-click-selected city if it's one of
# yours, otherwise your least-developed holding (the natural default investment).
func _develop_target() -> int:
	if _action_city_id >= 0 and GameState.is_player_city(_action_city_id):
		return _action_city_id
	return GameState.player_lowest_dev_city()

func _on_develop_realm() -> void:
	var cid: int = _develop_target()
	if cid < 0:
		_set_info("You hold no cities to develop.")
		return
	var city_name: String = GameState.get_city(cid).get("name", "your city")
	if GameState.player_develop_city(cid):
		var dev: int = int(GameState.get_city(cid).get("development", 0))
		_set_info("⚒ %s prospers — development raised to %d. Your realm grows in standing." % [city_name, dev], Color(0.6, 0.9, 0.5))
		if _world_view != null:
			_world_view.refresh()
	else:
		_set_info("Cannot develop %s yet — the realm's treasury or stores are short." % city_name, Color(1.0, 0.6, 0.3))
	_refresh_develop_btn()
	_refresh_raise_btn()
	_refresh_realm_label()

# Update the Develop button to name its target city + cost, and disable it when the
# realm can't currently afford the investment (or the city is maxed).
func _refresh_develop_btn() -> void:
	if _develop_btn == null:
		return
	var cid: int = _develop_target()
	if cid < 0:
		_develop_btn.text = "⚒ Develop Realm"
		_develop_btn.disabled = true
		return
	var c: Dictionary = GameState.get_city(cid)
	var cost: Dictionary = GameState.develop_city_cost(cid)
	_develop_btn.text = "⚒ Develop %s  (%dg %dw %ds)" % [
		c.get("name", "city"), int(cost.get("gold", 0)), int(cost.get("wood", 0)), int(cost.get("stone", 0))]
	_develop_btn.disabled = not GameState.can_player_develop_city(cid)

func _on_raise_army() -> void:
	# Armies are no longer gold-levied — your host IS the soldiers you train at the Barracks
	# in the city view. This button just reports your standing host and points you there.
	var host: int = GameState.player_field_strength()
	_set_info("⚔ Your host: %d trained troops at your seat. Train more at the Barracks (city view), then March them from here." % host,
		Color(0.85, 0.85, 0.6))

# Reports the player's REAL standing host (trained at the Barracks) — armies are no longer
# purchased with gold, so this is informational and always enabled as a reminder.
func _refresh_raise_btn() -> void:
	if _raise_btn == null:
		return
	_raise_btn.text = "⚔ Host: %d trained — train at the Barracks" % GameState.player_field_strength()
	_raise_btn.disabled = false

func _on_march() -> void:
	# Already armed → this press cancels the march order.
	if _march_arming:
		_march_arming = false
		_march_source_city = -1
		_set_info("March order cancelled.", Color(0.80, 0.74, 0.54))
		_refresh_march_btn()
		return
	if _action_city_id < 0 or not GameState.is_player_city(_action_city_id):
		_set_info("Right-click your seat to march the troops you've trained there.", Color(1.0, 0.6, 0.3))
		return
	var host: int = GameState.player_field_strength()
	if host <= 0:
		_set_info("No trained troops to march — train soldiers at the Barracks in your city first.", Color(1.0, 0.6, 0.3))
		return
	_march_arming = true
	_march_source_city = _action_city_id
	_set_info("⚔ March order armed (%d trained troops from %s) — right-click an enemy village to send them." % [
		host, GameState.get_city(_action_city_id).get("name", "your seat")], Color(1.0, 0.9, 0.4))
	_refresh_march_btn()

# Enabled when the selected own city holds trained troops; shows targeting state while armed.
func _refresh_march_btn() -> void:
	if _march_btn == null:
		return
	if _march_arming:
		_march_btn.text = "⚔ Marching… right-click a target  (✕ cancel)"
		_march_btn.disabled = false
		return
	var host: int = GameState.player_field_strength() if (_action_city_id >= 0 and GameState.is_player_city(_action_city_id)) else 0
	if host > 0:
		_march_btn.text = "⚔ March host (%d) from %s" % [host, GameState.get_city(_action_city_id).get("name", "city")]
		_march_btn.disabled = false
	else:
		_march_btn.text = "⚔ March — select your seat (needs trained troops)"
		_march_btn.disabled = true

func _on_diplomacy() -> void:
	if _diplo_faction_id < 0:
		_set_info("Right-click a rival's city to treat with that kingdom.", Color(1.0, 0.6, 0.3))
		return
	var nm: String = _CampaignMap.kingdom_by_id(GameState.world, _diplo_faction_id).get("name", "the rival")
	# Toggle: at truce → declare war; otherwise → offer a truce.
	if GameState.player_relation_with(_diplo_faction_id) == "truce":
		GameState.player_set_diplomacy(_diplo_faction_id, "war")
		_set_info("⚔ You break the truce and declare war on %s." % nm, Color(1.0, 0.6, 0.3))
	else:
		GameState.player_set_diplomacy(_diplo_faction_id, "truce")
		_set_info("🕊 A truce is sworn with %s — their armies will keep off your lands." % nm, Color(0.6, 0.9, 0.5))
	_refresh_diplo_btn()

func _refresh_diplo_btn() -> void:
	if _diplo_btn == null:
		return
	if _diplo_faction_id < 0:
		_diplo_btn.text = "🕊 Diplomacy — select a rival's city"
		_diplo_btn.disabled = true
		return
	var nm: String = _CampaignMap.kingdom_by_id(GameState.world, _diplo_faction_id).get("name", "rival")
	if GameState.player_relation_with(_diplo_faction_id) == "truce":
		_diplo_btn.text = "⚔ Declare War on %s" % nm
	else:
		_diplo_btn.text = "🕊 Offer Truce to %s" % nm
	_diplo_btn.disabled = false

# Right-click selected a city for orders. If a march order is armed, this right-click
# designates the target (and launches). Otherwise it selects the city for develop/raise.
func _on_city_selected(city_id: int) -> void:
	var c: Dictionary = GameState.get_city(city_id)
	if c.is_empty():
		return
	if _world_view != null:
		_world_view.set_selected_city(city_id)   # visual selection ring

	# Campaign targeting: a real-troop host is awaiting a destination.
	if _march_arming:
		if GameState.is_player_city(city_id):
			# Re-selecting an own city cancels targeting and falls through to normal select.
			_march_arming = false
			_march_source_city = -1
		else:
			var tgt_name: String = c.get("name", "the enemy village")
			var host: int = GameState.player_field_strength()
			if GameState.player_march_units(_march_source_city, city_id):
				_set_info("⚔ Your %d trained troops march on %s! They leave the city and take the road." % [host, tgt_name], Color(0.6, 0.9, 0.5))
				if _world_view != null:
					_world_view.refresh()
				_refresh_march_status()
			else:
				_set_info("No road reaches %s from there — choose a connected target." % tgt_name, Color(1.0, 0.6, 0.3))
			_march_arming = false
			_march_source_city = -1
			_refresh_march_btn()
			return

	if GameState.is_player_city(city_id):
		_action_city_id = city_id
		_diplo_faction_id = -1
		_set_info("Selected %s (yours) — Development %d, Garrison ⚔ %d. Use Develop to invest here." % [
			c.get("name", "city"), int(c.get("development", 0)), int(c.get("garrison", 0))], Color(0.6, 0.9, 0.5))
	else:
		_action_city_id = -1
		var owner_id: int = int(_CampaignMap.owner_of(c))
		_diplo_faction_id = owner_id
		var owner_k: Dictionary = _CampaignMap.kingdom_by_id(GameState.world, owner_id)
		var owner_name: String = owner_k.get("name", "a rival lord") if not owner_k.is_empty() else "a rival lord"
		var rel: String = GameState.player_relation_with(owner_id)
		var rel_note: String = "  [truce]" if rel == "truce" else ("  [at war]" if rel == "war" else "")
		_set_info("%s is held by %s%s — develop only your own; use Diplomacy to treat with them." % [
			c.get("name", "city"), owner_name, rel_note], Color(1.0, 0.6, 0.3))
	_refresh_develop_btn()
	_refresh_raise_btn()
	_refresh_march_btn()
	_refresh_diplo_btn()

func _refresh_realm_label() -> void:
	if _realm_label == null:
		return
	var s: Dictionary = GameState.player_realm_stores()
	if s.is_empty():
		_realm_label.text = ""
		return
	_realm_label.text = "Realm stores —  %d gold   %d wood   %d stone   ·   %d cities" % [
		int(s.get("treasury", 0)), int(s.get("wood", 0)), int(s.get("stone", 0)), int(s.get("cities", 0))]

# Persistent readout of the player's marching armies (target + ETA in days).
func _refresh_march_status() -> void:
	if _march_status_label == null:
		return
	var armies: Array = GameState.player_marching_armies()
	if armies.is_empty():
		_march_status_label.text = ""
		return
	if armies.size() == 1:
		var a: Dictionary = armies[0]
		var eta: int = int(a.get("eta_days", 0))
		_march_status_label.text = "⚔ Your army (%d) marches on %s — ~%d day%s away" % [
			int(a.get("size", 0)), a.get("dest_name", "enemy lands"), eta, "" if eta == 1 else "s"]
	else:
		var total: int = 0
		for a in armies:
			total += int(a.get("size", 0))
		_march_status_label.text = "⚔ %d armies on the march (%d troops in the field)" % [armies.size(), total]

func _set_info(text: String, color: Color = Color(0.80, 0.74, 0.54)) -> void:
	var canvas: CanvasLayer = get_node_or_null("HUD")
	if canvas == null:
		return
	var info: Label = canvas.get_node_or_null("InfoPanel/InfoLabel")
	if info != null:
		info.text = text
		info.add_theme_color_override("font_color", color)

# Left-click a marching host (off-city) → read its banner: who, how many, where bound,
# and how many days out (the distance-scaled ETA from iter 67). Makes armies on the map
# legible instead of anonymous moving dots.
func _on_army_inspected(info: Dictionary) -> void:
	var size: int = int(info.get("size", 0))
	var owner_name: String = String(info.get("owner_name", "A kingdom"))
	var is_mine: bool = int(info.get("owner", -1)) == _CampaignMap.player_faction_id(GameState.world)
	var who: String = "Your host" if is_mine else "%s's host" % owner_name
	var col: Color = Color(0.55, 0.90, 0.55) if is_mine else Color.from_string(String(info.get("color_hex", "#cccccc")), Color(0.85, 0.78, 0.55))
	var txt: String
	if bool(info.get("moving", false)):
		var dest: String = String(info.get("dest_name", ""))
		var eta: int = int(info.get("eta_days", 0))
		var dest_str: String = dest if dest != "" else "the field"
		txt = "⚔ %s — %d troops, marching on %s (~%d day%s away)" % [
			who, size, dest_str, eta, "" if eta == 1 else "s"]
	else:
		txt = "⚔ %s — %d troops, holding position" % [who, size]
	_set_info(txt, col)

func _on_main_menu() -> void:
	get_tree().change_scene_to_file("res://view/menu/MainMenuScene.tscn")

func _on_mouse_entered_map() -> void:
	pass  # hover handled in WorldMapView via _input

# Populate the info panel with the hovered city's details (was: hover only highlighted
# the city, the panel never actually showed anything — "Hover to see details" was a lie).
func _on_city_hovered(city_id: int) -> void:
	var canvas: CanvasLayer = get_node_or_null("HUD")
	if canvas == null: return
	var info: Label = canvas.get_node_or_null("InfoPanel/InfoLabel")
	if info == null: return
	if city_id < 0:
		info.text = "Hover a city to see details · Click it to enter and rule it"
		info.add_theme_color_override("font_color", Color(0.80, 0.74, 0.54))
		return
	var city: Dictionary = GameState.get_city(city_id)
	if city.is_empty(): return
	var wm: Dictionary = GameState.world.get("world_map", {})
	var owner_fid: int = int(city.get("owner_faction_id", city.get("faction_id", -1)))
	var fac_name: String = "Unclaimed"
	var fac_col: Color = Color(0.85, 0.78, 0.55)
	for f in wm.get("factions", []):
		if f is Dictionary and f.get("id", -1) == owner_fid:
			fac_name = f.get("name", fac_name)
			fac_col = Color.from_string(f.get("color_hex", "#cccccc"), fac_col)
			break
	var dev: int = int(city.get("development", city.get("tier", 0)))
	var gar: int = int(city.get("garrison", 0))
	info.text = "%s — %s\nDevelopment %d · Garrison ⚔ %d\n(click to enter)" % [
		city.get("name", "City"), fac_name, dev, gar]
	info.add_theme_color_override("font_color", fac_col)

# A feudal title rose (Reeve→…→King). The strategic tick fires this while the player is on this
# map (capturing cities), so the celebration + the King WIN must present HERE, not only in the city
# view. Mirrors CityViewScene._on_title_promoted.
func _on_title_promoted(_title_index: int, title_name: String) -> void:
	if is_instance_valid(_event_feed):
		_event_feed.push("👑 You have risen to %s!" % title_name, 8.0, Color(1.0, 0.85, 0.3))
	if title_name == "King":
		_show_endgame(true, "You have risen to KING — the realm is yours!")

# A rival kingdom fell — vanquishing the LAST one is the conquest victory (mirrors CityViewScene).
func _on_ai_faction_defeated(faction_id: int) -> void:
	if is_instance_valid(_event_feed):
		_event_feed.push("⚔ %s has been vanquished!" % GameState.get_faction_display_name(faction_id), 6.0, Color(1.0, 0.85, 0.2))
	var any_alive: bool = false
	for fac in GameState.ai_factions:
		if fac is Dictionary and fac.get("is_alive", true):
			any_alive = true
			break
	if not any_alive and GameState.ai_factions.size() > 0:
		_show_endgame(true, "All enemies vanquished! Sovereign's Reach is yours!")

# A siege is marshalling against the player's seat — warn them on the map (the seat is besieged while
# they campaign abroad). Mirrors CityViewScene's warning but nudges the player to return.
func _on_ai_siege_assembling(faction_id: int, _target_player_id: int, eta_ticks: int) -> void:
	if not is_instance_valid(_event_feed):
		return
	var who: String = GameState.get_faction_display_name(faction_id)
	var days: int = maxi(1, int(round(float(eta_ticks) / 240.0)))
	var ready: bool = GameState.players.size() > 0 and GameState.is_siege_ready(GameState.players[0])
	var tail: String = " Your walls and garrison steady the people." if ready \
		else " Raise walls, towers and a garrison — return to your seat before it lands!"
	_event_feed.push("⚠ %s is marshalling a siege against your seat — ready in ~%d days.%s" % [who, days, tail],
		9.0, Color(1.0, 0.7, 0.25))

# A tribute envoy arrived while the player is on the map. The Accept/Refuse panel is in the city
# HUD, so nudge the player to return to the seat to answer before the demand lapses (it re-presents
# there). Feed-only — no decision is taken here.
func _on_envoy_sent_map(faction_id: int, demand: Dictionary) -> void:
	if not is_instance_valid(_event_feed) or demand.get("player_id", -1) != 0:
		return
	var who: String = GameState.get_faction_display_name(faction_id)
	var parts: Array = []
	for res in demand.get("demands", {}):
		parts.append("%d %s" % [demand["demands"][res], res])
	var what: String = ", ".join(parts) if not parts.is_empty() else "tribute"
	var deadline: int = int(demand.get("deadline_tick", 0))
	var days: int = maxi(1, int(round(float(deadline - SimulationClock.current_tick) / 240.0)))
	_event_feed.push("📜 An envoy of %s demands tribute (%s) — return to your seat to answer within ~%d days." % [who, what, days],
		8.0, Color(0.95, 0.85, 0.5))

# Popularity cratering to a revolt is a DEFEAT — the seat keeps ticking while you're on the map.
func _on_popularity_changed(_pid: int, _old: float, new_val: float) -> void:
	if new_val < 10.0:
		_show_endgame(false, "The people have revolted! Your reign is over.")

# The player's hall/keep razed (siege) is a DEFEAT — the seat can fall while you campaign abroad.
func _on_building_destroyed(player_id: int, building_id: int, _cause: String) -> void:
	if player_id != 0 or GameState.players.is_empty():
		return
	for bld in GameState.players[0].get("buildings", []):
		if bld is Dictionary and int(bld.get("id", -1)) == building_id \
				and String(bld.get("type", "")) in ["village_hall", "keep"]:
			_show_endgame(false, "Your keep has fallen! The realm is lost.")
			return

# Minimal end-game overlay (the world map has no game-over panel of its own). Pauses the realm and
# presents the win (King) or defeat (last holding lost), mirroring CityViewScene._show_game_over so
# both outcomes present wherever they're reached — the climb AND the collapse happen on this map.
func _show_endgame(victory: bool, message: String) -> void:
	if _endgame_shown:
		return
	_endgame_shown = true
	SimulationClock.set_speed(SimulationClock.SPEED_PAUSED)
	# Shared end-game overlay (iter284) at layer 60 (over the world-map chrome). On the map the only
	# action is Main Menu — Play Again/World Map don't apply to a finished strategic campaign.
	preload("res://view/hud/GameOverOverlay.gd").build(self, victory, message, [
		{"text": "Main Menu", "action": func(): get_tree().change_scene_to_file("res://view/menu/MainMenuScene.tscn")},
	], 60)
