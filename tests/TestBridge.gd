extends SceneTree
# Proof harness for bridge planning: the span auto-reaches the far bank, reports red when
# there's no crossing, and refuses rivers wider than the cap. Run:
#   godot --headless --script tests/TestBridge.gd

const BridgePlanner = preload("res://simulation/world/BridgePlanner.gd")
const WorldGrid     = preload("res://simulation/world/WorldGrid.gd")

const GRASS := 0
const RIVER := 3

var _pass := 0
var _fail := 0

# Minimal grid stub exposing just what BridgePlanner needs.
class MockGrid:
	var w: int
	var h: int
	var terr: Array
	var bld: Array
	func _init(w_: int, h_: int) -> void:
		w = w_; h = h_; terr = []; bld = []
		for y in range(h):
			var row: Array = []
			var brow: Array = []
			for x in range(w):
				row.append(0); brow.append(0)
			terr.append(row); bld.append(brow)
	func in_bounds(x: int, y: int) -> bool:
		return x >= 0 and y >= 0 and x < w and y < h
	func get_terrain(x: int, y: int) -> int:
		return terr[y][x] if in_bounds(x, y) else 0
	func get_building_at(x: int, y: int) -> int:
		return bld[y][x] if in_bounds(x, y) else 0
	func set_t(x: int, y: int, t: int) -> void:
		if in_bounds(x, y): terr[y][x] = t

func _init() -> void:
	_test_valid_crossing()
	_test_no_water()
	_test_too_wide()
	print("\n=== Bridge Results: %d passed, %d failed ===" % [_pass, _fail])
	quit(0 if _fail == 0 else 1)

func ok(label: String, cond: bool) -> void:
	if cond: _pass += 1; print("  PASS: %s" % label)
	else: _fail += 1; print("  FAIL: %s" % label)

# A 2-wide vertical river; anchoring on the land just west should span straight across.
func _test_valid_crossing() -> void:
	print("\n[Valid crossing]")
	var g := MockGrid.new(10, 3)
	for y in range(3):
		g.set_t(4, y, RIVER)
		g.set_t(5, y, RIVER)
	var p := BridgePlanner.plan(g, 3, 1)
	ok("plan is valid", p.get("ok", false))
	ok("spans the two water cells", p.get("cells", []) == [Vector2i(4, 1), Vector2i(5, 1)])
	ok("ends on the far bank", p.get("end", Vector2i.ZERO) == Vector2i(6, 1))
	ok("deck runs anchor→anchor", p.get("deck", []).size() == 4)
	ok("direction is eastward", p.get("dir", Vector2i.ZERO) == Vector2i(1, 0))

# Hovering open grass with no adjacent water is not a crossing → red.
func _test_no_water() -> void:
	print("\n[No water beside anchor]")
	var g := MockGrid.new(10, 3)
	var p := BridgePlanner.plan(g, 0, 0)
	ok("plan is invalid (no river to cross)", not p.get("ok", false))

# A river wider than the cap can't be spanned by one bridge → red.
func _test_too_wide() -> void:
	print("\n[River too wide]")
	var g := MockGrid.new(40, 1)
	for x in range(2, 2 + BridgePlanner.MAX_WATER + 3):
		g.set_t(x, 0, RIVER)
	var p := BridgePlanner.plan(g, 1, 0)
	ok("plan is invalid (over the width cap)", not p.get("ok", false))
