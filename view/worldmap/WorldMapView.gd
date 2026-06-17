extends Control
# Renders the strategic world map via _draw().
# Accepts WorldMapController render lists; emits city_clicked(city_id).

signal city_clicked(city_id: int)
signal city_hovered(city_id: int)   # -1 when the cursor leaves all cities
signal city_selected(city_id: int)  # right-click: select for orders (no scene change)
signal army_inspected(info: Dictionary)  # left-click a marching host (off-city): inspect it

const WorldMapController = preload("res://view/worldmap/WorldMapController.gd")
const WorldMapData       = preload("res://simulation/world/WorldMapData.gd")

var _data: Dictionary = {}
var _hovered_city_id: int = -1
var _selected_city_id: int = -1   # right-click-selected city (drawn with a selection ring)

# Mark a city as selected (or -1 to clear) and redraw the selection ring.
func set_selected_city(city_id: int) -> void:
	if city_id != _selected_city_id:
		_selected_city_id = city_id
		queue_redraw()

# Cached render lists rebuilt on apply_data
var _city_list:    Array = []
var _road_list:    Array = []
var _faction_list: Array = []
var _deposit_list: Array = []
var _army_list:    Array = []
var _battle_list:  Array = []
var _legend:       Array = []
var _army_frac:    float = 0.4   # sub-hop march progress, driven each frame by the scene
var _current_day:  int = 0       # campaign day, for fading battle markers

func apply_data(world_map_data: Dictionary) -> void:
	_data         = world_map_data
	_road_list    = WorldMapController.get_road_render_list(_data)
	_faction_list = WorldMapController.get_faction_territory_list(_data)
	_deposit_list = WorldMapController.get_resource_deposit_list(_data)
	mouse_filter  = Control.MOUSE_FILTER_STOP
	refresh()

# Re-read the dynamic strategic state (ownership, garrisons, armies, legend). Cheap
# enough to call every strategic day so campaigns are seen unfolding live.
func refresh() -> void:
	if _data.is_empty():
		return
	_city_list   = WorldMapController.get_city_render_list(_data)
	_army_list   = WorldMapController.get_army_render_list(_data, _army_frac)
	_battle_list = WorldMapController.get_battle_render_list(_data, _current_day)
	_legend      = WorldMapController.get_kingdom_legend(_data)
	queue_redraw()

# The current campaign day, so battle markers fade with age. Set by the scene before refresh.
func set_current_day(d: int) -> void:
	_current_day = d

# Animate marching armies between cities (called every frame while the campaign runs).
# Cheap: only re-positions the army markers, leaves the static lists alone.
func set_army_frac(f: float) -> void:
	if _data.is_empty():
		return
	_army_frac = f
	_army_list = WorldMapController.get_army_render_list(_data, _army_frac)
	queue_redraw()

func _draw() -> void:
	if _data.is_empty():
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.13, 0.19, 0.10))
		return
	_draw_background()
	_draw_faction_territories()
	_draw_roads()
	_draw_resource_deposits()
	_draw_battles()
	_draw_cities()
	_draw_armies()
	_draw_legend()

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT:
		var city_id: int = WorldMapController.find_city_near(_data, event.position, 24.0)
		if city_id >= 0:
			city_clicked.emit(city_id)
		else:
			# No city under the cursor — see if the player clicked a marching host.
			var army: Dictionary = WorldMapController.find_army_near(_data, event.position, 16.0, _army_frac)
			if not army.is_empty():
				army_inspected.emit(army)
	elif event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_RIGHT:
		# Right-click selects a city for strategic orders (no scene change).
		var sel: int = WorldMapController.find_city_near(_data, event.position, 24.0)
		if sel >= 0:
			city_selected.emit(sel)
	elif event is InputEventMouseMotion:
		var hov: int = WorldMapController.find_city_near(_data, event.position, 24.0)
		if hov != _hovered_city_id:
			_hovered_city_id = hov
			city_hovered.emit(hov)
			queue_redraw()
		# No city under the cursor → if a marching host is, read it into the panel too
		# (hover-to-inspect, the lighter sibling of click-to-inspect).
		if hov < 0:
			var army: Dictionary = WorldMapController.find_army_near(_data, event.position, 16.0, _army_frac)
			if not army.is_empty():
				army_inspected.emit(army)

