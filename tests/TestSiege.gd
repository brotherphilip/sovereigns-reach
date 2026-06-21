extends SceneTree
# End-to-end siege regression — the 20-min goal's core late-game challenge, in code.
# Drives the LIVE GameState autoload through a real run with a hostile faction and verifies
# the WHOLE chain works: the siege assembles (telegraphed), marches, and strikes — and that
# DEFENDING decides the outcome. An undefended seat falls; a prepared one (walls + tower +
# gatehouse → is_siege_ready) survives to Day 100. This is the live confirmation the xdotool
# playtests couldn't reliably reach. ~1.5s headless (iter265: ticks only at day boundaries — the
# siege chain is day-boundary-gated — and skips the per-tick citizen/besieger work it doesn't
# exercise, which had ballooned the runtime to >400s and made the whole suite un-runnable).
# Run: godot --headless --script tests/TestSiege.gd

const BuildingState = preload("res://simulation/buildings/BuildingState.gd")
const AIFaction     = preload("res://simulation/ai/AIFaction.gd")

const TPD: int = 240

var _gs: Node = null
var _sc: Node = null
var _eb: Node = null
var _assembled: int = 0
var _struck: int = 0
var _hall_destroyed: bool = false

var _pass := 0
var _fail := 0

func _init() -> void:
	await process_frame
	_gs = root.get_node_or_null("GameState")
	_sc = root.get_node_or_null("SimulationClock")
	_eb = root.get_node_or_null("EventBus")
	if _gs == null or _sc == null or _eb == null:
		print("FATAL: autoloads not found"); quit(1); return
	_eb.ai_siege_assembling.connect(func(_f, _t, _e): _assembled += 1)
	_eb.ai_siege_struck.connect(func(_f, _t, _d, _dmg): _struck += 1)
	_eb.building_destroyed.connect(func(pid, bid, _c): _note_destroyed(pid, bid))
	_run_all()
	print("\n=== Siege Results: %d passed, %d failed ===" % [_pass, _fail])
	quit(0 if _fail == 0 else 1)

func ok(label: String, cond: bool) -> void:
	if cond: _pass += 1; print("  PASS: %s" % label)
	else: _fail += 1; print("  FAIL: %s" % label)

func _note_destroyed(player_id: int, building_id: int) -> void:
	if player_id != 0:
		return
	for b in _gs.players[0].get("buildings", []):
		if b is Dictionary and int(b.get("id", -1)) == building_id and String(b.get("type", "")) == "village_hall":
			_hall_destroyed = true

func _add(p: Dictionary, t: String, x: int, y: int, id: int) -> void:
	var b: Dictionary = BuildingState.create(t, 0, x, y, id)
	if not b.is_empty():
		b["built"] = true
		p["buildings"].append(b)

# Build a fresh game with a hostile bandit faction; `defended` adds siege-ready defences.
func _setup(defended: bool, two_factions: bool = false) -> Dictionary:
	_gs.players.clear()
	_gs.ai_factions.clear()
	_gs._grid = null
	_gs._next_building_id = 1
	_gs._next_unit_id = 1
	_sc.current_tick = 0
	_assembled = 0
	_struck = 0
	_hall_destroyed = false
	_gs.setup_world(12345, 8)
	_gs.initialize_player(0, "Defender", 50, 50)
	# This is a SIEGE regression — it exercises the AI siege chain + hall HP, NOT the citizen
	# economy. The per-tick citizen/wildlife sims (NeedsSystem, pathfinding, lifecycle, herds —
	# all added since this test was written) had ballooned its runtime ~25s → >400s, making the
	# full suite un-runnable. The siege outcome is INDEPENDENT of them (AI threat = army/gold/days;
	# strikes damage the hall directly), so drop them to keep the test fast with full day-coverage.
	_gs.citizens.clear()
	_gs.wildlife.clear()
	# The siege DAMAGE (assembly → strike → hall HP) is the day-boundary chain this test verifies;
	# the besieger warband that physically marches on the seat (iter264 seat-attackers) is a visual
	# layer whose per-day pathfinding dominated the runtime. _catch_up_mode skips that per-tick AI
	# unit movement (GameState L1307) WITHOUT gating the day-boundary siege block (L1476) — so the
	# siege outcome is identical, far faster. (Verified 9/0 unchanged.)
	_gs._catch_up_mode = true
	var p: Dictionary = _gs.players[0]
	var id := 1
	_add(p, "village_hall", 50, 50, id); id += 1
	_add(p, "apple_orchard", 47, 50, id); id += 1
	_add(p, "granary", 54, 50, id); id += 1
	if defended:
		_add(p, "stone_wall", 52, 50, id); id += 1
		_add(p, "lookout_tower", 53, 50, id); id += 1
		_add(p, "gatehouse", 48, 50, id); id += 1
	_gs.add_ai_faction(AIFaction.ARCHETYPE_BANDIT, 70, 70)
	if two_factions:
		# Mirror the LIVE world (CityViewScene spawns bandit_king + ashen_barony): TWO besiegers
		# deal ~8 strikes over 100 days, which a defended seat must still survive (iter118).
		_gs.add_ai_faction(AIFaction.ARCHETYPE_ASHEN_BARONY, 30, 70)
	# The King's Peace is now 10 sun cycles (PLAYER_GRACE_DAYS=750, iter187). This test exercises
	# the POST-peace siege MECHANICS, so age the hostile factions past the grace — otherwise
	# nothing assembles within the run window and the siege chain is left untested.
	for f in _gs.ai_factions:
		if f is Dictionary:
			f["days_alive"] = AIFaction.PLAYER_GRACE_DAYS
	return p

