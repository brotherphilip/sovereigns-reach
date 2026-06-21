extends SceneTree
# Perf benchmark for GameState.simulate_tick (iter290). Builds a HEAVY but realistic mid-game seat
# — a developed town (many staffed buildings), a full citizen body, a player garrison, an enemy
# warband on the grid, and wildlife — then times steady-state ticks. Three variants attribute the
# cost: FULL, no-citizens (isolate CitizenSystem), no-units (isolate combat/unit AI). Read-only
# measurement; changes nothing in the game.
# Run: godot --headless --script tools/BenchTick.gd

const CitizenSystem = preload("res://simulation/world/CitizenSystem.gd")
const BuildingState = preload("res://simulation/buildings/BuildingState.gd")
const BuildingRegistry = preload("res://simulation/buildings/BuildingRegistry.gd")
const UnitState = preload("res://simulation/units/UnitState.gd")
const WildlifeSystem = preload("res://simulation/world/WildlifeSystem.gd")

var _gs: Node = null

func _init() -> void:
	await process_frame
	_gs = root.get_node_or_null("GameState")
	if _gs == null:
		print("FATAL: GameState autoload not found"); quit(1); return
	_run()
	quit(0)

func _rng(s: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new(); r.seed = s; return r

# Build a developed town: ~14 staffed building types around the keep.
func _setup(citizen_n: int, player_units: int, enemy_units: int) -> void:
	_gs.players.clear(); _gs.ai_factions.clear(); _gs.citizens.clear(); _gs.wildlife.clear()
	_gs._grid = null
	_gs.setup_world(42, 8)
	_gs.initialize_player(0, "Bench", 100, 100)
	_gs._catch_up_mode = false
	_gs.spectator_mode = false
	var p: Dictionary = _gs.players[0]
	p["resources"] = {"wood": 9999, "stone": 9999, "iron": 9999, "pitch": 0}
	p["gold"] = 9999
	# A developed town's worth of staffed buildings around the keep.
	var plan := ["woodcutter_camp","apple_orchard","wheat_farm","granary","market","bakery",
		"brewery","blacksmith","apothecary","barracks","hovel","hovel","hovel","stone_quarry"]
	var bid: int = 5000
	var i: int = 0
	for bt in plan:
		var defn: Dictionary = BuildingRegistry.lookup(bt)
		if defn.is_empty():
			continue
		var gx: int = 92 + (i % 5) * 3
		var gy: int = 92 + (i / 5) * 3
		var b: Dictionary = BuildingState.create(bt, 0, gx, gy, bid)
		bid += 1; i += 1
		if b.is_empty():
			continue
		b["built"] = true
		b["workers"] = defn.get("max_workers", 0)
		p["buildings"].append(b)
		if _gs._grid != null:
			_gs._grid.set_building_at(gx, gy, b["id"])
	# Citizens around the keep.
	_gs._next_citizen_id = CitizenSystem.spawn(_gs.citizens, citizen_n, 100.0, 100.0, _rng(7), _gs._next_citizen_id)
	# Player garrison.
	var uid: int = 9000
	for u in range(player_units):
		p["units"].append(UnitState.create("swordsman", 0, 100 + (u % 6), 100 + (u / 6), uid)); uid += 1
	# An enemy warband on the grid (exercises the unit-AI/combat path) — aged so it can act.
	if enemy_units > 0:
		var fac := {"id": 1, "name": "Raiders", "is_alive": true, "archetype": "bandit_king",
			"units": [], "siege_assembly": {}, "days_alive": 9999, "threat_level": 80.0}
		for u in range(enemy_units):
			fac["units"].append(UnitState.create("armed_peasant", 1, 110 + (u % 6), 105 + (u / 6), uid)); uid += 1
		_gs.ai_factions.append(fac)

var _warmup: int = 20

func _bench(label: String, ticks: int) -> float:
	# Warm up (lazy init + let citizens settle into homes/jobs), then time the steady state.
	for w in range(_warmup):
		_gs.simulate_tick(w)
	var t0: int = Time.get_ticks_usec()
	for k in range(ticks):
		_gs.simulate_tick(100 + k)
	var dt: int = Time.get_ticks_usec() - t0
	var per: float = float(dt) / float(ticks)
	print("  %-28s %7.1f µs/tick  (%d ticks, %.1f ms total)" % [label, per, ticks, dt / 1000.0])
	return per

func _run() -> void:
	var N: int = 600
	print("\n=== simulate_tick benchmark (heavy mid-game seat) ===")
	_setup(40, 24, 24)
	var pop: int = _gs.citizens.size()
	print("  state: %d citizens, %d buildings, %d player units, %d enemy units" % [
		pop, _gs.players[0].get("buildings", []).size(), _gs.players[0].get("units", []).size(),
		_gs.ai_factions[0].get("units", []).size() if not _gs.ai_factions.is_empty() else 0])
	var full: float = _bench("FULL (cold, 20-tick warmup)", N)
	# A SETTLED town: warm up ~3 game-days so citizens reach homes/jobs and stop thrashing —
	# this is the realistic steady-state cost vs the cold clumped-spawn transient above.
	_setup(40, 24, 24)
	_warmup = 720
	var settled: float = _bench("FULL (settled, 720-tick warmup)", N)
	_warmup = 20
	print("  → settled is %.0f%% of cold (citizen thrash on cold spawn inflates the cold number)" % (settled / full * 100.0))
	_setup(0, 24, 24)
	var no_cit: float = _bench("no citizens", N)
	_setup(40, 0, 0)
	var no_units: float = _bench("no units (player+enemy)", N)
	_setup(40, 24, 24)
	var wl_n: int = _gs.wildlife.size()
	_gs.wildlife.clear()
	var no_wild: float = _bench("no wildlife", N)
	print("  (wildlife herd size was %d — no-wildlife saves %.1f µs/tick)" % [wl_n, maxf(0.0, full - no_wild)])
	print("\n  attribution (rough): citizens ≈ %.1f µs/tick, units ≈ %.1f µs/tick" % [
		maxf(0.0, full - no_cit), maxf(0.0, full - no_units)])
	print("  → at 240 ticks/economic-day, FULL = %.2f ms per game-day of seat sim" % (full * 240.0 / 1000.0))

	# --- Direct per-PHASE timing on the full heavy state (the real attribution) ---
	print("\n=== per-phase timing (heavy state) ===")
	_setup(40, 24, 24)
	var p: Dictionary = _gs.players[0]
	var fac: Dictionary = _gs.ai_factions[0]
	var enemies: Array = _gs._enemies_of_faction()
	for w in range(20): _gs.simulate_tick(w)
	_phase("_tick_player_economy", N, func(t): _gs._tick_player_economy(p, t))
	_phase("CitizenSystem.tick", N, func(t): CitizenSystem.tick(_gs.citizens, p, _gs._citizen_rng, t, _gs._grid, 1.0, true, _gs.world))
	_phase("_tick_player_unit_movement", N, func(t): _gs._tick_player_unit_movement(p, t))
	_phase("_tick_force_units (enemy)", N, func(t): _gs._tick_force_units(fac, fac.get("units", []), enemies, t, Vector2i(-1, -1)))
	print("  wildlife herd size: %d" % _gs.wildlife.size())
	_phase("_gather_wildlife_threats", N, func(_t): _gs._gather_wildlife_threats())
	_phase("WildlifeSystem.tick", N, func(t): _gs._next_animal_id = WildlifeSystem.tick(_gs.wildlife, _gs._gather_wildlife_threats(), _gs._grid, _gs._wildlife_rng, t, _gs._next_animal_id))

func _phase(label: String, ticks: int, fn: Callable) -> void:
	var t0: int = Time.get_ticks_usec()
	for k in range(ticks):
		fn.call(100 + k)
	var per: float = float(Time.get_ticks_usec() - t0) / float(ticks)
	print("  %-30s %7.1f µs/call" % [label, per])
