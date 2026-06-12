extends RefCounted
# GDD §7 — Edict panel data extraction.
# Pure static functions: player dict + current_tick → card display data.
# Cooldown display in game-days.

const EdictSystem = preload("res://simulation/edicts/EdictSystem.gd")

const TICKS_PER_DAY: int = 240

# ── Data extraction ───────────────────────────────────────────────────────────

# Returns panel data: {active: Array, available: Array, locked: Array, edict_points: int}
static func get_panel_data(player: Dictionary, current_tick: int) -> Dictionary:
	var active:    Array = _get_active_cards(player, current_tick)
	var available: Array = _get_available_cards(player, current_tick)
	var locked:    Array = _get_locked_cards(player, current_tick)
	return {
		"active": active,
		"available": available,
		"locked": locked,
		"edict_points": player.get("edict_points", 0),
	}

# Returns only the active edict cards with time-remaining info.
static func get_active_cards(player: Dictionary, current_tick: int) -> Array:
	return _get_active_cards(player, current_tick)

# Returns remaining ticks for an active edict (0 for passive with no expiry).
static func get_remaining_ticks(player: Dictionary, edict_id: String, current_tick: int) -> int:
	for entry in player.get("active_edicts", []):
		if entry is Dictionary and entry.get("id") == edict_id:
			var expires_at: int = entry.get("expires_at", 0)
			if expires_at <= current_tick:
				return 0
			return expires_at - current_tick
	return 0

# Returns remaining cooldown ticks for an edict.
static func get_cooldown_remaining(player: Dictionary, edict_id: String, current_tick: int) -> int:
	var key: String = "edict_cooldown_" + edict_id
	var until: int = player.get(key, 0)
	return maxi(0, until - current_tick)

# Returns formatted "Xd Yh" label for a tick count.
static func format_ticks(ticks: int) -> String:
	if ticks <= 0:
		return "Ready"
	var days: int = ticks / TICKS_PER_DAY
	var rem: int  = ticks % TICKS_PER_DAY
	# Approximate remaining ticks as a percentage of the day
	if days > 0:
		return "%dd %d%%" % [days, (rem * 100) / TICKS_PER_DAY]
	return "%d%%" % [(rem * 100) / TICKS_PER_DAY]

# ── Internal ─────────────────────────────────────────────────────────────────

static func _get_active_cards(player: Dictionary, current_tick: int) -> Array:
	var result: Array = []
	for entry in player.get("active_edicts", []):
		if not entry is Dictionary:
			continue
		var edict_id: String = entry.get("id", "")
		var defn: Dictionary = EdictSystem.lookup(edict_id)
		if defn.is_empty():
			continue
		var remaining: int = get_remaining_ticks(player, edict_id, current_tick)
		result.append({
			"id": edict_id,
			"name": defn.get("name", edict_id),
			"remaining_ticks": remaining,
			"remaining_label": format_ticks(remaining),
			"modifiers": defn.get("modifiers", {}),
			"is_passive": defn.get("type", EdictSystem.EdictType.ACTIVE) == EdictSystem.EdictType.PASSIVE,
		})
	return result

static func _get_available_cards(player: Dictionary, current_tick: int) -> Array:
	var result: Array = []
	for edict_id in EdictSystem.EDICTS:
		if EdictSystem.is_active(player, edict_id):
			continue
		var check: Dictionary = EdictSystem.can_activate(player, edict_id, current_tick)
		if not check.get("ok", false):
			continue
		var defn: Dictionary = EdictSystem.lookup(edict_id)
		result.append({
			"id": edict_id,
			"name": defn.get("name", edict_id),
			"cost_points": defn.get("cost_points", 0),
			"description": defn.get("description", ""),
			"cooldown_label": "Ready",
		})
	return result

static func _get_locked_cards(player: Dictionary, current_tick: int) -> Array:
	var result: Array = []
	for edict_id in EdictSystem.EDICTS:
		if EdictSystem.is_active(player, edict_id):
			continue
		var check: Dictionary = EdictSystem.can_activate(player, edict_id, current_tick)
		if check.get("ok", false):
			continue
		var defn: Dictionary = EdictSystem.lookup(edict_id)
		var cooldown: int = get_cooldown_remaining(player, edict_id, current_tick)
		result.append({
			"id": edict_id,
			"name": defn.get("name", edict_id),
			"cost_points": defn.get("cost_points", 0),
			"reason": check.get("reason", ""),
			"cooldown_remaining": cooldown,
			"cooldown_label": format_ticks(cooldown),
		})
	return result
