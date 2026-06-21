extends SceneTree
# DIAGNOSTIC (iter304): the user watched a SPECTATED city whose buildings lost HP with NO enemies
# visible on the minimap or camera. This probe enters spectator on a city, ticks it, and classifies
# EVERY building-HP decrease by its real cause: FIRE (is_on_fire), a BESIEGER physically in reach, or
# — the bug we're hunting — NO enemy anywhere near (a phantom/invisible hit). Reports weather + the
# besieger roster too, so we can see whether attackers even exist and whether they're near the wall.
# Run: godot --headless --script tools/ProbeSpectatorDamage.gd

func _init() -> void:
	await process_frame
	var gs = root.get_node_or_null("GameState")
	var clock = root.get_node_or_null("SimulationClock")
	if gs == null or clock == null:
		print("FATAL: no GameState/SimulationClock"); quit(1); return
	_run(gs, clock)
	quit(0)

func _living_enemies_near(gs, bx: int, by: int, radius: int) -> int:
	var n: int = 0
	for fac in gs.ai_factions:
		if not (fac is Dictionary):
			continue
		for u in fac.get("units", []):
			if not (u is Dictionary and u.get("is_alive", false)):
				continue
			var dx: int = int(u.get("pos_x", 0)) - bx
			var dy: int = int(u.get("pos_y", 0)) - by
			if dx * dx + dy * dy <= radius * radius:
				n += 1
	return n

func _snapshot(gs) -> Dictionary:
	var m: Dictionary = {}
	if gs.players.is_empty():
		return m
	for b in gs.players[0].get("buildings", []):
		if b is Dictionary:
			m[int(b.get("id", -1))] = int(b.get("hp", 0))
	return m