# ── Background (procedural biome continent) ────────────────────────────────────

const _SEA_DEEP: Color = Color(0.13, 0.27, 0.45)
const _SEA_SHALLOW: Color = Color(0.20, 0.45, 0.60)   # lighter shelf hugging the coast

const _SNOW: Color = Color(0.87, 0.89, 0.93)   # snow-dusted high peaks

# Overhaul iter3: a more distinct, vibrant palette so biomes read apart (plains/forest were both
# a samey green) — bright meadow plains, deep forest, golden dry hills, slate mountains.
func _biome_color(b: int) -> Color:
	match b:
		WorldMapData.B_SEA:      return _SEA_DEEP
		WorldMapData.B_COAST:    return Color(0.81, 0.74, 0.49)   # sandy shore
		WorldMapData.B_PLAINS:   return Color(0.56, 0.69, 0.33)   # bright meadow green
		WorldMapData.B_FOREST:   return Color(0.19, 0.41, 0.22)   # deep forest green (clearly darker)
		WorldMapData.B_HILLS:    return Color(0.65, 0.57, 0.32)   # golden dry hills (reads as elevation)
		WorldMapData.B_MOUNTAIN: return Color(0.47, 0.44, 0.46)   # slate rock
		WorldMapData.B_RIVER:    return Color(0.26, 0.50, 0.77)
	return _SEA_DEEP

func _draw_background() -> void:
	# Ocean fills the whole panel; the continent sits in the 0..MAP_WIDTH×MAP_HEIGHT
	# region (the same coordinate space the cities are placed in).
	draw_rect(Rect2(Vector2.ZERO, size), _SEA_DEEP)
	var biome: Dictionary = _data.get("biome", {})
	if biome.is_empty():
		return
	var cols: int = biome["cols"]
	var rows: int = biome["rows"]
	var cw: float = biome["cell_w"]
	var ch: float = biome["cell_h"]
	var tiles: PackedByteArray = biome["tiles"]
	# Slight overlap (+1px) avoids hairline seams between cells. A subtle deterministic
	# per-tile shade (hash of gx,gy) breaks the flat single-colour blocks so the land reads
	# textured/undulating rather than a chunky grid (overhaul iter1).
	for gy in range(rows):
		for gx in range(cols):
			var b: int = tiles[gy * cols + gx]
			if b == WorldMapData.B_SEA:
				# Shallow-water shelf (overhaul iter2): a sea cell touching land gets a lighter
				# band, so the continent reads with a shoreline/depth instead of land slamming
				# straight into deep ocean.
				var coastal: bool = false
				for d in [[1, 0], [-1, 0], [0, 1], [0, -1], [1, 1], [1, -1], [-1, 1], [-1, -1]]:
					var nx: int = gx + d[0]
					var ny: int = gy + d[1]
					if nx >= 0 and ny >= 0 and nx < cols and ny < rows and tiles[ny * cols + nx] != WorldMapData.B_SEA:
						coastal = true
						break
				if coastal:
					draw_rect(Rect2(gx * cw, gy * ch, cw + 1.0, ch + 1.0), _SEA_SHALLOW)
				continue   # else: deep-ocean base already filled
			var c: Color = _biome_color(b)
			var h: int = ((gx * 73856093) ^ (gy * 19349663)) & 1023
			var shade: float = 1.0 + (float(h) / 1023.0 - 0.5) * 0.16   # ±8% brightness
			# Snow-dusted peaks: the brightest-shaded mountain tiles cap with snow (variety).
			if b == WorldMapData.B_MOUNTAIN and shade > 1.05:
				c = _SNOW
			else:
				c = Color(clampf(c.r * shade, 0.0, 1.0), clampf(c.g * shade, 0.0, 1.0), clampf(c.b * shade, 0.0, 1.0))
			draw_rect(Rect2(gx * cw, gy * ch, cw + 1.0, ch + 1.0), c)

# ── Faction territories (tint the land each kingdom holds) ─────────────────────

