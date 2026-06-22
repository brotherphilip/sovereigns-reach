extends RefCounted
# GDD §4 — Tech Tree panel data extraction.
# Pure static functions: player dict → panel display data.
# Issues RESEARCH_TECH commands when the player clicks Research.

const TechTree = preload("res://simulation/tech/TechTree.gd")

# Status string constants used by the panel
const STATUS_RESEARCHED  = "researched"
const STATUS_AVAILABLE   = "available"
const STATUS_LOCKED      = "locked"
const STATUS_UNAFFORDABLE = "unaffordable"

# ── Data extraction ───────────────────────────────────────────────────────────

# Returns panel data dict: {branches: Dict[branch_int → Array[item]], prestige: int}
# Each item: {id, name, status, cost_prestige, requires, unlocks_buildings, modifiers}
static func get_panel_data(player: Dictionary) -> Dictionary:
	return {
		"branches": _get_all_branches(player),
		"prestige": int(player.get("prestige", 0)),
		"unlocked_count": player.get("tech_unlocks", []).size(),
	}

# Returns the list of researchable techs as display items.
static func get_researchable_items(player: Dictionary) -> Array:
	var result: Array = []
	for tech_id in TechTree.get_researchable(player):
		var defn: Dictionary = TechTree.lookup(tech_id)
		result.append({
			"id": tech_id,
			"name": defn.get("name", tech_id),
			"cost_prestige": defn.get("cost_prestige", 0),
			"status": STATUS_AVAILABLE,
		})
	return result

# Returns the tech status for a single tech_id given player state.
static func get_tech_status(player: Dictionary, tech_id: String) -> String:
	if TechTree.is_unlocked(player, tech_id):
		return STATUS_RESEARCHED
	var check: Dictionary = TechTree.can_research(player, tech_id)
	if check.get("ok", false):
		return STATUS_AVAILABLE
	# Distinguish "can't afford" from "locked by prereqs"
	var defn: Dictionary = TechTree.lookup(tech_id)
	if player.get("prestige", 0) < defn.get("cost_prestige", 0):
		return STATUS_UNAFFORDABLE
	return STATUS_LOCKED

# Returns a plain-language benefit summary for a tech definition dict.
# A SHORT one-line payoff summary for the always-visible tech row (the full breakdown stays in the
# Research-button tooltip). Prefers what it UNLOCKS — what a planning player most wants — else its
# headline modifier. So the tech list reads as "what does this get me", not bare names + costs.
static func get_tech_summary(defn: Dictionary) -> String:
	var ub: Array = defn.get("unlocks_buildings", [])
	if not ub.is_empty():
		var names: Array = []
		for u in ub:
			names.append(String(u).replace("_", " ").capitalize())
		return "Unlocks " + ", ".join(names)
	var m: Dictionary = defn.get("modifiers", {})
	for key in m:
		var val = m[key]
		var dk: String = key.replace("_", " ").capitalize()
		if (val is float or val is int) and float(val) < 5.0:
			return "%s %+.0f%%" % [dk, float(val) * 100.0]
		return "%s: %s" % [dk, str(val)]
	return String(defn.get("description", ""))

static func get_tech_hint_text(defn: Dictionary) -> String:
	var lines: Array = []
	var unlocks: Array = defn.get("unlocks_buildings", [])
	if not unlocks.is_empty():
		lines.append("Unlocks: " + ", ".join(unlocks))
	var mods: Dictionary = defn.get("modifiers", {})
	for key in mods:
		var val = mods[key]
		var display_key: String = key.replace("_", " ").capitalize()
		if val is float or val is int:
			lines.append("%s: %+.0f%%" % [display_key, float(val) * 100.0] if float(val) < 5.0 else "%s: +%s" % [display_key, str(val)])
		else:
			lines.append("%s: %s" % [display_key, str(val)])
	var req: Array = defn.get("requires", [])
	if not req.is_empty():
		lines.append("Requires: " + ", ".join(req))
	if lines.is_empty():
		return defn.get("description", "No details available.")
	return "\n".join(lines)

# ── Internal ──────────────────────────────────────────────────────────────────

static func _get_all_branches(player: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for branch_val in TechTree.Branch.values():
		var branch_techs: Array = TechTree.get_branch(branch_val)
		var items: Array = []
		for tech_id in branch_techs:
			var defn: Dictionary = TechTree.lookup(tech_id)
			items.append({
				"id": tech_id,
				"name": defn.get("name", tech_id),
				"status": get_tech_status(player, tech_id),
				"cost_prestige": defn.get("cost_prestige", 0),
				"requires": defn.get("requires", []),
				"unlocks_buildings": defn.get("unlocks_buildings", []),
				"modifiers": defn.get("modifiers", {}),
			})
		result[branch_val] = items
	return result
