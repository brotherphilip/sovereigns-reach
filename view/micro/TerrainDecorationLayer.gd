extends Node2D
# Static terrain decorations (trees/mountains/rocks/water), split into DecorChunk
# canvas items so the renderer culls off-screen blocks (fast when zoomed in). The
# whole layer also hides below DECOR_MIN_ZOOM — decorations are the heaviest art
# and illegible when tiny, so skipping them keeps zoomed-out smooth too.

const CHUNK: int = 16
const DECOR_MIN_ZOOM: float = 0.55
const DecorChunk = preload("res://view/micro/DecorChunk.gd")

var _camera: Camera2D = null
var _map_w: int = 200
var _map_h: int = 200
var _chunks: Array = []

func _ready() -> void:
	var gs: Vector2i = GameState.get_grid_size()
	_map_w = gs.x
	_map_h = gs.y
	for cy in range(0, _map_h, CHUNK):
		for cx in range(0, _map_w, CHUNK):
			var ch := DecorChunk.new()
			add_child(ch)
			ch.setup(cx, cy, mini(cx + CHUNK, _map_w), mini(cy + CHUNK, _map_h))
			_chunks.append(ch)
	set_process(true)

func set_camera(cam: Camera2D) -> void:
	_camera = cam

func _process(_delta: float) -> void:
	if _camera == null:
		return
	var want_visible: bool = _camera.zoom.x >= DECOR_MIN_ZOOM
	if want_visible != visible:
		visible = want_visible

func refresh() -> void:
	for ch in _chunks:
		ch.queue_redraw()