func _draw_faction_territories() -> void:
	var biome: Dictionary = _data.get("biome", {})
	if not biome.is_empty() and biome.has("territory"):
		var cols: int = biome["cols"]
		var rows: int = biome["rows"]
		var cw: float = biome["cell_w"]
		var ch: float = biome["cell_h"]
		var terr: PackedByteArray = biome["territory"]
		# Overhaul iter1: render territory as crisp BORDERS — a strong colour band where a
		# kingdom meets a different owner (or the wilds), with only a faint interior wash.
		# The old uniform 0.22 fill over every owned cell muddied the whole map.
		for gy in range(rows):
			for gx in range(cols):
				var owner: int = terr[gy * cols + gx]
				if owner == 0:
					continue   # neutral / sea / mountain
				var is_border: bool = false
				for d in [[1, 0], [-1, 0], [0, 1], [0, -1]]:
					var nx: int = gx + d[0]
					var ny: int = gy + d[1]
					if nx < 0 or ny < 0 or nx >= cols or ny >= rows or terr[ny * cols + nx] != owner:
						is_border = true
						break
				var col: Color = _faction_color(owner - 1)
				col.a = 0.50 if is_border else 0.08
				draw_rect(Rect2(gx * cw, gy * ch, cw + 1.0, ch + 1.0), col)
	# Faction name labels near each capital.
	for f in _faction_list:
		draw_string(ThemeDB.fallback_font, f["center_pos"] + Vector2(-40, -f["radius"] * 0.0 - 24),
			f.get("name", ""), HORIZONTAL_ALIGNMENT_LEFT, -1, 11,
			Color.from_string(f["color_hex"], Color.GRAY).lightened(0.35))

func _faction_color(faction_id: int) -> Color:
	if faction_id >= 0 and faction_id < WorldMapData.FACTION_COLORS.size():
		return Color.from_string(WorldMapData.FACTION_COLORS[faction_id], Color.GRAY)
	return Color.GRAY

# ── Roads ─────────────────────────────────────────────────────────────────────

const ROAD_COLOR: Color = Color(0.55, 0.40, 0.25, 0.70)

func _draw_roads() -> void:
	for r in _road_list:
		var fp: Vector2 = r["from_pos"]
		var tp: Vector2 = r["to_pos"]
		# Slight curve via perpendicular midpoint offset
		var mid: Vector2 = (fp + tp) * 0.5
		var perp: Vector2 = (tp - fp).orthogonal().normalized() * 14.0
		mid += perp
		draw_polyline(PackedVector2Array([fp, mid, tp]), ROAD_COLOR, 1.5)

# ── Resource deposits ─────────────────────────────────────────────────────────

func _draw_resource_deposits() -> void:
	for d in _deposit_list:
		var p: Vector2  = d["pos"]
		var t: String   = d["type"]
		match t:
			"wood":  _draw_wood_icon(p)
			"stone": _draw_stone_icon(p)
			"iron":  _draw_iron_icon(p)
			"food":  _draw_food_icon(p)

func _draw_wood_icon(p: Vector2) -> void:
	# Crossed axe — two diagonal lines
	var col := Color(0.40, 0.26, 0.12)
	draw_line(p + Vector2(-5, -5), p + Vector2(5, 5),  col, 2.0)
	draw_line(p + Vector2(5,  -5), p + Vector2(-5, 5), col, 2.0)
	# Small circle handle
	draw_circle(p, 2.5, col)

func _draw_stone_icon(p: Vector2) -> void:
	# Stack of 3 small quads (stone pile)
	var col := Color(0.55, 0.55, 0.55)
	draw_rect(Rect2(p.x - 5, p.y + 1,  10, 4), col)
	draw_rect(Rect2(p.x - 4, p.y - 3,   8, 4), col.lightened(0.1))
	draw_rect(Rect2(p.x - 3, p.y - 7,   6, 4), col.lightened(0.2))

func _draw_iron_icon(p: Vector2) -> void:
	# Crossed pickaxes
	var col := Color(0.50, 0.50, 0.58)
	draw_line(p + Vector2(-6, -3), p + Vector2(6,  3), col, 2.5)
	draw_line(p + Vector2(-6,  3), p + Vector2(6, -3), col, 2.5)
	draw_circle(p, 2.0, col)

