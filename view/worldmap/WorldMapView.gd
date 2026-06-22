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

# ── Zoom & pan (overhaul iter7) ───────────────────────────────────────────────
# The map layers draw under a zoom/pan transform; the legend stays in screen space.
# Mouse-wheel zooms toward the cursor; middle-drag pans. Starts zoomed IN, not the
# whole-continent fit, so cities/armies read large by default.
const ZOOM_MIN: float = 1.0
const ZOOM_MAX: float = 4.0
const ZOOM_DEFAULT: float = 1.7
var _zoom: float = ZOOM_DEFAULT
var _pan: Vector2 = Vector2.ZERO
var _view_inited: bool = false
var _panning: bool = false

# Clamp the pan so the map always covers the panel (no voids off the edges).
func _clamp_pan() -> void:
	var minx: float = minf(0.0, size.x - size.x * _zoom)
	var miny: float = minf(0.0, size.y - size.y * _zoom)
	_pan.x = clampf(_pan.x, minx, 0.0)
	_pan.y = clampf(_pan.y, miny, 0.0)

# Centre the starting view on the PLAYER'S OWN holding (so a new player isn't dropped into
# a sea of rival nodes with no idea which is theirs), once size + the city list are known.
func _ensure_view_inited() -> void:
	if _view_inited or size.x <= 0.0:
		return
	var focus: Vector2 = _player_focus_point()
	if focus == Vector2.INF and _city_list.is_empty():
		return  # wait for the city list so we can frame the player's seat, not the map centre
	_view_inited = true
	if focus != Vector2.INF:
		_pan = size * 0.5 - focus * _zoom
	else:
		_pan = size * 0.5 * (1.0 - _zoom)
	_clamp_pan()

# Map (world) position of the player's own city — their start, else any held city.
func _player_focus_point() -> Vector2:
	var fallback: Vector2 = Vector2.INF
	for c in _city_list:
		if c.get("is_player_start", false):
			return c.get("pos", Vector2.INF)
		if c.get("is_player_owned", false) and fallback == Vector2.INF:
			fallback = c.get("pos", Vector2.INF)
	return fallback

# Screen point -> map (world) coordinates, inverting the zoom/pan transform.
func _to_world(p: Vector2) -> Vector2:
	return (p - _pan) / _zoom

# Re-zoom keeping the world point under `focus` (screen) fixed (zoom toward cursor).
func _apply_zoom(new_zoom: float, focus: Vector2) -> void:
	new_zoom = clampf(new_zoom, ZOOM_MIN, ZOOM_MAX)
	if is_equal_approx(new_zoom, _zoom):
		return
	var world: Vector2 = _to_world(focus)
	_zoom = new_zoom
	_pan = focus - world * _zoom
	_clamp_pan()
	queue_redraw()

func apply_data(world_map_data: Dictionary) -> void:
	_data         = world_map_data
	_road_list    = WorldMapController.get_road_render_list(_data)
	_faction_list = WorldMapController.get_faction_territory_list(_data)
	_deposit_list = WorldMapController.get_resource_deposit_list(_data)
	mouse_filter  = Control.MOUSE_FILTER_STOP
	# Linear filtering smooths the baked relief raster when it is scaled up by zoom.
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_build_relief_texture()
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
	_ensure_view_inited()
	# Styled off-map background fills the WHOLE panel in SCREEN space so no zoom/pan ever
	# reveals a raw-black void: a soft vertical sea/fog gradient (deep below, hazier above),
	# the calm "open water / unknown sea" framing a cartographic map sits in.
	_draw_offmap_backdrop()
	# Map layers render under the zoom/pan transform.
	draw_set_transform(_pan, 0.0, Vector2(_zoom, _zoom))
	_draw_background()
	_draw_faction_territories()
	_draw_roads()
	_draw_resource_deposits()
	_draw_battles()
	_draw_cities()
	_draw_armies()
	# Reset to screen space for the fixed UI overlay (Kingdoms legend + zoom indicator).
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# Fade the map edge into the surrounding sea/fog so the relief raster has no hard aliased
	# seam where it ends — drawn over the map but under the UI chrome.
	_draw_map_edge_fade()
	# Atmospheric edge framing — drawn over the map but UNDER the UI panels so the realm
	# reads as a crafted cartographic artifact with depth, not a flat data grid (iter314).
	_draw_vignette()
	_draw_legend()
	_draw_zoom_indicator()

# Styled off-map backdrop (screen space): a calm vertical sea/fog gradient covering the whole
# panel, so panning/zooming the relief raster can NEVER expose a raw-black void. Top reads as a
# hazy horizon fog, the body as open deep water — the empty sea a cartographic map floats in.
const _OFFMAP_TOP: Color = Color(0.16, 0.22, 0.30)   # hazy sea-horizon fog
const _OFFMAP_BOT: Color = Color(0.09, 0.16, 0.26)   # deep open water
func _draw_offmap_backdrop() -> void:
	var w: float = size.x
	var h: float = size.y
	if w <= 0.0 or h <= 0.0:
		return
	draw_polygon(
		PackedVector2Array([Vector2(0, 0), Vector2(w, 0), Vector2(w, h), Vector2(0, h)]),
		PackedColorArray([_OFFMAP_TOP, _OFFMAP_TOP, _OFFMAP_BOT, _OFFMAP_BOT]))

# Fade the relief raster's rectangular edge into the surrounding sea/fog, so the map has no hard
# aliased seam where the texture stops. Four screen-space gradient bands, hugging the on-screen
# position of the map's outer edge (mapped through the zoom/pan transform), opaque-fog at the rim
# of the map fading to clear just inside it.
func _draw_map_edge_fade() -> void:
	var w: float = size.x
	var h: float = size.y
	if w <= 0.0 or h <= 0.0:
		return
	# Map rectangle corners in screen space.
	var tl: Vector2 = Vector2.ZERO * _zoom + _pan
	var br: Vector2 = _map_size * _zoom + _pan
	var fog := Color(_OFFMAP_BOT.r, _OFFMAP_BOT.g, _OFFMAP_BOT.b, 0.85)
	var clear := Color(_OFFMAP_BOT.r, _OFFMAP_BOT.g, _OFFMAP_BOT.b, 0.0)
	var band: float = 26.0   # how far the fog reaches inward from the map edge (screen px)
	# Top edge of the map.
	draw_polygon(PackedVector2Array([
		Vector2(tl.x, tl.y), Vector2(br.x, tl.y), Vector2(br.x, tl.y + band), Vector2(tl.x, tl.y + band)]),
		PackedColorArray([fog, fog, clear, clear]))
	# Bottom edge.
	draw_polygon(PackedVector2Array([
		Vector2(tl.x, br.y - band), Vector2(br.x, br.y - band), Vector2(br.x, br.y), Vector2(tl.x, br.y)]),
		PackedColorArray([clear, clear, fog, fog]))
	# Left edge.
	draw_polygon(PackedVector2Array([
		Vector2(tl.x, tl.y), Vector2(tl.x + band, tl.y), Vector2(tl.x + band, br.y), Vector2(tl.x, br.y)]),
		PackedColorArray([fog, clear, clear, fog]))
	# Right edge.
	draw_polygon(PackedVector2Array([
		Vector2(br.x - band, tl.y), Vector2(br.x, tl.y), Vector2(br.x, br.y), Vector2(br.x - band, br.y)]),
		PackedColorArray([clear, fog, fog, clear]))

