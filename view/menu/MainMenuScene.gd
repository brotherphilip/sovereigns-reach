extends Node
# Main menu entry point. Builds title screen procedurally.
# New Game → WorldMapScene; Load Game → save picker → CityViewScene; Quit.

const SaveManager = preload("res://simulation/persistence/SaveManager.gd")
const DifficultySystem = preload("res://simulation/core/DifficultySystem.gd")

var _diff_btn: Button = null

func _ready() -> void:
	_build_background()
	_build_ui()
	# Reset any leftover simulation state from a previous game
	SimulationClock.set_speed(SimulationClock.SPEED_PAUSED)

# ── Background ────────────────────────────────────────────────────────────────

func _build_background() -> void:
	var bg := _MenuBG.new()
	bg.name = "Background"
	add_child(bg)

# ── UI panels ─────────────────────────────────────────────────────────────────

func _build_ui() -> void:
	var canvas := CanvasLayer.new()
	canvas.name  = "UICanvas"
	canvas.layer = 10
	add_child(canvas)

	var vp: Vector2 = get_viewport().get_visible_rect().size
	if vp == Vector2.ZERO:
		vp = Vector2(1280, 720)

	# Semi-transparent center panel
	var panel := Panel.new()
	panel.position = Vector2(vp.x * 0.5 - 200, vp.y * 0.3)
	panel.size     = Vector2(400, 340)
	var style := StyleBoxFlat.new()
	style.bg_color    = Color(0.08, 0.10, 0.07, 0.86)
	style.set_border_width_all(2)
	style.border_color = Color(0.55, 0.45, 0.20, 0.9)
	style.corner_radius_top_left    = 6
	style.corner_radius_top_right   = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	panel.add_theme_stylebox_override("panel", style)
	canvas.add_child(panel)

	# Title
	var title := Label.new()
	title.text = "Sovereign's Reach"
	title.position = Vector2(0, 24)
	title.size = Vector2(400, 60)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", Color(0.91, 0.76, 0.26))
	panel.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "A Medieval Kingdom Builder"
	subtitle.position = Vector2(0, 76)
	subtitle.size = Vector2(400, 24)
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_size_override("font_size", 12)
	subtitle.add_theme_color_override("font_color", Color(0.70, 0.64, 0.46))
	panel.add_child(subtitle)

	# Divider
	var div := ColorRect.new()
	div.color    = Color(0.55, 0.45, 0.20, 0.5)
	div.position = Vector2(30, 110)
	div.size     = Vector2(340, 1)
	panel.add_child(div)

	# Buttons
	var has_save: bool = SaveManager.save_exists(SaveManager.DEFAULT_SAVE_PATH)
	var buttons: Array = []
	if has_save:
		buttons.append(["Resume Save", _on_resume_save])
	buttons.append_array([
		["New Game",  _on_new_game],
		["Load Game", _on_load_game],
		["Quit",      _on_quit],
	])
	var btn_y: float = 130.0
	for b in buttons:
		var btn := _make_menu_button(b[0], Vector2(80, btn_y), Vector2(240, 46), b[1])
		panel.add_child(btn)
		btn_y += 60.0

	# Difficulty selector — cycles PEACEFUL -> NORMAL -> HARD -> SIEGE_LORD
	_diff_btn = _make_menu_button("Difficulty: " + DifficultySystem.level_name(DifficultySystem.current), Vector2(80, btn_y), Vector2(240, 46), _on_cycle_difficulty)
	panel.add_child(_diff_btn)
	btn_y += 60.0

	# Version
	var ver := Label.new()
	ver.text = "v2.0"
	ver.position = Vector2(vp.x - 130, vp.y - 24)
	ver.size = Vector2(120, 20)
	ver.add_theme_font_size_override("font_size", 10)
	ver.add_theme_color_override("font_color", Color(0.5, 0.5, 0.4))
	canvas.add_child(ver)

func _make_menu_button(text: String, pos: Vector2, sz: Vector2,
                        callback: Callable) -> Button:
	var btn := Button.new()
	btn.text     = text
	btn.position = pos
	btn.size     = sz
	btn.add_theme_font_size_override("font_size", 15)
	btn.pressed.connect(callback)
	return btn

func _on_cycle_difficulty() -> void:
	DifficultySystem.current = (DifficultySystem.current + 1) % 4
	if _diff_btn != null:
		_diff_btn.text = "Difficulty: " + DifficultySystem.level_name(DifficultySystem.current)

# ── Transitions ───────────────────────────────────────────────────────────────

