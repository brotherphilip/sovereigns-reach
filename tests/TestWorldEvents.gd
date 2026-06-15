extends SceneTree
# Proof harness for WorldEventSystem (data-driven realm events).
# Run: godot --headless --script tests/TestWorldEvents.gd

const WorldEventSystem = preload("res://simulation/world/WorldEventSystem.gd")

var _pass := 0
var _fail := 0

func _init() -> void:
	_test_definitions_valid()
	_test_cooldown()
	_test_event_fires_and_applies()
	_test_effects_are_bounded()
	_test_min_day_gating()
	print("\n=== World Events Results: %d passed, %d failed ===" % [_pass, _fail])
	quit(0 if _fail == 0 else 1)

func ok(label: String, cond: bool) -> void:
	if cond: _pass += 1; print("  PASS: %s" % label)
	else: _fail += 1; print("  FAIL: %s" % label)

func _player() -> Dictionary:
	return {
		"id": 0, "gold": 100, "popularity": 50.0, "prestige": 0.0,
		"resources": {"wood": 100, "stone": 50, "iron": 20},
		"food": {"apples": 100},
	}

func _test_definitions_valid() -> void:
	print("\n[Event definitions]")
	ok("there is a pool of events", WorldEventSystem.EVENTS.size() >= 8)
	var ids := {}
	var all_have_fields := true
	var has_good := false
	var has_bad := false
	for e in WorldEventSystem.EVENTS:
		if not (e.has("id") and e.has("title") and e.has("text") and e.has("tone") and e.has("weight") and e.has("effect")):
			all_have_fields = false
		ids[e.get("id", "")] = true
		if e.get("tone") == "good": has_good = true
		if e.get("tone") == "bad": has_bad = true
	ok("every event has the required fields", all_have_fields)
	ok("event ids are unique", ids.size() == WorldEventSystem.EVENTS.size())
	ok("pool has both good and bad events", has_good and has_bad)

func _test_cooldown() -> void:
	print("\n[Cooldown]")
	var rng := RandomNumberGenerator.new(); rng.seed = 1
	var world := {"last_event_day": 10}
	# Strictly within the cooldown window (day - last < COOLDOWN_DAYS), nothing fires.
	var fired := false
	for d in range(11, 10 + WorldEventSystem.COOLDOWN_DAYS):  # days 11..(last+cooldown-1)
		for _i in range(50):
			if not WorldEventSystem.tick(_player(), world, rng, d).is_empty():
				fired = true
	ok("no event fires during the cooldown window", not fired)
	# Exactly at the cooldown boundary an event becomes possible again.
	var possible := false
	for _i in range(200):
		var w2 := {"last_event_day": 10}
		if not WorldEventSystem.tick(_player(), w2, rng, 10 + WorldEventSystem.COOLDOWN_DAYS).is_empty():
			possible = true
	ok("an event can fire once the cooldown elapses", possible)

func _test_event_fires_and_applies() -> void:
	print("\n[Event fires + applies effect]")
	var rng := RandomNumberGenerator.new(); rng.seed = 42
	var p := _player()
	var world := {}
	var fired_count := 0
	var saw_summary := false
	# Run a long stretch; events should fire periodically.
	for d in range(1, 400):
		var ev := WorldEventSystem.tick(p, world, rng, d)
		if not ev.is_empty():
			fired_count += 1
			if String(ev.get("summary", "")) != "": saw_summary = true
	ok("events fire over time", fired_count > 0)
	ok("a fired event carries a human-readable summary", saw_summary)
	# With ~COOLDOWN spacing over 400 days they shouldn't fire more than once per cooldown.
	ok("events respect roughly the cooldown spacing", fired_count <= 400 / WorldEventSystem.COOLDOWN_DAYS)

func _test_effects_are_bounded() -> void:
	print("\n[Effects are bounded — never below 0 / never instant-revolt]")
	var p := _player()
	# Drain a player to near-zero, then apply every bad effect directly; nothing underflows.
	p["gold"] = 5; p["resources"] = {"wood": 5, "stone": 5, "iron": 5}; p["food"] = {"apples": 5}; p["popularity"] = 11.0
	for e in WorldEventSystem.EVENTS:
		WorldEventSystem._apply_effect(p, e.get("effect", {}))
	ok("gold never negative", int(p.get("gold", -1)) >= 0)
	ok("wood never negative", int(p.get("resources", {}).get("wood", -1)) >= 0)
	ok("food never negative", int(p.get("food", {}).get("apples", -1)) >= 0)
	ok("popularity stays in [0,100]", p.get("popularity", -1.0) >= 0.0 and p.get("popularity", 101.0) <= 100.0)

func _test_min_day_gating() -> void:
	print("\n[min_day gating]")
	# On day 1 only events with min_day <= 1 are eligible; force many rolls and confirm
	# no too-early event id ever appears.
	var rng := RandomNumberGenerator.new(); rng.seed = 7
	var bad := false
	for _i in range(2000):
		var world := {}
		var ev := WorldEventSystem.tick(_player(), world, rng, 1)
		if not ev.is_empty() and int(ev.get("min_day", 0)) > 1:
			bad = true
	ok("no event fires before its min_day", not bad)
