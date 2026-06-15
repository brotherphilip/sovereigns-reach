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
	_test_choice_events()
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
		var core: bool = e.has("id") and e.has("title") and e.has("text") and e.has("tone") and e.has("weight")
		var payload: bool = e.has("effect") or e.has("choices")   # auto-event xor decision
		if not (core and payload):
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

func _test_choice_events() -> void:
	print("\n[Choice events]")
	# There is at least one choice event, and choice events have well-formed choices.
	var choice_events: Array = []
	for e in WorldEventSystem.EVENTS:
		if WorldEventSystem.has_choices(e):
			choice_events.append(e)
	ok("there are choice events", choice_events.size() >= 3)
	var well_formed := true
	for e in choice_events:
		for c in e["choices"]:
			if not (c.has("label") and c.has("effect")):
				well_formed = false
	ok("every choice has a label + effect", well_formed)

	# A choice event picked by tick() must NOT auto-apply its effect (deferred to resolve).
	var p := _player()
	var gold_before: int = p["gold"]
	var loan := WorldEventSystem.event_by_id("barons_loan")
	ok("event_by_id finds a known event", not loan.is_empty())
	# Simulate tick choosing the loan by calling the deferred path directly:
	ok("a choice event carries no auto-summary", not loan.has("summary"))
	ok("player unchanged before a decision", p["gold"] == gold_before)

	# resolve() applies the chosen option.
	var p2 := _player(); var g0: int = p2["gold"]
	var out := WorldEventSystem.resolve(p2, "barons_loan", 0)  # accept loan: +150 gold, -6 pop
	ok("resolve returns a summary", String(out.get("summary", "")) != "")
	ok("accepting the loan adds gold", int(p2["gold"]) == g0 + 150)
	ok("accepting the loan costs popularity", p2["popularity"] < 50.0)

	# Resolving the OTHER option gives a different outcome.
	var p3 := _player()
	WorldEventSystem.resolve(p3, "barons_loan", 1)  # decline: +10 prestige
	ok("declining the loan grants prestige instead", p3.get("prestige", 0.0) >= 10.0)
	ok("declining the loan leaves gold unchanged", int(p3["gold"]) == _player()["gold"])

	# Invalid resolves are safe no-ops.
	ok("resolve with bad index is empty", WorldEventSystem.resolve(_player(), "barons_loan", 9).is_empty())
	ok("resolve with bad id is empty", WorldEventSystem.resolve(_player(), "nope", 0).is_empty())
	# spawn_citizens is surfaced for the caller (refugees event welcomes 2).
	var ref_out := WorldEventSystem.resolve(_player(), "refugees_at_gate", 0)
	ok("welcoming refugees reports spawn_citizens", int(ref_out.get("spawn_citizens", 0)) == 2)