# Soft edge-darkening that frames the map and gives the flat hex grid a sense of depth.
# Four gradient bands (opaque at the rim, transparent inward); corners double up = darkest,
# which is exactly the falloff a vignette wants. Cheap: 4 colored quads, screen space.
func _draw_vignette() -> void:
	var w: float = size.x
	var h: float = size.y
	if w <= 0.0 or h <= 0.0:
		return
	var band: float = minf(w, h) * 0.22      # how far inward the darkening reaches
	var edge := Color(0.02, 0.03, 0.015, 0.40)
	var clear := Color(0.02, 0.03, 0.015, 0.0)
	# Top
	draw_polygon(PackedVector2Array([Vector2(0, 0), Vector2(w, 0), Vector2(w, band), Vector2(0, band)]),
		PackedColorArray([edge, edge, clear, clear]))
	# Bottom
	draw_polygon(PackedVector2Array([Vector2(0, h - band), Vector2(w, h - band), Vector2(w, h), Vector2(0, h)]),
		PackedColorArray([clear, clear, edge, edge]))
	# Left
	draw_polygon(PackedVector2Array([Vector2(0, 0), Vector2(band, 0), Vector2(band, h), Vector2(0, h)]),
		PackedColorArray([edge, clear, clear, edge]))
	# Right
	draw_polygon(PackedVector2Array([Vector2(w - band, 0), Vector2(w, 0), Vector2(w, h), Vector2(w - band, h)]),
		PackedColorArray([clear, edge, edge, clear]))

# Small screen-space readout of the current zoom + the controls (so the iter7 zoom/pan is
# discoverable). Bottom-left of the map, outlined for legibility (overhaul iter10).
func _draw_zoom_indicator() -> void:
	var txt: String = "⊕ %.1f×   ·   wheel: zoom   ·   middle-drag: pan" % _zoom
	var pos: Vector2 = Vector2(12.0, 40.0)   # top-left, below the scene title bar (clear of UI)
	draw_string(ThemeDB.fallback_font, pos + Vector2(1, 1), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0, 0, 0, 0.8))
	draw_string(ThemeDB.fallback_font, pos, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.93, 0.88, 0.70))

func _input(event: InputEvent) -> void:
	# Hit-testing happens in MAP (world) space — invert the zoom/pan transform. The pick radius
	# is divided by zoom so the on-screen grab distance stays constant as you zoom.
	if event is InputEventMouseButton and event.pressed:
		match event.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				_apply_zoom(_zoom * 1.15, event.position)
				return
			MOUSE_BUTTON_WHEEL_DOWN:
				_apply_zoom(_zoom / 1.15, event.position)
				return
			MOUSE_BUTTON_MIDDLE:
				_panning = true
				return
			MOUSE_BUTTON_LEFT:
				var wp: Vector2 = _to_world(event.position)
				var city_id: int = WorldMapController.find_city_near(_data, wp, 24.0 / _zoom)
				if city_id >= 0:
					city_clicked.emit(city_id)
				else:
					var army: Dictionary = WorldMapController.find_army_near(_data, wp, 16.0 / _zoom, _army_frac)
					if not army.is_empty():
						army_inspected.emit(army)
			MOUSE_BUTTON_RIGHT:
				var sel: int = WorldMapController.find_city_near(_data, _to_world(event.position), 24.0 / _zoom)
				if sel >= 0:
					city_selected.emit(sel)
	elif event is InputEventMouseButton and not event.pressed and event.button_index == MOUSE_BUTTON_MIDDLE:
		_panning = false
	elif event is InputEventMouseMotion:
		if _panning:
			_pan += event.relative
			_clamp_pan()
			queue_redraw()
			return
		var wp: Vector2 = _to_world(event.position)
		var hov: int = WorldMapController.find_city_near(_data, wp, 24.0 / _zoom)
		if hov != _hovered_city_id:
			_hovered_city_id = hov
			city_hovered.emit(hov)
			queue_redraw()
		if hov < 0:
			var army: Dictionary = WorldMapController.find_army_near(_data, wp, 16.0 / _zoom, _army_frac)
			if not army.is_empty():
				army_inspected.emit(army)

# ── Background (procedural biome continent) ────────────────────────────────────

const _SEA_DEEP: Color = Color(0.13, 0.27, 0.45)
const _SEA_SHALLOW: Color = Color(0.20, 0.45, 0.60)   # lighter shelf hugging the coast

const _SNOW: Color = Color(0.87, 0.89, 0.93)   # snow-dusted high peaks

# Overhaul iter315 (user steer "make it much more realistic"): muted, natural earth tones in place
# of the bright board-game palette — grassland olive, deep muted forest, tan hills, grey-brown rock.
# The elevation read the old saturated colours faked is now supplied properly by hillshading below.
func _biome_color(b: int) -> Color:
	match b:
		WorldMapData.B_SEA:      return _SEA_DEEP
		WorldMapData.B_COAST:    return Color(0.74, 0.69, 0.52)   # muted sand
		WorldMapData.B_PLAINS:   return Color(0.50, 0.55, 0.34)   # grassland olive
		WorldMapData.B_FOREST:   return Color(0.26, 0.38, 0.24)   # muted forest (lifted off black)
		WorldMapData.B_HILLS:    return Color(0.55, 0.50, 0.35)   # tan / khaki hills
		WorldMapData.B_MOUNTAIN: return Color(0.53, 0.50, 0.47)   # grey-brown rock
		WorldMapData.B_RIVER:    return Color(0.27, 0.43, 0.57)
	return _SEA_DEEP

# Per-biome pseudo-elevation (0 sea … 1 peak). FALLBACK ONLY — used when an older save lacks
# the generator's continuous `elev` field. Land biomes sit above _SEA_LEVEL so coasts stay dry.
func _biome_elev(b: int) -> float:
	match b:
		WorldMapData.B_SEA:      return 0.0
		WorldMapData.B_RIVER:    return 0.40
		WorldMapData.B_COAST:    return 0.36
		WorldMapData.B_PLAINS:   return 0.48
		WorldMapData.B_FOREST:   return 0.54
		WorldMapData.B_HILLS:    return 0.78
		WorldMapData.B_MOUNTAIN: return 0.98
	return 0.0

