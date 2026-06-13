extends Control
# Macro kingdom view — draws shires, army banners, AI siege tents.
# Toggled visible via Tab key or HUD button. Rendered as a full-screen overlay.

const MacroViewController = preload("res://view/macro/MacroViewController.gd")

const SHIRE_ALPHA: float = 0.55
const MAP_MARGIN: int = 40

var _map_w: int = 200
var _map_h: int = 200
var _panel_size: Vector2 = Vector2.ZERO
var _shire_flashes: Array = []  # [{shire_id, start_ms, new_owner}]

func _ready() -> void:
	var gs: Vector2i = GameState.get_grid_size()
	_map_w = gs.x
	_map_h = gs.y
	mouse_filter = Control.MOUSE_FILTER_PASS
	EventBus.simulation_tick.connect(_on_tick)
	EventBus.shire_ownership_changed.connect(_on_shire_ownership_changed)
	set_process_input(true)

func _on_shire_ownership_changed(shire_id: int, _old_owner: int, _new_owner: int) -> void:
	_shire_flashes.append({"shire_id": shire_id, "start_ms": Time.get_ticks_msec(), "new_owner": _new_owner})

func _on_tick(_t: int) -> void:
	queue_redraw()

func _process(_delta: float) -> void:
	if not visible:
		return
	if not _shire_flashes.is_empty():
		queue_redraw()
		return
	for f in GameState.ai_factions:
		if f is Dictionary and f.get("threat_level", 0.0) > 60.0:
			queue_redraw()
			return

func _draw() -> void:
	_panel_size = size
	if _panel_size == Vector2.ZERO:
		_panel_size = get_viewport_rect().size

	var bg := Rect2(Vector2.ZERO, _panel_size)
	draw_rect(bg, Color(0.08, 0.10, 0.12, 0.92))

	_draw_shires()
	_draw_army_routes()
	_draw_player_banners()
	_draw_ai_banners()
	_draw_siege_tents()
	_draw_player_summary()
	_draw_legend()

func _map_to_screen(gx: int, gy: int) -> Vector2:
	var mx: float = MAP_MARGIN + float(gx) / float(_map_w) * (_panel_size.x - MAP_MARGIN * 2)
	var my: float = MAP_MARGIN + float(gy) / float(_map_h) * (_panel_size.y - MAP_MARGIN * 2)
	return Vector2(mx, my)

func _draw_shires() -> void:
	var shires: Array = MacroViewController.get_shire_render_list(
		GameState.world, GameState.players, GameState.ai_factions)
	var now_ms: int = Time.get_ticks_msec()
	var active_flashes: Array = []
	for fl in _shire_flashes:
		if now_ms - fl["start_ms"] < 1200:
			active_flashes.append(fl)
	_shire_flashes = active_flashes
	for shire in shires:
		var cx: int    = shire.get("capital_x", 0)
		var cy: int    = shire.get("capital_y", 0)
		var sp: Vector2 = _map_to_screen(cx, cy)
		var col: Color  = Color.from_string(shire.get("color", "#888888"), Color.GRAY)
		col.a = SHIRE_ALPHA
		draw_circle(sp, 30.0, col)
		for fl in active_flashes:
			if fl["shire_id"] == shire.get("id", -1):
				var age: float = float(now_ms - fl["start_ms"]) / 1200.0
				draw_arc(sp, 34.0, 0.0, TAU, 32, Color(1.0, 1.0, 1.0, 1.0 - age), 3.0)
		draw_string(ThemeDB.fallback_font, sp + Vector2(-20, 5),
			shire.get("name", ""), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color.WHITE)

func _draw_player_banners() -> void:
	var fog_active: bool = GameState.weather.get("effects", {}).get("fog_army_ui", false)
	if fog_active:
		return
	var banners: Array = MacroViewController.get_player_army_banners(GameState.players)
	for banner in banners:
		var sp: Vector2 = _map_to_screen(banner.get("pos_x", 0), banner.get("pos_y", 0))
		var col: Color  = Color.from_string(banner.get("color", "#88ff88"), Color.GREEN)
		_draw_banner(sp, col, "P%d (%d)" % [banner.get("player_id", 0), banner.get("unit_count", 0)])

func _draw_ai_banners() -> void:
	var fog_active: bool = GameState.weather.get("effects", {}).get("fog_army_ui", false)
	var banners: Array = MacroViewController.get_ai_army_banners(GameState.ai_factions)
	var t: float = Time.get_ticks_msec() * 0.001
	for banner in banners:
		var sp: Vector2 = _map_to_screen(banner.get("pos_x", 0), banner.get("pos_y", 0))
		var col: Color  = Color.from_string(banner.get("color", "#ff4444"), Color.RED)
		if fog_active:
			# Fog of war: draw a faint question mark instead of full banner + count
			draw_circle(sp, 8.0, Color(0.5, 0.5, 0.6, 0.35))
			draw_string(ThemeDB.fallback_font, sp + Vector2(-4, 5), "?",
				HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.8, 0.8, 0.9, 0.6))
			continue
		var threat: float = banner.get("threat_level", 0.0)
		if threat > 60.0:
			var pulse: float = 0.55 + 0.45 * sin(t * 3.0)
			draw_circle(sp, 14.0, Color(1.0, 0.1, 0.1, 0.25 * pulse))
			draw_arc(sp, 14.0, 0.0, TAU, 24, Color(1.0, 0.15, 0.15, 0.75 * pulse), 2.0)
		_draw_banner(sp, col, "%s (%d)" % [banner.get("archetype", "?").left(6), banner.get("unit_count", 0)])

