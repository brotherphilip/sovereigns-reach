extends RefCounted
# GDD §3.3 — Religion & Faith
# Two intertwined mechanics:
#   1. Coverage (ΔR): church/cathedral influence radius vs hovel count drives a
#      standing popularity bonus (0–MAX_RELIGION_DELTA), read by PopularityEngine
#      via player.religion_coverage.
#   2. Faith (the accumulating resource): active churches, cathedrals and praying
#      monks generate Faith each game-day up to a cap set by the holy buildings.
#      When Faith fills to BLESSING_THRESHOLD it is spent on a Blessing — a
#      popularity spike plus a window of divine fire protection. This gives Faith
#      real weight: a mid-game investment (tech + stone buildings + monks) that
#      pays out as stability and disaster resistance.
#
# All state lives in plain player dict fields (faith, faith_cap, blessing_until)
# so it serialises with the rest of GameState.

const BuildingRegistry = preload("res://simulation/buildings/BuildingRegistry.gd")

# ── Coverage (ΔR) ─────────────────────────────────────────────────────────────
const MAX_RELIGION_DELTA: float = 10.0
const TILES_PER_HOVEL: float = 4.0

# ── Faith economy ─────────────────────────────────────────────────────────────
const FAITH_PER_CHURCH_PER_DAY: float    = 3.0
const FAITH_PER_CATHEDRAL_PER_DAY: float = 8.0
const FAITH_PER_MONK_PER_DAY: float      = 2.0   # monks pray; gives the unit a role
const FAITH_CAP_PER_CHURCH: float        = 30.0
const FAITH_CAP_PER_CATHEDRAL: float     = 80.0

const BLESSING_THRESHOLD: float      = 40.0
const BLESSING_DURATION_TICKS: int   = 720    # 3 game-days (TICKS_PER_GAME_DAY * 3)
const BLESSING_FIRE_REDUCTION: float = 0.5    # halves fire ignition risk while active

# Returns the religion coverage ratio (0.0–1.0).
# Coverage = sum of church/cathedral influence / hovel count.
static func compute_religion_coverage(player: Dictionary) -> float:
	var coverage_sum: float = 0.0
	var hovel_count: int = 0
	for building in player.get("buildings", []):
		if not building is Dictionary or not building.get("is_active", true):
			continue
		var btype: String = building.get("type", "")
		if btype == "church" or btype == "cathedral":
			coverage_sum += float(building.get("coverage_radius", 0)) / TILES_PER_HOVEL
		elif btype == "hovel":
			hovel_count += 1
	if hovel_count == 0:
		return 0.0
	return clampf(coverage_sum / float(hovel_count), 0.0, 1.0)

# Raw ΔR popularity bonus for the given coverage.
static func coverage_to_popularity_delta(coverage: float) -> float:
	return coverage * MAX_RELIGION_DELTA

# Maximum Faith the player's holy buildings can hold.
static func faith_capacity(player: Dictionary) -> float:
	var cap: float = 0.0
	for building in player.get("buildings", []):
		if not building is Dictionary or not building.get("is_active", true):
			continue
		match building.get("type", ""):
			"church":    cap += FAITH_CAP_PER_CHURCH
			"cathedral": cap += FAITH_CAP_PER_CATHEDRAL
	return cap

# Faith generated this game-day (before capping). Scales with building staffing,
# living monks, and the congregation's coverage.
static func daily_faith_gain(player: Dictionary) -> float:
	var gain: float = 0.0
	for building in player.get("buildings", []):
		if not building is Dictionary or not building.get("is_active", true):
			continue
		var btype: String = building.get("type", "")
		if btype != "church" and btype != "cathedral":
			continue
		var slots: int = maxi(1, int(building.get("max_workers", 1)))
		var staffing: float = clampf(0.5 + 0.5 * float(building.get("workers", 0)) / float(slots), 0.5, 1.0)
		if btype == "church":
			gain += FAITH_PER_CHURCH_PER_DAY * staffing
		else:
			gain += FAITH_PER_CATHEDRAL_PER_DAY * staffing
	# Praying monks add flat Faith (gives the monk unit a purpose).
	for u in player.get("units", []):
		if u is Dictionary and u.get("is_alive", false) and u.get("type", "") == "monk":
			gain += FAITH_PER_MONK_PER_DAY
	# A faithless congregation generates little; coverage scales the yield.
	var coverage: float = compute_religion_coverage(player)
	return gain * clampf(0.25 + 0.75 * coverage, 0.0, 1.0)

# Per game-day Faith update. Accrues Faith (capped), and bestows a Blessing when
# it reaches the threshold. Returns {faith, faith_cap, blessing: bool, spent}.
static func tick_faith(player: Dictionary, tick: int) -> Dictionary:
	var cap: float = faith_capacity(player)
	var faith: float = minf(player.get("faith", 0.0) + daily_faith_gain(player), cap)
	var blessing: bool = false
	var spent: float = 0.0
	if cap >= BLESSING_THRESHOLD and faith >= BLESSING_THRESHOLD:
		faith -= BLESSING_THRESHOLD
		spent = BLESSING_THRESHOLD
		player["blessing_until"] = tick + BLESSING_DURATION_TICKS
		blessing = true
	player["faith"] = maxf(0.0, faith)
	player["faith_cap"] = cap
	return {"faith": player["faith"], "faith_cap": cap, "blessing": blessing, "spent": spent}

# True while a Blessing's divine fire protection is active.
static func is_blessing_active(player: Dictionary, tick: int) -> bool:
	return player.get("blessing_until", 0) > tick

# Called every tick: updates player.religion_coverage (the standing ΔR input).
# Returns the new coverage value.
static func tick(player: Dictionary) -> float:
	var coverage: float = compute_religion_coverage(player)
	player["religion_coverage"] = coverage
	return coverage
