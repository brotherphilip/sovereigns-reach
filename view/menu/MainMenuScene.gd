extends Node
# Main menu entry point. Builds title screen procedurally.
# New Game → WorldMapScene; Load Game → save picker → CityViewScene; Quit.

const SaveManager = preload("res://simulation/persistence/SaveManager.gd")
const DifficultySystem = preload("res://simulation/core/DifficultySystem.gd")

var _diff_btn: Button = null
var _title: Label = null
var _title_shadow: Label = null
var _t: float = 0.0

func _ready() -> void:
	_build_background()
	_build_ui()
	# Reset any leftover simulation state from a previous game
	SimulationClock.set_speed(SimulationClock.SPEED_PAUSED)

func _process(delta: float) -> void:
	# Gentle gold "breathing" shimmer on the title for a touch of life.
	_t += delta
	if _title != null:
		var pulse: float = 0.5 + 0.5 * sin(_t * 1.6)
		_title.add_theme_color_override("font_color",
			Color(0.93, 0.77, 0.30).lerp(Color(1.0, 0.94, 0.58), pulse))

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

	# Buttons list (decides panel height so nothing clips).
	var has_save: bool = SaveManager.save_exists(SaveManager.DEFAULT_SAVE_PATH)
	var buttons: Array = []
	if has_save:
		buttons.append(["Resume Save", _on_resume_save])
	buttons.append_array([
		["New Game",  _on_new_game],
		["Load Game", _on_load_game],
		["Quit",      _on_quit],
	])
	var n_rows: int = buttons.size() + 1  # +1 for difficulty
	const PW: float = 480.0
	const ROW_H: float = 62.0
	const BTN_TOP: float = 188.0
	var ph: float = BTN_TOP + n_rows * ROW_H + 28.0

	# Center panel — warm parchment-dark with a heavy gold frame and shadow.
	var panel := Panel.new()
	panel.position = Vector2(vp.x * 0.5 - PW * 0.5, vp.y * 0.5 - ph * 0.5)
	panel.size     = Vector2(PW, ph)
	var style := StyleBoxFlat.new()
	style.bg_color     = Color(0.13, 0.10, 0.07, 0.96)
	style.set_border_width_all(3)
	style.border_color = Color(0.80, 0.62, 0.28, 1.0)
	style.set_corner_radius_all(12)
	style.shadow_color = Color(0.0, 0.0, 0.0, 0.6)
	style.shadow_size  = 14
	panel.add_theme_stylebox_override("panel", style)
	canvas.add_child(panel)

	# Title (with a drop shadow for weight)
	var title_shadow := Label.new()
	title_shadow.text = "Sovereign's Reach"
	title_shadow.position = Vector2(3, 41)
	title_shadow.size = Vector2(PW, 60)
	title_shadow.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_shadow.add_theme_font_size_override("font_size", 42)
	title_shadow.add_theme_color_override("font_color", Color(0.0, 0.0, 0.0, 0.55))
	panel.add_child(title_shadow)
	_title_shadow = title_shadow
	var title := Label.new()
	title.text = "Sovereign's Reach"
	title.position = Vector2(0, 38)
	title.size = Vector2(PW, 60)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 42)
	title.add_theme_color_override("font_color", Color(0.96, 0.80, 0.32))
	panel.add_child(title)
	_title = title

	var subtitle := Label.new()
	subtitle.text = "A Medieval Kingdom Builder"
	subtitle.position = Vector2(0, 104)
	subtitle.size = Vector2(PW, 24)
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_size_override("font_size", 14)
	subtitle.add_theme_color_override("font_color", Color(0.74, 0.66, 0.48))
	panel.add_child(subtitle)

	# Gold divider
	var div := ColorRect.new()
	div.color    = Color(0.72, 0.56, 0.26, 0.7)
	div.position = Vector2(40, 150)
	div.size     = Vector2(PW - 80, 2)
	panel.add_child(div)

	var bx: float = (PW - 360.0) * 0.5
	var btn_y: float = BTN_TOP
	for b in buttons:
		var btn := _make_menu_button(b[0], Vector2(bx, btn_y), Vector2(360, 50), b[1])
		panel.add_child(btn)
		btn_y += ROW_H

	# Difficulty selector — cycles PEACEFUL -> NORMAL -> HARD -> SIEGE_LORD
	_diff_btn = _make_menu_button("Difficulty: " + DifficultySystem.level_name(DifficultySystem.current), Vector2(bx, btn_y), Vector2(360, 50), _on_cycle_difficulty)
	panel.add_child(_diff_btn)
	btn_y += ROW_H

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
	btn.add_theme_font_size_override("font_size", 17)
	btn.add_theme_color_override("font_color", Color(0.94, 0.88, 0.72))
	btn.add_theme_color_override("font_hover_color", Color(1.0, 0.96, 0.74))
	btn.add_theme_color_override("font_pressed_color", Color(0.85, 0.70, 0.40))
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.20, 0.15, 0.09, 0.96)
	normal.set_corner_radius_all(7)
	normal.set_border_width_all(2)
	normal.border_color = Color(0.58, 0.45, 0.22, 0.95)
	btn.add_theme_stylebox_override("normal", normal)
	var hover := normal.duplicate()
	hover.bg_color = Color(0.36, 0.27, 0.13, 1.0)
	hover.border_color = Color(0.90, 0.72, 0.34, 1.0)
	btn.add_theme_stylebox_override("hover", hover)
	var pressed := normal.duplicate()
	pressed.bg_color = Color(0.14, 0.10, 0.06, 1.0)
	btn.add_theme_stylebox_override("pressed", pressed)
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
		var btn := _make_menu_button("Load Save", Vector2(110, 108), Vector2(220, 40), func(): _load_slot(slot))
		overlay.add_child(btn)

	var close_btn := _make_menu_button("Cancel", Vector2(160, 256), Vector2(120, 34), func(): overlay.queue_free())
	overlay.add_child(close_btn)

func _load_slot(slot: String) -> void:
	var data: Dictionary = SaveManager.load_save(slot)
	if data.is_empty():
		return
	GameState.deserialize(data)
	get_tree().change_scene_to_file("res://view/cityview/CityViewScene.tscn")

# ── Cinematic cross-fading background ─────────────────────────────────────────
# A sequence of animated medieval vignettes that slowly cross-fade into one
# another. Each scene is its own Node2D child (so we can fade it via modulate.a);
# a persistent _Overlay child draws the vignette + parchment frame on top.

