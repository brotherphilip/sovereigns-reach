extends Node
# Strategic world map scene. Generates WorldMapData (or reads cached),
# builds WorldMapView, handles city-click to enter CityViewScene.

const WorldMapData = preload("res://simulation/world/WorldMapData.gd")

var _world_view: Control = null

func _ready() -> void:
	# Generate or reuse world map data
	if not GameState.world.has("world_map") or GameState.world["world_map"].is_empty():
		var seed_val: int = GameState.server_config.get("map_seed", 42) \
		                    if GameState.has_method("server_config") \
		                    else 42
		GameState.world["world_map"] = WorldMapData.generate(seed_val)

	_build_scene()
	SimulationClock.set_speed(SimulationClock.SPEED_PAUSED)

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
	info_lbl.text     = "Hover or click a city to see details"
	info_lbl.position = Vector2(8, 6)
	info_lbl.size     = Vector2(264, 70)
	info_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info_lbl.add_theme_font_size_override("font_size", 11)
	info_lbl.add_theme_color_override("font_color", Color(0.80, 0.74, 0.54))
	info_panel.add_child(info_lbl)

	# Connect hover → info panel
	_world_view.mouse_entered.connect(_on_mouse_entered_map)

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

	# Defer scene change so the label has a frame to render
	get_tree().create_timer(0.05).timeout.connect(
		func(): get_tree().change_scene_to_file("res://view/cityview/CityViewScene.tscn"))

func _on_main_menu() -> void:
	get_tree().change_scene_to_file("res://view/menu/MainMenuScene.tscn")

func _on_mouse_entered_map() -> void:
	pass  # hover handled in WorldMapView via _input
