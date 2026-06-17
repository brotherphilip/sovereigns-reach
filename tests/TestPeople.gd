extends SceneTree
# Proof harness for the living-population lifecycle: aging/stages, old-age death,
# courtship/pairing, housed couples conceiving and bearing children with inherited
# genetics, housing-capped growth, and the skin-inheritance rules.
# Run: godot --headless --script tests/TestPeople.gd

const PeopleSystem  = preload("res://simulation/world/PeopleSystem.gd")
const CitizenSystem = preload("res://simulation/world/CitizenSystem.gd")
const BuildingRegistry = preload("res://simulation/buildings/BuildingRegistry.gd")

var _pass := 0
var _fail := 0
var _rng := RandomNumberGenerator.new()

func _init() -> void:
	_rng.seed = 99
	_test_stages()
	_test_aging_death()
	_test_pairing()
	_test_birth_and_genetics_links()
	_test_housing_cap()
	_test_population_sustains()
	_test_inherit_skin()
	print("\n=== People Results: %d passed, %d failed ===" % [_pass, _fail])
	quit(0 if _fail == 0 else 1)

func ok(label: String, cond: bool) -> void:
	if cond: _pass += 1; print("  PASS: %s" % label)
	else: _fail += 1; print("  FAIL: %s" % label)

func _person(id: int, sex: String, born_day: int, skin: float = 0.5) -> Dictionary:
	return CitizenSystem.make_citizen(id, 100.0, 100.0, _rng, 0,
		{"sex": sex, "born_day": born_day, "skin": skin})

func _player(rooms_buildings: Array) -> Dictionary:
	return {"buildings": rooms_buildings}

func _hovel() -> Dictionary:
	return {"type": "hovel", "built": true, "is_active": true}

func _test_stages() -> void:
	print("\n[Life stages]")
	ok("age 10 → baby", PeopleSystem.stage_for(10) == "baby")
	ok("age 100 → child", PeopleSystem.stage_for(100) == "child")
	ok("age 240 → adolescent", PeopleSystem.stage_for(240) == "adolescent")
	ok("age 350 → adult", PeopleSystem.stage_for(350) == "adult")
	ok("age 480 → midlife", PeopleSystem.stage_for(480) == "midlife")
	ok("age 560 → old", PeopleSystem.stage_for(560) == "old")
	ok("adult is working age", PeopleSystem.is_working_age({"born_day": -350}, 0))
	ok("child is not working age", not PeopleSystem.is_working_age({"born_day": -100}, 0))

func _test_aging_death() -> void:
	print("\n[Aging & death]")
	var citizens: Array = [_person(1, "m", -650)]   # age 650 > death cap
	PeopleSystem.tick_day(citizens, _player([]), _rng, 0, 100)
	ok("the very old die and are purged", citizens.is_empty())

func _test_pairing() -> void:
	print("\n[Courtship / pairing]")
	var citizens: Array = [_person(1, "m", -300), _person(2, "f", -320)]
	PeopleSystem.tick_day(citizens, _player([_hovel()]), _rng, 0, 100)
	ok("an eligible man and woman pair off",
		int(citizens[0].get("partner_id", -1)) == 2 and int(citizens[1].get("partner_id", -1)) == 1)

func _test_birth_and_genetics_links() -> void:
	print("\n[Birth from a housed couple]")
	var citizens: Array = [_person(1, "m", -300, 0.3), _person(2, "f", -300, 0.7)]
	var player := _player([_hovel(), _hovel()])   # base 8 + 8 rooms
	var nid: int = 100
	var born := false
	for day in range(220):
		nid = PeopleSystem.tick_day(citizens, player, _rng, day, nid)
		for c in citizens:
			if int(c.get("mother_id", -1)) > 0:
				born = true
	ok("the couple bore at least one child", born)
	var baby := {}
	for c in citizens:
		if int(c.get("mother_id", -1)) > 0:
			baby = c
			break
	ok("the child has both parents recorded",
		not baby.is_empty() and int(baby.get("mother_id", -1)) == 2 and int(baby.get("father_id", -1)) == 1)
	ok("the child's skin lies in [0,1]",
		not baby.is_empty() and baby.get("skin", -1.0) >= 0.0 and baby.get("skin", 2.0) <= 1.0)

func _test_housing_cap() -> void:
	print("\n[Housing caps growth]")
	var p0 := _player([])
	ok("base housing only with no homes", PeopleSystem.housing_capacity(p0) == PeopleSystem.BASE_HOUSING)
	var p2 := _player([_hovel(), _hovel()])
	var hovel_rooms: int = int(BuildingRegistry.lookup("hovel").get("rooms", 0))
	ok("each hovel adds its rooms", PeopleSystem.housing_capacity(p2) == PeopleSystem.BASE_HOUSING + 2 * hovel_rooms)
	# Fill to capacity; population must never exceed it via births.
	var citizens: Array = []
	var nid: int = 1
	for i in range(PeopleSystem.housing_capacity(p2)):
		var sex := "m" if i % 2 == 0 else "f"
		citizens.append(_person(nid, sex, -300, 0.5)); nid += 1
	for day in range(120):
		nid = PeopleSystem.tick_day(citizens, p2, _rng, day, nid)
	ok("births never exceed housing capacity", PeopleSystem.living_count(citizens) <= PeopleSystem.housing_capacity(p2))

# A fed, housed realm must SUSTAIN its population over a long run — not collapse mid-game when the
# founding settlers age out. Pre-iter126 the initial settlers were one working-age cohort that died
# together (~a death-wave), collapsing the realm to near-empty by ~day 320. The staggered-age fix
# (CitizenSystem age pyramid) keeps a younger generation always maturing. Guards that regression.
func _test_population_sustains() -> void:
	print("\n[Population sustains over a long run — no founding-cohort collapse (iter126)]")
	var citizens: Array = []
	var rng := RandomNumberGenerator.new(); rng.seed = 7
	var nid: int = CitizenSystem.spawn(citizens, 14, 100.0, 100.0, rng, 1)
	var start: int = PeopleSystem.living_count(citizens)
	var player := _player([_hovel(), _hovel(), _hovel(), _hovel()])  # housed realm (headroom)
	var lowest: int = start
	for day in range(1, 320 + 1):
		nid = PeopleSystem.tick_day(citizens, player, rng, day, nid)
		lowest = mini(lowest, PeopleSystem.living_count(citizens))
	var final_n: int = PeopleSystem.living_count(citizens)
	print("  start=%d  lowest=%d  final=%d" % [start, lowest, final_n])
	ok("population never collapses over 320 days (lowest >= 8)", lowest >= 8)
	ok("population still healthy at day 320 (>= 9)", final_n >= 9)

func _test_inherit_skin() -> void:
	print("\n[Skin inheritance]")
	var in_range := 0
	var outside := 0
	var all_valid := true
	for i in range(400):
		var s: float = PeopleSystem.inherit_skin(0.3, 0.7, _rng)
		if s < 0.0 or s > 1.0:
			all_valid = false
		if s >= 0.3 - 0.001 and s <= 0.7 + 0.001:
			in_range += 1
		else:
			outside += 1
	ok("skin always within [0,1]", all_valid)
	ok("usually within the parents' range", in_range > outside * 3)
	ok("occasionally exceeds the parents' range (rare mutation)", outside > 0)