# ── Relief raster (baked hillshaded terrain) ───────────────────────────────────
# iter315 realism overhaul: instead of a board-game hex grid with cartoon tree/rock glyphs,
# the continent is baked ONCE into a continuous relief image — muted earth tones, NW-light
# hillshading from the real elevation field, smooth biome blending, depth-shaded ocean and
# snow peaks. Drawn as a single texture, so it reads like an aerial/relief map, not a board.
const RELIEF_W: int = 800
const RELIEF_H: int = 450
const _SEA_LEVEL: float = 0.32
# NW sun (light from the upper-left), pre-normalised; _FLAT_DOT is N·L over flat ground.
const _L: Vector3 = Vector3(-0.530, -0.530, 0.662)
const _FLAT_DOT: float = 0.662
const _Z_EXAG: float = 6.0       # gentle vertical exaggeration — soft landform relief, not busy
const _SHORE_WET: Color = Color(0.60, 0.55, 0.43)   # wet sand at the waterline
# iter318: the realistic relief read as a "distracting image" the cities/roads were dumped onto.
# Compress every land colour toward this cohesive base so the terrain becomes a calm, designed
# backdrop (the network reads as the structure) instead of a high-contrast biome patchwork.
const _LAND_BASE: Color = Color(0.45, 0.46, 0.35)
# How far each biome tone is pulled toward _LAND_BASE. Lowered from 0.38 to 0.22 so forests/plains/
# hills keep a distinct, legible identity while the terrain still reads as a calm designed backdrop.
const _LAND_UNIFY: float = 0.22

var _relief_tex: ImageTexture = null
var _map_size: Vector2 = Vector2(1600, 900)

# One weighted 3×3 blur pass over a grid field (centre weight `cw`, neighbours 1.0).
func _blur_field(src: PackedFloat32Array, cols: int, rows: int, cw: float) -> PackedFloat32Array:
	var dst := PackedFloat32Array(); dst.resize(cols * rows)
	for gy in range(rows):
		for gx in range(cols):
			var acc: float = 0.0; var cnt: float = 0.0
			for dy in range(-1, 2):
				for dx in range(-1, 2):
					var nx: int = gx + dx; var ny: int = gy + dy
					if nx < 0 or ny < 0 or nx >= cols or ny >= rows:
						continue
					var w: float = cw if (dx == 0 and dy == 0) else 1.0
					acc += src[ny * cols + nx] * w; cnt += w
			dst[gy * cols + gx] = acc / cnt
	return dst

# Bilinear sample of a grid field (cell-centred), clamped at the edges.
func _bilin(arr: PackedFloat32Array, cols: int, rows: int, gxf: float, gyf: float) -> float:
	var x0: int = floori(gxf); var y0: int = floori(gyf)
	var fx: float = gxf - float(x0); var fy: float = gyf - float(y0)
	var x1: int = clampi(x0 + 1, 0, cols - 1); var y1: int = clampi(y0 + 1, 0, rows - 1)
	x0 = clampi(x0, 0, cols - 1); y0 = clampi(y0, 0, rows - 1)
	var top: float = lerpf(arr[y0 * cols + x0], arr[y0 * cols + x1], fx)
	var bot: float = lerpf(arr[y1 * cols + x0], arr[y1 * cols + x1], fx)
	return lerpf(top, bot, fy)

# Bake the continent into a single hillshaded relief texture. Called once per map load.
func _build_relief_texture() -> void:
	var biome: Dictionary = _data.get("biome", {})
	if biome.is_empty():
		_relief_tex = null
		return
	var cols: int = int(biome["cols"])
	var rows: int = int(biome["rows"])
	_map_size = Vector2(cols * float(biome["cell_w"]), rows * float(biome["cell_h"]))
	var tiles: PackedByteArray = biome["tiles"]
	var n: int = cols * rows
	# Per-cell base land colour. Sea cells are stored as beach-sand so coasts blend to a
	# shore (not a blue halo); the real ocean is painted from the elevation field below.
	var sand: Color = _biome_color(WorldMapData.B_COAST)
	var cr := PackedFloat32Array(); cr.resize(n)
	var cg := PackedFloat32Array(); cg.resize(n)
	var cb := PackedFloat32Array(); cb.resize(n)
	for i in range(n):
		var b: int = tiles[i]
		var col: Color = sand if b == WorldMapData.B_SEA else _biome_color(b)
		col = col.lerp(_LAND_BASE, _LAND_UNIFY)   # cohesive designed palette (calm, not patchwork)
		cr[i] = col.r; cg[i] = col.g; cb[i] = col.b
	# Soften the categorical biome boundaries into natural land-cover gradients (one mild pass)
	# so forest/plains read as blended terrain instead of faceted cell blocks.
	cr = _blur_field(cr, cols, rows, 2.0)
	cg = _blur_field(cg, cols, rows, 2.0)
	cb = _blur_field(cb, cols, rows, 2.0)
	# Elevation field — prefer the generator's continuous noise; fall back to a per-biome
	# height for older saves. Blurred once so the hillshade reads as smooth, natural relief.
	var raw := PackedFloat32Array(); raw.resize(n)
	if biome.has("elev") and PackedFloat32Array(biome["elev"]).size() == n:
		var ev: PackedFloat32Array = PackedFloat32Array(biome["elev"])
		for i in range(n):
			raw[i] = ev[i]
	else:
		for i in range(n):
			raw[i] = _biome_elev(tiles[i])
	# Lightly-smoothed field for sea/coast thresholds (keeps the coastline fairly crisp).
	var se: PackedFloat32Array = _blur_field(raw, cols, rows, 3.0)
	# Mountain field: 1 at peak cells, blurred into a smooth dome. Mountains are only a handful
	# of cells and the fbm barely lifts them above the hill band, so we SYNTHESISE their relief
	# from this dome rather than trusting the noise — that's what makes them read as real massifs.
	var dome := PackedFloat32Array(); dome.resize(n)
	for i in range(n):
		dome[i] = 1.0 if tiles[i] == WorldMapData.B_MOUNTAIN else 0.0
	dome = _blur_field(_blur_field(dome, cols, rows, 1.0), cols, rows, 1.0)
	# Height field for the hillshade normal: a smoothed continent (gentle landform relief, no
	# fbm checkerboard) plus the mountain dome bulging the peaks up so they catch sun & shadow.
	var sh := PackedFloat32Array(); sh.resize(n)
	var base: PackedFloat32Array = _blur_field(se, cols, rows, 1.5)
	for i in range(n):
		sh[i] = base[i] + dome[i] * 0.32
	# Rasterise pixel by pixel into an RGBA8 buffer (one-time bake; ~360k px).
	var data := PackedByteArray(); data.resize(RELIEF_W * RELIEF_H * 4)
	var idx: int = 0
	for py in range(RELIEF_H):
		var gyf: float = (float(py) + 0.5) / float(RELIEF_H) * rows - 0.5
		for px in range(RELIEF_W):
			var gxf: float = (float(px) + 0.5) / float(RELIEF_W) * cols - 0.5
			var e: float = _bilin(se, cols, rows, gxf, gyf)
			var r: float; var g: float; var bl: float
			if e < _SEA_LEVEL:
				# Depth-shaded ocean: lit shelf near the coast, abyssal blue further out.
				var t: float = clampf((_SEA_LEVEL - e) / 0.16, 0.0, 1.0)
				var oc: Color = _SEA_SHALLOW.lerp(_SEA_DEEP, t)
				r = oc.r; g = oc.g; bl = oc.b
			else:
				r = _bilin(cr, cols, rows, gxf, gyf)
				g = _bilin(cg, cols, rows, gxf, gyf)
				bl = _bilin(cb, cols, rows, gxf, gyf)
				# Wet sand where the land just meets the waterline.
				var shore: float = 1.0 - smoothstep(_SEA_LEVEL, 0.355, e)
				if shore > 0.0:
					r = lerpf(r, _SHORE_WET.r, shore * 0.6)
					g = lerpf(g, _SHORE_WET.g, shore * 0.6)
					bl = lerpf(bl, _SHORE_WET.b, shore * 0.6)
				# Snow caps the peaks. Blended into the base BEFORE hillshading so snowy slopes
				# still catch sun/shadow (a flat white lerp after shading reads as a cloud blob).
				# Sampled from the mountain dome so snow sits on the bulged peaks. Tightened to the
				# dome CORE (higher threshold) and capped lower so caps read as snow-dusted rock,
				# not blinding cloud-blobs spread across the range (iter317 aesthetic cleanup).
				var snow: float = clampf((_bilin(dome, cols, rows, gxf, gyf) - 0.52) * 3.0, 0.0, 0.22)
				if snow > 0.0:
					r = lerpf(r, _SNOW.r, snow); g = lerpf(g, _SNOW.g, snow); bl = lerpf(bl, _SNOW.b, snow)
				# Hillshade from the (heavily-smoothed) height gradient under the NW sun.
				var zx: float = (_bilin(sh, cols, rows, gxf + 1.0, gyf) - _bilin(sh, cols, rows, gxf - 1.0, gyf)) * 0.5
				var zy: float = (_bilin(sh, cols, rows, gxf, gyf + 1.0) - _bilin(sh, cols, rows, gxf, gyf - 1.0)) * 0.5
				var nx: float = -zx * _Z_EXAG
				var ny: float = -zy * _Z_EXAG
				var inv: float = 1.0 / sqrt(nx * nx + ny * ny + 1.0)
				var dotl: float = (nx * _L.x + ny * _L.y + _L.z) * inv
				# Gentle hillshade: soft form, tight range, so the terrain stays a calm backdrop
				# rather than a high-contrast light/shadow patchwork competing with the network.
				var shade: float = clampf(1.0 + (dotl - _FLAT_DOT) * 1.1, 0.74, 1.18)
				r *= shade; g *= shade; bl *= shade
			data[idx]     = int(clampf(r, 0.0, 1.0) * 255.0)
			data[idx + 1] = int(clampf(g, 0.0, 1.0) * 255.0)
			data[idx + 2] = int(clampf(bl, 0.0, 1.0) * 255.0)
			data[idx + 3] = 255
			idx += 4
	var img := Image.create_from_data(RELIEF_W, RELIEF_H, false, Image.FORMAT_RGBA8, data)
	_relief_tex = ImageTexture.create_from_image(img)

