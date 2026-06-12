extends RefCounted
# GDD §7.5 — Shire Capital Buffs
# Manages capital upgrade progression, donation tracking, and server-wide buffs.
# Capital state lives in world["shires"][i]: capital_level, capital_donations, capital_buffs.

# Maximum capital level (GDD §1.2.2: multiple upgrade paths, reflects co-op win condition)
const MAX_LEVEL: int = 5

# Prestige multiplier granted per capital level (stacks with PrestigeSystem)
const PRESTIGE_MULT_PER_LEVEL: float = 0.1

# Resource costs to upgrade from level N to level N+1.
# Each upgrade is progressively more expensive (GDD §1.2.2: "requires massive resources")
const UPGRADE_COSTS: Array = [
	{},                                              # Level 0 → 1
	{"stone": 200, "wood": 100},                    # Level 1 → 2
	{"stone": 500, "wood": 200, "iron": 50},        # Level 2 → 3
	{"stone": 1000, "wood": 400, "iron": 150},      # Level 3 → 4
	{"stone": 2000, "wood": 800, "iron": 400, "gold": 500},  # Level 4 → 5
]

# Server-wide buffs granted at each capital level.
# Applied globally to all players in the shire (read via get_capital_buffs).
const LEVEL_BUFFS: Array = [
	{},                                              # Level 0: no buffs
	{"prestige_mult": 0.1},                         # Level 1
	{"prestige_mult": 0.2, "edict_tier_cap": 1},   # Level 2
	{"prestige_mult": 0.3, "edict_tier_cap": 2, "iron_mining_bonus": 0.15},  # Level 3 (Grand Forge)
	{"prestige_mult": 0.4, "edict_tier_cap": 3, "ai_warning_bonus": 2},      # Level 4 (Watchtower)
	{"prestige_mult": 0.5, "edict_tier_cap": 4, "border_radius_bonus": 0.2}, # Level 5 (Grand Surveyor)
]

# ── Donation ─────────────────────────────────────────────────────────────────

# Records a resource donation from a player to a shire capital.
# Does NOT deduct from player (caller must do that).
static func record_donation(player: Dictionary, shire: Dictionary, resource: String, amount: int) -> void:
	if not shire.has("capital_donations"):
		shire["capital_donations"] = {}
	var donations: Dictionary = shire["capital_donations"]
	var pid: String = str(player.get("id", 0))
	if not donations.has(pid):
		donations[pid] = {}
	donations[pid][resource] = donations[pid].get(resource, 0) + amount

# Returns total amount of a specific resource donated to a capital by all players.
static func get_total_donated(shire: Dictionary, resource: String) -> int:
	var total: int = 0
	for pid_donations in shire.get("capital_donations", {}).values():
		total += pid_donations.get(resource, 0)
	return total

# Returns donation totals for a specific player (all resources).
static func get_player_donations(shire: Dictionary, player_id: int) -> Dictionary:
	return shire.get("capital_donations", {}).get(str(player_id), {})

# ── Upgrade ──────────────────────────────────────────────────────────────────

# Returns {ok, reason} — whether the shire capital can be upgraded.
static func can_upgrade(shire: Dictionary, world: Dictionary) -> Dictionary:
	var level: int = shire.get("capital_level", 0)
	if level >= MAX_LEVEL:
		return {"ok": false, "reason": "Already at maximum level"}
	var cost: Dictionary = UPGRADE_COSTS[level]
	# Check that donations cover the upgrade cost
	for resource in cost:
		if get_total_donated(shire, resource) < cost[resource]:
			return {"ok": false, "reason": "Insufficient donations of %s (need %d)" % [resource, cost[resource]]}
	return {"ok": true, "reason": ""}

# Upgrades the capital level (donations already verified by can_upgrade).
# Resets donation tracking for the next tier. Returns new level.
static func upgrade(shire: Dictionary, world: Dictionary) -> int:
	var check: Dictionary = can_upgrade(shire, world)
	if not check["ok"]:
		return shire.get("capital_level", 0)
	shire["capital_level"] = shire.get("capital_level", 0) + 1
	shire["capital_donations"] = {}  # Consumed by upgrade
	return shire["capital_level"]

# ── Buffs ────────────────────────────────────────────────────────────────────

# Returns the server-wide buff dictionary for the current capital level.
static func get_capital_buffs(shire: Dictionary) -> Dictionary:
	var level: int = clampi(shire.get("capital_level", 0), 0, MAX_LEVEL)
	return LEVEL_BUFFS[level].duplicate()

# Returns the prestige multiplier bonus from a capital (cumulative from all levels).
static func get_prestige_multiplier(shire: Dictionary) -> float:
	return get_capital_buffs(shire).get("prestige_mult", 0.0)

# Returns the maximum edict tier the capital unlocks for players in this shire.
static func get_edict_tier_cap(shire: Dictionary) -> int:
	return get_capital_buffs(shire).get("edict_tier_cap", 0)

# Ensures a shire dict has all required capital fields initialized.
static func ensure_capital_fields(shire: Dictionary) -> void:
	if not shire.has("capital_level"):
		shire["capital_level"] = 0
	if not shire.has("capital_donations"):
		shire["capital_donations"] = {}