class _MenuBG extends Node2D:
	const HOLD: float = 8.0   # seconds a scene stays fully visible
	const FADE: float = 2.6   # seconds to cross-fade to the next scene

	var _scenes: Array = []
	var _idx: int = 0
	var _next: int = 0
	var _timer: float = 0.0
	var _fading: bool = false
	var _fade_t: float = 0.0

	func _ready() -> void:
		_scenes = [
			_DawnKeep.new(),
			_VillageWakes.new(),
			_MarketDay.new(),
			_HarvestFields.new(),
			_NightFestival.new(),
			_SiegeAtDusk.new(),
		]
		_scenes.shuffle()
		for i in _scenes.size():
			var s = _scenes[i]
			# Give each scene a unique slow Ken Burns push (always zoomed in a
			# little so the drift never reveals the canvas edges).
			s.kz0 = 1.03 + randf() * 0.02
			s.kz1 = s.kz0 + 0.06 + randf() * 0.05
			var ang: float = randf() * TAU
			s.kpan = Vector2(cos(ang), sin(ang))
			s.modulate.a = 1.0 if i == 0 else 0.0
			s.visible = (i == 0)
			add_child(s)
		if not _scenes.is_empty():
			_scenes[0].begin()
		# Persistent framing + storybook caption on top of every scene.
		add_child(_Overlay.new())

	func _process(delta: float) -> void:
		if _scenes.size() < 2:
			return
		if not _fading:
			_timer += delta
			if _timer >= HOLD:
				_fading = true
				_fade_t = 0.0
				_next = (_idx + 1) % _scenes.size()
				_scenes[_next].visible = true
				_scenes[_next].modulate.a = 0.0
				_scenes[_next].begin()
		else:
			_fade_t += delta
			var p: float = clampf(_fade_t / FADE, 0.0, 1.0)
			# Ease in-out for a softer dissolve.
			var e: float = p * p * (3.0 - 2.0 * p)
			_scenes[_idx].modulate.a = 1.0 - e
			_scenes[_next].modulate.a = e
			if p >= 1.0:
				_scenes[_idx].visible = false
				_scenes[_idx].modulate.a = 1.0
				_idx = _next
				_fading = false
				_timer = 0.0


# ── Shared scene base ─────────────────────────────────────────────────────────

class _Scene extends Node2D:
	const KB_DUR: float = 13.0   # seconds the Ken Burns push spans

	var t: float = 0.0
	var age: float = 0.0         # time since this scene became active
	var caption: String = ""     # storybook label shown by _Overlay
	var kz0: float = 1.04        # Ken Burns start zoom
	var kz1: float = 1.12        # Ken Burns end zoom
	var kpan: Vector2 = Vector2.ZERO  # drift direction (unit-ish)

	# Called by _MenuBG when this scene starts fading in.
	func begin() -> void:
		age = 0.0

	func _process(delta: float) -> void:
		t += delta
		if visible:
			age += delta
			_apply_ken_burns()
			queue_redraw()

	# Slow zoom + drift. Staying zoomed in (scale ≥ 1) and keeping the pan within
	# the zoom headroom guarantees the scaled scene always covers the screen.
	func _apply_ken_burns() -> void:
		var p: float = clampf(age / KB_DUR, 0.0, 1.0)
		var e: float = p * p * (3.0 - 2.0 * p)
		var s: float = lerpf(kz0, kz1, e)
		var c: Vector2 = vp() * 0.5
		scale = Vector2(s, s)
		position = c * (1.0 - s) + kpan * (s - 1.0) * c

	func vp() -> Vector2:
		var v: Vector2 = get_viewport_rect().size
		if v == Vector2.ZERO: v = Vector2(1280, 720)
		return v

	# Vertical gradient fill.
	func vgrad(x: float, y: float, w: float, h: float, top: Color, bot: Color, steps: int = 48) -> void:
		var sh: float = h / float(steps)
		for i in range(steps):
			var f: float = float(i) / float(steps - 1)
			draw_rect(Rect2(x, y + i * sh, w, sh + 1.0), top.lerp(bot, f))

	# Rolling-hill silhouette spanning the full width, filled down to the bottom.
	func hill(base_y: float, amp: float, freq: float, phase: float, col: Color) -> void:
		var v: Vector2 = vp()
		var pts := PackedVector2Array()
		pts.append(Vector2(0, v.y))
		var seg: int = 32
		for i in range(seg + 1):
			var x: float = v.x * float(i) / float(seg)
			var yy: float = base_y + sin(phase + freq * float(i)) * amp
			pts.append(Vector2(x, yy))
		pts.append(Vector2(v.x, v.y))
		draw_colored_polygon(pts, col)

	# A simple cottage: walls, gable roof, optional chimney smoke.
	func cottage(pos: Vector2, s: float, wall: Color, roof: Color, smoke: bool) -> void:
		var w: float = 46.0 * s
		var h: float = 32.0 * s
		draw_rect(Rect2(pos.x - w * 0.5, pos.y - h, w, h), wall)
		var roof_pts := PackedVector2Array([
			Vector2(pos.x - w * 0.62, pos.y - h),
			Vector2(pos.x, pos.y - h - 26.0 * s),
			Vector2(pos.x + w * 0.62, pos.y - h),
		])
		draw_colored_polygon(roof_pts, roof)
		# Door + window.
		draw_rect(Rect2(pos.x - 6.0 * s, pos.y - 16.0 * s, 12.0 * s, 16.0 * s), Color(0.16, 0.10, 0.06))
		draw_rect(Rect2(pos.x + 9.0 * s, pos.y - 24.0 * s, 9.0 * s, 9.0 * s), Color(0.95, 0.82, 0.45, 0.85))
		if smoke:
			var cx: float = pos.x - w * 0.34
			var cy: float = pos.y - h - 18.0 * s
			draw_rect(Rect2(cx - 4.0 * s, pos.y - h - 18.0 * s, 8.0 * s, 18.0 * s), roof.darkened(0.2))
			for i in range(5):
				var ph: float = t * 0.6 + float(i) * 0.9
				var rise: float = fmod(ph, 4.0)
				var puff: Vector2 = Vector2(cx + sin(ph * 1.7) * 9.0 * s, cy - rise * 22.0 * s)
				var a: float = clampf(0.34 - rise * 0.07, 0.0, 0.34)
				draw_circle(puff, (4.0 + rise * 3.0) * s, Color(0.85, 0.85, 0.88, a))

	# A small walking villager. dir = +1 right / -1 left, gait drives leg swing.
	func villager(pos: Vector2, s: float, tunic: Color, gait: float) -> void:
		var skin := Color(0.86, 0.68, 0.52)
		var hip: Vector2 = pos + Vector2(0, -7.0 * s)
		var sh: float = sin(gait) * 4.0 * s
		# Legs.
		draw_line(hip, pos + Vector2(sh, 0), tunic.darkened(0.35), 2.2 * s)
		draw_line(hip, pos + Vector2(-sh, 0), tunic.darkened(0.35), 2.2 * s)
		# Body + head.
		var neck: Vector2 = pos + Vector2(0, -18.0 * s)
		draw_line(hip, neck, tunic, 4.0 * s)
		draw_circle(neck + Vector2(0, -3.0 * s), 3.2 * s, skin)

	# Crenellated wall segment from x0..x1 at given top y.
	func crenellated(x0: float, x1: float, top_y: float, bot_y: float, col: Color, merlon: float) -> void:
		draw_rect(Rect2(x0, top_y, x1 - x0, bot_y - top_y), col)
		var x: float = x0
		while x < x1:
			draw_rect(Rect2(x, top_y - merlon, merlon, merlon), col)
			x += merlon * 2.0


