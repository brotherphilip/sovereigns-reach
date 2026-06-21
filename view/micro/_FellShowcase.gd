extends "res://view/micro/TreeLayer.gd"
# DEV-ONLY preview of the felling "theatre": draws one topple at a spread of fixed ages across
# a row (upright → teeter → swing → impact dust + leaf burst → fading log), so the whole arc is
# inspectable in a SINGLE screenshot without timing an animation frame. Used to tune/verify the
# fall FX in TreeLayer._paint_fall.
# Run: godot res://view/micro/_FellShowcase.tscn   (SR_SHOT=/path SR_SHOT_DELAY=n to capture;
#      SR_SEASON=0..3 picks the seasonal foliage palette.)

func _ready() -> void:
	set_process(false)   # don't let the base layer pull sim falls or age anything
	_season = 1
	if OS.get_environment("SR_SEASON") != "":
		_season = clampi(int(OS.get_environment("SR_SEASON")), 0, 3)
	if OS.get_environment("SR_SHOT") != "":
		_shoot(OS.get_environment("SR_SHOT"))

func _draw() -> void:
	draw_rect(Rect2(0, 0, 1600, 420), Color(0.38, 0.62, 0.34))   # grass so foliage reads in-game
	var ages: Array = [0.0, 0.35, 0.70, 1.0, FALL_DUR, FALL_DUR + 0.18,
		FALL_DUR + 0.40, FALL_DUR + 0.75, FALL_DUR + 1.25]
	var labels: Array = ["upright", "teeter", "swing", "near-flat", "IMPACT", "dust",
		"dust", "settling", "fading"]
	for i in ages.size():
		var px: float = 110.0 + float(i) * 165.0
		var py: float = 250.0
		_paint_fall(Vector2(px, py), 7 + i, 11, 1.0, float(ages[i]))
		draw_string(ThemeDB.fallback_font, Vector2(px - 45, py + 48), String(labels[i]),
			HORIZONTAL_ALIGNMENT_CENTER, 110, 13, Color.WHITE)

func _shoot(path: String) -> void:
	var d: float = 1.0
	if OS.get_environment("SR_SHOT_DELAY") != "":
		d = float(OS.get_environment("SR_SHOT_DELAY"))
	await get_tree().create_timer(d).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
	print("[FellShowcase] saved %s" % path)
	get_tree().quit()
