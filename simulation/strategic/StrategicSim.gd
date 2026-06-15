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