# ── Scene 1: Dawn over the Keep ────────────────────────────────────────────────

class _DawnKeep extends _Scene:
	func _init() -> void:
		caption = "Dawn breaks over the keep"

	func _draw() -> void:
		var v: Vector2 = vp()
		var horizon: float = v.y * 0.66
		# Sunrise sky.
		vgrad(0, 0, v.x, horizon, Color(0.16, 0.17, 0.34), Color(0.97, 0.66, 0.36))
		# Rising sun with breathing glow.
		var sun: Vector2 = Vector2(v.x * 0.5, horizon - 30.0 - sin(t * 0.25) * 10.0)
		for i in range(6):
			var r: float = 60.0 + float(i) * 26.0
			draw_circle(sun, r, Color(1.0, 0.85, 0.5, 0.06))
		draw_circle(sun, 46.0, Color(1.0, 0.92, 0.66, 0.95))
		# Clouds drifting.
		for i in range(5):
			var cx: float = fmod(v.x * (0.1 + float(i) * 0.23) + t * (6.0 + i * 2.0), v.x + 240.0) - 120.0
			var cy: float = horizon * (0.22 + float(i % 3) * 0.13)
			var ca := Color(1.0, 0.86, 0.72, 0.22)
			draw_circle(Vector2(cx, cy), 26.0, ca)
			draw_circle(Vector2(cx + 26, cy + 4), 32.0, ca)
			draw_circle(Vector2(cx + 60, cy), 24.0, ca)
		# Layered hills.
		hill(horizon + 6, 14, 0.5, 0.4, Color(0.30, 0.26, 0.34))
		hill(horizon + 46, 20, 0.35, 2.1, Color(0.20, 0.20, 0.28))
		# Castle silhouette on the central hill.
		_keep(Vector2(v.x * 0.5, horizon + 38), Color(0.10, 0.10, 0.16))
		hill(horizon + 96, 26, 0.28, 4.0, Color(0.11, 0.13, 0.16))
		# God rays fanning down from the rising sun.
		for i in range(7):
			var ra: float = -1.9 + float(i) * 0.18 + sin(t * 0.2) * 0.03
			var far: Vector2 = sun + Vector2(cos(ra), sin(ra)) * (v.y * 1.1)
			draw_line(sun, far, Color(1.0, 0.88, 0.6, 0.05), 26.0)
		# Low rolling mist hugging the hills.
		for i in range(4):
			var mx: float = fmod(t * 8.0 + float(i) * 360.0, v.x + 400.0) - 200.0
			var my: float = horizon + 70.0 + float(i) * 22.0
			draw_circle(Vector2(mx, my), 120.0, Color(0.85, 0.82, 0.86, 0.05))
			draw_circle(Vector2(mx + 140, my + 10), 150.0, Color(0.85, 0.82, 0.86, 0.045))
		# Foreground grass band.
		draw_rect(Rect2(0, horizon + 150, v.x, v.y), Color(0.09, 0.13, 0.10))
		# Birds drifting across.
		for i in range(7):
			var bx: float = fmod(t * 28.0 + float(i) * 190.0, v.x + 200.0) - 100.0
			var by: float = v.y * 0.20 + sin(t * 0.6 + i) * 16.0 + float(i % 3) * 22.0
			var fl: float = sin(t * 4.0 + i) * 4.0
			draw_polyline(PackedVector2Array([
				Vector2(bx - 7, by + fl), Vector2(bx, by), Vector2(bx + 7, by + fl)
			]), Color(0.10, 0.10, 0.14, 0.7), 1.6)

	func _keep(base: Vector2, col: Color) -> void:
		# Central tower + two flanking towers, crenellated.
		crenellated(base.x - 60, base.x - 24, base.y - 64, base.y, col, 8)
		crenellated(base.x + 24, base.x + 60, base.y - 64, base.y, col, 8)
		crenellated(base.x - 26, base.x + 26, base.y - 96, base.y, col, 9)
		# Banner on the keep.
		var pole := Vector2(base.x, base.y - 96)
		draw_line(pole, pole + Vector2(0, -26), col.lightened(0.3), 2.0)
		var wave: float = sin(t * 3.0) * 3.0
		draw_colored_polygon(PackedVector2Array([
			pole + Vector2(0, -26), pole + Vector2(20 + wave, -21), pole + Vector2(0, -16)
		]), Color(0.74, 0.20, 0.18))


# ── Scene 2: The Village Wakes ─────────────────────────────────────────────────

