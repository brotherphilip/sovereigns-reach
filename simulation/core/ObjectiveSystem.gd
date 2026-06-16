extends RefCounted
# Forward-looking objectives — a STANDING sense of direction toward the 20-minute goal.
# Unlike MilestoneSystem (backward-looking "you did X" achievements), these always tell
# the player what to reach for NEXT, in order, all the way to "rule to Day 100". Shown
# as a small persistent HUD panel; each completion also fires a realm_notice.
#
# Data-driven: add an {id, text} entry + an `is_complete` case to grow the arc.

const BuildingRegistry = preload("res://simulation/buildings/BuildingRegistry.gd")

const OBJECTIVES: Array = [
	{"id": "found_hall",     "text": "Found your seat — build a Village Hall."},
	{"id": "feed_people",    "text": "Feed your people — build an Orchard and a Granary."},
	{"id": "grow_village",   "text": "Grow your village to 20 souls — build Hovels to house new families."},
	{"id": "survive_winter", "text": "Endure to Day 48 — stock winter food (orchards reap in autumn; bake bread to keep)."},
	{"id": "ready_for_war",  "text": "Ready your defences — build a Barracks, Wall or Tower."},
	{"id": "rule_to_100",    "text": "Endure — rule your realm to Day 100 (20 minutes)."},
]

# Which build-menu category the player needs for each objective — so the HUD can auto-open
# the build menu on the right tab as objectives advance (generalises the iter81 Civic default).
# Objectives with no associated build (endure-to-day) are absent → the menu is left alone.
const BUILD_CATEGORY: Dictionary = {
	"found_hall":    BuildingRegistry.Category.CIVIC,    # Village Hall
	"feed_people":   BuildingRegistry.Category.FOOD,     # Orchard + Granary
	"grow_village":  BuildingRegistry.Category.CIVIC,    # Hovels
	"ready_for_war": BuildingRegistry.Category.DEFENSE,  # Wall/Tower (survival vs the siege)
}

# The build category an objective points at, or -1 if it needs no building (caller leaves the
# menu untouched). Safe for any id, including unknown ones.
static func build_category_for(id: String) -> int:
	return int(BUILD_CATEGORY.get(id, -1))

static func _built_types(player: Dictionary) -> Array:
	var out: Array = []
	for b in player.get("buildings", []):
		if b is Dictionary and b.get("built", false):
			out.append(b.get("type", ""))
	return out

static func _has_any(types: Array, wanted: Array) -> bool:
	for t in wanted:
		if t in types:
			return true
	return false

static func _has_built_category(player: Dictionary, cats: Array) -> bool:
	for b in player.get("buildings", []):
		if not (b is Dictionary and b.get("built", false)):
			continue
		var cat: int = int(BuildingRegistry.lookup(b.get("type", "")).get("category", -1))
		if cat in cats:
			return true
	return false

static func is_complete(id: String, player: Dictionary, _world: Dictionary, day: int) -> bool:
	var built: Array = _built_types(player)
	match id:
		"found_hall":
			return _has_any(built, ["village_hall", "keep"])
		"feed_people":
			return _has_any(built, ["apple_orchard", "wheat_farm", "pig_farm", "dairy_farm", "hops_farm"]) \
				and "granary" in built
		"grow_village":
			return int(player.get("population", 0)) >= 20
		"survive_winter":
			return day >= 48
		"ready_for_war":
			return _has_built_category(player, [BuildingRegistry.Category.MILITARY, BuildingRegistry.Category.DEFENSE])
		"rule_to_100":
			return day >= 100
	return false

# Evaluate progress for the day. Mutates world["objectives_done"] (id->true). Returns
# {index, total, text, completed, newly_completed: [ {id,text} ]} for the view/notices.
static func evaluate(player: Dictionary, world: Dictionary, day: int) -> Dictionary:
	var done: Dictionary = world.get("objectives_done", {})
	var newly: Array = []
	for o in OBJECTIVES:
		var oid: String = o.get("id", "")
		if not done.has(oid) and is_complete(oid, player, world, day):
			done[oid] = true
			newly.append(o)
	world["objectives_done"] = done

	var idx: int = OBJECTIVES.size()
	for i in range(OBJECTIVES.size()):
		if not done.has(OBJECTIVES[i].get("id", "")):
			idx = i
			break
	var current_text: String = OBJECTIVES[idx].get("text", "") if idx < OBJECTIVES.size() \
		else "Your realm endures. Long may you reign."
	return {
		"index": idx,
		"total": OBJECTIVES.size(),
		"text": current_text,
		"completed": done.size(),
		"newly_completed": newly,
	}
