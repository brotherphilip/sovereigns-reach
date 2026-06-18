extends RefCounted
# Orchestrator for the strategic / campaign layer. Called once per game-day from
# GameState.simulate_tick. Runs, for every living kingdom: daily economy → (AI
# only) brain decisions → army marches & battles, then resolves kingdom defeat.
#
# Kept separate from the sibling modules so it can preload all of them without
# creating a circular dependency. Pure simulation: returns a structured event
# list for the caller (GameState) to forward to EventBus — no EventBus import
# here, so it stays fully headless-testable.

const CampaignMap    = preload("res://simulation/strategic/CampaignMap.gd")
const KingdomEconomy = preload("res://simulation/strategic/KingdomEconomy.gd")
const CampaignSystem = preload("res://simulation/strategic/CampaignSystem.gd")
const KingdomAI      = preload("res://simulation/strategic/KingdomAI.gd")

# Advance the whole strategic layer one game-day. Returns Array of per-kingdom
# result dicts: {"faction_id", "events":[String], "battles":[Dictionary]}.
static func tick_day(world: Dictionary, players: Array, tick: int) -> Array:
	var results: Array = []
	if not CampaignMap.ensure_initialized(world, players):
		return results

	for kingdom in CampaignMap.kingdoms(world):
		if not (kingdom is Dictionary and kingdom.get("is_alive", false)):
			continue
		var events: Array = []
		var battles: Array = []

		# Order matters: collect income, then advance armies already on the march
		# (so a campaign takes at least a day and is observably "in motion"), then
		# let the brain invest / raise / launch fresh orders for tomorrow.
		events.append_array(KingdomEconomy.tick_day(world, kingdom, tick))
		# tick_armies returns assault result dicts; split them out for the caller.
		for entry in CampaignSystem.tick_armies(world, kingdom, players, tick):
			if entry is Dictionary:
				battles.append(entry)
			else:
				events.append(entry)
		events.append_array(KingdomAI.decide(world, kingdom, players, tick))

		results.append({
			"faction_id": kingdom.get("id", -1),
			"events": events,
			"battles": battles,
		})

	# Secessions: neglected, over-extended AI conquests revolt back to independence — so the
	# pool of capturable independents doesn't deplete late-game (iter155: 20→2) and the world
	# stays alive to expand into. Player holdings are EXEMPT (you actively govern; this also
	# keeps the verified King climb untouched). See _process_secessions.
	results.append_array(_process_secessions(world, tick))

	# Defeat resolution: a kingdom that holds no cities has fallen.
	for kingdom in CampaignMap.kingdoms(world):
		if not (kingdom is Dictionary and kingdom.get("is_alive", false)):
			continue
		if CampaignMap.faction_city_count(world, kingdom.get("id", -1)) == 0:
			kingdom["is_alive"] = false
			# Disband any armies that were still in the field.
			kingdom["armies"] = []
			results.append({
				"faction_id": kingdom.get("id", -1),
				"events": ["kingdom_defeated"],
				"battles": [],
			})

	return results

# A neglected (development 0), non-capital, frontier city held by an AI great house can revolt
# back to INDEPENDENT — replenishing the conquest pool and adding rebellion drama. Conservative:
# player-exempt, capitals/seat-exempt, only dev-0 frontier cities, and never strips a faction
# below 3 holdings. Deterministic per-tick RNG. Returns per-secession result dicts.
const SECESSION_CHANCE: float = 0.012   # per eligible city per day
static func _process_secessions(world: Dictionary, tick: int) -> Array:
	var out: Array = []
	var rng := RandomNumberGenerator.new()
	rng.seed = tick * 2654435761
	var seat: int = int(world.get("player_seat_city_id", -1))
	for c in CampaignMap.cities(world):
		if not c is Dictionary:
			continue
		var owner: int = CampaignMap.owner_of(c)
		if owner == CampaignMap.INDEPENDENT_FACTION_ID or owner == CampaignMap.PLAYER_FACTION_ID:
			continue
		if c.get("is_capital", false) or c.get("id", -1) == seat:
			continue
		if int(c.get("development", c.get("tier", 0))) > 0:
			continue
		if CampaignMap.faction_city_count(world, owner) <= 3:
			continue
		# Frontier only: it must border a city the owner doesn't hold.
		var frontier: bool = false
		for nid in CampaignMap.neighbor_ids(c):
			var n: Dictionary = CampaignMap.city_by_id(world, nid)
			if not n.is_empty() and CampaignMap.owner_of(n) != owner:
				frontier = true
				break
		if not frontier:
			continue
		if rng.randf() < SECESSION_CHANCE:
			CampaignMap.set_owner(world, c.get("id", -1), CampaignMap.INDEPENDENT_FACTION_ID)
			c["garrison"] = maxi(4, int(c.get("garrison", 0)) / 2)
			c["unrest"] = 0.0
			var dk: Dictionary = CampaignMap.kingdom_by_id(world, owner)
			if not dk.is_empty():
				dk["cities_lost"] = dk.get("cities_lost", 0) + 1
			out.append({"faction_id": owner, "events": ["city_seceded"], "battles": []})
	return out