func _run(gs, clock) -> void:
	gs.players.clear(); gs.ai_factions.clear(); gs.citizens.clear()
	gs.world = {}
	gs._grid = null
	gs.setup_world(12345, 8)
	gs.initialize_player(0, "Watcher", 100, 100)
	gs.ensure_strategic_initialized()

	# Pick a city that is NOT the player's seat to spectate.
	var CM = load("res://simulation/strategic/CampaignMap.gd")
	var seat_fid: int = CM.player_faction_id(gs.world)
	var target_id: int = -1
	for c in CM.cities(gs.world):
		if CM.owner_of(c) != seat_fid:
			target_id = int(c.get("id", -1)); break
	if target_id < 0:
		# fall back to any city
		var cities: Array = CM.cities(gs.world)
		if cities.size() > 0:
			target_id = int(cities[0].get("id", -1))
	print("[probe] spectating city_id=%d" % target_id)
	gs.enter_spectator_city(target_id, 100, 100, 12345)

	print("[probe] spectator_mode=%s  buildings=%d  ai_factions=%d  under_siege=%s" % [
		str(gs.spectator_mode), gs.players[0].get("buildings", []).size(),
		gs.ai_factions.size(), str(gs.world.get("spectator_under_siege", false))])
	var atk := 0
	for fac in gs.ai_factions:
		atk += fac.get("units", []).size()
	print("[probe] besieger units present: %d" % atk)

	var fire_hits := 0
	var besieger_hits := 0
	var phantom_hits := 0   # HP dropped with NO living enemy within 30 tiles AND not on fire
	var phantom_examples: Array = []

	var prev: Dictionary = _snapshot(gs)
	var start: int = clock.current_tick
	for t in range(start + 1, start + 60 * 240 + 1):   # 60 game-days
		clock.current_tick = t
		gs.simulate_tick(t)
		if t % 30 != 0:
			continue
		var cur: Dictionary = _snapshot(gs)
		for b in gs.players[0].get("buildings", []):
			if not b is Dictionary:
				continue
			var bid: int = int(b.get("id", -1))
			var before: int = int(prev.get(bid, -1))
			var after: int = int(cur.get(bid, before))
			if before >= 0 and after < before:
				var on_fire: bool = b.get("is_on_fire", false)
				var near: int = _living_enemies_near(gs, int(b.get("grid_x", 0)), int(b.get("grid_y", 0)), 30)
				if on_fire:
					fire_hits += 1
				elif near > 0:
					besieger_hits += 1
				else:
					phantom_hits += 1
					if phantom_examples.size() < 6:
						phantom_examples.append("day %d: %s @(%d,%d) %d→%d  weather=%d  ai_factions=%d  enemies<30t=%d" % [
							t / 240, String(b.get("type", "")), int(b.get("grid_x", 0)), int(b.get("grid_y", 0)),
							before, after, int(gs.weather.get("current", -1)), gs.ai_factions.size(), near])
		prev = cur

	print("\n=== SPECTATOR (non-besieged) BUILDING-DAMAGE CLASSIFICATION (60 days) ===")
	print("  FIRE hits (is_on_fire):        %d" % fire_hits)
	print("  BESIEGER hits (enemy<30t):     %d" % besieger_hits)
	print("  PHANTOM hits (NO cause!):      %d   <-- the reported bug if > 0" % phantom_hits)
	for ex in phantom_examples:
		print("     • " + ex)

	# ── Scenario B: a BESIEGED spectator — inject a besieger host like _spawn_spectator_military does
	# (id 90, archetype="") with units a short march from the town, and watch whether buildings ever
	# take damage while NO living besieger is within 30 tiles (= an invisible/phantom hit).
	var US = load("res://simulation/units/UnitState.gd")
	var foes: Array = []
	var uid: int = 900000
	for j in range(8):
		# stage ~12 tiles SE of the town centre (100,100), like the real besieger spawn
		foes.append(US.create("armed_peasant", 90, 100 + 8 + (j % 4), 100 + 6 + (j / 4) * 2, uid)); uid += 1
	gs.ai_factions = [{"id": 90, "name": "Probe Host", "archetype": "", "is_alive": true, "units": foes}]
	gs.world["spectator_under_siege"] = true
	var b_fire := 0; var b_bes := 0; var b_phantom := 0
	var b_examples: Array = []
	prev = _snapshot(gs)
	start = clock.current_tick
	for t2 in range(start + 1, start + 30 * 240 + 1):   # 30 game-days
		clock.current_tick = t2
		gs.simulate_tick(t2)
		if t2 % 30 != 0:
			continue
		var cur2: Dictionary = _snapshot(gs)
		for b in gs.players[0].get("buildings", []):
			if not b is Dictionary: continue
			var bid2: int = int(b.get("id", -1))
			var before2: int = int(prev.get(bid2, -1))
			var after2: int = int(cur2.get(bid2, before2))
			if before2 >= 0 and after2 < before2:
				var near2: int = _living_enemies_near(gs, int(b.get("grid_x", 0)), int(b.get("grid_y", 0)), 30)
				if b.get("is_on_fire", false): b_fire += 1
				elif near2 > 0: b_bes += 1
				else:
					b_phantom += 1
					if b_examples.size() < 6:
						b_examples.append("day %d: %s @(%d,%d) %d→%d  ai_units_alive=%d  enemies<30t=%d" % [
							t2 / 240, String(b.get("type", "")), int(b.get("grid_x", 0)), int(b.get("grid_y", 0)),
							before2, after2, _count_alive(gs), near2])
		prev = cur2
	print("\n=== SPECTATOR (BESIEGED, injected host of 8) — 30 days ===")
	print("  FIRE hits:                     %d" % b_fire)
	print("  BESIEGER hits (enemy<30t):     %d" % b_bes)
	print("  PHANTOM hits (NO cause!):      %d   <-- invisible-attacker bug if > 0" % b_phantom)
	for ex in b_examples:
		print("     • " + ex)
	print("=== end ===")

func _count_alive(gs) -> int:
	var n := 0
	for fac in gs.ai_factions:
		for u in fac.get("units", []):
			if u is Dictionary and u.get("is_alive", false): n += 1
	return n
