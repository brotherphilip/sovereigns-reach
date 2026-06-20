extends SceneTree
# Regression for the iter106 fix: a spectated world-map city must show its troops.
# Strategic battles are abstract (army size vs garrison numbers), so a spectated city used
# to render only villagers — no garrison, no besiegers — making a city you were told was
# "under attack" look empty. enter_spectator_city now spawns the garrison as visible
# defenders and, if a hostile army targets the city, the besiegers at the gates.
# Run: godot --headless --script tests/TestSpectatorTroops.gd

const WorldMapData = preload("res://simulation/world/WorldMapData.gd")
const CampaignMap  = preload("res://simulation/strategic/CampaignMap.gd")

var _gs: Node = null
var _sc: Node = null
var _pass := 0
var _fail := 0

func _init() -> void:
	await process_frame
	_gs = root.get_node_or_null("GameState")
	_sc = root.get_node_or_null("SimulationClock")
	if _gs == null or _sc == null:
		print("FATAL: autoloads not found"); quit(1); return
	_run()
	print("\n=== Spectator Troops Results: %d passed, %d failed ===" % [_pass, _fail])
	quit(0 if _fail == 0 else 1)

func ok(label: String, cond: bool) -> void:
	if cond: _pass += 1; print("  PASS: %s" % label)
	else: _fail += 1; print("  FAIL: %s" % label)

func _first_city_id() -> int:
	for c in _gs.world.get("world_map", {}).get("cities", []):
		if c is Dictionary:
			return int(c.get("id", -1))
	return -1

func _run() -> void:
	print("\n[Spectated city shows its troops]")
	_gs.setup_world(12345, 8)
	_gs.initialize_player(0, "Watcher", 50, 50)
	# Generate the strategic world map the way New Game does, then upgrade it (garrisons etc.).
	_gs.world["world_map"] = WorldMapData.generate(12345)
	ok("strategic layer initialised", _gs.ensure_strategic_initialized())
	var cid: int = _first_city_id()
	ok("found a world-map city", cid >= 0)
	var city: Dictionary = CampaignMap.city_by_id(_gs.world, cid)
	# Cities now START with an empty garrison and raise troops over time (iter187), so model
	# a DEFENDED holding by giving it a garrison — that's the precondition this feature needs
	# (a garrisoned city must render visible defenders when spectated).
	city["garrison"] = 8
	ok("a defended city has a garrison (>=4)", int(city.get("garrison", 0)) >= 4)

	# Spectate it — the garrison should now be VISIBLE defenders (no besiegers yet).
	_gs.enter_spectator_city(cid, 100, 100, 12345)
	var defenders: int = _gs.players[0].get("units", []).size()
	ok("spectated city shows visible garrison defenders", defenders >= 1)
	ok("no besiegers when no army targets the city", _gs.ai_factions.is_empty() and not bool(_gs.world.get("spectator_under_siege", false)))

	# Now a hostile army marches on the city → besiegers should appear at the gates.
	var owner: int = CampaignMap.owner_of(city)
	var injected := false
	for k in CampaignMap.kingdoms(_gs.world):
		if k is Dictionary and int(k.get("id", -1)) != owner:
			k["armies"] = k.get("armies", [])
			k["armies"].append({"id": 1, "size": 40, "dest_city_id": cid, "location_city_id": -1})
			injected = true
			break
	ok("set up a hostile army targeting the city", injected)
	_gs.enter_spectator_city(cid, 100, 100, 12345)
	var besiegers: int = 0
	for f in _gs.ai_factions:
		besiegers += f.get("units", []).size()
	ok("a besieged city shows the attackers at the gates", besiegers >= 1)
	ok("under-siege flag is set", bool(_gs.world.get("spectator_under_siege", false)))
	ok("the garrison still defends alongside", _gs.players[0].get("units", []).size() >= 1)

	# The besiegers should MARCH on the town and FIGHT the garrison — a live battle, not a
	# tableau — so a watcher sees the attack play out (the iter108 "in real time" follow-up).
	var def_before: int = _living(_gs.players[0].get("units", []))
	var bes_before: int = _living_in_factions()
	for tk in range(1, 25 * 240 + 1):
		_sc.current_tick = tk
		_gs.simulate_tick(tk)
	var def_after: int = _living(_gs.players[0].get("units", []))
	var bes_after: int = _living_in_factions()
	ok("the besieging battle is fought (casualties occur)", def_after < def_before or bes_after < bes_before)

func _living(arr: Array) -> int:
	var n: int = 0
	for u in arr:
		if u is Dictionary and u.get("is_alive", false):
			n += 1
	return n

func _living_in_factions() -> int:
	var n: int = 0
	for f in _gs.ai_factions:
		n += _living(f.get("units", []))
	return n