class _VillageWakes extends _Scene:
	func _init() -> void:
		caption = "The village stirs to life"

	func _draw() -> void:
		var v: Vector2 = vp()
		var horizon: float = v.y * 0.52
		vgrad(0, 0, v.x, horizon, Color(0.46, 0.66, 0.85), Color(0.78, 0.86, 0.84))
		draw_circle(Vector2(v.x * 0.8, horizon * 0.4), 38.0, Color(1.0, 0.97, 0.85, 0.9))
		# Rolling green hills.
		hill(horizon + 20, 22, 0.32, 1.0, Color(0.34, 0.50, 0.24))
		hill(horizon + 70, 30, 0.26, 3.2, Color(0.27, 0.43, 0.19))
		hill(horizon + 140, 26, 0.4, 5.5, Color(0.21, 0.36, 0.15))
		# Winding path.
		var path := PackedVector2Array()
		for i in range(33):
			var f: float = float(i) / 32.0
			path.append(Vector2(v.x * (0.12 + f * 0.8) + sin(f * 6.0) * 24.0, horizon + 150 + f * (v.y - horizon - 150)))
		draw_polyline(path, Color(0.62, 0.52, 0.36, 0.8), 14.0)
		# Cottages.
		cottage(Vector2(v.x * 0.22, horizon + 96), 1.1, Color(0.72, 0.62, 0.46), Color(0.46, 0.26, 0.16), true)
		cottage(Vector2(v.x * 0.40, horizon + 110), 1.3, Color(0.76, 0.66, 0.50), Color(0.40, 0.22, 0.14), true)
		cottage(Vector2(v.x * 0.74, horizon + 104), 1.2, Color(0.70, 0.60, 0.45), Color(0.44, 0.25, 0.15), true)
		# Windmill.
		_windmill(Vector2(v.x * 0.88, horizon + 70), 1.1)
		# Campfire.
		_campfire(Vector2(v.x * 0.55, v.y * 0.86))
		# Villagers walking the path.
		for i in range(4):
			var loop: float = fmod(t * 0.10 + float(i) * 0.27, 1.0)
			var px: float = v.x * (0.14 + loop * 0.78) + sin(loop * 6.0) * 24.0
			var py: float = horizon + 150 + loop * (v.y - horizon - 150)
			var tunics := [Color(0.66, 0.28, 0.24), Color(0.30, 0.40, 0.62), Color(0.40, 0.46, 0.26), Color(0.56, 0.46, 0.24)]
			villager(Vector2(px, py), 0.7 + loop * 0.6, tunics[i], t * 5.0 + i)
		# Butterflies fluttering over the meadow.
		var fcols := [Color(0.95, 0.75, 0.25), Color(0.85, 0.45, 0.55), Color(0.55, 0.65, 0.9)]
		for i in range(6):
			var bx: float = fmod(v.x * 0.12 + t * (20.0 + i * 6.0) + i * 230.0, v.x + 120.0) - 60.0
			var by: float = horizon + 70.0 + sin(t * 2.2 + i * 1.7) * 26.0 + float(i % 3) * 30.0
			var flap: float = abs(sin(t * 12.0 + i)) * 4.0 + 1.5
			var bc: Color = fcols[i % 3]
			draw_circle(Vector2(bx - flap, by), 2.6, bc)
			draw_circle(Vector2(bx + flap, by), 2.6, bc)

	func _windmill(base: Vector2, s: float) -> void:
		var top: Vector2 = base + Vector2(0, -70.0 * s)
		draw_colored_polygon(PackedVector2Array([
			base + Vector2(-16 * s, 0), base + Vector2(16 * s, 0),
			top + Vector2(10 * s, 0), top + Vector2(-10 * s, 0)
		]), Color(0.62, 0.54, 0.42))
		draw_colored_polygon(PackedVector2Array([
			top + Vector2(-12 * s, 0), top + Vector2(12 * s, 0), top + Vector2(0, -14 * s)
		]), Color(0.44, 0.26, 0.16))
		# Rotating sails.
		var hub: Vector2 = top + Vector2(0, 2)
		for k in range(4):
			var a: float = t * 0.9 + TAU * float(k) / 4.0
			var tip: Vector2 = hub + Vector2(cos(a), sin(a)) * 38.0 * s
			draw_line(hub, tip, Color(0.30, 0.22, 0.14), 4.0 * s)
			var perp: Vector2 = Vector2(-sin(a), cos(a)) * 7.0 * s
			draw_colored_polygon(PackedVector2Array([hub, tip, tip + perp]), Color(0.86, 0.82, 0.70, 0.85))

	func _campfire(pos: Vector2) -> void:
		# Logs.
		draw_line(pos + Vector2(-10, 2), pos + Vector2(10, -2), Color(0.30, 0.18, 0.10), 4.0)
		draw_line(pos + Vector2(-10, -2), pos + Vector2(10, 2), Color(0.26, 0.15, 0.09), 4.0)
		# Flickering flames.
		for i in range(3):
			var fl: float = 12.0 + sin(t * 9.0 + i * 2.0) * 5.0
			var sway: float = sin(t * 7.0 + i) * 3.0
			draw_colored_polygon(PackedVector2Array([
				pos + Vector2(-6 + i * 6, 0), pos + Vector2(-2 + i * 6 + sway, -fl), pos + Vector2(2 + i * 6, 0)
			]), Color(1.0, 0.55 + i * 0.12, 0.12, 0.9))
		draw_circle(pos + Vector2(0, -22), 26.0, Color(1.0, 0.6, 0.2, 0.10))


# ── Scene 3: Harvest Fields ────────────────────────────────────────────────────

