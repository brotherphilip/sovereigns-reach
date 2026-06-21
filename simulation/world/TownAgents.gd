extends RefCounted
# LIVE town roster — the cheap "everything tracker" for AI-owned towns.
#
# The economy already decides, each day, exactly which workers staff which buildings. The problem
# was that decision was thrown away — only the resulting gold/goods survived, so when you looked at
# a town the game had to INVENT people. This records the decision instead: one lightweight agent per
# working soul, tagged with WHAT they're doing and roughly WHERE, plus the idle remainder. It is
# pure bookkeeping over data the economy already produces — O(workers), no pathfinding, no per-tick
# physics — so it stays cheap even across every town, yet it's the ACTUAL state, not a simulation:
# the view reads this same roster to show people where they really are, doing what they're really
# doing, and the live cost/earnings are this roster's activity.
#
# Agent dict: {"act": <ACT_*>, "btype": String, "x": float, "y": float}
#   x,y are world-grid coords (near the town's capital), good enough to place a figure "roughly".

const BuildingRegistry = preload("res://simulation/buildings/BuildingRegistry.gd")

# What an agent is actually doing right now.
const ACT_GATHER  := "gather"    # felling / mining / reaping at a producer (raw goods)
const ACT_PROCESS := "process"   # working raw into goods at a processor (mill, bakery, smith…)
const ACT_TRADE   := "trade"     # market / trading post
const ACT_IDLE    := "idle"      # no post today (no job, or no materials/room to work)

# Raw GATHERERS (stand at the resource) vs PROCESSORS (stand at the workshop) vs traders.
const _GATHERERS: Array = [
	"woodcutter_camp", "apple_orchard", "wheat_farm", "hops_farm", "pig_farm", "dairy_farm",
	"iron_mine", "stone_quarry", "fishing_hut",
]
const _TRADERS: Array = ["market", "trading_post"]

# The activity a worker at this building type is performing.
static func activity_for(btype: String) -> String:
	if btype in _GATHERERS:
		return ACT_GATHER
	if btype in _TRADERS:
		return ACT_TRADE
	return ACT_PROCESS

# A deterministic, stable world position for the building at slot `index` of a town centred on
# (cx, cy) — a loose spiral of rings around the centre, so a town's buildings (and the workers at
# them) read as spread across a settlement rather than stacked on one tile. Stable across days so a
# worker doesn't teleport when re-rostered to the same post.
static func building_pos(cx: float, cy: float, index: int) -> Vector2:
	var ring: int = 1 + index / 6
	var step: int = index % 6
	var ang: float = (float(step) / 6.0) * TAU + float(ring) * 0.7
	var rad: float = 3.0 * float(ring)
	return Vector2(cx + cos(ang) * rad, cy + sin(ang) * rad)

# Append `count` working agents at the building in slot `index`. A small deterministic jitter per
# worker spreads them around the building so a 4-worker farm isn't 4 figures on one pixel.
static func add_workers(agents: Array, btype: String, count: int, index: int, cx: float, cy: float) -> void:
	var base: Vector2 = building_pos(cx, cy, index)
	var act: String = activity_for(btype)
	for i in range(count):
		var a: float = float(i) / float(maxi(1, count)) * TAU
		agents.append({
			"act": act, "btype": btype,
			"x": base.x + cos(a) * 0.8, "y": base.y + sin(a) * 0.8,
		})

# Append `count` idle townsfolk loosely gathered near the town centre (the square / hall).
static func add_idle(agents: Array, count: int, cx: float, cy: float) -> void:
	for i in range(count):
		var ang: float = float(i) * 2.399963   # golden-angle scatter — even, deterministic
		var rad: float = 1.0 + float(i % 5) * 0.5
		agents.append({
			"act": ACT_IDLE, "btype": "",
			"x": cx + cos(ang) * rad, "y": cy + sin(ang) * rad,
		})

# Tally how many agents are doing each activity (for a town's live readout / debugging).
static func activity_counts(agents: Array) -> Dictionary:
	var out: Dictionary = {ACT_GATHER: 0, ACT_PROCESS: 0, ACT_TRADE: 0, ACT_IDLE: 0}
	for a in agents:
		var k: String = String(a.get("act", ACT_IDLE))
		out[k] = int(out.get(k, 0)) + 1
	return out
