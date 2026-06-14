extends RefCounted
# GDD §1.4.3 — Single-player milestone tracking.
# Each milestone is a one-time achievement that grants a prestige bonus and
# a notification. The milestones dict (GameState.milestones) is the persistent
# latch: once a key is set to true it is never unset.

const PRESTIGE_BONUS: float = 50.0

# Milestone definitions: id → {label, condition checked in check()}
const DEFINITIONS: Dictionary = {
	"first_woodcutter": "Felled the first tree — your lumber trade begins.",
	"first_farm":       "Sowed the first field — your people will not starve.",
	"population_50":    "50 souls call your realm home.",
	"first_edict":      "Your will is law — the first royal edict proclaimed.",
	"three_shires":     "Three shires fly your banner — a kingdom takes shape.",
}

# Returns Array[String] of milestone ids newly earned this call.
# Mutates milestones dict in-place (adds earned keys = true).
# Grants PRESTIGE_BONUS to player for each newly earned milestone.
static func check(player: Dictionary, _world: Dictionary, milestones: Dictionary, active_edicts: Array) -> Array:
	var earned: Array = []

	if not milestones.has("first_woodcutter"):
		for b in player.get("buildings", []):
			if b is Dictionary and b.get("type", "") == "woodcutter_camp":
				milestones["first_woodcutter"] = true
				earned.append("first_woodcutter")
				break

	if not milestones.has("first_farm"):
		for b in player.get("buildings", []):
			if b is Dictionary and b.get("type", "") in ["wheat_farm", "pig_farm", "dairy_farm", "hops_farm"]:
				milestones["first_farm"] = true
				earned.append("first_farm")
				break

	if not milestones.has("population_50"):
		if player.get("population", 0) >= 50:
			milestones["population_50"] = true
			earned.append("population_50")

	if not milestones.has("first_edict"):
		for e in active_edicts:
			if e is Dictionary and e.has("id"):
				milestones["first_edict"] = true
				earned.append("first_edict")
				break

	if not earned.is_empty():
		var bonus: float = float(earned.size()) * PRESTIGE_BONUS
		player["prestige"] = player.get("prestige", 0.0) + bonus

	return earned

static func get_label(milestone_id: String) -> String:
	return DEFINITIONS.get(milestone_id, milestone_id)
