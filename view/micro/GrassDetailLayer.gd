extends Node2D
# Overlays fine grass-blade texture onto the green ground tiles (GRASS / VALLEY / MARSH) by
# drawing them once as iso diamonds with the grass_detail shader (multiply blend). The flat
# TerrainChunk underneath supplies the season/biome colour; this adds the turf detail on top.
# Static mesh (built once), GPU-sampled — ~no per-frame cost; off-screen chunks are culled.
# Sits above terrain, below water/decor/buildings (added in that child order).

const HALF_W: float = 32.0
const HALF_H: float = 16.0

# Terrains that read as green ground and get blade detail (not water/rock/road/mountain).
const DETAIL_TERRAIN: Array = [0, 4, 7]   # GRASS, MARSH, VALLEY

func _ready() -> void:
	material = ShaderMaterial.new()
	material.shader = preload("res://view/micro/grass_detail.gdshader")
	material.set_shader_parameter("grass_tex", preload("res://view/micro/textures/grass_detail.png"))
	material.set_shader_parameter("strength", 0.7)   # visible turf detail without over-darkening

func _draw() -> void:
	var gs: Vector2i = GameState.get_grid_size()
	for gy in range(gs.y):
		for gx in range(gs.x):
			if GameState.get_terrain_at(gx, gy) not in DETAIL_TERRAIN:
				continue
			var cx: float = (gx - gy) * HALF_W
			var cy: float = (gx + gy) * HALF_H
			draw_colored_polygon(PackedVector2Array([
				Vector2(cx, cy - HALF_H), Vector2(cx + HALF_W, cy),
				Vector2(cx, cy + HALF_H), Vector2(cx - HALF_W, cy),
			]), Color(1, 1, 1, 1))
