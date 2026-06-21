extends RefCounted
# GDD §2.1 / §2.2 — Macro world-map view data extraction.
# Pure static functions: world/players/ai_factions dicts → render data arrays.
# The actual rendering (CanvasLayer, sprites, labels) reads from these dicts.
# No Node inheritance; no scene tree dependency.

# Shire owner color palette (player_id → color string; -1 = neutral/AI)
const SHIRE_COLORS: Array = [
	"#4fc3f7",  # player 0 — light blue
	"#81c784",  # player 1 — light green
	"#ffb74d",  # player 2 — amber
	"#e57373",  # player 3 — soft red
	"#ce93d8",  # player 4 — lavender
	"#4db6ac",  # player 5 — teal
	"#fff176",  # player 6 — yellow
	"#ff8a65",  # player 7 — coral
]

const AI_COLORS: Dictionary = {
	"bandit_king":      "#8d6e63",  # brown
	"merchant_prince":  "#ffd54f",  # gold
	"ironhand":         "#90a4ae",  # steel gray
	"ashen_barony":     "#7e57c2",  # purple
}

const NEUTRAL_COLOR: String = "#455a64"  # dark slate

# ── Shire data ────────────────────────────────────────────────────────────────

# Returns an array of shire render items:
#   {id, owner_id, capital_level, color, name, capital_x, capital_y}
static func get_shire_render_list(world: Dictionary, players: Array,
		ai_factions: Array) -> Array:
	var result: Array = []
	for shire in world.get("shires", []):
		if not shire is Dictionary:
			continue
		var owner: int = shire.get("owner_id", -1)
		result.append({
			"id": shire.get("id", -1),
			"owner_id": owner,
			"capital_level": shire.get("capital_level", 0),
			"color": get_shire_color(owner, players, ai_factions, shire.get("owner_is_player", false)),
			"name": shire.get("name", "Shire"),
			"capital_x": shire.get("capital_x", 0),
			"capital_y": shire.get("capital_y", 0),
		})
	return result

# Returns the hex color string for a shire owned by `owner_id`.
static func get_shire_color(owner_id: int, players: Array, ai_factions: Array,
		owner_is_player: bool = false) -> String:
	if owner_id < 0:
		return NEUTRAL_COLOR
	if owner_is_player:
		return SHIRE_COLORS[owner_id] if owner_id < SHIRE_COLORS.size() else NEUTRAL_COLOR
	for fac in ai_factions:
		if fac is Dictionary and fac.get("id", -1) == owner_id:
			return AI_COLORS.get(fac.get("archetype", ""), NEUTRAL_COLOR)
	return NEUTRAL_COLOR

# ── Army banners ──────────────────────────────────────────────────────────────

# Returns player army banner data for the macro map:
#   {player_id, color, pos_x, pos_y, unit_count, army_strength}
static func get_player_army_banners(players: Array) -> Array:
	var result: Array = []
	for player in players:
		if not (player is Dictionary and player.get("is_alive", false)):
			continue
		var units: Array = player.get("units", [])
		var alive_count: int = 0
		for u in units:
			if u is Dictionary and u.get("is_alive", false):
				alive_count += 1
		if alive_count == 0:
			continue
		var pid: int = player.get("id", 0)
		result.append({
			"player_id": pid,
			"color": SHIRE_COLORS[pid] if pid < SHIRE_COLORS.size() else NEUTRAL_COLOR,
			"pos_x": player.get("keep_x", 0),
			"pos_y": player.get("keep_y", 0),
			"unit_count": alive_count,
			"army_strength": player.get("military_strength", 0),
		})
	return result

# Returns AI faction army data:
#   {faction_id, archetype, color, pos_x, pos_y, unit_count, threat_level}
static func get_ai_army_banners(ai_factions: Array) -> Array:
	var result: Array = []
	for fac in ai_factions:
		if not (fac is Dictionary and fac.get("is_alive", false)):
			continue
		var units: Array = fac.get("units", [])
		var alive_count: int = 0
		for u in units:
			if u is Dictionary and u.get("is_alive", false):
				alive_count += 1
		var arch: String = fac.get("archetype", "")
		result.append({
			"faction_id": fac.get("id", -1),
			"archetype": arch,
			"color": AI_COLORS.get(arch, NEUTRAL_COLOR),
			"pos_x": fac.get("capital_x", 0),
			"pos_y": fac.get("capital_y", 0),
			"unit_count": alive_count,
			"threat_level": fac.get("threat_level", 0.0),
		})
	return result

# ── Siege tent display ────────────────────────────────────────────────────────

# Returns siege assembly data for all AI factions currently assembling:
#   {faction_id, target_player_id, target_x, target_y, progress (0.0–1.0), eta_label}
static func get_siege_tent_data(ai_factions: Array) -> Array:
	var result: Array = []
	for fac in ai_factions:
		if not (fac is Dictionary and not fac.get("siege_assembly", {}).is_empty()):
			continue
		var asm: Dictionary = fac["siege_assembly"]
		var elapsed: int    = asm.get("ticks_elapsed", 0)
		var total: int      = preload("res://simulation/ai/AIFaction.gd").SIEGE_ASSEMBLY_TICKS
		var progress: float = clampf(float(elapsed) / float(total), 0.0, 1.0)
		var remaining: int  = maxi(0, total - elapsed)
		var days_left: int  = remaining / 240
		result.append({
			"faction_id": fac.get("id", -1),
			"target_player_id": asm.get("target_player_id", -1),
			"target_x": asm.get("target_x", 0),
			"target_y": asm.get("target_y", 0),
			"capital_x": fac.get("capital_x", 0),
			"capital_y": fac.get("capital_y", 0),
			"progress": progress,
			"eta_label": "%d days" % days_left,
		})
	return result

