extends Node
# DEV-ONLY building sheet: draws every building type at its REAL iso footprint (so multi-mass
# compositions tuned for a 4×4 keep / 5×5 cathedral read correctly), in a labelled grid, via
# BuildingModels.draw_finished. Renders into an exact-size SubViewport (the project stretch is
# canvas_items @1920×1080, which would otherwise clip a larger sheet).
# Run: godot res://view/micro/_BuildingShowcase.tscn  (SR_SHOT=/path SR_SHOT_DELAY=n to capture)
#   SR_SEASON=0..3   pick a season (snow etc.)
#   SR_ONE=<btype>   render ONE building large & centred for close inspection
const BuildingModels   = preload("res://view/micro/BuildingModels.gd")
const BuildingRegistry = preload("res://simulation/buildings/BuildingRegistry.gd")

const TYPES: Array = [
	"village_hall","keep","guildhall","church","cathedral","market","trading_post","inn","well",
	"hovel","granary","bakery","brewery","mill","dairy_farm","apple_orchard","wheat_farm","hops_farm",
	"pig_farm","blacksmith","armory","armorer","barracks","siege_workshop","tannery","fletcher",
	"crossbow_workshop","poleturner","woodcutter_camp","stone_quarry","iron_mine","pitch_rig",
	"stockpile","apothecary","watchtower","lookout_tower","gatehouse","stone_wall","wooden_palisade","great_tower",
]

const HW := 32.0
const HH := 16.0
const COLS := 6
const CELLW := 380.0
const CELLH := 340.0

class Drawer extends Node2D:
	var season: int = 2
	var one: String = ""
	func _corners(c: Vector2, w: int, h: int) -> Array:
		var c00 := Vector2(0, 0)
		var cW0 := Vector2(w * HW, w * HH)
		var cWH := Vector2((w - h) * HW, (w + h) * HH)
		var c0H := Vector2(-h * HW, h * HH)
		var fc := (c00 + cWH) * 0.5
		var off := c - fc
		return [c00 + off, cW0 + off, cWH + off, c0H + off]   # top,right,bot,left
	func _draw() -> void:
		if one != "" and BuildingRegistry.is_valid_type(one):
			var d: Dictionary = BuildingRegistry.lookup(one)
			var w: int = int(d.get("width", 1)); var h: int = int(d.get("height", 1))
			var cc := _corners(Vector2(360, 380), w, h)
			if BuildingRegistry.is_field(one):
				BuildingModels.draw_field_ground(self, one, cc[0], cc[1], cc[2], cc[3], season, 7)
			BuildingModels.draw_finished(self, one, 0, w, h, cc[0], cc[1], cc[2], cc[3],
				Color(0.74, 0.70, 0.62), Color(0.6, 0.4, 0.3), Color(0.4, 0.3, 0.2), 0.4, season, 7)
			draw_string(ThemeDB.fallback_font, Vector2(150, 690), "%s  (%d×%d)" % [one, w, h],
				HORIZONTAL_ALIGNMENT_CENTER, 420, 20, Color.WHITE)
			return
		for i in TYPES.size():
			var bt: String = TYPES[i]
			var dd: Dictionary = BuildingRegistry.lookup(bt)
			var w2: int = int(dd.get("width", 1)); var h2: int = int(dd.get("height", 1))
			var gx := float(i % COLS)
			var gy := float(i / COLS)
			var cx := 40.0 + gx * CELLW + CELLW * 0.5
			var cy := 80.0 + gy * CELLH + CELLH * 0.44
			var cc := _corners(Vector2(cx, cy), w2, h2)
			if BuildingRegistry.is_field(bt):
				BuildingModels.draw_field_ground(self, bt, cc[0], cc[1], cc[2], cc[3], season, i + 3)
			BuildingModels.draw_finished(self, bt, 0, w2, h2, cc[0], cc[1], cc[2], cc[3],
				Color(0.74, 0.70, 0.62), Color(0.6, 0.4, 0.3), Color(0.4, 0.3, 0.2), 0.4, season, i + 3)
			draw_string(ThemeDB.fallback_font, Vector2(cx - 90, 80.0 + gy * CELLH + CELLH - 16.0),
				"%s  %d×%d" % [bt, w2, h2], HORIZONTAL_ALIGNMENT_CENTER, 180, 13, Color(1, 1, 1))

func _ready() -> void:
	var season := 2
	if OS.get_environment("SR_SEASON") != "":
		season = clampi(int(OS.get_environment("SR_SEASON")), 0, 3)
	var one := OS.get_environment("SR_ONE")
	var rows := int(ceil(TYPES.size() / float(COLS)))
	var W := int(COLS * CELLW) + 80
	var H := int(rows * CELLH) + 160
	if one != "":
		W = 720; H = 760
	var sv := SubViewport.new()
	sv.size = Vector2i(W, H)
	sv.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	sv.transparent_bg = false
	add_child(sv)
	var bg := ColorRect.new()
	bg.color = Color(0.42, 0.60, 0.34)
	bg.size = Vector2(W, H)
	bg.z_index = -10
	sv.add_child(bg)
	var d := Drawer.new()
	d.season = season
	d.one = one
	sv.add_child(d)
	d.queue_redraw()
	if OS.get_environment("SR_SHOT") != "":
		_shoot(sv, OS.get_environment("SR_SHOT"))

func _shoot(sv: SubViewport, path: String) -> void:
	var dly := 2.0
	if OS.get_environment("SR_SHOT_DELAY") != "":
		dly = float(OS.get_environment("SR_SHOT_DELAY"))
	await get_tree().create_timer(dly).timeout
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	sv.get_texture().get_image().save_png(path)
	print("[Showcase] saved %s" % path)
	get_tree().quit()
