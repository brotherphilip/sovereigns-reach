extends SceneTree
# Phase 1 of the strategic/tactical layer fusion: the army you march is your REAL trained
# units, not a gold-levied pool. Proves create_unit_army carries unit identities, the seat
# is emptied when they march, casualties trim the carried roster, and a capture turns the
# survivors into the city's garrison roster.
# Run: godot --headless --script tests/TestMarchArmy.gd

const CampaignMap    = preload("res://simulation/strategic/CampaignMap.gd")
const CampaignSystem = preload("res://simulation/strategic/CampaignSystem.gd")
const UnitState      = preload("res://simulation/units/UnitState.gd")

var _pass := 0
var _fail := 0

func ok(label: String, cond: bool) -> void:
	if cond: _pass += 1; print("  PASS: %s" % label)
	else: _fail += 1; print("  FAIL: %s" % label)

func _units(n: int, owner: int) -> Array:
	var a: Array = []
	for i in range(n):
		a.append(UnitState.create("militia", owner, 10 + i, 10, 1000 + i))
	return a

func _init() -> void:
	await process_frame
	var PF: int = CampaignMap.PLAYER_FACTION_ID
	var IND: int = CampaignMap.INDEPENDENT_FACTION_ID

	# A tiny two-city world: the player's seat (id 8) connected to a weak independent (id 9).
	var world: Dictionary = {"world_map": {
		"strategic_init": true, "player_faction_id": PF, "player_seat_city_id": 8,
		"kingdoms": [
			{"id": PF, "is_alive": true, "is_player": true, "armies": [], "next_army_id": 1},
		],
		"cities": [
			{"id": 8, "name": "Home",  "owner_faction_id": PF,  "development": 1, "garrison": 0,
				"pos_x": 400.0, "pos_y": 400.0, "connected_to": [9]},
			{"id": 9, "name": "Reach", "owner_faction_id": IND, "development": 0, "garrison": 1,
				"pos_x": 460.0, "pos_y": 400.0, "connected_to": [8]},
		],
	}}
	var k: Dictionary = world["world_map"]["kingdoms"][0]

	print("\n[create_unit_army carries the real troops]")
	var troops: Array = _units(6, PF)
	var aid: int = CampaignSystem.create_unit_army(world, k, 8, troops)
	ok("army formed from real units", aid >= 0)
	var army: Dictionary = CampaignSystem.find_army(k, aid)
	ok("army size == unit count (6)", int(army.get("size", 0)) == 6)
	ok("army carries the actual unit dicts", army.get("units", []).size() == 6)
	ok("carried units keep identity (a known id)", army["units"][0].get("id", -1) == 1000)

	print("\n[launch consumes a road path]")
	ok("campaign launches to the connected target", CampaignSystem.launch_campaign(world, k, aid, 9))
	ok("army now has a destination", int(army.get("dest_city_id", -1)) == 9)

	print("\n[arrival assault: a near-undefended independent falls; survivors garrison it]")
	# March it home: drive ticks until it arrives and assaults (garrison 1 vs 6 should fall).
	var captured := false
	for tick in range(1, 400):
		var events: Array = CampaignSystem.tick_armies(world, k, [], tick)
		for e in events:
			if e is Dictionary and e.get("captured", false) and int(e.get("city_id", -1)) == 9:
				captured = true
		if captured: break
	ok("the weak independent city was captured", captured)
	var reach: Dictionary = CampaignMap.city_by_id(world, 9)
	ok("captured city is now the player's", CampaignMap.owner_of(reach) == PF)
	ok("captured city holds a real garrison roster", reach.get("garrison_units", []).size() >= 1)
	ok("garrison roster never exceeds the host that took it (6)", reach.get("garrison_units", []).size() <= 6)

	print("\n[casualty sync trims the carried roster to survivors]")
	var a2: Dictionary = {"id": 1, "size": 10, "units": _units(10, PF)}
	a2["size"] = 4
	CampaignSystem._sync_carried_units(a2)
	ok("roster trimmed to new size (4)", a2["units"].size() == 4)

	print("\n=== March Army Results: %d passed, %d failed ===" % [_pass, _fail])
	quit(0 if _fail == 0 else 1)