class _HarvestFields extends _Scene:
	func _init() -> void:
		caption = "Golden fields, ripe for harvest"

	func _draw() -> void:
		var v: Vector2 = vp()
		var horizon: float = v.y * 0.46
		vgrad(0, 0, v.x, horizon, Color(0.55, 0.46, 0.62), Color(0.99, 0.76, 0.42))
		var sun: Vector2 = Vector2(v.x * 0.28, horizon * 0.55)
		for i in range(5):
			draw_circle(sun, 50.0 + i * 22.0, Color(1.0, 0.80, 0.45, 0.07))
		draw_circle(sun, 40.0, Color(1.0, 0.90, 0.62, 0.95))
		# Distant tree line.
		hill(horizon + 8, 12, 0.6, 1.5, Color(0.30, 0.28, 0.20))
		# Golden field base.
		draw_rect(Rect2(0, horizon, v.x, v.y - horizon), Color(0.74, 0.58, 0.22))
		draw_rect(Rect2(0, horizon, v.x, v.y - horizon), Color(0.80, 0.62, 0.24, 0.4))
		# Swaying wheat — rows getting taller toward foreground.
		var rows: int = 9
		for r in range(rows):
			var ry: float = horizon + 30 + float(r) / float(rows) * (v.y - horizon - 20)
			var rscale: float = 0.4 + float(r) / float(rows) * 1.4
			var col := Color(0.86, 0.70, 0.28).lerp(Color(0.66, 0.50, 0.16), 1.0 - float(r) / float(rows))
			var step: float = 16.0
			var x: float = 0.0
			while x < v.x:
				var sway: float = sin(t * 1.6 + x * 0.03 + r) * 5.0 * rscale
				var bottom: Vector2 = Vector2(x, ry + 16 * rscale)
				var tip: Vector2 = Vector2(x + sway, ry - 18 * rscale)
				draw_line(bottom, tip, col, 2.0 * rscale)
				draw_circle(tip, 2.4 * rscale, col.lightened(0.2))
				x += step
		# Sun-lit pollen / chaff drifting on the breeze.
		for i in range(40):
			var px: float = fmod(float(i) * 137.0 + t * (12.0 + (i % 5) * 4.0), v.x)
			var py: float = horizon + 40.0 + fmod(float(i) * 53.0 - t * 6.0, v.y - horizon - 40.0)
			var pa: float = 0.18 + 0.14 * sin(t * 2.0 + i)
			draw_circle(Vector2(px, py), 1.6, Color(1.0, 0.94, 0.7, pa))
		# Farmers bent over, working.
		_farmer(Vector2(v.x * 0.46, v.y * 0.66), 1.0)
		_farmer(Vector2(v.x * 0.66, v.y * 0.78), 1.25)
		# A flock crossing the sky.
		for i in range(9):
			var bx: float = fmod(t * 34.0 + float(i) * 70.0, v.x + 160.0) - 80.0
			var by: float = horizon * (0.3 + (i % 4) * 0.08) + sin(t + i) * 6.0
			var fl: float = sin(t * 4.5 + i) * 3.0
			draw_polyline(PackedVector2Array([
				Vector2(bx - 5, by + fl), Vector2(bx, by), Vector2(bx + 5, by + fl)
			]), Color(0.28, 0.20, 0.16, 0.7), 1.4)

	func _farmer(pos: Vector2, s: float) -> void:
		var skin := Color(0.84, 0.66, 0.50)
		var hip: Vector2 = pos + Vector2(0, -8.0 * s)
		var bend: float = sin(t * 2.0) * 3.0 * s
		var head: Vector2 = pos + Vector2(14.0 * s + bend, -16.0 * s)
		draw_line(hip, pos + Vector2(-3 * s, 0), Color(0.32, 0.26, 0.18), 2.4 * s)
		draw_line(hip, pos + Vector2(4 * s, 0), Color(0.32, 0.26, 0.18), 2.4 * s)
		draw_line(hip, head, Color(0.50, 0.40, 0.26), 4.0 * s)
		draw_circle(head, 3.4 * s, skin)
		# Scythe / sickle stroke.
		var tool_end: Vector2 = head + Vector2(16.0 * s, 8.0 * s + bend)
		draw_line(head + Vector2(2, 2), tool_end, Color(0.55, 0.55, 0.58), 1.6 * s)


# ── Scene 4: Siege at Dusk ─────────────────────────────────────────────────────

class _SiegeAtDusk extends _Scene:
	func _init() -> void:
		caption = "The siege rages at dusk"

	func _draw() -> void:
		var v: Vector2 = vp()
		var horizon: float = v.y * 0.6
		vgrad(0, 0, v.x, horizon, Color(0.18, 0.12, 0.22), Color(0.70, 0.34, 0.22))
		# Drifting smoke haze.
		for i in range(5):
			var sx: float = fmod(v.x * 0.2 * i + t * 10.0, v.x + 200.0) - 100.0
			draw_circle(Vector2(sx, horizon * (0.3 + i * 0.1)), 40.0, Color(0.2, 0.16, 0.18, 0.18))
		# Distant ridge.
		hill(horizon + 10, 16, 0.4, 2.0, Color(0.14, 0.10, 0.14))
		draw_rect(Rect2(0, horizon + 60, v.x, v.y), Color(0.10, 0.09, 0.10))
		# Castle wall on the right with towers + torches.
		var wall_top: float = horizon - 30
		var wall_bot: float = horizon + 80
		crenellated(v.x * 0.62, v.x, wall_top, wall_bot, Color(0.16, 0.15, 0.18), 16)
		crenellated(v.x * 0.66, v.x * 0.74, wall_top - 40, wall_bot, Color(0.13, 0.12, 0.15), 14)
		crenellated(v.x * 0.90, v.x * 0.98, wall_top - 40, wall_bot, Color(0.13, 0.12, 0.15), 14)
		for tx in [v.x * 0.70, v.x * 0.82, v.x * 0.94]:
			var fl: float = 6.0 + sin(t * 11.0 + tx) * 3.0
			draw_circle(Vector2(tx, wall_top - 6), fl, Color(1.0, 0.6, 0.2, 0.85))
			draw_circle(Vector2(tx, wall_top - 6), fl * 2.4, Color(1.0, 0.5, 0.15, 0.12))
		# Catapult on the left that periodically fires a flaming projectile.
		var cat: Vector2 = Vector2(v.x * 0.16, wall_bot - 6)
		var cycle: float = fmod(t, 4.0)
		var arm_a: float = lerp(-2.4, -0.5, clampf(cycle / 0.5, 0.0, 1.0)) if cycle < 0.5 else lerp(-0.5, -2.4, clampf((cycle - 0.5) / 1.2, 0.0, 1.0))
		draw_rect(Rect2(cat.x - 22, cat.y - 6, 44, 14), Color(0.26, 0.18, 0.10))
		draw_line(cat + Vector2(-14, 0), cat + Vector2(14, -2), Color(0.20, 0.14, 0.08), 5.0)
		var pivot: Vector2 = cat + Vector2(0, -10)
		var arm_tip: Vector2 = pivot + Vector2(cos(arm_a), sin(arm_a)) * 40.0
		draw_line(pivot, arm_tip, Color(0.36, 0.26, 0.14), 5.0)
		# Flaming projectile arcs after launch.
		if cycle > 0.5:
			var p: float = clampf((cycle - 0.5) / 3.0, 0.0, 1.0)
			var start: Vector2 = Vector2(v.x * 0.18, wall_bot - 50)
			var endp: Vector2 = Vector2(v.x * 0.72, wall_top + 30)
			var proj: Vector2 = start.lerp(endp, p) + Vector2(0, -sin(p * PI) * 180.0)
			for k in range(5):
				var tp: float = clampf(p - float(k) * 0.04, 0.0, 1.0)
				var tr: Vector2 = start.lerp(endp, tp) + Vector2(0, -sin(tp * PI) * 180.0)
				draw_circle(tr, 7.0 - k, Color(1.0, 0.6 - k * 0.08, 0.1, 0.7 - k * 0.12))
			draw_circle(proj, 8.0, Color(1.0, 0.85, 0.4, 0.95))
		# Marching banner army across the foreground.
		for i in range(10):
			var mx: float = fmod(t * 16.0 + float(i) * 96.0, v.x * 0.6 + 120.0) - 60.0
			var my: float = v.y * 0.9 + (i % 2) * 14.0
			villager(Vector2(mx, my), 0.85, Color(0.22, 0.24, 0.30), t * 6.0 + i)
			# Spear + pennant.
			draw_line(Vector2(mx + 6, my), Vector2(mx + 6, my - 34), Color(0.30, 0.22, 0.14), 1.8)
			var wave: float = sin(t * 4.0 + i) * 2.0
			draw_colored_polygon(PackedVector2Array([
				Vector2(mx + 6, my - 34), Vector2(mx + 18 + wave, my - 30), Vector2(mx + 6, my - 26)
			]), Color(0.66, 0.18, 0.16))
		# Embers rising from the burning walls.
		for i in range(50):
			var seed_x: float = fmod(float(i) * 71.0, v.x * 0.4) + v.x * 0.6
			var rise: float = fmod(t * (24.0 + (i % 7) * 6.0) + float(i) * 37.0, v.y * 0.8)
			var ex: float = seed_x + sin(t * 2.0 + i) * 14.0
			var ey: float = wall_bot - rise
			var ea: float = clampf(0.7 - rise / (v.y * 0.8), 0.0, 0.7)
			draw_circle(Vector2(ex, ey), 1.8, Color(1.0, 0.55 + (i % 3) * 0.12, 0.12, ea))


