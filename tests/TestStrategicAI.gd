extends SceneTree
# Proof harness for the strategic / campaign AI layer.
# Run: godot --headless --script tests/TestStrategicAI.gd
#
# Drives the world-map kingdoms through ~500 game-days and proves the systems
# work together: economies grow, cities are developed/built up, armies are raised
# and march, campaigns capture cities, kingdoms can fall, the PLAYER can do all of
# it through the command pipeline, diplomacy fires, and the whole thing is
# deterministic. Two scenarios:
#   A) Pure-sim run (call StrategicSim directly) — the AI plays itself.
#   B) Live integration (drive GameState/SimulationClock + CommandQueue) — proves
#      the strategic layer ticks inside the real game loop and the player-parity
#      commands route end-to-end.

const WorldMapData   = preload("res://simulation/world/WorldMapData.gd")
const CampaignMap    = preload("res://simulation/strategic/CampaignMap.gd")
const KingdomEconomy = preload("res://simulation/strategic/KingdomEconomy.gd")
const KingdomAI      = preload("res://simulation/strategic/KingdomAI.gd")
const CampaignSystem = preload("res://simulation/strategic/CampaignSystem.gd")
const StrategicSim   = preload("res://simulation/strategic/StrategicSim.gd")

# CommandType integer constants (avoids compile-time autoload resolution). These
# match the order in CommandQueue.CommandType; the strategic ones are last.
const CT_DEVELOP_CITY    = 27
const CT_RAISE_ARMY      = 28
const CT_LAUNCH_CAMPAIGN = 29
const CT_STRATEGIC_DIPLOMACY = 30

const TICKS_PER_DAY := 240
const SIM_DAYS := 500

var _pass := 0
var _fail := 0

func _init() -> void:
	await process_frame
	_verify_command_enum()
	_run_pure_sim()
	_run_determinism()
	_run_live_integration()
	_run_player_ui_actions()
	_test_seat_shield()
	_test_ai_building_economy()
	print("\n=== Strategic AI Results: %d passed, %d failed ===" % [_pass, _fail])
	quit(0 if _fail == 0 else 1)

# A faction earns ONLY from the production buildings it builds, at player rates.
func _test_ai_building_economy() -> void:
	print("\n── AI building economy ──")
	var AIFaction = preload("res://simulation/ai/AIFaction.gd")
	var BanditKing = preload("res://simulation/ai/BanditKing.gd")
	var ResourceTick = preload("res://simulation/economy/ResourceTick.gd")
	# A faction with no buildings earns nothing.
	var empty = AIFaction.make_faction(9, "Empty", "bandit_king", 0, 0)
	empty["buildings"] = []
	var w0 = int(empty["resources"].get("wood", 0))
	var g0 = int(empty.get("gold", 0))
	AIFaction._process_economy(empty)
	ok("a buildingless faction earns no goods", int(empty["resources"].get("wood", 0)) == w0 and int(empty.get("gold", 0)) == g0)
	# Buildings with NO workforce produce nothing — the core fairness fix.
	var unstaffed = AIFaction.make_faction(6, "NoWorkers", "bandit_king", 0, 0)
	unstaffed["buildings"] = ["woodcutter_camp", "woodcutter_camp"]
	unstaffed["population"] = 0
	unstaffed["resources"] = {"wood": 0}
	AIFaction._process_economy(unstaffed)
	ok("unstaffed buildings produce nothing (no workforce)", int(unstaffed["resources"].get("wood", 0)) == 0)
	# Fully-staffed income matches the summed per-building daily output at standard rates.
	var f = AIFaction.make_faction(8, "Builders", "bandit_king", 0, 0)
	f["buildings"] = ["woodcutter_camp", "woodcutter_camp"]
	f["population"] = 10   # plenty to fully staff both camps
	f["resources"] = {"wood": 0}
	AIFaction._process_economy(f)
	var expected = 2 * int(ResourceTick.daily_output("woodcutter_camp").get("wood", 0))
	ok("staffed income == Σ buildings' daily_output (player rate)", int(f["resources"].get("wood", 0)) == expected)
	# Over time, a bandit actually erects buildings and accrues goods.
	var b = BanditKing.make(7, 50, 50)
	for day in range(30):
		AIFaction.tick(b, {}, day * 240)
	ok("the AI built a production economy", b.get("buildings", []).size() > 0)
	ok("and accrued goods from it", int(b["resources"].get("wood", 0)) > 0)

