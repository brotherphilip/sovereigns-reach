extends SceneTree
# Proof harness for unit AI task handling (idle auto-aggro, attack-move, patrol,
# ranged kiting, formation spread, AI-faction deploy/march).
# Run: godot --headless --script tests/TestUnitAI.gd

const UnitState    = preload("res://simulation/units/UnitState.gd")
const UnitRegistry = preload("res://simulation/units/UnitRegistry.gd")
const AIFaction    = preload("res://simulation/ai/AIFaction.gd")

const CT_ISSUE_MOVE_ORDER = 12

var _gs: Node = null
var _t: int = 0
var _pass := 0
var _fail := 0
var _projectiles: Array = []   # captured EventBus.projectile_fired events

func _init() -> void:
	await process_frame
	_gs = root.get_node_or_null("GameState")
	if _gs == null:
		print("FATAL: no GameState"); quit(1); return
	var eb: Node = root.get_node_or_null("EventBus")
	if eb != null:
		eb.projectile_fired.connect(func(fx, fy, tx, ty, kind):
			_projectiles.append({"fx": fx, "fy": fy, "tx": tx, "ty": ty, "kind": kind}))
	_gs.setup_world(77, 4)
	_test_auto_aggro_and_combat()
	_test_guard_leash_returns_to_post()
	_test_aggressive_stance_no_leash()
	_test_attack_move_chase()
	_test_ranged_kiting()
	_test_ranged_projectile()
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

# ── 1b. A holding unit defends its post and RETURNS after an auto-kill ───────────
# (Predictable troops: a unit left somewhere stays there — it won't wander the map.)

func _test_guard_leash_returns_to_post() -> void:
	print("\n[Guard-post leash: defend + return]")
	_arena(50, 50)
	_gs.add_ai_faction("bandit_king", 54, 50)
	var guard := _mk_player_unit("swordsman", 50, 50, 9051)  # left to hold this post
	var foe := _mk_enemy_unit("armed_peasant", 54, 50, 0)    # wanders into aggro range
	_run(240)   # engage + kill
	ok("holding unit slew the intruder", not foe.get("is_alive", true))
	_run(900)   # time to march back to its post
	var back: int = abs(guard.get("pos_x", 0) - 50) + abs(guard.get("pos_y", 0) - 50)
	ok("the unit returned to its post after the fight (didn't wander off)", back <= 2)

# ── 1c. AGGRESSIVE stance pursues — it does NOT leash back to its post ───────────

func _test_aggressive_stance_no_leash() -> void:
	print("\n[Aggressive stance: no leash]")
	_arena(50, 50)
	# Both units have chased far from their post (guard at 50,50; now at 65,50) and
	# their target is gone. A GUARD unit marches back; an AGGRESSIVE one holds.
	var guard_u := _mk_player_unit("swordsman", 65, 50, 9061)
	guard_u["guard_x"] = 50; guard_u["guard_y"] = 50
	guard_u["stance"] = UnitState.STANCE_GUARD
	guard_u["auto_aggro"] = true
	guard_u["order"] = UnitState.ORDER_ATTACK
	guard_u["target_id"] = 99999   # no such enemy → "target gone"
	_gs._tick_force_units(_gs.players[0], [guard_u], [], 80, Vector2i(-1, -1))
	ok("guard unit marches back to its post when the foe is gone", guard_u.get("order") == UnitState.ORDER_MOVE)

	var aggr_u := _mk_player_unit("swordsman", 65, 50, 9062)
	aggr_u["guard_x"] = 50; aggr_u["guard_y"] = 50
	aggr_u["stance"] = UnitState.STANCE_AGGRESSIVE
	aggr_u["auto_aggro"] = false   # aggressive units never arm the leash
	aggr_u["order"] = UnitState.ORDER_ATTACK
	aggr_u["target_id"] = 99999
	_gs._tick_force_units(_gs.players[0], [aggr_u], [], 80, Vector2i(-1, -1))
	ok("aggressive unit holds its ground (no leash back to post)", aggr_u.get("order") != UnitState.ORDER_MOVE)

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

# ── 3b. Ranged units loose visible projectiles; melee does not ──────────────────

func _test_ranged_projectile() -> void:
	print("\n[Ranged projectiles]")
	_arena(50, 50)
	_gs.add_ai_faction("bandit_king", 60, 50)
	var archer := _mk_player_unit("archer", 50, 50, 9301)
	var foe := _mk_enemy_unit("settler", 55, 50, 0)   # in range (8), not point-blank
	_projectiles.clear()
	UnitState.issue_attack_order(archer, foe.get("pos_x", 55), foe.get("pos_y", 50), 0)
	_run(120)
	ok("archer loosed at least one arrow", _projectiles.size() > 0)
	if _projectiles.size() > 0:
		var p: Dictionary = _projectiles[0]
		ok("arrow flew from the archer's tile", p["fx"] == 50 and p["fy"] == 50)
		ok("arrow was an 'arrow' (pierce, range<10)", p["kind"] == "arrow")

	# A melee duel must NOT emit projectiles.
	_arena(70, 70)
	_gs.add_ai_faction("bandit_king", 80, 70)
	var sword := _mk_player_unit("swordsman", 70, 70, 9311)
	var foe2 := _mk_enemy_unit("settler", 71, 70, 0)
	_projectiles.clear()
	UnitState.issue_attack_order(sword, foe2.get("pos_x", 71), foe2.get("pos_y", 70), 0)
	_run(120)
	ok("melee swordsman fired no projectiles", _projectiles.is_empty())

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
	# The King's Peace (AIFaction.PLAYER_GRACE_DAYS) blocks sieges against a fresh
	# faction; this test validates the post-grace march, so age the faction past it.
	# Reference the constant directly so a future grace-length change can't re-stale this.
	_gs.ai_factions[0]["days_alive"] = AIFaction.PLAYER_GRACE_DAYS + 10
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