func _run_days(days: int) -> void:
	# The siege chain (assembly, strikes, hall damage) is ENTIRELY day-boundary-gated in
	# simulate_tick (`tick % TICKS_PER_GAME_DAY == 0`), and the AI assembly counter advances by a
	# full TICKS_PER_DAY per AI tick — so ticking ONLY at the day boundaries reproduces the exact
	# siege outcome while skipping the 239 intra-day ticks/day of per-tick work (citizen/besieger
	# movement, fire ticks…) this test doesn't exercise. That keeps full day-coverage at ~1/240th
	# the tick count — the fix for the runtime that had ballooned to >400s and made the whole suite
	# un-runnable (iter262/265). The siege outcome is verified unchanged vs the per-tick version.
	for d in range(1, days + 1):
		var tk: int = d * TPD
		_sc.current_tick = tk
		_gs.simulate_tick(tk)

func _hall_hp() -> int:
	for b in _gs.players[0].get("buildings", []):
		if b is Dictionary and String(b.get("type", "")) == "village_hall":
			return int(b.get("hp", -1))
	return -1

func _run_all() -> void:
	# Case A — an UNDEFENDED seat: the siege chain fires and the hall ultimately falls.
	print("\n[Undefended seat — the siege is a real threat]")
	_setup(false)
	# Sieges are paced slower now (longer King's Peace + smaller strikes) so an undefended
	# seat takes longer to fall — give the run a wider horizon to prove it still does.
	_run_days(260)
	ok("siege was telegraphed (assembling fired)", _assembled > 0)
	ok("siege landed (a strike connected)", _struck > 0)
	ok("an undefended seat is razed by the siege", _hall_destroyed and _hall_hp() <= 0)

	# Case B — a PREPARED seat (walls + tower + gatehouse): it weathers the siege to Day 100.
	print("\n[Defended seat — preparation wins the 20-minute goal]")
	var p := _setup(true)
	ok("walls + tower + gatehouse read as siege-ready", _gs.is_siege_ready(p))
	_run_days(100)
	ok("the prepared seat is still attacked (strikes land)", _struck > 0)
	ok("the prepared seat SURVIVES to Day 100 (hall stands)", not _hall_destroyed and _hall_hp() > 0)

	# Case C — the LIVE world has TWO besiegers (bandit_king + ashen_barony). A live capstone
	# playtest (iter118) showed a fully siege-ready seat still fell ~day 91 because two siege
	# chains dealt ~8 strikes (8×75=600 > 500 HP) — the taught "build defences" strategy couldn't
	# reach the 20-min goal. With SIEGE_DAMAGE_DEFENDED tuned to 50, a prepared seat must now
	# weather BOTH factions to Day 100. (TestSiege previously only covered one faction.)
	print("\n[Defended seat vs TWO factions — the real live world must be survivable]")
	var p2 := _setup(true, true)
	ok("siege-ready vs two factions", _gs.is_siege_ready(p2))
	_run_days(100)
	ok("two siege chains both strike", _struck > 0)
	ok("a PREPARED seat survives TWO besiegers to Day 100", not _hall_destroyed and _hall_hp() > 0)
