extends Node2D
# DEV-ONLY building sprite-sheet: draws one of each building type at large size in a labeled
# grid via BuildingModels.draw_finished, so per-type shape/colour differences are inspectable.
# Run: godot res://view/micro/_BuildingShowcase.tscn  (SR_SHOT=/path SR_SHOT_DELAY=n to capture)
const BuildingModels = preload("res://view/micro/BuildingModels.gd")

const TYPES: Array = [
	"village_hall","keep","guildhall","church","market","trading_post","inn","well",
	"hovel","granary","bakery","brewery","mill","dairy_farm","apple_orchard","wheat_farm",
	"blacksmith","armory","barracks","siege_workshop","tannery","woodcutter_camp",
	"stone_quarry","iron_mine","watchtower","gatehouse","stone_wall","apothecary",
]

func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.38, 0.62, 0.34)   # grass-ish so roofs read like in-game
	bg.size = Vector2(2000, 1200)
	bg.z_index = -10
	add_child(bg)
	if OS.get_environment("SR_SHOT") != "":
		_shoot(OS.get_environment("SR_SHOT"))

func _draw() -> void:
	var cols := 7
	var cw := 168.0
	var ch := 150.0
	for i in TYPES.size():
		var bt: String = TYPES[i]
		var gx := float(i % cols)
		var gy := float(i / cols)
		var cx := 110.0 + gx * cw
		var cy := 120.0 + gy * ch
		# Iso footprint (1x1) centered at cx,cy.
		var hw := 30.0
		var hh := 15.0
		var top := Vector2(cx, cy - hh)
		var right := Vector2(cx + hw, cy)
		var bot := Vector2(cx, cy + hh)
		var left := Vector2(cx - hw, cy)
		# Bespoke models use their own internal colours; pass neutral placeholders.
		BuildingModels.draw_finished(self, bt, 0, 1, 1, top, right, bot, left,
			Color(0.74, 0.70, 0.62), Color(0.6, 0.4, 0.3), Color(0.4, 0.3, 0.2), 0.4, 2)
		draw_string(ThemeDB.fallback_font, Vector2(cx - 50, cy + 34), bt,
			HORIZONTAL_ALIGNMENT_CENTER, 100, 11, Color.WHITE)

func _shoot(path: String) -> void:
	var d := 2.0
	if OS.get_environment("SR_SHOT_DELAY") != "":
		d = float(OS.get_environment("SR_SHOT_DELAY"))
	await get_tree().create_timer(d).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
	print("[Showcase] saved %s" % path)
	get_tree().quit()
