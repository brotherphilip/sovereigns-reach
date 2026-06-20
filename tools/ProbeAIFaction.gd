extends SceneTree
# Probe the CITY-VIEW AI faction economy (simulation/ai/AIFaction.gd): does it actually build
# woodcutters, PAY wood for buildings, and EARN wood only from staffed producers? Logs its
# building counts + resources + population over time. Run: godot --headless --script tools/ProbeAIFaction.gd
const AIFaction = preload("res://simulation/ai/AIFaction.gd")

func _init() -> void:
	var fac: Dictionary = AIFaction.make_faction(0, "Test House", AIFaction.ARCHETYPE_BANDIT, 100, 100)
	var world: Dictionary = {}
	print("day | wood stone iron | gold | pop | buildings(count by type)")
	for day in range(1, 121):
		AIFaction.tick(fac, world, day * 240)
		if day % 15 == 0 or day == 1:
			var res: Dictionary = fac.get("resources", {})
			var counts: Dictionary = {}
			for b in fac.get("buildings", []):
				var bt: String = b if b is String else (b.get("type","") if b is Dictionary else "")
				counts[bt] = int(counts.get(bt, 0)) + 1
			print("%4d | w=%d s=%d i=%d | gold=%d | pop=%d | %s" % [
				day, int(res.get("wood",0)), int(res.get("stone",0)), int(res.get("iron",0)),
				int(fac.get("gold",0)), int(fac.get("population",0)), str(counts)])
	quit(0)
