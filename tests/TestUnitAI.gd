extends SceneTree
# Proof harness for unit AI task handling (idle auto-aggro, attack-move, patrol,
# ranged kiting, formation spread, AI-faction deploy/march).
# Run: godot --headless --script tests/TestUnitAI.gd

const UnitState    = preload("res://simulation/units/UnitState.gd")
const UnitRegistry = preload("res://simulation/units/UnitRegistry.gd")

const CT_ISSUE_MOVE_ORDER = 12

var _gs: Node = null
var _t: int = 0
var _pass := 0
var _fail := 0

func _init() -> void:
	await process_frame
	_gs = root.get_node_or_null("GameState")
	if _gs == null:
		print("FATAL: no GameState"); quit(1); return
	_gs.setup_world(77, 4)
	_test_auto_aggro_and_combat()
	_test_attack_move_chase()
	_test_ranged_kiting()
	_test_patrol_cycle()
	_test_formation_spread()
	_test_ai_faction_march()
	_test_terrain_slows_movement()
	_test_unstick()
	print("\n=== Unit AI Results: %d passed, %d failed ===" % [_pass, _fail])
	quit(0 if _fail == 0 else 1)

func ok(label: String, cond: bool) -> void:
	if cond: _pass += 1; print("  PASS: %s" % label)
	else: _fail += 1; print("  FAIL: %s" % label)

func _run(n: int) -> void:
	for _i in range(n):
		_t += 1
		_gs.simulate_tick(_t)

func _arena(cx: int, cy: int) -> void:
	# Fresh state with an open grass arena so terrain doesn't confound the tests.
	_gs.players = []
	_gs.ai_factions = []
	_gs.citizens = []
	_gs.initialize_player(0, "P", cx, cy)
	_gs.citizens = []  # drop spawned villagers; we only test units
	_gs.prepare_starting_area(cx, cy, 18)

func _mk_player_unit(utype: String, x: int, y: int, uid: int) -> Dictionary:
	var u: Dictionary = UnitState.create(utype, 0, x, y, uid)
	_gs.players[0]["units"].append(u)
	return u

func _mk_enemy_unit(utype: String, x: int, y: int, uid: int) -> Dictionary:
	var fac: Dictionary = _gs.ai_factions[0]
	var u: Dictionary = UnitState.create(utype, fac.get("id", 0), x, y, uid)
	fac["units"].append(u)
	return u

# ── 1. Idle units defend themselves; combat resolves ────────────────────────────

func _test_auto_aggro_and_combat() -> void:
	print("\n[Idle auto-aggro + combat]")
	_arena(50, 50)
	_gs.add_ai_faction("bandit_king", 56, 50)
	var hero := _mk_player_unit("swordsman", 50, 50, 9001)   # idle, no orders
	var foe := _mk_enemy_unit("armed_peasant", 56, 50, 0)    # within aggro radius
	ok("units start idle", hero.get("order", "") == UnitState.ORDER_IDLE)
	_run(720)  # ~3 game-days
	ok("idle hero auto-acquired and fought (left idle/standing)",
		hero.get("order", "") == UnitState.ORDER_ATTACK or not foe.get("is_alive", true))
	ok("the weaker raider was slain in auto-combat", not foe.get("is_alive", true))

# ── 2. Attack-move chases a distant target ──────────────────────────────────────

func _test_attack_move_chase() -> void:
	print("\n[Attack-move chase]")
	_arena(50, 50)
	_gs.add_ai_faction("bandit_king", 50, 50)
	var hero := _mk_player_unit("militia", 50, 50, 9101)
	var foe := _mk_enemy_unit("armed_peasant", 62, 50, 0)   # 12 tiles east
	UnitState.issue_attack_order(hero, 62, 50, 0)
	var start_dx: int = abs(hero.get("pos_x", 0) - 62)
	_run(420)
	var end_dx: int = abs(hero.get("pos_x", 0) - foe.get("pos_x", 62))
	ok("attacker closed the distance to its target", end_dx < start_dx)

# ── 3. Ranged units kite a melee attacker ───────────────────────────────────────

func _test_ranged_kiting() -> void:
	print("\n[Ranged kiting]")
	_arena(50, 50)
	_gs.add_ai_faction("bandit_king", 51, 50)
	var archer := _mk_player_unit("archer", 50, 50, 9201)
	# A passive (attack-0) foe right next to the keep so it neither chases nor
	# rally-marches — isolates the archer's kiting behaviour.
	var foe := _mk_enemy_unit("settler", 51, 50, 0)         # point-blank, harmless
	UnitState.issue_attack_order(archer, 51, 50, 0)
	_run(180)
	var dist: int = maxi(abs(archer.get("pos_x", 0) - foe.get("pos_x", 0)),
		abs(archer.get("pos_y", 0) - foe.get("pos_y", 0)))
	ok("archer backed off from point-blank (dist > 1)", dist > 1)

