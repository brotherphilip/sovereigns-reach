extends Node2D
# Dev gallery: every unit type at 2.4x, in idle | walk | attack states.
const UnitArt = preload("res://view/micro/UnitArt.gd")
const TYPES := [
	"peasant","scout","monk","merchant","settler",
	"armed_peasant","archer","ladderman","tunneler","militia",
	"crossbowman","pikeman","swordsman","captain","halberdier",
	"battering_ram","catapult","trebuchet","siege_tower","mantlet",
]
func _ready() -> void:
	if OS.get_environment("SR_SHOT") != "":
		var d := 2.0
		if OS.get_environment("SR_SHOT_DELAY") != "":
			d = float(OS.get_environment("SR_SHOT_DELAY"))
		await get_tree().create_timer(d).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(OS.get_environment("SR_SHOT"))
		print("[UnitPreview] saved")
		get_tree().quit()

func _process(_d): queue_redraw()
func _draw():
	draw_rect(Rect2(0,0,1280,720), Color(0.30,0.46,0.24))
	var t := Time.get_ticks_msec()*0.001
	var cols := 4
	var cw := 300.0; var chh := 168.0; var sc := 2.4
	for i in TYPES.size():
		var col := i % cols
		var row := i / cols
		var base := Vector2(70.0 + col*cw, 110.0 + row*chh)
		var states := ["idle","walk","attack"]
		for j in 3:
			var u := {"id": i*3+j, "type": TYPES[i], "order": states[j],
				"pos_x":0,"pos_y":0,"target_x": (1 if states[j]!="idle" else 0),"target_y":0,
				"hp":8,"max_hp":10,"is_alive":true}
			var team := Color(0.31,0.62,0.95) if j<2 else Color(0.85,0.25,0.22)
			var cell := base + Vector2(j*72.0, 0)
			draw_set_transform(cell, 0.0, Vector2(sc, sc))
			UnitArt.draw_unit(self, Vector2.ZERO, u, team, t, 0.0)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		draw_string(ThemeDB.fallback_font, base + Vector2(-6, 26), TYPES[i],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1,1,0.85))
	draw_string(ThemeDB.fallback_font, Vector2(70,40),
		"Unit Art @2.4x — idle | walk | attack   (blue=player, red=enemy)",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(1,0.95,0.7))