func _draw_background() -> void:
	# The continent is a single baked relief raster (see _build_relief_texture), drawn under
	# the zoom/pan transform. Linear filtering keeps it smooth as the view scales up.
	if _relief_tex == null:
		return
	draw_texture_rect(_relief_tex, Rect2(Vector2.ZERO, _map_size), false)

# ── Faction territories (tint the land each kingdom holds) ─────────────────────

func _draw_faction_territories() -> void:
	var biome: Dictionary = _data.get("biome", {})
	if not biome.is_empty() and biome.has("territory"):
		var cols: int = biome["cols"]
		var rows: int = biome["rows"]
		var cw: float = biome["cell_w"]
		var ch: float = biome["cell_h"]
		var terr: PackedByteArray = biome["territory"]
		# iter315: render kingdom territory as a clean FRONTIER LINE following the cell edges
		# where ownership changes — political boundaries drawn over the physical relief, the way
		# a real map reads. (The old per-cell colour fills were pixelated blocks that fought the
		# naturalistic terrain.) Each owner draws its own edge inset toward its land, so a shared
		# border shows both kingdoms' colours as a twin frontier line.
		var inset: float = 1.6
		for gy in range(rows):
			for gx in range(cols):
				var owner: int = terr[gy * cols + gx]
				if owner == 0:
					continue   # neutral / sea / mountain
				var col: Color = _faction_color(owner - 1)
				var x0: float = gx * cw
				var y0: float = gy * ch
				var x1: float = x0 + cw
				var y1: float = y0 + ch
				# For each of the 4 cell edges that faces a DIFFERENT owner, draw the boundary
				# segment (inset toward this cell) over a dark casing for legibility.
				# right
				if gx + 1 >= cols or terr[gy * cols + gx + 1] != owner:
					_frontier_seg(Vector2(x1 - inset, y0), Vector2(x1 - inset, y1), col)
				# left
				if gx - 1 < 0 or terr[gy * cols + gx - 1] != owner:
					_frontier_seg(Vector2(x0 + inset, y0), Vector2(x0 + inset, y1), col)
				# down
				if gy + 1 >= rows or terr[(gy + 1) * cols + gx] != owner:
					_frontier_seg(Vector2(x0, y1 - inset), Vector2(x1, y1 - inset), col)
				# up
				if gy - 1 < 0 or terr[(gy - 1) * cols + gx] != owner:
					_frontier_seg(Vector2(x0, y0 + inset), Vector2(x1, y0 + inset), col)
	# Faction name labels near each capital.
	for f in _faction_list:
		draw_string(ThemeDB.fallback_font, f["center_pos"] + Vector2(-40, -f["radius"] * 0.0 - 24),
			f.get("name", ""), HORIZONTAL_ALIGNMENT_LEFT, -1, 11,
			Color.from_string(f["color_hex"], Color.GRAY).lightened(0.35))

# One frontier boundary segment: a faint dark casing under a muted coloured line, anti-aliased.
# Kept deliberately subtle (thin, low-alpha) so borders read as quiet political lines tracing the
# realms — not the screaming graphics they were (3px casing / 1.8px line @ 0.9 alpha).
func _frontier_seg(a: Vector2, b: Vector2, col: Color) -> void:
	draw_line(a, b, Color(0.05, 0.05, 0.05, 0.25), 2.0, true)
	draw_line(a, b, Color(col.r, col.g, col.b, 0.65), 1.2, true)

func _faction_color(faction_id: int) -> Color:
	if faction_id >= 0 and faction_id < WorldMapData.FACTION_COLORS.size():
		return Color.from_string(WorldMapData.FACTION_COLORS[faction_id], Color.GRAY)
	return Color.GRAY

# ── Roads ─────────────────────────────────────────────────────────────────────

# iter316 (user steer "restyle roads as realistic routes"): the roads ARE the strategic
# adjacency graph (connected_to → bfs_path marching + frontier_targets), so they stay — but
# they now read like faint earthen trade tracks worn into the land, not bright painted curves.
# A short-dashed dusty line over a soft shadow: the cartographic convention for a track/route,
# and subtle enough to sit naturally on the new relief while still tracing the march network.
const _ROAD_DUST: Color   = Color(0.46, 0.37, 0.25, 0.62)   # worn earthen track
const _ROAD_SHADOW: Color = Color(0.10, 0.07, 0.04, 0.30)   # soft groove beneath it
const _ROAD_DASH: float   = 6.0
const _ROAD_GAP: float    = 4.5

