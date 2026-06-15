extends Node
# Strategic world map scene. Generates WorldMapData (or reads cached),
# builds WorldMapView, handles city-click to enter CityViewScene.

const WorldMapData = preload("res://simulation/world/WorldMapData.gd")

var _world_view: Control = null

var _loading_canvas: CanvasLayer = null

# "Watch the campaign" live strategic ticker.
var _watching: bool = false
var _watch_accum: float = 0.0
var _watch_speed: int = 1               # 1 = 1 day / WATCH_INTERVAL; 2,4 faster
var _watch_btn: Button = null
var _watch_speed_btn: Button = null
var _day_label: Label = null
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

	_build_scene()
	SimulationClock.set_speed(SimulationClock.SPEED_PAUSED)

	# Dev/headless hook: jump straight into spectating a developed rival city.
	# (Returns early — that flow changes scene itself.)
	if OS.get_environment("SR_SPECTATE") != "":
		_dev_jump_to_spectator()
		return

	# Reveal the map: drop the loading overlay now that the scene is built.
	if _loading_canvas:
		_loading_canvas.queue_free()
		_loading_canvas = null

	# Dev/headless hook: auto-run the campaign watcher (used for screenshots).
	if OS.get_environment("SR_AUTOWATCH") != "":
		_watch_speed = 4
		_on_toggle_watch()

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

# Drive the strategic campaign simulation while "watching", and keep the view in
# sync. The in-game clock stays paused on the map; we advance the strategic layer
# directly so rivals visibly grow, march and conquer.
func _process(delta: float) -> void:
	if not _watching or _world_view == null:
		return
	_watch_accum += delta * float(_watch_speed)
	var advanced: bool = false
	while _watch_accum >= WATCH_INTERVAL:
		_watch_accum -= WATCH_INTERVAL
		GameState.advance_strategic_day()
		advanced = true
	if advanced:
		_world_view.refresh()
		if _day_label != null:
			_day_label.text = "Campaign day %d" % GameState.strategic_day()

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
	info_lbl.text     = "Hover a city to see details · Click it to enter and rule it"
	info_lbl.position = Vector2(8, 6)
	info_lbl.size     = Vector2(264, 70)
	info_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info_lbl.add_theme_font_size_override("font_size", 11)
	info_lbl.add_theme_color_override("font_color", Color(0.80, 0.74, 0.54))
	info_panel.add_child(info_lbl)

	# Connect hover → info panel (show the hovered city's details)
	_world_view.mouse_entered.connect(_on_mouse_entered_map)
	_world_view.city_hovered.connect(_on_city_hovered)

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
	_watching = not _watching
	if _watch_btn != null:
		_watch_btn.text = "⏸ Pause Campaign" if _watching else "▶ Watch Campaign"

func _on_cycle_watch_speed() -> void:
	_watch_speed = 1 if _watch_speed >= 4 else _watch_speed * 2
	if _watch_speed_btn != null:
		_watch_speed_btn.text = "%d×" % _watch_speed

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
