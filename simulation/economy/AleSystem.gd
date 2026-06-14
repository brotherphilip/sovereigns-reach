extends RefCounted
# GDD §3.2 — Ale Distribution (ΔA)
# Manages hops→brewery→ale production chain, inn coverage, and ale consumption.
# PopularityEngine reads player.inn_coverage (0.0–1.0) set by this system.

# Ale consumed per inn per day tick (inn must have worker + active)
const ALE_PER_INN_PER_DAY: int = 1

# Returns the inn coverage ratio (0.0–1.0): what fraction of hovels are within inn AoE.
# Each staffed, active inn covers approximately 4 hovels.
static func compute_inn_coverage(player: Dictionary) -> float:
	var inn_count: int = 0
	var hovel_count: int = 0
	for building in player.get("buildings", []):
		if not building is Dictionary:
			continue
		var btype: String = building.get("type", "")
		if btype == "inn" and building.get("is_active", true) and building.get("workers", 0) > 0:
			inn_count += 1
		elif btype == "hovel":
			hovel_count += 1
	if hovel_count == 0:
		return 0.0
	return clampf(float(inn_count * 4) / float(hovel_count), 0.0, 1.0)

# Called every tick to update player.inn_coverage and consume ale at day boundaries.
# Returns dict with "ale_consumed", "ale_shortage" (both 0 if not day boundary).
static func tick(player: Dictionary, tick: int) -> Dictionary:
	# Coverage is recalculated every tick so PopularityEngine always has fresh value
	var coverage: float = compute_inn_coverage(player)
	player["inn_coverage"] = coverage

	if tick == 0 or tick % 240 != 0:
		return {}

	# Ale consumption: each active inn consumes 1 ale per day
	var inn_count: int = 0
	for building in player.get("buildings", []):
		if not building is Dictionary:
			continue
		if building.get("type", "") == "inn" and building.get("is_active", true) and building.get("workers", 0) > 0:
			inn_count += 1

	var ration: int = player.get("ale_ration", 1)
	# Higher ration = more ale consumed per inn per day (scaled 0.0–2.0)
	var ration_mult: float = float(ration) * 0.5  # 0=0.0, 1=0.5, 2=1.0, 3=1.5, 4=2.0
	var to_consume: int = roundi(float(inn_count) * float(ALE_PER_INN_PER_DAY) * ration_mult)

	if to_consume <= 0:
		return {"ale_consumed": 0, "ale_shortage": 0}

	var food: Dictionary = player.get("food", {})
	var ale_stock: int = food.get("ale", 0)
	var consumed: int = mini(ale_stock, to_consume)
	food["ale"] = ale_stock - consumed

	return {
		"ale_consumed": consumed,
		"ale_shortage": to_consume - consumed,
	}