# ── Scene 5: Market Day ────────────────────────────────────────────────────────

class _MarketDay extends _Scene:
	func _init() -> void:
		caption = "Market day in the square"

	func _draw() -> void:
		var v: Vector2 = vp()
		var horizon: float = v.y * 0.42
		vgrad(0, 0, v.x, horizon, Color(0.50, 0.68, 0.88), Color(0.86, 0.90, 0.86))
		draw_circle(Vector2(v.x * 0.18, horizon * 0.4), 34.0, Color(1.0, 0.97, 0.85, 0.9))
		# Town backdrop: a row of timbered houses behind the square.
		for i in range(7):
			var hx: float = v.x * (0.06 + i * 0.14)
			cottage(Vector2(hx, horizon + 60.0), 1.0 + float(i % 2) * 0.25,
				Color(0.74, 0.64, 0.48), Color(0.42, 0.24, 0.15), i % 2 == 0)
		# Cobbled ground.
		draw_rect(Rect2(0, horizon + 40.0, v.x, v.y), Color(0.46, 0.42, 0.38))
		draw_rect(Rect2(0, horizon + 40.0, v.x, v.y), Color(0.30, 0.27, 0.24, 0.25))
		# Bunting strung across the square, gently swaying.
		var bcols := [Color(0.70, 0.22, 0.20), Color(0.90, 0.74, 0.30), Color(0.28, 0.42, 0.62), Color(0.34, 0.52, 0.30)]
		var by0: float = horizon + 30.0
		var prev := Vector2(0, by0)
		for i in range(17):
			var fx: float = v.x * float(i) / 16.0
			var droop: float = sin(float(i) * 0.8) * 0.0 + 18.0
			var fy: float = by0 + sin(float(i) * 0.9) * 6.0 + droop * sin(PI * float(i % 4) / 4.0)
			var cur := Vector2(fx, fy)
			if i > 0:
				draw_line(prev, cur, Color(0.25, 0.20, 0.14), 1.5)
				var flag_wave: float = sin(t * 3.0 + i) * 3.0
				draw_colored_polygon(PackedVector2Array([
					prev, cur, (prev + cur) * 0.5 + Vector2(flag_wave, 16.0)
				]), bcols[i % 4])
			prev = cur
		# Market stalls with striped awnings.
		for i in range(4):
			_stall(Vector2(v.x * (0.16 + i * 0.22), horizon + 120.0), bcols[i % 4])
		# A well in the centre.
		var well := Vector2(v.x * 0.5, v.y * 0.82)
		draw_rect(Rect2(well.x - 22, well.y - 16, 44, 24), Color(0.45, 0.42, 0.40))
		draw_rect(Rect2(well.x - 22, well.y - 16, 44, 6), Color(0.30, 0.28, 0.26))
		draw_line(well + Vector2(-18, -16), well + Vector2(-18, -54), Color(0.30, 0.22, 0.14), 3.0)
		draw_line(well + Vector2(18, -16), well + Vector2(18, -54), Color(0.30, 0.22, 0.14), 3.0)
		draw_line(well + Vector2(-22, -54), well + Vector2(22, -54), Color(0.34, 0.26, 0.16), 3.0)
		# A milling crowd of townsfolk.
		var crowd := [Color(0.66, 0.28, 0.24), Color(0.30, 0.40, 0.62), Color(0.40, 0.46, 0.26),
			Color(0.56, 0.46, 0.24), Color(0.52, 0.30, 0.50), Color(0.24, 0.46, 0.46)]
		for i in range(9):
			var phase: float = t * 0.3 + float(i) * 1.4
			var cx: float = v.x * (0.12 + 0.76 * (0.5 + 0.5 * sin(phase * 0.7 + i)))
			var cy: float = v.y * (0.74 + 0.18 * (0.5 + 0.5 * sin(phase + i * 2.0)))
			villager(Vector2(cx, cy), 0.85 + (cy / v.y - 0.7) * 0.8, crowd[i % 6], t * 4.0 + i * 1.3)
		# Pigeons pecking near the well.
		for i in range(5):
			var gx: float = well.x + sin(t * 0.5 + i * 2.0) * (40.0 + i * 8.0)
			var gy: float = well.y + 18.0 + (i % 2) * 6.0
			var peck: float = abs(sin(t * 3.0 + i)) * 2.0
			draw_circle(Vector2(gx, gy - peck), 2.6, Color(0.55, 0.55, 0.6))

	func _stall(pos: Vector2, awning: Color) -> void:
		var w: float = 64.0
		var h: float = 34.0
		# Counter.
		draw_rect(Rect2(pos.x - w * 0.5, pos.y - h, w, h), Color(0.50, 0.36, 0.22))
		draw_rect(Rect2(pos.x - w * 0.5, pos.y - h, w, 6.0), Color(0.38, 0.27, 0.16))
		# Posts.
		draw_line(Vector2(pos.x - w * 0.5, pos.y - h), Vector2(pos.x - w * 0.5, pos.y - h - 40.0), Color(0.34, 0.24, 0.14), 3.0)
		draw_line(Vector2(pos.x + w * 0.5, pos.y - h), Vector2(pos.x + w * 0.5, pos.y - h - 40.0), Color(0.34, 0.24, 0.14), 3.0)
		# Striped awning.
		var ax: float = pos.x - w * 0.56
		var ay: float = pos.y - h - 40.0
		var stripes: int = 6
		for s in range(stripes):
			var sw: float = (w * 1.12) / float(stripes)
			var col: Color = awning if s % 2 == 0 else Color(0.92, 0.88, 0.78)
			draw_colored_polygon(PackedVector2Array([
				Vector2(ax + s * sw, ay), Vector2(ax + (s + 1) * sw, ay),
				Vector2(ax + (s + 1) * sw, ay + 12.0), Vector2(ax + s * sw, ay + 12.0),
			]), col)
		# Goods on the counter (crates / produce).
		for k in range(3):
			draw_circle(Vector2(pos.x - 18.0 + k * 18.0, pos.y - h - 4.0), 4.0, Color(0.80, 0.30, 0.20))