func _on_new_game() -> void:
	# Clear any leftover world state so WorldMapScene generates fresh
	GameState.world.erase("world_map")
	GameState.world.erase("selected_city_id")
	get_tree().change_scene_to_file("res://view/worldmap/WorldMapScene.tscn")

func _on_resume_save() -> void:
	_load_slot(SaveManager.DEFAULT_SAVE_PATH)

func _on_load_game() -> void:
	_show_load_overlay()

func _on_quit() -> void:
	get_tree().quit()

# ── Load overlay ──────────────────────────────────────────────────────────────

func _show_load_overlay() -> void:
	var canvas := get_node_or_null("UICanvas")
	if canvas == null: return
	var vp: Vector2 = get_viewport().get_visible_rect().size
	if vp == Vector2.ZERO: vp = Vector2(1280, 720)

	var overlay := Panel.new()
	overlay.name     = "LoadOverlay"
	overlay.position = Vector2(vp.x * 0.5 - 220, vp.y * 0.3)
	overlay.size     = Vector2(440, 300)
	var sty := StyleBoxFlat.new()
	sty.bg_color = Color(0.07, 0.09, 0.07, 0.95)
	sty.set_border_width_all(2)
	sty.border_color = Color(0.55, 0.45, 0.20, 0.9)
	overlay.add_theme_stylebox_override("panel", sty)
	canvas.add_child(overlay)

	var hdr := Label.new()
	hdr.text = "Load Game"
	hdr.position = Vector2(0, 10)
	hdr.size = Vector2(440, 30)
	hdr.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hdr.add_theme_font_size_override("font_size", 16)
	hdr.add_theme_color_override("font_color", Color(0.91, 0.76, 0.26))
	overlay.add_child(hdr)

	# Build save list from the single default slot if it exists
	if not SaveManager.save_exists(SaveManager.DEFAULT_SAVE_PATH):
		var no_saves := Label.new()
		no_saves.text = "No save files found."
		no_saves.position = Vector2(0, 100)
		no_saves.size = Vector2(440, 30)
		no_saves.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		no_saves.add_theme_color_override("font_color", Color.LIGHT_GRAY)
		overlay.add_child(no_saves)
	else:
		var meta: Dictionary = SaveManager.get_save_metadata(SaveManager.DEFAULT_SAVE_PATH)
		var saved_ts: int = int(meta.get("saved_at", 0))
		var date_str: String = Time.get_datetime_string_from_unix_time(saved_ts).left(16).replace("T", " ") if saved_ts > 0 else "Unknown date"
		var game_day: int = int(meta.get("game_day", 0))
		var shires: int   = int(meta.get("shire_count", 0))
		var diff: String  = meta.get("difficulty", "Normal")
		var info_lbl := Label.new()
		info_lbl.text = "Saved: %s\nDay %d  ·  %d Shires  ·  %s" % [date_str, game_day, shires, diff]
		info_lbl.position = Vector2(20, 52)
		info_lbl.size = Vector2(400, 46)
		info_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		info_lbl.add_theme_font_size_override("font_size", 11)
		info_lbl.add_theme_color_override("font_color", Color(0.80, 0.74, 0.54))
		overlay.add_child(info_lbl)
		var slot: String = SaveManager.DEFAULT_SAVE_PATH
		var btn := Button.new()
		btn.text     = "Load Save"
		btn.position = Vector2(110, 108)
		btn.size     = Vector2(220, 40)
		btn.add_theme_font_size_override("font_size", 14)
		btn.pressed.connect(func(): _load_slot(slot))
		overlay.add_child(btn)

	var close_btn := Button.new()
	close_btn.text     = "Cancel"
	close_btn.position = Vector2(160, 256)
	close_btn.size     = Vector2(120, 34)
	close_btn.pressed.connect(func(): overlay.queue_free())
	overlay.add_child(close_btn)

func _load_slot(slot: String) -> void:
	var data: Dictionary = SaveManager.load_save(slot)
	if data.is_empty():
		return
	GameState.deserialize(data)
	get_tree().change_scene_to_file("res://view/cityview/CityViewScene.tscn")

# ── Background inner class ────────────────────────────────────────────────────

