extends SceneTree
const UnitArt = preload("res://view/micro/UnitArt.gd")
const TYPES = ["peasant","scout","monk","merchant","settler","armed_peasant","archer",
	"ladderman","tunneler","militia","crossbowman","pikeman","swordsman","captain",
	"halberdier","battering_ram","catapult","trebuchet","siege_tower","mantlet"]

class Painter extends Node2D:
	const UA = preload("res://view/micro/UnitArt.gd")
	var types: Array
	var cell: Vector2
	var margin: float
	func _draw() -> void:
		# checker bg so we can see sprite bounds + transparency
		for i in range(types.size()):
			var t: String = types[i]
			var team: Color = UA._style(t).get("cloth", Color(0.5,0.4,0.3))
			var feet := Vector2(i * cell.x + cell.x * 0.5, cell.y - margin)
			var u := {"type": t, "order": "idle", "id": i, "is_alive": true,
				"pos_x": 0, "pos_y": 0, "target_x": 1, "target_y": 0, "hp": 1, "max_hp": 1}
			UA.draw_unit(self, feet, u, team, 0.0, 0.0)

func _init() -> void:
	await process_frame
	var cell := Vector2(64, 80)
	var margin := 10.0
	var vp := SubViewport.new()
	vp.size = Vector2i(int(cell.x) * TYPES.size(), int(cell.y))
	vp.transparent_bg = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var p := Painter.new()
	p.types = TYPES; p.cell = cell; p.margin = margin
	vp.add_child(p)
	root.add_child(vp)
	await process_frame
	await process_frame
	var img := vp.get_texture().get_image()
	# composite over a mid-gray so transparency reads in the PNG
	var bg := Image.create(img.get_width(), img.get_height(), false, img.get_format())
	bg.fill(Color(0.45,0.55,0.40))
	bg.blend_rect(img, Rect2i(0,0,img.get_width(),img.get_height()), Vector2i.ZERO)
	bg.save_png("/tmp/atlas.png")
	print(">>> atlas saved %dx%d" % [img.get_width(), img.get_height()])
	quit(0)