# ── 4. Patrol loops between waypoints ───────────────────────────────────────────

func _test_patrol_cycle() -> void:
	print("\n[Patrol cycle]")
	_arena(50, 50)
	var scout := _mk_player_unit("scout", 44, 50, 9301)
	UnitState.issue_patrol_order(scout, 44, 50, 50, 50)
	var reached_b := false
	for _k in range(12):
		_run(60)
		if scout.get("patrol_to_b", true) == false:  # flipped after reaching B
			reached_b = true
			break
	ok("patrol reached far waypoint and turned back", reached_b)
	ok("patrolling unit actually moved", scout.get("pos_x", 44) != 44)

# ── 5. Group move fans out into a formation ─────────────────────────────────────

func _test_formation_spread() -> void:
	print("\n[Formation spread]")
	_arena(50, 50)
	var a := _mk_player_unit("swordsman", 48, 50, 9401)
	var b := _mk_player_unit("swordsman", 49, 50, 9402)
	var c := _mk_player_unit("swordsman", 50, 51, 9403)
	for u in [a, b, c]:
		_gs._cmd_issue_move_order({"player_id": 0, "payload":
			{"unit_id": u.get("id"), "target_x": 60, "target_y": 60}})
	var targets: Dictionary = {}
	for u in [a, b, c]:
		targets["%d,%d" % [u.get("target_x"), u.get("target_y")]] = true
	ok("3 units sent to one tile got distinct destinations", targets.size() == 3)

# ── 6. AI raiders deploy and march on the player's seat ─────────────────────────

func _test_ai_faction_march() -> void:
	print("\n[AI faction deploy + march]")
	_arena(50, 50)
	_gs.add_ai_faction("bandit_king", 66, 50)
	var raider := _mk_enemy_unit("militia", 66, 50, 0)   # far from keep (50,50)
	var start_dx: int = abs(raider.get("pos_x", 0) - 50)
	_run(600)
	var end_dx: int = abs(raider.get("pos_x", 0) - 50)
	ok("idle raider marched toward the player's seat", end_dx < start_dx)

# ── Terrain greatly/half slows movement (forest ≈ ½, water ≈ ⅕) ─────────────────

func _test_terrain_slows_movement() -> void:
	print("\n[Terrain-aware movement speed]")
	_arena(45, 50)
	# Three walled corridors (mountain walls) so each mover is FORCED straight
	# through its terrain instead of detouring around the costly tiles.
	for x in range(44, 63):
		# grass corridor at y=47 (walls 46/48)
		_gs._grid.set_terrain(x, 46, 2); _gs._grid.set_terrain(x, 48, 2)
		_gs._grid.set_terrain(x, 47, 0)
		# forest corridor at y=51 (walls 50/52)
		_gs._grid.set_terrain(x, 50, 2); _gs._grid.set_terrain(x, 52, 2)
		_gs._grid.set_terrain(x, 51, 1)
		# water corridor at y=55 (walls 54/56)
		_gs._grid.set_terrain(x, 54, 2); _gs._grid.set_terrain(x, 56, 2)
		_gs._grid.set_terrain(x, 55, 3)
	var g := _mk_player_unit("militia", 45, 47, 9501)
	var f := _mk_player_unit("militia", 45, 51, 9502)
	var w := _mk_player_unit("militia", 45, 55, 9503)
	for u in [g, f, w]:
		_gs._cmd_issue_move_order({"player_id": 0, "payload":
			{"unit_id": u.get("id"), "target_x": 61, "target_y": u.get("pos_y", 0)}})
	_run(900)
	var gd: int = g.get("pos_x", 45) - 45
	var fd: int = f.get("pos_x", 45) - 45
	var wd: int = w.get("pos_x", 45) - 45
	print("  [info] advanced grass=%d forest=%d water=%d (tiles)" % [gd, fd, wd])
	ok("grass mover outpaces forest mover", gd > fd)
	ok("forest mover outpaces water mover", fd > wd)
	ok("water greatly slows (water ≤ ~half of forest)", wd * 2 <= fd + 1)

# ── Stuck units auto-relocate to the nearest free cell ──────────────────────────

func _test_unstick() -> void:
	print("\n[Auto-unstick from a blocked cell]")
	_arena(50, 50)
	var u := _mk_player_unit("swordsman", 50, 50, 9601)
	# Drop a mountain right under the unit — it must escape, not freeze.
	_gs._grid.set_terrain(50, 50, 2)  # MOUNTAIN (impassable)
	ok("unit starts on a now-blocked tile", _gs._tile_blocked_for_foot(50, 50))
	_run(5)
	var on_blocked: bool = _gs._tile_blocked_for_foot(u.get("pos_x", 0), u.get("pos_y", 0))
	ok("stuck unit relocated off the blocked tile", not on_blocked)
	ok("unit actually moved", u.get("pos_x", 50) != 50 or u.get("pos_y", 50) != 50)
