extends Node2D
# DEV-ONLY trial (iter203): renders the village_hall procedural model and the painted
# sprite overlay on top, at the true 4x4 iso footprint, for before/after comparison.
# Run: godot res://view/micro/_SpriteTrial.tscn  (SR_SHOT=/path SR_SHOT_DELAY=n to capture)
const BuildingModels = preload("res://view/micro/BuildingModels.gd")
const BuildingSpriteOverlay = preload("res://view/micro/BuildingSpriteOverlay.gd")

const HALF_W := 32.0
const HALF_H := 16.0

func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.38, 0.62, 0.34)
	bg.size = Vector2(1400, 760)
	bg.z_index = -10
	add_child(bg)
	if OS.get_environment("SR_SHOT") != "":
		_shoot(OS.get_environment("SR_SHOT"))

func _process(_d: float) -> void:
	queue_redraw()   # animate (smoke/flag) and pick up the imported texture once ready

func _footprint(cx: float, cy: float, w: int, h: int) -> Array:
	var top   := Vector2(cx,                       cy - HALF_H)
	var right := Vector2(cx + w * HALF_W,          cy + (w - 1) * HALF_H)
	var bot   := Vector2(cx + (w - h) * HALF_W,    cy + (w + h - 1) * HALF_H)
	var left  := Vector2(cx - h * HALF_W,          cy + (h - 1) * HALF_H)
	return [top, right, bot, left]

func _draw() -> void:
	# LEFT: procedural only.   RIGHT: procedural + painted sprite overlay.
	# Configurable so any building can be tuned: SR_TRIAL_BTYPE / SR_TRIAL_W / SR_TRIAL_H.
	var btype := OS.get_environment("SR_TRIAL_BTYPE")
	if btype == "": btype = "village_hall"
	var fw := int(OS.get_environment("SR_TRIAL_W")) if OS.get_environment("SR_TRIAL_W") != "" else 4
	var fh := int(OS.get_environment("SR_TRIAL_H")) if OS.get_environment("SR_TRIAL_H") != "" else 4
	var labelf := ThemeDB.fallback_font
	for variant in range(2):
		var cx := 320.0 + float(variant) * 760.0
		var cy := 300.0
		var fp := _footprint(cx, cy, fw, fh)
		var top: Vector2 = fp[0]; var right: Vector2 = fp[1]; var bot: Vector2 = fp[2]; var left: Vector2 = fp[3]
		# Tile diamond outline so the footprint is visible.
		draw_polyline(PackedVector2Array([top, right, bot, left, top]), Color(1, 1, 1, 0.25), 1.0)
		BuildingModels.draw_finished(self, btype, 0, fw, fh, top, right, bot, left,
			Color(0.82, 0.77, 0.66), Color(0.74, 0.34, 0.24), Color(0.45, 0.32, 0.20),
			Time.get_ticks_msec() * 0.001, 2, 1)
		if variant == 1:
			BuildingSpriteOverlay.draw(self, btype, top, right, bot, left)
		var lbl := "procedural" if variant == 0 else "procedural + painted sprite"
		draw_string(labelf, Vector2(cx - 90, cy + 230), lbl, HORIZONTAL_ALIGNMENT_CENTER, 200, 18, Color.WHITE)

func _shoot(path: String) -> void:
	var d := 2.0
	if OS.get_environment("SR_SHOT_DELAY") != "":
		d = float(OS.get_environment("SR_SHOT_DELAY"))
	await get_tree().create_timer(d).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
	print("[SpriteTrial] saved %s" % path)
	get_tree().quit()
