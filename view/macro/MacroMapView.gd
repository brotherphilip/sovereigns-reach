extends Control
# Macro kingdom view — draws shires, army banners, AI siege tents.
# Toggled visible via Tab key or HUD button. Rendered as a full-screen overlay.

const MacroViewController = preload("res://view/macro/MacroViewController.gd")

const SHIRE_ALPHA: float = 0.55
const MAP_MARGIN: int = 40

var _map_w: int = 200
var _map_h: int = 200
var _panel_size: Vector2 = Vector2.ZERO

func _ready() -> void:
	var gs: Vector2i = GameState.get_grid_size()
	_map_w = gs.x
	_map_h = gs.y
	mouse_filter = Control.MOUSE_FILTER_PASS
	EventBus.simulation_tick.connect(_on_tick)
	set_process_input(true)

func _on_tick(_t: int) -> void:
	queue_redraw()

func _draw() -> void:
	_panel_size = size
	if _panel_size == Vector2.ZERO:
		_panel_size = get_viewport_rect().size

	var bg := Rect2(Vector2.ZERO, _panel_size)
	draw_rect(bg, Color(0.08, 0.10, 0.12, 0.92))

	_draw_shires()
	_draw_player_banners()
	_draw_ai_banners()
	_draw_siege_tents()
	_draw_legend()

func _map_to_screen(gx: int, gy: int) -> Vector2:
	var mx: float = MAP_MARGIN + float(gx) / float(_map_w) * (_panel_size.x - MAP_MARGIN * 2)
	var my: float = MAP_MARGIN + float(gy) / float(_map_h) * (_panel_size.y - MAP_MARGIN * 2)
	return Vector2(mx, my)

func _draw_shires() -> void:
	var shires: Array = MacroViewController.get_shire_render_list(
		GameState.world, GameState.players, GameState.ai_factions)
	for shire in shires:
		var cx: int    = shire.get("capital_x", 0)
		var cy: int    = shire.get("capital_y", 0)
		var sp: Vector2 = _map_to_screen(cx, cy)
		var col: Color  = Color.from_string(shire.get("color", "#888888"), Color.GRAY)
		col.a = SHIRE_ALPHA
		draw_circle(sp, 30.0, col)
		draw_string(ThemeDB.fallback_font, sp + Vector2(-20, 5),
			shire.get("name", ""), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color.WHITE)

func _draw_player_banners() -> void:
	var banners: Array = MacroViewController.get_player_army_banners(GameState.players)
	for banner in banners:
		var sp: Vector2 = _map_to_screen(banner.get("pos_x", 0), banner.get("pos_y", 0))
		var col: Color  = Color.from_string(banner.get("color", "#88ff88"), Color.GREEN)
		_draw_banner(sp, col, "P%d (%d)" % [banner.get("player_id", 0), banner.get("unit_count", 0)])

func _draw_ai_banners() -> void:
	var banners: Array = MacroViewController.get_ai_army_banners(GameState.ai_factions)
	for banner in banners:
		var sp: Vector2 = _map_to_screen(banner.get("pos_x", 0), banner.get("pos_y", 0))
		var col: Color  = Color.from_string(banner.get("color", "#ff4444"), Color.RED)
		_draw_banner(sp, col, "%s (%d)" % [banner.get("archetype", "?").left(6), banner.get("unit_count", 0)])

func _draw_banner(sp: Vector2, col: Color, label: String) -> void:
	# Draw a flag pole + flag
	draw_line(sp, sp + Vector2(0, -24), col.darkened(0.3), 2.0)
	var flag := PackedVector2Array([sp + Vector2(0, -24), sp + Vector2(16, -18), sp + Vector2(0, -12)])
	draw_colored_polygon(flag, col)
	draw_string(ThemeDB.fallback_font, sp + Vector2(-15, 8), label,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color.WHITE)

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

func _draw_legend() -> void:
	var y: float = _panel_size.y - 30
	draw_string(ThemeDB.fallback_font, Vector2(MAP_MARGIN, y),
		"[TAB] Close Macro View | Circles = AI Capitals | Flags = Armies | Orange = Siege",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color.GRAY)
