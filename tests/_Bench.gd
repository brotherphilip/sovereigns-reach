extends SceneTree
const UnitState = preload("res://simulation/units/UnitState.gd")
const TYPES = ["peasant","archer","armed_peasant","militia","crossbowman","pikeman",
	"swordsman","captain","halberdier","ladderman","tunneler","scout","monk","merchant",
	"settler","battering_ram","catapult","trebuchet","siege_tower","mantlet"]
var _layer
var _cam
func _init() -> void:
	await process_frame
	await process_frame
	_cam = Camera2D.new()
	root.add_child(_cam)
	_cam.make_current()
	_layer = preload("res://view/micro/UnitLayer.gd").new()
	root.add_child(_layer)
	_layer.set_camera(_cam)
	await process_frame
	for n in [50, 150, 300]:
		for zoom in [1.0, 0.3]:
			_cam.zoom = Vector2(zoom, zoom)
			_cam.position = Vector2(0, 0)
			var arr := []
			for i in range(n):
				var u: Dictionary = UnitState.create(TYPES[i % TYPES.size()], 0, 100 + (i % 20), 100 + int(i / 20.0), i)
				arr.append(u)
			_layer._player_units = arr
			_layer._ai_units = []
			# warm one frame
			_layer.queue_redraw(); await process_frame
			var t0: int = Time.get_ticks_usec()
			var frames: int = 30
			for f in range(frames):
				_layer.queue_redraw()
				await process_frame
			var dt: float = float(Time.get_ticks_usec() - t0) / 1000.0 / float(frames)
			print(">>> units=%d zoom=%.1f  %.1f ms/frame  (%.0f fps)" % [n, zoom, dt, 1000.0 / maxf(dt, 0.001)])
	quit(0)