func _draw_roads() -> void:
	for r in _road_list:
		var fp: Vector2 = r["from_pos"]
		var tp: Vector2 = r["to_pos"]
		# Gentle arc via a quadratic Bézier (perpendicular control offset), sampled smooth so the
		# track curves instead of kinking at the midpoint. Control comes from the shared helper so
		# marching armies (WorldMapController.road_point) ride this exact curve.
		var ctrl: Vector2 = WorldMapController.road_ctrl(fp, tp)
		var pts := PackedVector2Array()
		const STEPS: int = 16
		for i in range(STEPS + 1):
			var t: float = float(i) / float(STEPS)
			var omt: float = 1.0 - t
			pts.append(omt * omt * fp + 2.0 * omt * t * ctrl + t * t * tp)
		_draw_dashed_route(pts)

# Walk a polyline by arc length, painting dashes (with gaps) as an earthen track over a soft
# shadow. The on/off phase carries across segments so the dashing stays even around the curve.
func _draw_dashed_route(pts: PackedVector2Array) -> void:
	var phase: float = 0.0      # distance into the current dash (drawing) or gap
	var drawing: bool = true
	for i in range(pts.size() - 1):
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[i + 1]
		var seg: float = a.distance_to(b)
		var pos: float = 0.0
		while pos < seg:
			var span: float = (_ROAD_DASH if drawing else _ROAD_GAP) - phase
			var step: float = minf(span, seg - pos)
			if drawing:
				var p0: Vector2 = a.lerp(b, pos / seg)
				var p1: Vector2 = a.lerp(b, (pos + step) / seg)
				draw_line(p0 + Vector2(0.5, 0.7), p1 + Vector2(0.5, 0.7), _ROAD_SHADOW, 2.2, true)
				draw_line(p0, p1, _ROAD_DUST, 1.4, true)
			pos += step
			phase += step
			if phase >= (_ROAD_DASH if drawing else _ROAD_GAP) - 0.001:
				phase = 0.0
				drawing = not drawing

# ── Resource deposits ─────────────────────────────────────────────────────────

# iter317: the four deposit glyphs (crossed axe / stone pile / pickaxes / wheat sheaf) were
# four unrelated little drawings = visual hodgepodge. Replaced with ONE coherent token — a small
# parchment disc with a coloured rim + centre keyed to the resource — so they read as a quiet,
# uniform set instead of a noisy jumble. Colour alone distinguishes type; the marker is identical.
func _deposit_color(t: String) -> Color:
	match t:
		"wood":  return Color(0.42, 0.30, 0.16)   # timber brown
		"stone": return Color(0.52, 0.52, 0.54)   # quarry grey
		"iron":  return Color(0.44, 0.49, 0.60)   # ore steel-blue
		"food":  return Color(0.74, 0.60, 0.22)   # grain gold
	return Color(0.6, 0.6, 0.6)

func _draw_resource_deposits() -> void:
	# Quiet, uniform markers: a small muted disc keyed to the resource colour. Deliberately
	# subtler than the settlements — deposits are background strategic info, not the headline.
	for d in _deposit_list:
		var p: Vector2 = d["pos"]
		var c: Color = _deposit_color(d["type"])
		draw_circle(p + Vector2(0.4, 0.6), 3.6, Color(0.0, 0.0, 0.0, 0.18))   # soft shadow
		draw_circle(p, 3.3, Color(c.r, c.g, c.b, 0.82))                       # muted resource disc
		draw_arc(p, 3.3, 0, TAU, 16, c.darkened(0.45), 1.0, true)            # darker rim
		draw_circle(p, 1.1, c.lightened(0.45))                               # faint highlight

# ── Cities ────────────────────────────────────────────────────────────────────

# Settlement rank (0 hamlet · 1 town · 2 city · 3 capital) from the strategic data — drives a
# coherent size hierarchy so a backwater village and a great-house capital read apart at a glance,
# and the elaborate keep is reserved for the few capitals rather than stamped on all 80 cities.
func _settlement_rank(c: Dictionary) -> int:
	if c.get("is_capital", false):
		return 3
	var dev: int = int(c.get("development", c.get("tier", 0)))
	var tier: int = int(c.get("tier", 0))
	if dev >= 6 or tier >= 3:
		return 2
	if dev >= 3 or tier >= 1:
		return 1
	return 0

func _draw_cities() -> void:
	for c in _city_list:
		var p:    Vector2 = c["pos"]
		var col:  Color   = Color.from_string(c["faction_color"], Color.GRAY)
		var is_player_owned: bool = c.get("is_player_owned", false)
		var is_start: bool = c.get("is_player_start", false)
		var is_hovered: bool = c.get("id", -1) == _hovered_city_id
		var is_selected: bool = c.get("id", -1) == _selected_city_id
		var rank: int = _settlement_rank(c)
		var ring_r: float = 11.0 + float(rank) * 2.5

		# Settled-ground clearing: a soft halo of cultivated land tying the town to the terrain,
		# so the map reads as composed AROUND its settlements rather than icons dumped on a relief.
		# Towns and up only (rank ≥ 1) — the 50+ hamlets would otherwise speckle the whole map.
		if rank >= 1:
			var halo_r: float = [0.0, 20.0, 26.0, 34.0][rank]
			var halo_a: float = [0.0, 0.13, 0.17, 0.22][rank]
			_ground_halo(p, halo_r, Color(0.84, 0.79, 0.62, halo_a))

		# Player-owned holdings get a gold ring so the realm reads at a glance.
		if is_player_owned:
			draw_arc(p, ring_r, 0, TAU, 24, Color(0.95, 0.78, 0.10, 0.70), 2.5, true)
		# The player's SEAT gets an unmistakable pulsing beacon + a tag, so a first-timer can
		# instantly spot "this one is mine" among dozens of rival nodes.
		if is_start:
			var pulse: float = 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.004)
			draw_arc(p, ring_r + 5.0 + pulse * 4.0, 0, TAU, 28, Color(1.0, 0.85, 0.25, 0.30 + 0.45 * pulse), 3.0, true)
			draw_arc(p, ring_r + 2.0, 0, TAU, 28, Color(1.0, 0.88, 0.35, 0.95), 2.5, true)
			_draw_map_label(p + Vector2(-50, -ring_r - 16.0), "⚜ YOUR SEAT", 100.0, 13, Color(1.0, 0.90, 0.45))
		# Hover highlight.
		if is_hovered:
			draw_arc(p, ring_r - 1.0, 0, TAU, 24, Color(1.0, 1.0, 1.0, 0.8), 2.0, true)
		# Selection ring — the city the player has right-clicked for orders.
		if is_selected:
			draw_arc(p, ring_r + 4.0, 0, TAU, 28, Color(0.30, 0.90, 1.0, 0.95), 3.0, true)
			draw_arc(p, ring_r + 7.0, 0, TAU, 28, Color(0.30, 0.90, 1.0, 0.35), 1.5, true)

		_draw_settlement(p, col, rank, is_player_owned, int(c.get("id", 0)))

		# Name — prominence scales with rank so minor places stay quiet; capitals & the player's
		# own holdings read boldest. Centred under the icon, haloed for legibility on any terrain.
		var fsize: int = [11, 12, 13, 14][rank]
		var name_col: Color
		if is_player_owned:
			name_col = Color(1.0, 0.90, 0.50)
		elif rank == 0:
			name_col = Color(0.88, 0.86, 0.80, 0.82)   # hamlets recede
		else:
			name_col = Color(0.97, 0.95, 0.90)
		var label: String = c.get("name", "")
		if is_start:
			label += " ★"
		var yoff: float = 11.0 + float(rank) * 2.5
		_draw_map_label(p + Vector2(-40, yoff), label, 80.0, fsize, name_col)

		# Garrison is gnarly clutter on all 80 cities — show it only where it matters right now:
		# the city you're inspecting (hover/select) or one of your own holdings. (Per-kingdom army
		# totals still live in the Kingdoms legend.)
		if is_hovered or is_selected or is_player_owned:
			var ginfo: String = "⚔ %d" % int(c.get("garrison", 0))
			_draw_map_label(p + Vector2(-40, yoff + 14.0), ginfo, 80.0, 11, Color(0.95, 0.88, 0.72))