func _draw_food_icon(p: Vector2) -> void:
	# Wheat sheaf: vertical stem + 5 radiating arcs
	var col := Color(0.72, 0.58, 0.18)
	draw_line(p + Vector2(0, 6), p + Vector2(0, -6), col, 1.5)
	for i in range(5):
		var a: float = (-PI * 0.3) + float(i) * (PI * 0.6 / 4.0)
		draw_line(p, p + Vector2(sin(a) * 6, -cos(a) * 6 - 2), col, 1.5)

# ── Cities ────────────────────────────────────────────────────────────────────

func _draw_cities() -> void:
	for c in _city_list:
		var p:    Vector2 = c["pos"]
		var col:  Color   = Color.from_string(c["faction_color"], Color.GRAY)
		var tier: int     = c.get("tier", 0)
		var is_player_owned: bool = c.get("is_player_owned", false)
		var is_start: bool = c.get("is_player_start", false)
		var is_hovered: bool = c.get("id", -1) == _hovered_city_id

		# Player-owned cities get a gold ring so the realm reads at a glance.
		if is_player_owned:
			draw_arc(p, 20.0, 0, TAU, 24, Color(0.95, 0.78, 0.10, 0.85), 3.0)

		# Hover highlight
		if is_hovered:
			draw_arc(p, 18.0, 0, TAU, 24, Color.WHITE.darkened(0.1), 2.0)

		# Selection ring — the city the player has right-clicked for orders.
		if c.get("id", -1) == _selected_city_id:
			draw_arc(p, 24.0, 0, TAU, 28, Color(0.30, 0.90, 1.0, 0.95), 3.0)
			draw_arc(p, 27.0, 0, TAU, 28, Color(0.30, 0.90, 1.0, 0.35), 1.5)

		_draw_castle_icon(p, col, tier, is_player_owned)

		# Development pips (filled = developed) beneath the castle.
		_draw_development_pips(p, c.get("development", 0), col)

		# City name
		var name_col: Color = Color(0.15, 0.10, 0.05) if not is_player_owned else Color(0.60, 0.45, 0.10)
		var label: String = c.get("name", "")
		if is_start:
			label += " ★"
		draw_string(ThemeDB.fallback_font, p + Vector2(-30, 20), label,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 9, name_col)

		# Garrison strength on every city (the defenders that campaigns fight).
		var ginfo: String = "⚔ %d" % c.get("garrison", 0)
		draw_string(ThemeDB.fallback_font, p + Vector2(-30, 30), ginfo,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(0.30, 0.22, 0.12, 0.85))

func _draw_development_pips(p: Vector2, development: int, col: Color) -> void:
	var n: int = clampi(development, 0, 10)
	var shown: int = mini(n, 5)  # cap the row; 1 pip per 2 dev beyond 5
	var step: float = 4.0
	var total_w: float = float(shown) * step
	var x0: float = p.x - total_w * 0.5
	for i in range(shown):
		var lit: bool = true
		var pc: Color = col.lightened(0.2) if lit else Color(0.4, 0.4, 0.4, 0.5)
		draw_rect(Rect2(x0 + i * step, p.y + 7.0, 2.5, 2.5), pc)

# ── Recently-contested cities (fading battle markers) ───────────────────────────
# A clash of crossed swords inside an expanding ring marks where the war was just
# fought; both fade as the battle recedes into the past. Captures flare red, repelled
# assaults a steely white-blue. So the strategic map tells the story of the war.
func _draw_battles() -> void:
	for b in _battle_list:
		var p: Vector2 = b.get("pos", Vector2.ZERO)
		var fade: float = clampf(b.get("fade_frac", 0.0), 0.0, 1.0)
		var a: float = 1.0 - fade                       # fresh = opaque, stale = faint
		var captured: bool = b.get("captured", false)
		var col: Color = Color(0.95, 0.30, 0.20, a) if captured else Color(0.80, 0.88, 1.0, a)
		# Expanding shock ring (grows as it fades).
		var ring_r: float = 12.0 + fade * 12.0
		draw_arc(p, ring_r, 0, TAU, 28, Color(col.r, col.g, col.b, a * 0.5), 2.0)
		# Crossed swords (two short blades) at the city.
		var s: float = 7.0
		draw_line(p + Vector2(-s, -s), p + Vector2(s, s), col, 2.0)
		draw_line(p + Vector2(s, -s), p + Vector2(-s, s), col, 2.0)