class _MenuBG extends Node2D:
	var _angle: float = 0.0

	func _process(delta: float) -> void:
		_angle += delta * 0.08
		queue_redraw()
	const BLOB_DATA: Array = [
		# [cx_frac, cy_frac, rx, ry, color]
		[0.10, 0.15, 180, 120, Color(0.18, 0.27, 0.14, 1.0)],
		[0.88, 0.08, 220, 90,  Color(0.25, 0.34, 0.18, 1.0)],
		[0.55, 0.90, 260, 80,  Color(0.15, 0.22, 0.12, 1.0)],
		[0.05, 0.75, 150, 130, Color(0.22, 0.30, 0.16, 1.0)],
		[0.78, 0.60, 200, 110, Color(0.19, 0.26, 0.13, 1.0)],
		[0.40, 0.20, 170, 70,  Color(0.24, 0.31, 0.17, 1.0)],
		[0.92, 0.82, 140, 160, Color(0.16, 0.23, 0.11, 1.0)],
		[0.30, 0.70, 190, 100, Color(0.28, 0.36, 0.20, 1.0)],
		[0.65, 0.40, 130, 90,  Color(0.21, 0.29, 0.15, 1.0)],
		[0.15, 0.50, 160, 70,  Color(0.26, 0.33, 0.19, 1.0)],
		[0.50, 0.55, 300, 140, Color(0.17, 0.24, 0.12, 0.7)],
		[0.80, 0.30, 120, 80,  Color(0.23, 0.30, 0.16, 1.0)],
	]

	func _draw() -> void:
		var vp: Vector2 = get_viewport_rect().size
		if vp == Vector2.ZERO: vp = Vector2(1280, 720)

		# Base fill — dark forest green
		draw_rect(Rect2(Vector2.ZERO, vp), Color(0.13, 0.19, 0.10))

		# Terrain blobs (8-sided ellipse approximation)
		for blob in BLOB_DATA:
			var cx: float = blob[0] * vp.x
			var cy: float = blob[1] * vp.y
			var rx: float = blob[2]
			var ry: float = blob[3]
			var col: Color = blob[4]
			_draw_ellipse(cx, cy, rx, ry, col)

		# Decorative parchment border
		var border_inset: float = 16.0
		var border_pts := PackedVector2Array([
			Vector2(border_inset, border_inset),
			Vector2(vp.x - border_inset, border_inset),
			Vector2(vp.x - border_inset, vp.y - border_inset),
			Vector2(border_inset, vp.y - border_inset),
			Vector2(border_inset, border_inset),
		])
		draw_polyline(border_pts, Color(0.55, 0.45, 0.20, 0.35), 1.5)

		# Corner decorations (small diamond shapes)
		var corners: Array = [
			Vector2(border_inset, border_inset),
			Vector2(vp.x - border_inset, border_inset),
			Vector2(vp.x - border_inset, vp.y - border_inset),
			Vector2(border_inset, vp.y - border_inset),
		]
		for corn in corners:
			draw_circle(corn, 4.0, Color(0.55, 0.45, 0.20, 0.5))

		# Vignette: semi-transparent dark overlay at edges
		draw_rect(Rect2(0, 0, vp.x, 40), Color(0, 0, 0, 0.4))
		draw_rect(Rect2(0, vp.y - 40, vp.x, 40), Color(0, 0, 0, 0.4))
		draw_rect(Rect2(0, 0, 40, vp.y), Color(0, 0, 0, 0.4))
		draw_rect(Rect2(vp.x - 40, 0, 40, vp.y), Color(0, 0, 0, 0.4))

		# Animated decorative sigil (slowly rotating crown-like ring)
		var cx: float = vp.x * 0.5
		var cy: float = vp.y * 0.25
		var ring_col := Color(0.55, 0.45, 0.20, 0.18)
		draw_arc(Vector2(cx, cy), 80.0, 0, TAU, 32, ring_col, 1.5)
		draw_arc(Vector2(cx, cy), 64.0, 0, TAU, 32, ring_col, 0.8)
		const POINTS: int = 8
		for i in range(POINTS):
			var a: float = _angle + TAU * float(i) / float(POINTS)
			var p1: Vector2 = Vector2(cx + cos(a) * 64.0, cy + sin(a) * 64.0)
			var p2: Vector2 = Vector2(cx + cos(a) * 80.0, cy + sin(a) * 80.0)
			draw_line(p1, p2, Color(0.55, 0.45, 0.20, 0.30), 1.5)
		var inner_ring_col := Color(0.91, 0.76, 0.26, 0.10)
		draw_arc(Vector2(cx, cy), 44.0, _angle, _angle + TAU, 32, inner_ring_col, 2.5)

	func _draw_ellipse(cx: float, cy: float, rx: float, ry: float, col: Color) -> void:
		var pts := PackedVector2Array()
		var SIDES: int = 8
		for i in range(SIDES):
			var angle: float = TAU * float(i) / float(SIDES)
			pts.append(Vector2(cx + rx * cos(angle), cy + ry * sin(angle)))
		draw_colored_polygon(pts, col)