# Centred map label with a small semi-transparent backing plate + a dark 4-direction halo, so
# names stay legible over busy terrain instead of smearing into the relief. The plate is sized to
# the actual text and centred under the `width` box the text is laid out in (pos is its top-left).
func _draw_map_label(pos: Vector2, text: String, width: float, fsize: int, col: Color) -> void:
	var f: Font = ThemeDB.fallback_font
	const _HALO: Color = Color(0.0, 0.0, 0.0, 0.85)
	const _PLATE: Color = Color(0.05, 0.06, 0.04, 0.50)
	var tw: float = f.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, fsize).x
	# Text is centre-aligned within [pos.x, pos.x + width]; centre the plate on that midline.
	var cx: float = pos.x + width * 0.5
	var pad_x: float = 4.0
	var plate_w: float = tw + pad_x * 2.0
	var asc: float = f.get_ascent(fsize)
	var plate := Rect2(cx - plate_w * 0.5, pos.y - asc - 1.0, plate_w, float(fsize) + 4.0)
	draw_rect(plate, _PLATE)
	for o in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
		draw_string(f, pos + o, text, HORIZONTAL_ALIGNMENT_CENTER, width, fsize, _HALO)
	draw_string(f, pos, text, HORIZONTAL_ALIGNMENT_CENTER, width, fsize, col)

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
		# March route to the target — a clear dashed track + arrowhead so you can read a host
		# crossing the realm in real time (iter319: thicker/clearer than the old thin line).
		if a.get("moving", false):
			var to: Vector2 = a["to"]
			draw_line(p, to, Color(col.r, col.g, col.b, 0.30), 4.0, true)   # soft column trail
			var dir: Vector2 = (to - p)
			if dir.length() > 1.0:
				dir = dir.normalized()
				var perp: Vector2 = dir.orthogonal() * 5.0
				var tip: Vector2 = p.lerp(to, 0.6)
				draw_colored_polygon(PackedVector2Array([
					tip + dir * 8.0, tip - dir * 3.0 + perp, tip - dir * 3.0 - perp,
				]), Color(col.r, col.g, col.b, 0.85))
		_draw_army_marker(p, col, int(a.get("size_band", 0)), int(a.get("size", 0)),
			a.get("composition", {}))
		# Your own marching hosts get a glanceable destination + ETA tag, so you can
		# read where your troops are bound without clicking (few of them, no clutter).
		if a.get("is_player", false) and a.get("moving", false):
			var dest: String = String(a.get("dest_name", ""))
			if dest != "":
				var eta: int = int(a.get("eta_days", 0))
				var tag: String = "→ %s (%dd)" % [dest, eta]
				var tp := p + Vector2(10, 14)
				draw_string(ThemeDB.fallback_font, tp + Vector2(1, 1), tag,
					HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.04, 0.06, 0.03, 0.9))
				draw_string(ThemeDB.fallback_font, tp, tag,
					HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.70, 0.96, 0.62))

# A field host: a big faction shield carrying the icon of its DOMINANT troop type (so an archer
# host, a pike column and a siege train read apart at a glance while traversing), a strength
# pennant whose size grows with the band, and the troop count. Band 0:1-10 … 4:100+.
func _draw_army_marker(p: Vector2, col: Color, band: int, size_count: int, comp: Dictionary) -> void:
	var r: float = 9.0 + float(band) * 2.4        # iter319: much bigger than the old ~4px disc
	_ground_shadow(p + Vector2(r * 0.18, r * 0.14), r * 1.05, r * 0.42)
	# Strength pennant on a short pole above the shield.
	var fw: float = 9.0 + float(band) * 2.0
	var fh: float = 6.0 + float(band) * 1.0
	var top := p + Vector2(0, -(r + 8.0 + float(band) * 2.0))
	draw_line(p + Vector2(0.8, 0.8), top + Vector2(0.8, 0.8), Color(0, 0, 0, 0.35), 1.8)
	draw_line(p, top, Color(0.20, 0.15, 0.09), 1.8)
	draw_colored_polygon(PackedVector2Array([top, top + Vector2(fw, fh * 0.5), top + Vector2(0, fh)]), col)
	draw_polyline(PackedVector2Array([
		top, top + Vector2(fw, fh * 0.5), top + Vector2(0, fh), top]), col.darkened(0.5), 1.0)
	# Shield disc (dark rim, faction fill, NW-lit edge) carrying the troop-type glyph.
	draw_circle(p, r + 1.6, Color(0.08, 0.07, 0.06, 0.92))
	draw_circle(p, r, col)
	draw_arc(p, r - 0.5, PI * 1.05, PI * 1.95, 12, col.lightened(0.35), 1.8, true)
	_draw_unit_glyph(p, r * 0.62, _dominant_group(comp))
	# Troop count, centred just under the shield.
	_draw_map_label(p + Vector2(-40, r + 1.0), str(size_count), 80.0, 11, Color(0.98, 0.96, 0.90))

# The icon group that best represents a host (the most numerous of infantry / ranged / siege).
# Empty composition (gold-levied AI armies) falls back to a generic infantry host.
func _dominant_group(comp: Dictionary) -> String:
	var inf: int = int(comp.get("infantry", 0))
	var rng: int = int(comp.get("ranged", 0))
	var sg: int = int(comp.get("siege", 0))
	if inf == 0 and rng == 0 and sg == 0:
		return "infantry"
	if sg >= inf and sg >= rng:
		return "siege"
	if rng >= inf and rng >= sg:
		return "ranged"
	return "infantry"

# A short line drawn as a dark drop-shadow under a light ink stroke, so unit glyphs stay legible
# on ANY faction-coloured shield.
func _ink_line(a: Vector2, b: Vector2, w: float) -> void:
	draw_line(a + Vector2(0.7, 0.8), b + Vector2(0.7, 0.8), Color(0.0, 0.0, 0.0, 0.55), w + 0.6, true)
	draw_line(a, b, Color(0.98, 0.96, 0.88), w, true)

