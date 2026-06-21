extends SceneTree
# Proof harness for per-citizen survival needs: HP / food / warmth decay at a difficulty-scaled
# burn rate, the unfed and the frozen lose HP and die by name, indoor recovery tops needs up,
# winter bites warmth harder, founders get distinct family names, surnames pass down the father's
# line, and close kin never pair (no inbreeding).
# Run: godot --headless --script tests/TestNeeds.gd

const NeedsSystem      = preload("res://simulation/world/NeedsSystem.gd")
const CitizenSystem    = preload("res://simulation/world/CitizenSystem.gd")
const PeopleSystem     = preload("res://simulation/world/PeopleSystem.gd")
const DifficultySystem = preload("res://simulation/core/DifficultySystem.gd")
const SeasonSystem     = preload("res://simulation/world/SeasonSystem.gd")

var _pass := 0
var _fail := 0
var _rng := RandomNumberGenerator.new()

func _init() -> void:
	_rng.seed = 1234
	DifficultySystem.current = DifficultySystem.Level.NORMAL
	_test_fields_and_names()
	_test_distinct_founder_surnames()
	_test_decay_and_starvation_death()
	_test_cold_death_and_cause()
	_test_indoor_recovery()
	_test_winter_burns_faster()
	_test_comfort_regen()
	_test_surname_inheritance()
	_test_no_inbreeding()
	_test_worker_provisioning_no_spiral()
	print("\n=== Needs Results: %d passed, %d failed ===" % [_pass, _fail])
	quit(0 if _fail == 0 else 1)

func ok(label: String, cond: bool) -> void:
	if cond: _pass += 1; print("  PASS: %s" % label)
	else: _fail += 1; print("  FAIL: %s" % label)

func _alive(citizens: Array) -> int:
	var n := 0
	for c in citizens:
		if c.get("is_alive", false): n += 1
	return n

func _test_fields_and_names() -> void:
	print("\n[Fields & names]")
	var c := CitizenSystem.make_citizen(1, 100.0, 100.0, _rng, 0, {"name": "Aldric", "surname": "Mason"})
	ok("has hp", c.has("hp") and float(c["hp"]) == NeedsSystem.HP_MAX)
	ok("has food in start band", float(c["food"]) >= NeedsSystem.START_MIN and float(c["food"]) <= NeedsSystem.START_MAX)
	ok("has warmth in start band", float(c["warmth"]) >= NeedsSystem.START_MIN)
	ok("full_name joins name + surname", NeedsSystem.full_name(c) == "Aldric Mason")
	var d := CitizenSystem.make_citizen(2, 100.0, 100.0, _rng, 0, {"name": "Bryn"})
	ok("full_name with no surname is just the first name", NeedsSystem.full_name(d) == "Bryn")

func _test_distinct_founder_surnames() -> void:
	print("\n[Founder households]")
	var citizens: Array = []
	CitizenSystem.spawn(citizens, 12, 100.0, 100.0, _rng, 1)
	var seen := {}
	for c in citizens:
		seen[String(c.get("surname", ""))] = true
	ok("12 founders → 12 distinct surnames", seen.size() == 12)
	ok("no founder is unnamed-line", not seen.has(""))

func _test_decay_and_starvation_death() -> void:
	print("\n[Starvation]")
	var c := CitizenSystem.make_citizen(1, 100.0, 100.0, _rng, 0, {"name": "Edmund", "surname": "Baker"})
	c["food"] = 100.0; c["warmth"] = 100.0; c["hp"] = 100.0
	var citizens := [c]
	var player := {"food": {}}   # empty larder → no food to eat
	# Decay food to zero over enough days, then HP should fall and they should die by name.
	var died_name := ""
	for day in range(40):
		var gone := NeedsSystem.tick_day(citizens, player, SeasonSystem.Season.SUMMER, _rng)
		if not gone.is_empty():
			died_name = String(gone[0]["name"])
			break
	ok("an unfed villager eventually dies", died_name == "Edmund Baker")
	ok("the dead are marked not-alive", not c.get("is_alive", true))
	ok("food bottomed out before death", float(c["food"]) <= 0.0)

func _test_cold_death_and_cause() -> void:
	print("\n[Cold]")
	var c := CitizenSystem.make_citizen(1, 100.0, 100.0, _rng, 0, {"name": "Wynn", "surname": "Holt"})
	c["food"] = 100.0; c["warmth"] = 5.0; c["hp"] = 20.0
	var citizens := [c]
	# Warm-but-starving would be "hunger"; here food is full and warmth is gone → "the cold".
	var player := {"food": {"bread": 999}}
	var cause := ""
	for day in range(20):
		var gone := NeedsSystem.tick_day(citizens, player, SeasonSystem.Season.WINTER, _rng)
		if not gone.is_empty():
			cause = String(gone[0]["cause"])
			break
	ok("a frozen villager dies of the cold", cause == "the cold")

func _test_indoor_recovery() -> void:
	print("\n[Indoor recovery]")
	var c := CitizenSystem.make_citizen(1, 100.0, 100.0, _rng, 0, {})
	c["food"] = 10.0; c["warmth"] = 10.0
	# Warmth always recovers at the hearth; food only with a stocked larder.
	NeedsSystem.recover_inside(c, false)
	ok("warmth recovers indoors", float(c["warmth"]) > 10.0)
	ok("food does NOT recover with an empty larder", float(c["food"]) == 10.0)
	NeedsSystem.recover_inside(c, true)
	ok("food recovers indoors when the larder has food", float(c["food"]) > 10.0)