# ── Scene 6: Night Festival ────────────────────────────────────────────────────

class _NightFestival extends _Scene:
	func _init() -> void:
		caption = "A festival of lanterns by night"

	func _draw() -> void:
		var v: Vector2 = vp()
		var horizon: float = v.y * 0.64
		vgrad(0, 0, v.x, horizon, Color(0.04, 0.04, 0.12), Color(0.20, 0.12, 0.26))
		# Stars.
		for i in range(70):
			var sx: float = fmod(float(i) * 97.0, v.x)
			var sy: float = fmod(float(i) * 53.0, horizon)
			var tw: float = 0.4 + 0.6 * abs(sin(t * 2.0 + i))
			draw_circle(Vector2(sx, sy), 1.2, Color(1.0, 1.0, 0.9, 0.5 * tw))
		# Big moon with halo.
		var moon := Vector2(v.x * 0.78, horizon * 0.34)
		for i in range(4):
			draw_circle(moon, 44.0 + i * 22.0, Color(0.85, 0.88, 1.0, 0.05))
		draw_circle(moon, 40.0, Color(0.94, 0.95, 0.86))
		draw_circle(moon + Vector2(-12, -6), 7.0, Color(0.86, 0.88, 0.80, 0.6))
		draw_circle(moon + Vector2(10, 8), 5.0, Color(0.86, 0.88, 0.80, 0.5))
		# Fireworks bursting on a cycle.
		_firework(Vector2(v.x * 0.30, horizon * 0.42), fmod(t, 3.0) / 3.0, Color(1.0, 0.6, 0.3))
		_firework(Vector2(v.x * 0.58, horizon * 0.30), fmod(t + 1.5, 3.0) / 3.0, Color(0.5, 0.8, 1.0))
		# Medieval village skyline: peaked-roof cottages, a church, and a keep.
		var sky_glow := Color(0.55, 0.35, 0.18, 0.20)
		draw_rect(Rect2(0, horizon - 30.0, v.x, 60.0), sky_glow)
		hill(horizon + 6, 14, 0.4, 1.0, Color(0.08, 0.07, 0.12))
		var sil := Color(0.09, 0.08, 0.13)
		var base_y: float = horizon + 30.0
		var lit := Color(1.0, 0.78, 0.36, 0.85)
		# Row of cottages with steep gable roofs.
		var hx: float = -10.0
		var idx: int = 0
		while hx < v.x:
			var hw: float = 40.0 + float(idx % 3) * 14.0
			var hh: float = 26.0 + float(idx % 4) * 8.0
			# Leave gaps where the church + keep landmarks stand.
			if not ((hx > v.x * 0.10 and hx < v.x * 0.26) or (hx > v.x * 0.74 and hx < v.x * 0.92)):
				draw_rect(Rect2(hx, base_y - hh, hw, hh), sil)
				draw_colored_polygon(PackedVector2Array([
					Vector2(hx - 4.0, base_y - hh),
					Vector2(hx + hw + 4.0, base_y - hh),
					Vector2(hx + hw * 0.5, base_y - hh - 18.0),
				]), sil.darkened(0.25))
				if idx % 2 == 0:
					draw_rect(Rect2(hx + hw * 0.5 - 4.0, base_y - hh * 0.55, 8.0, 9.0), lit)
			hx += hw + 12.0
			idx += 1
		# Church with steep roof, bell-tower steeple and a tall lit window.
		var cxch: float = v.x * 0.17
		draw_rect(Rect2(cxch - 26.0, base_y - 54.0, 52.0, 54.0), sil)
		draw_colored_polygon(PackedVector2Array([
			Vector2(cxch - 30.0, base_y - 54.0), Vector2(cxch + 30.0, base_y - 54.0),
			Vector2(cxch, base_y - 78.0),
		]), sil.darkened(0.25))
		# Steeple tower.
		draw_rect(Rect2(cxch - 10.0, base_y - 96.0, 20.0, 96.0), sil)
		draw_colored_polygon(PackedVector2Array([
			Vector2(cxch - 12.0, base_y - 96.0), Vector2(cxch + 12.0, base_y - 96.0),
			Vector2(cxch, base_y - 124.0),
		]), sil.darkened(0.3))
		draw_line(Vector2(cxch, base_y - 124.0), Vector2(cxch, base_y - 136.0), sil.lightened(0.3), 2.0)
		draw_line(Vector2(cxch - 5.0, base_y - 131.0), Vector2(cxch + 5.0, base_y - 131.0), sil.lightened(0.3), 2.0)
		draw_rect(Rect2(cxch - 4.0, base_y - 42.0, 8.0, 18.0), lit)         # arched window glow
		draw_rect(Rect2(cxch - 3.0, base_y - 84.0, 6.0, 8.0), lit)         # belfry glow
		# Castle keep — crenellated towers on the right of the square.
		var kx: float = v.x * 0.83
		crenellated(kx - 36.0, kx - 12.0, base_y - 70.0, base_y, sil, 8.0)
		crenellated(kx + 12.0, kx + 36.0, base_y - 70.0, base_y, sil, 8.0)
		crenellated(kx - 14.0, kx + 14.0, base_y - 96.0, base_y, sil.darkened(0.1), 9.0)
		draw_rect(Rect2(kx - 4.0, base_y - 30.0, 8.0, 10.0), lit)
		# Banner atop the keep.
		var pole := Vector2(kx, base_y - 96.0)
		draw_line(pole, pole + Vector2(0, -22.0), sil.lightened(0.4), 2.0)
		var wave: float = sin(t * 3.0) * 3.0
		draw_colored_polygon(PackedVector2Array([
			pole + Vector2(0, -22.0), pole + Vector2(16.0 + wave, -18.0), pole + Vector2(0, -14.0),
		]), Color(0.62, 0.20, 0.18))
		# Ground + reflected glow.
		draw_rect(Rect2(0, horizon + 30.0, v.x, v.y), Color(0.06, 0.05, 0.09))
		# Bonfire in the square.
		_bonfire(Vector2(v.x * 0.5, v.y * 0.9))
		# Floating paper lanterns rising and swaying.
		for i in range(14):
			var rise: float = fmod(t * (10.0 + (i % 5) * 4.0) + float(i) * 60.0, v.y + 80.0)
			var lx: float = v.x * (0.06 + 0.9 * fmod(float(i) * 0.137 + 0.05, 1.0)) + sin(t * 0.8 + i) * 18.0
			var ly: float = v.y - rise
			var lc := Color(1.0, 0.66, 0.30, clampf(0.85 - rise / (v.y + 80.0) * 0.5, 0.2, 0.85))
			draw_circle(Vector2(lx, ly), 14.0, Color(1.0, 0.6, 0.25, 0.12))
			draw_rect(Rect2(lx - 5.0, ly - 7.0, 10.0, 13.0), lc)
			draw_circle(Vector2(lx, ly), 3.0, Color(1.0, 0.95, 0.7, 0.9))

	func _firework(center: Vector2, p: float, col: Color) -> void:
		if p < 0.05:
			return
		var n: int = 16
		var rad: float = p * 110.0
		var fade: float = clampf(1.0 - p, 0.0, 1.0)
		for k in range(n):
			var a: float = TAU * float(k) / float(n)
			var tip: Vector2 = center + Vector2(cos(a), sin(a)) * rad
			draw_circle(tip, 2.6 * fade + 0.6, Color(col.r, col.g, col.b, fade))
			draw_line(center.lerp(tip, 0.6), tip, Color(col.r, col.g, col.b, fade * 0.5), 1.4)

	func _bonfire(pos: Vector2) -> void:
		draw_circle(pos + Vector2(0, -30), 44.0, Color(1.0, 0.6, 0.2, 0.10))
		draw_line(pos + Vector2(-16, 4), pos + Vector2(16, -4), Color(0.30, 0.18, 0.10), 6.0)
		draw_line(pos + Vector2(-16, -4), pos + Vector2(16, 4), Color(0.26, 0.15, 0.09), 6.0)
		for i in range(5):
			var fl: float = 22.0 + sin(t * 9.0 + i * 2.0) * 9.0
			var sway: float = sin(t * 6.0 + i) * 5.0
			draw_colored_polygon(PackedVector2Array([
				pos + Vector2(-10 + i * 5, 0), pos + Vector2(-4 + i * 5 + sway, -fl), pos + Vector2(2 + i * 5, 0)
			]), Color(1.0, 0.5 + i * 0.1, 0.12, 0.9))


