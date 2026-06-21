extends SceneTree
# Guards the seat-entry tribute RE-PRESENTATION (iter276). EventBus.ai_envoy_sent is a ONE-SHOT
# emit at demand generation, and the DiplomacyPanel lives only in the city HUD — so a tribute
# demand sent while the player was on the WORLD MAP (where they campaign) was never shown and
# silently expired at its 7-day deadline, unanswered. On entering the seat the panel now
# reconstructs any UNFULFILLED, NON-EXPIRED demand via DiplomacySystem.owed_tribute and routes it
# through the normal modal queue. This locks owed_tribute: it must surface live demands and must
# NOT resurrect expired/answered ones, nor leak other players' demands.
# Run: godot --headless --script tests/TestDiplomacyRepresent.gd

const DiplomacySystem = preload("res://simulation/ai/DiplomacySystem.gd")
const TPD: int = 240

var _pass := 0
var _fail := 0

func _init() -> void:
	_run()
	print("\n=== Diplomacy Re-present Results: %d passed, %d failed ===" % [_pass, _fail])
	quit(0 if _fail == 0 else 1)

func ok(label: String, cond: bool) -> void:
	if cond:
		_pass += 1; print("  PASS: %s" % label)
	else:
		_fail += 1; print("  FAIL: %s" % label)

func _run() -> void:
	var now: int = 10000
	var live: int = now + TPD * 7   # a fresh 7-day-deadline demand

	print("\n[owed_tribute surfaces only live, unanswered, this-player demands]")
	var fac := {
		"id": 7, "name": "Ashen Barony", "archetype": "ashen_barony", "threat_level": 60.0,
		"is_alive": true,
		"tribute_demands": [
			{"player_id": 0, "resource": "gold", "amount": 100, "deadline_tick": live, "fulfilled": false},
			{"player_id": 0, "resource": "iron", "amount": 20, "deadline_tick": live, "fulfilled": false},
			{"player_id": 0, "resource": "wood", "amount": 50, "deadline_tick": 5000, "fulfilled": false},   # EXPIRED
			{"player_id": 0, "resource": "stone", "amount": 30, "deadline_tick": live, "fulfilled": true},    # ANSWERED
			{"player_id": 1, "resource": "gold", "amount": 99, "deadline_tick": live, "fulfilled": false},    # other player
		],
	}
	var owed: Dictionary = DiplomacySystem.owed_tribute(fac, 0, now)
	var dm: Dictionary = owed.get("demands", {})
	ok("includes the live gold demand (100)", int(dm.get("gold", 0)) == 100)
	ok("includes the live iron demand (20)", int(dm.get("iron", 0)) == 20)
	ok("EXCLUDES the expired wood demand", not dm.has("wood"))
	ok("EXCLUDES the already-answered stone demand", not dm.has("stone"))
	ok("EXCLUDES another player's demand", dm.size() == 2)
	ok("reports the live deadline", int(owed.get("deadline_tick", 0)) == live)

	print("\n[nothing owed → empty (no spurious re-presentation)]")
	ok("no tribute_demands → empty",
		DiplomacySystem.owed_tribute({"id": 8, "tribute_demands": []}, 0, now).get("demands", {}).is_empty())
	ok("only-EXPIRED demands → empty (not resurrected)",
		DiplomacySystem.owed_tribute({"id": 9, "tribute_demands": [
			{"player_id": 0, "resource": "gold", "amount": 10, "deadline_tick": 100, "fulfilled": false}],
			}, 0, now).get("demands", {}).is_empty())
	ok("only-ANSWERED demands → empty",
		DiplomacySystem.owed_tribute({"id": 10, "tribute_demands": [
			{"player_id": 0, "resource": "gold", "amount": 10, "deadline_tick": live, "fulfilled": true}],
			}, 0, now).get("demands", {}).is_empty())
	ok("a demand AT exactly the deadline tick is still live (>=)",
		not DiplomacySystem.owed_tribute({"id": 11, "tribute_demands": [
			{"player_id": 0, "resource": "gold", "amount": 10, "deadline_tick": now, "fulfilled": false}],
			}, 0, now).get("demands", {}).is_empty())
	ok("a demand one tick PAST the deadline is gone",
		DiplomacySystem.owed_tribute({"id": 12, "tribute_demands": [
			{"player_id": 0, "resource": "gold", "amount": 10, "deadline_tick": now - 1, "fulfilled": false}],
			}, 0, now).get("demands", {}).is_empty())