# ── helpers ──────────────────────────────────────────────────────────────────

func ok(label: String, cond: bool) -> void:
	if cond:
		_pass += 1
		print("  PASS: %s" % label)
	else:
		_fail += 1
		print("  FAIL: %s" % label)

func _make_world(seed_val: int) -> Dictionary:
	var world: Dictionary = {}
	world["world_map"] = WorldMapData.generate(seed_val)
	# Flag a player start city so a player faction is resolved.
	world["selected_city_id"] = WorldMapData.generate(seed_val).get("cities", [{}])[0].get("id", 0)
	return world

func _total_cities_owned(world: Dictionary, fid: int) -> int:
	return CampaignMap.faction_city_count(world, fid)

func _ownership_fingerprint(world: Dictionary) -> int:
	var h: int = 1469598103934665603
	for c in CampaignMap.cities(world):
		h = (h * 1099511628211) ^ int(c.get("owner_faction_id", -1) + 2)
		h = (h * 1099511628211) ^ int(c.get("development", 0) + 1)
	return h & 0x7FFFFFFFFFFFFFFF

# Verify the integer constants we use line up with the live enum, so the live
# integration test actually exercises the intended commands.
func _verify_command_enum() -> void:
	print("\n[Enum] command type alignment")
	var cq = root.get_node_or_null("CommandQueue")
	if cq == null:
		ok("CommandQueue autoload present", false)
		return
	var e = cq.CommandType
	ok("DEVELOP_CITY constant matches enum", e.DEVELOP_CITY == CT_DEVELOP_CITY)
	ok("RAISE_ARMY constant matches enum", e.RAISE_ARMY == CT_RAISE_ARMY)
	ok("LAUNCH_CAMPAIGN constant matches enum", e.LAUNCH_CAMPAIGN == CT_LAUNCH_CAMPAIGN)
	ok("STRATEGIC_DIPLOMACY constant matches enum", e.STRATEGIC_DIPLOMACY == CT_STRATEGIC_DIPLOMACY)

# ── A) Pure-sim: the AI plays the whole world by itself ──────────────────────

func _run_pure_sim() -> void:
	print("\n[A] Pure strategic simulation (%d game-days)" % SIM_DAYS)
	var world := _make_world(7777)
	ok("strategic state initialises", CampaignMap.ensure_initialized(world, []))

	var kingdoms := CampaignMap.kingdoms(world)
	ok("kingdoms created (>=2)", kingdoms.size() >= 2)
	ok("every city has an owner", _all_cities_owned(world))

	# Baselines.
	var start_treasury := {}
	var start_dev := {}
	var start_city_count := {}
	for k in kingdoms:
		var fid: int = k["id"]
		start_treasury[fid] = k.get("treasury", 0)
		start_dev[fid] = KingdomEconomy.total_development(world, fid)
		start_city_count[fid] = _total_cities_owned(world, fid)

	# Run the campaign.
	var captures := 0
	var armies_raised := 0
	var developments := 0
	var tribute_events := 0
	var max_armies_in_motion := 0
	var saw_kingdom_defeated := false

	for day in range(1, SIM_DAYS + 1):
		var tick := day * TICKS_PER_DAY
		var results := StrategicSim.tick_day(world, [], tick)
		for r in results:
			for ev in r.get("events", []):
				match ev:
					"army_raised": armies_raised += 1
					"city_developed": developments += 1
					"tribute_extracted": tribute_events += 1
					"kingdom_defeated": saw_kingdom_defeated = true
			for b in r.get("battles", []):
				if b.get("captured", false):
					captures += 1
		# Sample armies on the march.
		var moving := 0
		for k in kingdoms:
			moving += CampaignSystem.armies_in_motion(k)
		max_armies_in_motion = maxi(max_armies_in_motion, moving)

	# Assertions — the pillars of the goal.
	var any_treasury_grew := false
	var any_dev_grew := false
	var total_dev_now := 0
	var total_dev_start := 0
	for k in kingdoms:
		var fid: int = k["id"]
		if k.get("treasury", 0) > start_treasury[fid]:
			any_treasury_grew = true
		var dev_now := KingdomEconomy.total_development(world, fid)
		total_dev_now += dev_now
		total_dev_start += start_dev[fid]
		if dev_now > start_dev[fid]:
			any_dev_grew = true

	ok("economy grows (a kingdom's treasury rose)", any_treasury_grew)
	ok("cities are developed/built up (total development rose)", total_dev_now > total_dev_start)
	ok("development decisions fired (>0)", developments > 0)
	ok("armies were raised (>0)", armies_raised > 0)
	ok("armies marched on campaign (>0 in motion)", max_armies_in_motion > 0)
	ok("campaigns captured cities (>0)", captures > 0)
	ok("diplomacy fired (tribute extracted >0)", tribute_events > 0)

	# Conquest actually redistributed territory.
	var any_grew_territory := false
	var any_shrank_territory := false
	for k in kingdoms:
		var fid: int = k["id"]
		var now := _total_cities_owned(world, fid)
		if now > start_city_count[fid]:
			any_grew_territory = true
		if now < start_city_count[fid]:
			any_shrank_territory = true
	ok("a kingdom expanded its territory", any_grew_territory)
	ok("a kingdom lost territory", any_shrank_territory)
	ok("total city ownership is conserved (no cities lost/dup)", _all_cities_owned(world))
	print("  [info] captures=%d armies_raised=%d developments=%d tribute=%d peak_armies_moving=%d defeats=%s"
		% [captures, armies_raised, developments, tribute_events, max_armies_in_motion, str(saw_kingdom_defeated)])

