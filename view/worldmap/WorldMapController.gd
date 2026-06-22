extends RefCounted
# Pure static data extractors for the world map view.
# Accepts WorldMapData.generate() output; returns render-ready arrays.
# No Node imports — fully headless-testable.

const WorldMapData    = preload("res://simulation/world/WorldMapData.gd")
const CampaignSystem  = preload("res://simulation/strategic/CampaignSystem.gd")
const UnitRegistry    = preload("res://simulation/units/UnitRegistry.gd")

# Bucket an army's carried real units into the three marker icon groups (infantry / ranged /
# siege) so the world-map marker can show WHAT is marching, not just how many. Gold-levied
# armies carry no unit roster → empty dict, and the marker falls back to a generic host icon.
static func _army_composition(army: Dictionary) -> Dictionary:
	var comp := {"infantry": 0, "ranged": 0, "siege": 0}
	for u in army.get("units", []):
		if not u is Dictionary:
			continue
		var def: Dictionary = UnitRegistry.lookup(String(u.get("type", "")))
		if String(def.get("category", "")) == UnitRegistry.CAT_SIEGE:
			comp["siege"] += 1
		elif String(def.get("attack_type", "")) == UnitRegistry.ATTACK_PIERCE:
			comp["ranged"] += 1
		else:
			comp["infantry"] += 1
	return comp

static func get_city_render_list(data: Dictionary) -> Array:
	var cities: Array   = data.get("cities", [])
	var result: Array   = []
	var player_fid: int = data.get("player_faction_id", -1)
	for c in cities:
		# Colour by CURRENT owner (strategic state) so conquests show as the city
		# changing hands; fall back to the static faction_id before init.
		var owner_fid: int = c.get("owner_faction_id", c.get("faction_id", 0))
		result.append({
			"id":             c.get("id", 0),
			"pos":            Vector2(c.get("pos_x", 0.0), c.get("pos_y", 0.0)),
			"name":           c.get("name", ""),
			"faction_color":  _faction_color_hex(data, owner_fid),
			"owner_faction_id": owner_fid,
			"tier":           c.get("tier", 0),
			"is_capital":     c.get("is_capital", false),
			"is_player_start": c.get("is_player_start", false),
			"is_player_owned": owner_fid == player_fid and player_fid >= 0,
			"population":     c.get("population", 0),
			"troop_count":    c.get("troop_count", 0),
			"garrison":       c.get("garrison", c.get("troop_count", 0)),
			"development":    c.get("development", c.get("tier", 0)),
		})
	return result

static func _faction_color_hex(data: Dictionary, faction_id: int) -> String:
	var factions: Array = data.get("factions", [])
	if faction_id >= 0 and faction_id < factions.size():
		return factions[faction_id].get("color_hex", "#888888")
	# The player (and any non-great-house kingdom) carries its own colour.
	for k in data.get("kingdoms", []):
		if k is Dictionary and int(k.get("id", -999)) == faction_id:
			return String(k.get("color_hex", "#888888"))
	return "#6b6b6b"  # independent villages — neutral grey

# Field armies currently on the march, positioned partway along the road from
# their current city toward the next hop so movement is visible.
# `march_frac` (0..1) = how far along the CURRENT road hop a marching army is, so the
# caller (the live map) can animate armies sliding smoothly between cities each frame
# rather than jumping city-to-city. Idle armies ignore it (drawn at their city).
static func get_army_render_list(data: Dictionary, march_frac: float = 0.4) -> Array:
	var result: Array = []
	for k in data.get("kingdoms", []):
		if not k is Dictionary:
			continue
		var col_hex: String = _faction_color_hex(data, k.get("id", -1))
		for a in k.get("armies", []):
			if not a is Dictionary or a.get("size", 0) <= 0:
				continue
			var here: Dictionary = _city(data, a.get("location_city_id", -1))
			if here.is_empty():
				continue
			var from_pos := Vector2(here.get("pos_x", 0.0), here.get("pos_y", 0.0))
			var path: Array = a.get("path", [])
			var pos := from_pos
			var to_pos := from_pos
			var dest_name: String = ""
			var eta_days: int = 0
			if not path.is_empty():
				var nxt: Dictionary = _city(data, path[0])
				if not nxt.is_empty():
					to_pos = Vector2(nxt.get("pos_x", 0.0), nxt.get("pos_y", 0.0))
					# Prefer the army's TRUE travel progress (distance-scaled by the
					# sim); fall back to the caller's sweep only for legacy armies.
					var frac: float = a.get("march_frac", march_frac)
					pos = from_pos.lerp(to_pos, clampf(frac, 0.0, 1.0))  # animated march
				var dest_id: int = a.get("dest_city_id", path[path.size() - 1])
				var dc: Dictionary = _city(data, dest_id)
				dest_name = String(dc.get("name", "")) if not dc.is_empty() else ""
				# Reuse the sim's exact distance-scaled ETA (wrap the map dict as a world).
				eta_days = CampaignSystem.days_to_destination({"world_map": data}, a)
			result.append({
				"pos":   pos,
				"to":    to_pos,
				"moving": not path.is_empty(),
				"size":  a.get("size", 0),
				"size_band": size_band(a.get("size", 0)),
				"color_hex": col_hex,
				"owner": k.get("id", -1),
				"owner_name": String(k.get("name", "A kingdom")),
				"is_player": k.get("id", -1) == data.get("player_faction_id", -1),
				"army_id": a.get("id", -1),
				"dest_name": dest_name,
				"eta_days": eta_days,
				"composition": _army_composition(a),
			})
	return result