# Troop-type pictograph centred on the shield: crossed swords (infantry), a drawn bow (ranged),
# or a catapult/trebuchet (siege).
func _draw_unit_glyph(c: Vector2, s: float, group: String) -> void:
	match group:
		"ranged":
			# A bow (arc) with its string and a nocked arrow.
			var bc := c + Vector2(-s * 0.15, 0.0)
			draw_arc(bc + Vector2(0.7, 0.8), s, -PI * 0.55, PI * 0.55, 12, Color(0.0, 0.0, 0.0, 0.55), 2.4, true)
			draw_arc(bc, s, -PI * 0.55, PI * 0.55, 12, Color(0.98, 0.96, 0.88), 1.8, true)
			_ink_line(bc + Vector2(cos(-PI * 0.55), sin(-PI * 0.55)) * s,
				bc + Vector2(cos(PI * 0.55), sin(PI * 0.55)) * s, 1.4)   # bowstring
			_ink_line(c + Vector2(-s * 0.7, 0.0), c + Vector2(s * 0.9, 0.0), 1.4)   # arrow shaft
			_ink_line(c + Vector2(s * 0.9, 0.0), c + Vector2(s * 0.5, -s * 0.25), 1.2)  # arrowhead
			_ink_line(c + Vector2(s * 0.9, 0.0), c + Vector2(s * 0.5, s * 0.25), 1.2)
		"siege":
			# A trebuchet: A-frame with a slung throwing arm.
			_ink_line(c + Vector2(-s * 0.7, s * 0.6), c + Vector2(0.0, -s * 0.5), 1.8)   # left leg
			_ink_line(c + Vector2(s * 0.7, s * 0.6), c + Vector2(0.0, -s * 0.5), 1.8)    # right leg
			_ink_line(c + Vector2(-s * 0.7, s * 0.6), c + Vector2(s * 0.7, s * 0.6), 1.6)  # base
			_ink_line(c + Vector2(-s * 0.6, -s * 0.1), c + Vector2(s * 0.8, -s * 0.8), 1.8)  # throwing arm
			draw_circle(c + Vector2(s * 0.8 + 0.7, -s * 0.8 + 0.8), s * 0.22, Color(0.0, 0.0, 0.0, 0.55))
			draw_circle(c + Vector2(s * 0.8, -s * 0.8), s * 0.20, Color(0.98, 0.96, 0.88))   # payload
		_:
			# Crossed swords (generic / infantry).
			_ink_line(c + Vector2(-s * 0.7, s * 0.7), c + Vector2(s * 0.7, -s * 0.7), 2.0)   # blade 1
			_ink_line(c + Vector2(s * 0.7, s * 0.7), c + Vector2(-s * 0.7, -s * 0.7), 2.0)   # blade 2
			_ink_line(c + Vector2(-s * 0.85, s * 0.45), c + Vector2(-s * 0.45, s * 0.85), 1.6)  # hilt guards
			_ink_line(c + Vector2(s * 0.85, s * 0.45), c + Vector2(s * 0.45, s * 0.85), 1.6)

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
		var is_you: bool = k.get("is_player", false)
		# Highlight the player's own kingdom row so the realm is found at a glance (overhaul iter9).
		if is_you:
			draw_rect(Rect2(origin.x + 3.0, y - 10.0, panel_w - 6.0, row_h), Color(0.95, 0.78, 0.10, 0.16))
			draw_string(ThemeDB.fallback_font, Vector2(origin.x + pad - 7.0, y + 2.0), "♔",
				HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(1.0, 0.85, 0.30))
		# Colour swatch.
		draw_rect(Rect2(origin.x + pad, y - 8.0, 10.0, 10.0), col if alive else col.darkened(0.5))
		var nm: String = k.get("name", "")
		if is_you:
			nm += " (You)"
		var txt_col: Color = Color(0.88, 0.82, 0.64) if alive else Color(0.5, 0.45, 0.4)
		if is_you:
			txt_col = Color(1.0, 0.90, 0.55)
		var line: String = nm if alive else nm + " ✝"
		draw_string(ThemeDB.fallback_font, Vector2(origin.x + pad + 16.0, y + 2.0), line,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 10, txt_col)
		var stats: String = "%d⌂ %d⚔" % [k.get("city_count", 0), k.get("army_size", 0)]
		draw_string(ThemeDB.fallback_font, Vector2(origin.x + panel_w - 56.0, y + 2.0), stats,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 9, txt_col)
		y += row_h

# A soft radial clearing (triangle-fan gradient: solid centre → transparent rim) marking the
# cultivated land around a settlement, so it sits in a composed pocket of terrain (iter318).
func _ground_halo(c: Vector2, r: float, col: Color) -> void:
	var pts := PackedVector2Array([c])
	var cols := PackedColorArray([col])
	var clear := Color(col.r, col.g, col.b, 0.0)
	var segs: int = 20
	for i in range(segs + 1):
		var a: float = float(i) / float(segs) * TAU
		pts.append(c + Vector2(cos(a), sin(a)) * r)
		cols.append(clear)
	draw_polygon(pts, cols)

# A small flattened ground-shadow ellipse, so an icon sits ON the terrain instead of
# floating over it (depth pass, iter314). Centred at c with radii rx,ry.
func _ground_shadow(c: Vector2, rx: float, ry: float) -> void:
	var pts := PackedVector2Array()
	for i in range(16):
		var a: float = float(i) / 16.0 * TAU
		pts.append(c + Vector2(cos(a) * rx, sin(a) * ry))
	draw_colored_polygon(pts, Color(0.0, 0.0, 0.0, 0.22))

# iter317: one coherent settlement symbol set, sized by rank, all lit from the upper-left to
# match the relief's NW sun. Hamlets are a single hut; the elaborate banner-flying keep is now
# reserved for capitals — so the map has a real size hierarchy instead of 80 identical castles.
const _ICON_OUTLINE: Color = Color(0.09, 0.07, 0.05, 0.9)

# iter319: settlements are no longer "everything is a castle". Each rank is a visually distinct
# place built from shared NW-lit primitives — a hamlet of huts, a village with a church, a walled
# town, and a banner keep for capitals — and a per-settlement hash jitters the layout so no two
# look stamped from the same mould. Markers are larger than before so towns read clearly.
func _draw_settlement(p: Vector2, faction_col: Color, rank: int, is_player: bool, seed_id: int) -> void:
	var body: Color = Color(0.91, 0.76, 0.26) if is_player else faction_col
	var hsh: int = absi(seed_id * 1103515245 + 12345)
	match rank:
		0: _settle_hamlet(p, body, hsh)
		1: _settle_village(p, body, hsh)
		2: _settle_town(p, body, hsh)
		_: _settle_capital(p, body, hsh)

# ── Building primitives (shared flat NW-lit language) ──────────────────────────
# `base` is the ground point (bottom-centre); the building rises above it.
func _b_house(base: Vector2, w: float, h: float, body: Color) -> void:
	var lit: Color  = body.lightened(0.22)
	var roof: Color = body.darkened(0.5)
	var x: float = base.x - w * 0.5
	var y: float = base.y - h
	draw_rect(Rect2(x, y, w, h), body)
	draw_rect(Rect2(x + w * 0.62, y, w * 0.38, h), Color(0, 0, 0, 0.20))   # shaded SE face
	draw_rect(Rect2(x, y, w * 0.14, h), lit)                               # NW-lit edge
	draw_rect(Rect2(x, y, w, h), _ICON_OUTLINE, false, 0.8)
	var peak := Vector2(base.x, y - h * 0.72)
	var l := Vector2(x - w * 0.12, y)
	var r := Vector2(x + w + w * 0.12, y)
	draw_colored_polygon(PackedVector2Array([peak, l, r]), roof)
	draw_line(peak, l, roof.lightened(0.3), 1.0)
	draw_line(l, r, _ICON_OUTLINE, 0.8)