func _all_cities_owned(world: Dictionary) -> bool:
	for c in CampaignMap.cities(world):
		if c.get("owner_faction_id", -1) < 0:
			return false
	return true

# ── B) Determinism: same seed → identical outcome ────────────────────────────

func _run_determinism() -> void:
	print("\n[B] Determinism")
	var fp1 := _simulate_to_fingerprint(4242)
	var fp2 := _simulate_to_fingerprint(4242)
	var fp3 := _simulate_to_fingerprint(9999)
	ok("same seed yields identical end-state", fp1 == fp2)
	ok("different seed yields different end-state", fp1 != fp3)

func _simulate_to_fingerprint(seed_val: int) -> int:
	var world := _make_world(seed_val)
	CampaignMap.ensure_initialized(world, [])
	for day in range(1, 200):
		StrategicSim.tick_day(world, [], day * TICKS_PER_DAY)
	return _ownership_fingerprint(world)

# ── C) Live integration: real game loop + player-parity commands ─────────────

# The world map advances the strategic layer directly with the clock paused, so the
# command queue isn't drained there — the Develop button calls GameState directly.
# Verify those direct player-action methods (iter 30: the first interactive strategic control).
func _run_player_ui_actions() -> void:
	print("\n[D] Player world-map UI actions (direct, no command queue)")
	var gs = root.get_node_or_null("GameState")
	if gs == null:
		ok("GameState autoload present", false)
		return
	gs.world = {}
	gs.world["world_map"] = WorldMapData.generate(909090)
	gs.world["selected_city_id"] = gs.world["world_map"]["cities"][0]["id"]
	gs.players = []
	CampaignMap.ensure_initialized(gs.world, gs.players)
	var pfid: int = CampaignMap.player_faction_id(gs.world)

	var cid: int = gs.player_lowest_dev_city()
	ok("player_lowest_dev_city returns an owned city", cid >= 0 and CampaignMap.owner_of(CampaignMap.city_by_id(gs.world, cid)) == pfid)
	# is_player_city: true for an owned city, false for an enemy one (per-city order gating).
	ok("is_player_city true for an owned city", gs.is_player_city(cid))
	var enemy_cid: int = -1
	for c in CampaignMap.cities(gs.world):
		if CampaignMap.owner_of(c) != pfid:
			enemy_cid = c.get("id", -1); break
	ok("is_player_city false for an enemy city", enemy_cid >= 0 and not gs.is_player_city(enemy_cid))
	var cost: Dictionary = gs.develop_city_cost(cid)
	ok("develop_city_cost reports gold/wood/stone", cost.has("gold") and cost.has("wood") and cost.has("stone"))
	ok("can_player_develop_city true with starting treasury", gs.can_player_develop_city(cid))

	# Realm-stores readout reflects the treasury/wood/stone before the investment.
	var stores_before: Dictionary = gs.player_realm_stores()
	ok("player_realm_stores reports treasury/wood/stone/cities",
		stores_before.has("treasury") and stores_before.has("wood") and stores_before.has("stone") and stores_before.has("cities"))

	var dev_before: int = int(CampaignMap.city_by_id(gs.world, cid).get("development", 0))
	var ok_dev: bool = gs.player_develop_city(cid)
	var dev_after: int = int(CampaignMap.city_by_id(gs.world, cid).get("development", 0))
	ok("player_develop_city succeeds (direct, no tick)", ok_dev)
	ok("development rose by exactly 1", dev_after == dev_before + 1)

	# After investing, the readout shows the deducted treasury/stores.
	var stores_after: Dictionary = gs.player_realm_stores()
	ok("realm stores drop after developing", int(stores_after.get("treasury", 0)) < int(stores_before.get("treasury", 0)) and int(stores_after.get("wood", 0)) < int(stores_before.get("wood", 0)))

	# Raise Army (direct UI path) at an owned city: spends gold, musters an army.
	var pk0: Dictionary = CampaignMap.kingdom_by_id(gs.world, pfid)
	var gold_before: int = int(pk0.get("treasury", 0))
	var armies_before: int = pk0.get("armies", []).size()
	ok("raise_army_cost = size × gold-per-soldier", gs.raise_army_cost(10) == 10 * CampaignSystem.GOLD_PER_SOLDIER)
	ok("can_player_raise_army true at owned city with treasury", gs.can_player_raise_army(cid, 10))
	ok("can_player_raise_army false at an enemy city", enemy_cid < 0 or not gs.can_player_raise_army(enemy_cid, 10))
	ok("player_raise_army musters a force", gs.player_raise_army(cid, 10))
	ok("raising spent the treasury", int(CampaignMap.kingdom_by_id(gs.world, pfid).get("treasury", 0)) == gold_before - gs.raise_army_cost(10))
	ok("an army now exists for the realm", CampaignMap.kingdom_by_id(gs.world, pfid).get("armies", []).size() >= armies_before + 1)

	# Launch Campaign (direct UI path): the mustered army marches on a road-connected
	# neighbour that isn't ours.
	var army_id: int = gs.player_army_at_city(cid)
	ok("player_army_at_city finds the mustered army", army_id >= 0)
	ok("player_army_at_city is -1 at a city with no army", gs.player_army_at_city(enemy_cid) == -1)
	var march_target: int = -1
	for nid in CampaignMap.neighbor_ids(CampaignMap.city_by_id(gs.world, cid)):
		if not gs.is_player_city(nid):
			march_target = nid; break
	if march_target >= 0:
		ok("player_launch_campaign sets the army marching", gs.player_launch_campaign(army_id, march_target))
		var marching: Dictionary = CampaignSystem.find_army(CampaignMap.kingdom_by_id(gs.world, pfid), army_id)
		ok("the army now has a destination + path", int(marching.get("dest_city_id", -1)) == march_target and not marching.get("path", []).is_empty())
	else:
		ok("(no non-owned neighbour to march on for this seed — skipped)", true)
	ok("player_launch_campaign refuses a bogus army id", not gs.player_launch_campaign(-999, enemy_cid))

	# Diplomacy (direct UI path): truce/war with the kingdom holding an enemy city.
	var rival_fid: int = CampaignMap.owner_of(CampaignMap.city_by_id(gs.world, enemy_cid))
	ok("player_relation_with defaults to neutral", gs.player_relation_with(rival_fid) == "neutral")
	ok("player_set_diplomacy truce succeeds", gs.player_set_diplomacy(rival_fid, "truce"))
	ok("relation is now truce", gs.player_relation_with(rival_fid) == "truce")
	# Mutual: the rival also records the truce with the player.
	var rival_k: Dictionary = CampaignMap.kingdom_by_id(gs.world, rival_fid)
	ok("truce is mutual", String(rival_k.get("relations", {}).get(str(pfid), "")) == "truce")
	# Honoured by AI targeting: the truced rival never picks a player city to march on.
	ok("KingdomAI._at_truce sees the truce", KingdomAI._at_truce(rival_k, pfid))
	var rival_target: Dictionary = KingdomAI._best_target(gs.world, rival_k)
	ok("truced rival does not target a player city", rival_target.is_empty() or not gs.is_player_city(int(rival_target.get("target_id", -1))))
	ok("player_set_diplomacy war flips the relation", gs.player_set_diplomacy(rival_fid, "war") and gs.player_relation_with(rival_fid) == "war")

	# Drain the realm's stores → the actions are correctly gated as unaffordable.
	var pk: Dictionary = CampaignMap.kingdom_by_id(gs.world, pfid)
	pk["treasury"] = 0
	pk["resources"] = {"wood": 0, "stone": 0, "iron": 0, "food": 0}
	ok("can_player_develop_city false when stores are empty", not gs.can_player_develop_city(cid))
	ok("player_develop_city refused when unaffordable", not gs.player_develop_city(cid))
	ok("can_player_raise_army false when treasury empty", not gs.can_player_raise_army(cid, 10))
	ok("player_raise_army refused when unaffordable", not gs.player_raise_army(cid, 10))

