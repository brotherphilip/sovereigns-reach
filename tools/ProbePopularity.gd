extends SceneTree
# Reusable 100-day popularity-trajectory probe (the change.md playtest loop's
# "does the late game drift toward revolt?" question). Drives the REAL GameState
# day boundary — world events, weather, seasons, sieges, services — for a managed
# village and logs popularity over a full 20-minute life.
#
# Run: godot --headless --script tools/ProbePopularity.gd
#
# Setup: a typical managed seat (Hall + Orchard + Granary + 2 Hovels), food
# pre-stocked so starvation noise doesn't mask the popularity drivers we care about
# (food is already a solved problem), plus two rival AI factions for real war
# pressure once the King's Peace lapses (~day 30; sieges assemble over 48 days).

const BuildingState = preload("res://simulation/buildings/BuildingState.gd")
const AIFaction     = preload("res://simulation/ai/AIFaction.gd")

func _bld(p: Dictionary, btype: String, gx: int, gy: int, workers: int) -> void:
	var b: Dictionary = BuildingState.create(btype, 0, gx, gy, 12345 + gx * 7 + gy)
	b["built"] = true
	b["is_active"] = true
	b["workers"] = workers
	p["buildings"].append(b)

func _init() -> void:
	await process_frame
	var gs = root.get_node_or_null("GameState")
	if gs == null:
		print("NO GAMESTATE"); quit(1); return

	gs.setup_world(12345, 8)
	gs.initialize_player(0, "Your Lord", 100, 100)
	var p: Dictionary = gs.players[0]

	# A managed seat.
	_bld(p, "village_hall", 100, 100, 0)
	_bld(p, "apple_orchard", 103, 100, 3)
	_bld(p, "granary", 100, 103, 1)
	_bld(p, "hovel", 98, 100, 0)
	_bld(p, "hovel", 100, 98, 0)
	# Food solved: pre-stock a generous apple buffer so the run never starves.
	p["food"] = {"apples": 2000}

	# Optional: a prepared realm (SR_PROBE_DEFENDED=1) — walls + a tower so the siege
	# morale penalty uses the lighter "defended" path (A/B against the undefended run).
	if OS.get_environment("SR_PROBE_DEFENDED") != "":
		_bld(p, "stone_wall", 102, 102, 0)
		_bld(p, "stone_wall", 98, 102, 0)
		_bld(p, "lookout_tower", 102, 98, 0)
		print("[defended variant: walls + tower built]")

	# Two rivals for real war pressure after the King's Peace.
	gs.add_ai_faction(AIFaction.ARCHETYPE_ASHEN_BARONY, 120, 120)
	gs.add_ai_faction(AIFaction.ARCHETYPE_IRONHAND, 80, 80)

	var TPD: int = 240
	print("day,popularity,food_apples,population")
	var min_pop: float = 100.0
	var min_day: int = 0
	for t in range(1, 100 * TPD + 1):
		gs.simulate_tick(t)
		if t % (TPD) == 0:
			var day: int = t / TPD
			var pop: float = float(p.get("popularity", 50.0))
			if pop < min_pop:
				min_pop = pop; min_day = day
			if day % 5 == 0:
				print("%d,%.1f,%d,%d" % [day, pop, int(p.get("food", {}).get("apples", 0)), int(p.get("population", 0))])
			if pop < 10.0:
				print("REVOLT at day %d (popularity %.1f)" % [day, pop])
				break
	print("MIN popularity over the life: %.1f (day %d)" % [min_pop, min_day])
	print("FINAL popularity: %.1f" % float(p.get("popularity", 50.0)))
	quit(0)