# ── Armies on the march ─────────────────────────────────────────────────────────

func _draw_armies() -> void:
	for a in _army_list:
		var p: Vector2 = a["pos"]
		var col: Color = Color.from_string(a["color_hex"], Color.GRAY)
		# March line to the target.
		if a.get("moving", false):
			var to: Vector2 = a["to"]
			draw_line(p, to, Color(col.r, col.g, col.b, 0.55), 1.5)
			var dir: Vector2 = (to - p)
			if dir.length() > 1.0:
				dir = dir.normalized()
				var perp: Vector2 = dir.orthogonal() * 4.0
				var tip: Vector2 = p.lerp(to, 0.55)
				draw_colored_polygon(PackedVector2Array([
					tip + dir * 6.0, tip - dir * 2.0 + perp, tip - dir * 2.0 - perp,
				]), Color(col.r, col.g, col.b, 0.8))
		_draw_army_marker(p, col, int(a.get("size_band", 0)), int(a.get("size", 0)))
		# Your own marching hosts get a glanceable destination + ETA tag, so you can
		# read where your troops are bound without clicking (few of them, no clutter).
		if a.get("is_player", false) and a.get("moving", false):
			var dest: String = String(a.get("dest_name", ""))
			if dest != "":
				var eta: int = int(a.get("eta_days", 0))
				var tag: String = "→ %s (%dd)" % [dest, eta]
				var tp := p + Vector2(6, 10)
				draw_string(ThemeDB.fallback_font, tp + Vector2(1, 1), tag,
					HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.04, 0.06, 0.03, 0.9))
				draw_string(ThemeDB.fallback_font, tp, tag,
					HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.70, 0.96, 0.62))

# A heraldic banner whose size and number of pennants grow with the host's strength,
# so a lone raiding party and a great army read differently at a glance.
# Band 0:1-10, 1:11-30, 2:31-60, 3:61-100, 4:100+.
func _draw_army_marker(p: Vector2, col: Color, band: int, size_count: int) -> void:
	var pole_h: float = 12.0 + float(band) * 4.0
	var flag_w: float = 8.0 + float(band) * 2.0
	var flag_h: float = 5.0 + float(band) * 1.2
	var pennants: int = band + 1                 # 1..5 flags by band
	var top := p + Vector2(0, -pole_h)
	# Shadow + pole.
	draw_line(p + Vector2(1, 1), top + Vector2(1, 1), Color(0, 0, 0, 0.35), 1.6)
	draw_line(p, top, Color(0.22, 0.16, 0.10), 1.6)
	# Stacked pennants flying from the pole.
	for i in range(pennants):
		var fy: float = top.y + float(i) * (flag_h + 1.5)
		var base := Vector2(top.x, fy)
		draw_colored_polygon(PackedVector2Array([
			base, base + Vector2(flag_w, flag_h * 0.5), base + Vector2(0, flag_h),
		]), col)
		draw_polyline(PackedVector2Array([
			base, base + Vector2(flag_w, flag_h * 0.5), base + Vector2(0, flag_h),
		]), col.darkened(0.45), 1.0)
	# Foot disc + troop count.
	draw_circle(p, 3.0 + float(band) * 0.6, Color(0.10, 0.08, 0.06, 0.9))
	draw_circle(p, 2.0 + float(band) * 0.6, col)
	var label := Vector2(top.x + flag_w + 2.0, top.y - 1.0)
	draw_string(ThemeDB.fallback_font, label + Vector2(1, 1), str(size_count),
		HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.05, 0.04, 0.03, 0.9))
	draw_string(ThemeDB.fallback_font, label, str(size_count),
		HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.98, 0.96, 0.90))