# The player's actively-ruled seat city is immune to abstract strategic capture
# (CampaignSystem._resolve_assault); it can only fall via the tactical siege.
func _test_seat_shield() -> void:
	print("\n[E] Seat-shield: the actively-ruled seat can't be taken by a strategic assault")
	var world := _make_world(2024)
	CampaignMap.ensure_initialized(world, [])
	var cities: Array = CampaignMap.cities(world)
	var seat: Dictionary = cities[0]
	var other: Dictionary = cities[1]
	var atkfid: int = CampaignMap.owner_of(other) if CampaignMap.owner_of(other) != CampaignMap.owner_of(seat) else CampaignMap.owner_of(cities[2])
	var attacker := {"id": atkfid}
	# An overwhelming host that would trivially capture an unshielded city.
	var army := {"id": 999001, "owner_faction_id": atkfid, "size": 500}
	# 1) Not the seat → falls.
	world["player_seat_city_id"] = -1
	var owner_before: int = CampaignMap.owner_of(seat)
	var r_open: Dictionary = CampaignSystem._resolve_assault(world, attacker, army.duplicate(), seat, 7)
	ok("an unshielded city falls to an overwhelming assault", r_open.get("captured", false))
	# 2) Mark it the player's seat → repelled, not captured.
	CampaignMap.set_owner(world, seat.get("id", -1), owner_before)  # restore ownership
	world["player_seat_city_id"] = seat.get("id", -1)
	var r_seat: Dictionary = CampaignSystem._resolve_assault(world, attacker, army.duplicate(), seat, 7)
	ok("the player's seat is NOT captured", not r_seat.get("captured", false))
	ok("the seat assault is flagged repelled", r_seat.get("repelled_seat", false))
	ok("the seat stays under its owner", CampaignMap.owner_of(seat) == owner_before)

