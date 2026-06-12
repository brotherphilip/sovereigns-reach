extends RefCounted
# Pure static data extractors for the world map view.
# Accepts WorldMapData.generate() output; returns render-ready arrays.
# No Node imports — fully headless-testable.

const WorldMapData = preload("res://simulation/world/WorldMapData.gd")

static func get_city_render_list(data: Dictionary) -> Array:
	var cities: Array   = data.get("cities", [])
	var factions: Array = data.get("factions", [])
	var result: Array   = []
	for c in cities:
		var fid: int     = c.get("faction_id", 0)
		var col_hex: String = "#888888"
		if fid >= 0 and fid < factions.size():
			col_hex = factions[fid].get("color_hex", "#888888")
		result.append({
			"id":             c.get("id", 0),
			"pos":            Vector2(c.get("pos_x", 0.0), c.get("pos_y", 0.0)),
			"name":           c.get("name", ""),
			"faction_color":  col_hex,
			"tier":           c.get("tier", 0),
			"is_capital":     c.get("is_capital", false),
			"is_player_start": c.get("is_player_start", false),
			"population":     c.get("population", 0),
			"troop_count":    c.get("troop_count", 0),
		})
	return result

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