# A tower/keep block. `cone` = pointed roof (church/tower); else battlemented top (fortified).
func _b_tower(base: Vector2, w: float, h: float, body: Color, cone: bool) -> void:
	var lit: Color  = body.lightened(0.2)
	var roof: Color = body.darkened(0.5)
	var x: float = base.x - w * 0.5
	var y: float = base.y - h
	draw_rect(Rect2(x, y, w, h), body)
	draw_rect(Rect2(x + w * 0.6, y, w * 0.4, h), Color(0, 0, 0, 0.20))
	draw_rect(Rect2(x, y, w * 0.18, h), lit)
	draw_rect(Rect2(x, y, w, h), _ICON_OUTLINE, false, 0.8)
	if cone:
		var peak := Vector2(base.x, y - h * 0.6)
		draw_colored_polygon(PackedVector2Array([peak, Vector2(x - w * 0.14, y), Vector2(x + w + w * 0.14, y)]), roof)
		draw_line(peak, Vector2(x - w * 0.14, y), roof.lightened(0.28), 1.0)
	else:
		var km: float = w / 3.4
		for m in range(3):
			var mx: float = x + float(m) * (w / 2.55) + km * 0.12
			draw_rect(Rect2(mx, y - h * 0.16, km, h * 0.16), body)
			draw_rect(Rect2(mx, y - h * 0.16, km, h * 0.16), _ICON_OUTLINE, false, 0.5)

# ── Settlement composers (back-to-front: higher/farther buildings drawn first) ──
# Hamlet: one or two small huts.
func _settle_hamlet(p: Vector2, body: Color, hsh: int) -> void:
	_ground_shadow(p + Vector2(2.0, 1.2), 9.0, 3.4)
	if (hsh & 1) == 1:
		_b_house(p + Vector2(-6.0, -1.0), 7.0, 5.0, body)
	_b_house(p, 9.0, 6.5, body)

# Village: a couple of cottages flanking a small church (cone-roofed tower) — clearly not a castle.
func _settle_village(p: Vector2, body: Color, hsh: int) -> void:
	_ground_shadow(p + Vector2(2.5, 1.6), 15.0, 5.0)
	_b_house(p + Vector2(-9.0, 1.0), 8.0, 5.5, body)
	if (hsh & 2) == 2:
		_b_house(p + Vector2(10.0, 2.0), 7.5, 5.0, body)
	_b_tower(p + Vector2(1.0, 0.0), 7.0, 15.0, body, true)        # church steeple
	_b_house(p + Vector2(-2.0, 2.0), 9.0, 6.5, body)             # hall in front

# Town: a cluster of houses behind a fortified tower, reading as a market town.
func _settle_town(p: Vector2, body: Color, hsh: int) -> void:
	_ground_shadow(p + Vector2(3.0, 2.0), 20.0, 6.5)
	_b_house(p + Vector2(-12.0, 0.0), 9.0, 6.0, body)
	_b_house(p + Vector2(12.0, 1.0), 9.0, 6.0, body)
	if (hsh & 4) == 4:
		_b_house(p + Vector2(0.0, -3.0), 8.0, 5.5, body)
	_b_tower(p + Vector2(5.0, 2.5), 9.0, 18.0, body, false)      # fortified tower
	_b_house(p + Vector2(-5.0, 3.0), 11.0, 7.5, body)           # main hall up front

# Capital: a banner-flying keep with two flanking towers, a couple of houses at its foot.
func _settle_capital(p: Vector2, body: Color, _hsh: int) -> void:
	var dark: Color = body.darkened(0.35)
	var lit: Color  = body.lightened(0.18)
	var roof: Color = body.darkened(0.5)
	var scale: float = 16.0
	var bw: float = scale * 1.4
	var bh: float = scale * 1.2
	var tw: float = scale * 0.55
	var th: float = scale * 1.55
	_ground_shadow(p + Vector2(scale * 0.14, scale * 0.06), bw * 0.95, scale * 0.36)
	# Houses clustered at the foot of the castle (drawn first, behind).
	_b_house(p + Vector2(-bw * 0.62, 2.0), 9.0, 6.0, body)
	_b_house(p + Vector2(bw * 0.62, 3.0), 9.0, 6.0, body)
	# Flanking towers with conical roofs.
	for side in [-1, 1]:
		var tx: float = p.x + side * (bw * 0.5 + tw * 0.3) - tw * 0.5
		draw_rect(Rect2(tx, p.y - th, tw, th), body)
		draw_rect(Rect2(tx + tw * 0.58, p.y - th, tw * 0.42, th), Color(0, 0, 0, 0.20))
		draw_rect(Rect2(tx, p.y - th, tw * 0.16, th), lit)
		draw_rect(Rect2(tx, p.y - th, tw, th), _ICON_OUTLINE, false, 0.8)
		var rt := Vector2(tx + tw * 0.5, p.y - th - scale * 0.55)
		draw_colored_polygon(PackedVector2Array([
			rt, Vector2(tx - tw * 0.14, p.y - th), Vector2(tx + tw * 1.14, p.y - th)]), roof)
		draw_line(rt, Vector2(tx - tw * 0.14, p.y - th), roof.lightened(0.28), 1.0)
	# Central keep.
	var bx: float = p.x - bw * 0.5
	draw_rect(Rect2(bx, p.y - bh, bw, bh), body)
	draw_rect(Rect2(bx + bw * 0.62, p.y - bh, bw * 0.38, bh), Color(0, 0, 0, 0.20))
	draw_rect(Rect2(bx, p.y - bh, bw * 0.10, bh), lit)
	draw_rect(Rect2(bx, p.y - bh, bw, bh), _ICON_OUTLINE, false, 1.0)
	var km: float = bw / 7.0
	for m in range(4):
		var mx: float = bx + float(m) * (bw / 3.6) + km * 0.2
		draw_rect(Rect2(mx, p.y - bh - scale * 0.28, km, scale * 0.28), body)
		draw_rect(Rect2(mx, p.y - bh - scale * 0.28, km, scale * 0.28), _ICON_OUTLINE, false, 0.6)
	draw_arc(p + Vector2(0, -scale * 0.30), scale * 0.28, PI, TAU, 8, dark.darkened(0.3), 1.6)
	# Banner from the keep.
	var flag_x: float = p.x + bw * 0.05
	var flag_top: Vector2 = Vector2(flag_x, p.y - bh - scale * 0.9)
	draw_line(Vector2(flag_x, p.y - bh - scale * 0.26), flag_top, dark, 1.5)
	draw_colored_polygon(PackedVector2Array([
		flag_top, flag_top + Vector2(scale * 0.65, scale * 0.2), flag_top + Vector2(0, scale * 0.42),
	]), lit)