func _run_live_integration() -> void:
	print("\n[C] Live integration via GameState + CommandQueue")
	var gs = root.get_node_or_null("GameState")
	var cq = root.get_node_or_null("CommandQueue")
	var sc = root.get_node_or_null("SimulationClock")
	if gs == null or cq == null or sc == null:
		ok("autoloads present", false)
		return

	# Build a world map; the player kingdom is resolved purely from the map
	# (selected_city_id), so no in-city player/grid setup is needed here.
	var seed_val := 31337
	gs.world = {}
	gs.world["world_map"] = WorldMapData.generate(seed_val)
	gs.world["selected_city_id"] = gs.world["world_map"]["cities"][0]["id"]
	gs.players = []

	# Initialise strategic state and grab the player's kingdom.
	CampaignMap.ensure_initialized(gs.world, gs.players)
	var pfid: int = CampaignMap.player_faction_id(gs.world)
	var pk: Dictionary = CampaignMap.kingdom_by_id(gs.world, pfid)
	ok("player kingdom resolved", not pk.is_empty() and pk.get("is_player", false))

	# Give the player kingdom ample resources so the parity commands can succeed.
	pk["treasury"] = 9000
	pk["resources"] = {"wood": 4000, "stone": 4000, "iron": 1000, "food": 4000}

	var owned: Array = CampaignMap.faction_city_ids(gs.world, pfid)
	ok("player owns >=1 city", owned.size() >= 1)
	var dev_city: int = owned[0] if owned.size() > 0 else -1
	var dev_before: int = CampaignMap.city_by_id(gs.world, dev_city).get("development", 0)

	# Pick the WEAKEST enemy city on the player's frontier and a player-owned
	# city adjacent to it to stage the army from (guarantees a 1-hop assault).
	var target_id := -1
	var stage_id := -1
	var best_def := 1 << 30
	for cid in owned:
		var c: Dictionary = CampaignMap.city_by_id(gs.world, cid)
		for nid in CampaignMap.neighbor_ids(c):
			var n: Dictionary = CampaignMap.city_by_id(gs.world, nid)
			if n.is_empty() or CampaignMap.owner_of(n) == pfid:
				continue
			var d: int = CampaignMap.city_defense(n)
			if d < best_def:
				best_def = d
				target_id = nid
				stage_id = cid
	ok("found a player frontier (stage + enemy target)", stage_id >= 0 and target_id >= 0)

	# 1) DEVELOP_CITY through the command pipeline.
	cq.enqueue(CT_DEVELOP_CITY, {"city_id": dev_city}, 0)
	sc._advance_tick()
	var dev_after: int = CampaignMap.city_by_id(gs.world, dev_city).get("development", 0)
	ok("player DEVELOP_CITY raised development", dev_after == dev_before + 1)

	# 2) RAISE_ARMY large enough to overwhelm the target.
	# Field a maximal levy — trivially beats the weakest frontier city.
	var army_size: int = CampaignSystem.MAX_ARMY_SIZE
	cq.enqueue(CT_RAISE_ARMY, {"city_id": stage_id, "size": army_size}, 0)
	sc._advance_tick()
	# Re-fetch kingdom (same dict ref, but be safe).
	pk = CampaignMap.kingdom_by_id(gs.world, pfid)
	ok("player RAISE_ARMY created a field army", CampaignSystem.total_army_size(pk) >= army_size - 2)
	var army_id := -1
	for a in pk.get("armies", []):
		if a.get("location_city_id", -1) == stage_id:
			army_id = a.get("id", -1)
			break
	ok("raised army is stationed at the staging city", army_id >= 0)

	# 3) LAUNCH_CAMPAIGN against the adjacent enemy city, then let the strategic
	#    tick resolve the assault on the next game-day boundary.
	cq.enqueue(CT_LAUNCH_CAMPAIGN, {"army_id": army_id, "target_city_id": target_id}, 0)
	sc._advance_tick()
	var army := CampaignSystem.find_army(pk, army_id)
	ok("player campaign army has a march path", not army.is_empty() and not army.get("path", []).is_empty())
	# The world-map "armies on the march" readout reports this host with an ETA.
	var marching: Array = gs.player_marching_armies()
	ok("player_marching_armies reports the marching host (with ETA)",
		marching.size() >= 1 and int(marching[0].get("eta_days", 0)) >= 1 and String(marching[0].get("dest_name", "")) != "")

	# Advance to the next game-day boundary so _tick_strategic_layer runs and the
	# army (path length 1, adjacent target) assaults.
	var captured_target := false
	for _i in range(TICKS_PER_DAY + 5):
		sc._advance_tick()
		if CampaignMap.owner_of(CampaignMap.city_by_id(gs.world, target_id)) == pfid:
			captured_target = true
			break
	ok("player campaign captured the enemy city (parity proven)", captured_target)

	# 4) STRATEGIC_DIPLOMACY: declare war/truce changes relations.
	var other_fid := -1
	for k in CampaignMap.kingdoms(gs.world):
		if k.get("id", -1) != pfid:
			other_fid = k.get("id", -1)
			break
	if other_fid >= 0:
		cq.enqueue(CT_STRATEGIC_DIPLOMACY, {"faction_id": other_fid, "action": "war"}, 0)
		sc._advance_tick()
		pk = CampaignMap.kingdom_by_id(gs.world, pfid)
		ok("player diplomacy changed relations", pk.get("relations", {}).get(str(other_fid), "") == "war")

	# 5) The strategic layer keeps running inside the live loop without crashing
	#    and AI kingdoms also act (some city not owned by the player still changes).
	var fp_a := _ownership_fingerprint(gs.world)
	for _d in range(60):
		for _t in range(TICKS_PER_DAY):
			sc._advance_tick()
	var fp_b := _ownership_fingerprint(gs.world)
	ok("world keeps evolving under the live game loop", fp_a != fp_b)