func _draw_banner(sp: Vector2, col: Color, label: String) -> void:
	# Draw a flag pole + flag
	draw_line(sp, sp + Vector2(0, -24), col.darkened(0.3), 2.0)
	var flag := PackedVector2Array([sp + Vector2(0, -24), sp + Vector2(16, -18), sp + Vector2(0, -12)])
	draw_colored_polygon(flag, col)
	draw_string(ThemeDB.fallback_font, sp + Vector2(-15, 8), label,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color.WHITE)

func _draw_army_routes() -> void:
	var tents: Array = MacroViewController.get_siege_tent_data(GameState.ai_factions)
	for tent in tents:
		var origin: Vector2 = _map_to_screen(tent.get("capital_x", 0), tent.get("capital_y", 0))
		var dest: Vector2   = _map_to_screen(tent.get("target_x", 0), tent.get("target_y", 0))
		var prog: float     = tent.get("progress", 0.0)
		var route_col := Color(1.0, 0.40, 0.10, 0.65)
		draw_dashed_line(origin, dest, route_col, 2.0, 12.0)
		# Arrowhead at destination end
		var dir: Vector2 = (dest - origin).normalized()
		var perp: Vector2 = Vector2(-dir.y, dir.x) * 7.0
		var tip: Vector2  = dest - dir * 14.0
		draw_colored_polygon(PackedVector2Array([dest, tip + perp, tip - perp]), route_col)
		# Progress marker: circle along the line showing assembly progress
		var marker: Vector2 = origin.lerp(dest, prog)
		draw_circle(marker, 5.0, Color(1.0, 0.75, 0.10, 0.85))

func _draw_siege_tents() -> void:
	var tents: Array = MacroViewController.get_siege_tent_data(GameState.ai_factions)
	for tent in tents:
		var sp: Vector2 = _map_to_screen(tent.get("target_x", 0), tent.get("target_y", 0))
		draw_circle(sp, 12.0, Color(0.9, 0.6, 0.1, 0.8))
		# Progress arc
		var prog: float = tent.get("progress", 0.0)
		draw_arc(sp, 12.0, -PI * 0.5, -PI * 0.5 + TAU * prog, 20, Color.RED, 3.0)
		draw_string(ThemeDB.fallback_font, sp + Vector2(14, 4),
			tent.get("eta_label", ""), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color.YELLOW)

func _draw_player_summary() -> void:
	if GameState.players.is_empty():
		return
	var p: Dictionary = GameState.players[0]
	var shire_count: int = p.get("shire_ids", []).size()
	var alive_units: int = 0
	for u in p.get("units", []):
		if u is Dictionary and u.get("is_alive", true):
			alive_units += 1
	var gold: int = int(p.get("gold", 0))
	var summary: String = "Your realm:  Shires: %d  |  Army: %d  |  Gold: %d" % [shire_count, alive_units, gold]
	var bar_h: float = 22.0
	draw_rect(Rect2(0, 0, _panel_size.x, bar_h), Color(0.05, 0.08, 0.04, 0.80))
	draw_string(ThemeDB.fallback_font, Vector2(MAP_MARGIN, 14), summary,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.91, 0.76, 0.26))

func _draw_legend() -> void:
	var y: float = _panel_size.y - 30
	draw_string(ThemeDB.fallback_font, Vector2(MAP_MARGIN, y),
		"[TAB] Close  |  Circles = AI Capitals  |  Flags = Armies  |  Orange = Siege route (● = progress)  |  Red pulse = Hostile (threat >60)",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color.GRAY)
	# Faction legend top-right
	_draw_faction_legend()

func _draw_faction_legend() -> void:
	const ARCH_DISPLAY: Dictionary = {
		"bandit_king":    "Bandit King",
		"merchant_prince":"Merchant Prince",
		"ironhand":       "The Ironhand",
		"ashen_barony":   "Ashen Barony",
	}
	var x: float = _panel_size.x - 180
	var y: float = MAP_MARGIN
	draw_rect(Rect2(x - 8, y - 4, 172, 16 + GameState.ai_factions.size() * 18), Color(0.0, 0.0, 0.0, 0.5))
	draw_string(ThemeDB.fallback_font, Vector2(x, y), "AI Factions",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color.LIGHT_GRAY)
	y += 16
	for f in GameState.ai_factions:
		if not (f is Dictionary and f.get("is_alive", false)):
			continue
		var col: Color = Color.from_string(
			MacroViewController.get_ai_army_banners([f])[0].get("color", "#ff4444") if not MacroViewController.get_ai_army_banners([f]).is_empty() else "#ff4444",
			Color.RED)
		var arch: String = f.get("archetype", "?")
		var display: String = ARCH_DISPLAY.get(arch, arch)
		var threat: float = f.get("threat_level", 0.0)
		draw_circle(Vector2(x + 5, y + 4), 5.0, col)
		draw_string(ThemeDB.fallback_font, Vector2(x + 14, y + 8),
			"%s  T:%.0f" % [display, threat], HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color.WHITE)
		y += 18