func _test_winter_burns_faster() -> void:
	print("\n[Seasonal warmth burn]")
	var summer := CitizenSystem.make_citizen(1, 100.0, 100.0, _rng, 0, {})
	var winter := CitizenSystem.make_citizen(2, 100.0, 100.0, _rng, 0, {})
	summer["warmth"] = 100.0; winter["warmth"] = 100.0
	summer["food"] = 100.0; winter["food"] = 100.0
	NeedsSystem.tick_day([summer], {"food": {"bread": 9}}, SeasonSystem.Season.SUMMER, _rng)
	NeedsSystem.tick_day([winter], {"food": {"bread": 9}}, SeasonSystem.Season.WINTER, _rng)
	ok("winter drains warmth faster than summer", float(winter["warmth"]) < float(summer["warmth"]))

func _test_comfort_regen() -> void:
	print("\n[HP regen when provided for]")
	var c := CitizenSystem.make_citizen(1, 100.0, 100.0, _rng, 0, {})
	c["food"] = 100.0; c["warmth"] = 100.0; c["hp"] = 40.0
	NeedsSystem.tick_day([c], {"food": {"bread": 9}}, SeasonSystem.Season.SUMMER, _rng)
	ok("a fed, warm villager mends (HP regen)", float(c["hp"]) > 40.0)

func _test_surname_inheritance() -> void:
	print("\n[Lineage]")
	var citizens: Array = []
	var father := CitizenSystem.make_citizen(1, 100.0, 100.0, _rng, 0,
		{"sex": "m", "surname": "Fletcher", "born_day": -300})
	var mother := CitizenSystem.make_citizen(2, 100.0, 100.0, _rng, 0,
		{"sex": "f", "surname": "Webber", "born_day": -300})
	father["partner_id"] = 2; mother["partner_id"] = 1
	mother["pregnant_until"] = 0
	citizens.append(father); citizens.append(mother)
	var player := {"buildings": [{"type": "hovel", "built": true, "is_active": true}]}
	var nid := PeopleSystem.tick_day(citizens, player, _rng, 0, 3)
	ok("a child was born", citizens.size() == 3)
	if citizens.size() == 3:
		ok("child inherits the FATHER's family name", String(citizens[2].get("surname", "")) == "Fletcher")

# Regression for the ×20-speed mass-death bug: a hungry WORKER must stay at their post and be
# provisioned from the realm larder (so food producers don't all abandon their jobs when food
# dips — the death-spiral that wiped whole villages). With an empty larder they get nothing.
func _test_worker_provisioning_no_spiral() -> void:
	print("\n[Worker provisioning — no abandonment spiral]")
	var market := {"id": 1, "type": "market", "grid_x": 50, "grid_y": 50,
		"built": true, "is_active": true, "max_workers": 2, "workers": 1}
	var worker := CitizenSystem.make_citizen(1, 50.0, 51.0, _rng, 0,
		{"born_day": -350, "surname": "Reeve"})   # ~age 350 → working-age adult
	worker["role"] = "worker"; worker["job"] = 1; worker["state"] = "work"
	worker["job_type"] = "trader"; worker["state_ticks"] = 9999   # don't shuffle (null-grid safe)
	worker["food"] = 10.0; worker["warmth"] = 100.0
	var citizens := [worker]
	var fed := {"buildings": [market], "food": {"apples": 500}, "population": 1, "food_ration": 2}
	for i in range(30):
		CitizenSystem.tick(citizens, fed, _rng, i + 1, null, 1.0, false, {})
	ok("a hungry worker is NOT pulled off the job (no abandonment spiral)",
		String(worker.get("role", "")) == "worker" and int(worker.get("job", -1)) == 1)
	ok("an employed worker is provisioned at post (food recovers from the larder)",
		float(worker["food"]) > 10.0)
	# Empty larder → no food to draw → the worker is NOT fed (so a truly food-less realm still starves).
	worker["food"] = 10.0
	var poor := {"buildings": [market], "food": {}, "population": 1, "food_ration": 2}
	for i in range(10):
		CitizenSystem.tick(citizens, poor, _rng, 100 + i, null, 1.0, false, {})
	ok("with an empty larder the worker is NOT fed (food gate holds)", float(worker["food"]) <= 10.0)

func _test_no_inbreeding() -> void:
	print("\n[No inbreeding]")
	# Two siblings (shared parents, same surname) of marrying age must NOT pair.
	var bro := CitizenSystem.make_citizen(10, 100.0, 100.0, _rng, 0,
		{"sex": "m", "surname": "Stone", "born_day": -290})
	var sis := CitizenSystem.make_citizen(11, 100.0, 100.0, _rng, 0,
		{"sex": "f", "surname": "Stone", "born_day": -290})
	bro["mother_id"] = 1; bro["father_id"] = 2
	sis["mother_id"] = 1; sis["father_id"] = 2
	var citizens := [bro, sis]
	PeopleSystem.tick_day(citizens, {"buildings": []}, _rng, 0, 12)
	ok("siblings stay single (no inbreeding)", int(bro.get("partner_id", -1)) == -1 and int(sis.get("partner_id", -1)) == -1)
	# A stranger of a different line CAN pair with one of them.
	var out := CitizenSystem.make_citizen(13, 100.0, 100.0, _rng, 0,
		{"sex": "f", "surname": "Brook", "born_day": -290})
	var c2 := [bro, out]
	PeopleSystem.tick_day(c2, {"buildings": []}, _rng, 0, 14)
	ok("an unrelated villager pairs normally", int(bro.get("partner_id", -1)) == 13)