# ── Kingdom legend ──────────────────────────────────────────────────────────────

func _draw_legend() -> void:
	if _legend.is_empty():
		return
	var pad: float = 8.0
	var row_h: float = 18.0
	var panel_w: float = 196.0
	var panel_h: float = pad * 2.0 + float(_legend.size()) * row_h + 18.0
	var origin := Vector2(size.x - panel_w - 10.0, 46.0)
	draw_rect(Rect2(origin, Vector2(panel_w, panel_h)), Color(0.08, 0.10, 0.07, 0.86))
	draw_rect(Rect2(origin, Vector2(panel_w, panel_h)), Color(0.55, 0.45, 0.20, 0.7), false, 1.0)
	draw_string(ThemeDB.fallback_font, origin + Vector2(pad, 14.0), "Kingdoms",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.91, 0.76, 0.26))
	var y: float = origin.y + 20.0 + pad
	for k in _legend:
		var col: Color = Color.from_string(k["color_hex"], Color.GRAY)
		var alive: bool = k.get("is_alive", true)
		# Colour swatch.
		draw_rect(Rect2(origin.x + pad, y - 8.0, 10.0, 10.0), col if alive else col.darkened(0.5))
		var nm: String = k.get("name", "")
		if k.get("is_player", false):
			nm += " (You)"
		var txt_col: Color = Color(0.88, 0.82, 0.64) if alive else Color(0.5, 0.45, 0.4)
		var line: String = nm if alive else nm + " ✝"
		draw_string(ThemeDB.fallback_font, Vector2(origin.x + pad + 16.0, y + 2.0), line,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 10, txt_col)
		var stats: String = "%d⌂ %d⚔" % [k.get("city_count", 0), k.get("army_size", 0)]
		draw_string(ThemeDB.fallback_font, Vector2(origin.x + panel_w - 56.0, y + 2.0), stats,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 9, txt_col)
		y += row_h

func _draw_castle_icon(p: Vector2, faction_col: Color, tier: int, is_player: bool) -> void:
	var scale: float = 8.0 + tier * 4.0  # tier 0=8, 1=12, 2=16, 3=20
	var body_col: Color = faction_col if not is_player else Color(0.91, 0.76, 0.26)
	var dark_col: Color = body_col.darkened(0.35)

	# Keep body (rectangle)
	var bw: float = scale * 1.4
	var bh: float = scale * 1.2
	draw_rect(Rect2(p.x - bw * 0.5, p.y - bh, bw, bh), body_col)
	draw_rect(Rect2(p.x - bw * 0.5, p.y - bh, bw, bh), dark_col, false, 1.0)

	# Two flanking towers
	var tw: float = scale * 0.7
	var th: float = scale * 1.5
	for side in [-1, 1]:
		var tx: float = p.x + side * (bw * 0.5 + tw * 0.3) - tw * 0.5
		draw_rect(Rect2(tx, p.y - th, tw, th), body_col)
		draw_rect(Rect2(tx, p.y - th, tw, th), dark_col, false, 0.8)
		# Battlements (3 merlons)
		var mw: float = tw / 3.5
		for m in range(3):
			var mx: float = tx + float(m) * (tw / 3.0) + mw * 0.15
			draw_rect(Rect2(mx, p.y - th - scale * 0.35, mw, scale * 0.35),
				body_col.lightened(0.15))

	# Gate arch (darker circle bottom of keep body)
	draw_arc(p + Vector2(0, -scale * 0.4), scale * 0.35,
		PI, TAU, 8, dark_col.darkened(0.3), 2.0)

	# Flag on tallest tower
	var flag_x: float = p.x + bw * 0.5 + tw * 0.35
	var flag_top: Vector2 = Vector2(flag_x, p.y - th - scale * 0.8)
	draw_line(Vector2(flag_x, p.y - th), flag_top, dark_col, 1.5)
	draw_colored_polygon(PackedVector2Array([
		flag_top,
		flag_top + Vector2(scale * 0.7, scale * 0.25),
		flag_top + Vector2(0, scale * 0.5),
	]), body_col.lightened(0.2))
