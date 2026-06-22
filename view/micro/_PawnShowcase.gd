extends Node2D
# DEV-ONLY: a curated gallery of villagers at large scale so the procedural figures + the clear
# male/female distinction can be inspected and polished (play-zoom pawns are too small to judge).
# Drives the real CitizenLayer by populating GameState.citizens, then scales the layer up.
# Top row = men, bottom row = women, each spanning hair/headwear/beard/stage/role variety.
# Run: godot res://view/micro/_PawnShowcase.tscn  (SR_SHOT=/path SR_SHOT_DELAY=n to capture)
const CitizenLayer  = preload("res://view/micro/CitizenLayer.gd")
const CitizenSystem = preload("res://simulation/world/CitizenSystem.gd")

const SC := 4.0
const ORIGIN := Vector2(150.0, 250.0)
const ROW_GAP := 5.6      # in iso (x+y) units → screen-Y gap = ROW_GAP*16*SC

# Each: label + overrides. col index = order; row 0 = men, row 1 = women.
const MEN := [
	{"l": "beard", "force_beard": "full", "force_head": "", "force_hstyle": 0},
	{"l": "stubble", "force_beard": "stubble", "force_head": ""},
	{"l": "long hair", "force_beard": "", "force_head": "", "force_hstyle": 2},
	{"l": "cap", "force_head": "cap", "force_beard": "long"},
	{"l": "hood", "force_head": "hood", "force_beard": ""},
	{"l": "coif", "force_head": "coif", "force_beard": "stubble"},
	{"l": "worker", "role": "worker", "job": "woodcutter", "force_beard": "full"},
	{"l": "builder", "role": "builder", "walk": true},
	{"l": "elder", "stage": "old", "force_beard": "long"},
	{"l": "boy", "stage": "child", "force_head": "cap"},
]
const WOMEN := [
	{"l": "loose", "force_head": "", "force_hstyle": 0, "force_apron": true},
	{"l": "braid", "force_head": "", "force_hstyle": 1, "force_apron": true},
	{"l": "bun", "force_head": "", "force_hstyle": 2, "force_shawl": true},
	{"l": "kerchief", "force_head": "kerchief", "force_apron": true},
	{"l": "coif", "force_head": "coif"},
	{"l": "wimple", "force_head": "wimple", "force_shawl": true},
	{"l": "apron+shawl", "force_head": "", "force_apron": true, "force_shawl": true},
	{"l": "walking", "force_head": "kerchief", "walk": true, "force_apron": true},
	{"l": "elder", "stage": "old", "force_head": "wimple"},
	{"l": "girl", "stage": "child", "force_hstyle": 1},
]

var _labels: Array = []   # [{pos, text}]

func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.42, 0.60, 0.36)
	bg.size = Vector2(1920, 1080)
	bg.z_index = -10
	add_child(bg)

	var people: Array = []
	var rng := RandomNumberGenerator.new(); rng.seed = 7
	var idc := 1
	var rows := [MEN, WOMEN]
	for r in range(rows.size()):
		var rowdef: Array = rows[r]
		for ci in range(rowdef.size()):
			var spec: Dictionary = rowdef[ci]
			var c: Dictionary = {"id": idc, "is_alive": true, "facing": 1.0, "skin": rng.randf_range(0.35, 0.85),
				"hair_color": [Color(0.20,0.13,0.07), Color(0.45,0.28,0.12), Color(0.66,0.50,0.22), Color(0.12,0.10,0.09), Color(0.55,0.20,0.12)][idc % 5],
				"hair_style": 0}
			c["sex"] = "m" if r == 0 else "f"
			c["stage"] = spec.get("stage", "adult")
			c["role"] = spec.get("role", "peasant")
			if spec.has("job"): c["job_type"] = spec["job"]
			for k in ["force_head", "force_beard", "force_hstyle", "force_apron", "force_shawl"]:
				if spec.has(k): c[k] = spec[k]
			# Position: row r, column ci. x-y = ci (→ screen X = ci*32); x+y = r*ROW_GAP.
			var col_i := float(ci)
			var rowv := float(r) * ROW_GAP
			c["x"] = (col_i + rowv) * 0.5
			c["y"] = (rowv - col_i) * 0.5
			if spec.get("walk", false):
				c["state"] = "walk"; c["vx"] = 0.04; c["vy"] = 0.0
			else:
				c["state"] = "idle"; c["vx"] = 0.0; c["vy"] = 0.0
			if c["role"] == "worker":
				c["state"] = "work"; c["work_anim"] = "chop"; c["work_phase"] = ""
			people.append(c)
			# Label position (screen space): layer.position + SC * iso(x,y), nudged below feet.
			var iso := Vector2((c["x"] - c["y"]) * 32.0, (c["x"] + c["y"]) * 16.0)
			_labels.append({"pos": ORIGIN + SC * iso + Vector2(-38, 14), "text": spec["l"]})
			idc += 1
	GameState.citizens = people

	var layer := CitizenLayer.new()
	layer.scale = Vector2(SC, SC)
	layer.position = ORIGIN
	add_child(layer)
	queue_redraw()
	if OS.get_environment("SR_SHOT") != "":
		_shoot(OS.get_environment("SR_SHOT"))

func _process(_d: float) -> void:
	queue_redraw()

func _draw() -> void:
	draw_string(ThemeDB.fallback_font, Vector2(150, 60), "VILLAGERS — top: men · bottom: women",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 26, Color(1, 1, 0.9))
	for lb in _labels:
		draw_string(ThemeDB.fallback_font, lb.pos, lb.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(0.95, 0.95, 0.85))

func _shoot(path: String) -> void:
	var d := 2.0
	if OS.get_environment("SR_SHOT_DELAY") != "":
		d = float(OS.get_environment("SR_SHOT_DELAY"))
	await get_tree().create_timer(d).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
	print("[PawnShowcase] saved %s" % path)
	get_tree().quit()
