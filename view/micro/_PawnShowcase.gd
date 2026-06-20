extends Node2D
# DEV-ONLY: renders a row of villagers/workers at a large scale so the procedural figures
# can be inspected and polished (the play-zoom pawns are too small to judge fine detail).
# Drives the real CitizenLayer by populating GameState.citizens, then scales the layer up.
# Run: godot res://view/micro/_PawnShowcase.tscn  (SR_SHOT=/path SR_SHOT_DELAY=n to capture)
const CitizenLayer  = preload("res://view/micro/CitizenLayer.gd")
const CitizenSystem = preload("res://simulation/world/CitizenSystem.gd")

func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.42, 0.62, 0.36)
	bg.size = Vector2(1400, 760)
	bg.z_index = -10
	add_child(bg)

	# A spread of distinct people: m/f, walking/idle, a builder, an elder, a child.
	var rng := RandomNumberGenerator.new(); rng.seed = 9
	var people: Array = []
	CitizenSystem.spawn(people, 8, 0.0, 0.0, rng, 1)
	# Lay them in a horizontal screen row (tx+ty constant) and vary state/sex/stage.
	var combos := [
		{"sex": "m", "stage": "adult", "role": "peasant", "walk": false},
		{"sex": "f", "stage": "adult", "role": "peasant", "walk": false},
		{"sex": "m", "stage": "adult", "role": "peasant", "walk": true},
		{"sex": "f", "stage": "adult", "role": "peasant", "walk": true},
		{"sex": "m", "stage": "adult", "role": "worker",  "walk": true},
		{"sex": "m", "stage": "old",   "role": "peasant", "walk": false},
		{"sex": "f", "stage": "child", "role": "peasant", "walk": false},
		{"sex": "m", "stage": "adult", "role": "builder", "walk": true},
	]
	for i in people.size():
		var c: Dictionary = people[i]
		var cb: Dictionary = combos[i % combos.size()]
		# tx-ty = i (→ screen X = i·32, a tidy row); tx+ty = 0 (→ screen Y = 0).
		c["x"] = float(i) * 0.5; c["y"] = float(i) * -0.5
		c["is_alive"] = true
		c["sex"] = cb["sex"]; c["stage"] = cb["stage"]; c["role"] = cb["role"]
		c["facing"] = 1.0
		if cb["walk"]:
			c["state"] = "walk"; c["vx"] = 0.04; c["vy"] = 0.0
		else:
			c["state"] = "idle"; c["vx"] = 0.0; c["vy"] = 0.0
		c["id"] = i + 1
	GameState.citizens = people

	var layer := CitizenLayer.new()
	layer.scale = Vector2(6.0, 6.0)
	layer.position = Vector2(90, 470)   # row starts left; feet land mid-canvas
	add_child(layer)

	if OS.get_environment("SR_SHOT") != "":
		_shoot(OS.get_environment("SR_SHOT"))

func _shoot(path: String) -> void:
	var d := 2.0
	if OS.get_environment("SR_SHOT_DELAY") != "":
		d = float(OS.get_environment("SR_SHOT_DELAY"))
	await get_tree().create_timer(d).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
	print("[PawnShowcase] saved %s" % path)
	get_tree().quit()
