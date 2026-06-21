extends SceneTree
# Edge-case probe (iter293): what happens when the SEAT population reaches 0 (all villagers dead)?
# Births need a fertile pair, so 0 can't recover that way; there's no population-0 loss condition;
# food isn't consumed at pop 0 (no starvation pressure) and PopularityEngine doesn't read population.
# So is pop 0 a handled loss, or a silent LIMBO (empty seat, no game-over, no recovery)? Measure it.
# Run: godot --headless --script tools/ProbeDepopulation.gd

const TPD: int = 240

func _init() -> void:
	await process_frame
	var gs = root.get_node_or_null("GameState")
	var clock = root.get_node_or_null("SimulationClock")
	if gs == null:
		print("FATAL: no GameState"); quit(1); return
	gs.players.clear(); gs.ai_factions.clear(); gs.citizens.clear()
	gs._grid = null
	gs.setup_world(4242, 8)
	gs.initialize_player(0, "Probe", 100, 100)
	var p: Dictionary = gs.players[0]
	# Stock food + keep popularity comfortable, then WIPE the population (the all-died end-state).
	p["food"] = {"apples": 500, "bread": 200}
	p["popularity"] = 60.0
	gs.citizens.clear()
	p["population"] = 0
	print("[probe] start: population=%d popularity=%.1f is_alive=%s buildings=%d" % [
		int(p.get("population", 0)), float(p.get("popularity", 0.0)), str(p.get("is_alive", true)),
		p.get("buildings", []).size()])

	# Track realm notices (a depopulation message would show up here). Reach EventBus via the
	# autoload NODE (the bare `--script` harness doesn't register autoload global identifiers).
	var eb = root.get_node_or_null("EventBus")
	var notices: Array = []
	var lost := [false]
	var pop_crit := [false]
	if eb != null:
		eb.realm_notice.connect(func(t, _tone): notices.append(t))
		eb.player_realm_lost.connect(func(): lost[0] = true)
		eb.popularity_changed.connect(func(_pid, _o, nv): if nv < 10.0: pop_crit[0] = true)

	# Simulate ~40 game-days at day boundaries.
	clock.current_tick = 0
	for d in range(40):
		for _t in range(TPD):
			clock.current_tick += 1
			gs.simulate_tick(clock.current_tick)
	var pop_now: int = int(p.get("population", 0))
	var living: int = gs.citizens.size()
	print("[probe] after 40 days: population=%d living_citizens=%d popularity=%.1f is_alive=%s" % [
		pop_now, living, float(p.get("popularity", 0.0)), str(p.get("is_alive", true))])
	print("[probe] revolt-loss(<10) fired: %s · player_realm_lost fired: %s" % [str(pop_crit[0]), str(lost[0])])
	print("[probe] realm notices during the run (%d): %s" % [notices.size(), str(notices.slice(0, 8))])
	if pop_now == 0 and living == 0 and not pop_crit[0] and not lost[0]:
		print("[probe] VERDICT: LIMBO — pop 0, no loss fired, no recovery. Empty-seat dead-end.")
	elif living > 0 or pop_now > 0:
		print("[probe] VERDICT: RECOVERED — population came back (%d)." % maxi(pop_now, living))
	else:
		print("[probe] VERDICT: LOSS handled (a loss condition fired).")
	quit(0)
