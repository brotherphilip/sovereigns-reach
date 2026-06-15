extends RefCounted
# Pure static data extractors for the world map view.
# Accepts WorldMapData.generate() output; returns render-ready arrays.
# No Node imports — fully headless-testable.

const WorldMapData = preload("res://simulation/world/WorldMapData.gd")

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
	return "#888888"

# Field armies currently on the march, positioned partway along the road from
# their current city toward the next hop so movement is visible.
static func get_army_render_list(data: Dictionary) -> Array:
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
			if not path.is_empty():
				var nxt: Dictionary = _city(data, path[0])
				if not nxt.is_empty():
					to_pos = Vector2(nxt.get("pos_x", 0.0), nxt.get("pos_y", 0.0))
					pos = from_pos.lerp(to_pos, 0.35)  # marching out from the city
			result.append({
				"pos":   pos,
				"to":    to_pos,
				"moving": not path.is_empty(),
				"size":  a.get("size", 0),
				"size_band": size_band(a.get("size", 0)),
				"color_hex": col_hex,
				"owner": k.get("id", -1),
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
