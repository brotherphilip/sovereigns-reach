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
