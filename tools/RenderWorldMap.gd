extends SceneTree
# Dev harness: render the strategic world map to a PNG so the relief raster can be eyeballed.
# Run (needs a real display — use Xvfb, NOT --headless, so the canvas actually rasterises):
#   xvfb-run -a -s "-screen 0 1600x900x24" godot --path . --script tools/RenderWorldMap.gd
# Optional: pass a seed via SR_SEED env. Output: user://worldmap_relief.png (printed as a path).

const WorldMapView = preload("res://view/worldmap/WorldMapView.gd")
const WorldMapData = preload("res://simulation/world/WorldMapData.gd")

func _initialize() -> void:
	var seed_value: int = 12345
	var env_seed: String = OS.get_environment("SR_SEED")
	if env_seed != "":
		seed_value = int(env_seed)
	root.size = Vector2i(1600, 900)
	var data: Dictionary = WorldMapData.generate(seed_value)
	if OS.get_environment("SR_ARMIES") != "":
		_inject_demo_armies(data)
	var view: WorldMapView = WorldMapView.new()
	view.size = Vector2(1600, 900)
	root.add_child(view)
	view.apply_data(data)
	# Default to the full-continent fit (zoom 1.0) for evaluation; override with SR_ZOOM.
	var zoom_env: String = OS.get_environment("SR_ZOOM")
	view._zoom = float(zoom_env) if zoom_env != "" else 1.0
	# Render a few frames so the canvas draws, then capture the backbuffer.
	await process_frame
	await process_frame
	await process_frame
	var img: Image = root.get_texture().get_image()
	# Write to user:// (outside the project tree) so the engine never auto-imports the dev
	# render into the repo. The globalized absolute path is printed for easy viewing.
	var out_abs: String = ProjectSettings.globalize_path("user://worldmap_relief.png")
	var err: int = img.save_png(out_abs)
	print("[RenderWorldMap] seed=", seed_value, " saved=", out_abs, " err=", err)
	quit()

# Inject a few demo kingdoms/armies (idle infantry, marching archers, a siege train) so the
# army markers can be eyeballed — the bare generated map has no strategic armies. SR_ARMIES=1.
func _inject_demo_armies(data: Dictionary) -> void:
	var cities: Array = data.get("cities", [])
	if cities.size() < 8:
		return
	var function_units := func(t: String, n: int) -> Array:
		var arr: Array = []
		for i in range(n):
			arr.append({"id": i, "type": t, "hp": 50, "is_alive": true})
		return arr
	var c0: Dictionary = cities[2]
	var c1: Dictionary = cities[4]
	var c2: Dictionary = cities[5]
	var c3: Dictionary = cities[9]
	var c4: Dictionary = cities[12]
	var c5: Dictionary = cities[15]
	data["player_faction_id"] = 1000
	data["kingdoms"] = [{
		"id": 1000, "name": "Player Realm", "color_hex": "#e0b020",
		"armies": [
			# Idle infantry host sitting on its city.
			{"id": 1, "owner_faction_id": 1000, "size": 45, "location_city_id": c0.get("id", 0),
				"dest_city_id": -1, "path": [], "units": function_units.call("swordsman", 45)},
			# Marching archer host (mid-road).
			{"id": 2, "owner_faction_id": 1000, "size": 22, "location_city_id": c1.get("id", 0),
				"dest_city_id": c2.get("id", 0), "path": [c2.get("id", 0)], "march_frac": 0.5,
				"units": function_units.call("archer", 22)},
			# Marching siege train.
			{"id": 3, "owner_faction_id": 1000, "size": 70, "location_city_id": c3.get("id", 0),
				"dest_city_id": c4.get("id", 0), "path": [c4.get("id", 0)], "march_frac": 0.35,
				"units": function_units.call("catapult", 70)},
			# Small idle raider band (low band).
			{"id": 4, "owner_faction_id": 1000, "size": 6, "location_city_id": c5.get("id", 0),
				"dest_city_id": -1, "path": [], "units": function_units.call("militia", 6)},
		],
	}]