# ── Persistent overlay: vignette + parchment frame ────────────────────────────

class _Overlay extends Node2D:
	func _process(_delta: float) -> void:
		queue_redraw()

	func _draw() -> void:
		var v: Vector2 = get_viewport_rect().size
		if v == Vector2.ZERO: v = Vector2(1280, 720)
		# Soft edge vignette.
		var band: float = 70.0
		draw_rect(Rect2(0, 0, v.x, band), Color(0, 0, 0, 0.45))
		draw_rect(Rect2(0, v.y - band, v.x, band), Color(0, 0, 0, 0.5))
		draw_rect(Rect2(0, 0, band, v.y), Color(0, 0, 0, 0.4))
		draw_rect(Rect2(v.x - band, 0, band, v.y), Color(0, 0, 0, 0.4))
		# Parchment frame.
		var inset: float = 16.0
		draw_polyline(PackedVector2Array([
			Vector2(inset, inset), Vector2(v.x - inset, inset),
			Vector2(v.x - inset, v.y - inset), Vector2(inset, v.y - inset),
			Vector2(inset, inset),
		]), Color(0.62, 0.50, 0.24, 0.45), 1.5)
		for corn in [Vector2(inset, inset), Vector2(v.x - inset, inset),
				Vector2(v.x - inset, v.y - inset), Vector2(inset, v.y - inset)]:
			draw_circle(corn, 4.0, Color(0.62, 0.50, 0.24, 0.6))
		# Storybook caption for whichever vignette is most visible, fading with it.
		var bg = get_parent()
		if bg != null and "_scenes" in bg:
			var best = null
			var best_a: float = 0.0
			for sc in bg._scenes:
				if sc.visible and sc.modulate.a > best_a:
					best_a = sc.modulate.a
					best = sc
			if best != null and best.caption != "":
				var font: Font = ThemeDB.fallback_font
				var fs: int = 20
				var cy: float = v.y - 44.0
				var a: float = best_a * 0.92
				draw_string(font, Vector2(2, cy + 2), best.caption,
					HORIZONTAL_ALIGNMENT_CENTER, v.x, fs, Color(0, 0, 0, a * 0.6))
				draw_string(font, Vector2(0, cy), best.caption,
					HORIZONTAL_ALIGNMENT_CENTER, v.x, fs, Color(0.93, 0.86, 0.64, a))
