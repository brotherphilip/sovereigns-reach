extends RefCounted
# GDD §1.4.3 — Single-player milestone tracking.
# Each milestone is a one-time achievement that grants a prestige bonus and
# a notification. The milestones dict (GameState.milestones) is the persistent
# latch: once a key is set to true it is never unset.

const PRESTIGE_BONUS: float = 50.0

# Milestone definitions: id → {label, condition checked in check()}
# Paced across the whole 20-min (100-day) life: the first five land in the early
# game, the rest fill the mid/late session so the reward loop never goes quiet.
const DEFINITIONS: Dictionary = {
	# ── Early game ──
	"first_woodcutter": "Your first woodcutter is at work — the timber has begun to flow.",
	"first_farm":       "Your first farm is sown — your people's bread is secured.",
	"population_50":    "Fifty souls now live under your rule — your village is growing.",
	"first_edict":      "Your first decree is proclaimed — your word is now law.",
	"three_shires":     "Three lands answer to you now — a realm begins to take shape.",
	# ── Mid / late game (pace the long middle of the run) ──
	"first_watchtower": "Your first watchtower stands — your hall can weather an attack.",
	"town_of_ten":      "Ten buildings raised — your village has grown into a town.",
	"treasury_300":     "Your treasury holds 300 gold — your rule rests on firm coin.",
	"standing_army":    "Five men now bear arms for you — a standing guard is mustered.",
	"reign_day_50":     "Fifty days you have ruled — the realm holds steady.",
	"reign_day_75":     "Seventy-five days you have ruled — the enemy's pressure eases, and the realm still stands.",
}

# A standing army of this many living soldiers earns the standing_army milestone — a
# military reward signpost beyond the wall-or-unit siege-readiness check.
const STANDING_ARMY_SIZE: int = 5

# Returns Array[String] of milestone ids newly earned this call.
# Mutates milestones dict in-place (adds earned keys = true).
# Grants PRESTIGE_BONUS to player for each newly earned milestone.
static func check(player: Dictionary, _world: Dictionary, milestones: Dictionary, active_edicts: Array, day: int = 0) -> Array:
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

	if not milestones.has("three_shires"):
		if player.get("shire_ids", []).size() >= 3:
			milestones["three_shires"] = true
			earned.append("three_shires")

	# ── Mid / late game ──
	if not milestones.has("first_watchtower"):
		for b in player.get("buildings", []):
			if b is Dictionary and b.get("type", "") == "watchtower":
				milestones["first_watchtower"] = true
				earned.append("first_watchtower")
				break

	if not milestones.has("town_of_ten"):
		if player.get("buildings", []).size() >= 10:
			milestones["town_of_ten"] = true
			earned.append("town_of_ten")

	if not milestones.has("treasury_300"):
		if player.get("gold", 0) >= 300:
			milestones["treasury_300"] = true
			earned.append("treasury_300")

	if not milestones.has("standing_army"):
		var soldiers: int = 0
		for u in player.get("units", []):
			if u is Dictionary and u.get("is_alive", false):
				soldiers += 1
		if soldiers >= STANDING_ARMY_SIZE:
			milestones["standing_army"] = true
			earned.append("standing_army")

	if not milestones.has("reign_day_50"):
		if day >= 50:
			milestones["reign_day_50"] = true
			earned.append("reign_day_50")

	if not milestones.has("reign_day_75"):
		if day >= 75:
			milestones["reign_day_75"] = true
			earned.append("reign_day_75")

	if not earned.is_empty():
		var bonus: float = float(earned.size()) * PRESTIGE_BONUS
		player["prestige"] = player.get("prestige", 0.0) + bonus

	return earned

static func get_label(milestone_id: String) -> String:
	return DEFINITIONS.get(milestone_id, milestone_id)
