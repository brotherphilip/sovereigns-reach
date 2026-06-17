extends RefCounted
# Derived feudal title. The player's standing is purely a function of how much they hold
# and develop — no caps or gates (expansion IS the progression). Climbing the ladder is
# the goal; the top title (King) is the win. Pure simulation; no Godot scene imports.

const CampaignMap = preload("res://simulation/strategic/CampaignMap.gd")

# Ordered low → high. `min_score` is the standing required to hold the title. Index = rank.
const TITLES: Array = [
	{"name": "Reeve",   "min_score": 0},
	{"name": "Bailiff", "min_score": 6},
	{"name": "Knight",  "min_score": 14},
	{"name": "Baron",   "min_score": 26},
	{"name": "Earl",    "min_score": 42},
	{"name": "Duke",    "min_score": 62},
	{"name": "King",    "min_score": 88},
]

static func king_index() -> int:
	return TITLES.size() - 1

# Standing score: each held village contributes (1 + its development); prestige adds a
# slow bonus so investing in your realm also advances your title.
static func domain_score(world: Dictionary, faction_id: int, prestige: float = 0.0) -> int:
	var score: int = 0
	for cid in CampaignMap.faction_city_ids(world, faction_id):
		var c: Dictionary = CampaignMap.city_by_id(world, cid)
		if c.is_empty():
			continue
		score += 1 + int(c.get("development", c.get("tier", 0)))
	score += int(prestige / 100.0)
	return score

static func title_index_for(score: int) -> int:
	var idx: int = 0
	for i in range(TITLES.size()):
		if score >= int(TITLES[i]["min_score"]):
			idx = i
	return idx

static func title_name(index: int) -> String:
	if index < 0 or index >= TITLES.size():
		return "Reeve"
	return String(TITLES[index]["name"])

# The player's current title index from live state (does not mutate world).
static func current_index(world: Dictionary, players: Array) -> int:
	var pfid: int = CampaignMap.player_faction_id(world)
	var prestige: float = 0.0
	if players.size() > 0 and players[0] is Dictionary:
		prestige = float(players[0].get("prestige", 0.0))
	return title_index_for(domain_score(world, pfid, prestige))

# Recompute the player's title; if it rose since the last check, store it on world and
# return the new index. Title never demotes. Returns -1 when there is no promotion.
static func check_promotion(world: Dictionary, players: Array) -> int:
	var new_idx: int = current_index(world, players)
	var cur: int = int(world.get("player_title_index", 0))
	if new_idx > cur:
		world["player_title_index"] = new_idx
		return new_idx
	world["player_title_index"] = maxi(cur, new_idx)
	return -1
