extends SceneTree
# Proof harness for ObjectiveSystem (standing forward-looking objectives).
# Run: godot --headless --script tests/TestObjectives.gd

const ObjectiveSystem = preload("res://simulation/core/ObjectiveSystem.gd")

var _pass := 0
var _fail := 0

func _init() -> void:
	_test_definitions()
	_test_individual_completions()
	_test_evaluate_progression()
	_test_build_category_mapping()
	print("\n=== Objectives Results: %d passed, %d failed ===" % [_pass, _fail])
	quit(0 if _fail == 0 else 1)

func ok(label: String, cond: bool) -> void:
	if cond: _pass += 1; print("  PASS: %s" % label)
	else: _fail += 1; print("  FAIL: %s" % label)

func _bld(t: String) -> Dictionary:
	return {"type": t, "built": true}

func _test_definitions() -> void:
	print("\n[Definitions]")
	ok("ordered objective list exists", ObjectiveSystem.OBJECTIVES.size() >= 5)
	var ids := {}
	var well := true
	for o in ObjectiveSystem.OBJECTIVES:
		if not (o.has("id") and o.has("text")): well = false
		ids[o.get("id","")] = true
	ok("each objective has id + text", well)
	ok("ids unique", ids.size() == ObjectiveSystem.OBJECTIVES.size())
	ok("final objective is the 20-minute goal", ObjectiveSystem.OBJECTIVES[-1].get("id") == "rule_to_100")

func _test_individual_completions() -> void:
	print("\n[Individual completion checks]")
	var empty := {"buildings": [], "population": 0}
	ok("found_hall incomplete with no buildings", not ObjectiveSystem.is_complete("found_hall", empty, {}, 1))
	ok("found_hall complete with a hall", ObjectiveSystem.is_complete("found_hall", {"buildings": [_bld("village_hall")]}, {}, 1))
	ok("feed_people needs BOTH orchard and granary",
		not ObjectiveSystem.is_complete("feed_people", {"buildings": [_bld("apple_orchard")]}, {}, 1))
	ok("feed_people complete with orchard + granary",
		ObjectiveSystem.is_complete("feed_people", {"buildings": [_bld("apple_orchard"), _bld("granary")]}, {}, 1))
	ok("grow_village needs population >= 20",
		ObjectiveSystem.is_complete("grow_village", {"population": 20, "buildings": []}, {}, 1)
		and not ObjectiveSystem.is_complete("grow_village", {"population": 19, "buildings": []}, {}, 1))
	ok("survive_winter completes at day 6", ObjectiveSystem.is_complete("survive_winter", empty, {}, 6)
		and not ObjectiveSystem.is_complete("survive_winter", empty, {}, 5))
	ok("ready_for_war complete with a barracks (military)",
		ObjectiveSystem.is_complete("ready_for_war", {"buildings": [_bld("barracks")]}, {}, 1))
	ok("ready_for_war complete with a palisade (defense)",
		ObjectiveSystem.is_complete("ready_for_war", {"buildings": [_bld("wooden_palisade")]}, {}, 1))
	ok("ready_for_war NOT complete with only an orchard",
		not ObjectiveSystem.is_complete("ready_for_war", {"buildings": [_bld("apple_orchard")]}, {}, 1))
	ok("rule_to_100 completes at day 12", ObjectiveSystem.is_complete("rule_to_100", empty, {}, 12)
		and not ObjectiveSystem.is_complete("rule_to_100", empty, {}, 11))
	# Unbuilt sites don't count.
	ok("an unbuilt hall site does NOT satisfy found_hall",
		not ObjectiveSystem.is_complete("found_hall", {"buildings": [{"type": "village_hall", "built": false}]}, {}, 1))

func _test_evaluate_progression() -> void:
	print("\n[evaluate() progression]")
	var world := {}
	var player := {"buildings": [], "population": 0}
	var r0 := ObjectiveSystem.evaluate(player, world, 1)
	ok("starts on the first objective", r0["index"] == 0 and r0["completed"] == 0)
	ok("current text is the hall objective", "Village Hall" in String(r0["text"]))

	# Build a hall → first objective completes, current advances, newly_completed reported.
	player["buildings"] = [_bld("village_hall")]
	var r1 := ObjectiveSystem.evaluate(player, world, 2)
	ok("hall completion advances the index", r1["index"] == 1)
	ok("newly_completed reports the hall objective", r1["newly_completed"].size() == 1)
	ok("completed count rises to 1", r1["completed"] == 1)

	# Re-evaluating without change reports no NEW completions (idempotent).
	var r2 := ObjectiveSystem.evaluate(player, world, 3)
	ok("no double-counting on re-eval", r2["newly_completed"].is_empty() and r2["index"] == 1)

	# Completing a LATER objective out of order still tracks correctly (day>=100).
	var r3 := ObjectiveSystem.evaluate(player, world, 100)
	var got_rule := false
	for o in r3["newly_completed"]:
		if o.get("id") == "rule_to_100": got_rule = true
	# survive_winter (day>=48) and rule_to_100 (day>=100) both complete at day 100.
	ok("day-100 eval completes the time-based objectives", got_rule)

# The HUD auto-opens the build menu on the category each objective needs (iter82).
func _test_build_category_mapping() -> void:
	print("\n[Build-category mapping]")
	var BR = preload("res://simulation/buildings/BuildingRegistry.gd")
	ok("found_hall → CIVIC", ObjectiveSystem.build_category_for("found_hall") == BR.Category.CIVIC)
	ok("feed_people → FOOD", ObjectiveSystem.build_category_for("feed_people") == BR.Category.FOOD)
	ok("grow_village → CIVIC", ObjectiveSystem.build_category_for("grow_village") == BR.Category.CIVIC)
	ok("ready_for_war → DEFENSE", ObjectiveSystem.build_category_for("ready_for_war") == BR.Category.DEFENSE)
	ok("survive_winter → -1 (no build, menu untouched)", ObjectiveSystem.build_category_for("survive_winter") == -1)
	ok("rule_to_100 → -1 (no build)", ObjectiveSystem.build_category_for("rule_to_100") == -1)
	ok("unknown id → -1 (safe)", ObjectiveSystem.build_category_for("nonsense") == -1)
	# Every objective that maps to a category must map to a REAL build tab (0..4).
	var all_valid := true
	for o in ObjectiveSystem.OBJECTIVES:
		var c: int = ObjectiveSystem.build_category_for(o.get("id", ""))
		if c != -1 and (c < 0 or c > int(BR.Category.DEFENSE)): all_valid = false
	ok("all mapped categories are valid tabs", all_valid)