# Army strength → marker tier: 0:1-10, 1:11-30, 2:31-60, 3:61-100, 4:100+.
# Shared by the world map and the in-session macro overlay so both read alike.
static func size_band(size: int) -> int:
	if size >= 101: return 4
	if size >= 61:  return 3
	if size >= 31:  return 2
	if size >= 11:  return 1
	return 0

# Per-kingdom legend: name, colour, cities held, alive/defeated.
static func get_kingdom_legend(data: Dictionary) -> Array:
	var cities: Array = data.get("cities", [])
	var counts: Dictionary = {}
	for c in cities:
		var ofid: int = c.get("owner_faction_id", c.get("faction_id", -1))
		counts[ofid] = counts.get(ofid, 0) + 1
	var result: Array = []
	for k in data.get("kingdoms", []):
		if not k is Dictionary:
			continue
		var fid: int = k.get("id", -1)
		result.append({
			"id":         fid,
			"name":       k.get("name", "Kingdom %d" % fid),
			"color_hex":  _faction_color_hex(data, fid),
			"city_count": counts.get(fid, 0),
			"is_alive":   k.get("is_alive", true),
			"is_player":  k.get("is_player", false),
			"army_size":  _kingdom_army_size(k),
		})
	return result

static func _kingdom_army_size(kingdom: Dictionary) -> int:
	var s: int = 0
	for a in kingdom.get("armies", []):
		if a is Dictionary:
			s += a.get("size", 0)
	return s

static func _city(data: Dictionary, city_id: int) -> Dictionary:
	var cities: Array = data.get("cities", [])
	if city_id >= 0 and city_id < cities.size() and cities[city_id] is Dictionary \
			and cities[city_id].get("id", -1) == city_id:
		return cities[city_id]
	for c in cities:
		if c is Dictionary and c.get("id", -1) == city_id:
			return c
	return {}

static func get_road_render_list(data: Dictionary) -> Array:
	var cities: Array = data.get("cities", [])
	var roads: Array  = data.get("roads", [])
	var result: Array = []
	for r in roads:
		var fi: int = r.get("from_id", 0)
		var ti: int = r.get("to_id", 0)
		if fi >= cities.size() or ti >= cities.size():
			continue
		result.append({
			"from_pos": Vector2(cities[fi]["pos_x"], cities[fi]["pos_y"]),
			"to_pos":   Vector2(cities[ti]["pos_x"], cities[ti]["pos_y"]),
		})
	return result

static func get_faction_territory_list(data: Dictionary) -> Array:
	var cities: Array   = data.get("cities", [])
	var factions: Array = data.get("factions", [])
	var result: Array   = []
	for f in factions:
		var cap_id: int = f.get("capital_city_id", 0)
		if cap_id >= cities.size(): continue
		var cap = cities[cap_id]
		var city_count: int = f.get("city_ids", []).size()
		var radius: float = clampf(80.0 + float(city_count) * 12.0, 80.0, 220.0)
		result.append({
			"faction_id": f.get("id", 0),
			"center_pos": Vector2(cap.get("pos_x", 0.0), cap.get("pos_y", 0.0)),
			"color_hex":  f.get("color_hex", "#888888"),
			"radius":     radius,
			"name":       f.get("name", ""),
		})
	return result

static func get_resource_deposit_list(data: Dictionary) -> Array:
	var deposits: Array = data.get("deposits", [])
	var result: Array   = []
	for d in deposits:
		result.append({
			"pos":  Vector2(d.get("pos_x", 0.0), d.get("pos_y", 0.0)),
			"type": d.get("type", "wood"),
		})
	return result

static func get_player_start_city(data: Dictionary) -> Dictionary:
	for c in data.get("cities", []):
		if c.get("is_player_start", false):
			return c
	return {}

static func find_city_near(data: Dictionary, screen_pos: Vector2, radius: float) -> int:
	var best_id: int   = -1
	var best_d: float  = INF
	for c in data.get("cities", []):
		var cpos := Vector2(c.get("pos_x", 0.0), c.get("pos_y", 0.0))
		var d: float = screen_pos.distance_to(cpos)
		if d < radius and d < best_d:
			best_d  = d
			best_id = c.get("id", -1)
	return best_id

# Recently-contested cities → fading battle markers. Reads world_map["recent_battles"]
# (stamped by GameState as the strategic war resolves). `fade_frac` 0→1 = fresh→stale.
static func get_battle_render_list(data: Dictionary, current_day: int, fade_days: int = 6) -> Array:
	var result: Array = []
	if fade_days <= 0:
		return result
	for m in data.get("recent_battles", []):
		if not m is Dictionary:
			continue
		var age: int = current_day - int(m.get("day", -999))
		if age < 0 or age >= fade_days:
			continue
		var c: Dictionary = _city(data, int(m.get("city_id", -1)))
		if c.is_empty():
			continue
		result.append({
			"pos":       Vector2(c.get("pos_x", 0.0), c.get("pos_y", 0.0)),
			"fade_frac": clampf(float(age) / float(fade_days), 0.0, 1.0),
			"captured":  bool(m.get("captured", false)),
		})
	return result

# Nearest marching army marker to a screen point (within radius), or {} if none.
# Returns the same enriched render dict get_army_render_list produces (size, owner_name,
# dest_name, eta_days, moving…) so the caller can show a full host inspection.
static func find_army_near(data: Dictionary, screen_pos: Vector2, radius: float, march_frac: float = 0.4) -> Dictionary:
	var best: Dictionary = {}
	var best_d: float = radius
	for a in get_army_render_list(data, march_frac):
		var d: float = screen_pos.distance_to(a.get("pos", Vector2.ZERO))
		if d <= best_d:
			best_d = d
			best = a
	return best
